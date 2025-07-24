// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import "@uniswap/v3-core/contracts/libraries/LowGasSafeMath.sol";
import "@uniswap/v3-core/contracts/libraries/LiquidityMath.sol";
import "@uniswap/v3-core/contracts/libraries/SafeCast.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "./interfaces/IAlgebraPool.sol";
import "./lib/TickBitmapAlgebra.sol";
import "./lib/AlgebraPriceMovementMath.sol";
import "../IUniV3likeQuoterCore.sol";

/// @title Algebra Integral Quoter Core
/// @notice Core logic for quoting swaps against Algebra Integral pools using native Algebra math
contract AlgebraIntegralQuoterCore {
    using LowGasSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;

    /// @notice Returns the amount0 delta and amount1 delta for a given swap
    /// @param poolAddress The address of the pool to quote against
    /// @param zeroForOne Whether the amount in is token0 or token1
    /// @param amountSpecified The amount of the swap, which implicitly configures the swap as exact input or exact output
    /// @param sqrtPriceLimitX96 The Q64.96 sqrt price limit. If zero for one, the price cannot be less than this
    /// value after the swap. If one for zero, the price cannot be greater than this value after the swap
    /// @return amount0 The amount0 delta of the swap
    /// @return amount1 The amount1 delta of the swap
    function quote(address poolAddress, bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96)
        public
        view
        virtual
        returns (int256 amount0, int256 amount1)
    {
        require(amountSpecified != 0, "amountSpecified cannot be zero");
        bool exactInput = amountSpecified > 0;
        (int24 tickSpacing, uint16 fee, SwapState memory state) =
            getInitState(poolAddress, zeroForOne, amountSpecified, sqrtPriceLimitX96);

        // Continue swapping as long as we haven't used the entire input/output and haven't reached the price limit
        while (state.amountSpecifiedRemaining != 0 && state.sqrtPriceX96 != sqrtPriceLimitX96) {
            StepComputations memory step;
            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            (step.tickNext, step.initialized, step.sqrtPriceNextX96) =
                nextInitializedTickAndPrice(poolAddress, state.tick, tickSpacing, zeroForOne);

            (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = AlgebraPriceMovementMath
                .movePriceTowardsTarget(
                zeroForOne,
                state.sqrtPriceX96,
                getSqrtRatioTargetX96(zeroForOne, step.sqrtPriceNextX96, sqrtPriceLimitX96),
                state.liquidity,
                state.amountSpecifiedRemaining,
                uint24(fee)
            );

            if (exactInput) {
                state.amountSpecifiedRemaining -= (step.amountIn + step.feeAmount).toInt256();
                state.amountCalculated = state.amountCalculated.sub(step.amountOut.toInt256());
            } else {
                state.amountSpecifiedRemaining += step.amountOut.toInt256();
                state.amountCalculated = state.amountCalculated.add((step.amountIn + step.feeAmount).toInt256());
            }

            // Shift tick if we reached the next price
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                // If the tick is initialized, run the tick transition
                if (step.initialized) {
                    (, int128 liquidityNet,,,,,,) = getTicks(poolAddress, step.tickNext);
                    // If we're moving leftward, we interpret liquidityNet as the opposite sign
                    // Safe because liquidityNet cannot be type(int128).min
                    if (zeroForOne) {
                        liquidityNet = -liquidityNet;
                    }
                    state.liquidity = LiquidityMath.addDelta(state.liquidity, liquidityNet);
                }
                state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                // Recompute unless we're on a lower tick boundary (i.e. already transitioned ticks), and haven't moved
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }

        (amount0, amount1) = zeroForOne == exactInput
            ? (amountSpecified - state.amountSpecifiedRemaining, state.amountCalculated)
            : (state.amountCalculated, amountSpecified - state.amountSpecifiedRemaining);
    }

    /// @notice Get the initial state for a swap
    /// @dev Optimized to fetch multiple pool state variables in a single call
    function getInitState(address poolAddress, bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96)
        internal
        view
        returns (int24 ts, uint16 fee, SwapState memory state)
    {
        // Get all needed data in fewer calls to reduce gas
        uint160 price;
        int24 tick;
        uint8 pluginConfig;
        uint16 communityFee;
        (price, tick, fee, pluginConfig, communityFee,) = IAlgebraPool(poolAddress).globalState();

        checkSqrtPriceLimitWithinAllowed(zeroForOne, sqrtPriceLimitX96, price);
        ts = IAlgebraPool(poolAddress).tickSpacing();

        state = SwapState({
            amountSpecifiedRemaining: amountSpecified,
            liquidity: IAlgebraPool(poolAddress).liquidity(),
            sqrtPriceX96: price,
            amountCalculated: 0,
            tick: tick
        });
    }

    /// @notice Check that the sqrt price limit is within allowed bounds
    function checkSqrtPriceLimitWithinAllowed(bool zeroForOne, uint160 sqrtPriceLimit, uint160 startPrice)
        internal
        pure
    {
        bool withinAllowed = zeroForOne
            ? sqrtPriceLimit < startPrice && sqrtPriceLimit > TickMath.MIN_SQRT_RATIO
            : sqrtPriceLimit > startPrice && sqrtPriceLimit < TickMath.MAX_SQRT_RATIO;
        require(withinAllowed, "sqrtPriceLimit out of bounds");
    }

    /// @notice Get the next initialized tick and its sqrt price
    function nextInitializedTickAndPrice(address pool, int24 tick, int24 tickSpacing, bool zeroForOne)
        internal
        view
        returns (int24 tickNext, bool initialized, uint160 sqrtPriceNextX96)
    {
        (tickNext, initialized) = nextInitializedTickWithinOneWord(pool, tick, tickSpacing, zeroForOne);
        // Ensure that we do not overshoot the min/max tick, as the tick bitmap is not aware of these bounds
        if (tickNext < TickMath.MIN_TICK) {
            tickNext = TickMath.MIN_TICK;
        } else if (tickNext > TickMath.MAX_TICK) {
            tickNext = TickMath.MAX_TICK;
        }
        // Get the price for the next tick
        sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(tickNext);
    }

    /// @notice Get the sqrt ratio target for the swap
    function getSqrtRatioTargetX96(bool zeroForOne, uint160 sqrtPriceNextX96, uint160 sqrtPriceLimitX96)
        internal
        pure
        returns (uint160)
    {
        return (zeroForOne ? sqrtPriceNextX96 < sqrtPriceLimitX96 : sqrtPriceNextX96 > sqrtPriceLimitX96)
            ? sqrtPriceLimitX96
            : sqrtPriceNextX96;
    }

    /// @notice Get the next initialized tick within one word from the tick bitmap
    function nextInitializedTickWithinOneWord(address poolAddress, int24 tick, int24 tickSpacing, bool zeroForOne)
        internal
        view
        returns (int24 next, bool initialized)
    {
        return TickBitmap.nextInitializedTickWithinOneWord(poolAddress, tick, tickSpacing, zeroForOne);
    }

    /// @notice Get tick info from the pool
    function getTicks(address pool, int24 tick)
        internal
        view
        returns (
            uint128 liquidityTotal,
            int128 liquidityDelta,
            uint256 outerFeeGrowth0Token,
            uint256 outerFeeGrowth1Token,
            int56 outerTickCumulative,
            uint160 outerSecondsPerLiquidity,
            uint32 outerSecondsSpent,
            bool initialized
        )
    {
        return IAlgebraPool(pool).ticks(tick);
    }
}

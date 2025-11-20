// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@uniswap/v3-core/contracts/libraries/LowGasSafeMath.sol";
import "@uniswap/v3-core/contracts/libraries/SafeCast.sol";
import "./AlgebraConstants.sol";
import "./AlgebraTokenDeltaMath.sol";

/// @title Computes the result of price movement
/// @notice Contains methods for computing the result of price movement within a single tick price range.
library AlgebraPriceMovementMath {
    using LowGasSafeMath for uint256;
    using SafeCast for uint256;

    /// @notice Gets the next sqrt price given an input amount of token0 or token1
    function getNewPriceAfterInput(uint160 price, uint128 liquidity, uint256 input, bool zeroToOne)
        internal
        pure
        returns (uint160 resultPrice)
    {
        return getNewPrice(price, liquidity, input, zeroToOne, true);
    }

    /// @notice Gets the next sqrt price given an output amount of token0 or token1
    function getNewPriceAfterOutput(uint160 price, uint128 liquidity, uint256 output, bool zeroToOne)
        internal
        pure
        returns (uint160 resultPrice)
    {
        return getNewPrice(price, liquidity, output, zeroToOne, false);
    }

    function getNewPrice(uint160 price, uint128 liquidity, uint256 amount, bool zeroToOne, bool fromInput)
        internal
        pure
        returns (uint160 resultPrice)
    {
        require(price != 0, "Price cannot be zero");
        require(liquidity != 0, "Liquidity cannot be zero");
        if (amount == 0) return price;

        if (zeroToOne == fromInput) {
            // rounding up or down
            uint256 liquidityShifted = uint256(liquidity) << AlgebraConstants.RESOLUTION;

            if (fromInput) {
                uint256 product;
                if ((product = amount * price) / amount == price) {
                    uint256 denominator = liquidityShifted + product;
                    if (denominator >= liquidityShifted) {
                        return uint160(FullMath.mulDivRoundingUp(liquidityShifted, price, denominator));
                    }
                }

                return uint160(divRoundingUp(liquidityShifted, (liquidityShifted / price).add(amount)));
            } else {
                uint256 product;
                require((product = amount * price) / amount == price, "Product overflow");
                require(liquidityShifted > product, "Denominator underflow");
                return FullMath.mulDivRoundingUp(liquidityShifted, price, liquidityShifted - product).toUint160();
            }
        } else {
            if (fromInput) {
                return uint256(price).add(
                    amount <= type(uint160).max
                        ? (amount << AlgebraConstants.RESOLUTION) / liquidity
                        : FullMath.mulDiv(amount, AlgebraConstants.Q96, liquidity)
                ).toUint160();
            } else {
                uint256 quotient = amount <= type(uint160).max
                    ? divRoundingUp(amount << AlgebraConstants.RESOLUTION, liquidity)
                    : FullMath.mulDivRoundingUp(amount, AlgebraConstants.Q96, liquidity);

                require(price > quotient, "Price - quotient underflow");
                return uint160(price - quotient);
            }
        }
    }

    // Helper function to replace unsafeDivRoundingUp
    function divRoundingUp(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y > 0, "Division by zero");
        z = x / y;
        if (x % y > 0) z++;
    }

    function getInputTokenDelta01(uint160 to, uint160 from, uint128 liquidity) internal pure returns (uint256) {
        return AlgebraTokenDeltaMath.getToken0Delta(to, from, liquidity, true);
    }

    function getInputTokenDelta10(uint160 to, uint160 from, uint128 liquidity) internal pure returns (uint256) {
        return AlgebraTokenDeltaMath.getToken1Delta(from, to, liquidity, true);
    }

    function getOutputTokenDelta01(uint160 to, uint160 from, uint128 liquidity) internal pure returns (uint256) {
        return AlgebraTokenDeltaMath.getToken1Delta(to, from, liquidity, false);
    }

    function getOutputTokenDelta10(uint160 to, uint160 from, uint128 liquidity) internal pure returns (uint256) {
        return AlgebraTokenDeltaMath.getToken0Delta(from, to, liquidity, false);
    }

    /// @notice Computes the result of swapping some amount in, or amount out, given the parameters of the swap
    /// @dev The fee, plus the amount in, will never exceed the amount remaining if the swap's `amountSpecified` is positive
    /// @param zeroToOne The direction of price movement
    /// @param currentPrice The current Q64.96 sqrt price of the pool
    /// @param targetPrice The Q64.96 sqrt price that cannot be exceeded, from which the direction of the swap is inferred
    /// @param liquidity The usable liquidity
    /// @param amountAvailable How much input or output amount is remaining to be swapped in/out
    /// @param fee The fee taken from the input amount, expressed in hundredths of a bip
    /// @return resultPrice The Q64.96 sqrt price after swapping the amount in/out, not to exceed the price target
    /// @return input The amount to be swapped in, of either token0 or token1, based on the direction of the swap
    /// @return output The amount to be received, of either token0 or token1, based on the direction of the swap
    /// @return feeAmount The amount of input that will be taken as a fee
    function movePriceTowardsTarget(
        bool zeroToOne,
        uint160 currentPrice,
        uint160 targetPrice,
        uint128 liquidity,
        int256 amountAvailable,
        uint24 fee
    ) internal pure returns (uint160 resultPrice, uint256 input, uint256 output, uint256 feeAmount) {
        function(uint160, uint160, uint128) pure returns (uint256) getInputTokenAmount =
            zeroToOne ? getInputTokenDelta01 : getInputTokenDelta10;

        if (amountAvailable >= 0) {
            // exactIn or not
            uint256 amountAvailableAfterFee = FullMath.mulDiv(
                uint256(amountAvailable), AlgebraConstants.FEE_DENOMINATOR - fee, AlgebraConstants.FEE_DENOMINATOR
            );
            input = getInputTokenAmount(targetPrice, currentPrice, liquidity);
            if (amountAvailableAfterFee >= input) {
                resultPrice = targetPrice;
                feeAmount = FullMath.mulDivRoundingUp(input, fee, AlgebraConstants.FEE_DENOMINATOR - fee);
            } else {
                resultPrice = getNewPriceAfterInput(currentPrice, liquidity, amountAvailableAfterFee, zeroToOne);
                require(targetPrice != resultPrice, "Target price reached unexpectedly");

                input = getInputTokenAmount(resultPrice, currentPrice, liquidity);
                // we didn't reach the target, so take the remainder of the maximum input as fee
                feeAmount = uint256(amountAvailable) - input;
            }

            output = (zeroToOne ? getOutputTokenDelta01 : getOutputTokenDelta10)(resultPrice, currentPrice, liquidity);
        } else {
            function(uint160, uint160, uint128) pure returns (uint256) getOutputTokenAmount =
                zeroToOne ? getOutputTokenDelta01 : getOutputTokenDelta10;

            output = getOutputTokenAmount(targetPrice, currentPrice, liquidity);
            amountAvailable = -amountAvailable;
            require(amountAvailable >= 0, "Invalid amount required");

            if (uint256(amountAvailable) >= output) {
                resultPrice = targetPrice;
            } else {
                resultPrice = getNewPriceAfterOutput(currentPrice, liquidity, uint256(amountAvailable), zeroToOne);

                // should be always true if the price is in the allowed range
                if (targetPrice != resultPrice) output = getOutputTokenAmount(resultPrice, currentPrice, liquidity);

                // cap the output amount to not exceed the remaining output amount
                if (output > uint256(amountAvailable)) output = uint256(amountAvailable);
            }

            input = getInputTokenAmount(resultPrice, currentPrice, liquidity);
            feeAmount = FullMath.mulDivRoundingUp(input, fee, AlgebraConstants.FEE_DENOMINATOR - fee);
        }
    }
}

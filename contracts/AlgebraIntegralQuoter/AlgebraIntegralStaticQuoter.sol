// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {LowGasSafeMath as UniV3LowGasSafeMath} from "@uniswap/v3-core/contracts/libraries/LowGasSafeMath.sol";
import {SafeCast as UniV3SafeCast} from "@uniswap/v3-core/contracts/libraries/SafeCast.sol";

import "./interfaces/IAlgebraStaticQuoter.sol";
import "./interfaces/IAlgebraFactory.sol";
import "./lib/PathNoFee.sol";
import "./AlgebraIntegralQuoterCore.sol";

/// @title Algebra Integral Static Quoter
/// @notice Provides quotes for swaps against Algebra Integral pools using native Algebra math
/// @dev This quoter is gas-optimized for on-chain usage and provides mathematically identical
/// results to the official Algebra QuoterV2 by using the same PriceMovementMath library
contract AlgebraIntegralStaticQuoter is AlgebraIntegralQuoterCore {
    using UniV3LowGasSafeMath for uint256;
    using UniV3LowGasSafeMath for int256;
    using UniV3SafeCast for uint256;
    using UniV3SafeCast for int256;
    using PathNoFee for bytes;

    /// @dev The Algebra factory contract
    address immutable factory;

    /// @dev Array of tick spacing deployers for finding the most liquid pool
    address[] public tickSpacingDeployers;

    /// @param _factory The address of the Algebra factory
    /// @param _tickSpacingDeployers The addresses of tick spacing deployers
    constructor(address _factory, address[] memory _tickSpacingDeployers) {
        factory = _factory;
        tickSpacingDeployers = _tickSpacingDeployers;
    }

    /// @notice Finds the most liquid pool for a token pair across all deployers
    /// @param tokenA The first token of the pair
    /// @param tokenB The second token of the pair
    /// @return The address of the most liquid pool, or address(0) if none found
    function getPool(address tokenA, address tokenB) public view returns (address) {
        address[] memory foundPools = new address[](1 + tickSpacingDeployers.length);

        // Position 0: Regular pool
        foundPools[0] = IAlgebraFactory(factory).poolByPair(tokenA, tokenB);

        // Positions 1+: Custom pools for each tick spacing deployer
        for (uint256 i = 0; i < tickSpacingDeployers.length; i++) {
            foundPools[i + 1] = IAlgebraFactory(factory).customPoolByPair(tickSpacingDeployers[i], tokenA, tokenB);
        }

        // Find the most liquid pool among all non-zero addresses
        address bestPool = address(0);
        uint128 highestLiquidity = 0;

        for (uint256 i = 0; i < foundPools.length; i++) {
            if (foundPools[i] != address(0)) {
                uint128 liq = IAlgebraPool(foundPools[i]).liquidity();
                if (liq > highestLiquidity) {
                    highestLiquidity = liq;
                    bestPool = foundPools[i];
                }
            }
        }

        return bestPool;
    }

    /// @notice Returns the amount out received for a given exact input swap without executing the swap
    /// @param params The parameters necessary for the swap, encoded as QuoteExactInputSingleParams
    /// @return amountOut The amount of the output token that would be received
    function quoteExactInputSingle(QuoteExactInputSingleParams memory params) public view returns (uint256 amountOut) {
        bool zeroForOne = params.tokenIn < params.tokenOut;
        address pool = getPool(params.tokenIn, params.tokenOut);
        require(pool != address(0), "Pool not found");

        (int256 amount0, int256 amount1) = quote(
            pool,
            zeroForOne,
            params.amountIn.toInt256(),
            params.sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : params.sqrtPriceLimitX96
        );

        return zeroForOne ? uint256(-amount1) : uint256(-amount0);
    }

    /// @notice Returns the amount out received for a given exact input multi-hop swap without executing the swap
    /// @param path The path of the swap, i.e. each token pair encoded as (token0, token1)
    /// @param amountIn The amount of the first token to swap
    /// @return amountOut The amount of the last token that would be received
    function quoteExactInput(bytes memory path, uint256 amountIn) public view returns (uint256 amountOut) {
        while (true) {
            (address tokenIn, address tokenOut) = path.decodeFirstPool();

            // The outputs of prior swaps become the inputs to subsequent ones
            amountIn = quoteExactInputSingle(
                QuoteExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    sqrtPriceLimitX96: 0
                })
            );

            // Decide whether to continue or terminate
            if (path.hasMultiplePools()) {
                path = path.skipToken();
            } else {
                return amountIn;
            }
        }
    }
}

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "@uniswap/v3-core/contracts/libraries/LowGasSafeMath.sol";
import "@uniswap/v3-core/contracts/libraries/SafeCast.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import "./interfaces/IAlgebraStaticQuoter.sol";
import "./interfaces/IAlgebraFactory.sol";
import "./lib/PathNoFee.sol";
import "./AlgebraIntegralQuoterCore.sol";

contract AlgebraIntegralStaticQuoter is AlgebraIntegralQuoterCore {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using PathNoFee for bytes;

    address immutable factory;
    address[] public tickSpacingDeployers;

    constructor(address _factory, address[] memory _tickSpacingDeployers) {
        factory = _factory;
        tickSpacingDeployers = _tickSpacingDeployers;
    }

    function getPool(address tokenA, address tokenB) private view returns (address) {
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

    function quoteExactInput(bytes memory path, uint256 amountIn) public view returns (uint256 amountOut) {
        uint256 i = 0;
        while (true) {
            (address tokenIn, address tokenOut) = path.decodeFirstPool();
            // the outputs of prior swaps become the inputs to subsequent ones
            uint256 _amountOut = quoteExactInputSingle(
                QuoteExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    sqrtPriceLimitX96: 0
                })
            );
            amountIn = _amountOut;
            i++;

            // decide whether to continue or terminate
            if (path.hasMultiplePools()) {
                path = path.skipToken();
            } else {
                return amountIn;
            }
        }
    }
}

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import "@uniswap/v3-core/contracts/libraries/SafeCast.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "./AlgebraConstants.sol";

/// @title Functions based on Q64.96 sqrt price and liquidity
/// @notice Contains the math that uses square root of price as a Q64.96 and liquidity to compute deltas
library AlgebraTokenDeltaMath {
    using SafeCast for uint256;

    /// @notice Gets the token0 delta between two prices
    /// @dev Calculates liquidity / sqrt(lower) - liquidity / sqrt(upper)
    function getToken0Delta(uint160 priceLower, uint160 priceUpper, uint128 liquidity, bool roundUp)
        internal
        pure
        returns (uint256 token0Delta)
    {
        uint256 priceDelta = priceUpper - priceLower;
        require(priceDelta < priceUpper, "Invalid price delta"); // forbids underflow and 0 priceLower
        uint256 liquidityShifted = uint256(liquidity) << AlgebraConstants.RESOLUTION;

        token0Delta = roundUp
            ? FullMath.mulDivRoundingUp(FullMath.mulDivRoundingUp(priceDelta, liquidityShifted, priceUpper), 1, priceLower)
            : FullMath.mulDiv(FullMath.mulDiv(priceDelta, liquidityShifted, priceUpper), 1, priceLower);
    }

    /// @notice Gets the token1 delta between two prices
    /// @dev Calculates liquidity * (sqrt(upper) - sqrt(lower))
    function getToken1Delta(uint160 priceLower, uint160 priceUpper, uint128 liquidity, bool roundUp)
        internal
        pure
        returns (uint256 token1Delta)
    {
        require(priceUpper >= priceLower, "Invalid price range");
        uint256 priceDelta = priceUpper - priceLower;
        token1Delta = roundUp
            ? FullMath.mulDivRoundingUp(priceDelta, liquidity, AlgebraConstants.Q96)
            : FullMath.mulDiv(priceDelta, liquidity, AlgebraConstants.Q96);
    }

    /// @notice Helper that gets signed token0 delta
    function getToken0Delta(uint160 priceLower, uint160 priceUpper, int128 liquidity)
        internal
        pure
        returns (int256 token0Delta)
    {
        token0Delta = liquidity >= 0
            ? getToken0Delta(priceLower, priceUpper, uint128(liquidity), true).toInt256()
            : -getToken0Delta(priceLower, priceUpper, uint128(-liquidity), false).toInt256();
    }

    /// @notice Helper that gets signed token1 delta
    function getToken1Delta(uint160 priceLower, uint160 priceUpper, int128 liquidity)
        internal
        pure
        returns (int256 token1Delta)
    {
        token1Delta = liquidity >= 0
            ? getToken1Delta(priceLower, priceUpper, uint128(liquidity), true).toInt256()
            : -getToken1Delta(priceLower, priceUpper, uint128(-liquidity), false).toInt256();
    }
}

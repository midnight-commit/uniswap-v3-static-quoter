// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;
pragma abicoder v2;

/// @title Algebra QuoterV2 Interface
/// @notice Interface for the deployed official Algebra QuoterV2 contract
interface IAlgebraQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        address deployer;
        uint256 amountIn;
        uint160 limitSqrtPrice;
    }

    /// @notice Returns the amount out received for a given exact input but for a swap of a single pool
    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        returns (
            uint256 amountOut,
            uint256 amountIn,
            uint160 sqrtPriceX96After,
            uint32 initializedTicksCrossed,
            uint256 gasEstimate,
            uint16 fee
        );
}

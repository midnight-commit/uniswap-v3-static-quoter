// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

/// @title The interface for the Algebra Factory
/// @notice The Algebra Factory facilitates creation of Algebra pools and control over the protocol fees
interface IAlgebraFactory {
    /// @notice Returns the pool address for a given pair of tokens, or address 0 if it does not exist
    /// @dev tokenA and tokenB may be passed in either token0/token1 or token1/token0 order
    /// @param tokenA The contract address of either token0 or token1
    /// @param tokenB The contract address of the other token
    /// @return pool The pool address
    function poolByPair(address tokenA, address tokenB) external view returns (address pool);

    /// @notice Returns the custom pool address for a given deployer and pair of tokens, or address 0 if it does not exist
    /// @dev tokenA and tokenB may be passed in either token0/token1 or token1/token0 order
    /// @param deployer The deployer address that created the custom pool
    /// @param tokenA The contract address of either token0 or token1
    /// @param tokenB The contract address of the other token
    /// @return customPool The custom pool address
    function customPoolByPair(address deployer, address tokenA, address tokenB)
        external
        view
        returns (address customPool);

    /// @notice Returns the current owner of the factory
    /// @return The address that can call owner-only functions
    function owner() external view returns (address);

    /// @notice Checks if an account has a role or is the owner
    /// @param role The role to check
    /// @param account The account to check
    /// @return True if the account has the role or is the owner
    function hasRoleOrOwner(bytes32 role, address account) external view returns (bool);

    /// @notice Returns the default configuration for new pools
    /// @return communityFee The default community fee
    /// @return tickSpacing The default tick spacing
    /// @return fee The default fee
    function defaultConfigurationForPool() external view returns (uint16 communityFee, int24 tickSpacing, uint16 fee);

    /// @notice Computes the pool address for given tokens
    /// @param token0 The first token
    /// @param token1 The second token
    /// @return pool The computed pool address
    function computePoolAddress(address token0, address token1) external view returns (address pool);

    /// @notice Creates a pool for the given two tokens
    /// @param tokenA One of the two tokens in the desired pool
    /// @param tokenB The other of the two tokens in the desired pool
    /// @param data Additional data for pool creation
    /// @return pool The address of the newly created pool
    function createPool(address tokenA, address tokenB, bytes calldata data) external returns (address pool);
}

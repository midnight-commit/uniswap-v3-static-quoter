// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

/// @title Algebra constants for price movement calculations
library AlgebraConstants {
    uint8 internal constant RESOLUTION = 96;
    uint256 internal constant Q96 = 1 << 96;
    uint256 internal constant Q128 = 1 << 128;
    uint24 internal constant FEE_DENOMINATOR = 1e6;
}

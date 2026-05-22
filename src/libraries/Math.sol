// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Math
/// @notice Lightweight math utilities for the AMM
library Math {
    /// @notice Babylonian square root approximation
    /// @param y The value to compute the square root of
    /// @return z The integer square root of y
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    /// @notice Returns the smaller of two values
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

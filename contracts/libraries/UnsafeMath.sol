// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library UnsafeMath {
    /// @notice Calculate `a + b` without overflow check
    function addU256(uint256 a, uint256 b) internal pure returns (uint256) {
        // prettier-ignore
        unchecked { return a + b; }
    }

    /// @notice Calculate `a + b` without overflow check
    function addU128(uint128 a, uint128 b) internal pure returns (uint128) {
        // prettier-ignore
        unchecked { return a + b; }
    }

    /// @notice Calculate `a - b` without underflow check
    function subU256(uint256 a, uint256 b) internal pure returns (uint256) {
        // prettier-ignore
        unchecked { return a - b; }
    }

    /// @notice Calculate `a - b` without underflow check
    function subU128(uint128 a, uint128 b) internal pure returns (uint128) {
        // prettier-ignore
        unchecked { return a - b; }
    }

    /// @notice Calculate `a - b` without underflow check
    function subU96(uint96 a, uint96 b) internal pure returns (uint96) {
        // prettier-ignore
        unchecked { return a - b; }
    }

    /// @notice Calculate `a * b` without overflow check
    function mulU256(uint256 a, uint256 b) internal pure returns (uint256) {
        // prettier-ignore
        unchecked { return a * b; }
    }

    /// @notice Calculate `a / b` without overflow check
    function divU256(uint256 a, uint256 b) internal pure returns (uint256) {
        // prettier-ignore
        unchecked { return a / b; }
    }
}

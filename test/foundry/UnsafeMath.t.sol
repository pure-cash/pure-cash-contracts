// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import "forge-std/Test.sol";
import "../../contracts/libraries/UnsafeMath.sol";

contract UnsafeMathTest is Test {
    using UnsafeMath for *;

    function setUp() public {}

    function testFuzz_addU256_u128(uint128 a, uint128 b) public pure {
        assertEq(uint256(a) + b, a.addU256(b));
    }

    function testFuzz_addU256_u256(uint256 a, uint256 b) public pure {
        unchecked {
            assertEq(a + b, a.addU256(b));
        }
    }
}

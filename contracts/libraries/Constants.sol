// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

library Constants {
    uint24 internal constant BASIS_POINTS_DIVISOR = 10_000_000;

    uint8 internal constant DECIMALS_6 = 6;
    uint8 internal constant PRICE_DECIMALS = 10;
    uint64 internal constant PRICE_1 = uint64(10 ** PRICE_DECIMALS);

    uint256 internal constant Q64 = 1 << 64;
    uint256 internal constant Q96 = 1 << 96;
    uint256 internal constant Q72 = 1 << 72;
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import "forge-std/Test.sol";
import "../../contracts/test/WETH9.sol";
import "../../contracts/core/MarketManagerUpgradeable.sol";

abstract contract BaseTest is Test {
    address internal constant ALICE = address(0x11);
    address internal constant BOB = address(0x22);
    address internal constant CARRIE = address(0x33);
    address internal constant EXECUTOR = address(0x99);

    uint64 internal constant PRICE = 29899096567035; // 2989.9096567035

    IConfigurable.MarketConfig cfg;

    constructor() {
        cfg.minMarginPerPosition = 0.005 ether;
        cfg.maxLeveragePerPosition = 10;
        cfg.liquidationFeeRatePerPosition = 0.004 * 1e7;
        cfg.maxSizeRatePerPosition = 1 * 1e7;
        cfg.openPositionThreshold = 0.9 * 1e7;
        cfg.liquidationExecutionFee = 0.005 ether;
        cfg.liquidityCap = 1000000e18;
        cfg.liquidityBufferModuleEnabled = true;
        cfg.decimals = 18;
        cfg.tradingFeeRate = 0.0007 * 1e7;
        cfg.protocolFeeRate = 0.5 * 1e7;
        cfg.maxFeeRate = 0.02 * 1e7;
        cfg.maxBurningRate = 0.95 * 1e7;
        cfg.liquidityTradingFeeRate = 0.0005 * 1e7;

        cfg.minMintingRate = 0;
        cfg.riskFreeTime = 7200;
        cfg.liquidityScale = 100e4 * 1e18;
        cfg.stableCoinSupplyCap = 10e8 * 1e6;
        cfg.maxShortSizeRate = 2 * 1e7;
    }

    function deployWETH9() internal returns (WETH9) {
        return new WETH9();
    }

    function encodePrice(IERC20 _market, uint64 _price, uint32 _timestamp) internal pure returns (PackedValue value) {
        value = PackedValue.wrap(0);
        value = value.packAddress(address(_market), 0);
        value = value.packUint64(_price, 160);
        value = value.packUint32(_timestamp, 224);
    }
}

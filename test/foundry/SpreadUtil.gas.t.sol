// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import "forge-std/Test.sol";
import "../../contracts/libraries/SpreadUtil.sol";
import {LONG, SHORT} from "../../contracts/types/Side.sol";
import "../../contracts/core/interfaces/IConfigurable.sol";

contract SpreadUtilGasTest is Test {
    using SafeCast for *;

    IConfigurable.MarketConfig cfg;

    constructor() {
        cfg.minMintingRate = 0.5e7;
        cfg.riskFreeTime = 7200;
        cfg.liquidityScale = 1_000_000 ether;
        cfg.stableCoinSupplyCap = type(uint64).max;
    }

    function test_calcSpread_Long() public view {
        SpreadUtil.calcSpread(
            cfg,
            SpreadUtil.CalcSpreadParam({
                side: LONG,
                sizeDelta: 1e18,
                spreadFactorBeforeX96: 1e18 << 96,
                lastTradingTimestamp: 1721637008
            })
        );
    }

    function test_calcSpread_Short() public view {
        SpreadUtil.calcSpread(
            cfg,
            SpreadUtil.CalcSpreadParam({
                side: SHORT,
                sizeDelta: 1e18,
                spreadFactorBeforeX96: 1e18 << 96,
                lastTradingTimestamp: 1721637008
            })
        );
    }

    function test_calcSpreadAmount_RoundUp() public pure {
        SpreadUtil.calcSpreadAmount(63382530011411470074835160268, 100, Math.Rounding.Up);
    }

    function test_calcSpreadAmount_RoundDown() public pure {
        SpreadUtil.calcSpreadAmount(63382530011411470074835160268, 100, Math.Rounding.Down);
    }

    function test_calcSpreadFactorAfterX96_Long() public pure {
        SpreadUtil.calcSpreadFactorAfterX96(1e18 << 96, LONG, type(uint96).max);
    }

    function test_calcSpreadFactorAfterX96_Short() public pure {
        SpreadUtil.calcSpreadFactorAfterX96(-1e18 << 96, SHORT, type(uint96).max);
    }

    function test_refreshSpread_Long() public view {
        SpreadUtil.refreshSpread(
            cfg,
            SpreadUtil.CalcSpreadParam({
                side: LONG,
                sizeDelta: 0,
                spreadFactorBeforeX96: -1e18 << 96,
                lastTradingTimestamp: 1721637008
            })
        );
    }

    function test_refreshSpread_Short() public view {
        SpreadUtil.refreshSpread(
            cfg,
            SpreadUtil.CalcSpreadParam({
                side: SHORT,
                sizeDelta: 0,
                spreadFactorBeforeX96: -1e18 << 96,
                lastTradingTimestamp: 1721637008
            })
        );
    }
}

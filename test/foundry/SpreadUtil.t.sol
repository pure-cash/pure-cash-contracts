// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import "forge-std/Test.sol";
import "../../contracts/libraries/SpreadUtil.sol";
import {LONG, SHORT} from "../../contracts/types/Side.sol";
import "../../contracts/core/interfaces/IConfigurable.sol";

contract SpreadUtilTest is Test {
    IConfigurable.MarketConfig cfg;

    constructor() {
        cfg.minMintingRate = 0.5e7;
        cfg.riskFreeTime = 7200;
        cfg.liquidityScale = 1_000_000 ether;
        cfg.stableCoinSupplyCap = type(uint64).max;
    }

    function setUp() public {}

    function test_calcSpread() public {
        vm.warp(1721637008 + 100);
        (uint128 spreadAmount, int256 spreadFactorAfterX96) = SpreadUtil.calcSpread(
            cfg,
            SpreadUtil.CalcSpreadParam({
                side: SHORT,
                sizeDelta: 1e18,
                spreadFactorBeforeX96: 1e18 << 96,
                lastTradingTimestamp: 1721637008
            })
        );
        assertEq(spreadFactorAfterX96, -1100391146031449133243665976888888888888888888);
        assertEq(spreadAmount, 986111111112);
    }

    function test_calcSpreadAmount() public pure {
        uint128 spreadAmount = SpreadUtil.calcSpreadAmount(63382530011411470074835160268, 100, Math.Rounding.Up);
        assertEq(spreadAmount, 80, "round up");

        spreadAmount = SpreadUtil.calcSpreadAmount(63382530011411470074835160268, 100, Math.Rounding.Down);
        assertEq(spreadAmount, 79, "round down");
    }

    function testFuzz_calcSpreadAmount(uint104 _spreadX96, uint96 _sizeDelta, bool _roundingUp) public pure {
        vm.assume(_spreadX96 <= Constants.Q96);
        SpreadUtil.calcSpreadAmount(_spreadX96, _sizeDelta, _roundingUp ? Math.Rounding.Up : Math.Rounding.Down);
    }

    function test_calcSpreadFactorAfterX96() public pure {
        int256 spreadFactorAfterX96 = SpreadUtil.calcSpreadFactorAfterX96(0, LONG, 0);
        assertEq(spreadFactorAfterX96, 0, "zero size delta, long");

        spreadFactorAfterX96 = SpreadUtil.calcSpreadFactorAfterX96(0, SHORT, 0);
        assertEq(spreadFactorAfterX96, 0, "zero size delta, short");

        spreadFactorAfterX96 = SpreadUtil.calcSpreadFactorAfterX96(1e18 << 96, LONG, 1e18);
        assertEq(spreadFactorAfterX96, 158456325028528675187087900672000000000000000000, "long 1 ETH");

        spreadFactorAfterX96 = SpreadUtil.calcSpreadFactorAfterX96(1e18 << 96, SHORT, 1e18);
        assertEq(spreadFactorAfterX96, 0, "short 1 ETH");

        spreadFactorAfterX96 = SpreadUtil.calcSpreadFactorAfterX96(1e18 << 96, LONG, type(uint96).max);
        assertEq(spreadFactorAfterX96, (1e18 << 96) + int256(uint256(type(uint96).max) << 96));

        spreadFactorAfterX96 = SpreadUtil.calcSpreadFactorAfterX96(-1e18 << 96, SHORT, type(uint96).max);
        assertEq(spreadFactorAfterX96, ((-1e18 << 96) - int256(uint256(type(uint96).max) << 96)));
    }

    function testFuzz_calcSpreadFactorAfterX96(
        int256 _spreadFactorBeforeX96,
        uint8 _side,
        uint96 _sizeDelta
    ) public pure {
        vm.assume(_side <= 1);
        vm.assume(
            -(int256(uint256(type(uint128).max)) << 96) <= _spreadFactorBeforeX96 &&
                _spreadFactorBeforeX96 <= int256(uint256(type(uint128).max) << 96)
        );
        SpreadUtil.calcSpreadFactorAfterX96(_spreadFactorBeforeX96, Side.wrap(_side), _sizeDelta);
    }

    struct RefreshSpreadCase {
        string desc;
        IConfigurable.MarketConfig _cfg;
        SpreadUtil.CalcSpreadParam _param;
        uint blockTimestamp;
        int256 spreadFactorAfterX96Want;
        uint256 spreadX96Want;
    }

    function test_refreshSpread() public {
        RefreshSpreadCase[12] memory cases;
        cases[0] = RefreshSpreadCase({
            desc: "time elapsed in seconds = cfg.riskFreeTime, long",
            _cfg: cfg,
            _param: SpreadUtil.CalcSpreadParam({
                side: LONG,
                sizeDelta: 0,
                spreadFactorBeforeX96: 1e18 << 96,
                lastTradingTimestamp: 1721637008
            }),
            blockTimestamp: 1721637008 + 7200,
            spreadFactorAfterX96Want: 0,
            spreadX96Want: 0
        });
        cases[1] = RefreshSpreadCase({
            desc: "time elapsed in seconds = cfg.riskFreeTime, short",
            _cfg: cfg,
            _param: SpreadUtil.CalcSpreadParam({
                side: SHORT,
                sizeDelta: 0,
                spreadFactorBeforeX96: 1e18 << 96,
                lastTradingTimestamp: 1721637008
            }),
            blockTimestamp: 1721637008 + 7200,
            spreadFactorAfterX96Want: 0,
            spreadX96Want: 0
        });
        cases[2] = RefreshSpreadCase({
            desc: "time elapsed in seconds > cfg.riskFreeTime, long",
            _cfg: cfg,
            _param: SpreadUtil.CalcSpreadParam({
                side: LONG,
                sizeDelta: 0,
                spreadFactorBeforeX96: 1e18 << 96,
                lastTradingTimestamp: 1721637008
            }),
            blockTimestamp: 1721637008 + 7200 + 100,
            spreadFactorAfterX96Want: 0,
            spreadX96Want: 0
        });
        cases[3] = RefreshSpreadCase({
            desc: "time elapsed in seconds > cfg.riskFreeTime, short",
            _cfg: cfg,
            _param: SpreadUtil.CalcSpreadParam({
                side: SHORT,
                sizeDelta: 0,
                spreadFactorBeforeX96: 1e18 << 96,
                lastTradingTimestamp: 1721637008
            }),
            blockTimestamp: 1721637008 + 7200 + 100,
            spreadFactorAfterX96Want: 0,
            spreadX96Want: 0
        });
        cases[4] = RefreshSpreadCase({
            desc: "time elapsed in seconds < cfg.riskFreeTime, spreadFactorBeforeX96 = 0",
            _cfg: cfg,
            _param: SpreadUtil.CalcSpreadParam({
                side: SHORT,
                sizeDelta: 0,
                spreadFactorBeforeX96: 0,
                lastTradingTimestamp: 1721637008
            }),
            blockTimestamp: 1721637008 + 100,
            spreadFactorAfterX96Want: 0,
            spreadX96Want: 0
        });
        cases[5] = RefreshSpreadCase({
            desc: "time elapsed in seconds < cfg.riskFreeTime, long and spreadFactorAfterX96 > 0",
            _cfg: cfg,
            _param: SpreadUtil.CalcSpreadParam({
                side: LONG,
                sizeDelta: 0,
                spreadFactorBeforeX96: 1e18 << 96,
                lastTradingTimestamp: 1721637008
            }),
            blockTimestamp: 1721637008 + 100,
            spreadFactorAfterX96Want: 78127771368232888460300284359111111111111111112,
            spreadX96Want: 0
        });

        cases[6] = RefreshSpreadCase({
            desc: "time elapsed in seconds < cfg.riskFreeTime, short and spreadFactorAfterX96 < 0",
            _cfg: cfg,
            _param: SpreadUtil.CalcSpreadParam({
                side: SHORT,
                sizeDelta: 0,
                spreadFactorBeforeX96: -1e18 << 96,
                lastTradingTimestamp: 1721637008
            }),
            blockTimestamp: 1721637008 + 100,
            spreadFactorAfterX96Want: -78127771368232888460300284359111111111111111112,
            spreadX96Want: 0
        });

        cases[7] = RefreshSpreadCase({
            desc: "time elapsed in seconds < cfg.riskFreeTime, short and spreadFactorAfterX96 > 0",
            _cfg: cfg,
            _param: SpreadUtil.CalcSpreadParam({
                side: SHORT,
                sizeDelta: 0,
                spreadFactorBeforeX96: 1e18 << 96,
                lastTradingTimestamp: 1721637008
            }),
            blockTimestamp: 1721637008 + 100,
            spreadFactorAfterX96Want: 78127771368232888460300284359111111111111111112,
            spreadX96Want: 78127771368232888460301
        });

        cases[8] = RefreshSpreadCase({
            desc: "time elapsed in seconds < cfg.riskFreeTime, long and spreadFactorAfterX96 < 0",
            _cfg: cfg,
            _param: SpreadUtil.CalcSpreadParam({
                side: LONG,
                sizeDelta: 0,
                spreadFactorBeforeX96: -1e18 << 96,
                lastTradingTimestamp: 1721637008
            }),
            blockTimestamp: 1721637008 + 100,
            spreadFactorAfterX96Want: -78127771368232888460300284359111111111111111112,
            spreadX96Want: 78127771368232888460301
        });

        cases[9] = RefreshSpreadCase({
            desc: "time elapsed in seconds < cfg.riskFreeTime, short and spreadFactorAfterX96 < 0",
            _cfg: cfg,
            _param: SpreadUtil.CalcSpreadParam({
                side: SHORT,
                sizeDelta: 0,
                spreadFactorBeforeX96: -1e18 << 96,
                lastTradingTimestamp: 1721637008
            }),
            blockTimestamp: 1721637008 + 100,
            spreadFactorAfterX96Want: -78127771368232888460300284359111111111111111112,
            spreadX96Want: 0
        });

        // Unable to run a fuzz test to test if function works with extreme values because the `unchecked` block
        // Here are some cases
        cases[10] = RefreshSpreadCase({
            desc: "time elapsed in seconds = 0, spreadFactorBeforeX96 is type(int232).min, long and spreadFactorAfterX96 < 0",
            _cfg: cfg,
            _param: SpreadUtil.CalcSpreadParam({
                side: LONG,
                sizeDelta: 0,
                spreadFactorBeforeX96: type(int232).min,
                lastTradingTimestamp: 1721637008
            }),
            blockTimestamp: 1721637008,
            spreadFactorAfterX96Want: type(int232).min,
            spreadX96Want: Math.ceilDiv(
                3450873173395281893717377931138512726225554486085193277581262111899648,
                cfg.liquidityScale
            )
        });

        cases[11] = RefreshSpreadCase({
            desc: "time elapsed in seconds = 0, spreadFactorBeforeX96 is type(int232).max, short and spreadFactorAfterX96 > 0",
            _cfg: cfg,
            _param: SpreadUtil.CalcSpreadParam({
                side: SHORT,
                sizeDelta: 0,
                spreadFactorBeforeX96: type(int232).max,
                lastTradingTimestamp: 1721637008
            }),
            blockTimestamp: 1721637008,
            spreadFactorAfterX96Want: type(int232).max,
            spreadX96Want: Math.ceilDiv(
                3450873173395281893717377931138512726225554486085193277581262111899647,
                cfg.liquidityScale
            )
        });
        for (uint i; i < cases.length; i++) {
            console.log("Running %d: %s", i, cases[i].desc);
            cfg = cases[i]._cfg;
            vm.warp(cases[i].blockTimestamp);
            (int256 spreadFactorAfterX96, uint256 spreadX96) = SpreadUtil.refreshSpread(cfg, cases[i]._param);
            assertEq(spreadFactorAfterX96, cases[i].spreadFactorAfterX96Want, "spreadFactorAfterX96");
            assertEq(spreadX96, cases[i].spreadX96Want, "spreadX96");
        }
    }
}

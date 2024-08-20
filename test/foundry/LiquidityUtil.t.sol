// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import {LONG, SHORT} from "../../contracts/types/Side.sol";
import "../../contracts/libraries/LiquidityUtil.sol";
import "../../contracts/core/LPToken.sol";
import "../../contracts/test/ERC20Test.sol";
import "./BaseTest.t.sol";

contract LiquidityUtilTest is BaseTest {
    IMarketManager.State private state;

    IERC20 market = new ERC20Test("Market Token", "MT", 18, 1000000e18);

    address private constant account = address(0x111);
    address private constant receiver = address(0x222);
    address private constant feeReceiver = address(0x333);

    function setUp() public {}

    function test_deployLPToken_pass() public {
        LPToken lpt = LiquidityUtil.deployLPToken(market, "MT");
        assertEq(lpt.symbol(), "MT");
        assertEq(lpt.totalSupply(), 0);
        assertEq(lpt.symbol(), "MT");
        assertEq(lpt.decimals(), 6);
    }

    function test_computeLPTokenAddress_pass() public {
        address want = address(LiquidityUtil.deployLPToken(market, "MT"));
        address got = LiquidityUtil.computeLPTokenAddress(market);
        assertEq(got, want);
    }

    function test_mintLPT_revertIf_liquidityCapExceeded() public {
        vm.expectRevert(
            abi.encodeWithSelector(IMarketErrors.LiquidityCapExceeded.selector, 0, 1000000e18 + 1, 1000000e18)
        );
        LiquidityUtil.mintLPT(
            state,
            cfg,
            LiquidityUtil.MintParam({
                market: market,
                account: account,
                receiver: receiver,
                liquidity: 1000000e18 + 1,
                indexPrice: PRICE
            })
        );
    }

    function test_mintLPT_revertIf_notFirstAndLiquidityCapExceeded() public {
        LiquidityUtil.deployLPToken(market, "MT");
        LiquidityUtil.mintLPT(
            state,
            cfg,
            LiquidityUtil.MintParam({
                market: market,
                account: account,
                receiver: receiver,
                liquidity: 500000e18,
                indexPrice: PRICE
            })
        );
        assertEq(state.packedState.lpLiquidity, 500000e18);

        vm.expectRevert(
            abi.encodeWithSelector(IMarketErrors.LiquidityCapExceeded.selector, 500000e18, 500000e18 + 1, 1000000e18)
        );
        LiquidityUtil.mintLPT(
            state,
            cfg,
            LiquidityUtil.MintParam({
                market: market,
                account: account,
                receiver: receiver,
                liquidity: 500000e18 + 1,
                indexPrice: PRICE
            })
        );
    }

    function test_mintLPT_passIf_mintLPTFirst() public {
        LPToken lpt = LiquidityUtil.deployLPToken(market, "MT");

        LiquidityUtil.MintParam memory param = LiquidityUtil.MintParam({
            market: market,
            account: account,
            receiver: receiver,
            liquidity: 500000e18,
            indexPrice: PRICE
        });
        uint64 want = PositionUtil.calcDecimals6TokenValue(
            param.liquidity,
            param.indexPrice,
            cfg.decimals,
            Math.Rounding.Down
        );
        vm.expectEmit();
        emit IMarketLiquidity.LPTMinted(param.market, param.account, param.receiver, param.liquidity, want);
        uint64 got = LiquidityUtil.mintLPT(state, cfg, param);

        assertEq(want, got);
        assertEq(state.packedState.lpLiquidity, 500000e18);
        assertEq(state.packedState.lpNetSize, 0);
        assertEq(lpt.totalSupply(), want);
        assertEq(lpt.balanceOf(receiver), want);
    }

    function test_mintLPT_passIf_mintLPTNotFirst() public {
        LPToken lpt = LiquidityUtil.deployLPToken(market, "MT");

        LiquidityUtil.MintParam memory param = LiquidityUtil.MintParam({
            market: market,
            account: account,
            receiver: receiver,
            liquidity: 500000e18,
            indexPrice: PRICE
        });
        uint64 want = PositionUtil.calcDecimals6TokenValue(
            param.liquidity,
            param.indexPrice,
            cfg.decimals,
            Math.Rounding.Down
        );
        vm.expectEmit();
        emit IMarketLiquidity.LPTMinted(param.market, param.account, param.receiver, param.liquidity, want);
        uint64 got = LiquidityUtil.mintLPT(state, cfg, param);

        param.indexPrice = (PRICE * 8) / 10;
        uint64 want2 = uint64(
            Math.mulDiv(
                param.liquidity,
                want,
                uint256(PositionUtil.calcUnrealizedPnL(SHORT, 0, 0, param.indexPrice)) + 500000e18
            )
        );
        vm.expectEmit();
        emit IMarketLiquidity.LPTMinted(param.market, param.account, param.receiver, param.liquidity, want2);
        uint64 got2 = LiquidityUtil.mintLPT(state, cfg, param);

        assertEq(want, got);
        assertEq(want2, got2);
        assertEq(state.packedState.lpLiquidity, 1000000e18);
        assertEq(state.packedState.lpNetSize, 0);
        assertEq(lpt.totalSupply(), want + want2);
        assertEq(lpt.balanceOf(receiver), want + want2);
    }

    function _prepareBurnLPT() private returns (LPToken lpt) {
        lpt = LiquidityUtil.deployLPToken(market, "MT");

        LiquidityUtil.mintLPT(
            state,
            cfg,
            LiquidityUtil.MintParam({
                market: market,
                account: account,
                receiver: address(this),
                liquidity: 500000e18,
                indexPrice: PRICE
            })
        );
    }

    function test_burnLPT_revertIf_balanceRateCapExceeded() public {
        LPToken lpt = _prepareBurnLPT();

        state.packedState.lpNetSize = 300000e18;
        state.packedState.lpEntryPrice = PRICE;
        uint64 tokenValue = uint64(lpt.balanceOf(address(this)));

        vm.expectRevert(IMarketErrors.BalanceRateCapExceeded.selector);
        LiquidityUtil.burnLPT(
            state,
            LiquidityUtil.BurnParam({
                market: market,
                account: account,
                receiver: receiver,
                tokenValue: tokenValue,
                indexPrice: (PRICE * 4) / 5
            })
        );
    }

    function _test_burnLPT_pass(uint64 _newPrice) private {
        LPToken lpt = _prepareBurnLPT();
        state.packedState.lpNetSize = 300000e18;
        state.packedState.lpEntryPrice = PRICE;

        LiquidityUtil.BurnParam memory param = LiquidityUtil.BurnParam({
            market: market,
            account: account,
            receiver: receiver,
            tokenValue: 1000000e6,
            indexPrice: _newPrice
        });
        uint256 totalSupply = lpt.totalSupply();
        int256 pnl = PositionUtil.calcUnrealizedPnL(
            SHORT,
            state.packedState.lpNetSize,
            state.packedState.lpEntryPrice,
            param.indexPrice
        );
        if (_newPrice >= PRICE) assertLe(pnl, 0);
        else assertGt(pnl, 0);
        uint96 want = uint96(
            (uint256(pnl + int256(uint256(state.packedState.lpLiquidity))) * param.tokenValue) / totalSupply
        );
        vm.expectEmit();
        emit IMarketLiquidity.LPTBurned(param.market, param.account, param.receiver, want, param.tokenValue);
        uint96 got = LiquidityUtil.burnLPT(state, param);

        assertEq(want, got);
        assertEq(state.packedState.lpLiquidity, 500000e18 - want);
        assertEq(state.packedState.lpNetSize, 300000e18);
        assertEq(lpt.totalSupply(), totalSupply - 1000000e6);
    }

    function test_burnLPT_passIf_loss() public {
        _test_burnLPT_pass((PRICE * 6) / 5);
    }

    function test_burnLPT_passIf_profit() public {
        _test_burnLPT_pass((PRICE * 4) / 5);
    }

    function test_settlePosition_passIf_sideIsLongAndFirstIncrease() public {
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(IERC20(address(0x1)), 1e18, 0, PRICE);
        LiquidityUtil.settlePosition(state.packedState, IERC20(address(0x1)), LONG, PRICE, 1e18);

        assertEq(state.packedState.lpNetSize, 1e18);
        assertEq(state.packedState.lpEntryPrice, PRICE);
        assertEq(state.packedState.lpLiquidity, 0);
    }

    function test_settlePosition_passIf_sideIsLongAndNotFirstIncrease() public {
        LiquidityUtil.settlePosition(state.packedState, IERC20(address(0x1)), LONG, PRICE, 1e18);

        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(IERC20(address(0x1)), 2e18, 0, PRICE + 1);
        LiquidityUtil.settlePosition(state.packedState, IERC20(address(0x1)), LONG, PRICE + 2, 2e18);

        assertEq(state.packedState.lpNetSize, 3e18);
        assertEq(state.packedState.lpEntryPrice, PRICE + 1);
        assertEq(state.packedState.lpLiquidity, 0);
    }

    function test_settlePosition_passIf_sideIsShortAndDecreaseWithLoss() public {
        state.packedState.lpLiquidity = 100e18;
        state.packedState.lpNetSize = 20e18;
        state.packedState.lpEntryPrice = PRICE;

        vm.expectEmit();
        int256 unrealizedPnL = PositionUtil.calcUnrealizedPnL(SHORT, 1e18, PRICE, 3000 * 1e10);
        emit IMarketLiquidity.GlobalLiquiditySettled(IERC20(address(0x1)), -1e18, unrealizedPnL, PRICE);
        LiquidityUtil.settlePosition(state.packedState, IERC20(address(0x1)), SHORT, 3000 * 1e10, 1e18);

        assertEq(state.packedState.lpNetSize, 19e18);
        assertEq(state.packedState.lpEntryPrice, PRICE);
        assertEq(int256(uint256(state.packedState.lpLiquidity)), unrealizedPnL + 100e18);
    }

    function test_settlePosition_passIf_sideIsShortAndDecreaseWithProfit() public {
        state.packedState.lpLiquidity = 100e18;
        state.packedState.lpNetSize = 20e18;
        state.packedState.lpEntryPrice = PRICE;

        vm.expectEmit();
        int256 unrealizedPnL = PositionUtil.calcUnrealizedPnL(SHORT, 1e18, PRICE, 2000 * 1e10);
        emit IMarketLiquidity.GlobalLiquiditySettled(IERC20(address(0x1)), -1e18, unrealizedPnL, PRICE);
        LiquidityUtil.settlePosition(state.packedState, IERC20(address(0x1)), SHORT, 2000 * 1e10, 1e18);

        assertEq(state.packedState.lpNetSize, 19e18);
        assertEq(state.packedState.lpEntryPrice, PRICE);
        assertEq(int256(uint256(state.packedState.lpLiquidity)), unrealizedPnL + 100e18);
    }

    function test_settlePosition_passIf_sideIsShortAndDecreaseAll() public {
        state.packedState.lpLiquidity = 100e18;
        state.packedState.lpNetSize = 20e18;
        state.packedState.lpEntryPrice = PRICE;

        vm.expectEmit();
        int256 unrealizedPnL = PositionUtil.calcUnrealizedPnL(SHORT, 20e18, PRICE, 3000 * 1e10);
        emit IMarketLiquidity.GlobalLiquiditySettled(IERC20(address(0x1)), -20e18, unrealizedPnL, PRICE);
        LiquidityUtil.settlePosition(state.packedState, IERC20(address(0x1)), SHORT, 3000 * 1e10, 20e18);

        assertEq(state.packedState.lpNetSize, 0);
        assertEq(state.packedState.lpEntryPrice, PRICE);
        assertEq(int256(uint256(state.packedState.lpLiquidity)), unrealizedPnL + 100e18);
    }

    function test_settlePosition_revertIf_sideIsShortAndLiquidityNotEnough() public {
        state.packedState.lpLiquidity = 10e18;
        state.packedState.lpNetSize = 20e18;
        state.packedState.lpEntryPrice = 1;

        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedIntToUint.selector, -9999999999999999999));
        LiquidityUtil.settlePosition(state.packedState, IERC20(address(0x1)), SHORT, type(uint64).max, 20e18);
    }

    function test_settlePosition_passIf_decreaseAllAndIncrease() public {
        state.packedState.lpLiquidity = 100e18;
        state.packedState.lpNetSize = 20e18;
        state.packedState.lpEntryPrice = PRICE;

        LiquidityUtil.settlePosition(state.packedState, IERC20(address(0x1)), SHORT, 3000 * 1e10, 20e18);

        uint128 liquidityBefore = state.packedState.lpLiquidity;

        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(IERC20(address(0x1)), 30e18, 0, 3000 * 1e10);
        LiquidityUtil.settlePosition(state.packedState, IERC20(address(0x1)), LONG, 3000 * 1e10, 30e18);

        assertEq(state.packedState.lpLiquidity, liquidityBefore);
        assertEq(state.packedState.lpEntryPrice, 3000 * 1e10);
        assertEq(state.packedState.lpNetSize, 30e18);
    }

    function testFuzz_settlePosition_long(uint64 _indexPrice, uint96 _sizeDelta) public {
        vm.assume(_indexPrice > 0);

        uint128 netSizeBefore = type(uint128).max - type(uint96).max;
        state.packedState.lpNetSize = netSizeBefore;
        state.packedState.lpEntryPrice = PRICE;

        vm.expectEmit();
        uint64 entryPriceAfter = PositionUtil.calcNextEntryPrice(
            SHORT,
            state.packedState.lpNetSize,
            PRICE,
            _sizeDelta,
            _indexPrice
        );
        emit IMarketLiquidity.GlobalLiquiditySettled(
            IERC20(address(0x1)),
            int256(uint256(_sizeDelta)),
            0,
            entryPriceAfter
        );
        LiquidityUtil.settlePosition(state.packedState, IERC20(address(0x1)), LONG, _indexPrice, _sizeDelta);

        assertEq(state.packedState.lpNetSize, netSizeBefore + _sizeDelta);
        assertEq(state.packedState.lpEntryPrice, entryPriceAfter);
        assertEq(state.packedState.lpLiquidity, 0);
    }

    function testFuzz_settlePosition_short(
        uint128 _liquidity,
        uint64 _entryPrice,
        uint64 _indexPrice,
        uint128 _sizeBefore,
        uint96 _sizeDelta
    ) public {
        vm.assume(_liquidity > 0 && _indexPrice > 0 && _entryPrice > 0 && _sizeBefore >= _sizeDelta);

        state.packedState.lpLiquidity = _liquidity;
        state.packedState.lpEntryPrice = _entryPrice;
        state.packedState.lpNetSize = _sizeBefore;

        int256 unrealizedPnL = PositionUtil.calcUnrealizedPnL(SHORT, _sizeDelta, _entryPrice, _indexPrice);
        if (unrealizedPnL < 0 && -unrealizedPnL > int256(uint256(_liquidity))) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    SafeCast.SafeCastOverflowedIntToUint.selector,
                    unrealizedPnL + int256(uint256(_liquidity))
                )
            );
        } else if (unrealizedPnL + int256(uint256(_liquidity)) > int256(uint256(type(uint128).max))) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    SafeCast.SafeCastOverflowedUintDowncast.selector,
                    128,
                    unrealizedPnL + int256(uint256(_liquidity))
                )
            );
        } else {
            emit IMarketLiquidity.GlobalLiquiditySettled(
                IERC20(address(0x1)),
                -int256(uint256(_sizeDelta)),
                unrealizedPnL,
                PRICE
            );
        }
        LiquidityUtil.settlePosition(state.packedState, IERC20(address(0x1)), SHORT, _indexPrice, _sizeDelta);

        assertEq(state.packedState.lpNetSize, _sizeBefore - _sizeDelta);
        assertEq(state.packedState.lpEntryPrice, _entryPrice);
        assertEq(int256(uint256((state.packedState.lpLiquidity))), unrealizedPnL + int256(uint256(_liquidity)));
    }
}

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

    IConfigurable.MarketConfig cfgWithFee;

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
        emit IMarketLiquidity.LPTMinted(param.market, param.account, param.receiver, param.liquidity, want, 0);
        uint64 got = LiquidityUtil.mintLPT(state, cfg, param);

        assertEq(want, got);
        assertEq(state.packedState.lpLiquidity, 500000e18);
        assertEq(state.packedState.lpNetSize, 0);
        assertEq(lpt.totalSupply(), want);
        assertEq(lpt.balanceOf(receiver), want);
    }

    function test_mintLPT_passIf_mintLPTFirstWithFee() public {
        cfgWithFee = cfg;
        cfgWithFee.liquidityTradingFeeRate = 0.0005 * 1e7;

        LPToken lpt = LiquidityUtil.deployLPToken(market, "MT");

        LiquidityUtil.MintParam memory param = LiquidityUtil.MintParam({
            market: market,
            account: account,
            receiver: receiver,
            liquidity: 500000e18,
            indexPrice: PRICE
        });
        uint256 tradingFee = Math.ceilDiv(
            uint256(param.liquidity) * cfgWithFee.liquidityTradingFeeRate,
            Constants.BASIS_POINTS_DIVISOR
        );
        uint256 protocolFee = tradingFee;
        uint64 want = PositionUtil.calcDecimals6TokenValue(
            param.liquidity - uint96(tradingFee),
            param.indexPrice,
            cfg.decimals,
            Math.Rounding.Down
        );
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreasedByLPTradingFee(param.market, uint96(protocolFee));
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByLPTradingFee(param.market, 0);
        vm.expectEmit();
        emit IMarketLiquidity.LPTMinted(
            param.market,
            param.account,
            param.receiver,
            param.liquidity - uint96(tradingFee),
            want,
            uint96(tradingFee)
        );
        uint64 got = LiquidityUtil.mintLPT(state, cfgWithFee, param);

        assertEq(want, got);
        assertEq(state.packedState.lpLiquidity, 500000e18 - protocolFee);
        assertEq(state.packedState.lpNetSize, 0);
        assertEq(lpt.totalSupply(), want);
        assertEq(lpt.balanceOf(receiver), want);
        assertEq(state.protocolFee, protocolFee);
    }

    function test_mintLPT_passIf_mintLPTSecondWithFee() public {
        cfgWithFee = cfg;
        cfgWithFee.liquidityTradingFeeRate = 0.0005 * 1e7;

        LPToken lpt = LiquidityUtil.deployLPToken(market, "MT");

        LiquidityUtil.MintParam memory param = LiquidityUtil.MintParam({
            market: market,
            account: account,
            receiver: receiver,
            liquidity: 500000e18,
            indexPrice: PRICE
        });
        LiquidityUtil.mintLPT(state, cfgWithFee, param);

        uint128 protocolFeeBefore = state.protocolFee;
        uint128 lpLiquidityBefore = state.packedState.lpLiquidity;
        uint256 totalSupplyBefore = lpt.totalSupply();

        uint256 tradingFee = Math.ceilDiv(
            uint256(param.liquidity) * cfgWithFee.liquidityTradingFeeRate,
            Constants.BASIS_POINTS_DIVISOR
        );
        uint96 protocolFee = uint96((tradingFee * cfgWithFee.protocolFeeRate) / Constants.BASIS_POINTS_DIVISOR);
        uint96 liquidityFee = uint96(tradingFee - protocolFee);
        uint64 want = uint64(
            Math.mulDiv(param.liquidity - tradingFee, totalSupplyBefore, lpLiquidityBefore + liquidityFee)
        );
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreasedByLPTradingFee(param.market, uint96(protocolFee));
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByLPTradingFee(param.market, liquidityFee);
        vm.expectEmit();
        emit IMarketLiquidity.LPTMinted(
            param.market,
            param.account,
            param.receiver,
            param.liquidity - uint96(tradingFee),
            want,
            uint96(tradingFee)
        );
        uint64 got = LiquidityUtil.mintLPT(state, cfgWithFee, param);

        assertEq(want, got);
        assertEq(state.packedState.lpLiquidity, lpLiquidityBefore * 2 + liquidityFee);
        assertEq(state.packedState.lpNetSize, 0);
        assertEq(lpt.totalSupply(), totalSupplyBefore + want);
        assertEq(lpt.balanceOf(receiver), totalSupplyBefore + want);
        assertEq(state.protocolFee, protocolFee + protocolFeeBefore);
    }

    function test_mintLPT_passIf_mintLPTWithFeeExceedsLiquidityCap() public {
        cfgWithFee = cfg;
        cfgWithFee.liquidityTradingFeeRate = 0.0005 * 1e7;

        LPToken lpt = LiquidityUtil.deployLPToken(market, "MT");

        LiquidityUtil.MintParam memory param = LiquidityUtil.MintParam({
            market: market,
            account: account,
            receiver: receiver,
            liquidity: 500000e18,
            indexPrice: PRICE
        });
        LiquidityUtil.mintLPT(state, cfgWithFee, param);

        uint128 protocolFeeBefore = state.protocolFee;
        uint128 lpLiquidityBefore = state.packedState.lpLiquidity;
        uint256 totalSupplyBefore = lpt.totalSupply();

        param.liquidity = 500500250125062531265632;
        uint256 tradingFee = Math.ceilDiv(
            uint256(param.liquidity) * cfgWithFee.liquidityTradingFeeRate,
            Constants.BASIS_POINTS_DIVISOR
        );
        uint96 actualLiquidity = uint96(param.liquidity - tradingFee);
        uint256 liquidityFee = cfgWithFee.liquidityCap - lpLiquidityBefore - actualLiquidity;
        uint256 protocolFee = tradingFee - liquidityFee;
        uint64 want = uint64(Math.mulDiv(actualLiquidity, totalSupplyBefore, lpLiquidityBefore + liquidityFee));
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreasedByLPTradingFee(param.market, uint96(protocolFee));
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByLPTradingFee(param.market, uint96(liquidityFee));
        vm.expectEmit();
        emit IMarketLiquidity.LPTMinted(
            param.market,
            param.account,
            param.receiver,
            actualLiquidity,
            want,
            uint96(tradingFee)
        );
        uint64 got = LiquidityUtil.mintLPT(state, cfgWithFee, param);

        assertEq(want, got);
        assertEq(state.packedState.lpLiquidity, lpLiquidityBefore + actualLiquidity + liquidityFee);
        assertEq(state.packedState.lpNetSize, 0);
        assertEq(lpt.totalSupply(), totalSupplyBefore + want);
        assertEq(lpt.balanceOf(receiver), totalSupplyBefore + want);
        assertEq(state.protocolFee, protocolFee + protocolFeeBefore);
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
        emit IMarketLiquidity.LPTMinted(param.market, param.account, param.receiver, param.liquidity, want, 0);
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
        emit IMarketLiquidity.LPTMinted(param.market, param.account, param.receiver, param.liquidity, want2, 0);
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
            cfg,
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
        emit IMarketLiquidity.LPTBurned(param.market, param.account, param.receiver, want, param.tokenValue, 0);
        uint96 got = LiquidityUtil.burnLPT(state, cfg, param);

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

    function test_burnLPT_passIf_withFee() public {
        LPToken lpt = _prepareBurnLPT();

        uint256 totalSupplyBefore = lpt.totalSupply();
        uint128 lpLiquidityBefore = state.packedState.lpLiquidity;

        cfgWithFee = cfg;
        cfgWithFee.liquidityTradingFeeRate = 0.0005 * 1e7;

        LiquidityUtil.BurnParam memory param = LiquidityUtil.BurnParam({
            market: market,
            account: account,
            receiver: receiver,
            tokenValue: 1000000e6,
            indexPrice: PRICE
        });
        uint256 liquidityWithFee = Math.mulDiv(lpLiquidityBefore, param.tokenValue, totalSupplyBefore);
        uint256 tradingFee = Math.ceilDiv(
            liquidityWithFee * cfgWithFee.liquidityTradingFeeRate,
            Constants.BASIS_POINTS_DIVISOR
        );
        uint256 protocolFee = (tradingFee * cfgWithFee.protocolFeeRate) / Constants.BASIS_POINTS_DIVISOR;
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreasedByLPTradingFee(param.market, uint96(protocolFee));
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByLPTradingFee(param.market, uint96(tradingFee - protocolFee));
        vm.expectEmit();
        emit IMarketLiquidity.LPTBurned(
            param.market,
            param.account,
            param.receiver,
            uint96(liquidityWithFee - tradingFee),
            param.tokenValue,
            uint96(tradingFee)
        );
        uint96 got = LiquidityUtil.burnLPT(state, cfgWithFee, param);
        assertEq(got, liquidityWithFee - tradingFee);
        assertEq(state.packedState.lpLiquidity, lpLiquidityBefore - liquidityWithFee + (tradingFee - protocolFee));
        assertEq(state.protocolFee, protocolFee);
    }

    function test_burnLPT_passIf_burnAllWithFee() public {
        LPToken lpt = _prepareBurnLPT();

        uint128 lpLiquidityBefore = state.packedState.lpLiquidity;

        cfgWithFee = cfg;
        cfgWithFee.liquidityTradingFeeRate = 0.0005 * 1e7;

        LiquidityUtil.BurnParam memory param = LiquidityUtil.BurnParam({
            market: market,
            account: account,
            receiver: receiver,
            tokenValue: uint64(lpt.totalSupply()),
            indexPrice: PRICE
        });
        uint256 liquidityWithFee = lpLiquidityBefore;
        uint256 tradingFee = Math.ceilDiv(
            liquidityWithFee * cfgWithFee.liquidityTradingFeeRate,
            Constants.BASIS_POINTS_DIVISOR
        );
        uint256 protocolFee = tradingFee;
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreasedByLPTradingFee(param.market, uint96(protocolFee));
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByLPTradingFee(param.market, 0);
        vm.expectEmit();
        emit IMarketLiquidity.LPTBurned(
            param.market,
            param.account,
            param.receiver,
            uint96(liquidityWithFee - tradingFee),
            param.tokenValue,
            uint96(tradingFee)
        );
        uint96 got = LiquidityUtil.burnLPT(state, cfgWithFee, param);
        assertEq(got, liquidityWithFee - tradingFee);
        assertEq(state.packedState.lpLiquidity, 0);
        assertEq(state.protocolFee, protocolFee);
    }

    function test_settlePosition_passIf_sideIsLongAndFirstIncrease() public {
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(IERC20(address(0x1)), 1e18, 0, PRICE);
        LiquidityUtil.settlePosition(state, IERC20(address(0x1)), LONG, PRICE, 1e18);

        assertEq(state.packedState.lpNetSize, 1e18);
        assertEq(state.packedState.lpEntryPrice, PRICE);
        assertEq(state.packedState.lpLiquidity, 0);
    }

    function test_settlePosition_passIf_sideIsLongAndNotFirstIncrease() public {
        LiquidityUtil.settlePosition(state, IERC20(address(0x1)), LONG, PRICE, 1e18);

        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(IERC20(address(0x1)), 2e18, 0, PRICE + 1);
        LiquidityUtil.settlePosition(state, IERC20(address(0x1)), LONG, PRICE + 2, 2e18);

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
        LiquidityUtil.settlePosition(state, IERC20(address(0x1)), SHORT, 3000 * 1e10, 1e18);

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
        LiquidityUtil.settlePosition(state, IERC20(address(0x1)), SHORT, 2000 * 1e10, 1e18);

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
        LiquidityUtil.settlePosition(state, IERC20(address(0x1)), SHORT, 3000 * 1e10, 20e18);

        assertEq(state.packedState.lpNetSize, 0);
        assertEq(state.packedState.lpEntryPrice, PRICE);
        assertEq(int256(uint256(state.packedState.lpLiquidity)), unrealizedPnL + 100e18);
    }

    function test_settlePosition_revertIf_sideIsShortAndLiquidityNotEnough() public {
        state.packedState.lpLiquidity = 10e18;
        state.packedState.lpNetSize = 20e18;
        state.packedState.lpEntryPrice = 1;

        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedIntToUint.selector, -9999999999999999999));
        LiquidityUtil.settlePosition(state, IERC20(address(0x1)), SHORT, type(uint64).max, 20e18);
    }

    function test_settlePosition_passIf_decreaseAllAndIncrease() public {
        state.packedState.lpLiquidity = 100e18;
        state.packedState.lpNetSize = 20e18;
        state.packedState.lpEntryPrice = PRICE;

        LiquidityUtil.settlePosition(state, IERC20(address(0x1)), SHORT, 3000 * 1e10, 20e18);

        uint128 liquidityBefore = state.packedState.lpLiquidity;

        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(IERC20(address(0x1)), 30e18, 0, 3000 * 1e10);
        LiquidityUtil.settlePosition(state, IERC20(address(0x1)), LONG, 3000 * 1e10, 30e18);

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
        LiquidityUtil.settlePosition(state, IERC20(address(0x1)), LONG, _indexPrice, _sizeDelta);

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
        LiquidityUtil.settlePosition(state, IERC20(address(0x1)), SHORT, _indexPrice, _sizeDelta);

        assertEq(state.packedState.lpNetSize, _sizeBefore - _sizeDelta);
        assertEq(state.packedState.lpEntryPrice, _entryPrice);
        assertEq(int256(uint256((state.packedState.lpLiquidity))), unrealizedPnL + int256(uint256(_liquidity)));
    }

    function test_reviseLiquidityPnL_previousSettledPriceIsZero() public {
        state.previousSettledPrice = 0;
        state.accumulateScaledUSDPnL = 20000000;
        state.packedState.lpLiquidity = 100e18;

        uint128 lpLiquidityBefore = state.packedState.lpLiquidity;

        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityPnLRevised(market, PRICE, 12345678, 0);
        LiquidityUtil.reviseLiquidityPnL(state, market, PRICE, 12345678);

        assertEq(state.previousSettledPrice, PRICE);
        assertEq(state.accumulateScaledUSDPnL, 32345678);
        assertEq(state.packedState.lpLiquidity, lpLiquidityBefore);
    }

    function test_reviseLiquidityPnL_previousSettledPriceIsPositiveAndPriceHigher() public {
        state.previousSettledPrice = PRICE;
        state.accumulateScaledUSDPnL = 20000000e10;
        state.packedState.lpLiquidity = 100e18;

        uint128 lpLiquidityBefore = state.packedState.lpLiquidity;
        uint64 newPrice = (PRICE * 12) / 10;
        int256 revisedTokenPnL = -int256(
            Math.ceilDiv(
                uint256(newPrice - PRICE) * uint184(state.accumulateScaledUSDPnL),
                uint256(newPrice) * state.previousSettledPrice
            )
        );
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityPnLRevised(market, newPrice, 12345678e10, revisedTokenPnL);
        LiquidityUtil.reviseLiquidityPnL(state, market, newPrice, 12345678e10);

        assertEq(state.previousSettledPrice, newPrice);
        assertEq(state.accumulateScaledUSDPnL, 20000000e10 + 12345678e10);
        assertEq(state.packedState.lpLiquidity, uint256(int256(uint256(lpLiquidityBefore)) + revisedTokenPnL));
    }

    function test_reviseLiquidityPnL_previousSettledPriceIsPositiveAndPriceLower() public {
        state.previousSettledPrice = PRICE;
        state.accumulateScaledUSDPnL = 20000000e10;
        state.packedState.lpLiquidity = 100e18;

        uint128 lpLiquidityBefore = state.packedState.lpLiquidity;
        uint64 newPrice = PRICE / 2;
        int256 revisedTokenPnL = int256(
            (uint256(state.previousSettledPrice - newPrice) * uint184(state.accumulateScaledUSDPnL)) /
                (uint256(newPrice) * state.previousSettledPrice)
        );

        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityPnLRevised(market, newPrice, 12345678e10, revisedTokenPnL);
        LiquidityUtil.reviseLiquidityPnL(state, market, newPrice, 12345678e10);

        assertEq(state.previousSettledPrice, newPrice);
        assertEq(state.accumulateScaledUSDPnL, 20000000e10 + 12345678e10);
        assertEq(state.packedState.lpLiquidity, uint256(int256(uint256(lpLiquidityBefore)) + revisedTokenPnL));
    }

    function testFuzz_reviseLiquidityPnL(
        uint64 _previousSettledPrice,
        int184 _accumulateScaledUSDPnL,
        uint64 _indexPrice,
        int184 _scaledUSDPnL
    ) public {
        vm.assume(_previousSettledPrice > 0 && _indexPrice > 0);
        vm.assume(
            int256(_accumulateScaledUSDPnL) + _scaledUSDPnL >= type(int184).min &&
                int256(_accumulateScaledUSDPnL) + _scaledUSDPnL <= type(int184).max
        );

        state.previousSettledPrice = _previousSettledPrice;
        state.accumulateScaledUSDPnL = _accumulateScaledUSDPnL;

        int256 priceDiff = (int256(uint256(_previousSettledPrice)) - int256(uint256(_indexPrice))) *
            _accumulateScaledUSDPnL;
        int256 revisedTokenPnL = priceDiff >= 0
            ? priceDiff / int256(uint256(_indexPrice) * _previousSettledPrice)
            : -int256(Math.ceilDiv(uint256(-priceDiff), uint256(_indexPrice) * _previousSettledPrice));
        vm.assume(
            revisedTokenPnL > -int256(uint256(type(uint128).max)) &&
                revisedTokenPnL < int256(uint256(type(uint128).max))
        );
        if (revisedTokenPnL < 0) {
            state.packedState.lpLiquidity = uint128(uint256(-revisedTokenPnL));
        } else {
            state.packedState.lpLiquidity = uint128(type(uint128).max - uint256(revisedTokenPnL));
        }
        uint128 lpLiquidityBefore = state.packedState.lpLiquidity;
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityPnLRevised(market, _indexPrice, _scaledUSDPnL, revisedTokenPnL);
        LiquidityUtil.reviseLiquidityPnL(state, market, _indexPrice, _scaledUSDPnL);

        assertEq(state.previousSettledPrice, _indexPrice);
        assertEq(state.accumulateScaledUSDPnL, _accumulateScaledUSDPnL + _scaledUSDPnL);
        assertEq(state.packedState.lpLiquidity, uint256(int256(uint256(lpLiquidityBefore)) + revisedTokenPnL));
    }
}

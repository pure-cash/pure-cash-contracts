// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import "./BaseTest.t.sol";
import "../../contracts/core/interfaces/IMarketManager.sol";
import "../../contracts/libraries/PositionUtil.sol";
import "../../contracts/libraries/LiquidityUtil.sol";
import "../../contracts/core/LPToken.sol";
import "../../contracts/core/PUSD.sol";
import "../../contracts/test/MockPriceFeed.sol";
import {LONG, SHORT} from "../../contracts/types/Side.sol";
import {Math as _math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract PositionUtilTest is BaseTest {
    using SafeCast for *;

    address private constant account = address(0x111);
    address private constant receiver = address(0x222);
    address private constant feeReceiver = address(0x333);

    IMarketManager.State state;

    IERC20 market = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    ILPToken lpToken = LiquidityUtil.deployLPToken(market, "tLPT");
    IPUSD pusd = new PUSD();
    uint64 price = uint64(31681133113133);

    function setUp() public {
        cfg.minMintingRate = 0.2 * 1e7; // 0.2
        cfg.maxBurningRate = 0.9 * 1e7; // 0.9
    }

    function test_increasePosition_revertIf_sizeDeltaIsZeroAndPositionNotFound() public {
        PositionUtil.IncreasePositionParam memory param = PositionUtil.IncreasePositionParam({
            market: market,
            account: account,
            marginDelta: 100 * 1e18,
            sizeDelta: 0,
            minIndexPrice: price,
            maxIndexPrice: price
        });
        {
            assertEq(state.longPositions[account].size, 0);
        }

        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.PositionNotFound.selector, account));
        PositionUtil.increasePosition(state, cfg, param);
    }

    function test_increasePosition_revertIf_insufficientMargin() public {
        PositionUtil.IncreasePositionParam memory param = PositionUtil.IncreasePositionParam({
            market: market,
            account: account,
            marginDelta: cfg.minMarginPerPosition - 1,
            sizeDelta: 200 * 1e18,
            minIndexPrice: price,
            maxIndexPrice: price
        });
        {
            assertEq(state.longPositions[account].size, 0);
        }

        vm.expectRevert(IMarketErrors.InsufficientMargin.selector);
        PositionUtil.increasePosition(state, cfg, param);
    }

    function test_increasePosition_revertIf_sizeExceedsMaxSize() public {
        state.packedState.lpEntryPrice = price;
        state.packedState.lpNetSize = 0;
        state.packedState.lpLiquidity = 399 * 1e18;

        PositionUtil.IncreasePositionParam memory param = PositionUtil.IncreasePositionParam({
            market: market,
            account: account,
            marginDelta: 100 * 1e18,
            sizeDelta: 200 * 1e18,
            minIndexPrice: price,
            maxIndexPrice: price
        });
        PositionUtil.increasePosition(state, cfg, param);

        {
            assertEq(state.longPositions[account].size, 200e18);
            assertEq(state.packedState.lpNetSize, 200e18);
        }

        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.SizeExceedsMaxSize.selector, 400 * 1e18, 399.07 * 1e18));
        PositionUtil.increasePosition(state, cfg, param);
    }

    function test_increasePosition_revertIf_sizeExceedsMaxSizePerPosition() public {
        state.packedState.lpEntryPrice = price;
        state.packedState.lpNetSize = 0;
        state.packedState.lpLiquidity = cfg.liquidityCap;
        cfg.maxSizeRatePerPosition = 0.5 * 1e7; // 0.5

        PositionUtil.IncreasePositionParam memory param = PositionUtil.IncreasePositionParam({
            market: market,
            account: account,
            marginDelta: 500000e18 + 1,
            sizeDelta: 500000e18 + 1,
            minIndexPrice: price,
            maxIndexPrice: price
        });

        vm.expectRevert(
            abi.encodeWithSelector(IMarketErrors.SizeExceedsMaxSizePerPosition.selector, 500000e18 + 1, 500000e18)
        );
        PositionUtil.increasePosition(state, cfg, param);
    }

    function test_increasePosition_revertIf_leverageTooHigh() public {
        state.packedState.lpEntryPrice = price;
        state.packedState.lpNetSize = 0;
        state.packedState.lpLiquidity = 399 * 1e18;

        PositionUtil.IncreasePositionParam memory param = PositionUtil.IncreasePositionParam({
            market: market,
            account: account,
            marginDelta: 10 * 1e18,
            sizeDelta: 200 * 1e18,
            minIndexPrice: price,
            maxIndexPrice: price
        });

        vm.expectRevert(
            abi.encodeWithSelector(IMarketErrors.LeverageTooHigh.selector, 9.86 * 1e18, uint128(200e18), uint8(10))
        );
        PositionUtil.increasePosition(state, cfg, param);
    }

    function test_increasePosition_revertIf_marginRateTooHigh() public {
        state.packedState.lpEntryPrice = price;
        state.packedState.lpNetSize = 0;
        state.packedState.lpLiquidity = 399 * 1e18;
        PositionUtil.IncreasePositionParam memory param = PositionUtil.IncreasePositionParam({
            market: market,
            account: account,
            marginDelta: 10 * 1e18,
            sizeDelta: 50 * 1e18,
            minIndexPrice: price,
            maxIndexPrice: price
        });
        PositionUtil.increasePosition(state, cfg, param);
        param.minIndexPrice = price / 2;
        param.maxIndexPrice = price / 2;
        param.marginDelta = 0;
        param.sizeDelta = 40 * 1e18;

        vm.expectRevert(
            abi.encodeWithSelector(IMarketErrors.MarginRateTooHigh.selector, 9937000000000000000, 50663000000006976835)
        );
        PositionUtil.increasePosition(state, cfg, param);
    }

    function test_increasePosition_passIf_firstIncrease() public {
        state.packedState.lpEntryPrice = price;
        state.packedState.lpNetSize = 0;
        state.packedState.lpLiquidity = 399 * 1e18;

        uint128 protocolFeeBefore = state.protocolFee;
        IMarketManager.PackedState memory packedStateBefore = state.packedState;

        PositionUtil.IncreasePositionParam memory param = PositionUtil.IncreasePositionParam({
            market: market,
            account: account,
            marginDelta: 100e18,
            sizeDelta: 200e18,
            minIndexPrice: price,
            maxIndexPrice: price
        });

        uint64 nextTimestamp = block.timestamp.toUint64() + 10;
        vm.warp(nextTimestamp);

        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(market, int256(uint256(param.sizeDelta)), 0, price);
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreased(market, 0.07 * 1e18);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByTradingFee(market, 0.07 * 1e18);
        vm.expectEmit();
        emit IMarketPosition.PositionIncreased(
            param.market,
            param.account,
            param.marginDelta,
            99.86 * 1e18,
            param.sizeDelta,
            price,
            price,
            0.14 * 1e18,
            0
        );

        uint160 spreadGot = PositionUtil.increasePosition(state, cfg, param);

        {
            assertEq(spreadGot, 0);
            assertEq(state.protocolFee, protocolFeeBefore + 0.07 * 1e18);
            assertEq(state.packedState.spreadFactorX96, 15845632502852867518708790067200000000000000000000);
            assertEq(state.packedState.lastTradingTimestamp, nextTimestamp);
            assertEq(state.packedState.lpNetSize, packedStateBefore.lpNetSize + param.sizeDelta);
            assertEq(state.packedState.lpEntryPrice, price);
            assertEq(state.packedState.lpLiquidity, packedStateBefore.lpLiquidity + 0.07 * 1e18);
            assertEq(state.packedState.longSize, packedStateBefore.longSize + param.sizeDelta);
            IMarketManager.Position memory position = state.longPositions[param.account];
            assertEq(position.size, param.sizeDelta);
            assertEq(position.margin, 99.86 * 1e18);
            assertEq(position.entryPrice, price);
        }
    }

    function test_increasePosition_passIf_notFirstIncrease() public {
        state.packedState.lpEntryPrice = price;
        state.packedState.lpNetSize = 0;
        state.packedState.lpLiquidity = 399 * 1e18;

        PositionUtil.IncreasePositionParam memory param = PositionUtil.IncreasePositionParam({
            market: market,
            account: account,
            marginDelta: 100e18,
            sizeDelta: 100e18,
            minIndexPrice: price,
            maxIndexPrice: price
        });
        PositionUtil.increasePosition(state, cfg, param);

        uint128 protocolFeeBefore = state.protocolFee;
        IMarketManager.PackedState memory packedStateBefore = state.packedState;
        IMarketManager.Position memory positionBefore = state.longPositions[param.account];

        uint64 newPrice = (price * 13) / 10;
        {
            assertEq(packedStateBefore.longSize, param.sizeDelta);
            param.minIndexPrice = newPrice;
            param.maxIndexPrice = newPrice;
        }

        uint64 nextTimestamp = block.timestamp.toUint64() + 10;
        vm.warp(nextTimestamp);

        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(market, int256(uint256(param.sizeDelta)), 0, 36433303080102);
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreased(market, 0.035 * 1e18);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByTradingFee(market, 0.035 * 1e18);
        vm.expectEmit();
        emit IMarketPosition.PositionIncreased(
            param.market,
            param.account,
            param.marginDelta,
            199.86 * 1e18,
            param.sizeDelta,
            newPrice,
            36433303080103,
            0.07 * 1e18,
            0
        );

        uint160 spreadGot = PositionUtil.increasePosition(state, cfg, param);

        {
            assertEq(spreadGot, 0);
            assertEq(state.protocolFee, protocolFeeBefore + 0.035 * 1e18);
            assertEq(state.packedState.spreadFactorX96, 15834628591392553027376353407431111111111111111112);
            assertEq(state.packedState.lastTradingTimestamp, nextTimestamp);
            assertEq(state.packedState.lpNetSize, packedStateBefore.lpNetSize + param.sizeDelta);
            assertEq(state.packedState.lpEntryPrice, 36433303080102);
            assertEq(state.packedState.lpLiquidity, packedStateBefore.lpLiquidity + 0.035 * 1e18);
            assertEq(state.packedState.longSize, packedStateBefore.longSize + param.sizeDelta);
            IMarketManager.Position memory position = state.longPositions[param.account];
            assertEq(position.size, positionBefore.size + param.sizeDelta);
            assertEq(position.margin, 199.86 * 1e18);
            assertEq(position.entryPrice, 36433303080103);
        }
    }

    function test_increasePosition_passIf_spreadIsPositive_distributeSpread() public {
        state.packedState.lpEntryPrice = price;
        state.packedState.lpNetSize = 0;
        state.packedState.lpLiquidity = 399 * 1e18;

        PositionUtil.IncreasePositionParam memory param = PositionUtil.IncreasePositionParam({
            market: market,
            account: account,
            marginDelta: 100 * 1e18,
            sizeDelta: 100 * 1e18,
            minIndexPrice: price,
            maxIndexPrice: price
        });
        PositionUtil.increasePosition(state, cfg, param);

        vm.warp(block.timestamp + 7200 seconds);
        PositionUtil.decreasePosition(
            state,
            cfg,
            PositionUtil.DecreasePositionParam({
                market: market,
                account: account,
                marginDelta: 50 * 1e18,
                sizeDelta: 50 * 1e18,
                minIndexPrice: price,
                maxIndexPrice: price,
                receiver: receiver
            })
        );

        {
            assertLt(state.packedState.spreadFactorX96, 0);
        }

        uint128 protocolFeeBefore = state.protocolFee;
        uint256 stabilityFundBefore = state.globalStabilityFund;
        IMarketManager.PackedState memory packedStateBefore = state.packedState;
        IMarketManager.Position memory positionBefore = state.longPositions[param.account];

        uint64 newPrice = (price * 13) / 10;
        {
            assertEq(packedStateBefore.longSize, 50 * 1e18);
            param.maxIndexPrice = newPrice;
            param.minIndexPrice = newPrice;
        }

        uint64 nextTimestamp = block.timestamp.toUint64() + 10;
        vm.warp(nextTimestamp);

        vm.expectEmit();
        emit IMarketManager.GlobalStabilityFundIncreasedBySpread(market, 4993055555555556);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(market, int256(uint256(param.sizeDelta)), 0, 38017359735759);
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreased(market, 0.035 * 1e18);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByTradingFee(market, 0.035 * 1e18);
        vm.expectEmit();
        emit IMarketPosition.PositionIncreased(
            param.market,
            param.account,
            param.marginDelta,
            149820006944444444444,
            param.sizeDelta,
            newPrice,
            38017359735759,
            0.07 * 1e18,
            4993055555555556
        );

        uint160 spreadGot = PositionUtil.increasePosition(state, cfg, param);

        {
            assertEq(spreadGot, 4993055555555556);
            assertEq(state.protocolFee, protocolFeeBefore + 0.035 * 1e18);
            assertEq(state.packedState.spreadFactorX96, 3966910081443374125343415846684444444444444444444);
            assertEq(state.packedState.lastTradingTimestamp, nextTimestamp);
            assertEq(state.packedState.lpNetSize, packedStateBefore.lpNetSize + param.sizeDelta);
            assertEq(state.packedState.lpEntryPrice, 38017359735759);
            assertEq(state.packedState.lpLiquidity, packedStateBefore.lpLiquidity + 0.035 * 1e18);
            assertEq(state.packedState.longSize, packedStateBefore.longSize + param.sizeDelta);
            IMarketManager.Position memory position = state.longPositions[param.account];
            assertEq(position.size, positionBefore.size + param.sizeDelta);
            assertEq(position.margin, 149820006944444444444);
            assertEq(position.entryPrice, 38017359735759);
            assertEq(state.globalStabilityFund, stabilityFundBefore + 4993055555555556);
        }
    }

    function _prepareDecreasePositionState() private {
        state.packedState.lpEntryPrice = price;
        state.packedState.lpNetSize = 0;
        state.packedState.lpLiquidity = 399 * 1e18;

        PositionUtil.IncreasePositionParam memory param = PositionUtil.IncreasePositionParam({
            market: market,
            account: account,
            marginDelta: 100 * 1e18,
            sizeDelta: 200 * 1e18,
            minIndexPrice: price,
            maxIndexPrice: price
        });
        PositionUtil.increasePosition(state, cfg, param);
    }

    function test_decreasePosition_revertIf_positionNotFound() public {
        PositionUtil.DecreasePositionParam memory param = PositionUtil.DecreasePositionParam({
            market: market,
            account: account,
            marginDelta: 100 * 1e18,
            sizeDelta: 0,
            minIndexPrice: price,
            maxIndexPrice: price,
            receiver: receiver
        });
        {
            assertEq(state.longPositions[account].size, 0);
        }

        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.PositionNotFound.selector, account));
        PositionUtil.decreasePosition(state, cfg, param);
    }

    function test_decreasePosition_revertIf_insufficientMargin() public {
        _prepareDecreasePositionState();

        PositionUtil.DecreasePositionParam memory param = PositionUtil.DecreasePositionParam({
            market: market,
            account: account,
            marginDelta: 110 * 1e18,
            sizeDelta: 0,
            minIndexPrice: price,
            maxIndexPrice: price,
            receiver: receiver
        });
        vm.expectRevert(IMarketErrors.InsufficientMargin.selector);
        PositionUtil.decreasePosition(state, cfg, param);
    }

    function test_decreasePosition_revertIf_insufficientSizeToDecrease_liquidityBufferModuleEnabled() public {
        _prepareDecreasePositionState();

        PositionUtil.DecreasePositionParam memory param = PositionUtil.DecreasePositionParam({
            market: market,
            account: account,
            marginDelta: 0,
            sizeDelta: 300 * 1e18,
            minIndexPrice: price,
            maxIndexPrice: price,
            receiver: receiver
        });
        vm.expectRevert(
            abi.encodeWithSelector(IMarketErrors.InsufficientSizeToDecrease.selector, 300 * 1e18, 200 * 1e18)
        );
        PositionUtil.decreasePosition(state, cfg, param);
    }

    function test_decreasePosition_revertIf_insufficientSizeToDecrease_liquidityBufferModuleDisabled() public {
        _prepareDecreasePositionState();
        state.packedState.lpNetSize = 99 * 1e18;
        cfg.liquidityBufferModuleEnabled = false;

        PositionUtil.DecreasePositionParam memory param = PositionUtil.DecreasePositionParam({
            market: market,
            account: account,
            marginDelta: 0,
            sizeDelta: 100 * 1e18,
            minIndexPrice: price,
            maxIndexPrice: price,
            receiver: receiver
        });
        vm.expectRevert(
            abi.encodeWithSelector(IMarketErrors.InsufficientSizeToDecrease.selector, 100 * 1e18, 99 * 1e18)
        );
        PositionUtil.decreasePosition(state, cfg, param);
    }

    function test_decreasePosition_revertIf_leverageTooHigh() public {
        _prepareDecreasePositionState();

        PositionUtil.DecreasePositionParam memory param = PositionUtil.DecreasePositionParam({
            market: market,
            account: account,
            marginDelta: 90e18,
            sizeDelta: 0,
            minIndexPrice: price,
            maxIndexPrice: price,
            receiver: receiver
        });
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.LeverageTooHigh.selector, 9.86 * 1e18, 200 * 1e18, 10));
        PositionUtil.decreasePosition(state, cfg, param);
    }

    function test_decreasePosition_revertIf_marginRateTooHigh() public {
        _prepareDecreasePositionState();
        PositionUtil.DecreasePositionParam memory param = PositionUtil.DecreasePositionParam({
            market: market,
            account: account,
            marginDelta: 20e18,
            sizeDelta: 110e18,
            minIndexPrice: (price * 10) / 15,
            maxIndexPrice: price,
            receiver: receiver
        });

        vm.expectRevert(
            abi.encodeWithSelector(IMarketErrors.MarginRateTooHigh.selector, 24722499999997394102, 45639500000002140620)
        );
        PositionUtil.decreasePosition(state, cfg, param);
    }

    function test_decreasePosition_passIf_onlySomeSizeDelta() public {
        _prepareDecreasePositionState();

        uint64 newPrice = ((price * 12) / 10);
        PositionUtil.DecreasePositionParam memory param = PositionUtil.DecreasePositionParam({
            market: market,
            account: account,
            marginDelta: 0,
            sizeDelta: 50e18,
            minIndexPrice: newPrice,
            maxIndexPrice: newPrice,
            receiver: receiver
        });

        uint128 protocolFeeBefore = state.protocolFee;
        uint256 stabilityFundBefore = state.globalStabilityFund;
        IMarketManager.PackedState memory packedStateBefore = state.packedState;
        IMarketManager.Position memory positionBefore = state.longPositions[param.account];

        vm.expectEmit();
        emit IMarketManager.GlobalStabilityFundIncreasedBySpread(market, 10000000000000001);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(
            market,
            -int256(uint256(param.sizeDelta)),
            -8333333333332675740,
            packedStateBefore.lpEntryPrice
        );
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreased(market, 14583333333333563);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByTradingFee(market, 14583333333333564);
        vm.expectEmit();
        emit IMarketPosition.PositionDecreased(
            param.market,
            param.account,
            param.marginDelta,
            108154166666666008611,
            param.sizeDelta,
            newPrice,
            8333333333332675739,
            29166666666667127,
            10000000000000001,
            receiver
        );
        (uint128 spreadGot, uint128 adjustedMarginDeltaGot) = PositionUtil.decreasePosition(state, cfg, param);

        {
            assertEq(spreadGot, 10000000000000001);
            assertEq(adjustedMarginDeltaGot, param.marginDelta);
            assertEq(state.globalStabilityFund, stabilityFundBefore + 10000000000000001);
            assertEq(state.protocolFee, protocolFeeBefore + 14583333333333563);
            assertEq(state.packedState.lpNetSize, packedStateBefore.lpNetSize - param.sizeDelta);
            assertEq(state.packedState.lpEntryPrice, packedStateBefore.lpEntryPrice);
            assertEq(
                state.packedState.lpLiquidity,
                packedStateBefore.lpLiquidity + 14583333333333564 - 8333333333332675740
            );
            assertEq(state.packedState.longSize, packedStateBefore.longSize - param.sizeDelta);
            IMarketManager.Position memory position = state.longPositions[param.account];
            assertEq(position.size, positionBefore.size - param.sizeDelta);
            assertEq(
                position.margin,
                positionBefore.margin + 8333333333332675739 - 29166666666667127 - 10000000000000001
            );
            assertEq(position.entryPrice, positionBefore.entryPrice);
        }
    }

    function test_decreasePosition_passIf_onlyAllSizeDelta() public {
        _prepareDecreasePositionState();

        uint64 newPrice = ((price * 12) / 10);
        PositionUtil.DecreasePositionParam memory param = PositionUtil.DecreasePositionParam({
            market: market,
            account: account,
            marginDelta: 0,
            sizeDelta: 200e18,
            minIndexPrice: newPrice,
            maxIndexPrice: newPrice,
            receiver: receiver
        });

        uint128 protocolFeeBefore = state.protocolFee;
        uint256 stabilityFundBefore = state.globalStabilityFund;
        IMarketManager.PackedState memory packedStateBefore = state.packedState;
        IMarketManager.Position memory positionBefore = state.longPositions[param.account];

        vm.expectEmit();
        emit IMarketManager.GlobalStabilityFundIncreasedBySpread(market, 40000000000000001);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(
            market,
            -int256(uint256(param.sizeDelta)),
            -33333333333330702957,
            packedStateBefore.lpEntryPrice
        );
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreased(market, 58333333333334254);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByTradingFee(market, 58333333333334254);
        vm.expectEmit();
        emit IMarketPosition.PositionDecreased(
            param.market,
            param.account,
            133036666666664034447,
            0,
            param.sizeDelta,
            newPrice,
            33333333333330702956,
            116666666666668508,
            40000000000000001,
            receiver
        );
        (uint160 spreadGot, uint128 adjustedMarginDeltaGot) = PositionUtil.decreasePosition(state, cfg, param);

        {
            assertEq(spreadGot, 40000000000000001);
            assertEq(
                adjustedMarginDeltaGot,
                positionBefore.margin + 33333333333330702956 - 116666666666668508 - 40000000000000001
            );
            assertEq(state.globalStabilityFund, stabilityFundBefore + 40000000000000001);
            assertEq(state.protocolFee, protocolFeeBefore + 58333333333334254);
            assertEq(state.packedState.lpNetSize, packedStateBefore.lpNetSize - param.sizeDelta);
            assertEq(state.packedState.lpEntryPrice, packedStateBefore.lpEntryPrice);
            assertEq(
                state.packedState.lpLiquidity,
                packedStateBefore.lpLiquidity + 58333333333334254 - 33333333333330702957
            );
            assertEq(state.packedState.longSize, packedStateBefore.longSize - param.sizeDelta);
            IMarketManager.Position memory position = state.longPositions[param.account];
            assertEq(position.size, 0);
        }
    }

    function test_decreasePosition_passIf_onlySomeMarginDelta() public {
        _prepareDecreasePositionState();

        uint64 newPrice = ((price * 12) / 10);
        PositionUtil.DecreasePositionParam memory param = PositionUtil.DecreasePositionParam({
            market: market,
            account: account,
            marginDelta: 50e18,
            sizeDelta: 0,
            minIndexPrice: newPrice,
            maxIndexPrice: newPrice,
            receiver: receiver
        });

        uint128 protocolFeeBefore = state.protocolFee;
        uint256 stabilityFundBefore = state.globalStabilityFund;
        IMarketManager.PackedState memory packedStateBefore = state.packedState;
        IMarketManager.Position memory positionBefore = state.longPositions[param.account];

        uint96 marginAfter = uint96(uint256(int256(int96(positionBefore.margin - param.marginDelta))));

        vm.expectEmit();
        emit IMarketPosition.PositionDecreased(
            param.market,
            param.account,
            param.marginDelta,
            marginAfter,
            0,
            newPrice,
            0,
            0,
            0,
            receiver
        );
        (uint96 spreadGot, uint96 adjustedMarginDeltaGot) = PositionUtil.decreasePosition(state, cfg, param);

        {
            assertEq(spreadGot, 0);
            assertEq(adjustedMarginDeltaGot, param.marginDelta);
            assertEq(state.globalStabilityFund, stabilityFundBefore);
            assertEq(state.protocolFee, protocolFeeBefore);
            assertEq(state.packedState.lpNetSize, packedStateBefore.lpNetSize);
            assertEq(state.packedState.lpEntryPrice, packedStateBefore.lpEntryPrice);
            assertEq(state.packedState.lpLiquidity, packedStateBefore.lpLiquidity);
            assertEq(state.packedState.longSize, packedStateBefore.longSize);
            IMarketManager.Position memory position = state.longPositions[param.account];
            assertEq(position.size, positionBefore.size);
            assertEq(position.margin, marginAfter);
            assertEq(position.entryPrice, positionBefore.entryPrice);
        }
    }

    function test_decreasePosition_passIf_someSizeDeltaAndSomeMarginDelta() public {
        _prepareDecreasePositionState();

        uint64 newPrice = ((price * 10) / 12);
        PositionUtil.DecreasePositionParam memory param = PositionUtil.DecreasePositionParam({
            market: market,
            account: account,
            marginDelta: 50e18,
            sizeDelta: 100e18,
            minIndexPrice: newPrice,
            maxIndexPrice: newPrice,
            receiver: receiver
        });

        uint128 protocolFeeBefore = state.protocolFee;
        uint256 stabilityFundBefore = state.globalStabilityFund;
        IMarketManager.PackedState memory packedStateBefore = state.packedState;
        IMarketManager.Position memory positionBefore = state.longPositions[param.account];

        vm.expectEmit();
        emit IMarketManager.GlobalStabilityFundIncreasedBySpread(market, 20000000000000001);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(
            market,
            -int256(uint256(param.sizeDelta)),
            20000000000000757548,
            packedStateBefore.lpEntryPrice
        );
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreased(market, 42000000000000265);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByTradingFee(market, 42000000000000266);
        vm.expectEmit();
        emit IMarketPosition.PositionDecreased(
            param.market,
            param.account,
            param.marginDelta,
            29755999999999241919,
            param.sizeDelta,
            newPrice,
            -20000000000000757549,
            84000000000000531,
            20000000000000001,
            receiver
        );
        (uint128 spreadGot, uint128 adjustedMarginDeltaGot) = PositionUtil.decreasePosition(state, cfg, param);

        {
            assertEq(spreadGot, 20000000000000001);
            assertEq(adjustedMarginDeltaGot, param.marginDelta);
            assertEq(state.globalStabilityFund, stabilityFundBefore + 20000000000000001);
            assertEq(state.protocolFee, protocolFeeBefore + 42000000000000265);
            assertEq(state.packedState.lpNetSize, packedStateBefore.lpNetSize - param.sizeDelta);
            assertEq(state.packedState.lpEntryPrice, packedStateBefore.lpEntryPrice);
            assertEq(
                state.packedState.lpLiquidity,
                packedStateBefore.lpLiquidity + 42000000000000266 + 20000000000000757548
            );
            assertEq(state.packedState.longSize, packedStateBefore.longSize - param.sizeDelta);
            IMarketManager.Position memory position = state.longPositions[param.account];
            assertEq(position.size, positionBefore.size - param.sizeDelta);
            assertEq(
                position.margin,
                positionBefore.margin - param.marginDelta - 20000000000000757549 - 84000000000000531 - 20000000000000001
            );
            assertEq(position.entryPrice, positionBefore.entryPrice);
        }
    }

    function test_decreasePosition_passIf_onlyAllSizeDeltaAndLiquidityBufferModuleBurnReached() public {
        _prepareDecreasePositionState();
        state.packedState.lpNetSize = 180 * 1e18;
        state.globalPUSDPosition.entryPrice = price;
        state.globalPUSDPosition.size = 200 * 1e18;
        state.globalPUSDPosition.totalSupply = 600000 * 1e6;

        uint64 newPrice = ((price * 8) / 10);
        PositionUtil.DecreasePositionParam memory param = PositionUtil.DecreasePositionParam({
            market: market,
            account: account,
            marginDelta: 0,
            sizeDelta: 200e18,
            minIndexPrice: newPrice,
            maxIndexPrice: newPrice,
            receiver: receiver
        });

        uint128 protocolFeeBefore = state.protocolFee;
        uint256 stabilityFundBefore = state.globalStabilityFund;
        IMarketManager.PackedState memory packedStateBefore = state.packedState;
        IMarketManager.Position memory positionBefore = state.longPositions[param.account];

        vm.expectEmit();
        emit IMarketManager.GlobalStabilityFundIncreasedBySpread(market, 40000000000000001);

        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(market, 20 * 1e18, 0, 31047510450870);
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreased(market, 8750000000000138);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByTradingFee(market, 8750000000000138);
        vm.expectEmit();
        emit IPUSDManager.PUSDPositionDecreased(
            market,
            address(this),
            20 * 1e18,
            newPrice,
            60000000000,
            24982500000000394280,
            5000000000000394556,
            17500000000000276,
            0
        );
        vm.expectEmit();
        emit IMarketManager.LiquidityBufferModuleDebtIncreased(
            param.market,
            param.account,
            60000000000,
            24982500000000394280
        );

        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(
            market,
            -int256(uint256(param.sizeDelta)),
            45000000000001183669,
            31047510450870
        );
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreased(market, 87500000000001381);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByTradingFee(market, 87500000000001381);
        vm.expectEmit();
        emit IMarketPosition.PositionDecreased(
            param.market,
            param.account,
            49644999999996051671,
            0,
            param.sizeDelta,
            newPrice,
            -50000000000003945566,
            175000000000002762,
            40000000000000001,
            receiver
        );
        (uint160 spreadGot, uint128 adjustedMarginDeltaGot) = PositionUtil.decreasePosition(state, cfg, param);

        {
            assertEq(spreadGot, 40000000000000001);
            assertEq(
                adjustedMarginDeltaGot,
                positionBefore.margin - 50000000000003945566 - 175000000000002762 - 40000000000000001
            );
            assertEq(state.globalStabilityFund, stabilityFundBefore + 40000000000000001);
            assertEq(state.protocolFee, protocolFeeBefore + 8750000000000138 + 87500000000001381);
            assertEq(state.packedState.lpNetSize, 0);
            assertEq(state.packedState.lpEntryPrice, 31047510450870);
            assertEq(
                state.packedState.lpLiquidity,
                packedStateBefore.lpLiquidity + 8750000000000138 + 87500000000001381 + 45000000000001183669
            );
            assertEq(state.packedState.longSize, packedStateBefore.longSize - param.sizeDelta);
            IMarketManager.Position memory position = state.longPositions[param.account];
            assertEq(position.size, 0);
        }
    }

    function test_decreasePosition_passIf_someSizeDeltaAndSomeMarginDeltaAndLiquidityBufferModuleBurnReached() public {
        _prepareDecreasePositionState();
        state.packedState.lpNetSize = 80 * 1e18;
        state.globalPUSDPosition.entryPrice = price;
        state.globalPUSDPosition.size = 200 * 1e18;
        state.globalPUSDPosition.totalSupply = 600000 * 1e6;

        uint64 newPrice = ((price * 8) / 10);
        PositionUtil.DecreasePositionParam memory param = PositionUtil.DecreasePositionParam({
            market: market,
            account: account,
            marginDelta: 10e18,
            sizeDelta: 100e18,
            minIndexPrice: newPrice,
            maxIndexPrice: newPrice,
            receiver: receiver
        });

        uint128 protocolFeeBefore = state.protocolFee;
        uint256 stabilityFundBefore = state.globalStabilityFund;
        IMarketManager.PackedState memory packedStateBefore = state.packedState;
        IMarketManager.Position memory positionBefore = state.longPositions[param.account];

        vm.expectEmit();
        emit IMarketManager.GlobalStabilityFundIncreasedBySpread(market, 20000000000000001);

        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(market, 20 * 1e18, 0, 30413887788607);
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreased(market, 8750000000000138);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByTradingFee(market, 8750000000000138);
        vm.expectEmit();
        emit IPUSDManager.PUSDPositionDecreased(
            market,
            address(this),
            20 * 1e18,
            newPrice,
            60000000000,
            24982500000000394280,
            5000000000000394556,
            17500000000000276,
            0
        );
        vm.expectEmit();
        emit IMarketManager.LiquidityBufferModuleDebtIncreased(
            param.market,
            param.account,
            60000000000,
            24982500000000394280
        );

        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(
            market,
            -int256(uint256(param.sizeDelta)),
            19999999999999210886,
            30413887788607
        );
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreased(market, 43750000000000690);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByTradingFee(market, 43750000000000691);
        vm.expectEmit();
        emit IMarketPosition.PositionDecreased(
            param.market,
            param.account,
            param.marginDelta,
            64752499999998025835,
            param.sizeDelta,
            newPrice,
            -25000000000001972783,
            87500000000001381,
            20000000000000001,
            receiver
        );
        (uint128 spreadGot, uint128 adjustedMarginDeltaGot) = PositionUtil.decreasePosition(state, cfg, param);

        {
            assertEq(spreadGot, 20000000000000001);
            assertEq(adjustedMarginDeltaGot, param.marginDelta);
            assertEq(state.globalStabilityFund, stabilityFundBefore + 20000000000000001);
            assertEq(state.protocolFee, protocolFeeBefore + 8750000000000138 + 43750000000000690);
            assertEq(state.packedState.lpNetSize, 0);
            assertEq(state.packedState.lpEntryPrice, 30413887788607);
            assertEq(
                state.packedState.lpLiquidity,
                packedStateBefore.lpLiquidity + 8750000000000138 + 43750000000000691 + 19999999999999210886
            );
            assertEq(state.packedState.longSize, packedStateBefore.longSize - param.sizeDelta);
            IMarketManager.Position memory position = state.longPositions[param.account];
            assertEq(position.size, positionBefore.size - param.sizeDelta);
            assertEq(
                position.margin,
                positionBefore.margin - param.marginDelta - 25000000000001972783 - 87500000000001381 - 20000000000000001
            );
            assertEq(position.entryPrice, positionBefore.entryPrice);
        }
    }

    function _prepareLiquidatePositionState() private {
        state.packedState.lpEntryPrice = price;
        state.packedState.lpNetSize = 0;
        state.packedState.lpLiquidity = 399 * 1e18;
        cfg.maxLeveragePerPosition = 200;

        PositionUtil.IncreasePositionParam memory param = PositionUtil.IncreasePositionParam({
            market: market,
            account: account,
            marginDelta: 2 * 1e18,
            sizeDelta: 200 * 1e18,
            minIndexPrice: price,
            maxIndexPrice: price
        });
        PositionUtil.increasePosition(state, cfg, param);
    }

    function test_liquidatePosition_revertIf_positionNotFound() public {
        uint64 newPrice = ((price * 3) / 4);
        PositionUtil.LiquidatePositionParam memory param = PositionUtil.LiquidatePositionParam({
            market: market,
            account: account,
            minIndexPrice: newPrice,
            maxIndexPrice: newPrice,
            feeReceiver: feeReceiver
        });

        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.PositionNotFound.selector, account));
        PositionUtil.liquidatePosition(state, cfg, param);
    }

    function test_liquidatePosition_revertIf_marginRateTooLow() public {
        _prepareLiquidatePositionState();
        uint64 newPrice = ((price * 999) / 1000);
        PositionUtil.LiquidatePositionParam memory param = PositionUtil.LiquidatePositionParam({
            market: market,
            account: account,
            minIndexPrice: newPrice,
            maxIndexPrice: newPrice,
            feeReceiver: feeReceiver
        });

        vm.expectRevert(
            abi.encodeWithSelector(IMarketErrors.MarginRateTooLow.selector, 1.86 * 1e18, 1146141141146651170)
        );
        PositionUtil.liquidatePosition(state, cfg, param);
    }

    function test_liquidatePosition_pass() public {
        _prepareLiquidatePositionState();
        uint64 newPrice = ((price * 3) / 4);
        PositionUtil.LiquidatePositionParam memory param = PositionUtil.LiquidatePositionParam({
            market: market,
            account: account,
            minIndexPrice: newPrice,
            maxIndexPrice: newPrice,
            feeReceiver: feeReceiver
        });

        uint128 protocolFeeBefore = state.protocolFee;
        uint256 stabilityFundBefore = state.globalStabilityFund;
        IMarketManager.PackedState memory packedStateBefore = state.packedState;
        IMarketManager.Position memory positionBefore = state.longPositions[param.account];

        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(
            param.market,
            -int256(uint256(positionBefore.size)),
            910719617796507662,
            packedStateBefore.lpEntryPrice
        );
        vm.expectEmit();
        emit IMarketManager.GlobalStabilityFundIncreasedByLiquidation(param.market, 803642878471186030);
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreased(param.market, 70318751866228777);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByTradingFee(param.market, 70318751866228778);
        vm.expectEmit();
        emit IMarketPosition.PositionLiquidated(
            param.market,
            msg.sender,
            param.account,
            positionBefore.size,
            param.minIndexPrice,
            31537523904550,
            140637503732457555,
            803642878471186030,
            cfg.liquidationExecutionFee,
            param.feeReceiver
        );
        uint64 liquidationExecutionFeeGot = PositionUtil.liquidatePosition(state, cfg, param);

        {
            assertEq(liquidationExecutionFeeGot, cfg.liquidationExecutionFee);
            assertEq(state.globalStabilityFund, stabilityFundBefore + 803642878471186030);
            assertEq(state.protocolFee, protocolFeeBefore + 70318751866228777);
            assertEq(state.packedState.lpNetSize, packedStateBefore.lpNetSize - positionBefore.size);
            assertEq(state.packedState.lpEntryPrice, packedStateBefore.lpEntryPrice);
            assertEq(
                state.packedState.lpLiquidity,
                packedStateBefore.lpLiquidity + 70318751866228778 + 910719617796507662
            );
            assertEq(state.packedState.longSize, packedStateBefore.longSize - positionBefore.size);
            IMarketManager.Position memory position = state.longPositions[param.account];
            assertEq(position.size, 0);
        }
    }

    function test_liquidatePosition_passIf_liquidityBufferModuleBurnReached() public {
        _prepareLiquidatePositionState();
        state.packedState.lpNetSize = 180 * 1e18;
        state.globalPUSDPosition.entryPrice = price;
        state.globalPUSDPosition.size = 200 * 1e18;
        state.globalPUSDPosition.totalSupply = 600000 * 1e6;

        uint64 newPrice = ((price * 3) / 4);
        PositionUtil.LiquidatePositionParam memory param = PositionUtil.LiquidatePositionParam({
            market: market,
            account: account,
            minIndexPrice: newPrice,
            maxIndexPrice: newPrice,
            feeReceiver: feeReceiver
        });

        uint128 protocolFeeBefore = state.protocolFee;
        uint256 stabilityFundBefore = state.globalStabilityFund;
        IMarketManager.PackedState memory packedStateBefore = state.packedState;
        IMarketManager.Position memory positionBefore = state.longPositions[param.account];

        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(market, 20 * 1e18, 0, 30889104785304);
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreased(market, 9333333333333627);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByTradingFee(market, 9333333333333628);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityPnLRevised(market, newPrice, 158405665565680000000000000000000, 0);
        vm.expectEmit();
        emit IPUSDManager.PUSDPositionDecreased(
            market,
            address(this),
            20 * 1e18,
            newPrice,
            60000000000,
            26648000000000841132,
            6666666666667508387,
            18666666666667255,
            0
        );
        vm.expectEmit();
        emit IMarketManager.LiquidityBufferModuleDebtIncreased(
            param.market,
            param.account,
            60000000000,
            26648000000000841132
        );

        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(
            param.market,
            -int256(uint256(positionBefore.size)),
            -4112048372652685645,
            30889104785304
        );
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityPnLRevised(
            market,
            31537523904550,
            -129683823849200000000000000000000,
            -1643898676222120072
        );
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityPnLRevised(market, 31537523904550, -28721841716600000000000000000000, 0);
        vm.expectEmit();
        emit IMarketManager.GlobalStabilityFundIncreasedByLiquidation(param.market, 803642878471186030);
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreased(param.market, 70318751866228777);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByTradingFee(param.market, 70318751866228778);
        vm.expectEmit();
        emit IMarketPosition.PositionLiquidated(
            param.market,
            msg.sender,
            param.account,
            positionBefore.size,
            param.minIndexPrice,
            31537523904550,
            140637503732457555,
            803642878471186030,
            cfg.liquidationExecutionFee,
            param.feeReceiver
        );
        uint64 liquidationExecutionFeeGot = PositionUtil.liquidatePosition(state, cfg, param);

        {
            assertEq(liquidationExecutionFeeGot, cfg.liquidationExecutionFee);
            assertEq(state.globalStabilityFund, stabilityFundBefore + 803642878471186030);
            assertEq(state.protocolFee, protocolFeeBefore + 9333333333333627 + 70318751866228777);
            assertEq(state.packedState.lpNetSize, 0);
            assertEq(state.packedState.lpEntryPrice, 30889104785304);
            assertEq(
                state.packedState.lpLiquidity,
                packedStateBefore.lpLiquidity +
                    9333333333333628 +
                    70318751866228778 -
                    4112048372652685645 -
                    1643898676222120072
            );
            assertEq(state.packedState.longSize, packedStateBefore.longSize - positionBefore.size);
            IMarketManager.Position memory position = state.longPositions[param.account];
            assertEq(position.size, 0);
        }
    }

    function testFuzz_calcLiquidationFee(
        uint96 size,
        uint64 entryPrice,
        uint64 indexPrice,
        uint24 liquidationFeeRate
    ) public {
        vm.assume(
            entryPrice > 0 &&
                indexPrice > 0 &&
                liquidationFeeRate <= Constants.BASIS_POINTS_DIVISOR &&
                (size == 0 || uint256(entryPrice) / indexPrice <= uint256(type(uint96).max) / size)
        );

        unchecked {
            uint256 want = Math.mulDiv(
                uint256(size) * liquidationFeeRate,
                entryPrice,
                uint256(indexPrice) * Constants.BASIS_POINTS_DIVISOR
            );
            if (want > type(uint96).max) {
                vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 96, want));
                PositionUtil.calcLiquidationFee(size, entryPrice, indexPrice, liquidationFeeRate);
            } else {
                uint96 input = PositionUtil.calcLiquidationFee(size, entryPrice, indexPrice, liquidationFeeRate);
                assertEq(input, want);
            }
        }
    }

    function testFuzz_calcMaintenanceMargin(
        uint96 size,
        uint64 entryPrice,
        uint64 indexPrice,
        uint24 liquidationFeeRate,
        uint24 tradingFeeRate,
        uint64 liquidationExecutionFee
    ) public pure {
        vm.assume(
            liquidationFeeRate <= Constants.BASIS_POINTS_DIVISOR &&
                tradingFeeRate <= Constants.BASIS_POINTS_DIVISOR &&
                indexPrice > 0 &&
                entryPrice / indexPrice <= type(uint96).max
        );

        uint256 input = PositionUtil.calcMaintenanceMargin(
            size,
            entryPrice,
            indexPrice,
            liquidationFeeRate,
            tradingFeeRate,
            liquidationExecutionFee
        );

        uint256 want = Math.mulDivUp(
            size,
            uint256(entryPrice) * (uint256(liquidationFeeRate) + tradingFeeRate),
            uint256(indexPrice) * Constants.BASIS_POINTS_DIVISOR
        );
        want += liquidationExecutionFee;

        assertEq(input, want);
    }

    function _test_refreshSpreadFactor(Side _side) private {
        int256 spreadFactorBeforeX96 = state.packedState.spreadFactorX96;
        uint64 lastTradingTimestampBefore = state.packedState.lastTradingTimestamp;

        (, int256 spreadFactorAfterX96) = SpreadUtil.calcSpread(
            cfg,
            SpreadUtil.CalcSpreadParam({
                side: _side,
                sizeDelta: 100 * 1e18,
                spreadFactorBeforeX96: spreadFactorBeforeX96,
                lastTradingTimestamp: lastTradingTimestampBefore
            })
        );

        vm.expectEmit();
        emit IMarketManager.SpreadFactorChanged(market, spreadFactorAfterX96);
        PositionUtil.refreshSpreadFactor(state.packedState, cfg, market, 100 * 1e18, _side);

        {
            assertEq(state.packedState.spreadFactorX96, spreadFactorAfterX96);
            assertEq(state.packedState.lastTradingTimestamp, uint64(block.timestamp));
        }
    }

    function test_refreshSpreadFactor_passIf_sideIsLong() public {
        _test_refreshSpreadFactor(LONG);
    }

    function test_refreshSpreadFactor_passIf_sideIsShort() public {
        _test_refreshSpreadFactor(SHORT);
    }

    function _test_distributeTradingFee(Math.Rounding _rounding) private {
        uint128 protocolFeeBefore = state.protocolFee;
        uint128 liquidityBefore = state.packedState.lpLiquidity;

        PositionUtil.DistributeFeeParam memory param = PositionUtil.DistributeFeeParam({
            market: market,
            size: 10000 * 1e18,
            entryPrice: price,
            indexPrice: (price * 12) / 10,
            rounding: _rounding,
            tradingFeeRate: cfg.tradingFeeRate,
            protocolFeeRate: cfg.protocolFeeRate
        });
        uint96 want = PositionUtil.calcTradingFee(param);
        uint96 protocolFee = uint96((uint256(want) * cfg.protocolFeeRate) / Constants.BASIS_POINTS_DIVISOR);
        uint96 liquidityFee = want - protocolFee;

        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreased(market, protocolFee);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByTradingFee(market, liquidityFee);

        uint96 got = PositionUtil.distributeTradingFee(state, param);
        {
            assertEq(got, want);
            assertEq(state.protocolFee, protocolFeeBefore + protocolFee);
            assertEq(state.packedState.lpLiquidity, liquidityBefore + liquidityFee);
        }
    }

    function test_distributeTradingFee_passIf_roundingUp() public {
        _test_distributeTradingFee(Math.Rounding.Up);
    }

    function test_distributeTradingFee_passIf_roundingDown() public {
        _test_distributeTradingFee(Math.Rounding.Down);
    }

    function testFuzz_calcTradingFee_roundUp(
        uint24 tradingFeeRate,
        uint96 size,
        uint64 entryPrice,
        uint64 indexPrice
    ) public view {
        vm.assume(tradingFeeRate <= Constants.BASIS_POINTS_DIVISOR && (entryPrice & indexPrice) > 0);
        vm.assume(
            (uint256(size) * tradingFeeRate) / (uint256(indexPrice) * Constants.BASIS_POINTS_DIVISOR) <
                type(uint96).max / entryPrice
        );
        uint96 input = PositionUtil.calcTradingFee(
            PositionUtil.DistributeFeeParam({
                market: market,
                size: size,
                entryPrice: entryPrice,
                indexPrice: indexPrice,
                rounding: Math.Rounding.Up,
                tradingFeeRate: tradingFeeRate,
                protocolFeeRate: 0
            })
        );
        uint256 want = Math.mulDivUp(
            (uint256(size) * tradingFeeRate),
            entryPrice,
            uint256(indexPrice) * Constants.BASIS_POINTS_DIVISOR
        );
        assertEq(input, want);
    }

    function testFuzz_calcTradingFee_roundDown(
        uint24 tradingFeeRate,
        uint96 size,
        uint64 entryPrice,
        uint64 indexPrice
    ) public view {
        vm.assume(tradingFeeRate <= Constants.BASIS_POINTS_DIVISOR && (entryPrice & indexPrice) > 0);
        vm.assume(
            (uint256(size) * tradingFeeRate) / (uint256(indexPrice) * Constants.BASIS_POINTS_DIVISOR) <
                type(uint96).max / entryPrice
        );
        uint96 input = PositionUtil.calcTradingFee(
            PositionUtil.DistributeFeeParam({
                market: market,
                size: size,
                entryPrice: entryPrice,
                indexPrice: indexPrice,
                rounding: Math.Rounding.Down,
                tradingFeeRate: tradingFeeRate,
                protocolFeeRate: 0
            })
        );
        uint256 want = Math.mulDiv(
            (uint256(size) * tradingFeeRate),
            entryPrice,
            uint256(indexPrice) * Constants.BASIS_POINTS_DIVISOR
        );
        assertEq(input, want);
    }

    function test_distributeSpread_pass() private {
        uint256 stabilityFundBefore = state.globalStabilityFund;

        vm.expectEmit();
        emit IMarketManager.GlobalStabilityFundIncreasedBySpread(market, 0.2 * 1e18);
        PositionUtil.distributeSpread(state, market, 0.2 * 1e18);
        {
            assertEq(state.globalStabilityFund, stabilityFundBefore + 0.2 * 1e18);
        }
    }

    function test_distributeLiquidationFee_pass() private {
        uint256 stabilityFundBefore = state.globalStabilityFund;

        vm.expectEmit();
        emit IMarketManager.GlobalStabilityFundIncreasedByLiquidation(market, 0.2 * 1e18);
        PositionUtil.distributeLiquidationFee(state, market, 0.2 * 1e18);
        {
            assertEq(state.globalStabilityFund, stabilityFundBefore + 0.2 * 1e18);
        }
    }

    function test_calcNextEntryPrice_passIf_sizeBeforeIsZeroAndSizeDeltaIsZero() public pure {
        uint64 got = PositionUtil.calcNextEntryPrice(LONG, 0, 1e10, 0, 2 * 1e10);
        assertEq(got, 2 * 1e10);

        got = PositionUtil.calcNextEntryPrice(SHORT, 0, 1e10, 0, 2 * 1e10);
        assertEq(got, 2 * 1e10);
    }

    function test_calcNextEntryPrice_passIf_sizeBeforeIsPositiveAndSizeDeltaIsZero() public pure {
        uint64 got = PositionUtil.calcNextEntryPrice(LONG, 1, 1900 * 1e10, 0, 2000 * 1e10);
        assertEq(got, 1900 * 1e10);

        got = PositionUtil.calcNextEntryPrice(SHORT, 1, 1900 * 1e10, 0, 2000 * 1e10);
        assertEq(got, 1900 * 1e10);
    }

    function test_calcNextEntryPrice_passIf_sizeBeforeIsZeroAndSizeDeltaIsPositive() public pure {
        uint64 got = PositionUtil.calcNextEntryPrice(LONG, 0, 1900 * 1e10, 1, 2000 * 1e10);
        assertEq(got, 2000 * 1e10);

        got = PositionUtil.calcNextEntryPrice(SHORT, 0, 1900 * 1e10, 1, 2000 * 1e10);
        assertEq(got, 2000 * 1e10);
    }

    function test_calcNextEntryPrice_passIf_sizeBeforeIsPositiveAndSizeDeltaIsPositive() public pure {
        uint64 got = PositionUtil.calcNextEntryPrice(LONG, 100, 1900 * 1e10, 200, 2000 * 1e10);
        uint256 want = Math.ceilDiv(uint256(100) * (1900 * 1e10) + uint256(200) * (2000 * 1e10), 300);
        assertEq(got, want);

        got = PositionUtil.calcNextEntryPrice(SHORT, 100, 1900 * 1e10, 200, 2000 * 1e10);
        want = (uint256(100) * (1900 * 1e10) + uint256(200) * (2000 * 1e10)) / 300;
        assertEq(got, want);
    }

    function testFuzz_calcNextEntryPrice(
        uint128 sizeBefore,
        uint64 entryPriceBefore,
        uint128 sizeDelta,
        uint64 tradePrice
    ) public pure {
        vm.assume(entryPriceBefore > 0 && tradePrice > 0);
        vm.assume(uint256(sizeBefore) * entryPriceBefore <= type(uint256).max - uint256(sizeDelta) * tradePrice);
        uint64 nextEntryPriceLong = PositionUtil.calcNextEntryPrice(
            LONG,
            sizeBefore,
            entryPriceBefore,
            sizeDelta,
            tradePrice
        );
        uint64 nextEntryPriceShort = PositionUtil.calcNextEntryPrice(
            SHORT,
            sizeBefore,
            entryPriceBefore,
            sizeDelta,
            tradePrice
        );
        {
            if (sizeBefore == 0) {
                assertEq(nextEntryPriceLong, tradePrice);
                assertEq(nextEntryPriceShort, tradePrice);
            } else if (sizeDelta == 0) {
                assertEq(nextEntryPriceLong, entryPriceBefore);
                assertEq(nextEntryPriceShort, entryPriceBefore);
            } else {
                uint256 wantLong = Math.ceilDiv(
                    uint256(sizeBefore) * entryPriceBefore + uint256(sizeDelta) * tradePrice,
                    uint256(sizeBefore) + sizeDelta
                );
                uint256 wantShort = (uint256(sizeBefore) * entryPriceBefore + uint256(sizeDelta) * tradePrice) /
                    (uint256(sizeBefore) + sizeDelta);
                assertEq(nextEntryPriceLong, wantLong);
                assertEq(nextEntryPriceShort, wantShort);
            }
        }
    }

    function test_calcDecimals6TokenValue_pass() public pure {
        uint64 value = PositionUtil.calcDecimals6TokenValue(1e18, 100.6666666666 * 1e10, 18, Math.Rounding.Up);
        assertEq(value, 100.666667 * 1e6);
        value = PositionUtil.calcDecimals6TokenValue(1e18, 100.6666666666 * 1e10, 18, Math.Rounding.Down);
        assertEq(value, 100.666666 * 1e6);
    }

    function testFuzz_calcDecimals6TokenValue(
        uint96 _marketTokenAmount,
        uint64 _indexPrice,
        uint8 _marketDecimals
    ) public pure {
        if (_marketDecimals > 18) _marketDecimals = 18;
        uint256 denominator = 10 ** (Constants.PRICE_DECIMALS - Constants.DECIMALS_6 + _marketDecimals);
        vm.assume(uint256(_marketTokenAmount) * _indexPrice < type(uint64).max * denominator);
        {
            uint256 value = Math.mulDiv(_marketTokenAmount, _indexPrice, denominator, Math.Rounding.Up);
            assertLe(value, type(uint64).max);
            assertEq(
                value,
                PositionUtil.calcDecimals6TokenValue(_marketTokenAmount, _indexPrice, _marketDecimals, Math.Rounding.Up)
            );
        }
        {
            uint256 value = Math.mulDiv(_marketTokenAmount, _indexPrice, denominator, Math.Rounding.Down);
            assertLe(value, type(uint64).max);
            assertEq(
                value,
                PositionUtil.calcDecimals6TokenValue(
                    _marketTokenAmount,
                    _indexPrice,
                    _marketDecimals,
                    Math.Rounding.Down
                )
            );
        }
    }

    function test_calcMarketTokenValue_pass() public pure {
        uint96 value = PositionUtil.calcMarketTokenValue(100.666667 * 1e6, 100.6666666666 * 1e10, 18);
        assertEq(
            value,
            (uint256(100.666667 * 1e6) * (10 ** uint256(Constants.PRICE_DECIMALS - Constants.DECIMALS_6 + 18))) /
                (100.6666666666 * 1e10)
        );
    }

    function testFuzz_calcUnrealizedPnL_long(uint96 _size, uint64 _entryPrice, uint64 _price) public pure {
        vm.assume(_price > 0);

        int256 input = PositionUtil.calcUnrealizedPnL(LONG, _size, _entryPrice, _price);
        int256 want;
        if (_entryPrice > _price) {
            want = -Math.mulDivUp(_size, _entryPrice - _price, _price).toInt256();
        } else {
            want = Math.mulDiv(_size, _price - _entryPrice, _price).toInt256();
        }
        assertEq(input, want);
    }

    function testFuzz_calcUnrealizedPnL_short(uint96 _size, uint64 _entryPrice, uint64 _price) public pure {
        vm.assume(_price > 0);

        int256 input = PositionUtil.calcUnrealizedPnL(SHORT, _size, _entryPrice, _price);
        int256 want;
        if (_entryPrice < _price) {
            want = -Math.mulDivUp(_size, _price - _entryPrice, _price).toInt256();
        } else {
            want = Math.mulDiv(_size, _entryPrice - _price, _price).toInt256();
        }
        assertEq(input, want);
    }

    function test_calcUnrealizedPnL_passIf_sideIsLongAndEntryPriceGreaterThanPrice() public pure {
        int256 got = PositionUtil.calcUnrealizedPnL(LONG, 1000, 2000 * 1e10, 1900 * 1e10);
        int256 want = -Math.mulDivUp(1000, 100 * 1e10, 1900 * 1e10).toInt256();
        assertEq(got, want);
    }

    function test_calcUnrealizedPnL_passIf_sideIsLongAndEntryPriceNotGreaterThanPrice() public pure {
        int256 got = PositionUtil.calcUnrealizedPnL(LONG, 1000, 2000 * 1e10, 2000 * 1e10);
        assertEq(got, 0);
        got = PositionUtil.calcUnrealizedPnL(LONG, 1000, 1900 * 1e10, 2100 * 1e10);
        int256 want = Math.mulDiv(1000, 200 * 1e10, 2100 * 1e10).toInt256();
        assertEq(got, want);
    }

    function test_calcUnrealizedPnL_passIf_sideIsShortAndEntryPriceLessThanPrice() public pure {
        int256 got = PositionUtil.calcUnrealizedPnL(SHORT, 1000, 1900 * 1e10, 2000 * 1e10);
        int256 want = -Math.mulDivUp(1000, 100 * 1e10, 2000 * 1e10).toInt256();
        assertEq(got, want);
    }

    function test_calcUnrealizedPnL_passIf_sideIsShortAndEntryPriceNotLessThanPrice() public pure {
        int256 got = PositionUtil.calcUnrealizedPnL(SHORT, 1000, 2000 * 1e10, 2000 * 1e10);
        assertEq(got, 0);
        got = PositionUtil.calcUnrealizedPnL(SHORT, 1000, 2000 * 1e10, 1900 * 1e10);
        int256 want = Math.mulDiv(1000, 100 * 1e10, 1900 * 1e10).toInt256();
        assertEq(got, want);
    }

    function testFuzz_calcUnrealizedPnL(uint96 _size, uint64 _entryPrice, uint64 _price) public pure {
        vm.assume(_entryPrice > 0 && _price > 0);

        {
            int256 value = (int256(uint256(_price)) - int256(uint256(_entryPrice))) * int256(uint256(_size));
            int256 pnl = value <= 0 ? -int256(Math.ceilDiv(uint256(-value), _price)) : value / int256(uint256(_price));
            assertEq(PositionUtil.calcUnrealizedPnL(LONG, _size, _entryPrice, _price), pnl);
            if (pnl <= 0) {
                assertGt(pnl, type(int168).min);
            } else {
                assertLe(pnl, int256(uint256(type(uint160).max)));
            }
        }

        {
            int256 value = (int256(uint256(_entryPrice)) - int256(uint256(_price))) * int256(uint256(_size));
            int256 pnl = value <= 0 ? -int256(Math.ceilDiv(uint256(-value), _price)) : value / int256(uint256(_price));
            assertEq(PositionUtil.calcUnrealizedPnL(SHORT, _size, _entryPrice, _price), pnl);
            if (pnl <= 0) {
                assertGt(pnl, type(int168).min);
            } else {
                assertLe(pnl, int256(uint256(type(uint160).max)));
            }
        }
    }

    function testFuzz_calcUnrealizedPnL2(uint96 _size, uint64 _entryPrice, uint64 _price) public pure {
        vm.assume(_entryPrice > 0 && _price > 0);

        {
            int256 scaledUSDPnL = (int256(uint256(_price)) - int256(uint256(_entryPrice))) * int256(uint256(_size));
            int256 tokenPnL = scaledUSDPnL <= 0
                ? -int256(Math.ceilDiv(uint256(-scaledUSDPnL), _price))
                : scaledUSDPnL / int256(uint256(_price));
            (int184 tokenPnLGot, int184 scaledUSDPnLGot) = PositionUtil.calcUnrealizedPnL2(
                LONG,
                _size,
                _entryPrice,
                _price
            );
            assertEq(tokenPnLGot, tokenPnL);
            assertEq(scaledUSDPnLGot, scaledUSDPnL);
            if (tokenPnL <= 0) {
                assertGt(tokenPnL, type(int184).min);
            } else {
                assertLe(tokenPnL, int256(uint256(type(uint184).max)));
            }
        }

        {
            int256 scaledUSDPnL = (int256(uint256(_entryPrice)) - int256(uint256(_price))) * int256(uint256(_size));
            int256 tokenPnL = scaledUSDPnL <= 0
                ? -int256(Math.ceilDiv(uint256(-scaledUSDPnL), _price))
                : scaledUSDPnL / int256(uint256(_price));
            (int184 tokenPnLGot, int184 scaledUSDPnLGot) = PositionUtil.calcUnrealizedPnL2(
                SHORT,
                _size,
                _entryPrice,
                _price
            );
            assertEq(tokenPnLGot, tokenPnL);
            assertEq(scaledUSDPnLGot, scaledUSDPnL);
            if (tokenPnL <= 0) {
                assertGt(tokenPnL, type(int184).min);
            } else {
                assertLe(tokenPnL, int256(uint256(type(uint184).max)));
            }
        }
    }

    function testFuzz_calcReceiveAmount(
        uint96 _size,
        uint96 _tradingFee,
        uint64 _entryPrice,
        uint64 _price
    ) public pure {
        vm.assume(_entryPrice > 0 && _price > 0);
        {
            int256 pnl = PositionUtil.calcUnrealizedPnL(LONG, _size, _entryPrice, _price);
            int256 value = pnl + int256(uint256(_size)) - int256(uint256(_tradingFee)); // should never overflow/underflow here
        }

        {
            int256 pnl = PositionUtil.calcUnrealizedPnL(SHORT, _size, _entryPrice, _price);
            int256 value = pnl + int256(uint256(_size)) - int256(uint256(_tradingFee)); // should never overflow/underflow here
        }
    }

    function testFuzz_calcReceiveAmount_withSpread(
        uint96 _size,
        uint96 _tradingFee,
        uint96 _spread,
        uint64 _entryPrice,
        uint64 _price
    ) public pure {
        vm.assume(_entryPrice > 0 && _price > 0);
        {
            int256 pnl = PositionUtil.calcUnrealizedPnL(LONG, _size, _entryPrice, _price);
            int256 value = pnl + int256(uint256(_size)) - int256(uint256(_tradingFee)) - int256(uint256(_spread)); // should never overflow/underflow here
        }

        {
            int256 pnl = PositionUtil.calcUnrealizedPnL(SHORT, _size, _entryPrice, _price);
            int256 value = pnl + int256(uint256(_size)) - int256(uint256(_tradingFee)) - int256(uint256(_spread)); // should never overflow/underflow here
        }
    }

    function testFuzz_calcReceiveAmount_withSpreadAndMargin(
        uint96 _size,
        uint96 _tradingFee,
        uint96 _spread,
        uint64 _entryPrice,
        uint64 _price,
        uint96 _margin,
        uint96 _marginDelta
    ) public pure {
        vm.assume(_entryPrice > 0 && _price > 0);
        {
            int256 pnl = PositionUtil.calcUnrealizedPnL(LONG, _size, _entryPrice, _price);
            int256 value = pnl +
                int256(uint256(_size)) -
                int256(uint256(_tradingFee)) -
                int256(uint256(_spread)) +
                int256(uint256(_margin)) -
                int256(uint256(_marginDelta)); // should never overflow/underflow here
        }

        {
            int256 pnl = PositionUtil.calcUnrealizedPnL(SHORT, _size, _entryPrice, _price);
            int256 value = pnl +
                int256(uint256(_size)) -
                int256(uint256(_tradingFee)) -
                int256(uint256(_spread)) +
                int256(uint256(_margin)) -
                int256(uint256(_marginDelta)); // should never overflow/underflow here
        }
    }

    function test_calcLiquidationPrice_pass() public view {
        IMarketPosition.Position memory _position = IMarketPosition.Position({
            margin: 10 * 1e18,
            size: 100 * 1e18,
            entryPrice: price
        });

        uint64 liquidationPriceWant = Math
            .mulDiv(
                uint256(100 * 1e18) *
                    (uint64(cfg.liquidationFeeRatePerPosition) + cfg.tradingFeeRate + Constants.BASIS_POINTS_DIVISOR),
                price,
                (uint256(10 * 1e18) + 100 * 1e18 - cfg.liquidationExecutionFee) * Constants.BASIS_POINTS_DIVISOR
            )
            .toUint64();
        uint64 liquidationPriceGot = PositionUtil.calcLiquidationPrice(
            _position,
            cfg.liquidationFeeRatePerPosition,
            cfg.tradingFeeRate,
            cfg.liquidationExecutionFee
        );

        assertEq(liquidationPriceGot, liquidationPriceWant);
    }

    function test_calcTradingFeeRate_passIf_withFloatingTradingFeeRate() public {
        cfg.maxFeeRate = 0.9 * 1e7;
        cfg.openPositionThreshold = 0.5 * 1e7;
        uint24 tradingFeeRateGot = PositionUtil.calcTradingFeeRate(cfg, 1000 * 1e18, 520 * 1e18);
        uint24 tradingFeeRateWant = uint24((uint256(cfg.maxFeeRate) * (20 * 1e18)) / (500 * 1e18)) + cfg.tradingFeeRate;
        assertEq(tradingFeeRateGot, tradingFeeRateWant);
    }

    function test_calcTradingFeeRate_passIf_withNoFloatingTradingFeeRate() public {
        cfg.maxFeeRate = 0.9 * 1e7;
        cfg.openPositionThreshold = 0.5 * 1e7;
        uint24 tradingFeeRateGot = PositionUtil.calcTradingFeeRate(cfg, 1000 * 1e18, 480 * 1e18);
        assertEq(tradingFeeRateGot, cfg.tradingFeeRate);
    }

    function testFuzz_calcTradingFeeRate(
        uint128 _lpLiquidity,
        uint128 _lpNetSize,
        uint24 _maxFeeRate,
        uint24 _openPositionThreshold
    ) public {
        vm.assume(
            _lpLiquidity > 0 &&
                _lpNetSize <= _lpLiquidity &&
                _maxFeeRate <= Constants.BASIS_POINTS_DIVISOR &&
                _openPositionThreshold <= Constants.BASIS_POINTS_DIVISOR
        );
        cfg.maxFeeRate = _maxFeeRate;
        cfg.openPositionThreshold = _openPositionThreshold;
        uint24 tradingFeeRateWant;
        {
            uint256 floatingTradingFeeSize = (uint256(_lpLiquidity) * _openPositionThreshold) /
                Constants.BASIS_POINTS_DIVISOR;
            if (_lpNetSize > floatingTradingFeeSize) {
                uint256 floatingTradingFeeRate = (_maxFeeRate * (_lpNetSize - floatingTradingFeeSize)) /
                    (_lpLiquidity - floatingTradingFeeSize);
                assertLe(floatingTradingFeeRate, type(uint24).max);
                tradingFeeRateWant = uint24(floatingTradingFeeRate) + cfg.tradingFeeRate;
            } else {
                tradingFeeRateWant = cfg.tradingFeeRate;
            }
        }
        uint24 tradingFeeRateGot = PositionUtil.calcTradingFeeRate(cfg, _lpLiquidity, _lpNetSize);
        assertEq(tradingFeeRateGot, tradingFeeRateWant);
    }
}

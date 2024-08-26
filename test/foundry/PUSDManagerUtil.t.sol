// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import "./BaseTest.t.sol";
import "../../contracts/core/interfaces/IMarketManager.sol";
import "../../contracts/plugins/interfaces/IPositionRouter.sol";
import "../../contracts/core/PUSD.sol";
import "../../contracts/libraries/LiquidityUtil.sol";
import "../../contracts/libraries/PUSDManagerUtil.sol";
import "../../contracts/test/ERC20Test.sol";
import "../../contracts/test/MockPUSDManagerCallback.sol";
import {PUSDManagerUtilTest as UtilTest} from "../../contracts/test/PUSDManagerUtilTest.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PUSDManagerUtilTest is BaseTest {
    using SafeCast for *;

    address private constant account = address(0x111);
    address private constant receiver = address(0x222);
    address private constant feeReceiver = address(0x333);

    IMarketManager.State state;

    IERC20 market = new ERC20Test("Market Token", "MT", 18, 1000000e18);
    ILPToken lpToken = LiquidityUtil.deployLPToken(market, "tLPT");
    IPUSDManagerCallback pusdManagerCallback = IPUSDManagerCallback(address(new MockPUSDManagerCallback()));
    PUSD pusd = PUSDManagerUtil.deployPUSD();
    uint64 price = uint64(31681133113133);

    function setUp() public {
        delete state;

        state.packedState.lpLiquidity = 500 * 1e18;

        PositionUtil.increasePosition(
            state,
            cfg,
            PositionUtil.IncreasePositionParam({
                market: market,
                account: account,
                marginDelta: 20 * 1e18,
                sizeDelta: 100 * 1e18,
                minIndexPrice: price,
                maxIndexPrice: price
            })
        );
    }

    function test_mint_exactOut_revertIf_InvalidSize() public {
        PUSDManagerUtil.MintParam memory param = PUSDManagerUtil.MintParam({
            market: market,
            exactIn: false,
            amount: 0,
            callback: pusdManagerCallback,
            indexPrice: price,
            receiver: receiver
        });

        vm.expectRevert(IMarketErrors.InvalidSize.selector);
        UtilTest.mint(
            state,
            cfg,
            param,
            abi.encode(IPositionRouterCommon.CallbackData({margin: 11e18, account: msg.sender}))
        );
    }

    function test_mint_exactOut_revertIf_stableCoinSupplyCapExceeded() public {
        cfg.stableCoinSupplyCap = 100 * 1e6;

        PUSDManagerUtil.MintParam memory param = PUSDManagerUtil.MintParam({
            market: market,
            exactIn: false,
            amount: uint96((uint256(price) * 50 * 1e18) / (10 ** 22)),
            callback: pusdManagerCallback,
            indexPrice: price,
            receiver: receiver
        });
        bytes memory data = abi.encode(IPositionRouterCommon.CallbackData({margin: 110e18, account: msg.sender}));

        vm.expectRevert(
            abi.encodeWithSelector(IMarketErrors.StableCoinSupplyCapExceeded.selector, 100 * 1e6, 0, 158405665565)
        );
        UtilTest.mint(state, cfg, param, data);
    }

    function test_mint_exactOut_revertIf_insufficientSizeToDecrease() public {
        PUSDManagerUtil.MintParam memory param = PUSDManagerUtil.MintParam({
            market: market,
            exactIn: false,
            amount: uint96((uint256(price) * 100 * 1e18) / (10 ** 22)) + 10,
            callback: pusdManagerCallback,
            indexPrice: price,
            receiver: receiver
        });
        bytes memory data = abi.encode(IPositionRouterCommon.CallbackData({margin: 110e18, account: msg.sender}));

        vm.expectRevert(
            abi.encodeWithSelector(IMarketErrors.InsufficientSizeToDecrease.selector, 100000000003052289817, 100 * 1e18)
        );
        UtilTest.mint(state, cfg, param, data);
    }

    function test_mint_exactOut_revertIf_minMintingSizeCapNotMet() public {
        cfg.minMintingRate = 0.6 * 1e7;

        PUSDManagerUtil.MintParam memory param = PUSDManagerUtil.MintParam({
            market: market,
            exactIn: false,
            amount: uint96((uint256(price) * 50 * 1e18) / (10 ** 22)),
            callback: pusdManagerCallback,
            indexPrice: price,
            receiver: receiver
        });
        bytes memory data = abi.encode(IPositionRouterCommon.CallbackData({margin: 51e18, account: msg.sender}));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMarketErrors.MinMintingSizeCapNotMet.selector,
                100 * 1e18,
                49999999999790095891,
                300021000000000000000
            )
        );
        UtilTest.mint(state, cfg, param, data);
    }

    function test_mint_exactOut_revertIf_tooLittlePayAmount() public {
        MockPUSDManagerCallback(address(pusdManagerCallback)).setIgnoreTransfer();

        PUSDManagerUtil.MintParam memory param = PUSDManagerUtil.MintParam({
            market: market,
            exactIn: false,
            amount: uint96((uint256(price) * 10 * 1e18) / (10 ** 22)),
            callback: pusdManagerCallback,
            indexPrice: price,
            receiver: receiver
        });
        bytes memory data = abi.encode(IPositionRouterCommon.CallbackData({margin: 11e18, account: msg.sender}));

        market.transfer(address(pusdManagerCallback), 11e18);
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.TooLittlePayAmount.selector, 0, 10007999999957985593));
        UtilTest.mint(state, cfg, param, data);
    }

    function test_mint_exactOut_pass() public {
        {
            assertEq(pusd.balanceOf(receiver), 0);
        }

        uint64 newPrice = (price * 12) / 10;
        PUSDManagerUtil.MintParam memory param = PUSDManagerUtil.MintParam({
            market: market,
            exactIn: false,
            amount: uint96((uint256(newPrice) * 10 * 1e18) / (10 ** 22)),
            callback: pusdManagerCallback,
            indexPrice: newPrice,
            receiver: receiver
        });
        bytes memory data = abi.encode(IPositionRouterCommon.CallbackData({margin: 12e18, account: msg.sender}));

        uint128 protocolFeeBefore = state.protocolFee;
        IMarketManager.PackedState memory packedStateBefore = state.packedState;
        IMarketManager.GlobalPUSDPosition memory globalPUSDPositionBefore = state.globalPUSDPosition;
        uint256 globalStabilityFundBefore = state.globalStabilityFund;

        market.transfer(address(pusdManagerCallback), 12e18);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(
            param.market,
            -9999999999800354363,
            -1666666666633260875,
            packedStateBefore.lpEntryPrice
        );
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreased(param.market, 3499999999930124);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByTradingFee(param.market, 3499999999930124);
        vm.expectEmit();
        emit IMarketManager.GlobalStabilityFundIncreasedBySpread(param.market, 999999999980036);
        vm.expectEmit();
        emit IMarketManager.SpreadFactorChanged(
            param.market,
            int256(7130534626299607940392455355505246129052327084032)
        );
        vm.expectEmit();
        emit IPUSDManager.PUSDPositionIncreased(
            market,
            receiver,
            9999999999800354363,
            param.indexPrice,
            38017359735759,
            10007999999800194647,
            38017359735,
            6999999999860248,
            999999999980036
        );
        (uint128 payAmountGot, uint128 receiveAmountGot) = UtilTest.mint(state, cfg, param, data);

        {
            assertEq(payAmountGot, 10007999999800194647);
            assertEq(receiveAmountGot, 38017359735);

            assertEq(pusd.balanceOf(receiver), 38017359735);
            assertEq(pusd.totalSupply(), 38017359735);
            assertEq(market.balanceOf(msg.sender), 12 * 1e18 - 10007999999800194647);

            assertEq(state.protocolFee, protocolFeeBefore + 3499999999930124);
            assertEq(
                state.packedState.lpLiquidity,
                packedStateBefore.lpLiquidity + 3499999999930124 - 1666666666633260875
            );
            assertEq(state.packedState.lpNetSize, packedStateBefore.lpNetSize - 9999999999800354363);
            assertEq(state.packedState.spreadFactorX96, int256(7130534626299607940392455355505246129052327084032));
            assertEq(state.packedState.lastTradingTimestamp, block.timestamp);
            assertEq(state.globalStabilityFund, globalStabilityFundBefore + 999999999980036);
            assertEq(state.globalPUSDPosition.size, globalPUSDPositionBefore.size + 9999999999800354363);
            assertEq(state.globalPUSDPosition.totalSupply, globalPUSDPositionBefore.totalSupply + 38017359735);
            assertEq(state.globalPUSDPosition.entryPrice, 38017359735759);
        }
    }

    function test_mint_exactIn_revertIf_invalidSize() public {
        PUSDManagerUtil.MintParam memory param = PUSDManagerUtil.MintParam({
            market: market,
            exactIn: true,
            amount: 0,
            callback: pusdManagerCallback,
            indexPrice: price,
            receiver: receiver
        });
        bytes memory data = abi.encode(IPositionRouterCommon.CallbackData({margin: 11e18, account: msg.sender}));

        vm.expectRevert(IMarketErrors.InvalidSize.selector);
        UtilTest.mint(state, cfg, param, data);
    }

    function test_mint_exactIn_revertIf_tooLittlePayAmount() public {
        MockPUSDManagerCallback(address(pusdManagerCallback)).setIgnoreTransfer();

        PUSDManagerUtil.MintParam memory param = PUSDManagerUtil.MintParam({
            market: market,
            exactIn: true,
            amount: 10e18,
            callback: pusdManagerCallback,
            indexPrice: price,
            receiver: receiver
        });
        bytes memory data = abi.encode(IPositionRouterCommon.CallbackData({margin: 11e18, account: msg.sender}));

        market.transfer(address(pusdManagerCallback), 11e18);
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.TooLittlePayAmount.selector, 0, 10 * 1e18));
        UtilTest.mint(state, cfg, param, data);
    }

    function test_mint_exactIn_pass() public {
        {
            assertEq(pusd.balanceOf(receiver), 0);
        }

        uint64 newPrice = (price * 12) / 10;
        PUSDManagerUtil.MintParam memory param = PUSDManagerUtil.MintParam({
            market: market,
            exactIn: true,
            amount: 10 * 1e18,
            callback: pusdManagerCallback,
            indexPrice: newPrice,
            receiver: receiver
        });
        bytes memory data = abi.encode(IPositionRouterCommon.CallbackData({margin: 12e18, account: msg.sender}));

        uint128 protocolFeeBefore = state.protocolFee;
        IMarketManager.PackedState memory packedStateBefore = state.packedState;
        IMarketManager.GlobalPUSDPosition memory globalPUSDPositionBefore = state.globalPUSDPosition;
        uint256 globalStabilityFundBefore = state.globalStabilityFund;

        market.transfer(address(pusdManagerCallback), 12e18);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(
            param.market,
            -9992006394884092725,
            -1665334399147217374,
            packedStateBefore.lpEntryPrice
        );
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreased(param.market, 3497202238209432);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByTradingFee(param.market, 3497202238209432);
        vm.expectEmit();
        emit IMarketManager.GlobalStabilityFundIncreasedBySpread(param.market, 999200639488411);
        vm.expectEmit();
        emit IMarketManager.SpreadFactorChanged(
            param.market,
            int256(7131167944928988339819550499129273338156181094400)
        );
        vm.expectEmit();
        emit IPUSDManager.PUSDPositionIncreased(
            market,
            receiver,
            9992006394884092725,
            param.indexPrice,
            38017359735759,
            10 * 1e18,
            37986970159,
            6994404476418864,
            999200639488411
        );
        (uint128 payAmountGot, uint128 receiveAmountGot) = UtilTest.mint(state, cfg, param, data);

        {
            assertEq(payAmountGot, 10 * 1e18);
            assertEq(receiveAmountGot, 37986970159);

            assertEq(pusd.balanceOf(receiver), 37986970159);
            assertEq(pusd.totalSupply(), 37986970159);
            assertEq(market.balanceOf(msg.sender), 12 * 1e18 - 10 * 1e18);

            assertEq(state.protocolFee, protocolFeeBefore + 3497202238209432);
            assertEq(
                state.packedState.lpLiquidity,
                packedStateBefore.lpLiquidity + 3497202238209432 - 1665334399147217374
            );
            assertEq(state.packedState.lpNetSize, packedStateBefore.lpNetSize - 9992006394884092725);
            assertEq(state.packedState.spreadFactorX96, int256(7131167944928988339819550499129273338156181094400));
            assertEq(state.packedState.lastTradingTimestamp, block.timestamp);
            assertEq(state.globalStabilityFund, globalStabilityFundBefore + 999200639488411);
            assertEq(state.globalPUSDPosition.size, globalPUSDPositionBefore.size + 9992006394884092725);
            assertEq(state.globalPUSDPosition.totalSupply, globalPUSDPositionBefore.totalSupply + 37986970159);
            assertEq(state.globalPUSDPosition.entryPrice, 38017359735759);
        }
    }

    function _prepareBurnState() private {
        vm.warp(block.timestamp + cfg.riskFreeTime - 1);
        market.transfer(address(pusdManagerCallback), 52 * 1e18);
        UtilTest.mint(
            state,
            cfg,
            PUSDManagerUtil.MintParam({
                market: market,
                exactIn: true,
                amount: 50 * 1e18,
                callback: pusdManagerCallback,
                indexPrice: price,
                receiver: address(this)
            }),
            abi.encode(IPositionRouterCommon.CallbackData({margin: 52 * 1e18, account: msg.sender}))
        );
        assertLt(state.packedState.spreadFactorX96, 0);
    }

    function test_burn_exactIn_revertIf_invalidAmount_zeroAmount() public {
        _prepareBurnState();
        pusd.transfer(address(pusdManagerCallback), 3000 * 1e6);

        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.InvalidAmount.selector, pusd.totalSupply(), 0));
        UtilTest.burn(
            state,
            cfg,
            PUSDManagerUtil.BurnParam({
                market: market,
                exactIn: true,
                amount: 0,
                callback: pusdManagerCallback,
                indexPrice: price,
                receiver: receiver
            }),
            abi.encode(IPositionRouterCommon.CallbackData({margin: 3000 * 1e6, account: msg.sender}))
        );
    }

    function test_burn_exactIn_revertIf_invalidAmount_amountGreaterThanTotalSupply() public {
        _prepareBurnState();
        pusd.transfer(address(pusdManagerCallback), 3000 * 1e6);

        uint256 totalSupply = pusd.totalSupply();

        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.InvalidAmount.selector, totalSupply, totalSupply + 1));
        UtilTest.burn(
            state,
            cfg,
            PUSDManagerUtil.BurnParam({
                market: market,
                exactIn: true,
                amount: uint96(totalSupply) + 1,
                callback: pusdManagerCallback,
                indexPrice: price,
                receiver: receiver
            }),
            abi.encode(IPositionRouterCommon.CallbackData({margin: 3000 * 1e6, account: msg.sender}))
        );
    }

    function test_burn_exactIn_revertIf_invalidSize() public {
        _prepareBurnState();
        state.globalPUSDPosition.size = 0;
        pusd.transfer(address(pusdManagerCallback), 3100 * 1e6);

        vm.expectRevert(IMarketErrors.InvalidSize.selector);
        UtilTest.burn(
            state,
            cfg,
            PUSDManagerUtil.BurnParam({
                market: market,
                exactIn: true,
                amount: 3000 * 1e6,
                callback: pusdManagerCallback,
                indexPrice: price,
                receiver: receiver
            }),
            abi.encode(IPositionRouterCommon.CallbackData({margin: 3100 * 1e6, account: msg.sender}))
        );
    }

    function test_burn_exactIn_revertIf_maxBurningSizeCapExceeded() public {
        _prepareBurnState();
        state.packedState.lpLiquidity = state.packedState.lpNetSize + 1;
        cfg.maxBurningRate = 0.5 * 1e7;
        pusd.transfer(address(pusdManagerCallback), 3100 * 1e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMarketErrors.MaxBurningSizeCapExceeded.selector,
                state.packedState.lpNetSize,
                946935827481844054,
                25017488105305617939
            )
        );
        UtilTest.burn(
            state,
            cfg,
            PUSDManagerUtil.BurnParam({
                market: market,
                exactIn: true,
                amount: 3000 * 1e6,
                callback: pusdManagerCallback,
                indexPrice: price,
                receiver: receiver
            }),
            abi.encode(IPositionRouterCommon.CallbackData({margin: 3100 * 1e6, account: msg.sender}))
        );
    }

    function test_burn_exactIn_revertIf_unexpectedPayAmount() public {
        _prepareBurnState();
        MockPUSDManagerCallback(address(pusdManagerCallback)).setIgnoreTransfer();
        pusd.transfer(address(pusdManagerCallback), 3100 * 1e6);

        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.UnexpectedPayAmount.selector, 3000 * 1e6, 0));
        UtilTest.burn(
            state,
            cfg,
            PUSDManagerUtil.BurnParam({
                market: market,
                exactIn: true,
                amount: 3000 * 1e6,
                callback: pusdManagerCallback,
                indexPrice: price,
                receiver: receiver
            }),
            abi.encode(IPositionRouterCommon.CallbackData({margin: 3100 * 1e6, account: msg.sender}))
        );
    }

    function test_burn_exactIn_pass() public {
        _prepareBurnState();
        {
            assertEq(market.balanceOf(receiver), 0);
        }

        uint64 newPrice = (price * 8) / 10;
        uint256 pusdTotalSupplyBefore = pusd.totalSupply();
        uint256 pusdBalanceBefore = pusd.balanceOf(address(this));
        uint128 protocolFeeBefore = state.protocolFee;
        IMarketManager.PackedState memory packedStateBefore = state.packedState;
        IMarketManager.GlobalPUSDPosition memory globalPUSDPositionBefore = state.globalPUSDPosition;
        uint256 globalStabilityFundBefore = state.globalStabilityFund;

        PUSDManagerUtil.BurnParam memory param = PUSDManagerUtil.BurnParam({
            market: market,
            exactIn: true,
            amount: 3000 * 1e6,
            callback: pusdManagerCallback,
            indexPrice: newPrice,
            receiver: receiver
        });

        pusd.transfer(address(pusdManagerCallback), 3100 * 1e6);
        {
            assertEq(pusd.totalSupply(), pusdTotalSupplyBefore);
            assertEq(pusd.balanceOf(address(this)), pusdBalanceBefore - 3100 * 1e6);
        }
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(param.market, 946935827481844054, 0, 31563444314103);
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreased(param.market, 414284424523313);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByTradingFee(param.market, 414284424523313);
        vm.expectEmit();
        emit IMarketManager.GlobalStabilityFundIncreasedBySpread(param.market, 47300519260662);
        vm.expectEmit();
        emit IMarketManager.SpreadFactorChanged(
            param.market,
            int256(-3882512648038434378846672583847150789400368804295)
        );
        vm.expectEmit();
        emit IPUSDManager.PUSDPositionDecreased(
            market,
            receiver,
            946935827481844054,
            param.indexPrice,
            3000 * 1e6,
            1182793914984016460,
            236733956870479694,
            828568849046626,
            47300519260662
        );
        (uint128 payAmountGot, uint128 receiveAmountGot) = UtilTest.burn(
            state,
            cfg,
            param,
            abi.encode(IPositionRouterCommon.CallbackData({margin: 3100 * 1e6, account: msg.sender}))
        );
        {
            assertEq(payAmountGot, 3000 * 1e6);
            assertEq(receiveAmountGot, 1182793914984016460);

            assertEq(market.balanceOf(receiver), 1182793914984016460);

            assertEq(state.protocolFee, protocolFeeBefore + 414284424523313);
            assertEq(state.packedState.lpLiquidity, packedStateBefore.lpLiquidity + 414284424523313);
            assertEq(state.packedState.lpNetSize, packedStateBefore.lpNetSize + 946935827481844054);
            assertEq(state.packedState.spreadFactorX96, int256(-3882512648038434378846672583847150789400368804295));
            assertEq(state.packedState.lastTradingTimestamp, block.timestamp);
            assertEq(state.globalStabilityFund, globalStabilityFundBefore + 47300519260662);
            assertEq(state.globalPUSDPosition.size, globalPUSDPositionBefore.size - 946935827481844054);
            assertEq(state.globalPUSDPosition.totalSupply, globalPUSDPositionBefore.totalSupply - 3000 * 1e6);
            assertEq(state.globalPUSDPosition.entryPrice, globalPUSDPositionBefore.entryPrice);

            assertEq(pusd.totalSupply(), pusdTotalSupplyBefore - 3000 * 1e6);
            assertEq(pusd.balanceOf(address(this)), pusdBalanceBefore - 3100 * 1e6);
            assertEq(pusd.balanceOf(msg.sender), 100 * 1e6);
        }
    }

    function test_burn_exactOut_revertIf_insufficientSizeToDecrease() public {
        _prepareBurnState();
        uint96 expectAmount = PositionUtil.calcDecimals6TokenValue(
            uint96(state.globalPUSDPosition.size + 1),
            price,
            cfg.decimals,
            Math.Rounding.Up
        );
        pusd.transfer(address(pusdManagerCallback), pusd.balanceOf(address(this)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMarketErrors.InsufficientSizeToDecrease.selector,
                50002523238439320311,
                49965023789388764123
            )
        );
        UtilTest.burn(
            state,
            cfg,
            PUSDManagerUtil.BurnParam({
                market: market,
                exactIn: false,
                amount: uint96(state.globalPUSDPosition.size + 1),
                callback: pusdManagerCallback,
                indexPrice: price,
                receiver: receiver
            }),
            abi.encode(IPositionRouterCommon.CallbackData({margin: expectAmount, account: msg.sender}))
        );
    }

    function test_burn_exactOut_revertIf_invalidSize() public {
        _prepareBurnState();
        pusd.transfer(address(pusdManagerCallback), pusd.balanceOf(address(this)));

        vm.expectRevert(IMarketErrors.InvalidSize.selector);
        UtilTest.burn(
            state,
            cfg,
            PUSDManagerUtil.BurnParam({
                market: market,
                exactIn: false,
                amount: 0,
                callback: pusdManagerCallback,
                indexPrice: price,
                receiver: receiver
            }),
            abi.encode(IPositionRouterCommon.CallbackData({margin: 0, account: msg.sender}))
        );
    }

    function test_burn_exactOut_revertIf_maxBurningSizeCapExceeded() public {
        _prepareBurnState();
        state.packedState.lpLiquidity = state.packedState.lpNetSize + 1;
        cfg.maxBurningRate = 0.5 * 1e7;
        uint96 expectAmount = PositionUtil.calcMarketTokenValue(3000 * 1e6, price, cfg.decimals);
        pusd.transfer(address(pusdManagerCallback), 3100 * 1e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMarketErrors.MaxBurningSizeCapExceeded.selector,
                50034976210611235877,
                947646516060563145,
                25017488105305617939
            )
        );
        UtilTest.burn(
            state,
            cfg,
            PUSDManagerUtil.BurnParam({
                market: market,
                exactIn: false,
                amount: expectAmount,
                callback: pusdManagerCallback,
                indexPrice: price,
                receiver: receiver
            }),
            abi.encode(IPositionRouterCommon.CallbackData({margin: 3100 * 1e6, account: msg.sender}))
        );
    }

    function test_burn_exactOut_revertIf_unexpectedPayAmount() public {
        _prepareBurnState();
        MockPUSDManagerCallback(address(pusdManagerCallback)).setIgnoreTransfer();
        uint96 expectAmount = PositionUtil.calcMarketTokenValue(3000 * 1e6, price, cfg.decimals);

        pusd.transfer(address(pusdManagerCallback), 3100 * 1e6);

        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.UnexpectedPayAmount.selector, 3002251542, 0));
        UtilTest.burn(
            state,
            cfg,
            PUSDManagerUtil.BurnParam({
                market: market,
                exactIn: false,
                amount: expectAmount,
                callback: pusdManagerCallback,
                indexPrice: price,
                receiver: receiver
            }),
            abi.encode(IPositionRouterCommon.CallbackData({margin: 3100 * 1e6, account: msg.sender}))
        );
    }

    function test_burn_exactOut_pass() public {
        _prepareBurnState();
        {
            assertEq(market.balanceOf(receiver), 0);
        }

        uint64 newPrice = (price * 8) / 10;
        uint256 pusdTotalSupplyBefore = pusd.totalSupply();
        uint256 pusdBalanceBefore = pusd.balanceOf(address(this));
        uint128 protocolFeeBefore = state.protocolFee;
        IMarketManager.PackedState memory packedStateBefore = state.packedState;
        IMarketManager.GlobalPUSDPosition memory globalPUSDPositionBefore = state.globalPUSDPosition;
        uint256 globalStabilityFundBefore = state.globalStabilityFund;
        uint96 expectAmount = PositionUtil.calcMarketTokenValue(3000 * 1e6, newPrice, cfg.decimals);
        PUSDManagerUtil.BurnParam memory param = PUSDManagerUtil.BurnParam({
            market: market,
            exactIn: false,
            amount: expectAmount,
            callback: pusdManagerCallback,
            indexPrice: newPrice,
            receiver: receiver
        });

        pusd.transfer(address(pusdManagerCallback), 3100 * 1e6);
        {
            assertEq(pusd.totalSupply(), pusdTotalSupplyBefore);
            assertEq(pusd.balanceOf(address(this)), pusdBalanceBefore - 3100 * 1e6);
        }
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(param.market, 947637041846222554, 0, 31563358784394);
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreased(param.market, 414591205807728);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByTradingFee(param.market, 414591205807729);
        vm.expectEmit();
        emit IMarketManager.GlobalStabilityFundIncreasedBySpread(param.market, 47335545713971);
        vm.expectEmit();
        emit IMarketManager.SpreadFactorChanged(
            param.market,
            int256(-3882457092112816062478747396583730727188862628295)
        );
        vm.expectEmit();
        emit IPUSDManager.PUSDPositionDecreased(
            market,
            receiver,
            947637041846222554,
            param.indexPrice,
            2401777222,
            1183669784350467457,
            236909260461574333,
            829182411615457,
            47335545713971
        );
        (uint128 payAmountGot, uint128 receiveAmountGot) = UtilTest.burn(
            state,
            cfg,
            param,
            abi.encode(IPositionRouterCommon.CallbackData({margin: 3100 * 1e6, account: msg.sender}))
        );
        {
            assertEq(payAmountGot, 2401777222);
            assertEq(receiveAmountGot, 1183669784350467457);

            assertEq(market.balanceOf(receiver), 1183669784350467457);

            assertEq(state.protocolFee, protocolFeeBefore + 414591205807728);
            assertEq(state.packedState.lpLiquidity, packedStateBefore.lpLiquidity + 414591205807729);
            assertEq(state.packedState.lpNetSize, packedStateBefore.lpNetSize + 947637041846222554);
            assertEq(state.packedState.spreadFactorX96, int256(-3882457092112816062478747396583730727188862628295));
            assertEq(state.packedState.lastTradingTimestamp, block.timestamp);
            assertEq(state.globalStabilityFund, globalStabilityFundBefore + 47335545713971);
            assertEq(state.globalPUSDPosition.size, globalPUSDPositionBefore.size - 947637041846222554);
            assertEq(state.globalPUSDPosition.totalSupply, globalPUSDPositionBefore.totalSupply - 2401777222);
            assertEq(state.globalPUSDPosition.entryPrice, globalPUSDPositionBefore.entryPrice);

            assertEq(pusd.totalSupply(), pusdTotalSupplyBefore - 2401777222);
            assertEq(pusd.balanceOf(address(this)), pusdBalanceBefore - 3100 * 1e6);
            assertEq(pusd.balanceOf(msg.sender), 3100 * 1e6 - 2401777222);
        }
    }

    function test_liquidityBufferModuleBurn_pass() public {
        _prepareBurnState();

        uint64 newPrice = (price * 8) / 10;
        uint128 protocolFeeBefore = state.protocolFee;
        IMarketManager.PackedState memory packedStateBefore = state.packedState;
        IMarketManager.GlobalPUSDPosition memory globalPUSDPositionBefore = state.globalPUSDPosition;
        IMarketManager.LiquidityBufferModule memory liquidityBufferModuleBefore = state.liquidityBufferModule;

        PUSDManagerUtil.LiquidityBufferModuleBurnParam memory param = PUSDManagerUtil.LiquidityBufferModuleBurnParam({
            market: market,
            account: account,
            sizeDelta: 10 * 1e18,
            indexPrice: newPrice
        });

        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquiditySettled(param.market, int256(uint256(param.sizeDelta)), 0, 30625710587370);
        vm.expectEmit();
        emit IMarketManager.ProtocolFeeIncreased(param.market, 4375000000000069);
        vm.expectEmit();
        emit IMarketLiquidity.GlobalLiquidityIncreasedByTradingFee(param.market, 4375000000000069);
        vm.expectEmit();
        emit IPUSDManager.PUSDPositionDecreased(
            param.market,
            address(this),
            param.sizeDelta,
            param.indexPrice,
            31681133114,
            12491250000000197140,
            2500000000000197278,
            8750000000000138,
            0
        );
        vm.expectEmit();
        emit IMarketManager.LiquidityBufferModuleDebtIncreased(
            param.market,
            param.account,
            31681133114,
            12491250000000197140
        );
        PUSDManagerUtil.liquidityBufferModuleBurn(state, cfg, state.packedState, param);
        {
            assertEq(state.protocolFee, protocolFeeBefore + 4375000000000069);
            assertEq(state.packedState.lpLiquidity, packedStateBefore.lpLiquidity + 4375000000000069);
            assertEq(state.packedState.lpNetSize, packedStateBefore.lpNetSize + param.sizeDelta);
            assertEq(state.globalPUSDPosition.size, globalPUSDPositionBefore.size - param.sizeDelta);
            assertEq(state.globalPUSDPosition.totalSupply, globalPUSDPositionBefore.totalSupply - 31681133114);
            assertEq(state.globalPUSDPosition.entryPrice, globalPUSDPositionBefore.entryPrice);
            assertEq(state.liquidityBufferModule.pusdDebt, liquidityBufferModuleBefore.pusdDebt + 31681133114);
            assertEq(
                state.liquidityBufferModule.tokenPayback,
                liquidityBufferModuleBefore.tokenPayback + 12491250000000197140
            );
        }
    }

    function test_repayLiquidityBufferDebt_revertIf_noDebtToPay() public {
        _setLiquidityBufferModule(0, 0);
        vm.expectRevert(stdError.divisionError);
        PUSDManagerUtil.repayLiquidityBufferDebt(state, market, account, account);
    }

    function test_repayLiquidityBufferDebt_revertIf_payExceedsU128() public {
        _setLiquidityBufferModule(100e6, 0.05e18);
        deal(address(pusd), address(this), type(uint136).max);
        vm.expectRevert(
            abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 128, type(uint136).max)
        );
        PUSDManagerUtil.repayLiquidityBufferDebt(state, market, account, account);
    }

    function test_repayLiquidityBufferDebt_pass() public {
        _setLiquidityBufferModule(100e6, 0.05e18);
        deal(address(pusd), address(this), 100e6, true);
        vm.assertTrue(pusd.totalSupply() == 100e6);
        vm.expectEmit();
        emit IMarketManager.LiquidityBufferModuleDebtRepaid(market, account, 100e6, 0.05e18);
        uint128 receiveAmount = PUSDManagerUtil.repayLiquidityBufferDebt(state, market, account, account);
        assertTrue(state.liquidityBufferModule.pusdDebt == 0);
        assertTrue(state.liquidityBufferModule.tokenPayback == 0);
        assertTrue(state.tokenBalance == 0);
        assertTrue(pusd.totalSupply() == 0);
        assertTrue(receiveAmount == 0.05e18);
        assertTrue(market.balanceOf(account) == 0.05e18);
    }

    function test_repayLiquidityBufferDebt_passIf_payExceedsDebt() public {
        _setLiquidityBufferModule(100e6, 0.05e18);
        deal(address(pusd), address(this), 200e6);
        uint128 receiveAmount = PUSDManagerUtil.repayLiquidityBufferDebt(state, market, account, account);
        vm.assertTrue(receiveAmount == 0.05e18);
        assertTrue(state.liquidityBufferModule.pusdDebt == 0);
        assertTrue(state.liquidityBufferModule.tokenPayback == 0);
        assertTrue(state.tokenBalance == 0);
        assertTrue(market.balanceOf(account) == 0.05e18);
        assertTrue(pusd.balanceOf(address(this)) == 100e6);
        assertTrue(pusd.balanceOf(account) == 0);
    }

    function test_repayLiquidityBufferDebt_passThat_receiveAmountIsRoundingDown() public {
        _setLiquidityBufferModule(100e6, 3);
        deal(address(pusd), address(this), 50e6);
        uint128 receiveAmount = PUSDManagerUtil.repayLiquidityBufferDebt(state, market, account, account);
        vm.assertTrue(receiveAmount == 1);
        assertTrue(state.liquidityBufferModule.pusdDebt == 50e6);
        assertTrue(state.liquidityBufferModule.tokenPayback == 2);
        assertTrue(state.tokenBalance == 2);
        assertTrue(market.balanceOf(account) == 1);

        deal(address(pusd), address(this), 50e6);
        receiveAmount = PUSDManagerUtil.repayLiquidityBufferDebt(state, market, account, account);
        vm.assertTrue(receiveAmount == 2);
        assertTrue(state.liquidityBufferModule.pusdDebt == 0);
        assertTrue(state.liquidityBufferModule.tokenPayback == 0);
        assertTrue(state.tokenBalance == 0);
        assertTrue(market.balanceOf(account) == 3);
    }

    function _setLiquidityBufferModule(uint128 _pusdDebt, uint128 _tokenPayback) private {
        state.liquidityBufferModule.pusdDebt = _pusdDebt;
        state.liquidityBufferModule.tokenPayback = _tokenPayback;
        state.tokenBalance = _tokenPayback;
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import "./BaseTest.t.sol";
import "../../contracts/test/WETH9.sol";
import "../../contracts/test/ERC20Test.sol";
import "../../contracts/core/PUSD.sol";
import "../../contracts/test/MockChainLinkPriceFeed.sol";
import "../../contracts/test/MockPUSDManagerCallback.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../contracts/core/interfaces/IPUSDManager.sol";

contract MarketManagerTest is BaseTest {
    using SafeCast for *;

    MarketManagerUpgradeable private marketManager;
    PUSD private pusd;
    FeeDistributorUpgradeable private feeDistributor;
    IERC20 private weth;
    IERC20 private dai;
    IERC20 private usdt;
    ILPToken private lpToken;
    MockChainLinkPriceFeed private mockChanLink;
    uint64 private fixedDefaultRefPrice;
    MockPUSDManagerCallback pusdManagerCallback;

    function setUp() public {
        address impl = address(new FeeDistributorUpgradeable());
        feeDistributor = FeeDistributorUpgradeable(
            address(
                new ERC1967Proxy(
                    impl,
                    abi.encodeWithSelector(
                        FeeDistributorUpgradeable.initialize.selector,
                        address(this),
                        0.8333333 * 1e7,
                        0
                    )
                )
            )
        );

        impl = address(new MarketManagerUpgradeable());
        marketManager = MarketManagerUpgradeable(
            address(
                new ERC1967Proxy(
                    impl,
                    abi.encodeWithSelector(
                        MarketManagerUpgradeable.initialize.selector,
                        address(this),
                        feeDistributor,
                        true
                    )
                )
            )
        );
        pusd = PUSD(marketManager.pusd());

        weth = IERC20(address(deployWETH9()));
        lpToken = ILPToken(LiquidityUtil.computeLPTokenAddress(weth, address(marketManager)));
        vm.expectEmit();
        emit IMarketLiquidity.LPTokenDeployed(weth, lpToken);
        marketManager.enableMarket(weth, "LPT-ETH", cfg);

        dai = new ERC20Test("DAI", "DAI", 18, 0);
        usdt = new ERC20Test("USDT", "USDT", 6, 0);

        pusdManagerCallback = new MockPUSDManagerCallback();

        marketManager.updatePlugin(address(this), true);
        marketManager.updateUpdater(address(this));
        marketManager.updatePrice(encodePrice(weth, PRICE, uint32(block.timestamp)));

        mockChanLink = new MockChainLinkPriceFeed();
        mockChanLink.setDecimals(8);
        mockChanLink.setRoundData(100, int64(PRICE) / 100, 0, 0, 0);
        fixedDefaultRefPrice = (PRICE / 100) * 100;
    }

    function test_mintLPT_revertIf_notPlugin() public {
        vm.expectRevert(abi.encodeWithSelector(IPluginManager.PluginInactive.selector, address(0x1)));
        vm.prank(address(0x1));
        marketManager.mintLPT(weth, ALICE, ALICE);
    }

    function test_mintLPT_passIf_liquidityIsZero() public {
        vm.expectEmit();
        emit IMarketLiquidity.LPTMinted(weth, ALICE, ALICE, 0, 0);
        marketManager.mintLPT(weth, ALICE, ALICE);
    }

    function test_mintLPT_revertIf_liquidityExceedsCap() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);
        IMarketManager.PackedState memory packedState = marketManager.packedStates(weth);
        assertEq(packedState.lpLiquidity, 100e18);

        deal(address(weth), address(marketManager), cfg.liquidityCap + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMarketErrors.LiquidityCapExceeded.selector,
                100e18,
                cfg.liquidityCap + 1 - 100e18,
                cfg.liquidityCap
            )
        );
        marketManager.mintLPT(weth, ALICE, ALICE);
    }

    function test_mintLPT_passIf_totalSupplyIsZero() public {
        dealMarketManager(weth, 100e18);
        vm.expectEmit();
        emit IMarketLiquidity.LPTMinted(weth, ALICE, ALICE, 100e18, 298990965670);
        marketManager.mintLPT(weth, ALICE, ALICE);

        IMarketManager.PackedState memory packedState = marketManager.packedStates(weth);
        assertEq(packedState.lpLiquidity, 100e18);
        assertEq(marketManager.tokenBalances(weth), 100e18);

        ILPToken token = ILPToken(LiquidityUtil.computeLPTokenAddress(weth, address(marketManager)));
        assertEq(token.totalSupply(), 298990965670);
        assertEq(token.balanceOf(ALICE), 298990965670);
    }

    function test_mintLPT_passIf_totalSupplyIsGtZeroAndPriceIsChanged() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        marketManager.updatePrice(encodePrice(weth, PRICE << 1, uint32(block.timestamp + 1)));
        dealMarketManager(weth, 11e18);
        vm.expectEmit();
        emit IMarketLiquidity.LPTMinted(weth, ALICE, BOB, 11e18, 32889006223);
        marketManager.mintLPT(weth, ALICE, BOB);

        IMarketManager.PackedState memory packedState = marketManager.packedStates(weth);
        assertEq(packedState.lpLiquidity, 111e18);
        assertEq(marketManager.tokenBalances(weth), 111e18);

        assertEq(lpToken.totalSupply(), 298990965670 + 32889006223);
        assertEq(lpToken.balanceOf(BOB), 32889006223);
    }

    function test_mintLPT_passIf_netSizeGtZeroAndLoss() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 10e18);
        marketManager.increasePosition(weth, ALICE, 10e18);

        vm.warp(block.timestamp + 3600);
        marketManager.updatePrice(encodePrice(weth, PRICE << 1, uint32(block.timestamp)));
        dealMarketManager(weth, 100e18);
        vm.expectEmit();
        emit IMarketLiquidity.LPTMinted(weth, BOB, BOB, 100e18, 314715737493);
        marketManager.mintLPT(weth, BOB, BOB);

        IMarketManager.PackedState memory packedState = marketManager.packedStates(weth);
        uint256 increaseTradingFee = 3500000000000000;
        assertEq(packedState.lpLiquidity, 200e18 + increaseTradingFee);
        assertEq(marketManager.tokenBalances(weth), 200e18 + 10e18);

        assertEq(lpToken.totalSupply(), 298990965670 + 314715737493);
        assertEq(lpToken.balanceOf(BOB), 314715737493);
    }

    function test_mintLPT_passIf_netSizeGtZeroAndProfit() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 10e18);
        marketManager.increasePosition(weth, ALICE, 10e18);

        vm.warp(block.timestamp + 3600);
        marketManager.updatePrice(encodePrice(weth, PRICE >> 1, uint32(block.timestamp)));
        dealMarketManager(weth, 100e18);
        vm.expectEmit();
        emit IMarketLiquidity.LPTMinted(weth, BOB, BOB, 100e18, 271801320567);
        marketManager.mintLPT(weth, BOB, BOB);

        IMarketManager.PackedState memory packedState = marketManager.packedStates(weth);
        uint256 increaseTradingFee = 3500000000000000;
        assertEq(packedState.lpLiquidity, 200e18 + increaseTradingFee);
        assertEq(marketManager.tokenBalances(weth), 200e18 + 10e18);

        assertEq(lpToken.totalSupply(), 298990965670 + 271801320567);
        assertEq(lpToken.balanceOf(BOB), 271801320567);
    }

    function testFuzz_mintLPT(address _account, address _receiver, uint96 _liquidity, uint64 _indexPrice) public {
        vm.assume(_indexPrice > 0);
        if (_account == address(0)) _account = CARRIE;
        if (_receiver == address(0)) _receiver = CARRIE;

        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 50e18);
        marketManager.increasePosition(weth, BOB, 100e18);

        vm.warp(block.timestamp + 3600);
        marketManager.updatePrice(encodePrice(weth, _indexPrice, uint32(block.timestamp)));

        dealMarketManager(weth, _liquidity);
        IMarketManager.PackedState memory packedState = marketManager.packedStates(weth);
        if (packedState.lpLiquidity + _liquidity > cfg.liquidityCap) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IMarketErrors.LiquidityCapExceeded.selector,
                    packedState.lpLiquidity,
                    _liquidity,
                    cfg.liquidityCap
                )
            );
        } else {
            int256 pnl = PositionUtil.calcUnrealizedPnL(
                SHORT,
                packedState.lpNetSize,
                packedState.lpEntryPrice,
                _indexPrice
            );
            uint64 tokenValue = Math
                .mulDiv(_liquidity, lpToken.totalSupply(), (pnl + int256(uint256(packedState.lpLiquidity))).toUint256())
                .toUint64();
            vm.expectEmit();
            emit IMarketLiquidity.LPTMinted(weth, _account, _receiver, _liquidity, tokenValue);
        }
        marketManager.mintLPT(weth, _account, _receiver);
    }

    function test_burnLPT_revertIf_notPlugin() public {
        vm.expectRevert(abi.encodeWithSelector(IPluginManager.PluginInactive.selector, address(0x1)));
        vm.prank(address(0x1));
        marketManager.burnLPT(weth, ALICE, ALICE);
    }

    function test_burnLPT_revertIf_tokenValueIsZero() public {
        vm.expectRevert(stdError.divisionError);
        marketManager.burnLPT(weth, ALICE, ALICE);
    }

    function test_burnLPT_passIf_tokenValueIsZeroAndTotalSupplyIsNotZero() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        vm.expectEmit();
        emit IMarketLiquidity.LPTBurned(weth, ALICE, ALICE, 0, 0);
        marketManager.burnLPT(weth, ALICE, ALICE);
    }

    function test_burnLPT_passIf_burnAllIfNetSizeIsZero() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, BOB);

        vm.prank(BOB);
        lpToken.transfer(address(marketManager), 298990965670);
        vm.expectEmit();
        emit IMarketLiquidity.LPTBurned(weth, BOB, ALICE, 100e18, 298990965670);
        marketManager.burnLPT(weth, BOB, ALICE);

        IMarketManager.PackedState memory packedState = marketManager.packedStates(weth);
        assertEq(packedState.lpLiquidity, 0);
        assertEq(marketManager.tokenBalances(weth), 0);

        assertEq(lpToken.balanceOf(BOB), 0);
    }

    function test_burnLPT_revertIf_leftLiquidityLessThenLiquidityDelta() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, BOB);

        dealMarketManager(weth, 90e18);
        marketManager.increasePosition(weth, ALICE, 90e18);

        vm.prank(BOB);
        lpToken.transfer(address(marketManager), 2989 * 11 * 1e6);
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.BalanceRateCapExceeded.selector));
        marketManager.burnLPT(weth, BOB, ALICE);
    }

    function test_burnLPT_revertIf_leftLiquidityLessThenLiquidityDeltaWithProfit() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 90e18);
        marketManager.increasePosition(weth, ALICE, 100e18);

        vm.prank(ALICE);
        lpToken.transfer(address(marketManager), 2989 * 2 * 1e6);
        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.BalanceRateCapExceeded.selector));
        marketManager.burnLPT(weth, ALICE, ALICE);
    }

    function test_burnLPT_passIf_netSizeGtZeroAndLoss() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 90e18);
        marketManager.increasePosition(weth, ALICE, 10e18);

        IMarketManager.PackedState memory packedStateBefore = marketManager.packedStates(weth);
        vm.warp(block.timestamp + 3600);
        marketManager.updatePrice(encodePrice(weth, PRICE << 1, uint32(block.timestamp)));
        vm.prank(ALICE);
        lpToken.transfer(address(marketManager), 2989 * 1e6);
        vm.expectEmit();
        emit IMarketLiquidity.LPTBurned(weth, ALICE, ALICE, 949745959258903382, 2989 * 1e6);
        marketManager.burnLPT(weth, ALICE, ALICE);

        IMarketManager.PackedState memory packedStateAfter = marketManager.packedStates(weth);
        assertEq(packedStateAfter.lpLiquidity, packedStateBefore.lpLiquidity - 949745959258903382);
        assertEq(100e18 + 90e18 - 949745959258903382, marketManager.tokenBalances(weth));
    }

    function test_burnLPT_passIf_netSizeGtZeroAndProfit() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 90e18);
        marketManager.increasePosition(weth, ALICE, 10e18);

        IMarketManager.PackedState memory packedStateBefore = marketManager.packedStates(weth);
        vm.warp(block.timestamp + 3600);
        marketManager.updatePrice(encodePrice(weth, PRICE >> 1, uint32(block.timestamp)));
        vm.prank(ALICE);
        lpToken.transfer(address(marketManager), 2989 * 1e6);
        vm.expectEmit();
        emit IMarketLiquidity.LPTBurned(weth, ALICE, ALICE, 1099700322928496461, 2989 * 1e6);
        marketManager.burnLPT(weth, ALICE, ALICE);

        IMarketManager.PackedState memory packedStateAfter = marketManager.packedStates(weth);
        assertEq(packedStateAfter.lpLiquidity, packedStateBefore.lpLiquidity - 1099700322928496461);
        assertEq(100e18 + 90e18 - 1099700322928496461, marketManager.tokenBalances(weth));
    }

    function test_increasePosition_revertIf_notPlugin() public {
        vm.expectRevert(abi.encodeWithSelector(IPluginManager.PluginInactive.selector, address(0x1)));
        vm.prank(address(0x1));
        marketManager.increasePosition(weth, ALICE, 10e18);
    }

    function test_increasePosition_revertIf_balanceGtUint128() public {
        dealMarketManager(weth, uint256(type(uint128).max) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                128,
                uint256(type(uint128).max) + 1
            )
        );
        marketManager.increasePosition(weth, ALICE, 10e18);
    }

    function test_increasePosition_revertIf_marginDeltaGtUint96() public {
        dealMarketManager(weth, type(uint128).max);
        vm.expectRevert(
            abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 96, type(uint128).max)
        );
        marketManager.increasePosition(weth, ALICE, 10e18);
    }

    function test_increasePosition_passIf_firstIncrease() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 10e18);
        marketManager.increasePosition(weth, BOB, 10e18);

        IMarketPosition.Position memory position = marketManager.longPositions(weth, BOB);
        assertEq(position.size, 10e18);
        assertEq(position.entryPrice, PRICE);
        assertEq(position.margin, 9993000000000000000);

        IMarketManager.PackedState memory packedState = marketManager.packedStates(weth);
        assertEq(packedState.lpNetSize, 10e18);
        assertEq(packedState.lpEntryPrice, PRICE);
        assertEq(packedState.lpLiquidity, 100e18 + 3500000000000000);
        assertEq(packedState.longSize, 10e18);
        assertEq(packedState.lastTradingTimestamp, block.timestamp);
        assertEq(packedState.spreadFactorX96, 10e18 << 96);

        assertEq(marketManager.tokenBalances(weth), 110e18);
        assertEq(marketManager.protocolFees(weth), 3500000000000000);
    }

    function test_increasePosition_passIf_differentUserFirstIncrease() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 10e18);
        marketManager.increasePosition(weth, BOB, 10e18);

        vm.warp(block.timestamp + 3600);
        marketManager.updatePrice(encodePrice(weth, PRICE << 1, uint32(block.timestamp)));
        dealMarketManager(weth, 10e18);
        marketManager.increasePosition(weth, CARRIE, 10e18);

        IMarketPosition.Position memory position = marketManager.longPositions(weth, CARRIE);
        assertEq(position.size, 10e18);
        assertEq(position.entryPrice, PRICE << 1);
        assertEq(position.margin, 9993000000000000000);

        IMarketManager.PackedState memory packedState = marketManager.packedStates(weth);
        assertEq(packedState.lpNetSize, 20e18);
        assertEq(packedState.lpEntryPrice, (PRICE + (PRICE << 1)) >> 1);
        assertEq(packedState.lpLiquidity, 100e18 + 3500000000000000 * 2);
        assertEq(packedState.longSize, 20e18);
        assertEq(packedState.lastTradingTimestamp, block.timestamp);

        assertEq(marketManager.tokenBalances(weth), 120e18);
        assertEq(marketManager.protocolFees(weth), 3500000000000000 * 2);
    }

    function test_increasePosition_passIf_sameUserIncreaseAgain() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 10e18);
        marketManager.increasePosition(weth, BOB, 10e18);

        vm.warp(block.timestamp + 3600);
        marketManager.updatePrice(encodePrice(weth, PRICE << 1, uint32(block.timestamp)));
        dealMarketManager(weth, 10e18);
        marketManager.increasePosition(weth, BOB, 10e18);

        IMarketPosition.Position memory position = marketManager.longPositions(weth, BOB);
        assertEq(position.size, 20e18);
        assertEq(position.entryPrice, Math.ceilDiv(PRICE + (PRICE << 1), 2));
        assertEq(position.margin, 9993000000000000000 * 2);

        IMarketManager.PackedState memory packedState = marketManager.packedStates(weth);
        assertEq(packedState.lpNetSize, 20e18);
        assertEq(packedState.lpEntryPrice, (PRICE + (PRICE << 1)) >> 1);
        assertEq(packedState.lpLiquidity, 100e18 + 3500000000000000 * 2);
        assertEq(packedState.longSize, 20e18);
        assertEq(packedState.lastTradingTimestamp, block.timestamp);

        assertEq(marketManager.tokenBalances(weth), 120e18);
        assertEq(marketManager.protocolFees(weth), 3500000000000000 * 2);
    }

    function test_increasePosition_passIf_sameUserIncreaseAgainWithFloatingFee() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 10e18);
        marketManager.increasePosition(weth, BOB, 10e18);

        vm.warp(block.timestamp + 3600);
        marketManager.updatePrice(encodePrice(weth, PRICE << 1, uint32(block.timestamp)));
        dealMarketManager(weth, 50e18);
        marketManager.increasePosition(weth, BOB, 90e18);

        IMarketPosition.Position memory position = marketManager.longPositions(weth, BOB);
        assertEq(position.size, 100e18);
        assertEq(position.entryPrice, Math.ceilDiv(uint256(10e18) * PRICE + uint256(90e18) * (PRICE << 1), 100e18));
        assertEq(position.margin, 58130630000000000000);

        IMarketManager.PackedState memory packedState = marketManager.packedStates(weth);
        assertEq(packedState.lpNetSize, 100e18);
        assertEq(packedState.lpEntryPrice, (uint256(10e18) * PRICE + uint256(90e18) * (PRICE << 1)) / 100e18);
        assertEq(packedState.lpLiquidity, 100e18 + 3500000000000000 + 931185000000000000);
        assertEq(packedState.longSize, 100e18);
        assertEq(packedState.lastTradingTimestamp, block.timestamp);

        assertEq(marketManager.tokenBalances(weth), 160e18);
        assertEq(marketManager.protocolFees(weth), 3500000000000000 + 931185000000000000);
    }

    function test_increasePosition_passIf_sameUserIncreaseAgainWithSpread() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 10e18);
        marketManager.increasePosition(weth, BOB, 10e18);

        vm.warp(block.timestamp + 3600);
        marketManager.updatePrice(encodePrice(weth, PRICE << 1, uint32(block.timestamp)));
        dealMarketManager(weth, 50e18);
        marketManager.increasePosition(weth, BOB, 90e18);

        vm.warp(block.timestamp + 2 hours);
        marketManager.decreasePosition(weth, BOB, 40e18, 40e18, BOB);
        IMarketManager.PackedState memory packedState = marketManager.packedStates(weth);
        assertEq(packedState.lastTradingTimestamp, block.timestamp);
        assertEq(packedState.spreadFactorX96, -int256(40e18 << 96));

        marketManager.increasePosition(weth, BOB, 1e18);
        packedState = marketManager.packedStates(weth);
        assertEq(packedState.lpNetSize, 61e18);
        assertEq(packedState.lpEntryPrice, 56857298389770);
        assertEq(packedState.lpLiquidity, 98948334999999665659);
        assertEq(packedState.longSize, 61e18);
        assertEq(packedState.lastTradingTimestamp, block.timestamp);

        assertEq(marketManager.tokenBalances(weth), 160e18 - 40e18);
        assertEq(marketManager.globalStabilityFunds(weth), 40000000000001);
        assertEq(marketManager.protocolFees(weth), 948335000000000117);
    }

    function testFuzz_increasePosition(
        address _account,
        uint96 _sizeDelta,
        uint96 _marginDelta,
        uint96 _liquidity,
        uint64 _indexPrice,
        uint32 _timestamp
    ) public {
        vm.assume(_indexPrice > 0 && _timestamp > block.timestamp);

        if (_liquidity > cfg.liquidityCap) _liquidity = uint96(cfg.liquidityCap);
        dealMarketManager(weth, _liquidity);
        marketManager.mintLPT(weth, ALICE, ALICE);

        vm.warp(_timestamp);
        marketManager.updatePrice(encodePrice(weth, _indexPrice, _timestamp));

        dealMarketManager(weth, _marginDelta);
        uint256 maxSizePerPosition = (uint256(_liquidity) * cfg.maxSizeRatePerPosition) /
            Constants.BASIS_POINTS_DIVISOR;
        if (_sizeDelta == 0) {
            vm.expectRevert(abi.encodeWithSelector(IMarketErrors.PositionNotFound.selector, _account));
        } else if (_marginDelta < cfg.minMarginPerPosition) {
            vm.expectRevert(abi.encodeWithSelector(IMarketErrors.InsufficientMargin.selector));
        } else if (_sizeDelta > _liquidity) {
            vm.expectRevert(abi.encodeWithSelector(IMarketErrors.SizeExceedsMaxSize.selector, _sizeDelta, _liquidity));
        } else if (_sizeDelta > maxSizePerPosition) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IMarketErrors.SizeExceedsMaxSizePerPosition.selector,
                    _sizeDelta,
                    maxSizePerPosition
                )
            );
        } else {
            uint96 tradingFee = PositionUtil.calcTradingFee(
                PositionUtil.DistributeFeeParam({
                    market: weth,
                    size: _sizeDelta,
                    entryPrice: _indexPrice,
                    indexPrice: _indexPrice,
                    rounding: Math.Rounding.Up,
                    tradingFeeRate: PositionUtil.calcTradingFeeRate(cfg, _liquidity, _sizeDelta),
                    protocolFeeRate: cfg.protocolFeeRate
                })
            );
            int256 marginAfter = int256(uint256(_marginDelta)) - int256(uint256(tradingFee));
            uint256 maintenanceMargin = PositionUtil.calcMaintenanceMargin(
                _sizeDelta,
                _indexPrice,
                _indexPrice,
                cfg.liquidationFeeRatePerPosition,
                cfg.tradingFeeRate,
                cfg.liquidationExecutionFee
            );
            if (marginAfter <= 0 || maintenanceMargin >= uint256(marginAfter)) {
                vm.expectRevert(
                    abi.encodeWithSelector(IMarketErrors.MarginRateTooHigh.selector, marginAfter, maintenanceMargin)
                );
            } else {
                if (uint256(marginAfter) * cfg.maxLeveragePerPosition < _sizeDelta) {
                    vm.expectRevert(
                        abi.encodeWithSelector(
                            IMarketErrors.LeverageTooHigh.selector,
                            marginAfter,
                            _sizeDelta,
                            cfg.maxLeveragePerPosition
                        )
                    );
                } else {
                    vm.expectEmit();
                    emit IMarketPosition.PositionIncreased(
                        weth,
                        _account,
                        _marginDelta,
                        uint96(uint256(marginAfter)),
                        _sizeDelta,
                        _indexPrice,
                        _indexPrice,
                        tradingFee,
                        0
                    );
                }
            }
        }
        marketManager.increasePosition(weth, _account, _sizeDelta);
    }

    function test_decreasePosition_revertIf_notPlugin() public {
        vm.expectRevert(abi.encodeWithSelector(IPluginManager.PluginInactive.selector, address(0x1)));
        vm.prank(address(0x1));
        marketManager.decreasePosition(weth, ALICE, 10e18, 10e18, ALICE);
    }

    function test_decreasePosition_passIf_someMarginDeltaAndSomeSizeDeltaDecreased() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 10e18);
        marketManager.increasePosition(weth, BOB, 10e18);

        vm.warp(block.timestamp + 3600);
        marketManager.updatePrice(encodePrice(weth, PRICE << 1, uint32(block.timestamp)));

        marketManager.decreasePosition(weth, BOB, 0.5e18, 1e18, CARRIE);
        assertEq(marketManager.tokenBalances(weth), 109.5e18);

        IMarketManager.PackedState memory packedState = marketManager.packedStates(weth);
        assertEq(packedState.lpNetSize, 9e18);
        assertEq(packedState.lpEntryPrice, PRICE);
        assertEq(packedState.longSize, 9e18);

        IMarketPosition.Position memory position = marketManager.longPositions(weth, BOB);
        assertEq(position.size, 9e18);
        assertEq(position.entryPrice, PRICE);
        assertEq(position.margin, 9992644999999999999);

        assertGt(marketManager.globalStabilityFunds(weth), 0);

        assertEq(weth.balanceOf(CARRIE), 0.5e18);
    }

    function test_decreasePosition_passIf_marginDeltaIsZeroAndLeftSizeIsGtZero() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 10e18);
        marketManager.increasePosition(weth, BOB, 10e18);

        vm.warp(block.timestamp + 3600);
        marketManager.updatePrice(encodePrice(weth, PRICE << 1, uint32(block.timestamp)));

        marketManager.decreasePosition(weth, BOB, 0, 1e18, BOB);
        assertEq(marketManager.tokenBalances(weth), 110e18);

        IMarketManager.PackedState memory packedState = marketManager.packedStates(weth);
        assertEq(packedState.lpNetSize, 9e18);
        assertEq(packedState.lpEntryPrice, PRICE);
        assertEq(packedState.longSize, 9e18);

        IMarketPosition.Position memory position = marketManager.longPositions(weth, BOB);
        assertEq(position.size, 9e18);
        assertEq(position.entryPrice, PRICE);

        assertGt(marketManager.globalStabilityFunds(weth), 0);
    }

    function test_decreasePosition_passIf_marginDeltaIsZeroAndLeftSizeIsZero() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 10e18);
        marketManager.increasePosition(weth, BOB, 10e18);

        vm.warp(block.timestamp + 3600);
        marketManager.updatePrice(encodePrice(weth, PRICE << 1, uint32(block.timestamp)));

        marketManager.decreasePosition(weth, BOB, 0, 10e18, BOB);
        assertLt(marketManager.tokenBalances(weth), 100e18);

        IMarketManager.PackedState memory packedState = marketManager.packedStates(weth);
        assertEq(packedState.lpNetSize, 0);
        assertEq(packedState.lpEntryPrice, PRICE);
        assertEq(packedState.longSize, 0);

        IMarketPosition.Position memory position = marketManager.longPositions(weth, BOB);
        assertEq(position.size, 0);
        assertEq(position.entryPrice, 0);

        assertGt(marketManager.globalStabilityFunds(weth), 0);
    }

    function test_decreasePosition_passIf_marginDeltaIsGtMarginAndLeftSizeIsZero() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 10e18);
        marketManager.increasePosition(weth, BOB, 10e18);

        vm.warp(block.timestamp + 3600);
        marketManager.updatePrice(encodePrice(weth, PRICE << 1, uint32(block.timestamp)));

        (uint96 spread, uint96 actualMarginDelta) = marketManager.decreasePosition(
            weth,
            BOB,
            type(uint96).max,
            10e18,
            BOB
        );
        assertLt(marketManager.tokenBalances(weth), 100e18);
        assertLt(actualMarginDelta, type(uint96).max);

        IMarketManager.PackedState memory packedState = marketManager.packedStates(weth);
        assertEq(packedState.lpNetSize, 0);
        assertEq(packedState.lpEntryPrice, PRICE);
        assertEq(packedState.longSize, 0);

        IMarketPosition.Position memory position = marketManager.longPositions(weth, BOB);
        assertEq(position.size, 0);
        assertEq(position.entryPrice, 0);

        assertEq(marketManager.globalStabilityFunds(weth), spread);
    }

    function test_liquidatePosition_revertIf_notPlugin() public {
        vm.expectRevert(abi.encodeWithSelector(IPluginManager.PluginInactive.selector, address(0x1)));
        vm.prank(address(0x1));
        marketManager.liquidatePosition(weth, ALICE, ALICE);
    }

    function test_liquidatePosition_revertIf_marginRateTooLow() public {
        dealMarketManager(weth, 1000e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 10e18);
        marketManager.increasePosition(weth, BOB, 90e18);

        uint64 newPrice = (PRICE * 99) / 100;
        marketManager.updatePrice(encodePrice(weth, newPrice, uint32(block.timestamp)));

        vm.expectRevert(abi.encodeWithSelector(IMarketErrors.MarginRateTooLow.selector, 9.937 * 1e18, 0.428 * 1e18));
        marketManager.liquidatePosition(weth, BOB, EXECUTOR);
    }

    function test_liquidatePosition_pass() public {
        dealMarketManager(weth, 1000e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 10e18);
        marketManager.increasePosition(weth, BOB, 90e18);

        vm.warp(block.timestamp + 3600);
        marketManager.updatePrice(encodePrice(weth, PRICE >> 1, uint32(block.timestamp)));

        marketManager.liquidatePosition(weth, BOB, EXECUTOR);

        IMarketManager.PackedState memory packedState = marketManager.packedStates(weth);
        assertEq(packedState.lpNetSize, 0);
        assertEq(packedState.lpEntryPrice, PRICE);
        assertEq(packedState.longSize, 0);

        IMarketPosition.Position memory position = marketManager.longPositions(weth, BOB);
        assertEq(position.size, 0);
        assertEq(position.entryPrice, 0);

        assertEq(weth.balanceOf(EXECUTOR), cfg.liquidationExecutionFee);
    }

    function test_mintPUSD_revertIf_callerIsNotPlugin() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPluginManager.PluginInactive.selector, ALICE));
        marketManager.mintPUSD(
            weth,
            true,
            10e18,
            IPUSDManagerCallback(address(pusdManagerCallback)),
            abi.encode(IPositionRouterCommon.CallbackData({margin: 10e18, account: ALICE})),
            ALICE
        );
    }

    function test_mintPUSD_exactIn_pass() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 10e18);
        marketManager.increasePosition(weth, BOB, 10e18);

        vm.warp(block.timestamp + 10000);

        IMarketManager.PackedState memory packedState = marketManager.packedStates(weth);
        assertEq(packedState.lpNetSize, 10e18);

        deal(address(weth), address(pusdManagerCallback), 10e18);
        marketManager.mintPUSD(
            weth,
            true,
            10e18,
            IPUSDManagerCallback(address(pusdManagerCallback)),
            abi.encode(IPositionRouterCommon.CallbackData({margin: 10e18, account: ALICE})),
            ALICE
        );
        assertEq(pusd.balanceOf(ALICE), 29878181839);
        assertEq(weth.balanceOf(address(pusdManagerCallback)), 0);
        uint128 balance = marketManager.tokenBalances(weth);
        assertEq(balance, 100e18 + 10e18 + 10e18);
    }

    function test_mintPUSD_exactOut_pass() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 10e18);
        marketManager.increasePosition(weth, BOB, 10e18);

        vm.warp(block.timestamp + 10000);

        deal(address(weth), address(pusdManagerCallback), 1e18);
        marketManager.mintPUSD(
            weth,
            false,
            10e6,
            IPUSDManagerCallback(address(pusdManagerCallback)),
            abi.encode(IPositionRouterCommon.CallbackData({margin: 1e18, account: ALICE})),
            ALICE
        );
        assertEq(pusd.balanceOf(ALICE), 10e6);
        assertEq(weth.balanceOf(address(pusdManagerCallback)), 0);
        assertEq(weth.balanceOf(ALICE), 1e18 - 3346923870279456);
        uint128 balance = marketManager.tokenBalances(weth);
        assertEq(balance, 100e18 + 10e18 + 3346923870279456);
    }

    function test_burnPUSD_revertIf_callerIsNotPlugin() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPluginManager.PluginInactive.selector, ALICE));
        marketManager.burnPUSD(
            weth,
            true,
            10e6,
            IPUSDManagerCallback(address(pusdManagerCallback)),
            abi.encode(IPositionRouterCommon.CallbackData({margin: 10e6, account: ALICE})),
            ALICE
        );
    }

    function test_burnPUSD_exactIn_pass() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 10e18);
        marketManager.increasePosition(weth, BOB, 10e18);

        deal(address(weth), address(pusdManagerCallback), 10e18);
        marketManager.mintPUSD(
            weth,
            true,
            10e18,
            IPUSDManagerCallback(address(pusdManagerCallback)),
            abi.encode(IPositionRouterCommon.CallbackData({margin: 10e18, account: ALICE})),
            ALICE
        );

        vm.warp(block.timestamp + 2 hours);

        IMarketManager.PackedState memory packedState = marketManager.packedStates(weth);
        assertEq(packedState.lpNetSize, 7094962576570635);
        IPUSDManager.GlobalPUSDPosition memory position = marketManager.globalPUSDPositions(weth);
        assertEq(position.totalSupply, 29877883269);
        assertEq(pusd.balanceOf(ALICE), 29877883269);
        assertEq(weth.balanceOf(ALICE), 0);

        deal(address(pusd), address(pusdManagerCallback), 10e6);
        marketManager.burnPUSD(
            weth,
            true,
            10e6,
            IPUSDManagerCallback(address(pusdManagerCallback)),
            abi.encode(IPositionRouterCommon.CallbackData({margin: 10e6, account: ALICE})),
            ALICE
        );
        packedState = marketManager.packedStates(weth);
        assertEq(packedState.lpNetSize, 10439545239088643);
        assertEq(weth.balanceOf(address(ALICE)), 3342241454654246);
        uint128 balance = marketManager.tokenBalances(weth);
        assertEq(balance, 120e18 - 3342241454654246);
    }

    function test_burnPUSD_exactOut_pass() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 10e18);
        marketManager.increasePosition(weth, BOB, 10e18);

        deal(address(weth), address(pusdManagerCallback), 10e18);
        marketManager.mintPUSD(
            weth,
            true,
            10e18,
            IPUSDManagerCallback(address(pusdManagerCallback)),
            abi.encode(IPositionRouterCommon.CallbackData({margin: 10e18, account: ALICE})),
            ALICE
        );

        vm.warp(block.timestamp + 2 hours);

        IMarketManager.PackedState memory packedState = marketManager.packedStates(weth);
        assertEq(packedState.lpNetSize, 7094962576570635);
        IPUSDManager.GlobalPUSDPosition memory position = marketManager.globalPUSDPositions(weth);
        assertEq(position.totalSupply, 29877883269);
        assertEq(pusd.balanceOf(ALICE), 29877883269);
        assertEq(weth.balanceOf(ALICE), 0);

        deal(address(pusd), address(pusdManagerCallback), 20000e6);
        marketManager.burnPUSD(
            weth,
            false,
            5e18,
            IPUSDManagerCallback(address(pusdManagerCallback)),
            abi.encode(IPositionRouterCommon.CallbackData({margin: 20000e6, account: ALICE})),
            ALICE
        );
        packedState = marketManager.packedStates(weth);
        assertEq(packedState.lpNetSize, 5010597414292771976);
        assertEq(pusd.balanceOf(ALICE), 34917862971);
        assertEq(weth.balanceOf(address(ALICE)), 5e18);
        uint128 balance = marketManager.tokenBalances(weth);
        assertEq(balance, 120e18 - 5e18);
    }

    function test_upgradeToAndCall_revertIf_notGov() public {
        vm.prank(address(0x1));
        vm.expectRevert(abi.encodeWithSelector(GovernableUpgradeable.Forbidden.selector));
        marketManager.upgradeToAndCall(address(0x2), bytes(""));
    }

    function test_upgradeToAndCall_revertIf_initializeTwice() public {
        address newImpl = address(new MarketManagerUpgradeable());
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        marketManager.upgradeToAndCall(
            newImpl,
            abi.encodeWithSelector(MarketManagerUpgradeable.initialize.selector, address(this), feeDistributor, true)
        );
    }

    function test_upgradeToAndCall_pass() public {
        address newImpl = address(new MarketManagerUpgradeable());
        marketManager.upgradeToAndCall(newImpl, bytes(""));
    }

    function test_updatePSMCollateralCap_revertIf_notGov() public {
        vm.prank(ALICE);
        vm.expectRevert(GovernableUpgradeable.Forbidden.selector);
        marketManager.updatePSMCollateralCap(weth, 10e18);
    }

    function test_updatePSMCollateralCap_pass() public {
        marketManager.updatePSMCollateralCap(weth, 10e18);
        IPSM.CollateralState memory state = marketManager.psmCollateralStates(weth);
        vm.assertTrue(state.cap == 10e18, "cap");
        vm.assertTrue(state.decimals == 18, "decimals");
        vm.assertTrue(state.balance == 0, "balance");
    }

    function test_psmMintPUSD_revertIf_notPlugin() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPluginManager.PluginInactive.selector, ALICE));
        marketManager.psmMintPUSD(dai, address(this));
    }

    function test_psmMintPUSD_mintZeroIf_notSet() public {
        deal(address(dai), address(marketManager), 10e18);
        vm.expectEmit();
        emit IPSM.PSMMinted(dai, address(this), 0, 0);
        marketManager.psmMintPUSD(dai, address(this));
        vm.assertTrue(pusd.balanceOf(address(this)) == 0);
    }

    function test_psmMintPUSD_mintZeroIf_exceedsCap() public {
        marketManager.updatePSMCollateralCap(dai, 10e18);
        deal(address(dai), address(marketManager), 10e18);
        vm.expectEmit();
        emit IPSM.PSMMinted(dai, address(this), 10e18, 10e6);
        marketManager.psmMintPUSD(dai, address(this));
        vm.assertTrue(pusd.balanceOf(address(this)) == 10e6);

        IPSM.CollateralState memory state = marketManager.psmCollateralStates(dai);
        vm.assertTrue(state.balance == 10e18);

        // Transfer 1e18
        deal(address(dai), address(marketManager), 11e18);
        vm.expectEmit();
        emit IPSM.PSMMinted(dai, address(this), 0, 0);
        marketManager.psmMintPUSD(dai, address(this));
        vm.assertTrue(pusd.balanceOf(address(this)) == 10e6);
    }

    function test_psmMintPUSD_mintZeroIf_withoutPaying() public {
        marketManager.updatePSMCollateralCap(dai, 10e18);
        vm.expectEmit();
        emit IPSM.PSMMinted(dai, address(this), 0, 0);
        marketManager.psmMintPUSD(dai, address(this));
        vm.assertTrue(pusd.balanceOf(address(this)) == 0);
    }

    function test_psmMintPUSD_passIf_cannotExceedsCap() public {
        marketManager.updatePSMCollateralCap(dai, 10e18);
        deal(address(dai), address(marketManager), 11e18);
        vm.expectEmit();
        emit IPSM.PSMMinted(dai, address(this), 10e18, 10e6);
        marketManager.psmMintPUSD(dai, address(this));
        vm.assertTrue(pusd.balanceOf(address(this)) == 10e6);
    }

    function test_psmBurnPUSD_revertIf_notPlugin() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPluginManager.PluginInactive.selector, ALICE));
        marketManager.psmBurnPUSD(dai, address(this));
    }

    function test_psmBurnPUSD_revertIf_collateralBalanceIsZero() public {
        marketManager.updatePSMCollateralCap(dai, 10e18);
        marketManager.updatePSMCollateralCap(usdt, 10e6);

        // Mint PUSD by paying DAI
        deal(address(dai), address(marketManager), 10e18);
        marketManager.psmMintPUSD(dai, address(this));
        vm.assertTrue(pusd.balanceOf(address(this)) == 10e6);

        // Burn PUSD, receive USDT or other unregistered collaterals
        pusd.transfer(address(marketManager), 10e6);
        vm.expectRevert(abi.encodeWithSelector(IPSM.InsufficientPSMBalance.selector, 10e6, 0));
        marketManager.psmBurnPUSD(usdt, address(this));
    }

    function test_psmBurnPUSD_receiveNothingIf_withoutPaying() public {
        marketManager.updatePSMCollateralCap(dai, 10e18);
        deal(address(dai), address(marketManager), 10e18);
        marketManager.psmMintPUSD(dai, address(this));
        vm.assertTrue(pusd.balanceOf(address(this)) == 10e6);

        vm.expectEmit();
        emit IPSM.PSMBurned(dai, address(this), 0, 0);
        uint96 receiveAmount = marketManager.psmBurnPUSD(dai, address(this));
        vm.assertTrue(receiveAmount == 0);

        vm.assertTrue(pusd.balanceOf(address(this)) == 10e6);
    }

    function test_psmBurnPUSD_revertIf_exceedsCollateralBalance() public {
        marketManager.updatePSMCollateralCap(dai, 10e18);
        marketManager.updatePSMCollateralCap(usdt, 10e6);

        deal(address(dai), address(marketManager), 10e18);
        marketManager.psmMintPUSD(dai, address(this));
        IPSM.CollateralState memory state = marketManager.psmCollateralStates(dai);

        deal(address(usdt), address(marketManager), 10e6);
        marketManager.psmMintPUSD(usdt, address(this));
        state = marketManager.psmCollateralStates(usdt);
        vm.assertTrue(state.balance == 10e6);

        pusd.transfer(address(marketManager), 20e6);
        vm.expectRevert(abi.encodeWithSelector(IPSM.InsufficientPSMBalance.selector, 20e6, 10e6));
        marketManager.psmBurnPUSD(usdt, address(this));
    }

    function test_psmBurnPUSD_pass() public {
        marketManager.updatePSMCollateralCap(dai, 10e18);
        deal(address(dai), address(marketManager), 10e18);
        marketManager.psmMintPUSD(dai, address(this));

        pusd.transfer(address(marketManager), 10e6);
        vm.expectEmit();
        emit IPSM.PSMBurned(dai, address(this), 10e6, 10e18);
        uint96 receiveAmount = marketManager.psmBurnPUSD(dai, address(this));
        vm.assertTrue(receiveAmount == 10e18);
        vm.assertTrue(dai.balanceOf(address(this)) == 10e18);

        IPSM.CollateralState memory state = marketManager.psmCollateralStates(dai);
        vm.assertTrue(state.balance == 0);
    }

    function test_psmBurnPUSD_passIf_receiveMultipleCollaterals() public {
        marketManager.updatePSMCollateralCap(dai, 10e18);
        marketManager.updatePSMCollateralCap(usdt, 10e6);

        // Use DAI as collateral to mint PUSD
        deal(address(dai), address(marketManager), 10e18);
        marketManager.psmMintPUSD(dai, address(this));

        // Use USDT as collateral to mint PUSD
        deal(address(usdt), address(marketManager), 10e6);
        marketManager.psmMintPUSD(usdt, address(this));

        vm.assertTrue(pusd.balanceOf(address(this)) == 20e6);

        // Burn PUSD, receive USDT
        pusd.transfer(address(marketManager), 10e6);
        vm.expectEmit();
        emit IPSM.PSMBurned(usdt, address(this), 10e6, 10e6);
        uint96 receiveAmount = marketManager.psmBurnPUSD(usdt, address(this));
        vm.assertTrue(receiveAmount == 10e6);
        IPSM.CollateralState memory state = marketManager.psmCollateralStates(usdt);
        vm.assertTrue(state.balance == 0);

        // Burn PUSD, receive DAI
        pusd.transfer(address(marketManager), 10e6);
        vm.expectEmit();
        emit IPSM.PSMBurned(dai, address(this), 10e6, 10e18);
        receiveAmount = marketManager.psmBurnPUSD(dai, address(this));
        vm.assertTrue(receiveAmount == 10e18);
        state = marketManager.psmCollateralStates(dai);
        vm.assertTrue(state.balance == 0);

        vm.assertTrue(dai.balanceOf(address(this)) == 10e18);
        vm.assertTrue(usdt.balanceOf(address(this)) == 10e6);
    }

    function test_govUseStabilityFund_revertIf_notGov() public {
        vm.prank(ALICE);
        vm.expectRevert(GovernableUpgradeable.Forbidden.selector);
        marketManager.govUseStabilityFund(weth, ALICE, 10e18);
    }

    function test_govUseStabilityFund_pass() public {
        dealMarketManager(weth, 100e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 10e18);
        marketManager.increasePosition(weth, BOB, 10e18);

        vm.warp(block.timestamp + 3600);
        marketManager.updatePrice(encodePrice(weth, PRICE << 1, uint32(block.timestamp)));

        (uint96 spread, uint96 actualMarginDelta) = marketManager.decreasePosition(
            weth,
            BOB,
            type(uint96).max,
            10e18,
            BOB
        );
        assertGt(spread, 0);

        marketManager.govUseStabilityFund(weth, CARRIE, spread);
        assertEq(marketManager.tokenBalances(weth), 100e18 + 10e18 - actualMarginDelta - spread);
        assertEq(weth.balanceOf(CARRIE), spread);
    }

    function test_repayLiquidityBufferDebt_revertIf_callerIsNotPlugin() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPluginManager.PluginInactive.selector, ALICE));
        marketManager.repayLiquidityBufferDebt(weth, ALICE, ALICE);
    }

    function _prepareRepayLiquidityBufferDebtState() private {
        dealMarketManager(weth, 1000e18);
        marketManager.mintLPT(weth, ALICE, ALICE);

        dealMarketManager(weth, 21e18);
        marketManager.increasePosition(weth, BOB, 200e18);

        deal(address(weth), address(pusdManagerCallback), 20e18);
        marketManager.mintPUSD(
            weth,
            true,
            20e18,
            IPUSDManagerCallback(address(pusdManagerCallback)),
            abi.encode(IPositionRouterCommon.CallbackData({margin: 20e18, account: ALICE})),
            ALICE
        );

        vm.warp(block.timestamp + 3600);
        marketManager.updatePrice(encodePrice(weth, PRICE >> 1, uint32(block.timestamp)));

        marketManager.liquidatePosition(weth, BOB, EXECUTOR);

        IMarketManager.LiquidityBufferModule memory liquidityBufferModuleBefore = marketManager.liquidityBufferModules(
            weth
        );
        assertEq(liquidityBufferModuleBefore.pusdDebt, 59744423153);
        assertEq(liquidityBufferModuleBefore.tokenPayback, 39936057548207949741);
    }

    function test_repayLiquidityBufferDebt_passIf_payAmountLessThanPUSDDebt() public {
        _prepareRepayLiquidityBufferDebtState();

        uint256 totalSupplyBefore = pusd.totalSupply();
        uint256 tokenBalanceBefore = marketManager.tokenBalances(weth);

        dealMarketManager(pusd, 100e6);
        vm.expectEmit();
        emit IMarketManager.LiquidityBufferModuleDebtRepaid(weth, CARRIE, 100e6, 66844829091303402);
        uint128 receiveAmount = marketManager.repayLiquidityBufferDebt(weth, CARRIE, CARRIE);

        assertEq(receiveAmount, 66844829091303402);
        IMarketManager.LiquidityBufferModule memory liquidityBufferModuleAfter = marketManager.liquidityBufferModules(
            weth
        );
        assertEq(liquidityBufferModuleAfter.pusdDebt, 59744423153 - 100e6);
        assertEq(liquidityBufferModuleAfter.tokenPayback, 39936057548207949741 - 66844829091303402);
        assertEq(pusd.totalSupply(), totalSupplyBefore - 100e6);
        assertEq(marketManager.tokenBalances(weth), tokenBalanceBefore - 66844829091303402);
    }

    function test_repayLiquidityBufferDebt_passIf_payAmountEqualPUSDDebt() public {
        _prepareRepayLiquidityBufferDebtState();

        uint256 totalSupplyBefore = pusd.totalSupply();
        uint256 tokenBalanceBefore = marketManager.tokenBalances(weth);

        dealMarketManager(pusd, 59744423153);
        vm.expectEmit();
        emit IMarketManager.LiquidityBufferModuleDebtRepaid(weth, CARRIE, 59744423153, 39936057548207949741);
        uint128 receiveAmount = marketManager.repayLiquidityBufferDebt(weth, CARRIE, CARRIE);

        assertEq(receiveAmount, 39936057548207949741);
        IMarketManager.LiquidityBufferModule memory liquidityBufferModuleAfter = marketManager.liquidityBufferModules(
            weth
        );
        assertEq(liquidityBufferModuleAfter.pusdDebt, 0);
        assertEq(liquidityBufferModuleAfter.tokenPayback, 0);
        assertEq(pusd.totalSupply(), totalSupplyBefore - 59744423153);
        assertEq(marketManager.tokenBalances(weth), tokenBalanceBefore - 39936057548207949741);
    }

    function test_repayLiquidityBufferDebt_burnPUSDDebtIf_payAmountGreaterThanPUSDDebt() public {
        _prepareRepayLiquidityBufferDebtState();

        uint256 totalSupplyBefore = pusd.totalSupply();
        uint256 tokenBalanceBefore = marketManager.tokenBalances(weth);

        dealMarketManager(pusd, 59744423153 + 100e6);
        vm.expectEmit();
        emit IMarketManager.LiquidityBufferModuleDebtRepaid(weth, CARRIE, 59744423153, 39936057548207949741);
        uint128 receiveAmount = marketManager.repayLiquidityBufferDebt(weth, CARRIE, CARRIE);

        assertEq(receiveAmount, 39936057548207949741);
        IMarketManager.LiquidityBufferModule memory liquidityBufferModuleAfter = marketManager.liquidityBufferModules(
            weth
        );
        assertEq(liquidityBufferModuleAfter.pusdDebt, 0);
        assertEq(liquidityBufferModuleAfter.tokenPayback, 0);
        assertEq(pusd.totalSupply(), totalSupplyBefore - 59744423153);
        assertEq(marketManager.tokenBalances(weth), tokenBalanceBefore - 39936057548207949741);
    }

    function dealMarketManager(IERC20 _market, uint256 _delta) private {
        uint256 balanceBefore = _market.balanceOf(address(marketManager));
        deal(address(_market), address(marketManager), balanceBefore + _delta);
    }

    function testFuzz_setPrices(int256 refPrice1, int256 refPrice2, uint64 price1, uint64 price2) public {
        vm.assume(
            refPrice1 > 0 &&
                refPrice2 > 0 &&
                refPrice1 < int256(uint256(type(uint64).max / 100)) &&
                refPrice2 < int256(uint256(type(uint64).max / 100)) &&
                price1 > 0 &&
                price2 > 0
        );
        vm.warp(1721795755);
        marketManager.updateMarketPriceFeedConfig(weth, IChainLinkAggregator(address(mockChanLink)), 0, 100e3);
        mockChanLink.setRoundData(100, refPrice1, 0, 0, 0);
        marketManager.updatePrice(encodePrice(weth, price1, 1721795753));

        mockChanLink.setRoundData(101, refPrice2, 0, 0, 0);
        marketManager.updatePrice(encodePrice(weth, price2, 1721795754));
    }

    function test_updatePrice_revertIf_notUpdater() public {
        vm.warp(1721795755);
        vm.prank(address(0x1234));
        vm.expectRevert(GovernableUpgradeable.Forbidden.selector);
        marketManager.updatePrice(encodePrice(weth, PRICE, 1721795753));
    }

    function test_updatePrice_passIf_isUpdater() public {
        vm.warp(1721795755);
        marketManager.updatePrice(encodePrice(weth, PRICE, 1721795753));

        vm.expectEmit(true, false, false, true, address(marketManager));
        emit IPriceFeed.PriceUpdated(IERC20(weth), PRICE, PRICE, PRICE);
        marketManager.updatePrice(encodePrice(weth, PRICE, 1721795754));
    }

    function test_updatePrice_passIf_updatePriceTwiceInOneSecond() public {
        vm.warp(1721795755);
        vm.expectEmit(true, false, false, true, address(marketManager));
        emit IPriceFeed.PriceUpdated(IERC20(weth), PRICE, PRICE, PRICE);
        marketManager.updatePrice(encodePrice(weth, PRICE, 1721795754));

        marketManager.updatePrice(encodePrice(weth, PRICE + 1, 1721795754));
        (uint64 minPrice, uint64 maxPrice) = marketManager.getPrice(weth);
        assertEq(minPrice, PRICE);
        assertEq(maxPrice, PRICE);
    }

    function test_updatePrice_passIf_refPriceFeedNotSet() public {
        vm.warp(1721795755);
        marketManager.updateMarketPriceFeedConfig(weth, IChainLinkAggregator(address(0x0)), 0, 30e3);
        vm.expectEmit(true, false, false, true, address(marketManager));
        emit IPriceFeed.PriceUpdated(IERC20(weth), PRICE, PRICE, PRICE);
        marketManager.updatePrice(encodePrice(weth, PRICE, 1721795754));
        (uint64 minPrice, uint64 maxPrice) = marketManager.getPrice(weth);
        assertEq(minPrice, PRICE);
        assertEq(maxPrice, PRICE);
    }

    function test_updatePrice_passIf_reachMaxDeviationRatio() public {
        vm.warp(1721795755);
        marketManager.updateMarketPriceFeedConfig(weth, IChainLinkAggregator(address(mockChanLink)), 0, 200e3);
        vm.expectEmit(true, false, false, true, address(marketManager));
        uint64 upPrice = (PRICE * 111) / 100; // up 11%
        emit IPriceFeed.PriceUpdated(IERC20(weth), upPrice, fixedDefaultRefPrice, upPrice);
        marketManager.updatePrice(encodePrice(weth, upPrice, 1721795754));
        (uint64 minPrice, uint64 maxPrice) = marketManager.getPrice(weth);
        assertEq(minPrice, fixedDefaultRefPrice);
        assertEq(maxPrice, upPrice);

        uint64 downPrice = (PRICE * 89) / 100; // down 11%
        vm.expectEmit(true, false, false, true, address(marketManager));
        emit IPriceFeed.PriceUpdated(IERC20(weth), downPrice, downPrice, fixedDefaultRefPrice);
        marketManager.updatePrice(encodePrice(weth, downPrice, 1721795755));
        (minPrice, maxPrice) = marketManager.getPrice(weth);
        assertEq(minPrice, downPrice);
        assertEq(maxPrice, fixedDefaultRefPrice);
    }

    function test_updatePrice_passIf_reachMaxDeltaDiff() public {
        vm.warp(1721795755);
        marketManager.updateMarketPriceFeedConfig(weth, IChainLinkAggregator(address(mockChanLink)), 0, 100e3);
        // PRICE
        vm.expectEmit(true, false, false, true, address(marketManager));
        emit IPriceFeed.PriceUpdated(IERC20(weth), PRICE, PRICE, PRICE);
        marketManager.updatePrice(encodePrice(weth, PRICE, 1721795753));
        (uint64 minPrice, uint64 maxPrice) = marketManager.getPrice(weth);
        assertEq(minPrice, PRICE);
        assertEq(maxPrice, PRICE);

        // 1.04 * PRICE
        vm.expectEmit(true, false, false, true, address(marketManager));
        uint64 upPrice = (PRICE * 104) / 100; // up 4%
        emit IPriceFeed.PriceUpdated(IERC20(weth), upPrice, upPrice, upPrice);
        marketManager.updatePrice(encodePrice(weth, upPrice, 1721795754));
        (minPrice, maxPrice) = marketManager.getPrice(weth);
        assertEq(minPrice, upPrice);
        assertEq(maxPrice, upPrice);

        // PRICE
        vm.expectEmit(true, false, false, true, address(marketManager));
        emit IPriceFeed.PriceUpdated(IERC20(weth), PRICE, PRICE, PRICE);
        marketManager.updatePrice(encodePrice(weth, PRICE, 1721795755));
        (minPrice, maxPrice) = marketManager.getPrice(weth);
        assertEq(minPrice, PRICE);
        assertEq(maxPrice, PRICE);

        // 1.04 * PRICE
        vm.expectEmit(true, false, false, true, address(marketManager));
        emit IPriceFeed.MaxCumulativeDeltaDiffExceeded(IERC20(weth), upPrice, fixedDefaultRefPrice, 118459, 0);
        vm.expectEmit(true, false, false, true, address(marketManager));
        emit IPriceFeed.PriceUpdated(IERC20(weth), upPrice, fixedDefaultRefPrice, upPrice);
        marketManager.updatePrice(encodePrice(weth, upPrice, 1721795756));
        (minPrice, maxPrice) = marketManager.getPrice(weth);
        assertEq(minPrice, fixedDefaultRefPrice);
        assertEq(maxPrice, upPrice);

        // 1 minutes passed
        vm.warp(1721795756 + 1 minutes);
        vm.expectEmit(true, false, false, true, address(marketManager));
        emit IPriceFeed.PriceUpdated(IERC20(weth), upPrice, upPrice, upPrice);
        marketManager.updatePrice(encodePrice(weth, upPrice, 1721795756 + 1 minutes));
        (minPrice, maxPrice) = marketManager.getPrice(weth);
        assertEq(minPrice, upPrice);
        assertEq(maxPrice, upPrice);
    }
}

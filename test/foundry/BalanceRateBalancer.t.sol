// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import "forge-std/Test.sol";
import "../../contracts/plugins/BalanceRateBalancer.sol";
import "../../contracts/test/MockMarketManager.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {WETH9} from "../../contracts/test/WETH9.sol";
import "../../contracts/test/ERC20Test.sol";
import "../../contracts/plugins/DirectExecutablePlugin.sol";
import "../../contracts/plugins/interfaces/IBalanceRateBalancer.sol";
import "../../contracts/test/MockCurveSwap.sol";
import "../../contracts/plugins/interfaces/IPositionRouterCommon.sol";

contract BalanceRateBalancerTest is Test {
    BalanceRateBalancer balancer;
    IMarketManager marketManager;
    DirectExecutablePlugin plugin;
    MockCurveSwap curveSwap = new MockCurveSwap();

    address gov = address(this);
    address executor = address(0x1);

    address pusdImpl = address(new PUSDUpgradeable());
    IPUSD usd =
        IPUSD(
            address(
                new ERC1967Proxy(pusdImpl, abi.encodeWithSelector(PUSDUpgradeable.initialize.selector, address(this)))
            )
        );
    IERC20 weth = IERC20(address(new WETH9()));
    IERC20 dai = new ERC20Test("DAI", "DAI", 6, 0);

    function setUp() public {
        Governable govImpl = new Governable(gov);
        marketManager = IMarketManager(
            address(new MockMarketManager(PUSDUpgradeable(address(usd)), IWETHMinimum(address(weth))))
        );
        usd.setMinter(address(marketManager), true);

        plugin = new DirectExecutablePlugin(
            govImpl,
            usd,
            IMarketManager(address(marketManager)),
            IWETHMinimum(address(weth))
        );
        IPositionRouterCommon.EstimatedGasLimitType[]
            memory estimatedGasLimitTypes = new IPositionRouterCommon.EstimatedGasLimitType[](1);
        estimatedGasLimitTypes[0] = IPositionRouterCommon.EstimatedGasLimitType.IncreaseBalanceRate;
        uint256[] memory estimatedGasLimits = new uint256[](1);
        estimatedGasLimits[0] = 0;

        balancer = new BalanceRateBalancer(
            govImpl,
            marketManager,
            usd,
            plugin,
            estimatedGasLimitTypes,
            estimatedGasLimits
        );
        balancer.updatePositionExecutor(executor, true);
    }

    function test_createIncreaseBalanceRate_revertIf_notGov() public {
        vm.prank(address(0x2));

        vm.expectRevert(abi.encodeWithSelector(GovernableUpgradeable.Forbidden.selector));
        balancer.createIncreaseBalanceRate(IERC20(address(weth)), dai, 1000e6, new address[](0), new bytes[](0));
    }

    function test_createIncreaseBalanceRate_revertIf_insufficientExecutionFee() public {
        vm.txGasPrice(1);
        balancer.updateEstimatedGasLimit(IPositionRouterCommon.EstimatedGasLimitType.IncreaseBalanceRate, 1e17);

        vm.expectRevert(abi.encodeWithSelector(IPositionRouterCommon.InsufficientExecutionFee.selector, 0, 1e17));
        balancer.createIncreaseBalanceRate(IERC20(address(weth)), dai, 1000e6, new address[](0), new bytes[](0));
    }

    function test_createIncreaseBalanceRate_revertIf_invalidCallbackData() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0x1);

        vm.expectRevert(abi.encodeWithSelector(IBalanceRateBalancer.InvalidCallbackData.selector));
        balancer.createIncreaseBalanceRate(IERC20(address(weth)), dai, 1000e6, targets, new bytes[](0));
    }

    function _prepareEmptyCreateParam()
        private
        view
        returns (IBalanceRateBalancer.IncreaseBalanceRateRequestIdParam memory param)
    {
        IBalanceRateBalancer.IncreaseBalanceRateRequestIdParam memory param = IBalanceRateBalancer
            .IncreaseBalanceRateRequestIdParam({
                market: weth,
                collateral: dai,
                amount: 1000e6,
                executionFee: 0,
                account: gov,
                targets: new address[](0),
                calldatas: new bytes[](0)
            });

        return param;
    }

    function _createIncreaseBalanceRate(IBalanceRateBalancer.IncreaseBalanceRateRequestIdParam memory param) private {
        balancer.createIncreaseBalanceRate(
            param.market,
            param.collateral,
            param.amount,
            param.targets,
            param.calldatas
        );
    }

    function test_createIncreaseBalanceRate_success() public {
        IBalanceRateBalancer.IncreaseBalanceRateRequestIdParam memory param = _prepareEmptyCreateParam();

        vm.expectEmit();
        emit IBalanceRateBalancer.IncreaseBalanceRateCreated(
            param.market,
            param.collateral,
            param.amount,
            param.executionFee,
            param.account,
            param.targets,
            param.calldatas,
            keccak256(abi.encode(param))
        );
        _createIncreaseBalanceRate(param);
    }

    function test_createIncreaseBalanceRate_requireConflictRequests() public {
        IBalanceRateBalancer.IncreaseBalanceRateRequestIdParam memory param = _prepareEmptyCreateParam();

        _createIncreaseBalanceRate(param);
        vm.expectRevert(
            abi.encodeWithSelector(IPositionRouterCommon.ConflictRequests.selector, keccak256(abi.encode(param)))
        );
        _createIncreaseBalanceRate(param);
    }

    function test_cancelIncreaseBalanceRate_success() public {
        IBalanceRateBalancer.IncreaseBalanceRateRequestIdParam memory param = _prepareEmptyCreateParam();
        _createIncreaseBalanceRate(param);

        vm.prank(executor);
        bool result = balancer.cancelIncreaseBalanceRate(param, payable(executor));
        assertTrue(result);
    }

    function test_executeIncreaseBalanceRate_success() public {
        // use 1weth to swap 2000dai
        uint256 amount = 1e18;
        uint256 minDy = 2000e18;
        // marketManager has already minted 8000 pus;mint cap 20000 pusd;mint 2000 pusd at current tx.
        ERC20Test(payable(address(dai))).mint(address(marketManager), 8000e18);
        MockMarketManager(address(marketManager)).setPSMCollateralState(
            IPSM.CollateralState({decimals: 18, balance: 8000e18, cap: 20000e18})
        );

        // mockMarketManger need eth to mint weth
        vm.deal(address(marketManager), 10000 ether);
        // mint 1 weth to balancer
        vm.deal(address(balancer), 1 ether);
        vm.prank(address(balancer));
        WETH9(payable(address(weth))).deposit{value: amount}();
        // mint dai to curveSwap
        ERC20Test(payable(address(dai))).mint(address(curveSwap), minDy);

        bytes[] memory calldatas = new bytes[](3);
        address[4] memory route = [address(weth), address(1), address(dai), address(1)];
        uint256[] memory swapParam = new uint256[](0);
        uint256[][] memory swapParams = new uint256[][](0);
        address[5] memory pools = [address(1), address(1), address(1), address(1), address(1)];

        // 1. approve weth to curveSwap
        // 2. exchange from weth to dai, transfer dai to balancer
        // 3. approve dai to marketManager，mint pusd
        calldatas[0] = abi.encodeWithSelector(ERC20.approve.selector, address(curveSwap), amount);
        calldatas[1] = abi.encodeWithSelector(
            MockCurveSwap.exchange.selector,
            route,
            swapParams,
            amount,
            minDy,
            pools,
            address(balancer)
        );
        calldatas[2] = abi.encodeWithSelector(ERC20.approve.selector, address(marketManager), minDy);

        address[] memory targets = new address[](3);
        targets[0] = address(weth);
        targets[1] = address(curveSwap);
        targets[2] = address(dai);

        IBalanceRateBalancer.IncreaseBalanceRateRequestIdParam memory param = IBalanceRateBalancer
            .IncreaseBalanceRateRequestIdParam({
                market: weth,
                collateral: dai,
                amount: 2000e6,
                executionFee: 0,
                account: gov,
                targets: targets,
                calldatas: calldatas
            });
        _createIncreaseBalanceRate(param);
        balancer.updatePositionExecutor(address(balancer), true);
        plugin.updatePSMMinters(address(balancer), true);
        // use 1 weth to burn 2000pusd
        MockMarketManager(address(marketManager)).setReceiveAmount(1e18);
        MockMarketManager(address(marketManager)).setPayAmount(2000e6);

        vm.prank(executor);
        vm.expectEmit();
        emit IBalanceRateBalancer.IncreaseBalanceRateExecuted(keccak256(abi.encode(param)), payable(executor), 0);
        balancer.executeOrCancelIncreaseBalanceRate(param, true, payable(executor));
        assertEq(marketManager.psmCollateralStates(dai).balance, 10000e18);
    }
}

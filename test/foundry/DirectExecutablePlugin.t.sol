// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import "./PermitUtil.sol";
import "forge-std/Test.sol";
import "../../contracts/test/ERC20Test.sol";
import "../../contracts/test/MockMarketManager.sol";
import "../../contracts/plugins/DirectExecutablePlugin.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {WETH9} from "../../contracts/test/WETH9.sol";

contract DirectExecutablePluginTest is Test {
    DirectExecutablePlugin plugin;
    MockMarketManager marketManager;

    address gov = address(1);

    address pusdImpl = address(new PUSD());
    PUSD usd;

    IWETHMinimum weth = IWETHMinimum(address(new WETH9()));
    IERC20 dai = new ERC20Test("DAI", "DAI", 6, 0);
    PermitUtil permitUtil = new PermitUtil();

    address alice;
    uint256 alicePk;

    constructor() {
        Governable govImpl = new Governable(gov);
        marketManager = new MockMarketManager(weth);
        usd = marketManager.usd();
        plugin = new DirectExecutablePlugin(govImpl, IMarketManager(address(marketManager)), weth);
        (alice, alicePk) = makeAddrAndKey("alice");
    }

    function setUp() public {
        vm.deal(alice, 1 ether);
        vm.deal(address(weth), 1 ether);
    }

    function test_receiveETH() public {
        vm.prank(alice);
        vm.expectRevert(IMarketErrors.InvalidCaller.selector);
        (bool ok, ) = address(plugin).call{value: 0.1 ether}("");

        vm.prank(address(weth));
        (ok, ) = address(plugin).call{value: 0.1 ether}("");
        vm.assertTrue(ok);

        vm.assertTrue(address(plugin).balance == 0.1 ether);
    }

    function test_updateLiquidityBufferDebtPayer() public {
        vm.prank(alice);
        vm.expectRevert(GovernableProxy.Forbidden.selector);
        plugin.updateLiquidityBufferDebtPayer(alice, true);

        vm.prank(gov);
        vm.expectEmit();
        emit IDirectExecutablePlugin.LiquidityBufferDebtPayerUpdated(alice, true);
        plugin.updateLiquidityBufferDebtPayer(alice, true);
        bool active = plugin.liquidityBufferDebtPayers(alice);
        vm.assertTrue(active);
    }

    function test_updateAllowAnyoneRepayLiquidityBufferDebt() public {
        vm.prank(alice);
        vm.expectRevert(GovernableProxy.Forbidden.selector);
        plugin.updateAllowAnyoneRepayLiquidityBufferDebt(true);

        vm.prank(gov);
        plugin.updateAllowAnyoneRepayLiquidityBufferDebt(true);
        bool allowAnyone = plugin.allowAnyoneRepayLiquidityBufferDebt();
        vm.assertTrue(allowAnyone);
    }

    function test_updatePSMMinters() public {
        vm.prank(alice);
        vm.expectRevert(GovernableProxy.Forbidden.selector);
        plugin.updatePSMMinters(alice, true);

        vm.prank(gov);
        vm.expectEmit();
        emit IDirectExecutablePlugin.PSMMinterUpdated(alice, true);
        plugin.updatePSMMinters(alice, true);
        bool active = plugin.psmMinters(alice);
        vm.assertTrue(active);
    }

    function test_updateAllowAnyoneUsePSM() public {
        vm.prank(alice);
        vm.expectRevert(GovernableProxy.Forbidden.selector);
        plugin.updateAllowAnyoneUsePSM(true);

        vm.prank(gov);
        plugin.updateAllowAnyoneUsePSM(true);
        bool allowAnyone = plugin.allowAnyoneUsePSM();
        vm.assertTrue(allowAnyone);
    }

    function test_psmMintPUSD() public {
        vm.prank(alice);
        vm.expectRevert(GovernableProxy.Forbidden.selector);
        plugin.psmMintPUSD(IERC20(address(weth)), 1, alice, "");

        deal(address(dai), address(marketManager), 1e6);
        marketManager.setPSMCollateralState(IPSM.CollateralState({cap: 100e6, decimals: 8, balance: 1e6}));

        vm.prank(alice);
        dai.approve(address(marketManager), type(uint256).max);
        deal(address(dai), alice, 1000e6);

        uint256 snapshot = vm.snapshot();
        vm.prank(gov);
        plugin.updateAllowAnyoneUsePSM(true);
        vm.prank(alice);
        // Test that `allowAnyoneUsePSM` worked
        plugin.psmMintPUSD(dai, 1e6, alice, "");

        vm.revertTo(snapshot);

        vm.prank(gov);
        plugin.updatePSMMinters(alice, true);

        vm.startPrank(alice);
        // amount > 0 && amount + balance < cap, ok
        plugin.psmMintPUSD(dai, 1e6, alice, "");
        vm.assertTrue(dai.balanceOf(alice) == 1000e6 - 1e6);
        vm.assertTrue(dai.balanceOf(address(marketManager)) == 2e6);
        marketManager.setPSMCollateralState(IPSM.CollateralState({cap: 100e6, decimals: 8, balance: 2e6}));

        // Exceeds the mint cap
        vm.expectRevert(abi.encodeWithSelector(IDirectExecutablePlugin.PSMCapExceeded.selector, 2e6, 100e6, 100e6));
        plugin.psmMintPUSD(dai, 100e6, alice, "");

        // Someone transfer `dai` to market manager directly
        deal(address(dai), address(marketManager), 100e6);
        // Then no minting is allowed anymore
        vm.expectRevert(abi.encodeWithSelector(IDirectExecutablePlugin.PSMCapExceeded.selector, 100e6, 1e6, 100e6));
        plugin.psmMintPUSD(dai, 1e6, alice, "");

        // But can still mint without paying
        plugin.psmMintPUSD(dai, 0, alice, "");
    }

    function test_psmMintPUSD_revertIf_noAllowance() public {
        vm.prank(gov);
        plugin.updatePSMMinters(alice, true);
        deal(address(dai), address(marketManager), 1e6);
        marketManager.setPSMCollateralState(IPSM.CollateralState({cap: 100e6, decimals: 8, balance: 1e6}));

        deal(address(dai), alice, 1000e6);
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(marketManager), 0, 1e6)
        );
        plugin.psmMintPUSD(dai, 1e6, alice, "");
    }

    function test_psmMintPUSD_permit_pass() public {
        vm.prank(gov);
        plugin.updatePSMMinters(alice, true);
        deal(address(dai), address(marketManager), 1e6);
        marketManager.setPSMCollateralState(IPSM.CollateralState({cap: 100e6, decimals: 8, balance: 1e6}));

        deal(address(dai), alice, 1000e6);
        vm.startPrank(alice);
        vm.expectEmit();
        emit IERC20.Approval(address(alice), address(marketManager), 1e6);
        plugin.psmMintPUSD(
            dai,
            1e6,
            alice,
            permitUtil.constructIERC20PermitCalldata(
                alice,
                address(marketManager),
                1e6,
                type(uint256).max,
                0,
                IERC20Permit(address(dai)).DOMAIN_SEPARATOR(),
                alicePk
            )
        );

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(marketManager), 0, 1e6)
        );
        plugin.psmMintPUSD(dai, 1e6, alice, "");
    }

    function test_psmBurnPUSD_permit_revertIf_noAllowance() public {
        deal(address(usd), address(alice), 100e6);
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(marketManager), 0, 1e6)
        );
        plugin.psmBurnPUSD(dai, 1e6, alice, "");
    }

    function test_psmBurnPUSD_permit_pass() public {
        deal(address(usd), address(alice), 100e6);
        vm.startPrank(alice);
        vm.expectEmit();
        emit IERC20.Approval(address(alice), address(marketManager), 1e6);
        plugin.psmBurnPUSD(
            dai,
            1e6,
            alice,
            permitUtil.constructIERC20PermitCalldata(
                alice,
                address(marketManager),
                1e6,
                type(uint256).max,
                0,
                IERC20Permit(address(usd)).DOMAIN_SEPARATOR(),
                alicePk
            )
        );

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(marketManager), 0, 1e6)
        );
        plugin.psmBurnPUSD(dai, 1e6, alice, "");
    }

    function test_repayLiquidityBufferDebt() public {
        marketManager.setLiquidityBufferModule(10e6, 1e18);
        vm.prank(alice);
        usd.approve(address(marketManager), type(uint256).max);

        vm.prank(alice);
        vm.expectRevert(GovernableProxy.Forbidden.selector);
        plugin.repayLiquidityBufferDebt(IERC20(address(weth)), 1, alice, bytes(""));

        // allowAnyoneRepayLiquidityBufferDebt=true
        vm.prank(gov);
        plugin.updateAllowAnyoneRepayLiquidityBufferDebt(true);

        deal(address(usd), address(marketManager), 1e6);
        deal(address(weth), address(marketManager), 1e18);
        vm.prank(alice);
        uint256 aliceBalanceBefore = alice.balance;
        // amount=0&usd.balanceOf(marketManager)=1, repay 1usd
        plugin.repayLiquidityBufferDebt(IERC20(address(weth)), 0, alice, bytes(""));
        assertEq(alice.balance - aliceBalanceBefore, 1e17);
        assertEq(usd.balanceOf(address(marketManager)), 0);
        (uint128 pusdDebt, uint128 tokenPayback) = marketManager.liquidityBufferModule();
        assertEq(tokenPayback, 9e17);
        assertEq(pusdDebt, 9e6);

        // updateLiquidityBufferDebtPayer
        vm.prank(gov);
        plugin.updateAllowAnyoneRepayLiquidityBufferDebt(false);
        vm.prank(gov);
        plugin.updateLiquidityBufferDebtPayer(alice, true);

        deal(address(usd), address(marketManager), 1e6);
        vm.prank(alice);
        aliceBalanceBefore = alice.balance;
        // amount=0&usd.balanceOf(marketManager)=1, repay 1usd
        plugin.repayLiquidityBufferDebt(IERC20(address(weth)), 0, alice, bytes(""));
        assertEq(alice.balance - aliceBalanceBefore, 1e17);
        assertEq(usd.balanceOf(address(marketManager)), 0);
        (pusdDebt, tokenPayback) = marketManager.liquidityBufferModule();
        assertEq(tokenPayback, 8e17);
        assertEq(pusdDebt, 8e6);

        deal(address(usd), alice, 1e6);
        vm.prank(alice);
        aliceBalanceBefore = alice.balance;
        // amount=1&usd.balanceOf(marketManager)=0, repay 1usd
        plugin.repayLiquidityBufferDebt(IERC20(address(weth)), 1e6, alice, bytes(""));
        assertEq(alice.balance - aliceBalanceBefore, 1e17);
        assertEq(usd.balanceOf(address(marketManager)), 0);
        (pusdDebt, tokenPayback) = marketManager.liquidityBufferModule();
        assertEq(tokenPayback, 7e17);
        assertEq(pusdDebt, 7e6);

        // unexpected transfer usd to market manager
        deal(address(usd), address(marketManager), 1e6);
        deal(address(usd), alice, 7e6);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDirectExecutablePlugin.TooMuchRepaid.selector, 1e6, 7e6, 7e6));
        // amount=7&usd.balanceOf(marketManager)=1, repay 8usd revert
        plugin.repayLiquidityBufferDebt(IERC20(address(weth)), 7e6, alice, bytes(""));

        // receiver is contract
        deal(address(usd), alice, 1e6);
        vm.prank(alice);
        aliceBalanceBefore = alice.balance;
        // amount=1&usd.balanceOf(marketManager)=1, repay 1usd
        plugin.repayLiquidityBufferDebt(IERC20(address(weth)), 1e6, address(usd), bytes(""));
        assertEq(alice.balance - aliceBalanceBefore, 0);
        assertEq(usd.balanceOf(address(marketManager)), 0);
        (pusdDebt, tokenPayback) = marketManager.liquidityBufferModule();
        assertEq(tokenPayback, 5e17);
        assertEq(pusdDebt, 5e6);
        // contract receive weth
        assertEq(address(usd).balance, 0);
        assertEq(weth.balanceOf(address(usd)), 2e17);
    }
}

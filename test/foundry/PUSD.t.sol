// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import "forge-std/Test.sol";
import "../../contracts/core/PUSDUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PUSDTest is Test {
    PUSDUpgradeable private pusd;

    function setUp() public {
        PUSDUpgradeable impl = new PUSDUpgradeable();
        pusd = PUSDUpgradeable(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeWithSelector(PUSDUpgradeable.initialize.selector, address(this))
                )
            )
        );
    }

    function test_initialize_revertIf_initializeTwice() public {
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        pusd.initialize(address(this));
    }

    function test_decimals_pass() public view {
        assertEq(Constants.DECIMALS_6, pusd.decimals());
    }

    function test_setMinter_revertIf_notGov() public {
        vm.prank(address(0x1));
        vm.expectRevert(abi.encodeWithSelector(GovernableUpgradeable.Forbidden.selector));
        pusd.setMinter(address(this), true);
    }

    function test_setMinter_pass() public {
        vm.expectEmit();
        emit IPUSD.MinterUpdate(address(this), true);
        pusd.setMinter(address(this), true);
        assertTrue(pusd.minters(address(this)));

        vm.expectEmit();
        emit IPUSD.MinterUpdate(address(this), false);
        pusd.setMinter(address(this), false);
        assertFalse(pusd.minters(address(this)));
    }

    function test_mint_revertIf_notMinter() public {
        vm.expectRevert(abi.encodeWithSelector(IPUSD.InvalidMinter.selector));
        pusd.mint(address(0x1), 100);
    }

    function test_mint_pass() public {
        pusd.setMinter(address(0x1), true);
        vm.prank(address(0x1));
        vm.expectEmit();
        emit IERC20.Transfer(address(0), address(0x2), 100);
        pusd.mint(address(0x2), 100);
    }

    function test_burn_revertIf_notMinter() public {
        vm.expectRevert(abi.encodeWithSelector(IPUSD.InvalidMinter.selector));
        pusd.burn(100);
    }

    function test_burn_test() public {
        pusd.setMinter(address(0x1), true);
        pusd.setMinter(address(this), true);
        vm.prank(address(0x1));
        pusd.mint(address(this), 100);
        assertEq(100, pusd.balanceOf(address(this)));

        pusd.burn(100);
        assertEq(0, pusd.balanceOf(address(this)));
    }

    function test_upgradeToAndCall_revertIf_notGov() public {
        vm.prank(address(0x1));
        vm.expectRevert(abi.encodeWithSelector(GovernableUpgradeable.Forbidden.selector));
        pusd.upgradeToAndCall(address(0x2), bytes(""));
    }

    function test_upgradeToAndCall_revertIf_initializeTwice() public {
        address newImpl = address(new PUSDUpgradeable());
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        pusd.upgradeToAndCall(newImpl, abi.encodeWithSelector(PUSDUpgradeable.initialize.selector, address(this)));
    }

    function test_upgradeToAndCall_pass() public {
        address newImpl = address(new PUSDUpgradeable());
        pusd.upgradeToAndCall(newImpl, bytes(""));
    }
}

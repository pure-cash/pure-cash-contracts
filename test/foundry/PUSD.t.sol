// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import "forge-std/Test.sol";
import "../../contracts/core/PUSD.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PUSDTest is Test {
    PUSD private pusd;

    function setUp() public {
        pusd = new PUSD();
    }

    function test_decimals_pass() public view {
        assertEq(Constants.DECIMALS_6, pusd.decimals());
    }

    function test_mint_revertIf_notMinter() public {
        vm.prank(address(0x1));
        vm.expectRevert(abi.encodeWithSelector(IPUSD.InvalidMinter.selector));
        pusd.mint(address(0x1), 100);
    }

    function test_mint_pass() public {
        vm.expectEmit();
        emit IERC20.Transfer(address(0), address(0x2), 100);
        pusd.mint(address(0x2), 100);
    }

    function test_burn_revertIf_notMinter() public {
        vm.prank(address(0x1));
        vm.expectRevert(abi.encodeWithSelector(IPUSD.InvalidMinter.selector));
        pusd.burn(100);
    }

    function test_burn_test() public {
        pusd.mint(address(this), 100);
        assertEq(100, pusd.balanceOf(address(this)));

        pusd.burn(100);
        assertEq(0, pusd.balanceOf(address(this)));
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import "forge-std/Test.sol";
import "../../contracts/test/ERC20Test.sol";
import "../../contracts/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// `ExpectRevert` not working with `jump`, wrap with public methods
library TransferHelperWrapper {
    function safeTransfer(IERC20 _token, address _receiver, uint256 _amount) public {
        TransferHelper.safeTransfer(_token, _receiver, _amount);
    }

    function safeTransfer(IERC20 _token, address _receiver, uint256 _amount, uint256 _gasLimit) public {
        TransferHelper.safeTransfer(_token, _receiver, _amount, _gasLimit);
    }
}

// Mock a transfer that returns nothing
contract MockERC20 {
    function transfer(address to, uint256 value) external {}
}

// Mock a erc20 that has no method named `transfer`
contract MockERC20_2 {}

contract TransferHelperTest is Test {
    address immutable emptyAddr = address(0);
    address immutable nonexistentContract = address(1);
    address immutable alice = address(2);

    IERC20 token;

    function setUp() public {
        token = new ERC20Test("ERC20", "ERC20", 18, 0);
    }

    function test_safeTransfer_revertIf_invalidReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, emptyAddr));
        TransferHelperWrapper.safeTransfer(token, emptyAddr, 1e18);
    }

    function test_safeTransfer_revertIf_invalidContract() public {
        vm.expectRevert(abi.encodeWithSelector(Address.AddressEmptyCode.selector, nonexistentContract));
        TransferHelperWrapper.safeTransfer(IERC20(nonexistentContract), alice, 1e18);
    }

    function test_safeTransfer_revertIf_invalidERC20() public {
        IERC20 _token = IERC20(address(new MockERC20_2()));
        vm.expectRevert(Address.FailedInnerCall.selector);
        TransferHelperWrapper.safeTransfer(_token, alice, 1e18);
    }

    function test_safeTransfer_revertIf_transferReturnsFalse() public {
        ERC20Test(payable(address(token))).setTransferRes(false);
        deal(address(token), address(this), 1e18);
        vm.expectRevert(abi.encodeWithSelector(TransferHelper.TransferFailed.selector, token));
        TransferHelperWrapper.safeTransfer(token, alice, 1e18);
    }

    function test_safeTransfer_passIf_returnsTrue() public {
        deal(address(token), address(this), 1e18);
        TransferHelperWrapper.safeTransfer(token, alice, 1e18);
        vm.assertTrue(token.balanceOf(address(this)) == 0);
        vm.assertTrue(token.balanceOf(alice) == 1e18);
    }

    function test_safeTransfer_passIf_returnsNothing() public {
        IERC20 _token = IERC20(address(new MockERC20()));
        TransferHelperWrapper.safeTransfer(_token, alice, 1e18);
    }

    // The gas cost of `transfer` can be seen in the output trace(-vvvv) which is 1000
    function test_safeTransfer_specifyGasLimit() public {
        deal(address(token), address(this), 1e18);
        ERC20Test(payable(address(token))).setDrainGasInTransfer(true);
        try TransferHelperWrapper.safeTransfer(token, alice, 1e18, 1000) {} catch {}
    }
}

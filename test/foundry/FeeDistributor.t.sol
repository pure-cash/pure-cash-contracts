// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import "forge-std/Test.sol";
import "../../contracts/test/ERC20Test.sol";
import "../../contracts/core/FeeDistributorUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract FeeDistributorTest is Test {
    FeeDistributorUpgradeable private fd;

    function setUp() public {
        FeeDistributorUpgradeable impl = new FeeDistributorUpgradeable();
        fd = FeeDistributorUpgradeable(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeWithSelector(
                        FeeDistributorUpgradeable.initialize.selector,
                        address(this),
                        0.7692307 * 1e7, // 50/65
                        0.1538461 * 1e7 // 10/65
                    )
                )
            )
        );
    }

    function test_deposit() public {
        ERC20Test erc20 = new ERC20Test("", "", 18, 0);
        deal(address(erc20), address(fd), 100);
        vm.expectEmit();
        emit FeeDistributorUpgradeable.FeeDeposited(erc20, 76, 15, 9);
        fd.deposit(erc20);

        (uint128 protocolFee, uint128 ecosystemFee, uint128 developmentFund) = fd.feeDistributions(erc20);
        assertEq(76, protocolFee);
        assertEq(15, ecosystemFee);
        assertEq(9, developmentFund);
    }

    function test_deposit_twice() public {
        ERC20Test erc20 = new ERC20Test("", "", 18, 0);
        deal(address(erc20), address(fd), 100);
        vm.expectEmit();
        emit FeeDistributorUpgradeable.FeeDeposited(erc20, 76, 15, 9);
        fd.deposit(erc20);

        (uint128 protocolFee, uint128 ecosystemFee, uint128 developmentFund) = fd.feeDistributions(erc20);
        assertEq(76, protocolFee);
        assertEq(15, ecosystemFee);
        assertEq(9, developmentFund);

        deal(address(erc20), address(fd), 200);
        vm.expectEmit();
        emit FeeDistributorUpgradeable.FeeDeposited(erc20, 76, 15, 9);
        fd.deposit(erc20);

        (protocolFee, ecosystemFee, developmentFund) = fd.feeDistributions(erc20);
        assertEq(76 * 2, protocolFee);
        assertEq(15 * 2, ecosystemFee);
        assertEq(9 * 2, developmentFund);
    }

    function testFuzz_deposit(address _caller, uint128 _amount) public {
        vm.assume(_caller != address(0));
        vm.prank(_caller);
        ERC20Test erc20 = new ERC20Test("", "", 18, 0);
        deal(address(erc20), address(fd), _amount);
        vm.expectEmit();
        uint128 protocolFeeDelta = uint128((uint256(_amount) * fd.protocolFeeRate()) / 1e7);
        uint128 ecosystemFeeDelta = uint128((uint256(_amount) * fd.ecosystemFeeRate()) / 1e7);
        uint128 developmentFundDelta = _amount - protocolFeeDelta - ecosystemFeeDelta;
        emit FeeDistributorUpgradeable.FeeDeposited(erc20, protocolFeeDelta, ecosystemFeeDelta, developmentFundDelta);
        fd.deposit(erc20);

        (uint128 protocolFee, uint128 ecosystemFee, uint128 developmentFund) = fd.feeDistributions(erc20);
        assertEq(protocolFeeDelta, protocolFee);
        assertEq(ecosystemFeeDelta, ecosystemFee);
        assertEq(developmentFundDelta, developmentFund);
    }

    function test_withdrawProtocolFee_revertIf_notGov() public {
        vm.prank(address(0x1));
        vm.expectRevert(abi.encodeWithSelector(GovernableUpgradeable.Forbidden.selector));
        fd.withdrawProtocolFee(IERC20(address(0x2)), address(0x3), 0);
    }

    function test_withdrawEcosystemFee_revertIf_notGov() public {
        vm.prank(address(0x1));
        vm.expectRevert(abi.encodeWithSelector(GovernableUpgradeable.Forbidden.selector));
        fd.withdrawEcosystemFee(IERC20(address(0x2)), address(0x3), 0);
    }

    function test_withdrawDevelopmentFund_revertIf_notGov() public {
        vm.prank(address(0x1));
        vm.expectRevert(abi.encodeWithSelector(GovernableUpgradeable.Forbidden.selector));
        fd.withdrawDevelopmentFund(IERC20(address(0x2)), address(0x3), 0);
    }

    function test_withdrawProtocolFee() public {
        ERC20Test erc20 = new ERC20Test("", "", 18, 0);
        deal(address(erc20), address(fd), 100);
        vm.expectEmit();
        emit FeeDistributorUpgradeable.FeeDeposited(erc20, 76, 15, 9);
        fd.deposit(erc20);

        vm.expectEmit();
        emit FeeDistributorUpgradeable.ProtocolFeeWithdrawal(erc20, address(0x1), 3);
        fd.withdrawProtocolFee(erc20, address(0x1), 3);

        (uint128 protocolFee, , ) = fd.feeDistributions(erc20);
        assertEq(73, protocolFee);
    }

    function test_withdrawEcosystemFee() public {
        ERC20Test erc20 = new ERC20Test("", "", 18, 0);
        deal(address(erc20), address(fd), 100);
        vm.expectEmit();
        emit FeeDistributorUpgradeable.FeeDeposited(erc20, 76, 15, 9);
        fd.deposit(erc20);

        vm.expectEmit();
        emit FeeDistributorUpgradeable.EcosystemFeeWithdrawal(erc20, address(0x1), 3);
        fd.withdrawEcosystemFee(erc20, address(0x1), 3);

        (, uint128 ecosystemFee, ) = fd.feeDistributions(erc20);
        assertEq(12, ecosystemFee);
    }

    function test_withdrawDevelopmentFund() public {
        ERC20Test erc20 = new ERC20Test("", "", 18, 0);
        deal(address(erc20), address(fd), 100);
        vm.expectEmit();
        emit FeeDistributorUpgradeable.FeeDeposited(erc20, 76, 15, 9);
        fd.deposit(erc20);

        vm.expectEmit();
        emit FeeDistributorUpgradeable.DevelopmentFundWithdrawal(erc20, address(0x1), 3);
        fd.withdrawDevelopmentFund(erc20, address(0x1), 3);

        (, , uint128 developmentFund) = fd.feeDistributions(erc20);
        assertEq(6, developmentFund);
    }

    function test_upgradeToAndCall_revertIf_notGov() public {
        vm.prank(address(0x1));
        vm.expectRevert(abi.encodeWithSelector(GovernableUpgradeable.Forbidden.selector));
        fd.upgradeToAndCall(address(0x2), bytes(""));
    }

    function test_upgradeToAndCall_revertIf_initializeTwice() public {
        address newImpl = address(new FeeDistributorUpgradeable());
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        fd.upgradeToAndCall(
            newImpl,
            abi.encodeWithSelector(FeeDistributorUpgradeable.initialize.selector, address(this), 123, 456)
        );
    }

    function test_upgradeToAndCall_pass() public {
        address newImpl = address(new FeeDistributorUpgradeable());
        fd.upgradeToAndCall(newImpl, bytes(""));
    }
}

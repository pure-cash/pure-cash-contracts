// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import "forge-std/Test.sol";
import "./PermitUtil.sol";
import "../../contracts/test/ERC20Test.sol";
import "../../contracts/staking/StakingUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract StakingTest is Test {
    uint8 internal constant DECIMALS = 18;
    uint128 internal constant TOTAL_SUPPLY = 1_000 * 10_000 * 1e18;
    uint128 internal constant ERC20_LIMIT = 1_000 * 1e18;

    ERC20Test erc20;
    StakingUpgradeable private stakingUpgradeable;

    address alice;
    address bob;
    uint256 alicePk;
    uint256 bobPk;
    PermitUtil permitUtil;

    event Staked(IERC20 indexed token, address sender, address receiver, uint256 amount);
    event Unstaked(IERC20 indexed token, address account, address receiver, uint128 amount);
    event MaxStakedLimitSet(IERC20 indexed token, uint256 limit);

    function setUp() public {
        StakingUpgradeable impl = new StakingUpgradeable();
        stakingUpgradeable = StakingUpgradeable(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeWithSelector(StakingUpgradeable.initialize.selector, address(this))
                )
            )
        );
        permitUtil = new PermitUtil();
        (alice, alicePk) = makeAddrAndKey("alice");
        (bob, bobPk) = makeAddrAndKey("bob");
        erc20 = new ERC20Test("ERC20 TOKEN", "ERC20", DECIMALS, TOTAL_SUPPLY);
        erc20.mint(alice, TOTAL_SUPPLY);
        stakingUpgradeable.setMaxStakedLimit(erc20, ERC20_LIMIT);
        deal(alice, 100 ether);
        deal(bob, 100 ether);
    }

    function test_SetUpState() public view {
        assertEq(erc20.balanceOf(alice), TOTAL_SUPPLY);
        assertEq(stakingUpgradeable.maxStakedLimit(erc20), ERC20_LIMIT);
        assertEq(alice.balance, 100 * 1e18);
        assertEq(bob.balance, 100 * 1e18);
    }

    function test_stake_permit_revertIf_noAllowance() public {
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(stakingUpgradeable),
                0,
                1e18
            )
        );
        stakingUpgradeable.stake(erc20, alice, 1e18, "");
    }

    function test_stake_permit_pass() public {
        vm.startPrank(alice);
        vm.expectEmit();
        emit IERC20.Approval(alice, address(stakingUpgradeable), 1e18);
        stakingUpgradeable.stake(
            erc20,
            alice,
            1e18,
            permitUtil.constructIERC20PermitCalldata(
                alice,
                address(stakingUpgradeable),
                1e18,
                type(uint256).max,
                0,
                IERC20Permit(erc20).DOMAIN_SEPARATOR(),
                alicePk
            )
        );
    }

    function test_stake_revertIf_exceeded_max_staked_limit() public {
        vm.startPrank(alice);
        bytes memory permitCalldata = permitUtil.constructIERC20PermitCalldata(
            alice,
            address(stakingUpgradeable),
            1e18,
            type(uint256).max,
            0,
            IERC20Permit(erc20).DOMAIN_SEPARATOR(),
            alicePk
        );
        vm.expectRevert(abi.encodeWithSelector(IStaking.ExceededMaxStakedLimit.selector, 1001e18));
        stakingUpgradeable.stake(erc20, alice, 1001e18, permitCalldata);
    }

    function testFuzz_stake(uint128 _amount) public {
        vm.startPrank(alice);
        vm.assume(_amount <= ERC20_LIMIT);
        vm.expectEmit();
        emit Staked(erc20, alice, alice, _amount);
        stakingUpgradeable.stake(
            erc20,
            alice,
            _amount,
            permitUtil.constructIERC20PermitCalldata(
                alice,
                address(stakingUpgradeable),
                _amount,
                type(uint256).max,
                0,
                IERC20Permit(erc20).DOMAIN_SEPARATOR(),
                alicePk
            )
        );
        assertEq(erc20.balanceOf(alice), TOTAL_SUPPLY - _amount);
        assertEq(erc20.balanceOf(address(stakingUpgradeable)), _amount);
        assertEq(stakingUpgradeable.balances(erc20), _amount);
        assertEq(stakingUpgradeable.balancesPerAccount(alice, erc20), _amount);
    }

    function test_stake_to_own_address() public {
        vm.startPrank(alice);
        vm.expectEmit();
        emit Staked(erc20, alice, alice, 1e18);
        stakingUpgradeable.stake(
            erc20,
            alice,
            1e18,
            permitUtil.constructIERC20PermitCalldata(
                alice,
                address(stakingUpgradeable),
                1e18,
                type(uint256).max,
                0,
                IERC20Permit(erc20).DOMAIN_SEPARATOR(),
                alicePk
            )
        );
        assertEq(erc20.balanceOf(alice), TOTAL_SUPPLY - 1e18);
        assertEq(erc20.balanceOf(address(stakingUpgradeable)), 1e18);
        assertEq(stakingUpgradeable.balances(erc20), 1e18);
        assertEq(stakingUpgradeable.balancesPerAccount(alice, erc20), 1e18);
    }

    function test_stake_to_another_address() public {
        vm.startPrank(alice);
        vm.expectEmit();
        emit Staked(erc20, alice, bob, 1e18);
        stakingUpgradeable.stake(
            erc20,
            bob,
            1e18,
            permitUtil.constructIERC20PermitCalldata(
                alice,
                address(stakingUpgradeable),
                1e18,
                type(uint256).max,
                0,
                IERC20Permit(erc20).DOMAIN_SEPARATOR(),
                alicePk
            )
        );
        assertEq(erc20.balanceOf(alice), TOTAL_SUPPLY - 1e18);
        assertEq(erc20.balanceOf(address(stakingUpgradeable)), 1e18);
        assertEq(stakingUpgradeable.balances(erc20), 1e18);
        assertEq(stakingUpgradeable.balancesPerAccount(bob, erc20), 1e18);
    }

    function test_unstake_revertIf_invalid_input_amount() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IStaking.InvalidInputAmount.selector, 1e18));
        stakingUpgradeable.unstake(erc20, alice, 1e18);
    }

    function test_unstake_to_own_address() public {
        vm.startPrank(alice);
        stakingUpgradeable.stake(
            erc20,
            alice,
            1e18,
            permitUtil.constructIERC20PermitCalldata(
                alice,
                address(stakingUpgradeable),
                1e18,
                type(uint256).max,
                0,
                IERC20Permit(erc20).DOMAIN_SEPARATOR(),
                alicePk
            )
        );
        assertEq(erc20.balanceOf(alice), TOTAL_SUPPLY - 1e18);
        assertEq(erc20.balanceOf(address(stakingUpgradeable)), 1e18);
        assertEq(stakingUpgradeable.balances(erc20), 1e18);
        assertEq(stakingUpgradeable.balancesPerAccount(alice, erc20), 1e18);
        vm.expectEmit();
        emit Unstaked(erc20, alice, alice, 1e18);
        stakingUpgradeable.unstake(erc20, alice, 1e18);
        assertEq(erc20.balanceOf(alice), TOTAL_SUPPLY);
        assertEq(erc20.balanceOf(address(stakingUpgradeable)), 0);
        assertEq(stakingUpgradeable.balances(erc20), 0);
        assertEq(stakingUpgradeable.balancesPerAccount(alice, erc20), 0);
    }

    function test_unstake_to_another_address() public {
        vm.startPrank(alice);
        stakingUpgradeable.stake(
            erc20,
            alice,
            1e18,
            permitUtil.constructIERC20PermitCalldata(
                alice,
                address(stakingUpgradeable),
                1e18,
                type(uint256).max,
                0,
                IERC20Permit(erc20).DOMAIN_SEPARATOR(),
                alicePk
            )
        );
        assertEq(erc20.balanceOf(alice), TOTAL_SUPPLY - 1e18);
        assertEq(erc20.balanceOf(address(stakingUpgradeable)), 1e18);
        assertEq(stakingUpgradeable.balances(erc20), 1e18);
        assertEq(stakingUpgradeable.balancesPerAccount(alice, erc20), 1e18);
        vm.expectEmit();
        emit Unstaked(erc20, alice, bob, 1e18);
        stakingUpgradeable.unstake(erc20, bob, 1e18);
        assertEq(erc20.balanceOf(alice), TOTAL_SUPPLY - 1e18);
        assertEq(erc20.balanceOf(bob), 1e18);
        assertEq(erc20.balanceOf(address(stakingUpgradeable)), 0);
        assertEq(stakingUpgradeable.balances(erc20), 0);
        assertEq(stakingUpgradeable.balancesPerAccount(alice, erc20), 0);
    }

    function test_setMaxStakedLimit_revertIf_notGov() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(GovernableUpgradeable.Forbidden.selector));
        stakingUpgradeable.setMaxStakedLimit(erc20, ERC20_LIMIT);
    }

    function test_setMaxStakedLimit_revertIf_invalid_limit() public {
        vm.startPrank(alice);
        stakingUpgradeable.stake(
            erc20,
            alice,
            ERC20_LIMIT,
            permitUtil.constructIERC20PermitCalldata(
                alice,
                address(stakingUpgradeable),
                ERC20_LIMIT,
                type(uint256).max,
                0,
                IERC20Permit(erc20).DOMAIN_SEPARATOR(),
                alicePk
            )
        );
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(IStaking.InvalidLimit.selector, 100e18));
        stakingUpgradeable.setMaxStakedLimit(erc20, 100e18);
    }

    function test_setMaxStakedLimit() public {
        vm.expectEmit();
        emit MaxStakedLimitSet(erc20, 10000e18);
        stakingUpgradeable.setMaxStakedLimit(erc20, 10000e18);
        assertEq(stakingUpgradeable.maxStakedLimit(erc20), 10000e18);
    }
}

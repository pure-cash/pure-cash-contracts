// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import "forge-std/Test.sol";
import "../../contracts/core/LPToken.sol";
import "../../contracts/libraries/LiquidityUtil.sol";

contract LPTokenTest is Test {
    function setUp() public {}

    function test_initCodeHash() public pure {
        assertEq32(keccak256(type(LPToken).creationCode), LiquidityUtil.LP_TOKEN_INIT_CODE_HASH);
    }

    function test_initialize_revertIf_initializeTwice() public {
        LPToken token = LiquidityUtil.deployLPToken(IERC20(address(0x1)), "SomeSymbol");
        vm.expectRevert(abi.encodeWithSelector(LPToken.AlreadyInitialized.selector));
        token.initialize(IERC20(address(0x2)), "SomeSymbol2");
    }

    function test_mint_revertIf_notMarketManager() public {
        LPToken token = LiquidityUtil.deployLPToken(IERC20(address(0x1)), "SomeSymbol");
        vm.prank(address(0x1));
        vm.expectRevert(abi.encodeWithSelector(LPToken.Forbidden.selector));
        token.mint(address(0x1), 100);
    }

    function test_mint_pass() public {
        LPToken token = LiquidityUtil.deployLPToken(IERC20(address(0x1)), "SomeSymbol");
        token.mint(address(0x1), 100);
    }

    function test_burn_revertIf_notMarketManager() public {
        LPToken token = LiquidityUtil.deployLPToken(IERC20(address(0x1)), "SomeSymbol");
        vm.prank(address(0x1));
        vm.expectRevert(abi.encodeWithSelector(LPToken.Forbidden.selector));
        token.burn(100);
    }

    function test_burn_pass() public {
        LPToken token = LiquidityUtil.deployLPToken(IERC20(address(0x1)), "SomeSymbol");
        token.mint(address(this), 100);
        token.burn(100);
    }
}

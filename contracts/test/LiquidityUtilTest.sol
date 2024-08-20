// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../libraries/LiquidityUtil.sol";

contract LiquidityUtilTest {
    function LP_TOKEN_INIT_CODE_HASH() public pure returns (bytes32) {
        return LiquidityUtil.LP_TOKEN_INIT_CODE_HASH;
    }

    function deployLPToken(IERC20 _market, string calldata _tokenSymbol) public returns (LPToken token) {
        return LiquidityUtil.deployLPToken(_market, _tokenSymbol);
    }

    function computeLPTokenAddress(IERC20 _market) public view returns (address) {
        return LiquidityUtil.computeLPTokenAddress(_market);
    }
}

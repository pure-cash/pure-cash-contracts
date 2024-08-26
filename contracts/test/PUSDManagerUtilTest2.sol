// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../libraries/PUSDManagerUtil.sol";

contract PUSDManagerUtilTest2 {
    function PUSD_INIT_CODE_HASH() public pure returns (bytes32) {
        return PUSDManagerUtil.PUSD_INIT_CODE_HASH;
    }

    function deployPUSD() public returns (PUSD pusd) {
        return PUSDManagerUtil.deployPUSD();
    }

    function computePUSDAddress() public view returns (address) {
        return PUSDManagerUtil.computePUSDAddress();
    }
}

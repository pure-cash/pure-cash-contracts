// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract PermitUtil is Test {
    bytes32 private constant IERC20_PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function constructIERC20PermitCalldata(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint256 nonce,
        bytes32 domainSeparator,
        uint256 privateKey
    ) external pure returns (bytes memory _calldata) {
        bytes32 structHash = keccak256(abi.encode(IERC20_PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));
        bytes32 hash = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encode(owner, spender, value, deadline, v, r, s);
    }
}

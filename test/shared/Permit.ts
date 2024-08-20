import {ERC20Permit, IERC20} from "../../typechain-types";
import {Signature, Signer} from "ethers";
import {ethers} from "hardhat";
import {defaultAbiCoder} from "@ethersproject/abi";
import {time} from "@nomicfoundation/hardhat-network-helpers";

export async function genERC20PermitData(
    token: ERC20Permit,
    signer: Signer,
    spender: string,
    value: bigint,
    deadline?: bigint,
): Promise<string> {
    const owner = await signer.getAddress();
    const [name, nonce, verifyingContract, {chainId}] = await Promise.all([
        token.name(),
        token.nonces(owner),
        token.getAddress(),
        ethers.provider.getNetwork(),
    ]);
    deadline = deadline ?? BigInt((await time.latest()) + 3600);
    const signature = await signer.signTypedData(
        {name, version: "1", chainId, verifyingContract},
        {
            Permit: [
                {name: "owner", type: "address"},
                {name: "spender", type: "address"},
                {name: "value", type: "uint256"},
                {name: "nonce", type: "uint256"},
                {name: "deadline", type: "uint256"},
            ],
        },
        {owner, spender, value, nonce, deadline},
    );
    const {r, s, v} = Signature.from(signature);
    return defaultAbiCoder.encode(
        ["address", "address", "uint256", "uint256", "uint8", "bytes32", "bytes32"],
        [owner, spender, value, deadline, v, r, s],
    );
}

export async function resetAllowance(token: IERC20, signer: Signer, spender: string): Promise<void> {
    await token.connect(signer).approve(spender, 0n);
}

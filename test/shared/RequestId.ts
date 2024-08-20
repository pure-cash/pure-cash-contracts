import {ethers} from "hardhat";
import {Addressable} from "ethers";
import {AbiCoder} from "ethers";

export async function mintPUSDRequestId(param: {
    account: string;
    market: string | Addressable;
    exactIn: boolean;
    acceptableMaxPayAmount: bigint;
    acceptableMinReceiveAmount: bigint;
    receiver: string;
    executionFee: bigint;
}): Promise<string> {
    return ethers.keccak256(
        AbiCoder.defaultAbiCoder().encode(
            ["address", "address", "bool", "uint96", "uint64", "address", "uint256"],
            [
                param.account,
                param.market,
                param.exactIn,
                param.acceptableMaxPayAmount,
                param.acceptableMinReceiveAmount,
                param.receiver,
                param.executionFee,
            ],
        ),
    );
}

export async function burnPUSDRequestId(param: {
    market: string | Addressable;
    account: string;
    exactIn: boolean;
    acceptableMaxPayAmount: bigint;
    acceptableMinReceiveAmount: bigint;
    receiver: string;
    executionFee: bigint;
}): Promise<string> {
    return ethers.keccak256(
        AbiCoder.defaultAbiCoder().encode(
            ["address", "address", "bool", "uint64", "uint96", "address", "uint256"],
            [
                param.market,
                param.account,
                param.exactIn,
                param.acceptableMaxPayAmount,
                param.acceptableMinReceiveAmount,
                param.receiver,
                param.executionFee,
            ],
        ),
    );
}

export async function increasePositionRequestId(param: {
    account: string;
    market: string | Addressable;
    marginDelta: bigint;
    sizeDelta: bigint;
    acceptableIndexPrice: bigint;
    executionFee: bigint;
    payPUSD: boolean;
}): Promise<string> {
    return ethers.keccak256(
        AbiCoder.defaultAbiCoder().encode(
            ["address", "address", "uint96", "uint96", "uint64", "uint256", "bool"],
            [
                param.account,
                param.market,
                param.marginDelta,
                param.sizeDelta,
                param.acceptableIndexPrice,
                param.executionFee,
                param.payPUSD,
            ],
        ),
    );
}

export async function decreasePositionRequestId(param: {
    account: string;
    market: string | Addressable;
    marginDelta: bigint;
    sizeDelta: bigint;
    acceptableIndexPrice: bigint;
    receiver: string;
    executionFee: bigint;
    receivePUSD: boolean;
}): Promise<string> {
    return ethers.keccak256(
        AbiCoder.defaultAbiCoder().encode(
            ["address", "address", "uint96", "uint96", "uint64", "address", "uint256", "bool"],
            [
                param.account,
                param.market,
                param.marginDelta,
                param.sizeDelta,
                param.acceptableIndexPrice,
                param.receiver,
                param.executionFee,
                param.receivePUSD,
            ],
        ),
    );
}

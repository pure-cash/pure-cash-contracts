import {ContractTransactionResponse} from "ethers";

export async function gasUsed(txPromise: Promise<ContractTransactionResponse>): Promise<number> {
    const tx = await txPromise;
    const receipt = await tx.wait();
    return parseInt(receipt!.gasUsed.toString());
}

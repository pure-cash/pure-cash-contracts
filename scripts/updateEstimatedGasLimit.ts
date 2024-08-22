import {ethers, hardhatArguments, upgrades} from "hardhat";
import {networks} from "./networks";
import {HashZero} from "@ethersproject/constants";
import {AddressLike, BigNumberish} from "ethers";

export async function updateEstimatedGasLimit(chainId: bigint) {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const document = require(`../deployments/${chainId}.json`);

    const positionRouter = await ethers.getContractAt("PositionRouter", document.deployments.PositionRouter);
    const positionRouter2 = await ethers.getContractAt("PositionRouter2", document.deployments.PositionRouter2);
    const balanceRateBalancer = await ethers.getContractAt(
        "BalanceRateBalancer",
        document.deployments.BalanceRateBalancer,
    );

    let targets: AddressLike[] = [];
    let values: BigNumberish[] = [];
    let calldatas = [];
    const longonlyTimeLockController = await ethers.getContractAt(
        "PurecashTimelockController",
        document.deployments.LongonlyTimelockController,
    );

    for (let positionRouterKey in network.estimatedGasLimits.positionRouter) {
        calldatas.push(
            positionRouter.interface.encodeFunctionData("updateEstimatedGasLimit", [
                positionRouterKey,
                // @ts-ignore
                network.estimatedGasLimits.positionRouter[positionRouterKey],
            ]),
        );
        targets.push(await positionRouter.getAddress());
        values.push(0);
    }

    for (let positionRouter2Key in network.estimatedGasLimits.positionRouter2) {
        // @ts-ignore
        calldatas.push(
            positionRouter2.interface.encodeFunctionData("updateEstimatedGasLimit", [
                positionRouter2Key,
                // @ts-ignore
                network.estimatedGasLimits.positionRouter2[positionRouter2Key],
            ]),
        );
        targets.push(await positionRouter2.getAddress());
        values.push(0);
    }

    for (let balanceRateBalancerKey in network.estimatedGasLimits.balanceRateBalancer) {
        calldatas.push(
            balanceRateBalancer.interface.encodeFunctionData("updateEstimatedGasLimit", [
                balanceRateBalancerKey,
                // @ts-ignore
                network.estimatedGasLimits.balanceRateBalancer[balanceRateBalancerKey],
            ]),
        );
        targets.push(await balanceRateBalancer.getAddress());
        values.push(0);
    }

    const scheduleData = longonlyTimeLockController.interface.encodeFunctionData("scheduleBatch", [
        targets,
        values,
        calldatas,
        HashZero,
        HashZero,
        0,
    ]);

    const executeData = longonlyTimeLockController.interface.encodeFunctionData("executeBatch", [
        targets,
        values,
        calldatas,
        HashZero,
        HashZero,
    ]);
    console.log("longonlyTimeLockController: ", await longonlyTimeLockController.getAddress());
    console.log("scheduleData: ", scheduleData);
    console.log("executeData: ", executeData);
}

async function main() {
    await updateEstimatedGasLimit((await ethers.provider.getNetwork()).chainId);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

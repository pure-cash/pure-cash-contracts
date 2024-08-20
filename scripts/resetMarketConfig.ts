import {ethers, hardhatArguments} from "hardhat";
import {networks} from "./networks";
import {HashZero} from "@ethersproject/constants";
import {generateRandomBytes32} from "./util";

export async function resetMarketConfig(chainId: bigint) {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const document = require(`../deployments/${chainId}.json`);

    const marketManager = await ethers.getContractAt(
        "MarketManagerUpgradeable",
        document.deployments.MarketManagerUpgradeable,
    );

    const purecashTimeLockController = await ethers.getContractAt(
        "PurecashTimelockController",
        document.deployments.PurecashTimelockController,
    );

    let targets = [];
    let values = [];
    let calldatas = [];
    const salt = generateRandomBytes32();
    for (let item of network.markets) {
        targets.push(document.deployments.MarketManagerUpgradeable);
        values.push(0);
        calldatas.push(marketManager.interface.encodeFunctionData("updateMarketConfig", [item.token, item.marketCfg]));
    }
    const scheduleData = purecashTimeLockController.interface.encodeFunctionData("scheduleBatch", [
        targets,
        values,
        calldatas,
        HashZero,
        salt,
        0,
    ]);

    const executeData = purecashTimeLockController.interface.encodeFunctionData("executeBatch", [
        targets,
        values,
        calldatas,
        HashZero,
        salt,
    ]);
    console.log("purecashTimeLockController: ", await purecashTimeLockController.getAddress());
    console.log("scheduleData: ", scheduleData);
    console.log("executeData: ", executeData);
}

async function main() {
    await resetMarketConfig((await ethers.provider.getNetwork()).chainId);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

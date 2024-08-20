import {ethers, hardhatArguments, upgrades} from "hardhat";
import {networks} from "./networks";
import {HashZero} from "@ethersproject/constants";
import {generateRandomBytes32} from "./util";

export async function upgradeMarketManager(chainId: bigint) {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const document = require(`../deployments/${chainId}.json`);

    const MarketManagerUpgradeable = await ethers.getContractFactory("MarketManagerUpgradeable", {
        libraries: {
            ConfigurableUtil: document.deployments.ConfigurableUtil,
            LiquidityUtil: document.deployments.LiquidityUtil,
            MarketUtil: document.deployments.MarketUtil,
            PositionUtil: document.deployments.PositionUtil,
            PUSDManagerUtil: document.deployments.PUSDManagerUtil,
        },
    });
    const instance = await ethers.getContractAt(
        "MarketManagerUpgradeable",
        document.deployments.MarketManagerUpgradeable,
    );
    const purecashTimeLockController = await ethers.getContractAt(
        "PurecashTimelockController",
        document.deployments.PurecashTimelockController,
    );
    await upgrades.validateUpgrade(document.deployments.MarketManagerUpgradeable, MarketManagerUpgradeable);

    const marketManagerUpgradeableImpl = await MarketManagerUpgradeable.deploy();
    console.log("marketManagerUpgradeableImpl: ", await marketManagerUpgradeableImpl.getAddress());

    const salt = generateRandomBytes32();
    const scheduleData = purecashTimeLockController.interface.encodeFunctionData("schedule", [
        document.deployments.MarketManagerUpgradeable,
        0,
        instance.interface.encodeFunctionData("upgradeToAndCall", [
            await marketManagerUpgradeableImpl.getAddress(),
            "0x",
        ]),
        HashZero,
        salt,
        0,
    ]);

    const executeData = purecashTimeLockController.interface.encodeFunctionData("execute", [
        document.deployments.MarketManagerUpgradeable,
        0,
        instance.interface.encodeFunctionData("upgradeToAndCall", [
            await marketManagerUpgradeableImpl.getAddress(),
            "0x",
        ]),
        HashZero,
        salt,
    ]);
    console.log("purecashTimeLockController: ", await purecashTimeLockController.getAddress());
    console.log("scheduleData: ", scheduleData);
    console.log("executeData: ", executeData);
    // await upgrades.forceImport(document.deployments.MarketManagerUpgradeable, MarketManagerUpgradeable, {kind: "uups"});
}

async function main() {
    await upgradeMarketManager((await ethers.provider.getNetwork()).chainId);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

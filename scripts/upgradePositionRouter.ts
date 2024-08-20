import {ethers, hardhatArguments, upgrades} from "hardhat";
import {networks} from "./networks";

export async function upgradePositionRouter(chainId: bigint) {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const document = require(`../deployments/${chainId}.json`);

    const PositionRouter = await ethers.getContractFactory("PositionRouterUpgradeable");
    const instance = await ethers.getContractAt(
        "PositionRouterUpgradeable",
        document.deployments.PositionRouterUpgradeable,
    );
    const newInstance = await upgrades.upgradeProxy(instance, PositionRouter, {unsafeAllowRenames: true, kind: "uups"});
    console.log(`PositionRouterUpgradeable upgraded at ${await newInstance.getAddress()}`);
}

async function main() {
    await upgradePositionRouter((await ethers.provider.getNetwork()).chainId);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

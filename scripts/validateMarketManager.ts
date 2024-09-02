import {ethers, hardhatArguments, upgrades} from "hardhat";
import {networks} from "./networks";

async function main() {
    const chainId = (await ethers.provider.getNetwork()).chainId;
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const document = require(`../deployments/${chainId}.json`);

    const Factory = await ethers.getContractFactory("MarketManagerUpgradeable", {
        libraries: {
            ConfigurableUtil: document.deployments.ConfigurableUtil,
            LiquidityUtil: document.deployments.LiquidityUtil,
            MarketUtil: document.deployments.MarketUtil,
            PositionUtil: document.deployments.PositionUtil,
            PUSDManagerUtil: document.deployments.PUSDManagerUtil,
        },
    });
    await upgrades.validateUpgrade(document.deployments.MarketManagerUpgradeable, Factory, {kind: "uups"});
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

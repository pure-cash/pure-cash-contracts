import {ethers, hardhatArguments} from "hardhat";
import {networks} from "./networks";
import fs from "fs";

export async function upgradeLibraries(chainId: bigint) {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const documents = require(`../deployments/${chainId}.json`);

    // deploy libraries
    const {configurableUtil, liquidityUtil, marketUtil, positionUtil, pusdManagerUtil} = await deployLibraries();
    documents.deployments.ConfigurableUtil = await configurableUtil.getAddress();
    documents.deployments.LiquidityUtil = await liquidityUtil.getAddress();
    documents.deployments.MarketUtil = await marketUtil.getAddress();
    documents.deployments.PositionUtil = await positionUtil.getAddress();
    documents.deployments.PUSDManagerUtil = await pusdManagerUtil.getAddress();
    fs.writeFileSync(`deployments/${chainId}.json`, JSON.stringify(documents, null, 4));
    console.log(`💾 deployments output to deployments/${chainId}.json`);
}

async function main() {
    await upgradeLibraries((await ethers.provider.getNetwork()).chainId);
}

async function deployLibraries() {
    const PUSDManagerUtil = await ethers.getContractFactory("PUSDManagerUtil");
    const pusdManagerUtil = await PUSDManagerUtil.deploy();

    const ConfigurableUtil = await ethers.getContractFactory("ConfigurableUtil");
    const configurableUtil = await ConfigurableUtil.deploy();

    const LiquidityUtil = await ethers.getContractFactory("LiquidityUtil");
    const liquidityUtil = await LiquidityUtil.deploy();

    const MarketUtil = await ethers.getContractFactory("MarketUtil");
    const marketUtil = await MarketUtil.deploy();

    const PositionUtil = await ethers.getContractFactory("PositionUtil");
    const positionUtil = await PositionUtil.deploy();

    await configurableUtil.waitForDeployment();
    await liquidityUtil.waitForDeployment();
    await marketUtil.waitForDeployment();
    await positionUtil.waitForDeployment();
    await pusdManagerUtil.waitForDeployment();

    console.log(`ConfigurableUtil deployed to: ${await configurableUtil.getAddress()}`);
    console.log(`LiquidityPositionUtil deployed to: ${await liquidityUtil.getAddress()}`);
    console.log(`MarketUtil deployed to: ${await marketUtil.getAddress()}`);
    console.log(`PositionUtil deployed to: ${await positionUtil.getAddress()}`);
    console.log(`PUSDManagerUtil deployed to: ${await pusdManagerUtil.getAddress()}`);

    return {
        configurableUtil,
        liquidityUtil,
        marketUtil,
        positionUtil,
        pusdManagerUtil,
    };
}
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

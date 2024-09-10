import {ethers, hardhatArguments} from "hardhat";
import {networks} from "./networks";
import {HashZero} from "@ethersproject/constants";
import {generateRandomBytes32} from "./util";
import fs from "fs";

export async function upgrade0910(chainId: bigint) {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const document = require(`../deployments/${chainId}.json`);

    // 1. deploy libraries
    const {positionUtil, pusdManagerUtil, positionReader, liquidityReader} = await deployLibraries(
        document.deployments.LiquidityUtil,
    );
    document.deployments.PositionUtil = await positionUtil.getAddress();
    document.deployments.PUSDManagerUtil = await pusdManagerUtil.getAddress();
    document.deployments.PositionReader = await positionReader.getAddress();
    document.deployments.LiquidityReader = await liquidityReader.getAddress();

    // 2. deploy reader
    const Reader = await ethers.getContractFactory("Reader", {
        libraries: {
            LiquidityReader: document.deployments.LiquidityReader,
            PositionReader: document.deployments.PositionReader,
            PUSDManagerUtil: document.deployments.PUSDManagerUtil,
        },
    });
    const reader = await Reader.deploy(document.deployments.MarketManagerUpgradeable);
    document.deployments.Reader = await reader.getAddress();
    console.log(`Reader deployed to: ${await reader.getAddress()}`);

    // 3. deploy new MarketManagerImpl
    const MarketManagerUpgradeable = await ethers.getContractFactory("MarketManagerUpgradeable", {
        libraries: {
            ConfigurableUtil: document.deployments.ConfigurableUtil,
            LiquidityUtil: document.deployments.LiquidityUtil,
            MarketUtil: document.deployments.MarketUtil,
            PositionUtil: document.deployments.PositionUtil,
            PUSDManagerUtil: document.deployments.PUSDManagerUtil,
        },
    });
    const marketManagerUpgradeableImpl = await MarketManagerUpgradeable.deploy();
    console.log("new marketManagerUpgradeableImpl: ", await marketManagerUpgradeableImpl.getAddress());

    // 4. write to deployments
    fs.writeFileSync(`deployments/${chainId}.json`, JSON.stringify(document, null, 4));
    console.log(`💾 deployments output to deployments/${chainId}.json`);

    const purecashTimeLockController = await ethers.getContractAt(
        "PurecashTimelockController",
        document.deployments.PurecashTimelockController,
    );
    let targets = [];
    let values = [];
    let calldatas = [];
    const salt = generateRandomBytes32();

    // 5. upgrade market manager
    const marketManager = await ethers.getContractAt(
        "MarketManagerUpgradeable",
        document.deployments.MarketManagerUpgradeable,
    );
    targets.push(document.deployments.MarketManagerUpgradeable);
    calldatas.push(
        marketManager.interface.encodeFunctionData("upgradeToAndCall", [
            await marketManagerUpgradeableImpl.getAddress(),
            "0x",
        ]),
    );
    values.push(0);

    // 6. update estimated gas limit
    const positionRouter = await ethers.getContractAt("PositionRouter", document.deployments.PositionRouter);
    const positionRouter2 = await ethers.getContractAt("PositionRouter2", document.deployments.PositionRouter2);
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

    const scheduleData = purecashTimeLockController.interface.encodeFunctionData("scheduleBatch", [
        targets,
        values,
        calldatas,
        HashZero,
        salt,
        network.timelockController.minDelay,
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

async function deployLibraries(liquidityUtilAddress: string) {
    const PositionUtil = await ethers.getContractFactory("PositionUtil");
    const positionUtil = await PositionUtil.deploy();

    const PUSDManagerUtil = await ethers.getContractFactory("PUSDManagerUtil");
    const pusdManagerUtil = await PUSDManagerUtil.deploy();

    const PositionReader = await ethers.getContractFactory("PositionReader", {
        libraries: {
            PUSDManagerUtil: await pusdManagerUtil.getAddress(),
            PositionUtil: await positionUtil.getAddress(),
        },
    });
    const positionReader = await PositionReader.deploy();

    const LiquidityReader = await ethers.getContractFactory("LiquidityReader", {
        libraries: {
            PUSDManagerUtil: pusdManagerUtil,
            LiquidityUtil: await liquidityUtilAddress,
        },
    });
    const liquidityReader = await LiquidityReader.deploy();

    await positionReader.waitForDeployment();
    await pusdManagerUtil.waitForDeployment();
    await positionUtil.waitForDeployment();
    await liquidityReader.waitForDeployment();

    console.log(`PositionReader deployed to: ${await positionReader.getAddress()}`);
    console.log(`PusdManagerUtil deployed to: ${await pusdManagerUtil.getAddress()}`);
    console.log(`PositionUtil deployed to: ${await positionUtil.getAddress()}`);
    console.log(`LiquidityReader deployed to: ${await liquidityReader.getAddress()}`);

    return {
        positionUtil,
        pusdManagerUtil,
        positionReader,
        liquidityReader,
    };
}

async function main() {
    await upgrade0910((await ethers.provider.getNetwork()).chainId);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

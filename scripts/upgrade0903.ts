import {ethers, hardhatArguments} from "hardhat";
import {networks} from "./networks";
import {HashZero} from "@ethersproject/constants";
import {generateRandomBytes32} from "./util";
import fs from "fs";

export async function upgrade0903(chainId: bigint) {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const document = require(`../deployments/${chainId}.json`);

    // 1. deploy libraries
    const {configurableUtil, liquidityUtil, positionReader, liquidityReader} = await deployLibraries(
        document.deployments.PUSDManagerUtil,
        document.deployments.PositionUtil
    );
    document.deployments.ConfigurableUtil = await configurableUtil.getAddress();
    document.deployments.LiquidityUtil = await liquidityUtil.getAddress();
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
        document.deployments.PurecashTimelockController
    );
    let targets = [];
    let values = [];
    let calldatas = [];
    const salt = generateRandomBytes32();

    // 5. upgrade market manager
    const marketManager = await ethers.getContractAt(
        "MarketManagerUpgradeable",
        document.deployments.MarketManagerUpgradeable
    );
    targets.push(document.deployments.MarketManagerUpgradeable);
    calldatas.push(
        marketManager.interface.encodeFunctionData("upgradeToAndCall", [
            await marketManagerUpgradeableImpl.getAddress(),
            "0x",
        ])
    );
    values.push(0);

    // 6. update market config
    for (let item of network.markets) {
        targets.push(document.deployments.MarketManagerUpgradeable);
        values.push(0);
        calldatas.push(marketManager.interface.encodeFunctionData("updateMarketConfig", [item.token, item.marketCfg]));
    }

    // 7. update estimated gas limit
    const positionRouter = await ethers.getContractAt("PositionRouter", document.deployments.PositionRouter);
    const positionRouter2 = await ethers.getContractAt("PositionRouter2", document.deployments.PositionRouter2);
    for (let positionRouterKey in network.estimatedGasLimits.positionRouter) {
        calldatas.push(
            positionRouter.interface.encodeFunctionData("updateEstimatedGasLimit", [
                positionRouterKey,
                // @ts-ignore
                network.estimatedGasLimits.positionRouter[positionRouterKey],
            ])
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
            ])
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

async function deployLibraries(PUSDManagerUtil: string, positionUtil: string) {
    const ConfigurableUtil = await ethers.getContractFactory("ConfigurableUtil");
    const configurableUtil = await ConfigurableUtil.deploy();

    const LiquidityUtil = await ethers.getContractFactory("LiquidityUtil");
    const liquidityUtil = await LiquidityUtil.deploy();

    const PositionReader = await ethers.getContractFactory("PositionReader", {
        libraries: {
            PUSDManagerUtil: PUSDManagerUtil,
            PositionUtil: positionUtil,
        },
    });
    const positionReader = await PositionReader.deploy();

    const LiquidityReader = await ethers.getContractFactory("LiquidityReader", {
        libraries: {
            PUSDManagerUtil: PUSDManagerUtil,
            LiquidityUtil: await liquidityUtil.getAddress(),
        },
    });
    const liquidityReader = await LiquidityReader.deploy();

    await configurableUtil.waitForDeployment();
    await liquidityUtil.waitForDeployment();
    await positionReader.waitForDeployment();
    await liquidityReader.waitForDeployment();

    console.log(`ConfigurableUtil deployed to: ${await configurableUtil.getAddress()}`);
    console.log(`LiquidityPositionUtil deployed to: ${await liquidityUtil.getAddress()}`);
    console.log(`PositionReader deployed to: ${await positionReader.getAddress()}`);
    console.log(`LiquidityReader deployed to: ${await liquidityReader.getAddress()}`);

    return {
        configurableUtil,
        liquidityUtil,
        positionReader,
        liquidityReader,
    };
}

async function main() {
    await upgrade0903((await ethers.provider.getNetwork()).chainId);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

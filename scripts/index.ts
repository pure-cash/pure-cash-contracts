import {ethers, hardhatArguments, upgrades} from "hardhat";
import {networks} from "./networks";
import {getContractAddress} from "@ethersproject/address";
import {getCreate2Address} from "@ethersproject/address";
import {keccak256} from "@ethersproject/keccak256";
import {toUtf8Bytes} from "@ethersproject/strings";
import {bytecode} from "../artifacts/contracts/core/LPToken.sol/LPToken.json";
import {defaultAbiCoder} from "@ethersproject/abi";
import {AddressZero} from "@ethersproject/constants";

async function main() {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }

    if (network.weth === undefined) {
        // @ts-ignore
        network.weth = await deployMarketToken("WETH9");
    }
    const deployments = new Map<string, string | {index: number; market: string}[]>();
    // deploy libraries
    const {
        configurableUtil,
        liquidityUtil,
        marketUtil,
        positionUtil,
        pusdManagerUtil,
        liquidityReader,
        positionReader,
    } = await deployLibraries();
    const txReceipt = await configurableUtil.runner!.provider!.getTransactionReceipt(
        (await configurableUtil.deploymentTransaction())!.hash,
    );
    console.log(`First contract deployed at block ${txReceipt!.blockNumber}`);
    deployments.set("ConfigurableUtil", await configurableUtil.getAddress());
    deployments.set("LiquidityUtil", await liquidityUtil.getAddress());
    deployments.set("MarketUtil", await marketUtil.getAddress());
    deployments.set("PositionUtil", await positionUtil.getAddress());
    deployments.set("PUSDManagerUtil", await pusdManagerUtil.getAddress());
    deployments.set("LiquidityReader", await liquidityReader.getAddress());
    deployments.set("PositionReader", await positionReader.getAddress());

    const [deployer] = await ethers.getSigners();
    let nonce = await deployer.getNonce();
    console.log(`deployer address: ${deployer.address}, nonce: ${nonce}`);

    const purecashTimelockControllerAddr = getContractAddress({from: deployer.address, nonce: nonce++});
    const pluginsGovernableAddr = getContractAddress({from: deployer.address, nonce: nonce++});
    const positionRouterAddr = getContractAddress({from: deployer.address, nonce: nonce++});
    const positionRouter2Addr = getContractAddress({from: deployer.address, nonce: nonce++});
    nonce += 1; // skip the implementation contract
    // market manager address
    const marketManagerAddr = getContractAddress({from: deployer.address, nonce: nonce++});
    // mixed executor address
    const mixedExecutorAddr = getContractAddress({from: deployer.address, nonce: nonce++});
    // executor assistant address
    const executorAssistantAddr = getContractAddress({from: deployer.address, nonce: nonce++});
    // liquidator address
    const liquidatorAddr = getContractAddress({from: deployer.address, nonce: nonce++});
    nonce += 1; // skip the implementation contract
    // PUSD address
    const PUSDAddr = getContractAddress({from: deployer.address, nonce: nonce++});
    nonce += 1; // skip the implementation contract
    // fee distributor address
    const feeDistributorAddr = getContractAddress({from: deployer.address, nonce: nonce++});
    // Reader address
    const readerAddr = getContractAddress({from: deployer.address, nonce: nonce++});
    const directExecutablePluginAddr = getContractAddress({from: deployer.address, nonce: nonce++});

    deployments.set("PositionRouter", positionRouterAddr);
    deployments.set("PositionRouter2", positionRouter2Addr);
    deployments.set("Liquidator", liquidatorAddr);
    deployments.set("MarketManagerUpgradeable", marketManagerAddr);
    deployments.set("MixedExecutor", mixedExecutorAddr);
    deployments.set("ExecutorAssistant", executorAssistantAddr);
    deployments.set("PUSDUpgradeable", PUSDAddr);
    deployments.set("FeeDistributorUpgradeable", feeDistributorAddr);
    deployments.set("Reader", readerAddr);
    deployments.set("DirectExecutablePlugin", directExecutablePluginAddr);
    deployments.set("Governable", pluginsGovernableAddr);
    deployments.set("PurecashTimelockController", purecashTimelockControllerAddr);

    // deploy timelockController
    const timelockConfig = network.timelockController;
    const PurecashTimelockController = await ethers.getContractFactory("PurecashTimelockController");
    timelockConfig.executors.push(deployer.address);
    let timelockAdmin = deployer.address;
    if (timelockConfig.admin) {
        timelockAdmin = timelockConfig.admin;
    }
    const purecashTimelockController = await PurecashTimelockController.deploy(
        timelockConfig.minDelay,
        timelockConfig.proposers,
        timelockConfig.executors,
        timelockAdmin,
    );
    expectAddr(await purecashTimelockController.getAddress(), purecashTimelockControllerAddr);
    console.log(`timelockController deployed to: ${await purecashTimelockController.getAddress()}`);

    // deploy Governable for plugins
    const Governable = await ethers.getContractFactory("Governable");
    const pluginsGovernable = await Governable.deploy(deployer.address);
    await pluginsGovernable.waitForDeployment();
    expectAddr(await pluginsGovernable.getAddress(), pluginsGovernableAddr);
    console.log(`pluginsGovernable deployed to: ${await pluginsGovernable.getAddress()}`);

    // deploy plugins
    const PositionRouter = await ethers.getContractFactory("PositionRouter");
    const positionRouter = await PositionRouter.deploy(
        pluginsGovernableAddr,
        PUSDAddr,
        marketManagerAddr,
        network.weth,
        network.minPositionRouterExecutionFee,
    );
    await positionRouter.waitForDeployment();
    expectAddr(await positionRouter.getAddress(), positionRouterAddr);
    console.log(`PositionRouter deployed to: ${await positionRouter.getAddress()}`);

    const PositionRouter2 = await ethers.getContractFactory("PositionRouter2");
    const positionRouter2 = await PositionRouter2.deploy(
        pluginsGovernableAddr,
        PUSDAddr,
        marketManagerAddr,
        network.weth,
        network.minPositionRouterExecutionFee,
    );
    await positionRouter2.waitForDeployment();
    expectAddr(await positionRouter2.getAddress(), positionRouter2Addr);
    console.log(`PositionRouter2 deployed to: ${await positionRouter2.getAddress()}`);

    // deploy market manager
    const MarketManager = await ethers.getContractFactory("MarketManagerUpgradeable", {
        libraries: {
            ConfigurableUtil: await configurableUtil.getAddress(),
            LiquidityUtil: await liquidityUtil.getAddress(),
            MarketUtil: await marketUtil.getAddress(),
            PositionUtil: await positionUtil.getAddress(),
            PUSDManagerUtil: await pusdManagerUtil.getAddress(),
        },
    });
    const marketManager = await upgrades.deployProxy(
        MarketManager,
        [deployer.address, feeDistributorAddr, PUSDAddr, true],
        {kind: "uups"},
    );
    await marketManager.waitForDeployment();
    expectAddr(await marketManager.getAddress(), marketManagerAddr);
    console.log(`MarketManager deployed to: ${await marketManager.getAddress()}`);

    // deploy mixed executor
    const MixedExecutor = await ethers.getContractFactory("MixedExecutor");

    const mixedExecutor = await MixedExecutor.deploy(
        pluginsGovernableAddr,
        liquidatorAddr,
        positionRouterAddr,
        positionRouter2Addr,
        marketManagerAddr,
    );
    await mixedExecutor.waitForDeployment();
    expectAddr(await mixedExecutor.getAddress(), mixedExecutorAddr);
    console.log(`MixedExecutor deployed to: ${await mixedExecutor.getAddress()}`);

    // deploy executor assistant
    const ExecutorAssistant = await ethers.getContractFactory("ExecutorAssistant");
    const executorAssistant = await ExecutorAssistant.deploy(positionRouterAddr, positionRouter2Addr);
    await executorAssistant.waitForDeployment();
    expectAddr(await executorAssistant.getAddress(), executorAssistantAddr);
    console.log(`ExecutorAssistant deployed to: ${await executorAssistant.getAddress()}`);

    // deploy liquidator
    const Liquidator = await ethers.getContractFactory("Liquidator");
    const liquidator = await Liquidator.deploy(pluginsGovernableAddr, marketManagerAddr);
    await liquidator.waitForDeployment();
    expectAddr(await liquidator.getAddress(), liquidatorAddr);
    console.log(`Liquidator deployed to: ${await liquidator.getAddress()}`);

    // deploy PUSD
    const PUSD = await ethers.getContractFactory("PUSDUpgradeable");
    const pusd = await upgrades.deployProxy(PUSD, [deployer.address], {kind: "uups"});
    await pusd.waitForDeployment();
    expectAddr(await pusd.getAddress(), PUSDAddr);
    console.log(`PUSD deployed to: ${await pusd.getAddress()}`);

    // deploy fee distributor
    const FeeDistributor = await ethers.getContractFactory("FeeDistributorUpgradeable");
    const feeDistributor = await upgrades.deployProxy(
        FeeDistributor,
        [deployer.address, network.feeDistributorCfg.protocolFeeRate, network.feeDistributorCfg.ecosystemFeeRate],
        {kind: "uups"},
    );
    await feeDistributor.waitForDeployment();
    expectAddr(await feeDistributor.getAddress(), feeDistributorAddr);
    console.log(`FeeDistributor deployed to: ${await feeDistributor.getAddress()}`);

    // deploy reader
    const Reader = await ethers.getContractFactory("Reader", {
        libraries: {
            LiquidityReader: await liquidityReader.getAddress(),
            PositionReader: await positionReader.getAddress(),
            PUSDManagerUtil: await pusdManagerUtil.getAddress(),
        },
    });
    const reader = await Reader.deploy(marketManagerAddr);
    await reader.waitForDeployment();
    expectAddr(await reader.getAddress(), readerAddr);
    console.log(`Reader deployed to: ${await reader.getAddress()}`);

    // deploy MiscUpgradeable
    const DirectExecutablePlugin = await ethers.getContractFactory("DirectExecutablePlugin");
    const directExecutablePlugin = await DirectExecutablePlugin.deploy(
        pluginsGovernableAddr,
        PUSDAddr,
        marketManagerAddr,
        network.weth,
    );
    await directExecutablePlugin.waitForDeployment();
    expectAddr(await directExecutablePlugin.getAddress(), directExecutablePluginAddr);
    console.log(`DirectExecutablePlugin deployed to: ${await directExecutablePlugin.getAddress()}`);

    let nonceAfterDeployContract = await deployer.getNonce();

    // initialize plugins
    await positionRouter.updatePositionExecutor(mixedExecutorAddr, true, {nonce: nonceAfterDeployContract++});
    await positionRouter2.updatePositionExecutor(mixedExecutorAddr, true, {nonce: nonceAfterDeployContract++});
    await liquidator.updateExecutor(mixedExecutorAddr, true, {nonce: nonceAfterDeployContract++});
    await marketManager.updateUpdater(mixedExecutorAddr, {nonce: nonceAfterDeployContract++});
    await marketManager.updatePlugin(directExecutablePluginAddr, true, {nonce: nonceAfterDeployContract++});
    await marketManager.updatePlugin(positionRouterAddr, true, {nonce: nonceAfterDeployContract++});
    await marketManager.updatePlugin(positionRouter2Addr, true, {nonce: nonceAfterDeployContract++});
    await marketManager.updatePlugin(mixedExecutorAddr, true, {nonce: nonceAfterDeployContract++});
    await marketManager.updatePlugin(liquidatorAddr, true, {nonce: nonceAfterDeployContract++});
    console.log("Initialize plugins finished");

    for (let collateral of network.collaterals) {
        if (collateral.token === undefined) {
            collateral.token = await deployMarketToken("ERC20Test", collateral.symbol, 18, nonceAfterDeployContract++);
        }
        await marketManager.updatePSMCollateralCap(collateral.token, collateral.cap, {
            nonce: nonceAfterDeployContract++,
        });
    }

    const lptTokenInitCodeHash = keccak256(bytecode);
    let markets = [];
    let index = 1;
    for (let item of network.markets) {
        let marketAddr = item.token;
        if (marketAddr == undefined) {
            if (item.tokenSymbol === "WETH") {
                marketAddr = network.weth;
            } else {
                marketAddr = await deployMarketToken(
                    item.tokenFactory,
                    item.lpTokenSymbol,
                    item.tokenDecimals,
                    nonceAfterDeployContract++,
                );
            }
            item.token = marketAddr;
        }
        await marketManager.enableMarket(marketAddr, item.lpTokenSymbol, item.marketCfg, {
            nonce: nonceAfterDeployContract++,
        });
        const lpToken = getCreate2Address(
            marketManagerAddr,
            defaultAbiCoder.encode(["address"], [item.token]),
            lptTokenInitCodeHash,
        );

        await marketManager.updateMarketPriceFeedConfig(
            item.token,
            item.chainLinkPriceFeed,
            0,
            network.maxCumulativeDeltaDiff,
            {
                nonce: nonceAfterDeployContract++,
            },
        );
        if (item.chainLinkPriceFeed == AddressZero) {
            console.warn(`👿👿${item.lpTokenSymbol} chainLinkPriceFeed is not set👿👿`);
        }

        markets.push({
            lpTokenSymbol: item.lpTokenSymbol,
            index: index++,
            market: marketAddr,
            lpToken: lpToken,
        });
    }
    deployments.set("registerMarkets", markets);

    // initialize PUSD
    await pusd.setMinter(marketManagerAddr, true, {nonce: nonceAfterDeployContract++});

    // initialize mixed executor
    for (let item of network.mixedExecutors) {
        await mixedExecutor.setExecutor(item, true, {nonce: nonceAfterDeployContract++});
    }
    console.log("Initialize mixed executor finished");

    // transfer ownership
    await pluginsGovernable.changeGov(purecashTimelockControllerAddr, {nonce: nonceAfterDeployContract++});
    await purecashTimelockController.acceptGov(pluginsGovernableAddr, {nonce: nonceAfterDeployContract++});
    await marketManager.changeGov(purecashTimelockControllerAddr, {nonce: nonceAfterDeployContract++});
    await purecashTimelockController.acceptGov(marketManagerAddr, {nonce: nonceAfterDeployContract++});
    await pusd.changeGov(purecashTimelockControllerAddr, {nonce: nonceAfterDeployContract++});
    await purecashTimelockController.acceptGov(PUSDAddr, {nonce: nonceAfterDeployContract++});
    await feeDistributor.changeGov(purecashTimelockControllerAddr, {nonce: nonceAfterDeployContract++});
    await purecashTimelockController.acceptGov(feeDistributorAddr, {nonce: nonceAfterDeployContract++});
    await purecashTimelockController.renounceRole(keccak256(toUtf8Bytes("EXECUTOR_ROLE")), deployer.address);

    // write deployments to file
    const deploymentsOutput = {
        block: txReceipt!.blockNumber,
        deployments: Object.fromEntries(deployments),
    };
    const fs = require("fs");
    if (!fs.existsSync("deployments")) {
        fs.mkdirSync("deployments");
    }
    const chainId = (await configurableUtil.runner!.provider!.getNetwork()).chainId;
    fs.writeFileSync(`deployments/${chainId}.json`, JSON.stringify(deploymentsOutput, null, 4));
    console.log(`💾 deployments output to deployments/${chainId}.json`);
}

function expectAddr(actual: string, expected: string) {
    if (actual != expected) {
        throw new Error(`actual address ${actual} is not equal to expected address ${expected}`);
    }
}

async function deployLibraries() {
    const [deployer] = await ethers.getSigners();
    let nonce = await deployer.getNonce();
    const PUSDManagerUtil = await ethers.getContractFactory("PUSDManagerUtil");
    const pusdManagerUtil = await PUSDManagerUtil.deploy({nonce: nonce++});

    const ConfigurableUtil = await ethers.getContractFactory("ConfigurableUtil");
    const configurableUtil = await ConfigurableUtil.deploy({nonce: nonce++});

    const LiquidityUtil = await ethers.getContractFactory("LiquidityUtil");
    const liquidityUtil = await LiquidityUtil.deploy({nonce: nonce++});

    const MarketUtil = await ethers.getContractFactory("MarketUtil");
    const marketUtil = await MarketUtil.deploy({nonce: nonce++});

    const PositionUtil = await ethers.getContractFactory("PositionUtil");
    const positionUtil = await PositionUtil.deploy({nonce: nonce++});

    const LiquidityReader = await ethers.getContractFactory("LiquidityReader", {
        libraries: {
            LiquidityUtil: await liquidityUtil.getAddress(),
            PUSDManagerUtil: await pusdManagerUtil.getAddress(),
        },
    });
    const liquidityReader = await LiquidityReader.deploy({nonce: nonce++});

    const PositionReader = await ethers.getContractFactory("PositionReader", {
        libraries: {
            PUSDManagerUtil: await pusdManagerUtil.getAddress(),
            PositionUtil: await positionUtil.getAddress(),
        },
    });
    const positionReader = await PositionReader.deploy();

    await configurableUtil.waitForDeployment();
    await liquidityUtil.waitForDeployment();
    await marketUtil.waitForDeployment();
    await positionUtil.waitForDeployment();
    await pusdManagerUtil.waitForDeployment();
    await liquidityReader.waitForDeployment();
    await positionReader.waitForDeployment();

    console.log(`ConfigurableUtil deployed to: ${await configurableUtil.getAddress()}`);
    console.log(`LiquidityUtil deployed to: ${await liquidityUtil.getAddress()}`);
    console.log(`MarketUtil deployed to: ${await marketUtil.getAddress()}`);
    console.log(`PositionUtil deployed to: ${await positionUtil.getAddress()}`);
    console.log(`PUSDManagerUtil deployed to: ${await pusdManagerUtil.getAddress()}`);
    console.log(`LiquidityReader deployed to: ${await liquidityReader.getAddress()}`);
    console.log(`PositionReader deployed to: ${await positionReader.getAddress()}`);

    return {
        configurableUtil,
        liquidityUtil,
        marketUtil,
        positionUtil,
        pusdManagerUtil,
        liquidityReader,
        positionReader,
    };
}

async function deployMarketToken(factory: string, lpSymbol: string, tokenDecimals: number, nonce: number) {
    const Factory = await ethers.getContractFactory(factory);
    if (factory === "ERC20Test") {
        const tokenSymbol = lpSymbol.replace("LPT ", "");
        const addr = await (
            await Factory.deploy(tokenSymbol, tokenSymbol, tokenDecimals, 10n ** 10n * 10n ** BigInt(tokenDecimals))
        ).getAddress();
        console.log(`token ${factory} deployed to: ${addr}`);
        return addr;
    }
    const addr = await (await Factory.deploy({nonce: nonce})).getAddress();
    console.log(`token ${factory} deployed to: ${addr}`);
    return addr;
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

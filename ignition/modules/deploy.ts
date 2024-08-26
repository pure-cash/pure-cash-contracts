import {buildModule} from "@nomicfoundation/hardhat-ignition/modules";
import {hardhatArguments} from "hardhat";
import {IgnitionModuleBuilder} from "@nomicfoundation/ignition-core/dist/src/types/module-builder";
import {
    ArgumentType,
    ContractFuture,
    NamedArtifactContractDeploymentFuture,
} from "@nomicfoundation/ignition-core/dist/src/types/module";
import {networks} from "../../scripts/networks";
import {keccak256} from "@ethersproject/keccak256";
import {toUtf8Bytes} from "@ethersproject/strings";
import {AddressZero} from "@ethersproject/constants";

export default buildModule("deploy", (m) => {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    if (network.weth == undefined) {
        network.weth = m.contract("WETH9", [], {id: "deployToken_WETH"});
    }

    const owner = m.getAccount(0);

    const LibraryModule = buildModule("libraries", (m) => {
        const PUSDManagerUtil = m.library("PUSDManagerUtil");
        const ConfigurableUtil = m.library("ConfigurableUtil");
        const LiquidityUtil = m.library("LiquidityUtil");
        const MarketUtil = m.library("MarketUtil");
        const PositionUtil = m.library("PositionUtil");
        const LiquidityReader = m.library("LiquidityReader", {
            libraries: {
                PUSDManagerUtil: PUSDManagerUtil,
                LiquidityUtil: LiquidityUtil,
            },
        });
        const PositionReader = m.library("PositionReader", {
            libraries: {
                PUSDManagerUtil: PUSDManagerUtil,
                PositionUtil: PositionUtil,
            },
        });
        return {
            PUSDManagerUtil,
            ConfigurableUtil,
            LiquidityUtil,
            MarketUtil,
            PositionUtil,
            LiquidityReader,
            PositionReader,
        };
    });

    const ContractModule = buildModule("contract", (m) => {
        // deploy libraries
        const libraries = m.useModule(LibraryModule);

        const timelockConfig = network.timelockController;
        timelockConfig.executors.push(owner);
        let timelockAdmin = owner;
        if (timelockConfig.admin) {
            timelockAdmin = timelockConfig.admin;
        }
        const PurecashTimelockController = m.contract("PurecashTimelockController", [
            timelockConfig.minDelay,
            timelockConfig.proposers,
            timelockConfig.executors,
            timelockAdmin,
        ]);
        const Governable = m.contract("Governable", [owner]);
        const PUSDUpgradeable = deployUpgradeable(m, "PUSDUpgradeable", [owner]);

        const FeeDistributorUpgradeable = deployUpgradeable(m, "FeeDistributorUpgradeable", [
            owner,
            network.feeDistributorCfg.protocolFeeRate,
            network.feeDistributorCfg.ecosystemFeeRate,
        ]);

        const StakingUpgradeable = deployUpgradeable(m, "StakingUpgradeable", [owner]);

        const MarketManagerUpgradeable = deployUpgradeable(
            m,
            "MarketManagerUpgradeable",
            [owner, FeeDistributorUpgradeable, PUSDUpgradeable, true],
            {
                ConfigurableUtil: libraries.ConfigurableUtil,
                LiquidityUtil: libraries.LiquidityUtil,
                MarketUtil: libraries.MarketUtil,
                PositionUtil: libraries.PositionUtil,
                PUSDManagerUtil: libraries.PUSDManagerUtil,
            },
        );

        const positionRouterExecutionTypes = Object.keys(network.estimatedGasLimits.positionRouter);
        const positionRouterExecutionGasLimits = positionRouterExecutionTypes.map((key) => {
            // @ts-ignore
            return network.estimatedGasLimits.positionRouter[key];
        });
        const PositionRouter = m.contract("PositionRouter", [
            Governable,
            PUSDUpgradeable,
            MarketManagerUpgradeable,
            network.weth,
            positionRouterExecutionTypes,
            positionRouterExecutionGasLimits,
        ]);

        const positionRouter2ExecutionTypes = Object.keys(network.estimatedGasLimits.positionRouter2);
        const positionRouter2ExecutionGasLimits = positionRouter2ExecutionTypes.map((key) => {
            // @ts-ignore
            return network.estimatedGasLimits.positionRouter2[key];
        });
        const PositionRouter2 = m.contract("PositionRouter2", [
            Governable,
            PUSDUpgradeable,
            MarketManagerUpgradeable,
            network.weth,
            positionRouter2ExecutionTypes,
            positionRouter2ExecutionGasLimits,
        ]);

        const Liquidator = m.contract("Liquidator", [Governable, MarketManagerUpgradeable]);

        const DirectExecutablePlugin = m.contract("DirectExecutablePlugin", [
            Governable,
            PUSDUpgradeable,
            MarketManagerUpgradeable,
            network.weth,
        ]);

        const balanceRateBalancerExecutionTypes = Object.keys(network.estimatedGasLimits.balanceRateBalancer);
        const balanceRateBalancerExecutionGasLimits = balanceRateBalancerExecutionTypes.map((key) => {
            // @ts-ignore
            return network.estimatedGasLimits.balanceRateBalancer[key];
        });
        const BalanceRateBalancer = m.contract("BalanceRateBalancer", [
            Governable,
            MarketManagerUpgradeable,
            PUSDUpgradeable,
            DirectExecutablePlugin,
            balanceRateBalancerExecutionTypes,
            balanceRateBalancerExecutionGasLimits,
        ]);

        const MixedExecutor = m.contract("MixedExecutor", [
            Governable,
            Liquidator,
            PositionRouter,
            PositionRouter2,
            MarketManagerUpgradeable,
            BalanceRateBalancer,
        ]);

        const Reader = m.contract("Reader", [MarketManagerUpgradeable], {
            libraries: {
                LiquidityReader: libraries.LiquidityReader,
                PositionReader: libraries.PositionReader,
                PUSDManagerUtil: libraries.PUSDManagerUtil,
            },
        });
        return {
            ...libraries,
            PUSDUpgradeable,
            FeeDistributorUpgradeable,
            StakingUpgradeable,
            MarketManagerUpgradeable,
            PositionRouter,
            PositionRouter2,
            Liquidator,
            MixedExecutor,
            DirectExecutablePlugin,
            BalanceRateBalancer,
            Reader,
            Governable,
            PurecashTimelockController,
        };
    });

    const InitializeModule = buildModule("initialize", (m) => {
        // deploy libraries
        const contracts = m.useModule(ContractModule);
        const {
            PUSDUpgradeable,
            MarketManagerUpgradeable,
            PositionRouter,
            PositionRouter2,
            Liquidator,
            MixedExecutor,
            DirectExecutablePlugin,
            BalanceRateBalancer,
            StakingUpgradeable,
        } = contracts;
        // Update plugins
        m.call(MarketManagerUpgradeable, "updatePlugin", [Liquidator, true], {id: "updatePluginLiquidator"});
        m.call(MarketManagerUpgradeable, "updatePlugin", [PositionRouter, true], {id: "updatePluginPositionRouter"});
        m.call(MarketManagerUpgradeable, "updatePlugin", [PositionRouter2, true], {id: "updatePluginPositionRouter2"});
        m.call(MarketManagerUpgradeable, "updatePlugin", [MixedExecutor, true], {id: "updatePluginMixedExecutor"});
        m.call(MarketManagerUpgradeable, "updatePlugin", [DirectExecutablePlugin, true], {
            id: "updatePluginDirectExecutablePlugin",
        });
        m.call(MarketManagerUpgradeable, "updatePlugin", [BalanceRateBalancer, true], {
            id: "updateBalanceRateBalancerPlugin",
        });

        m.call(PositionRouter, "updatePositionExecutor", [MixedExecutor, true]);
        m.call(PositionRouter2, "updatePositionExecutor", [MixedExecutor, true], {
            id: "updatePositionExecutor2",
        });
        m.call(Liquidator, "updateExecutor", [MixedExecutor, true]);
        m.call(DirectExecutablePlugin, "updatePSMMinters", [BalanceRateBalancer, true]);

        for (let collateral of network.collaterals) {
            if (collateral.token === undefined) {
                collateral.token = m.contract("ERC20Test", [collateral.symbol, collateral.symbol, 18, 0], {
                    id: "deployToken_" + collateral.symbol,
                });
            }
            m.call(MarketManagerUpgradeable, "updatePSMCollateralCap", [collateral.token, collateral.cap], {
                id: "updatePSMCollateralCap_" + collateral.symbol,
            });
        }

        let deployTokens = {};
        for (let item of network.markets) {
            if (item.token === undefined) {
                if (item.tokenSymbol == "WETH") {
                    item.token = network.weth;
                } else {
                    item.token = m.contract(item.tokenFactory, [], {id: "deployToken_" + item.tokenSymbol});
                }
                deployTokens[item.tokenSymbol] = item.token;
            }

            const enableMarketCall = m.call(
                MarketManagerUpgradeable,
                "enableMarket",
                [item.token, item.lpTokenSymbol, item.marketCfg],
                {id: "enableMarket_" + item.tokenSymbol},
            );
            const lpTokenAddr = m.readEventArgument(enableMarketCall, "LPTokenDeployed", "token", {
                id: "readLpToken_" + item.tokenSymbol,
            });
            deployTokens[item.lpTokenSymbol] = m.contractAt("LPToken", lpTokenAddr, {
                id: item.lpTokenSymbol.replace("-", "_"),
            });

            m.call(
                MarketManagerUpgradeable,
                "updateMarketPriceFeedConfig",
                [item.token, item.chainLinkPriceFeed, 0, network.maxCumulativeDeltaDiff],
                {id: "updateMarketPriceFeedConfig_" + item.tokenSymbol},
            );
            if (item.chainLinkPriceFeed == AddressZero) {
                console.warn(`👿👿${item.lpTokenSymbol} chainLinkPriceFeed is not set👿👿`);
            }
        }

        for (let item of network.mixedExecutors) {
            m.call(MixedExecutor, "setExecutor", [item, true], {id: "setExecutor_" + item});
        }

        m.call(PUSDUpgradeable, "setMinter", [MarketManagerUpgradeable, true], {id: "PUSD_setMinter"});
        m.call(MarketManagerUpgradeable, "updateUpdater", [MixedExecutor], {id: "PriceFeed_updateUpdater"});

        return {
            ...contracts,
            ...deployTokens,
        };
    });

    const TransferOwnershipModule = buildModule("transferOwnership", (m) => {
        const contracts = m.useModule(InitializeModule);
        const {
            Governable,
            PurecashTimelockController,
            PUSDUpgradeable,
            FeeDistributorUpgradeable,
            StakingUpgradeable,
            MarketManagerUpgradeable,
        } = contracts;

        // transfer ownership
        const change0 = m.call(Governable, "changeGov", [PurecashTimelockController], {id: "Governable_changeGov"});
        const accept0 = m.call(PurecashTimelockController, "acceptGov", [Governable], {
            id: "Governable_acceptGov",
            after: [change0],
        });

        const change1 = m.call(PUSDUpgradeable, "changeGov", [PurecashTimelockController], {id: "PUSD_changeGov"});
        const accept1 = m.call(PurecashTimelockController, "acceptGov", [PUSDUpgradeable], {
            id: "PUSD_acceptGov",
            after: [change1],
        });

        const change2 = m.call(MarketManagerUpgradeable, "changeGov", [PurecashTimelockController], {
            id: "MarketManager_changeGov",
        });
        const accept2 = m.call(PurecashTimelockController, "acceptGov", [MarketManagerUpgradeable], {
            id: "MarketManager_acceptGov",
            after: [change2],
        });

        const change3 = m.call(FeeDistributorUpgradeable, "changeGov", [PurecashTimelockController], {
            id: "FeeDistributor_changeGov",
        });
        const accept3 = m.call(PurecashTimelockController, "acceptGov", [FeeDistributorUpgradeable], {
            id: "FeeDistributor_acceptGov",
            after: [change3],
        });

        const change4 = m.call(StakingUpgradeable, "changeGov", [PurecashTimelockController], {
            id: "Staking_changeGov",
        });
        const accept4 = m.call(PurecashTimelockController, "acceptGov", [StakingUpgradeable], {
            id: "Staking_acceptGov",
            after: [change4],
        });

        m.call(PurecashTimelockController, "renounceRole", [keccak256(toUtf8Bytes("EXECUTOR_ROLE")), owner], {
            after: [accept0, accept1, accept2, accept3, accept4],
        });
        return contracts;
    });

    return m.useModule(TransferOwnershipModule);
});

function deployUpgradeable(
    m: IgnitionModuleBuilder,
    contractName: string,
    params: ArgumentType[],
    libraries?: Record<string, ContractFuture<string>>,
): NamedArtifactContractDeploymentFuture<"ERC1967Proxy"> {
    const impl = m.contract(contractName, [], {
        id: contractName + "Impl",
        libraries: libraries,
    });
    const proxy = m.contract("ERC1967Proxy", [impl, m.encodeFunctionCall(impl, "initialize", params)], {
        id: contractName + "Proxy",
    });
    return m.contractAt(contractName, proxy);
}

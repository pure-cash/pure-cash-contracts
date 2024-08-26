import {ethers} from "hardhat";
import {parsePercent} from "./util";
import {AddressZero} from "@ethersproject/constants";
import {EstimatedGasLimitType} from "../test/shared/Constants";

const defaultCfg = {
    minMarginPerPosition: ethers.parseUnits("0.005", "ether"),
    maxLeveragePerPosition: 10n,
    liquidationFeeRatePerPosition: parsePercent("2.5%"),
    maxSizeRatePerPosition: parsePercent("100%"),
    liquidationExecutionFee: ethers.parseUnits("0.00032", "ether"),
    liquidityCap: ethers.parseUnits("200000", "ether"),
    liquidityBufferModuleEnabled: true,
    decimals: 18,
    tradingFeeRate: parsePercent("0.07%"),
    protocolFeeRate: parsePercent("50%"),
    openPositionThreshold: parsePercent("90%"),
    maxFeeRate: parsePercent("2%"),
    minMintingRate: parsePercent("50%"),
    maxBurningRate: parsePercent("95%"),
    riskFreeTime: 7200,
    liquidityScale: ethers.parseUnits("1000000", "ether"),
    stableCoinSupplyCap: BigInt(10e8) * 10n ** 6n,
};

const wbtcCfg = {
    ...defaultCfg,
    minMarginPerPosition: ethers.parseUnits("0.0002", 8),
    liquidationExecutionFee: ethers.parseUnits("0.00001", 8),
    liquidityCap: ethers.parseUnits("10000", 8),
    liquidityScale: ethers.parseUnits("50000", 8),
    decimals: 8,
};

const arbitrumCfg = {
    ...defaultCfg,
    liquidationExecutionFee: ethers.parseUnits("0.0004", "ether"),
};

const wbtcArbitrumCfg = {
    ...arbitrumCfg,
    minMarginPerPosition: ethers.parseUnits("0.0002", 8),
    liquidationExecutionFee: ethers.parseUnits("0.00001", 8),
    liquidityCap: ethers.parseUnits("10000", 8),
    liquidityScale: ethers.parseUnits("50000", 8),
};

const defaultFeeDistributorCfg = {
    protocolFeeRate: parsePercent("76.92307%"),
    ecosystemFeeRate: parsePercent("15.38461%"),
};

const defaultMaxCumulativeDeltaDiff = 100n * 1000n; // 10%

const defaultExecutionGasLimit = {
    positionRouter: {
        [EstimatedGasLimitType.IncreasePosition]: 195000,
        [EstimatedGasLimitType.IncreasePositionPayPUSD]: 260000,
        [EstimatedGasLimitType.DecreasePosition]: 210000,
        [EstimatedGasLimitType.DecreasePositionReceivePUSD]: 280000,
        [EstimatedGasLimitType.MintPUSD]: 240000,
        [EstimatedGasLimitType.BurnPUSD]: 240000,
    },
    positionRouter2: {
        [EstimatedGasLimitType.MintLPT]: 190000,
        [EstimatedGasLimitType.MintLPTPayPUSD]: 250000,
        [EstimatedGasLimitType.BurnLPT]: 190000,
        [EstimatedGasLimitType.BurnLPTReceivePUSD]: 280000,
    },
    balanceRateBalancer: {
        [EstimatedGasLimitType.IncreaseBalanceRate]: 400000,
    },
};

export const networks = {
    hardhat: {
        estimatedGasLimits: defaultExecutionGasLimit,
        maxCumulativeDeltaDiff: defaultMaxCumulativeDeltaDiff,
        feeDistributorCfg: defaultFeeDistributorCfg,
        weth: undefined,
        markets: [
            {
                tokenSymbol: "WETH",
                lpTokenSymbol: "ETH-PLP",
                token: undefined,
                tokenFactory: "WETH9",
                tokenDecimals: 18,
                chainLinkPriceFeed: AddressZero,
                maxCumulativeDeltaDiff: defaultMaxCumulativeDeltaDiff,
                marketCfg: arbitrumCfg,
            },
            {
                tokenSymbol: "WBTC",
                lpTokenSymbol: "BTC-PLP",
                tokenFactory: "WBTC",
                tokenDecimals: 8,
                token: undefined,
                chainLinkPriceFeed: AddressZero,
                maxCumulativeDeltaDiff: defaultMaxCumulativeDeltaDiff,
                marketCfg: wbtcArbitrumCfg,
            },
        ],
        mixedExecutors: ["0x9B6194f2467EB0Ca217B5E46F16cca2e27780A73", "0xad0504b3767e8d572C1bfd1DD9D3780E2baFA95D"],
        timelockController: {
            proposers: ["0xD311B7431F00916Afa2a1dE77e9C392f43bF76A5"],
            executors: [AddressZero],
            admin: AddressZero,
            minDelay: 0,
        },
        collaterals: [
            {
                symbol: "TESTCOLLATERAL",
                token: undefined,
                cap: ethers.parseUnits("10000000", "ether"),
            },
        ],
        tokenToStake: [
            {
                token: undefined,
                limit: 100n * 10000n,
            },
        ],
    },
    sepolia: {
        estimatedGasLimits: defaultExecutionGasLimit,
        maxCumulativeDeltaDiff: defaultMaxCumulativeDeltaDiff,
        feeDistributorCfg: defaultFeeDistributorCfg,
        weth: "0xf531B8F309Be94191af87605CfBf600D71C2cFe0",
        markets: [
            {
                tokenSymbol: "WETH",
                lpTokenSymbol: "ETH-PLP",
                token: "0xf531B8F309Be94191af87605CfBf600D71C2cFe0",
                tokenFactory: "WETH9",
                tokenDecimals: 18,
                chainLinkPriceFeed: "0x694AA1769357215DE4FAC081bf1f309aDC325306",
                maxCumulativeDeltaDiff: defaultMaxCumulativeDeltaDiff,
                marketCfg: defaultCfg,
            },
            // {
            //     tokenSymbol: "WBTC",
            //     lpTokenSymbol: "BTC-PLP",
            //     token: "0xC2bC29263BBCE83261886A7C75Fd95DA4a33B1De",
            //     tokenFactory: "WBTC",
            //     tokenDecimals: 8,
            //     chainLinkPriceFeed: "0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43",
            //     maxCumulativeDeltaDiff: defaultMaxCumulativeDeltaDiff,
            //     marketCfg: wbtcCfg,
            // },
        ],
        mixedExecutors: ["0x9B6194f2467EB0Ca217B5E46F16cca2e27780A73", "0xad0504b3767e8d572C1bfd1DD9D3780E2baFA95D"],
        timelockController: {
            // Safe account(threshold:2): [0x556D957AC956511b736c41f0c4B8782eB915DD2A,
            // 0x40eb139234B51054a961a3455b75dE289ea97c78,
            // 0x2a65daE709F90c0B60846B9a0d90829143c5b6f4]
            proposers: ["0xD311B7431F00916Afa2a1dE77e9C392f43bF76A5"],
            executors: [AddressZero],
            admin: AddressZero,
            minDelay: 0, // TODO
        },
        collaterals: [
            {
                symbol: "DAI",
                token: "0x47b81f1849BbfC29eb483c6A9BFD86fE66cd099f",
                cap: ethers.parseUnits("10000000", "ether"),
            },
        ],
        tokenToStake: [
            {
                token: undefined,
                limit: 100n * 10000n,
            },
        ],
    },
    "ethereum-mainnet": {
        estimatedGasLimits: defaultExecutionGasLimit,
        maxCumulativeDeltaDiff: defaultMaxCumulativeDeltaDiff,
        feeDistributorCfg: defaultFeeDistributorCfg,
        weth: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", // https://etherscan.io/address/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        markets: [
            {
                tokenSymbol: "WETH",
                lpTokenSymbol: "ETH-PLP",
                token: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", // https://etherscan.io/address/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
                tokenFactory: "WETH9",
                tokenDecimals: 18,
                chainLinkPriceFeed: "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419", // https://etherscan.io/address/0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
                maxCumulativeDeltaDiff: defaultMaxCumulativeDeltaDiff,
                marketCfg: {
                    ...defaultCfg,
                    liquidationFeeRatePerPosition: parsePercent("2%"),
                    liquidityCap: ethers.parseUnits("5000", "ether"),
                    protocolFeeRate: parsePercent("65%"),
                    riskFreeTime: 3600,
                    stableCoinSupplyCap: BigInt(5e7) * 10n ** 6n,
                },
            },
            // {
            //     tokenSymbol: "WBTC",
            //     lpTokenSymbol: "BTC-PLP",
            //     token: "0x577146734313Fb85E01E50663799656b87378A23",
            //     tokenFactory: "WBTC",
            //     tokenDecimals: 8,
            //     chainLinkPriceFeed: "0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c", // https://etherscan.io/address/0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c
            //     maxCumulativeDeltaDiff: defaultMaxCumulativeDeltaDiff,
            //     marketCfg: wbtcCfg,
            // },
        ],
        mixedExecutors: ["0xdb0cFc4c77c2FFab0fCFB8714479325E9762c5BD"],
        timelockController: {
            proposers: ["0x762B7E4072fd1E0b9af3540dD0ED51e156Cf6d60"],
            executors: [AddressZero],
            admin: AddressZero,
            minDelay: 300,
        },
        collaterals: [
            {
                symbol: "DAI",
                token: "0x6B175474E89094C44Da98b954EedeAC495271d0F", // https://etherscan.io/address/0x6B175474E89094C44Da98b954EedeAC495271d0F
                cap: ethers.parseUnits("50000000", "ether"),
            },
        ],
        tokenToStake: [
            {
                token: undefined,
                limit: 100n * 10000n,
            },
        ],
    },
};

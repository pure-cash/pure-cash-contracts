import "@nomicfoundation/hardhat-toolbox";
import "@nomiclabs/hardhat-solhint";
import "dotenv/config";
import "hardhat-contract-sizer";
import {HardhatUserConfig} from "hardhat/config";
import "@openzeppelin/hardhat-upgrades";
import "@nomicfoundation/hardhat-ignition-ethers";
import {ethers} from "ethers";

const accounts = [`${process.env.PRIVATE_KEY ?? "9".repeat(64)}`];

const config: HardhatUserConfig = {
    solidity: {
        compilers: [
            {
                version: "0.8.26",
                settings: {
                    evmVersion: "cancun",
                    viaIR: true,
                    optimizer: {
                        enabled: true,
                        runs: 1e8,
                    },
                    metadata: {
                        useLiteralContent: false,
                        bytecodeHash: "none",
                        appendCBOR: true,
                    },
                },
            },
        ],
        overrides: {
            "contracts/core/MarketManagerUpgradeable.sol": {
                version: "0.8.26",
                settings: {
                    evmVersion: "cancun",
                    viaIR: true,
                    optimizer: {
                        enabled: true,
                        runs: 900,
                    },
                    metadata: {
                        useLiteralContent: false,
                        bytecodeHash: "none",
                        appendCBOR: true,
                    },
                },
            },
            "contracts/test/WBTC.sol": {
                version: "0.4.24",
            },
        },
    },
    networks: {
        hardhat: {
            allowUnlimitedContractSize: false,
        },
        "arbitrum-sepolia": {
            url: `https://rpc.particle.network/evm-chain?chainId=421614&projectUuid=${process.env.PARTICLE_PROJECT_ID}&projectKey=${process.env.PARTICLE_PROJECT_KEY}`,
            chainId: 421614,
            accounts: accounts,
        },
        "arbitrum-mainnet": {
            url: `https://rpc.particle.network/evm-chain?chainId=42161&projectUuid=${process.env.PARTICLE_PROJECT_ID}&projectKey=${process.env.PARTICLE_PROJECT_KEY}`,
            chainId: 42161,
            accounts: accounts,
        },
        sepolia: {
            url: `https://rpc.particle.network/evm-chain?chainId=11155111&projectUuid=${process.env.PARTICLE_PROJECT_ID}&projectKey=${process.env.PARTICLE_PROJECT_KEY}`,
            chainId: 11155111,
            accounts: accounts,
            ignition: {
                maxFeePerGasLimit: ethers.parseUnits("20", "gwei"),
                // maxPriorityFeePerGas: ethers.parseUnits("2", "gwei"),
            },
        },
        "ethereum-mainnet": {
            url: `https://rpc.particle.network/evm-chain?chainId=1&projectUuid=${process.env.PARTICLE_PROJECT_ID}&projectKey=${process.env.PARTICLE_PROJECT_KEY}`,
            chainId: 1,
            accounts: accounts,
            ignition: {
                maxFeePerGasLimit: ethers.parseUnits("1", "gwei"),
                // maxPriorityFeePerGas: ethers.parseUnits("2", "gwei"),
            },
        },
    },
    etherscan: {
        apiKey: {
            arbitrumSepolia: `${process.env.ARBISCAN_API_KEY}`,
            arbitrumOne: `${process.env.ARBISCAN_API_KEY}`,
        },
    },
    sourcify: {
        enabled: false,
    },
    ignition: {
        blockPollingInterval: 1_000,
        timeBeforeBumpingFees: 2 * 60 * 1_000,
        maxFeeBumps: 4,
        requiredConfirmations: 1,
        strategyConfig: {
            create2: {
                // To learn more about salts, see the CreateX documentation
                // https://github.com/pcaversaccio/createx?tab=readme-ov-file#security-considerations
                salt: "0xb7d9f711E00ca9bE83E3348C57b3719A18598d1E000000000000000000082601",
            },
        },
    },
};

export default config;

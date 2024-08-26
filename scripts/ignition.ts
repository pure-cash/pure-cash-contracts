import hre, {ethers, hardhatArguments, upgrades} from "hardhat";
import {networks} from "./networks";
import deploy from "../ignition/modules/deploy";
import {spawn} from "child_process";
import * as readline from "readline";
import fs from "fs";

async function main() {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const chainId = (await ethers.provider.getNetwork()).chainId;
    await deployContract(deploy, chainId, network);
}

async function deployContract(deployModule: any, chainId: bigint, network: any) {
    const command =
        "export HARDHAT_IGNITION_CONFIRM_DEPLOYMENT=false && npx hardhat ignition deploy ignition/modules/deploy.ts --strategy create2 --network " +
        hardhatArguments.network;
    await runShellCommand(command, []);

    const deployedContracts = await hre.ignition.deploy(deployModule, {strategy: "create2"});
    await resetUpgradeableManifestFile(deployedContracts);

    const deployments = new Map<string, string | {tokenName: string; market: string}[]>();
    for (const [key, value] of Object.entries(deployedContracts)) {
        deployments.set(key, await value.getAddress());
    }

    let markets = [];
    let index = 1;
    for (let item of network.markets) {
        if (typeof item.token !== "string") {
            item.token = await deployedContracts[item.tokenSymbol].getAddress();
        }
        markets.push({
            tokenSymbol: item.tokenSymbol,
            token: item.token,
            lpToken: await deployedContracts[item.lpTokenSymbol].getAddress(),
        });
        index++;
    }
    // @ts-ignore
    deployments.set("registerMarkets", markets);
    // write deployments to file
    const deploymentsOutput = {
        block: await readDeployBlockNumber(chainId),
        deployments: Object.fromEntries(deployments),
    };
    const fs = require("fs");
    if (!fs.existsSync("deployments")) {
        fs.mkdirSync("deployments");
    }
    fs.writeFileSync(`deployments/${chainId}.json`, JSON.stringify(deploymentsOutput, null, 4));
}

async function resetUpgradeableManifestFile(deployedContracts: any) {
    for (const [contractName, contract] of Object.entries(deployedContracts)) {
        if (contractName.indexOf("Upgradeable") == -1) {
            continue;
        }
        let factoryName = contractName[0].toUpperCase() + contractName.substring(1);
        let libraries = {};
        if (factoryName == "MarketManagerUpgradeable") {
            libraries = {
                ConfigurableUtil: await deployedContracts.ConfigurableUtil.getAddress(),
                LiquidityUtil: await deployedContracts.LiquidityUtil.getAddress(),
                MarketUtil: await deployedContracts.MarketUtil.getAddress(),
                PUSDManagerUtil: await deployedContracts.PUSDManagerUtil.getAddress(),
                PositionUtil: await deployedContracts.PositionUtil.getAddress(),
            };
        }
        const factory = await ethers.getContractFactory(factoryName, {
            libraries: libraries,
        });
        // @ts-ignore
        await upgrades.forceImport(await contract.getAddress(), factory, {kind: "uups"});
    }
}

function runShellCommand(command: string, args: string[]): Promise<void> {
    return new Promise((resolve, reject) => {
        const child = spawn(command, args, {
            shell: true, // This ensures the command is run in a shell
        });

        // Create readline interfaces for stdout and stderr
        const rlStdout = readline.createInterface({
            input: child.stdout,
            output: process.stdout,
            terminal: false,
        });

        // Handle stdout data
        rlStdout.on("line", (line) => {
            process.stdout.write(`${line}\n`);
        });

        // Handle process exit
        child.on("close", (code) => {
            if (code === 0) {
                resolve();
            } else {
                reject(new Error(`Child process exited with code ${code}, command: ${command}, args: ${args}`));
            }
        });

        // Handle process errors
        child.on("error", (err) => {
            reject(new Error(`Failed to start process: ${err.message}`));
        });
    });
}

async function readDeployBlockNumber(chainId: bigint) {
    const fileStream = fs.createReadStream(`ignition/deployments/chain-${chainId}/journal.jsonl`);

    const rl = readline.createInterface({
        input: fileStream,
        crlfDelay: Infinity,
    });

    for await (const line of rl) {
        if (line === "") {
            continue;
        }
        const deployContent = JSON.parse(line);
        if (deployContent.receipt?.blockNumber !== undefined) {
            return deployContent.receipt.blockNumber;
        }
    }
    return undefined;
}

main().catch(console.error);

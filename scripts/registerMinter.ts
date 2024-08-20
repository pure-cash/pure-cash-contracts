import {networks} from "./networks";
import {ethers, hardhatArguments} from "hardhat";

async function registerMinter(chainId: bigint) {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const document = require(`../deployments/${chainId}.json`);

    const Factory = await ethers.getContractFactory("DirectExecutablePlugin");
    const encodeData = Factory.interface.encodeFunctionData("updatePSMMinters", [
        "0xa9cC3e33A05ac0F66E098665fd92F65F17CE8412",
        true,
    ]);
    console.log(`${encodeData}`);

    const TimelockController = await ethers.getContractFactory("PurecashTimelockController");
    const encodeData2 = TimelockController.interface.encodeFunctionData("schedule", [
        document.deployments.DirectExecutablePlugin,
        0,
        encodeData,
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        "0x0000000000000000000000000000000000000000000000000000000000000001",
        0,
    ]);
    const encodeData3 = TimelockController.interface.encodeFunctionData("execute", [
        document.deployments.DirectExecutablePlugin,
        0,
        encodeData,
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        "0x0000000000000000000000000000000000000000000000000000000000000001",
    ]);
    console.log(`${encodeData2}`);
    console.log(`${encodeData3}`);
}

async function main() {
    await registerMinter((await ethers.provider.getNetwork()).chainId);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

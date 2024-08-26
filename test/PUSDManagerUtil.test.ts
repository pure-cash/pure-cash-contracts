import {ethers} from "hardhat";
import {bytecode} from "../artifacts/contracts/core/PUSD.sol/PUSD.json";
import {keccak256} from "@ethersproject/keccak256";
import {loadFixture} from "@nomicfoundation/hardhat-network-helpers";
import {expect} from "chai";

describe("PUSDManagerUtil", () => {
    async function deployFixture() {
        const [market] = await ethers.getSigners();
        const PUSDManagerUtil = await ethers.getContractFactory("PUSDManagerUtil");
        const pusdManagerUtil = await PUSDManagerUtil.deploy();

        const PUSDManagerUtilTest = await ethers.getContractFactory("PUSDManagerUtilTest2", {
            libraries: {
                PUSDManagerUtil: await pusdManagerUtil.getAddress(),
            },
        });
        const pusdManagerUtilTest = await PUSDManagerUtilTest.deploy();
        return {pusdManagerUtilTest};
    }

    it(`pusd init code hash should be equal to ${keccak256(bytecode)}`, async () => {
        const {pusdManagerUtilTest} = await loadFixture(deployFixture);
        expect(await pusdManagerUtilTest.PUSD_INIT_CODE_HASH()).to.be.eq(keccak256(bytecode));
    });

    describe("#deployPUSD", () => {
        it("should deploy pusd", async () => {
            const {pusdManagerUtilTest} = await loadFixture(deployFixture);
            await pusdManagerUtilTest.deployPUSD();
            const addr = await pusdManagerUtilTest.computePUSDAddress();
            const token = await ethers.getContractAt("PUSD", addr);
            expect(await token.symbol()).to.be.eq("PUSD");
            expect(await token.decimals()).to.be.eq(6);
            expect(await token.name()).to.be.eq("Pure USD");
        });
    });
});

import {ethers} from "hardhat";
import {bytecode} from "../artifacts/contracts/core/LPToken.sol/LPToken.json";
import {keccak256} from "@ethersproject/keccak256";
import {loadFixture} from "@nomicfoundation/hardhat-network-helpers";
import {expect} from "chai";

describe("LiquidityUtil", () => {
    async function deployFixture() {
        const [market] = await ethers.getSigners();
        const LiquidityUtil = await ethers.getContractFactory("LiquidityUtil");
        const liquidityUtil = await LiquidityUtil.deploy();

        const LiquidityUtilTest = await ethers.getContractFactory("LiquidityUtilTest", {
            libraries: {
                LiquidityUtil: await liquidityUtil.getAddress(),
            },
        });
        const liquidityUtilTest = await LiquidityUtilTest.deploy();
        return {market, liquidityUtilTest};
    }

    it(`lp token init code hash should be equal to ${keccak256(bytecode)}`, async () => {
        const {liquidityUtilTest} = await loadFixture(deployFixture);
        expect(await liquidityUtilTest.LP_TOKEN_INIT_CODE_HASH()).to.be.eq(keccak256(bytecode));
    });

    describe("#deployLPToken", () => {
        it("should deploy lp token", async () => {
            const {market, liquidityUtilTest} = await loadFixture(deployFixture);
            await liquidityUtilTest.deployLPToken(market.address, "SomeSymbol");
            const addr = await liquidityUtilTest.computeLPTokenAddress(market.address);
            const token = await ethers.getContractAt("LPToken", addr);
            expect(await token.symbol()).to.be.eq("SomeSymbol");
            expect(await token.decimals()).to.be.eq(6);
            expect(await token.name()).to.be.eq("Pure.cash LP");
        });
    });
});

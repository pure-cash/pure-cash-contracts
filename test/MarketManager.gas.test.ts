import {ethers, upgrades} from "hardhat";
import {ERC20, FeeDistributorUpgradeable, MarketManagerUpgradeable} from "../typechain-types";
import {parsePercent} from "../scripts/util";
import {loadFixture, time} from "@nomicfoundation/hardhat-network-helpers";
import {BigNumberish} from "ethers";
import {use, expect} from "chai";
import {jestSnapshotPlugin} from "mocha-chai-jest-snapshot";
import {getCreate2Address} from "@ethersproject/address";
import {defaultAbiCoder} from "@ethersproject/abi";
import {bytecode} from "../artifacts/contracts/core/LPToken.sol/LPToken.json";
import {keccak256} from "@ethersproject/keccak256";
import {gasUsed} from "./shared/Gas";
import {AddressZero} from "@ethersproject/constants";
import {
    positionRouter2EstimatedGasLimitTypes,
    positionRouterEstimatedGasLimitTypes,
} from "./shared/PositionRouterFixture";

use(jestSnapshotPlugin());

describe("MarketManager", () => {
    const PRICE = 29899096567035; // 2989.9096567035

    const DEFAULT_ESTIMATED_GAS_LIMIT = 500_000n;
    const GAS_PRICE = ethers.parseUnits("1", "gwei");
    const DEFAULT_EXECUTION_FEE = GAS_PRICE * DEFAULT_ESTIMATED_GAS_LIMIT;

    const CFG = {
        minMarginPerPosition: ethers.parseUnits("0.005", "ether"),
        maxLeveragePerPosition: 10,
        liquidationFeeRatePerPosition: parsePercent("8%"),
        maxSizeRatePerPosition: parsePercent("99%"),
        openPositionThreshold: parsePercent("90%"),
        liquidationExecutionFee: ethers.parseUnits("0.0005", "ether"),
        tradingFeeRate: parsePercent("0.07%"),
        protocolFeeRate: parsePercent("50%"),
        maxFeeRate: parsePercent("2%"),
        decimals: 18,
        liquidityBufferModuleEnabled: true,
        liquidityCap: BigInt(100e4) * BigInt(1e18),
        minMintingRate: 0n,
        riskFreeTime: 7200,
        liquidityScale: BigInt(100e4) * BigInt(1e18),
        stableCoinSupplyCap: BigInt(10e8) * BigInt(1e6),
        maxBurningRate: parsePercent("95%"),
        liquidityTradingFeeRate: parsePercent("0.5%"),
        maxShortSizeRate: parsePercent("200%"),
    };

    async function deployFixture() {
        const [owner, executor, , alice, bob, carrie] = await ethers.getSigners();

        const feeDistributor = (await upgrades.deployProxy(
            await ethers.getContractFactory("FeeDistributorUpgradeable"),
            [owner.address, parsePercent("83.33333%"), parsePercent("0%")],
            {kind: "uups"},
        )) as unknown as FeeDistributorUpgradeable;

        const ConfigurableUtil = await ethers.getContractFactory("ConfigurableUtil");
        const configurableUtil = await ConfigurableUtil.deploy();

        const LiquidityUtil = await ethers.getContractFactory("LiquidityUtil");
        const liquidityUtil = await LiquidityUtil.deploy();

        const MarketUtil = await ethers.getContractFactory("MarketUtil");
        const marketUtil = await MarketUtil.deploy();

        const PUSDManagerUtil = await ethers.getContractFactory("PUSDManagerUtil");
        const pusdManagerUtil = await PUSDManagerUtil.deploy();

        const PositionUtil = await ethers.getContractFactory("PositionUtil");
        const positionUtil = await PositionUtil.deploy();

        const marketManager = (await upgrades.deployProxy(
            await ethers.getContractFactory("MarketManagerUpgradeable", {
                libraries: {
                    ConfigurableUtil: await configurableUtil.getAddress(),
                    LiquidityUtil: await liquidityUtil.getAddress(),
                    MarketUtil: await marketUtil.getAddress(),
                    PUSDManagerUtil: await pusdManagerUtil.getAddress(),
                    PositionUtil: await positionUtil.getAddress(),
                },
            }),
            [owner.address, await feeDistributor.getAddress(), true],
            {kind: "uups"},
        )) as unknown as MarketManagerUpgradeable;

        const Governable = await ethers.getContractFactory("Governable");
        const gov = await Governable.deploy(owner.address);

        const WETH = await ethers.getContractFactory("WETH9");
        const weth = await WETH.deploy();

        const Dai = await ethers.getContractFactory("ERC20Test");
        const dai = await Dai.deploy("DAI", "DAI", 18, 0);

        const PositionRouter = await ethers.getContractFactory("PositionRouter");
        const positionRouter = await PositionRouter.deploy(
            await gov.getAddress(),
            await marketManager.getAddress(),
            await weth.getAddress(),
            await positionRouterEstimatedGasLimitTypes(),
            Array((await positionRouterEstimatedGasLimitTypes()).length).fill(DEFAULT_ESTIMATED_GAS_LIMIT),
        );

        const PositionRouter2 = await ethers.getContractFactory("PositionRouter2");
        const positionRouter2 = await PositionRouter2.deploy(
            await gov.getAddress(),
            await marketManager.getAddress(),
            await weth.getAddress(),
            await positionRouter2EstimatedGasLimitTypes(),
            Array((await positionRouter2EstimatedGasLimitTypes()).length).fill(DEFAULT_ESTIMATED_GAS_LIMIT),
        );

        const Liquidator = await ethers.getContractFactory("Liquidator");
        const liquidator = await Liquidator.deploy(await gov.getAddress(), await marketManager.getAddress());

        const MixedExecutor = await ethers.getContractFactory("MixedExecutor");
        const mixedExecutor = await MixedExecutor.deploy(
            await gov.getAddress(),
            await liquidator.getAddress(),
            await positionRouter.getAddress(),
            await positionRouter2.getAddress(),
            await marketManager.getAddress(),
            AddressZero,
        );

        await marketManager.updatePlugin(await positionRouter.getAddress(), true);
        await marketManager.updatePlugin(await positionRouter2.getAddress(), true);
        await marketManager.updatePlugin(await liquidator.getAddress(), true);
        await marketManager.updateUpdater(await mixedExecutor.getAddress());
        await positionRouter.updatePositionExecutor(await mixedExecutor.getAddress(), true);
        await positionRouter2.updatePositionExecutor(await mixedExecutor.getAddress(), true);
        await liquidator.updateExecutor(await mixedExecutor.getAddress(), true);

        await mixedExecutor.setExecutor(executor.address, true);

        await expect(marketManager.enableMarket(await weth.getAddress(), "LPT WETH", CFG)).to.be.emit(
            marketManager,
            "LPTokenDeployed",
        );

        // initialize price
        const lastTime = await time.latest();
        await mixedExecutor
            .connect(executor)
            .updatePrice(encodeUpdatePriceParam(await weth.getAddress(), PRICE, lastTime));
        const {updateTimestamp, maxPrice, minPrice} = await marketManager.marketPricePacks(await weth.getAddress());
        expect(updateTimestamp).to.be.eq(lastTime);
        expect(maxPrice).to.be.eq(PRICE);
        expect(minPrice).to.be.eq(PRICE);

        const MockChainLinkPriceFeed = await ethers.getContractFactory("MockChainLinkPriceFeed");
        const mockChainLinkPriceFeed = await MockChainLinkPriceFeed.deploy();
        await mockChainLinkPriceFeed.setDecimals(8);

        const pusd = await ethers.getContractAt("PUSD", await marketManager.pusd());
        return {
            owner,
            executor,
            alice,
            bob,
            carrie,
            pusd,
            feeDistributor,
            marketManager,
            gov,
            weth,
            positionRouter,
            positionRouter2,
            mixedExecutor,
            mockChainLinkPriceFeed,
            dai,
        };
    }

    describe("#psmMintPUSD", () => {
        it("mint", async () => {
            const {marketManager, alice, owner, dai} = await loadFixture(deployFixture);
            await marketManager.connect(owner).updatePlugin(alice, true);
            await marketManager.connect(owner).updatePSMCollateralCap(dai, 10n ** 18n);
            await dai.connect(owner).mint(marketManager, 10n ** 18n);
            expect(await gasUsed(marketManager.connect(alice).psmMintPUSD(dai, alice))).toMatchSnapshot();
        });
    });

    describe("#psmBurnPUSD", () => {
        it("burn", async () => {
            const {marketManager, alice, owner, dai} = await loadFixture(deployFixture);
            await marketManager.connect(owner).updatePlugin(alice, true);
            await marketManager.connect(owner).updatePSMCollateralCap(dai, 10n ** 18n);
            await dai.connect(owner).mint(marketManager, 10n ** 18n);
            await marketManager.connect(alice).psmMintPUSD(dai, marketManager);
            expect(await gasUsed(marketManager.connect(alice).psmBurnPUSD(dai, alice))).toMatchSnapshot();
            expect(await dai.balanceOf(alice)).equal(10n ** 18n);
        });
    });

    describe("#executeOrCancelMintLPT", () => {
        it("first mint", async () => {
            const {executor, alice, positionRouter2, mixedExecutor, weth} = await loadFixture(deployFixture);

            await positionRouter2.connect(alice).createMintLPTETH(alice.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("1") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });
            expect(
                await gasUsed(
                    mixedExecutor.connect(executor).multicall([
                        mixedExecutor.interface.encodeFunctionData("updatePrice", [
                            encodeUpdatePriceParam(await weth.getAddress(), PRICE + 1, await time.latest()),
                        ]),
                        mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                            {
                                account: alice.address,
                                market: weth.target,
                                liquidityDelta: ethers.parseEther("1"),
                                executionFee: DEFAULT_EXECUTION_FEE,
                                receiver: alice.address,
                                payPUSD: false,
                                minReceivedFromBurningPUSD: 0,
                            },
                        ]),
                    ]),
                ),
            ).toMatchSnapshot();
        });

        it("different user first mint", async () => {
            const {executor, alice, bob, positionRouter2, mixedExecutor, weth} = await loadFixture(deployFixture);

            await positionRouter2.connect(alice).createMintLPTETH(alice.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("1") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 1, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                    {
                        account: alice.address,
                        market: weth.target,
                        liquidityDelta: ethers.parseEther("1"),
                        executionFee: DEFAULT_EXECUTION_FEE,
                        receiver: alice.address,
                        payPUSD: false,
                        minReceivedFromBurningPUSD: 0,
                    },
                ]),
            ]);

            await positionRouter2.connect(bob).createMintLPTETH(bob.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("1") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });

            expect(
                await gasUsed(
                    mixedExecutor.connect(executor).multicall([
                        mixedExecutor.interface.encodeFunctionData("updatePrice", [
                            encodeUpdatePriceParam(await weth.getAddress(), PRICE + 2, await time.latest()),
                        ]),
                        mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                            {
                                account: bob.address,
                                market: weth.target,
                                liquidityDelta: ethers.parseEther("1"),
                                executionFee: DEFAULT_EXECUTION_FEE,
                                receiver: bob.address,
                                payPUSD: false,
                                minReceivedFromBurningPUSD: 0,
                            },
                        ]),
                    ]),
                ),
            ).toMatchSnapshot();
        });

        it("same user mint again", async () => {
            const {executor, alice, bob, positionRouter2, marketManager, mixedExecutor, weth} =
                await loadFixture(deployFixture);

            await positionRouter2.connect(alice).createMintLPTETH(alice.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("1") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 1, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                    {
                        account: alice.address,
                        market: weth.target,
                        liquidityDelta: ethers.parseEther("1"),
                        executionFee: DEFAULT_EXECUTION_FEE,
                        receiver: alice.address,
                        payPUSD: false,
                        minReceivedFromBurningPUSD: 0,
                    },
                ]),
            ]);

            await positionRouter2.connect(alice).createMintLPTETH(alice.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("1") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });

            expect(
                await gasUsed(
                    mixedExecutor.connect(executor).multicall([
                        mixedExecutor.interface.encodeFunctionData("updatePrice", [
                            encodeUpdatePriceParam(await weth.getAddress(), PRICE + 2, await time.latest()),
                        ]),
                        mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                            {
                                account: alice.address,
                                market: weth.target,
                                liquidityDelta: ethers.parseEther("1"),
                                executionFee: DEFAULT_EXECUTION_FEE,
                                receiver: alice.address,
                                payPUSD: false,
                                minReceivedFromBurningPUSD: 0,
                            },
                        ]),
                    ]),
                ),
            ).toMatchSnapshot();
        });
    });

    describe("#executeOrCancelBurnLPT", () => {
        it("burn half", async () => {
            const {executor, alice, positionRouter2, mixedExecutor, weth, marketManager} =
                await loadFixture(deployFixture);

            await positionRouter2.connect(alice).createMintLPTETH(alice.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("1") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });

            await expect(
                mixedExecutor.connect(executor).multicall([
                    mixedExecutor.interface.encodeFunctionData("updatePrice", [
                        encodeUpdatePriceParam(await weth.getAddress(), PRICE + 1, await time.latest()),
                    ]),
                    mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                        {
                            account: alice.address,
                            market: weth.target,
                            liquidityDelta: ethers.parseEther("1"),
                            executionFee: DEFAULT_EXECUTION_FEE,
                            receiver: alice.address,
                            payPUSD: false,
                            minReceivedFromBurningPUSD: 0,
                        },
                    ]),
                ]),
            ).to.be.emit(marketManager, "LPTMinted");

            const tokenAddr = getCreate2Address(
                await marketManager.getAddress(),
                defaultAbiCoder.encode(["address"], [await weth.getAddress()]),
                keccak256(bytecode),
            );
            const token = (await ethers.getContractAt(
                "@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20",
                tokenAddr,
            )) as unknown as ERC20;
            let balance = await token.balanceOf(alice.address);
            expect(balance).to.be.gt(0n);

            await token.connect(alice).approve(await marketManager.getAddress(), (1n << 256n) - 1n);
            await positionRouter2
                .connect(alice)
                .createBurnLPT(await weth.getAddress(), balance >> 1n, 1n, alice.address, Uint8Array.of(), {
                    value: DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            expect(
                await gasUsed(
                    mixedExecutor.connect(executor).multicall([
                        mixedExecutor.interface.encodeFunctionData("updatePrice", [
                            encodeUpdatePriceParam(await weth.getAddress(), PRICE + 2, await time.latest()),
                        ]),
                        mixedExecutor.interface.encodeFunctionData("executeOrCancelBurnLPT", [
                            {
                                account: alice.address,
                                market: weth.target,
                                amount: balance >> 1n,
                                acceptableMinLiquidity: 1n,
                                receiver: alice.address,
                                executionFee: DEFAULT_EXECUTION_FEE,
                                receivePUSD: false,
                                minPUSDReceived: 0,
                            },
                        ]),
                    ]),
                ),
            ).toMatchSnapshot();

            balance = await token.balanceOf(alice.address);
            expect(balance).to.be.gt(0n);
        });

        it("burn all", async () => {
            const {executor, alice, positionRouter2, mixedExecutor, weth, marketManager} =
                await loadFixture(deployFixture);

            await positionRouter2.connect(alice).createMintLPTETH(alice.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("1") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });

            await expect(
                mixedExecutor.connect(executor).multicall([
                    mixedExecutor.interface.encodeFunctionData("updatePrice", [
                        encodeUpdatePriceParam(await weth.getAddress(), PRICE + 1, await time.latest()),
                    ]),
                    mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                        {
                            account: alice.address,
                            market: weth.target,
                            liquidityDelta: ethers.parseEther("1"),
                            executionFee: DEFAULT_EXECUTION_FEE,
                            receiver: alice.address,
                            payPUSD: false,
                            minReceivedFromBurningPUSD: 0,
                        },
                    ]),
                ]),
            ).to.be.emit(marketManager, "LPTMinted");

            const tokenAddr = getCreate2Address(
                await marketManager.getAddress(),
                defaultAbiCoder.encode(["address"], [await weth.getAddress()]),
                keccak256(bytecode),
            );
            const token = (await ethers.getContractAt(
                "@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20",
                tokenAddr,
            )) as unknown as ERC20;
            let balance = await token.balanceOf(alice.address);
            expect(balance).to.be.gt(0n);

            await token.connect(alice).approve(await marketManager.getAddress(), (1n << 256n) - 1n);
            await positionRouter2
                .connect(alice)
                .createBurnLPT(await weth.getAddress(), balance, 1n, alice.address, Uint8Array.of(), {
                    value: DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            expect(
                await gasUsed(
                    mixedExecutor.connect(executor).multicall([
                        mixedExecutor.interface.encodeFunctionData("updatePrice", [
                            encodeUpdatePriceParam(await weth.getAddress(), PRICE + 2, await time.latest()),
                        ]),
                        mixedExecutor.interface.encodeFunctionData("executeOrCancelBurnLPT", [
                            {
                                account: alice.address,
                                market: weth.target,
                                amount: balance,
                                acceptableMinLiquidity: 1n,
                                receiver: alice.address,
                                executionFee: DEFAULT_EXECUTION_FEE,
                                receivePUSD: false,
                                minPUSDReceived: 0,
                            },
                        ]),
                    ]),
                ),
            ).toMatchSnapshot();

            balance = await token.balanceOf(alice.address);
            expect(balance).to.be.eq(0n);
        });
    });

    describe("#executeOrCancelIncreasePosition", () => {
        it("first increase", async () => {
            const {executor, alice, bob, positionRouter, positionRouter2, mixedExecutor, weth, marketManager} =
                await loadFixture(deployFixture);

            await positionRouter2.connect(alice).createMintLPTETH(alice.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("10") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });
            await expect(
                mixedExecutor.connect(executor).multicall([
                    mixedExecutor.interface.encodeFunctionData("updatePrice", [
                        encodeUpdatePriceParam(await weth.getAddress(), PRICE + 1, await time.latest()),
                    ]),
                    mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                        {
                            account: alice.address,
                            market: weth.target,
                            liquidityDelta: ethers.parseEther("10"),
                            executionFee: DEFAULT_EXECUTION_FEE,
                            receiver: alice.address,
                            payPUSD: false,
                            minReceivedFromBurningPUSD: 0,
                        },
                    ]),
                ]),
            ).to.be.emit(marketManager, "LPTMinted");

            await positionRouter
                .connect(bob)
                .createIncreasePositionETH(ethers.parseEther("5"), PRICE + 3, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("2") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            expect(
                await gasUsed(
                    mixedExecutor.connect(executor).multicall([
                        mixedExecutor.interface.encodeFunctionData("updatePrice", [
                            encodeUpdatePriceParam(await weth.getAddress(), PRICE + 2, await time.latest()),
                        ]),
                        mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                            {
                                account: bob.address,
                                market: weth.target,
                                marginDelta: ethers.parseEther("2"),
                                sizeDelta: ethers.parseEther("5"),
                                acceptableIndexPrice: PRICE + 3,
                                executionFee: DEFAULT_EXECUTION_FEE,
                                payPUSD: false,
                            },
                        ]),
                    ]),
                ),
            ).toMatchSnapshot();

            const {size} = await marketManager.longPositions(await weth.getAddress(), bob.address);
            expect(size).to.be.eq(ethers.parseEther("5"));
        });

        it("different user first increase", async () => {
            const {executor, alice, bob, carrie, positionRouter, positionRouter2, mixedExecutor, weth, marketManager} =
                await loadFixture(deployFixture);

            await positionRouter2.connect(alice).createMintLPTETH(alice.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("10") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });
            await expect(
                mixedExecutor.connect(executor).multicall([
                    mixedExecutor.interface.encodeFunctionData("updatePrice", [
                        encodeUpdatePriceParam(await weth.getAddress(), PRICE + 1, await time.latest()),
                    ]),
                    mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                        {
                            account: alice.address,
                            market: weth.target,
                            liquidityDelta: ethers.parseEther("10"),
                            executionFee: DEFAULT_EXECUTION_FEE,
                            receiver: alice.address,
                            payPUSD: false,
                            minReceivedFromBurningPUSD: 0,
                        },
                    ]),
                ]),
            ).to.be.emit(marketManager, "LPTMinted");

            await positionRouter
                .connect(bob)
                .createIncreasePositionETH(ethers.parseEther("5"), PRICE + 3, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("2") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 2, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                    {
                        account: bob.address,
                        market: weth.target,
                        marginDelta: ethers.parseEther("2"),
                        sizeDelta: ethers.parseEther("5"),
                        acceptableIndexPrice: PRICE + 3,
                        executionFee: DEFAULT_EXECUTION_FEE,
                        payPUSD: false,
                    },
                ]),
            ]);

            await positionRouter
                .connect(carrie)
                .createIncreasePositionETH(ethers.parseEther("2"), PRICE + 10, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("2") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            expect(
                await gasUsed(
                    mixedExecutor.connect(executor).multicall([
                        mixedExecutor.interface.encodeFunctionData("updatePrice", [
                            encodeUpdatePriceParam(await weth.getAddress(), PRICE + 3, await time.latest()),
                        ]),
                        mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                            {
                                account: carrie.address,
                                market: weth.target,
                                marginDelta: ethers.parseEther("2"),
                                sizeDelta: ethers.parseEther("2"),
                                acceptableIndexPrice: PRICE + 10,
                                executionFee: DEFAULT_EXECUTION_FEE,
                                payPUSD: false,
                            },
                        ]),
                    ]),
                ),
            ).toMatchSnapshot();

            const {size} = await marketManager.longPositions(await weth.getAddress(), carrie.address);
            expect(size).to.be.eq(ethers.parseEther("2"));
        });

        it("same user increase again", async () => {
            const {executor, alice, bob, positionRouter, positionRouter2, mixedExecutor, weth, marketManager} =
                await loadFixture(deployFixture);

            await positionRouter2.connect(alice).createMintLPTETH(alice.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("10") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });
            await expect(
                mixedExecutor.connect(executor).multicall([
                    mixedExecutor.interface.encodeFunctionData("updatePrice", [
                        encodeUpdatePriceParam(await weth.getAddress(), PRICE + 1, await time.latest()),
                    ]),
                    mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                        {
                            account: alice.address,
                            market: weth.target,
                            liquidityDelta: ethers.parseEther("10"),
                            executionFee: DEFAULT_EXECUTION_FEE,
                            receiver: alice.address,
                            payPUSD: false,
                            minReceivedFromBurningPUSD: 0,
                        },
                    ]),
                ]),
            ).to.be.emit(marketManager, "LPTMinted");

            await positionRouter
                .connect(bob)
                .createIncreasePositionETH(ethers.parseEther("5"), PRICE + 3, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("2") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 2, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                    {
                        account: bob.address,
                        market: weth.target,
                        marginDelta: ethers.parseEther("2"),
                        sizeDelta: ethers.parseEther("5"),
                        acceptableIndexPrice: PRICE + 3,
                        executionFee: DEFAULT_EXECUTION_FEE,
                        payPUSD: false,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createIncreasePositionETH(ethers.parseEther("2"), PRICE + 10, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("2") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            expect(
                await gasUsed(
                    mixedExecutor.connect(executor).multicall([
                        mixedExecutor.interface.encodeFunctionData("updatePrice", [
                            encodeUpdatePriceParam(await weth.getAddress(), PRICE + 3, await time.latest()),
                        ]),
                        mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                            {
                                account: bob.address,
                                market: weth.target,
                                marginDelta: ethers.parseEther("2"),
                                sizeDelta: ethers.parseEther("2"),
                                acceptableIndexPrice: PRICE + 10,
                                executionFee: DEFAULT_EXECUTION_FEE,
                                payPUSD: false,
                            },
                        ]),
                    ]),
                ),
            ).toMatchSnapshot();

            const {size} = await marketManager.longPositions(await weth.getAddress(), bob.address);
            expect(size).to.be.eq(ethers.parseEther("7"));
        });

        it("same user increase again with floating trading fee", async () => {
            const {executor, alice, bob, positionRouter, positionRouter2, mixedExecutor, weth, marketManager} =
                await loadFixture(deployFixture);

            await positionRouter2.connect(alice).createMintLPTETH(alice.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("15") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });
            await expect(
                mixedExecutor.connect(executor).multicall([
                    mixedExecutor.interface.encodeFunctionData("updatePrice", [
                        encodeUpdatePriceParam(await weth.getAddress(), PRICE + 1, await time.latest()),
                    ]),
                    mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                        {
                            account: alice.address,
                            market: weth.target,
                            liquidityDelta: ethers.parseEther("15"),
                            executionFee: DEFAULT_EXECUTION_FEE,
                            receiver: alice.address,
                            payPUSD: false,
                            minReceivedFromBurningPUSD: 0,
                        },
                    ]),
                ]),
            ).to.be.emit(marketManager, "LPTMinted");

            await positionRouter
                .connect(bob)
                .createIncreasePositionETH(ethers.parseEther("5"), PRICE + 3, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("2") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 2, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                    {
                        account: bob.address,
                        market: weth.target,
                        marginDelta: ethers.parseEther("2"),
                        sizeDelta: ethers.parseEther("5"),
                        acceptableIndexPrice: PRICE + 3,
                        executionFee: DEFAULT_EXECUTION_FEE,
                        payPUSD: false,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createIncreasePositionETH(ethers.parseEther("5"), PRICE + 10, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("2") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            expect(
                await gasUsed(
                    mixedExecutor.connect(executor).multicall([
                        mixedExecutor.interface.encodeFunctionData("updatePrice", [
                            encodeUpdatePriceParam(await weth.getAddress(), PRICE + 3, await time.latest()),
                        ]),
                        mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                            {
                                account: bob.address,
                                market: weth.target,
                                marginDelta: ethers.parseEther("2"),
                                sizeDelta: ethers.parseEther("5"),
                                acceptableIndexPrice: PRICE + 10,
                                executionFee: DEFAULT_EXECUTION_FEE,
                                payPUSD: false,
                            },
                        ]),
                    ]),
                ),
            ).toMatchSnapshot();

            const {size} = await marketManager.longPositions(await weth.getAddress(), bob.address);
            expect(size).to.be.eq(ethers.parseEther("10"));
        });

        it("same user increase again with spread", async () => {
            const {executor, alice, bob, positionRouter, positionRouter2, mixedExecutor, weth, marketManager} =
                await loadFixture(deployFixture);

            await positionRouter2.connect(alice).createMintLPTETH(alice.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("200") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });
            await positionRouter
                .connect(bob)
                .createIncreasePositionETH(ethers.parseEther("10"), PRICE + 3, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("10") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await expect(
                mixedExecutor.connect(executor).multicall([
                    mixedExecutor.interface.encodeFunctionData("updatePrice", [
                        encodeUpdatePriceParam(await weth.getAddress(), PRICE, await time.latest()),
                    ]),
                    mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                        {
                            account: alice.address,
                            market: weth.target,
                            liquidityDelta: ethers.parseEther("200"),
                            executionFee: DEFAULT_EXECUTION_FEE,
                            receiver: alice.address,
                            payPUSD: false,
                            minReceivedFromBurningPUSD: 0,
                        },
                    ]),
                    mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                        {
                            account: bob.address,
                            market: weth.target,
                            marginDelta: ethers.parseEther("10"),
                            sizeDelta: ethers.parseEther("10"),
                            acceptableIndexPrice: PRICE + 3,
                            executionFee: DEFAULT_EXECUTION_FEE,
                            payPUSD: false,
                        },
                    ]),
                ]),
            ).to.be.emit(marketManager, "LPTMinted");

            await time.setNextBlockTimestamp((await time.latest()) + 3600);

            await positionRouter
                .connect(bob)
                .createIncreasePositionETH(
                    ethers.parseEther("90"),
                    (BigInt(PRICE) << 1n) + 10n,
                    DEFAULT_EXECUTION_FEE,
                    {
                        value: ethers.parseEther("50") + DEFAULT_EXECUTION_FEE,
                        gasPrice: GAS_PRICE,
                    },
                );
            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), BigInt(PRICE) << 1n, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                    {
                        account: bob.address,
                        market: weth.target,
                        marginDelta: ethers.parseEther("50"),
                        sizeDelta: ethers.parseEther("90"),
                        acceptableIndexPrice: (BigInt(PRICE) << 1n) + 10n,
                        executionFee: DEFAULT_EXECUTION_FEE,
                        payPUSD: false,
                    },
                ]),
            ]);
            await time.setNextBlockTimestamp((await time.latest()) + 2 * 3600);

            await positionRouter
                .connect(bob)
                .createDecreasePosition(
                    await weth.getAddress(),
                    ethers.parseEther("40"),
                    ethers.parseEther("40"),
                    1n,
                    bob.address,
                    {value: DEFAULT_EXECUTION_FEE, gasPrice: GAS_PRICE},
                );
            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), BigInt(PRICE) << 1n, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelDecreasePosition", [
                    {
                        account: bob.address,
                        market: weth.target,
                        marginDelta: ethers.parseEther("40"),
                        sizeDelta: ethers.parseEther("40"),
                        acceptableIndexPrice: 1n,
                        receiver: bob.address,
                        executionFee: DEFAULT_EXECUTION_FEE,
                        receivePUSD: false,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createIncreasePositionETH(ethers.parseEther("1"), (BigInt(PRICE) << 1n) + 10n, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("1") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });
            expect(
                await gasUsed(
                    mixedExecutor.connect(executor).multicall([
                        mixedExecutor.interface.encodeFunctionData("updatePrice", [
                            encodeUpdatePriceParam(
                                await weth.getAddress(),
                                (BigInt(PRICE) << 1n) + 1n,
                                await time.latest(),
                            ),
                        ]),
                        mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                            {
                                account: bob.address,
                                market: weth.target,
                                marginDelta: ethers.parseEther("1"),
                                sizeDelta: ethers.parseEther("1"),
                                acceptableIndexPrice: (BigInt(PRICE) << 1n) + 10n,
                                executionFee: DEFAULT_EXECUTION_FEE,
                                payPUSD: false,
                            },
                        ]),
                    ]),
                ),
            ).toMatchSnapshot();

            const {size} = await marketManager.longPositions(await weth.getAddress(), bob.address);
            expect(size).to.be.eq(ethers.parseEther("61"));
        });
    });

    describe("#executeOrCancelDecreasePosition", () => {
        it("decrease half", async () => {
            const {executor, alice, bob, positionRouter, positionRouter2, marketManager, mixedExecutor, weth} =
                await loadFixture(deployFixture);

            await positionRouter2.connect(alice).createMintLPTETH(alice.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("10") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 1, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                    {
                        account: alice.address,
                        market: weth.target,
                        liquidityDelta: ethers.parseEther("10"),
                        executionFee: DEFAULT_EXECUTION_FEE,
                        receiver: alice.address,
                        payPUSD: false,
                        minReceivedFromBurningPUSD: 0,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createIncreasePositionETH(ethers.parseEther("5"), PRICE + 3, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("2") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 2, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                    {
                        account: bob.address,
                        market: weth.target,
                        marginDelta: ethers.parseEther("2"),
                        sizeDelta: ethers.parseEther("5"),
                        acceptableIndexPrice: PRICE + 3,
                        executionFee: DEFAULT_EXECUTION_FEE,
                        payPUSD: false,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createDecreasePosition(
                    await weth.getAddress(),
                    ethers.parseEther("0.5"),
                    ethers.parseEther("2.5"),
                    PRICE,
                    bob.address,
                    {value: DEFAULT_EXECUTION_FEE, gasPrice: GAS_PRICE},
                );

            expect(
                await gasUsed(
                    mixedExecutor.connect(executor).multicall([
                        mixedExecutor.interface.encodeFunctionData("updatePrice", [
                            encodeUpdatePriceParam(await weth.getAddress(), PRICE + 3, await time.latest()),
                        ]),
                        mixedExecutor.interface.encodeFunctionData("executeOrCancelDecreasePosition", [
                            {
                                account: bob.address,
                                market: weth.target,
                                marginDelta: ethers.parseEther("0.5"),
                                sizeDelta: ethers.parseEther("2.5"),
                                acceptableIndexPrice: PRICE,
                                receiver: bob.address,
                                executionFee: DEFAULT_EXECUTION_FEE,
                                receivePUSD: false,
                            },
                        ]),
                    ]),
                ),
            ).toMatchSnapshot();

            const {size} = await marketManager.longPositions(await weth.getAddress(), bob.address);
            expect(size).to.be.eq(ethers.parseEther("2.5"));
        });

        it("decrease all", async () => {
            const {executor, alice, bob, positionRouter, positionRouter2, marketManager, mixedExecutor, weth} =
                await loadFixture(deployFixture);

            await positionRouter2.connect(alice).createMintLPTETH(alice.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("10") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 1, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                    {
                        account: alice.address,
                        market: weth.target,
                        liquidityDelta: ethers.parseEther("10"),
                        executionFee: DEFAULT_EXECUTION_FEE,
                        receiver: alice.address,
                        payPUSD: false,
                        minReceivedFromBurningPUSD: 0,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createIncreasePositionETH(ethers.parseEther("5"), PRICE + 3, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("2") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await positionRouter
                .connect(alice)
                .createIncreasePositionETH(ethers.parseEther("1"), PRICE + 3, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("2") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 2, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                    {
                        account: bob.address,
                        market: weth.target,
                        marginDelta: ethers.parseEther("2"),
                        sizeDelta: ethers.parseEther("5"),
                        acceptableIndexPrice: PRICE + 3,
                        executionFee: DEFAULT_EXECUTION_FEE,
                        payPUSD: false,
                    },
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                    {
                        account: alice.address,
                        market: weth.target,
                        marginDelta: ethers.parseEther("2"),
                        sizeDelta: ethers.parseEther("1"),
                        acceptableIndexPrice: PRICE + 3,
                        executionFee: DEFAULT_EXECUTION_FEE,
                        payPUSD: false,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createDecreasePosition(
                    await weth.getAddress(),
                    ethers.parseEther("0"),
                    ethers.parseEther("5"),
                    PRICE,
                    bob.address,
                    {value: DEFAULT_EXECUTION_FEE, gasPrice: GAS_PRICE},
                );

            expect(
                await gasUsed(
                    mixedExecutor.connect(executor).multicall([
                        mixedExecutor.interface.encodeFunctionData("updatePrice", [
                            encodeUpdatePriceParam(await weth.getAddress(), PRICE + 3, await time.latest()),
                        ]),
                        mixedExecutor.interface.encodeFunctionData("executeOrCancelDecreasePosition", [
                            {
                                account: bob.address,
                                market: weth.target,
                                marginDelta: ethers.parseEther("0"),
                                sizeDelta: ethers.parseEther("5"),
                                acceptableIndexPrice: PRICE,
                                receiver: bob.address,
                                executionFee: DEFAULT_EXECUTION_FEE,
                                receivePUSD: false,
                            },
                        ]),
                    ]),
                ),
            ).toMatchSnapshot();

            const {size} = await marketManager.longPositions(await weth.getAddress(), bob.address);
            expect(size).to.be.eq(ethers.parseEther("0"));
        });

        it("decrease half with liquidity buffer module burn", async () => {
            const {executor, alice, bob, positionRouter, positionRouter2, marketManager, mixedExecutor, weth} =
                await loadFixture(deployFixture);

            await positionRouter2.connect(alice).createMintLPTETH(alice.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("10") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 1, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                    {
                        account: alice.address,
                        market: weth.target,
                        liquidityDelta: ethers.parseEther("10"),
                        executionFee: DEFAULT_EXECUTION_FEE,
                        receiver: alice.address,
                        payPUSD: false,
                        minReceivedFromBurningPUSD: 0,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createIncreasePositionETH(ethers.parseEther("5"), PRICE + 3, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("2") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 2, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                    {
                        account: bob.address,
                        market: weth.target,
                        marginDelta: ethers.parseEther("2"),
                        sizeDelta: ethers.parseEther("5"),
                        acceptableIndexPrice: PRICE + 3,
                        executionFee: DEFAULT_EXECUTION_FEE,
                        payPUSD: false,
                    },
                ]),
            ]);

            await positionRouter
                .connect(alice)
                .createMintPUSDETH(false, BigInt(4000e6), alice.address, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("2") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 3, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelMintPUSD", [
                    {
                        account: alice.address,
                        market: weth.target,
                        exactIn: false,
                        acceptableMaxPayAmount: ethers.parseEther("2"),
                        acceptableMinReceiveAmount: BigInt(4000e6),
                        receiver: alice.address,
                        executionFee: DEFAULT_EXECUTION_FEE,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createDecreasePosition(
                    await weth.getAddress(),
                    ethers.parseEther("0.5"),
                    ethers.parseEther("4.9"),
                    PRICE,
                    bob.address,
                    {value: DEFAULT_EXECUTION_FEE, gasPrice: GAS_PRICE},
                );

            expect(
                await gasUsed(
                    mixedExecutor.connect(executor).multicall([
                        mixedExecutor.interface.encodeFunctionData("updatePrice", [
                            encodeUpdatePriceParam(await weth.getAddress(), PRICE + 4, await time.latest()),
                        ]),
                        mixedExecutor.interface.encodeFunctionData("executeOrCancelDecreasePosition", [
                            {
                                account: bob.address,
                                market: weth.target,
                                marginDelta: ethers.parseEther("0.5"),
                                sizeDelta: ethers.parseEther("4.9"),
                                acceptableIndexPrice: PRICE,
                                receiver: bob.address,
                                executionFee: DEFAULT_EXECUTION_FEE,
                                receivePUSD: false,
                            },
                        ]),
                    ]),
                ),
            ).toMatchSnapshot();

            const {size} = await marketManager.longPositions(await weth.getAddress(), bob.address);
            expect(size).to.be.eq(ethers.parseEther("0.1"));

            const {pusdDebt, tokenPayback} = await marketManager.liquidityBufferModules(await weth.getAddress());
            expect(pusdDebt).to.be.gt(0n);
            expect(tokenPayback).to.be.gt(0n);
        });

        it("decrease all with liquidity buffer module burn", async () => {
            const {executor, alice, bob, positionRouter, positionRouter2, marketManager, mixedExecutor, weth} =
                await loadFixture(deployFixture);

            await positionRouter2.connect(alice).createMintLPTETH(alice.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("10") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 1, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                    {
                        account: alice.address,
                        market: weth.target,
                        liquidityDelta: ethers.parseEther("10"),
                        executionFee: DEFAULT_EXECUTION_FEE,
                        receiver: alice.address,
                        payPUSD: false,
                        minReceivedFromBurningPUSD: 0,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createIncreasePositionETH(ethers.parseEther("5"), PRICE + 3, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("2") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await positionRouter
                .connect(alice)
                .createIncreasePositionETH(ethers.parseEther("2"), PRICE + 3, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("1") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 2, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                    {
                        account: bob.address,
                        market: weth.target,
                        marginDelta: ethers.parseEther("2"),
                        sizeDelta: ethers.parseEther("5"),
                        acceptableIndexPrice: PRICE + 3,
                        executionFee: DEFAULT_EXECUTION_FEE,
                        payPUSD: false,
                    },
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                    {
                        account: alice.address,
                        market: weth.target,
                        marginDelta: ethers.parseEther("1"),
                        sizeDelta: ethers.parseEther("2"),
                        acceptableIndexPrice: PRICE + 3,
                        executionFee: DEFAULT_EXECUTION_FEE,
                        payPUSD: false,
                    },
                ]),
            ]);

            await positionRouter
                .connect(alice)
                .createMintPUSDETH(false, BigInt(20900e6), alice.address, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("8") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 3, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelMintPUSD", [
                    {
                        account: alice.address,
                        market: weth.target,
                        exactIn: false,
                        acceptableMaxPayAmount: ethers.parseEther("8"),
                        acceptableMinReceiveAmount: BigInt(20900e6),
                        receiver: alice.address,
                        executionFee: DEFAULT_EXECUTION_FEE,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createDecreasePosition(
                    await weth.getAddress(),
                    ethers.parseEther("0"),
                    ethers.parseEther("5.0"),
                    PRICE,
                    bob.address,
                    {value: DEFAULT_EXECUTION_FEE, gasPrice: GAS_PRICE},
                );

            expect(
                await gasUsed(
                    mixedExecutor.connect(executor).multicall([
                        mixedExecutor.interface.encodeFunctionData("updatePrice", [
                            encodeUpdatePriceParam(await weth.getAddress(), PRICE + 4, await time.latest()),
                        ]),
                        mixedExecutor.interface.encodeFunctionData("executeOrCancelDecreasePosition", [
                            {
                                account: bob.address,
                                market: weth.target,
                                marginDelta: ethers.parseEther("0"),
                                sizeDelta: ethers.parseEther("5.0"),
                                acceptableIndexPrice: PRICE,
                                receiver: bob.address,
                                executionFee: DEFAULT_EXECUTION_FEE,
                                receivePUSD: false,
                            },
                        ]),
                    ]),
                ),
            ).toMatchSnapshot();

            const {size} = await marketManager.longPositions(await weth.getAddress(), bob.address);
            expect(size).to.be.eq(ethers.parseEther("0"));

            const {pusdDebt, tokenPayback} = await marketManager.liquidityBufferModules(await weth.getAddress());
            expect(pusdDebt).to.be.gt(0n);
            expect(tokenPayback).to.be.gt(0n);
        });
    });

    describe("#executeOrCancelMintPUSD", () => {
        it("first mint", async () => {
            const {executor, alice, bob, positionRouter, positionRouter2, mixedExecutor, weth, pusd} =
                await loadFixture(deployFixture);

            await positionRouter2.connect(alice).createMintLPTETH(alice.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("10") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 1, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                    {
                        account: alice.address,
                        market: weth.target,
                        liquidityDelta: ethers.parseEther("10"),
                        executionFee: DEFAULT_EXECUTION_FEE,
                        receiver: alice.address,
                        payPUSD: false,
                        minReceivedFromBurningPUSD: 0,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createIncreasePositionETH(ethers.parseEther("5"), PRICE + 3, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("2") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 2, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                    {
                        account: bob.address,
                        market: weth.target,
                        marginDelta: ethers.parseEther("2"),
                        sizeDelta: ethers.parseEther("5"),
                        acceptableIndexPrice: PRICE + 3,
                        executionFee: DEFAULT_EXECUTION_FEE,
                        payPUSD: false,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createMintPUSDETH(false, BigInt(1000e6), bob.address, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("1") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            expect(
                await gasUsed(
                    mixedExecutor.connect(executor).multicall([
                        mixedExecutor.interface.encodeFunctionData("updatePrice", [
                            encodeUpdatePriceParam(await weth.getAddress(), PRICE + 3, await time.latest()),
                        ]),
                        mixedExecutor.interface.encodeFunctionData("executeOrCancelMintPUSD", [
                            {
                                account: bob.address,
                                market: weth.target,
                                exactIn: false,
                                acceptableMaxPayAmount: ethers.parseEther("1"),
                                acceptableMinReceiveAmount: BigInt(1000e6),
                                receiver: bob.address,
                                executionFee: DEFAULT_EXECUTION_FEE,
                            },
                        ]),
                    ]),
                ),
            ).toMatchSnapshot();

            expect(await pusd.balanceOf(bob.address)).to.be.eq(1000e6);
        });

        it("different user first mint", async () => {
            const {executor, alice, bob, positionRouter, positionRouter2, mixedExecutor, weth, pusd} =
                await loadFixture(deployFixture);

            await positionRouter2.connect(alice).createMintLPTETH(alice.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("10") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 1, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                    {
                        account: alice.address,
                        market: weth.target,
                        liquidityDelta: ethers.parseEther("10"),
                        executionFee: DEFAULT_EXECUTION_FEE,
                        receiver: alice.address,
                        payPUSD: false,
                        minReceivedFromBurningPUSD: 0,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createIncreasePositionETH(ethers.parseEther("5"), PRICE + 3, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("2") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 2, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                    {
                        account: bob.address,
                        market: weth.target,
                        marginDelta: ethers.parseEther("2"),
                        sizeDelta: ethers.parseEther("5"),
                        acceptableIndexPrice: PRICE + 3,
                        executionFee: DEFAULT_EXECUTION_FEE,
                        payPUSD: false,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createMintPUSDETH(false, BigInt(1000e6), bob.address, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("1") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 3, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelMintPUSD", [
                    {
                        account: bob.address,
                        market: weth.target,
                        exactIn: false,
                        acceptableMaxPayAmount: ethers.parseEther("1"),
                        acceptableMinReceiveAmount: BigInt(1000e6),
                        receiver: bob.address,
                        executionFee: DEFAULT_EXECUTION_FEE,
                    },
                ]),
            ]);

            await positionRouter
                .connect(alice)
                .createMintPUSDETH(false, BigInt(1000e6), alice.address, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("1") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            expect(
                await gasUsed(
                    mixedExecutor.connect(executor).multicall([
                        mixedExecutor.interface.encodeFunctionData("updatePrice", [
                            encodeUpdatePriceParam(await weth.getAddress(), PRICE + 4, await time.latest()),
                        ]),
                        mixedExecutor.interface.encodeFunctionData("executeOrCancelMintPUSD", [
                            {
                                account: alice.address,
                                market: weth.target,
                                exactIn: false,
                                acceptableMaxPayAmount: ethers.parseEther("1"),
                                acceptableMinReceiveAmount: BigInt(1000e6),
                                receiver: alice.address,
                                executionFee: DEFAULT_EXECUTION_FEE,
                            },
                        ]),
                    ]),
                ),
            ).toMatchSnapshot();

            expect(await pusd.balanceOf(bob.address)).to.be.eq(1000e6);
        });

        it("same user mint again", async () => {
            const {executor, alice, bob, positionRouter, positionRouter2, marketManager, mixedExecutor, weth, pusd} =
                await loadFixture(deployFixture);

            await positionRouter2.connect(alice).createMintLPTETH(alice.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("10") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 1, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                    {
                        account: alice.address,
                        market: weth.target,
                        liquidityDelta: ethers.parseEther("10"),
                        executionFee: DEFAULT_EXECUTION_FEE,
                        receiver: alice.address,
                        payPUSD: false,
                        minReceivedFromBurningPUSD: 0,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createIncreasePositionETH(ethers.parseEther("5"), PRICE + 3, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("2") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 2, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                    {
                        account: bob.address,
                        market: weth.target,
                        marginDelta: ethers.parseEther("2"),
                        sizeDelta: ethers.parseEther("5"),
                        acceptableIndexPrice: PRICE + 3,
                        executionFee: DEFAULT_EXECUTION_FEE,
                        payPUSD: false,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createMintPUSDETH(false, BigInt(1000e6), bob.address, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("1") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 3, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelMintPUSD", [
                    {
                        account: bob.address,
                        market: weth.target,
                        exactIn: false,
                        acceptableMaxPayAmount: ethers.parseEther("1"),
                        acceptableMinReceiveAmount: BigInt(1000e6),
                        receiver: bob.address,
                        executionFee: DEFAULT_EXECUTION_FEE,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createMintPUSDETH(false, BigInt(1000e6), bob.address, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("1") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            expect(
                await gasUsed(
                    mixedExecutor.connect(executor).multicall([
                        mixedExecutor.interface.encodeFunctionData("updatePrice", [
                            encodeUpdatePriceParam(await weth.getAddress(), PRICE + 4, await time.latest()),
                        ]),
                        mixedExecutor.interface.encodeFunctionData("executeOrCancelMintPUSD", [
                            {
                                account: bob.address,
                                market: weth.target,
                                exactIn: false,
                                acceptableMaxPayAmount: ethers.parseEther("1"),
                                acceptableMinReceiveAmount: BigInt(1000e6),
                                receiver: bob.address,
                                executionFee: DEFAULT_EXECUTION_FEE,
                            },
                        ]),
                    ]),
                ),
            ).toMatchSnapshot();

            expect(await pusd.balanceOf(bob.address)).to.be.eq(2000e6);
        });
    });

    describe("#executeOrCancelBurnPUSD", () => {
        it("burn half", async () => {
            const {executor, alice, bob, positionRouter, positionRouter2, marketManager, mixedExecutor, weth, pusd} =
                await loadFixture(deployFixture);

            await positionRouter2.connect(alice).createMintLPTETH(alice.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("10") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 1, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                    {
                        account: alice.address,
                        market: weth.target,
                        liquidityDelta: ethers.parseEther("10"),
                        executionFee: DEFAULT_EXECUTION_FEE,
                        receiver: alice.address,
                        payPUSD: false,
                        minReceivedFromBurningPUSD: 0,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createIncreasePositionETH(ethers.parseEther("5"), PRICE + 3, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("2") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 2, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                    {
                        account: bob.address,
                        market: weth.target,
                        marginDelta: ethers.parseEther("2"),
                        sizeDelta: ethers.parseEther("5"),
                        acceptableIndexPrice: PRICE + 3,
                        executionFee: DEFAULT_EXECUTION_FEE,
                        payPUSD: false,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createMintPUSDETH(false, BigInt(1000e6), bob.address, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("1") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 3, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelMintPUSD", [
                    {
                        account: bob.address,
                        market: weth.target,
                        exactIn: false,
                        acceptableMaxPayAmount: ethers.parseEther("1"),
                        acceptableMinReceiveAmount: BigInt(1000e6),
                        receiver: bob.address,
                        executionFee: DEFAULT_EXECUTION_FEE,
                    },
                ]),
            ]);

            await pusd.connect(bob).approve(await marketManager.getAddress(), (1n << 256n) - 1n);

            await positionRouter
                .connect(bob)
                .createBurnPUSD(await weth.getAddress(), true, BigInt(500e6), 1n, bob.address, Uint8Array.of(), {
                    value: DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            expect(
                await gasUsed(
                    mixedExecutor.connect(executor).multicall([
                        mixedExecutor.interface.encodeFunctionData("updatePrice", [
                            encodeUpdatePriceParam(await weth.getAddress(), PRICE + 3, await time.latest()),
                        ]),
                        mixedExecutor.interface.encodeFunctionData("executeOrCancelBurnPUSD", [
                            {
                                account: bob.address,
                                market: weth.target,
                                exactIn: true,
                                acceptableMaxPayAmount: BigInt(500e6),
                                acceptableMinReceiveAmount: 1n,
                                receiver: bob.address,
                                executionFee: DEFAULT_EXECUTION_FEE,
                            },
                        ]),
                    ]),
                ),
            ).toMatchSnapshot();

            expect(await pusd.balanceOf(bob.address)).to.be.eq(500e6);
        });

        it("burn all", async () => {
            const {executor, alice, bob, positionRouter, positionRouter2, marketManager, mixedExecutor, weth, pusd} =
                await loadFixture(deployFixture);

            await positionRouter2.connect(alice).createMintLPTETH(alice.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("10") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 1, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                    {
                        account: alice.address,
                        market: weth.target,
                        liquidityDelta: ethers.parseEther("10"),
                        executionFee: DEFAULT_EXECUTION_FEE,
                        receiver: alice.address,
                        payPUSD: false,
                        minReceivedFromBurningPUSD: 0,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createIncreasePositionETH(ethers.parseEther("5"), PRICE + 3, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("2") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 2, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                    {
                        account: bob.address,
                        market: weth.target,
                        marginDelta: ethers.parseEther("2"),
                        sizeDelta: ethers.parseEther("5"),
                        acceptableIndexPrice: PRICE + 3,
                        executionFee: DEFAULT_EXECUTION_FEE,
                        payPUSD: false,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createMintPUSDETH(false, BigInt(1000e6), bob.address, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("1") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 3, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelMintPUSD", [
                    {
                        account: bob.address,
                        market: weth.target,
                        exactIn: false,
                        acceptableMaxPayAmount: ethers.parseEther("1"),
                        acceptableMinReceiveAmount: BigInt(1000e6),
                        receiver: bob.address,
                        executionFee: DEFAULT_EXECUTION_FEE,
                    },
                ]),
            ]);

            await pusd.connect(bob).transfer(alice.address, BigInt(500e6));

            await pusd.connect(bob).approve(await marketManager.getAddress(), (1n << 256n) - 1n);

            await positionRouter
                .connect(bob)
                .createBurnPUSD(await weth.getAddress(), true, BigInt(500e6), 1n, bob.address, Uint8Array.of(), {
                    value: DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            expect(
                await gasUsed(
                    mixedExecutor.connect(executor).multicall([
                        mixedExecutor.interface.encodeFunctionData("updatePrice", [
                            encodeUpdatePriceParam(await weth.getAddress(), PRICE + 3, await time.latest()),
                        ]),
                        mixedExecutor.interface.encodeFunctionData("executeOrCancelBurnPUSD", [
                            {
                                account: bob.address,
                                market: weth.target,
                                exactIn: true,
                                acceptableMaxPayAmount: BigInt(500e6),
                                acceptableMinReceiveAmount: 1n,
                                receiver: bob.address,
                                executionFee: DEFAULT_EXECUTION_FEE,
                            },
                        ]),
                    ]),
                ),
            ).toMatchSnapshot();

            expect(await pusd.balanceOf(bob.address)).to.be.eq(0);
        });
    });

    describe("#liquidatePosition", () => {
        it("liquidate", async () => {
            const {executor, alice, bob, positionRouter, positionRouter2, marketManager, mixedExecutor, weth} =
                await loadFixture(deployFixture);

            await positionRouter2.connect(alice).createMintLPTETH(alice.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("10") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 1, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                    {
                        account: alice.address,
                        market: weth.target,
                        liquidityDelta: ethers.parseEther("10"),
                        executionFee: DEFAULT_EXECUTION_FEE,
                        receiver: alice.address,
                        payPUSD: false,
                        minReceivedFromBurningPUSD: 0,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createIncreasePositionETH(ethers.parseEther("5"), PRICE + 3, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("2") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await positionRouter
                .connect(alice)
                .createIncreasePositionETH(ethers.parseEther("1"), PRICE + 3, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("2") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 2, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                    {
                        account: bob.address,
                        market: weth.target,
                        marginDelta: ethers.parseEther("2"),
                        sizeDelta: ethers.parseEther("5"),
                        acceptableIndexPrice: PRICE + 3,
                        executionFee: DEFAULT_EXECUTION_FEE,
                        payPUSD: false,
                    },
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                    {
                        account: alice.address,
                        market: weth.target,
                        marginDelta: ethers.parseEther("2"),
                        sizeDelta: ethers.parseEther("1"),
                        acceptableIndexPrice: PRICE + 3,
                        executionFee: DEFAULT_EXECUTION_FEE,
                        payPUSD: false,
                    },
                ]),
            ]);

            expect(
                await gasUsed(
                    mixedExecutor
                        .connect(executor)
                        .multicall([
                            mixedExecutor.interface.encodeFunctionData("updatePrice", [
                                encodeUpdatePriceParam(await weth.getAddress(), BigInt(100e10), await time.latest()),
                            ]),
                            mixedExecutor.interface.encodeFunctionData("liquidatePosition", [
                                await weth.getAddress(),
                                encodeLiquidatePositionParam(bob.address, true),
                            ]),
                        ]),
                ),
            ).toMatchSnapshot();

            const {size} = await marketManager.longPositions(await weth.getAddress(), bob.address);
            expect(size).to.be.eq(ethers.parseEther("0"));
        });

        it("liquidate with liquidity buffer module", async () => {
            const {executor, alice, bob, positionRouter, positionRouter2, marketManager, mixedExecutor, weth} =
                await loadFixture(deployFixture);

            await positionRouter2.connect(alice).createMintLPTETH(alice.address, DEFAULT_EXECUTION_FEE, {
                value: ethers.parseEther("10") + DEFAULT_EXECUTION_FEE,
                gasPrice: GAS_PRICE,
            });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 1, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelMintLPT", [
                    {
                        account: alice.address,
                        market: weth.target,
                        liquidityDelta: ethers.parseEther("10"),
                        executionFee: DEFAULT_EXECUTION_FEE,
                        receiver: alice.address,
                        payPUSD: false,
                        minReceivedFromBurningPUSD: 0,
                    },
                ]),
            ]);

            await positionRouter
                .connect(bob)
                .createIncreasePositionETH(ethers.parseEther("5"), PRICE + 3, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("2") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await positionRouter
                .connect(alice)
                .createIncreasePositionETH(ethers.parseEther("2"), PRICE + 3, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("1") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 2, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                    {
                        account: bob.address,
                        market: weth.target,
                        marginDelta: ethers.parseEther("2"),
                        sizeDelta: ethers.parseEther("5"),
                        acceptableIndexPrice: PRICE + 3,
                        executionFee: DEFAULT_EXECUTION_FEE,
                        payPUSD: false,
                    },
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelIncreasePosition", [
                    {
                        account: alice.address,
                        market: weth.target,
                        marginDelta: ethers.parseEther("1"),
                        sizeDelta: ethers.parseEther("2"),
                        acceptableIndexPrice: PRICE + 3,
                        executionFee: DEFAULT_EXECUTION_FEE,
                        payPUSD: false,
                    },
                ]),
            ]);

            await positionRouter
                .connect(alice)
                .createMintPUSDETH(false, BigInt(20900e6), alice.address, DEFAULT_EXECUTION_FEE, {
                    value: ethers.parseEther("8") + DEFAULT_EXECUTION_FEE,
                    gasPrice: GAS_PRICE,
                });

            await mixedExecutor.connect(executor).multicall([
                mixedExecutor.interface.encodeFunctionData("updatePrice", [
                    encodeUpdatePriceParam(await weth.getAddress(), PRICE + 3, await time.latest()),
                ]),
                mixedExecutor.interface.encodeFunctionData("executeOrCancelMintPUSD", [
                    {
                        account: alice.address,
                        market: weth.target,
                        exactIn: false,
                        acceptableMaxPayAmount: ethers.parseEther("8"),
                        acceptableMinReceiveAmount: BigInt(20900e6),
                        receiver: alice.address,
                        executionFee: DEFAULT_EXECUTION_FEE,
                    },
                ]),
            ]);

            expect(
                await gasUsed(
                    mixedExecutor
                        .connect(executor)
                        .multicall([
                            mixedExecutor.interface.encodeFunctionData("updatePrice", [
                                encodeUpdatePriceParam(await weth.getAddress(), 100e10, await time.latest()),
                            ]),
                            mixedExecutor.interface.encodeFunctionData("liquidatePosition", [
                                await weth.getAddress(),
                                encodeLiquidatePositionParam(bob.address, true),
                            ]),
                        ]),
                ),
            ).toMatchSnapshot();

            const {size} = await marketManager.longPositions(await weth.getAddress(), bob.address);
            expect(size).to.be.eq(ethers.parseEther("0"));

            const {pusdDebt, tokenPayback} = await marketManager.liquidityBufferModules(await weth.getAddress());
            expect(pusdDebt).to.be.gt(0n);
            expect(tokenPayback).to.be.gt(0n);
        });
    });

    describe("#updatePrice", () => {
        it("first and second price updates(refPriceFeed set)", async () => {
            const {executor, mockChainLinkPriceFeed, marketManager, mixedExecutor, weth} =
                await loadFixture(deployFixture);
            await marketManager.updateMarketPriceFeedConfig(
                await weth.getAddress(),
                await mockChainLinkPriceFeed.getAddress(),
                0,
                100000,
            );
            await mockChainLinkPriceFeed.setRoundData(100, 100e8, 0, 0, 0);
            expect(
                await gasUsed(
                    mixedExecutor
                        .connect(executor)
                        .multicall([
                            mixedExecutor.interface.encodeFunctionData("updatePrice", [
                                encodeUpdatePriceParam(await weth.getAddress(), 101e10, (await time.latest()) - 1),
                            ]),
                        ]),
                ),
            ).toMatchSnapshot();
            let maxPrice: bigint, minPrice: bigint;
            ({maxPrice, minPrice} = await marketManager.getPrice(await weth.getAddress()));
            expect(maxPrice).to.be.eq(101e10);
            expect(minPrice).to.be.eq(101e10);

            expect(
                await gasUsed(
                    mixedExecutor
                        .connect(executor)
                        .multicall([
                            mixedExecutor.interface.encodeFunctionData("updatePrice", [
                                encodeUpdatePriceParam(await weth.getAddress(), 102e10, await time.latest()),
                            ]),
                        ]),
                ),
            ).toMatchSnapshot();
            ({maxPrice, minPrice} = await marketManager.getPrice(await weth.getAddress()));
            expect(maxPrice).to.be.eq(102e10);
            expect(minPrice).to.be.eq(102e10);
        });

        it("first and second price updates(refPriceFeed not set)", async () => {
            const {executor, mockChainLinkPriceFeed, marketManager, mixedExecutor, weth} =
                await loadFixture(deployFixture);
            expect(
                await gasUsed(
                    mixedExecutor
                        .connect(executor)
                        .multicall([
                            mixedExecutor.interface.encodeFunctionData("updatePrice", [
                                encodeUpdatePriceParam(await weth.getAddress(), 101e10, (await time.latest()) - 1),
                            ]),
                        ]),
                ),
            ).toMatchSnapshot();
            let maxPrice: bigint, minPrice: bigint;
            ({maxPrice, minPrice} = await marketManager.getPrice(await weth.getAddress()));
            expect(maxPrice).to.be.eq(101e10);
            expect(minPrice).to.be.eq(101e10);

            expect(
                await gasUsed(
                    mixedExecutor
                        .connect(executor)
                        .multicall([
                            mixedExecutor.interface.encodeFunctionData("updatePrice", [
                                encodeUpdatePriceParam(await weth.getAddress(), 102e10, await time.latest()),
                            ]),
                        ]),
                ),
            ).toMatchSnapshot();
            ({maxPrice, minPrice} = await marketManager.getPrice(await weth.getAddress()));
            expect(maxPrice).to.be.eq(102e10);
            expect(minPrice).to.be.eq(102e10);
        });

        it("price updates if reach MaxDeviationRatio", async () => {
            const {executor, mockChainLinkPriceFeed, marketManager, mixedExecutor, weth} =
                await loadFixture(deployFixture);
            await marketManager.updateMarketPriceFeedConfig(
                await weth.getAddress(),
                await mockChainLinkPriceFeed.getAddress(),
                0,
                1000000,
            );
            await mockChainLinkPriceFeed.setRoundData(100, 100e8, 0, 0, 0);
            expect(
                await gasUsed(
                    mixedExecutor
                        .connect(executor)
                        .multicall([
                            mixedExecutor.interface.encodeFunctionData("updatePrice", [
                                encodeUpdatePriceParam(await weth.getAddress(), 120e10, (await time.latest()) - 1),
                            ]),
                        ]),
                ),
            ).toMatchSnapshot();
            let maxPrice: bigint, minPrice: bigint;
            ({maxPrice, minPrice} = await marketManager.getPrice(await weth.getAddress()));
            expect(maxPrice).to.be.eq(120e10);
            expect(minPrice).to.be.eq(100e10);
        });

        it("price updates if reach MaxDeltaDiff", async () => {
            const {executor, mockChainLinkPriceFeed, marketManager, mixedExecutor, weth} =
                await loadFixture(deployFixture);
            await marketManager.updateMarketPriceFeedConfig(
                await weth.getAddress(),
                await mockChainLinkPriceFeed.getAddress(),
                0,
                10000,
            );
            await mockChainLinkPriceFeed.setRoundData(100, 100e8, 0, 0, 0);
            await mixedExecutor
                .connect(executor)
                .multicall([
                    mixedExecutor.interface.encodeFunctionData("updatePrice", [
                        encodeUpdatePriceParam(await weth.getAddress(), 100e10, (await time.latest()) - 1),
                    ]),
                ]);

            expect(
                await gasUsed(
                    mixedExecutor
                        .connect(executor)
                        .multicall([
                            mixedExecutor.interface.encodeFunctionData("updatePrice", [
                                encodeUpdatePriceParam(await weth.getAddress(), 103e10, await time.latest()),
                            ]),
                        ]),
                ),
            ).toMatchSnapshot();
            let maxPrice: bigint, minPrice: bigint;
            ({maxPrice, minPrice} = await marketManager.getPrice(await weth.getAddress()));
            expect(maxPrice).to.be.eq(103e10);
            expect(minPrice).to.be.eq(100e10);
        });
    });
});

function encodeUpdatePriceParam(addr: string, price: BigNumberish, time: number): bigint {
    let packedValue = BigInt(0n);
    packedValue |= BigInt(ethers.getAddress(addr));
    packedValue |= BigInt(price) << 160n;
    packedValue |= BigInt(time) << 224n;
    return packedValue;
}

function encodeLiquidatePositionParam(addr: string, requireSuccess: boolean): bigint {
    let packedValue = BigInt(0n);
    packedValue |= BigInt(ethers.getAddress(addr));
    packedValue |= BigInt(requireSuccess ? 1 : 0) << 160n;
    return packedValue;
}

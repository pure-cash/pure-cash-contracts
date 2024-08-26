import {loadFixture, mine} from "@nomicfoundation/hardhat-network-helpers";
import {expect, use} from "chai";
import {ethers} from "hardhat";
import {jestSnapshotPlugin} from "mocha-chai-jest-snapshot";
import {gasUsed} from "./shared/Gas";
import {genERC20PermitData, resetAllowance} from "./shared/Permit";
import {positionRouter2EstimatedGasLimitTypes} from "./shared/PositionRouterFixture";

use(jestSnapshotPlugin());

describe("PositionRouter2", () => {
    const marketDecimals = 18n;
    const deadline = ethers.MaxUint256;

    const defaultEstimatedGasLimit = 500_000n;
    const gasPrice = ethers.parseUnits("1", "gwei");
    const defaultExecutionFee = gasPrice * defaultEstimatedGasLimit;

    async function deployFixture() {
        const [owner, trader, executor, other] = await ethers.getSigners();
        const weth = await ethers.deployContract("WETH9");
        const market = await ethers.deployContract("ERC20Test", ["Market", "MKT", marketDecimals, 0n]);
        await market.mint(trader.address, 10000n * 10n ** marketDecimals);
        await market.mint(other.address, 10000n * 10n ** marketDecimals);

        const liquidityUtil = await ethers.deployContract("LiquidityUtil");
        const pusdManagerUtil = await ethers.deployContract("PUSDManagerUtil");
        const marketManager = await ethers.deployContract("MockMarketManager", [weth.target], {
            value: 100n,
            libraries: {
                LiquidityUtil: liquidityUtil,
                PUSDManagerUtil: pusdManagerUtil,
            },
        });
        const usd = await ethers.getContractAt("PUSD", await marketManager.usd());
        const usdDecimals = await usd.decimals();
        await marketManager.mintPUSDArbitrary(trader.address, 10000n * 10n ** usdDecimals);

        await marketManager.deployLPToken(market.target, market.symbol + "-LP");
        await marketManager.deployLPToken(weth.target, weth.symbol + "-LP");
        const lpToken = await ethers.getContractAt("LPToken", await marketManager.lpTokens(market.target));
        const wethLpToken = await ethers.getContractAt("LPToken", await marketManager.lpTokens(weth.target));

        await market.mint(marketManager.target, 100n);

        await market.connect(trader).approve(marketManager.target, 10000n * 10n ** marketDecimals);
        await lpToken.connect(trader).approve(marketManager.target, 10000n * 10n ** marketDecimals);
        await wethLpToken.connect(trader).approve(marketManager.target, 10000n * 10n ** marketDecimals);
        await usd.connect(trader).approve(marketManager.target, 10000n * 10n ** usdDecimals);

        const govImpl = await ethers.deployContract("Governable", [owner.address]);
        const positionRouter2 = await ethers.deployContract("PositionRouter2", [
            govImpl.target,
            marketManager.target,
            await weth.getAddress(),
            await positionRouter2EstimatedGasLimitTypes(),
            Array((await positionRouter2EstimatedGasLimitTypes()).length).fill(defaultEstimatedGasLimit),
        ]);
        await positionRouter2.waitForDeployment();
        await positionRouter2.updatePositionExecutor(executor.address, true);

        return {
            owner,
            trader,
            executor,
            other,
            lpToken,
            wethLpToken,
            usd,
            marketManager,
            weth,
            market,
            positionRouter2,
        };
    }

    describe("#updatePositionExecutor", async () => {
        it("update position executor from true to false", async () => {
            const {positionRouter2, other} = await loadFixture(deployFixture);
            await positionRouter2.updatePositionExecutor(other.address, true);
            expect(await gasUsed(positionRouter2.updatePositionExecutor(other.address, false))).toMatchSnapshot();
            expect(await positionRouter2.positionExecutors(other.address)).to.eq(false);
        });
        it("update position executor from false to true", async () => {
            const {positionRouter2, other} = await loadFixture(deployFixture);
            await positionRouter2.updatePositionExecutor(other.address, false);
            expect(await gasUsed(positionRouter2.updatePositionExecutor(other.address, true))).toMatchSnapshot();
            expect(await positionRouter2.positionExecutors(other.address)).to.eq(true);
        });
        it("update position executor from true to true", async () => {
            const {positionRouter2, other} = await loadFixture(deployFixture);
            await positionRouter2.updatePositionExecutor(other.address, true);
            expect(await gasUsed(positionRouter2.updatePositionExecutor(other.address, true))).toMatchSnapshot();
            expect(await positionRouter2.positionExecutors(other.address)).to.eq(true);
        });
        it("update position executor from false to false", async () => {
            const {positionRouter2, other} = await loadFixture(deployFixture);
            await positionRouter2.updatePositionExecutor(other.address, false);
            expect(await gasUsed(positionRouter2.updatePositionExecutor(other.address, false))).toMatchSnapshot();
            expect(await positionRouter2.positionExecutors(other.address)).to.eq(false);
        });
    });

    describe("#updateDelayValues", async () => {
        it("update delay values", async () => {
            const {positionRouter2} = await loadFixture(deployFixture);
            expect(await gasUsed(positionRouter2.updateDelayValues(10n, 20n, 30n))).toMatchSnapshot();
        });
    });

    describe("#updateEstimatedGasLimit", async () => {
        it("update", async () => {
            const {positionRouter2} = await loadFixture(deployFixture);
            const estimatedGasLimit = ethers.parseUnits("1000000", "wei");
            expect(await gasUsed(positionRouter2.updateEstimatedGasLimit(0, estimatedGasLimit))).toMatchSnapshot();
            expect(await positionRouter2.estimatedGasLimits(0)).to.eq(estimatedGasLimit);
        });
    });

    describe("#updateExecutionGasLimit", async () => {
        it("update execution gas limit", async () => {
            const {positionRouter2} = await loadFixture(deployFixture);
            const executionGasLimit = 2000000n;
            expect(await gasUsed(positionRouter2.updateExecutionGasLimit(executionGasLimit))).toMatchSnapshot();
            expect(await positionRouter2.executionGasLimit()).to.eq(executionGasLimit);
        });
    });

    describe("MintLPT", () => {
        const liquidityDelta = 1n * 10n ** marketDecimals;
        describe("#createMintLPT", () => {
            it("first createMintLPT without permitData", async function () {
                const {trader, market, positionRouter2} = await loadFixture(deployFixture);
                expect(
                    await gasUsed(
                        positionRouter2.connect(trader).createMintLPT(market.target, 100n, trader.address, "0x", {
                            value: defaultExecutionFee,
                            gasPrice,
                        }),
                    ),
                ).toMatchSnapshot();
            });
            it("createMintLPT without permitData again", async function () {
                const {trader, market, positionRouter2} = await loadFixture(deployFixture);
                await positionRouter2.connect(trader).createMintLPT(market.target, 100n, trader.address, "0x", {
                    value: defaultExecutionFee,
                    gasPrice,
                });
                expect(
                    await gasUsed(
                        positionRouter2.connect(trader).createMintLPT(market.target, 101n, trader.address, "0x", {
                            value: defaultExecutionFee,
                            gasPrice,
                        }),
                    ),
                ).toMatchSnapshot();
            });
            it("first createMintLPT with permitData", async function () {
                const {trader, market, marketManager, positionRouter2} = await loadFixture(deployFixture);
                await resetAllowance(market, trader, await marketManager.getAddress());
                const permitData = await genERC20PermitData(
                    market,
                    trader,
                    await marketManager.getAddress(),
                    ethers.MaxUint256,
                    deadline,
                );
                expect(
                    await gasUsed(
                        positionRouter2.connect(trader).createMintLPT(market.target, 100n, trader.address, permitData, {
                            value: defaultExecutionFee,
                            gasPrice,
                        }),
                    ),
                ).toMatchSnapshot();
            });
            it("createMintLPT with permitData again", async function () {
                const {trader, market, marketManager, positionRouter2} = await loadFixture(deployFixture);
                await resetAllowance(market, trader, await marketManager.getAddress());
                const permitData = await genERC20PermitData(
                    market,
                    trader,
                    await marketManager.getAddress(),
                    ethers.MaxUint256,
                    deadline,
                );
                await positionRouter2.connect(trader).createMintLPT(market.target, 100n, trader.address, permitData, {
                    value: defaultExecutionFee,
                    gasPrice,
                });
                expect(
                    await gasUsed(
                        positionRouter2.connect(trader).createMintLPT(market.target, 101n, trader.address, "0x", {
                            value: defaultExecutionFee,
                            gasPrice,
                        }),
                    ),
                ).toMatchSnapshot();
            });
        });
        describe("#createMintLPTETH", () => {
            it("first createMintLPTETH", async function () {
                const {trader, positionRouter2} = await loadFixture(deployFixture);
                const liquidityDelta = 100n;
                const value = defaultExecutionFee + liquidityDelta;
                expect(
                    await gasUsed(
                        positionRouter2
                            .connect(trader)
                            .createMintLPTETH(trader.address, defaultExecutionFee, {value, gasPrice}),
                    ),
                ).toMatchSnapshot();
            });
            it("createMintLPTETH again", async function () {
                const {trader, positionRouter2} = await loadFixture(deployFixture);
                const liquidityDelta = 100n;
                let value = defaultExecutionFee + liquidityDelta;
                await positionRouter2
                    .connect(trader)
                    .createMintLPTETH(trader.address, defaultExecutionFee, {value, gasPrice});
                value = value + 1n;
                expect(
                    await gasUsed(
                        positionRouter2
                            .connect(trader)
                            .createMintLPTETH(trader.address, defaultExecutionFee, {value, gasPrice}),
                    ),
                ).toMatchSnapshot();
            });
        });
        describe("#createMintLPTPayPUSD", () => {
            it("first createMintLPTPayPUSD without permitData", async function () {
                const {trader, market, positionRouter2} = await loadFixture(deployFixture);
                expect(
                    await gasUsed(
                        positionRouter2
                            .connect(trader)
                            .createMintLPTPayPUSD(market.target, 100n, trader.address, 0n, "0x", {
                                value: defaultExecutionFee,
                                gasPrice,
                            }),
                    ),
                ).toMatchSnapshot();
            });
            it("createMintLPTPayPUSD without permitData again", async function () {
                const {trader, market, positionRouter2} = await loadFixture(deployFixture);
                await positionRouter2
                    .connect(trader)
                    .createMintLPTPayPUSD(market.target, 100n, trader.address, 0n, "0x", {
                        value: defaultExecutionFee,
                        gasPrice,
                    });
                expect(
                    await gasUsed(
                        positionRouter2
                            .connect(trader)
                            .createMintLPTPayPUSD(market.target, 101n, trader.address, 0n, "0x", {
                                value: defaultExecutionFee,
                                gasPrice,
                            }),
                    ),
                ).toMatchSnapshot();
            });
            it("first createMintLPTPayPUSD with permitData", async function () {
                const {trader, market, usd, positionRouter2} = await loadFixture(deployFixture);
                await resetAllowance(usd, trader, await positionRouter2.getAddress());
                const permitData = await genERC20PermitData(
                    usd,
                    trader,
                    await positionRouter2.getAddress(),
                    ethers.MaxUint256,
                    deadline,
                );
                expect(
                    await gasUsed(
                        positionRouter2
                            .connect(trader)
                            .createMintLPTPayPUSD(market.target, 100n, trader.address, 0n, permitData, {
                                value: defaultExecutionFee,
                                gasPrice,
                            }),
                    ),
                ).toMatchSnapshot();
            });
            it("createMintLPTPayPUSD with permitData again", async function () {
                const {trader, market, usd, positionRouter2} = await loadFixture(deployFixture);
                await resetAllowance(usd, trader, await positionRouter2.getAddress());
                const permitData = await genERC20PermitData(
                    usd,
                    trader,
                    await positionRouter2.getAddress(),
                    ethers.MaxUint256,
                    deadline,
                );
                await positionRouter2
                    .connect(trader)
                    .createMintLPTPayPUSD(market.target, 100n, trader.address, 0n, permitData, {
                        value: defaultExecutionFee,
                        gasPrice,
                    });
                expect(
                    await gasUsed(
                        positionRouter2
                            .connect(trader)
                            .createMintLPTPayPUSD(market.target, 101n, trader.address, 0n, "0x", {
                                value: defaultExecutionFee,
                                gasPrice,
                            }),
                    ),
                ).toMatchSnapshot();
            });
        });
        describe("#cancelMintLPT", () => {
            it("cancel when request not exists", async () => {
                const {owner, weth, positionRouter2} = await loadFixture(deployFixture);
                expect(
                    await gasUsed(
                        positionRouter2.cancelMintLPT(
                            {
                                account: owner.address,
                                market: weth.target,
                                liquidityDelta: 10n ** 18n - 10n ** 15n,
                                executionFee: 10n ** 15n,
                                receiver: owner.address,
                                payPUSD: false,
                                minReceivedFromBurningPUSD: 0,
                            },
                            owner.address,
                        ),
                    ),
                ).toMatchSnapshot();
            });

            it("cancel when executor cancel and market is not weth", async () => {
                const {positionRouter2, market, trader, executor} = await loadFixture(deployFixture);
                await positionRouter2.connect(trader).createMintLPT(market, liquidityDelta, trader.address, "0x", {
                    value: defaultExecutionFee,
                    gasPrice,
                });
                let idParam = {
                    account: trader.address,
                    market: market.getAddress(),
                    liquidityDelta: liquidityDelta,
                    executionFee: defaultExecutionFee,
                    receiver: trader.address,
                    payPUSD: false,
                    minReceivedFromBurningPUSD: 0,
                };
                expect(
                    await gasUsed(positionRouter2.connect(executor).cancelMintLPT(idParam, executor.address)),
                ).toMatchSnapshot();
            });
            it("cancel when executor cancel and market is weth", async () => {
                const {positionRouter2, weth, trader, executor} = await loadFixture(deployFixture);
                await positionRouter2.connect(trader).createMintLPTETH(trader.address, defaultExecutionFee, {
                    value: defaultExecutionFee + 100n,
                    gasPrice,
                });
                let idParam = {
                    account: trader.address,
                    market: weth.getAddress(),
                    liquidityDelta: 100n,
                    executionFee: defaultExecutionFee,
                    receiver: trader.address,
                    payPUSD: false,
                    minReceivedFromBurningPUSD: 0,
                };
                expect(
                    await gasUsed(positionRouter2.connect(executor).cancelMintLPT(idParam, executor.address)),
                ).toMatchSnapshot();
            });
            it("cancel when executor cancel and payPUSD is true", async () => {
                const {positionRouter2, market, usd, trader, executor} = await loadFixture(deployFixture);
                await positionRouter2
                    .connect(trader)
                    .createMintLPTPayPUSD(market.target, 100n, trader.address, 0n, "0x", {
                        value: defaultExecutionFee,
                        gasPrice,
                    });
                let idParam = {
                    account: trader.address,
                    market: market.getAddress(),
                    liquidityDelta: 100n,
                    executionFee: defaultExecutionFee,
                    receiver: trader.address,
                    payPUSD: true,
                    minReceivedFromBurningPUSD: 0,
                };
                expect(
                    await gasUsed(positionRouter2.connect(executor).cancelMintLPT(idParam, executor.address)),
                ).toMatchSnapshot();
            });

            it("cancel when request owner calls and market is not weth", async () => {
                const {positionRouter2, market, trader} = await loadFixture(deployFixture);
                await positionRouter2.connect(trader).createMintLPT(market, liquidityDelta, trader.address, "0x", {
                    value: defaultExecutionFee,
                    gasPrice,
                });
                let idParam = {
                    account: trader.address,
                    market: market.getAddress(),
                    liquidityDelta: liquidityDelta,
                    executionFee: defaultExecutionFee,
                    receiver: trader.address,
                    payPUSD: false,
                    minReceivedFromBurningPUSD: 0,
                };
                await mine(await positionRouter2.minBlockDelayPublic());
                expect(
                    await gasUsed(positionRouter2.connect(trader).cancelMintLPT(idParam, trader.address)),
                ).toMatchSnapshot();
            });
            it("cancel when request owner calls and market is weth", async () => {
                const {positionRouter2, weth, trader} = await loadFixture(deployFixture);
                await positionRouter2.connect(trader).createMintLPTETH(trader.address, defaultExecutionFee, {
                    value: defaultExecutionFee + 100n,
                    gasPrice,
                });
                let idParam = {
                    account: trader.address,
                    market: weth.getAddress(),
                    liquidityDelta: 100n,
                    executionFee: defaultExecutionFee,
                    receiver: trader.address,
                    payPUSD: false,
                    minReceivedFromBurningPUSD: 0,
                };
                await mine(await positionRouter2.minBlockDelayPublic());
                expect(
                    await gasUsed(positionRouter2.connect(trader).cancelMintLPT(idParam, trader.address)),
                ).toMatchSnapshot();
            });
            it("cancel when request owner calls and payPUSD is true", async () => {
                const {positionRouter2, market, usd, trader} = await loadFixture(deployFixture);
                await positionRouter2
                    .connect(trader)
                    .createMintLPTPayPUSD(market.target, 100n, trader.address, 0n, "0x", {
                        value: defaultExecutionFee,
                        gasPrice,
                    });
                let idParam = {
                    account: trader.address,
                    market: market.getAddress(),
                    liquidityDelta: 100n,
                    executionFee: defaultExecutionFee,
                    receiver: trader.address,
                    payPUSD: true,
                    minReceivedFromBurningPUSD: 0,
                };
                await mine(await positionRouter2.minBlockDelayPublic());
                expect(
                    await gasUsed(positionRouter2.connect(trader).cancelMintLPT(idParam, trader.address)),
                ).toMatchSnapshot();
            });
        });
        describe("#executeMintLPT", () => {
            it("execute when request is not exists", async () => {
                const {owner, trader, market, positionRouter2} = await loadFixture(deployFixture);
                expect(
                    await gasUsed(
                        positionRouter2.executeMintLPT(
                            {
                                account: trader.address,
                                market: market.getAddress(),
                                liquidityDelta: 100n,
                                executionFee: defaultExecutionFee,
                                receiver: trader.address,
                                payPUSD: true,
                                minReceivedFromBurningPUSD: 0,
                            },
                            owner.address,
                        ),
                    ),
                ).toMatchSnapshot();
            });

            it("execute mint LPT", async () => {
                const {positionRouter2, market, marketManager, trader, executor} = await loadFixture(deployFixture);
                await positionRouter2.connect(trader).createMintLPT(market, liquidityDelta, trader.address, "0x", {
                    value: defaultExecutionFee,
                    gasPrice,
                });
                let idParam = {
                    account: trader.address,
                    market: market.getAddress(),
                    liquidityDelta: liquidityDelta,
                    executionFee: defaultExecutionFee,
                    receiver: trader.address,
                    payPUSD: false,
                    minReceivedFromBurningPUSD: 0,
                };
                await positionRouter2.updateDelayValues(0n, 0n, 600n);
                expect(
                    await gasUsed(positionRouter2.connect(executor).executeMintLPT(idParam, executor.address)),
                ).toMatchSnapshot();
            });

            it("execute mint LPT and refund execution fee", async () => {
                const {positionRouter2, market, marketManager, trader, executor} = await loadFixture(deployFixture);
                await positionRouter2.connect(trader).createMintLPT(market, liquidityDelta, trader.address, "0x", {
                    value: defaultExecutionFee,
                    gasPrice,
                });
                let idParam = {
                    account: trader.address,
                    market: market.getAddress(),
                    liquidityDelta: liquidityDelta,
                    executionFee: defaultExecutionFee,
                    receiver: trader.address,
                    payPUSD: false,
                    minReceivedFromBurningPUSD: 0,
                };
                await positionRouter2.updateDelayValues(0n, 0n, 600n);
                expect(
                    await gasUsed(
                        positionRouter2
                            .connect(executor)
                            .executeMintLPT(idParam, executor.address, {gasPrice: gasPrice / 2n}),
                    ),
                ).toMatchSnapshot();
            });
        });
        describe("#executeOrCancelMintLPT", () => {
            it("execute mint LPT", async () => {
                const {positionRouter2, market, trader, executor} = await loadFixture(deployFixture);
                await positionRouter2.connect(trader).createMintLPT(market, liquidityDelta, trader.address, "0x", {
                    value: defaultExecutionFee,
                    gasPrice,
                });

                let idParam = {
                    account: trader.address,
                    market: market.target,
                    liquidityDelta: liquidityDelta,
                    executionFee: defaultExecutionFee,
                    receiver: trader.address,
                    payPUSD: false,
                    minReceivedFromBurningPUSD: 0n,
                };

                // set a delay value to prevent expire
                await positionRouter2.updateDelayValues(0n, 0n, 600n);
                expect(
                    await gasUsed(positionRouter2.connect(executor).executeOrCancelMintLPT(idParam, executor.address)),
                ).toMatchSnapshot();
            });
        });
    });

    describe("BurnLPT", () => {
        describe("#createBurnLPT", () => {
            it("first createBurnLPT without permitData", async () => {
                const {positionRouter2, market, trader, marketManager} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 10n);
                expect(
                    await gasUsed(
                        positionRouter2
                            .connect(trader)
                            .createBurnLPT(market, 10n, 0n, trader, "0x", {value: defaultExecutionFee, gasPrice}),
                    ),
                ).toMatchSnapshot();
            });
            it("createBurnLPT without permitData again", async () => {
                const {positionRouter2, market, trader, marketManager} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 21n);
                await positionRouter2
                    .connect(trader)
                    .createBurnLPT(market, 10n, 0n, trader, "0x", {value: defaultExecutionFee, gasPrice});
                expect(
                    await gasUsed(
                        positionRouter2
                            .connect(trader)
                            .createBurnLPT(market, 11n, 0n, trader, "0x", {value: defaultExecutionFee, gasPrice}),
                    ),
                ).toMatchSnapshot();
            });
            it("first createBurnLPT with permitData", async () => {
                const {positionRouter2, market, lpToken, trader, marketManager} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 10n);
                await resetAllowance(lpToken, trader, await marketManager.getAddress());
                const permitData = await genERC20PermitData(
                    lpToken,
                    trader,
                    await marketManager.getAddress(),
                    ethers.MaxUint256,
                    deadline,
                );
                expect(
                    await gasUsed(
                        positionRouter2
                            .connect(trader)
                            .createBurnLPT(market, 10n, 0n, trader, permitData, {value: defaultExecutionFee, gasPrice}),
                    ),
                ).toMatchSnapshot();
            });
            it("createBurnLPT with permitData again", async () => {
                const {positionRouter2, market, lpToken, trader, marketManager} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 21n);
                await resetAllowance(lpToken, trader, await marketManager.getAddress());
                const permitData = await genERC20PermitData(
                    lpToken,
                    trader,
                    await marketManager.getAddress(),
                    ethers.MaxUint256,
                    deadline,
                );
                await positionRouter2
                    .connect(trader)
                    .createBurnLPT(market, 10n, 0n, trader, permitData, {value: defaultExecutionFee, gasPrice});
                expect(
                    await gasUsed(
                        positionRouter2
                            .connect(trader)
                            .createBurnLPT(market, 11n, 0n, trader, "0x", {value: defaultExecutionFee, gasPrice}),
                    ),
                ).toMatchSnapshot();
            });
        });
        describe("#createBurnLPTReceivePUSD", () => {
            it("first createBurnLPTReceivePUSD without permitData", async () => {
                const {positionRouter2, market, lpToken, trader, marketManager} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 100n);
                expect(
                    await gasUsed(
                        positionRouter2.connect(trader).createBurnLPTReceivePUSD(market, 100n, 0n, trader, "0x", {
                            value: defaultExecutionFee,
                            gasPrice,
                        }),
                    ),
                ).toMatchSnapshot();
            });
            it("createBurnLPTReceivePUSD with permitData again", async () => {
                const {positionRouter2, market, lpToken, trader, marketManager} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 201n);
                await positionRouter2
                    .connect(trader)
                    .createBurnLPTReceivePUSD(market, 100n, 0n, trader, "0x", {value: defaultExecutionFee, gasPrice});
                expect(
                    await gasUsed(
                        positionRouter2.connect(trader).createBurnLPTReceivePUSD(market, 101n, 0n, trader, "0x", {
                            value: defaultExecutionFee,
                            gasPrice,
                        }),
                    ),
                ).toMatchSnapshot();
            });
            it("first createBurnLPTReceivePUSD with permitData", async () => {
                const {positionRouter2, market, lpToken, trader, marketManager} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 100n);
                await resetAllowance(lpToken, trader, await marketManager.getAddress());
                const permitData = await genERC20PermitData(
                    lpToken,
                    trader,
                    await marketManager.getAddress(),
                    ethers.MaxUint256,
                    deadline,
                );
                expect(
                    await gasUsed(
                        positionRouter2.connect(trader).createBurnLPTReceivePUSD(market, 100n, 0n, trader, permitData, {
                            value: defaultExecutionFee,
                            gasPrice,
                        }),
                    ),
                ).toMatchSnapshot();
            });
            it("createBurnLPTReceivePUSD with permitData again", async () => {
                const {positionRouter2, market, lpToken, trader, marketManager} = await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 201n);
                await resetAllowance(lpToken, trader, await marketManager.getAddress());
                const permitData = await genERC20PermitData(
                    lpToken,
                    trader,
                    await marketManager.getAddress(),
                    ethers.MaxUint256,
                    deadline,
                );
                await positionRouter2.connect(trader).createBurnLPTReceivePUSD(market, 100n, 0n, trader, permitData, {
                    value: defaultExecutionFee,
                    gasPrice,
                });
                expect(
                    await gasUsed(
                        positionRouter2.connect(trader).createBurnLPTReceivePUSD(market, 101n, 0n, trader, "0x", {
                            value: defaultExecutionFee,
                            gasPrice,
                        }),
                    ),
                ).toMatchSnapshot();
            });
        });

        describe("#cancelBurnLPT", () => {
            it("cancel when request not exists", async () => {
                const {trader, weth, positionRouter2} = await loadFixture(deployFixture);
                expect(
                    await gasUsed(
                        positionRouter2.cancelBurnLPT(
                            {
                                account: trader.address,
                                market: weth.target,
                                amount: 10n,
                                acceptableMinLiquidity: 0n,
                                receiver: trader.address,
                                executionFee: defaultExecutionFee,
                                receivePUSD: true,
                                minPUSDReceived: 0,
                            },
                            trader.address,
                        ),
                    ),
                ).toMatchSnapshot();
            });

            it("cancel when request exists", async () => {
                const {positionRouter2, marketManager, lpToken, market, trader, executor} =
                    await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 100n);
                await positionRouter2
                    .connect(trader)
                    .createBurnLPT(market, 100n, 0n, trader.address, "0x", {value: defaultExecutionFee, gasPrice});
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    amount: 100n,
                    acceptableMinLiquidity: 0n,
                    receiver: trader.address,
                    executionFee: defaultExecutionFee,
                    receivePUSD: false,
                    minPUSDReceived: 0,
                };
                expect(
                    await gasUsed(positionRouter2.connect(executor).cancelBurnLPT(idParam, executor.address)),
                ).toMatchSnapshot();
            });
        });

        describe("#executeBurnLPT", async () => {
            it("execute when request not exists", async () => {
                const {trader, positionRouter2, market} = await loadFixture(deployFixture);
                expect(
                    await gasUsed(
                        positionRouter2.executeBurnLPT(
                            {
                                account: trader.address,
                                market: market.target,
                                amount: 100n,
                                acceptableMinLiquidity: 0n,
                                receiver: trader.address,
                                executionFee: defaultExecutionFee,
                                receivePUSD: false,
                                minPUSDReceived: 0,
                            },
                            trader.address,
                        ),
                    ),
                ).toMatchSnapshot();
            });

            it("execute when the market is not weth", async () => {
                const {positionRouter2, marketManager, market, lpToken, trader, executor} =
                    await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 100n);
                await positionRouter2
                    .connect(trader)
                    .createBurnLPT(market, 100n, 0n, trader.address, "0x", {value: defaultExecutionFee, gasPrice});
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    amount: 100n,
                    acceptableMinLiquidity: 0n,
                    receiver: trader.address,
                    executionFee: defaultExecutionFee,
                    receivePUSD: false,
                    minPUSDReceived: 0,
                };
                // set a delay value to prevent expire
                await positionRouter2.updateDelayValues(0n, 0n, 600n);

                expect(
                    await gasUsed(positionRouter2.connect(executor).executeBurnLPT(idParam, executor.address)),
                ).toMatchSnapshot();
            });
            it("execute when the market is weth", async () => {
                const {positionRouter2, marketManager, weth, wethLpToken, trader, executor, other} =
                    await loadFixture(deployFixture);
                await marketManager.mintLPToken(weth.target, trader.address, 100n);
                await positionRouter2
                    .connect(trader)
                    .createBurnLPT(weth, 100n, 0n, other.address, "0x", {value: defaultExecutionFee, gasPrice});
                let idParam = {
                    account: trader.address,
                    market: weth.target,
                    amount: 100n,
                    acceptableMinLiquidity: 0n,
                    receiver: other.address,
                    executionFee: defaultExecutionFee,
                    receivePUSD: false,
                    minPUSDReceived: 0,
                };
                // set a delay value to prevent expire
                await positionRouter2.updateDelayValues(0n, 0n, 600n);

                await marketManager.setLiquidity(100n);
                expect(
                    await gasUsed(positionRouter2.connect(executor).executeBurnLPT(idParam, executor.address)),
                ).toMatchSnapshot();
            });

            it("execute when the market is weth and refund execution fee", async () => {
                const {positionRouter2, marketManager, weth, wethLpToken, trader, executor, other} =
                    await loadFixture(deployFixture);
                await marketManager.mintLPToken(weth.target, trader.address, 100n);
                await positionRouter2
                    .connect(trader)
                    .createBurnLPT(weth, 100n, 0n, other.address, "0x", {value: defaultExecutionFee, gasPrice});
                let idParam = {
                    account: trader.address,
                    market: weth.target,
                    amount: 100n,
                    acceptableMinLiquidity: 0n,
                    receiver: other.address,
                    executionFee: defaultExecutionFee,
                    receivePUSD: false,
                    minPUSDReceived: 0,
                };
                // set a delay value to prevent expire
                await positionRouter2.updateDelayValues(0n, 0n, 600n);

                await marketManager.setLiquidity(100n);
                expect(
                    await gasUsed(
                        positionRouter2
                            .connect(executor)
                            .executeBurnLPT(idParam, executor.address, {gasPrice: gasPrice / 2n}),
                    ),
                ).toMatchSnapshot();
            });
        });

        describe("#executeOrCancelBurnLPT", () => {
            it("execute burn LPT", async () => {
                const {positionRouter2, marketManager, market, lpToken, trader, executor} =
                    await loadFixture(deployFixture);
                await marketManager.mintLPToken(market.target, trader.address, 100n);
                await positionRouter2
                    .connect(trader)
                    .createBurnLPT(market, 100n, 0n, trader.address, "0x", {value: defaultExecutionFee, gasPrice});
                let idParam = {
                    account: trader.address,
                    market: market.target,
                    amount: 100n,
                    acceptableMinLiquidity: 0n,
                    receiver: trader.address,
                    executionFee: defaultExecutionFee,
                    receivePUSD: false,
                    minPUSDReceived: 0n,
                };
                // set a delay value to prevent expire
                await positionRouter2.updateDelayValues(0n, 0n, 600n);
                expect(
                    await gasUsed(positionRouter2.connect(executor).executeOrCancelBurnLPT(idParam, executor.address)),
                ).toMatchSnapshot();
            });
        });
    });
});

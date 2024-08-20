import {loadFixture, mine} from "@nomicfoundation/hardhat-network-helpers";
import {expect, use} from "chai";
import {ethers, upgrades} from "hardhat";
import {PUSDUpgradeable} from "../typechain-types";
import {ExecutionFeeType, PRICE_1} from "./shared/Constants";
import {jestSnapshotPlugin} from "mocha-chai-jest-snapshot";
import {gasUsed} from "./shared/Gas";
import {genERC20PermitData, resetAllowance} from "./shared/Permit";
import {
    burnPUSDRequestId,
    decreasePositionRequestId,
    increasePositionRequestId,
    mintPUSDRequestId,
} from "./shared/RequestId";
import {
    deployFixture,
    positionRouterExecutionFeeTypes,
    positionRouterMinExecutionFees,
} from "./shared/PositionRouterFixture";

use(jestSnapshotPlugin());
describe("PositionRouter", () => {
    const marketDecimals = 18n;
    const deadline = ethers.MaxUint256;

    describe("#updatePositionExecutor", async () => {
        it("update position executor from true to false", async () => {
            const {positionRouter, other} = await loadFixture(deployFixture);
            await positionRouter.updatePositionExecutor(other.address, true);
            expect(await gasUsed(positionRouter.updatePositionExecutor(other.address, false))).toMatchSnapshot();
            expect(await positionRouter.positionExecutors(other.address)).to.eq(false);
        });
        it("update position executor from false to true", async () => {
            const {positionRouter, other} = await loadFixture(deployFixture);
            await positionRouter.updatePositionExecutor(other.address, false);
            expect(await gasUsed(positionRouter.updatePositionExecutor(other.address, true))).toMatchSnapshot();
            expect(await positionRouter.positionExecutors(other.address)).to.eq(true);
        });
        it("update position executor from true to true", async () => {
            const {positionRouter, other} = await loadFixture(deployFixture);
            await positionRouter.updatePositionExecutor(other.address, true);
            expect(await gasUsed(positionRouter.updatePositionExecutor(other.address, true))).toMatchSnapshot();
            expect(await positionRouter.positionExecutors(other.address)).to.eq(true);
        });
        it("update position executor from false to false", async () => {
            const {positionRouter, other} = await loadFixture(deployFixture);
            await positionRouter.updatePositionExecutor(other.address, false);
            expect(await gasUsed(positionRouter.updatePositionExecutor(other.address, false))).toMatchSnapshot();
            expect(await positionRouter.positionExecutors(other.address)).to.eq(false);
        });
    });

    describe("#updateDelayValues", async () => {
        it("update delay values", async () => {
            const {positionRouter} = await loadFixture(deployFixture);
            expect(await gasUsed(positionRouter.updateDelayValues(10n, 20n, 30n))).toMatchSnapshot();
        });
    });

    describe("#updateMinExecutionFee", async () => {
        it("update min execution fee", async () => {
            const {positionRouter} = await loadFixture(deployFixture);
            const executionFeeTypes = await positionRouterExecutionFeeTypes();
            const minExecutionFees = await positionRouterMinExecutionFees();
            expect(executionFeeTypes.length).to.eq(minExecutionFees.length);
            for (let i = 0; i < executionFeeTypes.length; i++) {
                expect(await positionRouter.minExecutionFees(executionFeeTypes[i])).to.eq(minExecutionFees[i]);
                expect(
                    await gasUsed(
                        positionRouter.updateMinExecutionFee(executionFeeTypes[i], minExecutionFees[i] + 1000n),
                    ),
                ).toMatchSnapshot();
                expect(await positionRouter.minExecutionFees(executionFeeTypes[i])).to.eq(minExecutionFees[i] + 1000n);
            }
        });
    });

    describe("#updateExecutionGasLimit", async () => {
        it("update execution gas limit", async () => {
            const {positionRouter} = await loadFixture(deployFixture);
            const executionGasLimit = 2000000n;
            expect(await gasUsed(positionRouter.updateExecutionGasLimit(executionGasLimit))).toMatchSnapshot();
            expect(await positionRouter.executionGasLimit()).to.eq(executionGasLimit);
        });
    });

    describe("MintPUSD", () => {
        describe("#createMintPUSD", () => {
            it("first createMintPUSD without permitData", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createMintPUSD(market.target, false, 100n, 0n, trader.address, "0x", {
                                value: minExecutionFee,
                            }),
                    ),
                ).toMatchSnapshot();
                const param = {
                    account: trader.address,
                    market: market.target,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                const id = await mintPUSDRequestId(param);
                expect(await positionRouter.blockNumbers(id)).is.gt(0n);
            });
            it("createMintPUSD without permitData again", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                await positionRouter
                    .connect(trader)
                    .createMintPUSD(market.target, false, 100n, 0n, trader.address, "0x", {value: minExecutionFee});
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createMintPUSD(market.target, false, 100n, 1n, trader.address, "0x", {
                                value: minExecutionFee,
                            }),
                    ),
                ).toMatchSnapshot();
                const param1 = {
                    account: trader.address,
                    market: market.target,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                const param2 = {
                    account: trader.address,
                    market: market.target,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 1n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                const id1 = await mintPUSDRequestId(param1);
                const id2 = await mintPUSDRequestId(param2);
                expect(await positionRouter.blockNumbers(id1)).is.gt(0n);
                expect(await positionRouter.blockNumbers(id2)).is.gt(0n);
            });
            it("first createMintPUSD with permitData", async function () {
                const {trader, market, marketManager, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                await resetAllowance(market, trader, await marketManager.getAddress());
                const permitData = await genERC20PermitData(
                    market,
                    trader,
                    await marketManager.getAddress(),
                    100n,
                    deadline,
                );
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createMintPUSD(market.target, false, 100n, 0n, trader.address, permitData, {
                                value: minExecutionFee,
                            }),
                    ),
                ).toMatchSnapshot();
                const param = {
                    account: trader.address,
                    market: market.target,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                const id = await mintPUSDRequestId(param);
                expect(await positionRouter.blockNumbers(id)).is.gt(0n);
            });
            it("createMintPUSD with permitData again", async function () {
                const {trader, market, marketManager, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                await resetAllowance(market, trader, await marketManager.getAddress());
                const permitData = await genERC20PermitData(
                    market,
                    trader,
                    await marketManager.getAddress(),
                    ethers.MaxUint256,
                    deadline,
                );
                await positionRouter
                    .connect(trader)
                    .createMintPUSD(market.target, false, 100n, 0n, trader.address, permitData, {
                        value: minExecutionFee,
                    });
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createMintPUSD(market.target, false, 100n, 1n, trader.address, "0x", {
                                value: minExecutionFee,
                            }),
                    ),
                ).toMatchSnapshot();
                const param1 = {
                    account: trader.address,
                    market: market.target,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                const param2 = {
                    account: trader.address,
                    market: market.target,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 1n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                const id1 = await mintPUSDRequestId(param1);
                const id2 = await mintPUSDRequestId(param2);
                expect(await positionRouter.blockNumbers(id1)).is.gt(0n);
                expect(await positionRouter.blockNumbers(id2)).is.gt(0n);
            });
        });
        describe("#createMintPUSDETH", () => {
            it("first createMintPUSDETH", async function () {
                const {trader, weth, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSDETH);
                const amount = 100n;
                const value = minExecutionFee + amount;
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createMintPUSDETH(false, 0n, trader.address, minExecutionFee, {value}),
                    ),
                ).toMatchSnapshot();
                const param = {
                    account: trader.address,
                    market: weth.target,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                const id = await mintPUSDRequestId(param);
                expect(await positionRouter.blockNumbers(id)).is.gt(0n);
            });
            it("createMintPUSDETH again", async function () {
                const {trader, weth, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSDETH);
                const amount = 100n;
                const value = minExecutionFee + amount;
                await positionRouter
                    .connect(trader)
                    .createMintPUSDETH(false, 0n, trader.address, minExecutionFee, {value});
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createMintPUSDETH(false, 1n, trader.address, minExecutionFee, {value}),
                    ),
                ).toMatchSnapshot();
                const param1 = {
                    account: trader.address,
                    market: weth.target,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                const param2 = {
                    account: trader.address,
                    market: weth.target,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 1n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                const id1 = await mintPUSDRequestId(param1);
                const id2 = await mintPUSDRequestId(param2);
                expect(await positionRouter.blockNumbers(id1)).is.gt(0n);
                expect(await positionRouter.blockNumbers(id2)).is.gt(0n);
            });
        });
        describe("#cancelMintPUSD", () => {
            it("cancel when request not exists", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                const param = {
                    account: trader.address,
                    market: market.target,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                expect(await gasUsed(positionRouter.cancelMintPUSD(param, trader.address))).toMatchSnapshot();
            });

            it("cancel when executor cancel and market is not weth", async () => {
                const {positionRouter, market, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                await positionRouter
                    .connect(trader)
                    .createMintPUSD(market.target, false, 100n, 0n, trader.address, "0x", {value: minExecutionFee});
                const param = {
                    account: trader.address,
                    market: market.target,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                const id = await mintPUSDRequestId(param);
                expect(
                    await gasUsed(positionRouter.connect(executor).cancelMintPUSD(param, executor.address)),
                ).toMatchSnapshot();
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("cancel when executor cancel and market is weth", async () => {
                const {positionRouter, weth, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSDETH);
                await positionRouter.connect(trader).createMintPUSDETH(true, 100n, trader.address, minExecutionFee, {
                    value: minExecutionFee + 100n,
                });
                const param = {
                    account: trader.address,
                    market: weth.target,
                    exactIn: true,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                expect(
                    await gasUsed(positionRouter.connect(executor).cancelMintPUSD(param, executor.address)),
                ).toMatchSnapshot();
                const id = await mintPUSDRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });

            it("cancel when request owner calls", async () => {
                const {positionRouter, market, trader} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                await positionRouter
                    .connect(trader)
                    .createMintPUSD(market.target, false, 100n, 0n, trader.address, "0x", {value: minExecutionFee});
                await mine(await positionRouter.minBlockDelayPublic());
                const param = {
                    account: trader.address,
                    market: market.target,
                    exactIn: true,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                expect(
                    await gasUsed(positionRouter.connect(trader).cancelMintPUSD(param, trader.address)),
                ).toMatchSnapshot();
                const id = await mintPUSDRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });
        describe("#executeMintPUSD", () => {
            it("execute when request is not exists", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                const param = {
                    account: trader.address,
                    market: market.target,
                    exactIn: true,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                expect(await gasUsed(positionRouter.executeMintPUSD(param, trader.address))).toMatchSnapshot();
            });

            it("execute when the exactIn is true and market is weth", async () => {
                const {positionRouter, marketManager, weth, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSDETH);
                await positionRouter.connect(trader).createMintPUSDETH(true, 0n, trader.address, minExecutionFee, {
                    value: minExecutionFee + 100n,
                });
                // set a delay value to prevent expire
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await marketManager.setPayAmount(80n);
                const param = {
                    account: trader.address,
                    market: weth.target,
                    exactIn: true,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                expect(
                    await gasUsed(positionRouter.connect(executor).executeMintPUSD(param, executor.address)),
                ).toMatchSnapshot();
                const id = await mintPUSDRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("execute when the exactIn is true and market is not weth", async () => {
                const {positionRouter, market, marketManager, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                await positionRouter
                    .connect(trader)
                    .createMintPUSD(market.target, true, 100n, 0n, trader.address, "0x", {value: minExecutionFee});
                // set a delay value to prevent expire
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await marketManager.setPayAmount(80n);
                const param = {
                    account: trader.address,
                    market: market.target,
                    exactIn: true,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                expect(
                    await gasUsed(positionRouter.connect(executor).executeMintPUSD(param, executor.address)),
                ).toMatchSnapshot();
                const id = await mintPUSDRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("execute when the exactIn is false and market is weth", async () => {
                const {positionRouter, marketManager, weth, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSDETH);
                await positionRouter.connect(trader).createMintPUSDETH(false, 0n, trader.address, minExecutionFee, {
                    value: minExecutionFee + 100n,
                });
                // set a delay value to prevent expire
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await marketManager.setPayAmount(80n);
                const param = {
                    account: trader.address,
                    market: weth.target,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                expect(
                    await gasUsed(positionRouter.connect(executor).executeMintPUSD(param, executor.address)),
                ).toMatchSnapshot();
                const id = await mintPUSDRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("execute when the exactIn is false and market is not weth", async () => {
                const {positionRouter, market, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                await positionRouter
                    .connect(trader)
                    .createMintPUSD(market.target, false, 100n, 0n, trader.address, "0x", {value: minExecutionFee});
                // set a delay value to prevent expire
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                const param = {
                    account: trader.address,
                    market: market.target,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                expect(
                    await gasUsed(positionRouter.connect(executor).executeMintPUSD(param, executor.address)),
                ).toMatchSnapshot();
                const id = await mintPUSDRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });
        describe("#executeOrCancelMintPUSD", () => {
            it("cancel request if execution reverted", async () => {
                const {trader, executor, positionRouter, market} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                // _maxBlockDelay is 0, execution will revert immediately
                await positionRouter.updateDelayValues(0, 0, 0);

                // all requests should be cancelled because they reverted
                await positionRouter
                    .connect(trader)
                    .createMintPUSD(market.target, false, 100n, 0n, trader.address, "0x", {value: minExecutionFee});

                const param = {
                    account: trader.address,
                    market: market.target,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                expect(
                    await gasUsed(positionRouter.connect(executor).executeOrCancelMintPUSD(param, executor.address)),
                ).toMatchSnapshot();
                const id = await mintPUSDRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("execute request if execution passed", async () => {
                const {trader, executor, positionRouter, market} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                await positionRouter
                    .connect(trader)
                    .createMintPUSD(market.target, false, 100n, 0n, trader.address, "0x", {value: minExecutionFee});
                const param = {
                    account: trader.address,
                    market: market.target,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                await mine(await positionRouter.minBlockDelayExecutor());
                expect(
                    await gasUsed(positionRouter.connect(executor).executeOrCancelMintPUSD(param, executor.address)),
                ).toMatchSnapshot();
                const id = await mintPUSDRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });
    });

    describe("BurnPUSD", () => {
        describe("#createBurnPUSD", () => {
            it("first createBurnPUSD without permitData", async () => {
                const {positionRouter, market, trader} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createBurnPUSD(market, false, 100n, 0n, trader, "0x", {value: minExecutionFee}),
                    ),
                ).toMatchSnapshot();
                const param = {
                    market: market.target,
                    account: trader.address,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                const id = await burnPUSDRequestId(param);
                expect(await positionRouter.blockNumbers(id)).is.gt(0n);
            });
            it("createBurnPUSD without permitData again", async () => {
                const {positionRouter, market, trader} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                await positionRouter
                    .connect(trader)
                    .createBurnPUSD(market, false, 100n, 0n, trader, "0x", {value: minExecutionFee});
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createBurnPUSD(market, false, 100n, 1n, trader, "0x", {value: minExecutionFee}),
                    ),
                ).toMatchSnapshot();
                const param1 = {
                    market: market.target,
                    account: trader.address,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                const param2 = {
                    market: market.target,
                    account: trader.address,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 1n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                const id1 = await burnPUSDRequestId(param1);
                const id2 = await burnPUSDRequestId(param2);
                expect(await positionRouter.blockNumbers(id1)).is.gt(0n);
                expect(await positionRouter.blockNumbers(id2)).is.gt(0n);
            });
            it("first createBurnPUSD with permitData", async () => {
                const {positionRouter, market, usd, trader, marketManager} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                await resetAllowance(usd, trader, await marketManager.getAddress());
                const permitData = await genERC20PermitData(
                    usd,
                    trader,
                    await marketManager.getAddress(),
                    100n,
                    deadline,
                );
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createBurnPUSD(market, false, 100n, 0n, trader, permitData, {value: minExecutionFee}),
                    ),
                ).toMatchSnapshot();
                const param = {
                    market: market.target,
                    account: trader.address,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                const id = await burnPUSDRequestId(param);
                expect(await positionRouter.blockNumbers(id)).is.gt(0n);
            });
            it("createBurnPUSD with permitData again", async () => {
                const {positionRouter, market, usd, trader, marketManager} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                await resetAllowance(usd, trader, await marketManager.getAddress());
                const permitData = await genERC20PermitData(
                    usd,
                    trader,
                    await marketManager.getAddress(),
                    ethers.MaxUint256,
                    deadline,
                );
                await positionRouter
                    .connect(trader)
                    .createBurnPUSD(market, false, 100n, 0n, trader, permitData, {value: minExecutionFee});
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createBurnPUSD(market, false, 100n, 1n, trader, "0x", {value: minExecutionFee}),
                    ),
                ).toMatchSnapshot();
                const param1 = {
                    market: market.target,
                    account: trader.address,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                const param2 = {
                    market: market.target,
                    account: trader.address,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 1n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                const id1 = await burnPUSDRequestId(param1);
                const id2 = await burnPUSDRequestId(param2);
                expect(await positionRouter.blockNumbers(id1)).is.gt(0n);
                expect(await positionRouter.blockNumbers(id2)).is.gt(0n);
            });
        });

        describe("#cancelBurnPUSD", () => {
            it("cancel when request not exists", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                const param = {
                    market: market.target,
                    account: trader.address,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                expect(await gasUsed(positionRouter.cancelBurnPUSD(param, trader.address))).toMatchSnapshot();
            });

            it("cancel burn PUSD", async () => {
                const {positionRouter, market, usd, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                await positionRouter
                    .connect(trader)
                    .createBurnPUSD(market, false, 100n, 0n, trader, "0x", {value: minExecutionFee});
                const param = {
                    market: market.target,
                    account: trader.address,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                expect(
                    await gasUsed(positionRouter.connect(executor).cancelBurnPUSD(param, executor.address)),
                ).toMatchSnapshot();
                const id = await burnPUSDRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });

        describe("#executeBurnPUSD", () => {
            it("execute when request not exists", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                const param = {
                    market: market.target,
                    account: trader.address,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                expect(await gasUsed(positionRouter.executeBurnPUSD(param, trader.address))).toMatchSnapshot();
            });

            it("execute when exactIn is true and the market is weth", async () => {
                const {positionRouter, marketManager, weth, usd, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                await positionRouter
                    .connect(trader)
                    .createBurnPUSD(weth, true, 100n, 0n, trader, "0x", {value: minExecutionFee});

                // set a delay value to prevent expire
                await positionRouter.updateDelayValues(0n, 0n, 600n);

                await marketManager.setPayAmount(80n);
                await marketManager.setReceiveAmount(100n);
                const param = {
                    market: weth.target,
                    account: trader.address,
                    exactIn: true,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                expect(
                    await gasUsed(positionRouter.connect(executor).executeBurnPUSD(param, executor.address)),
                ).toMatchSnapshot();
                const id = await burnPUSDRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("execute when exactIn is true and the market is not weth", async () => {
                const {positionRouter, marketManager, market, usd, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                await positionRouter
                    .connect(trader)
                    .createBurnPUSD(market, true, 100n, 0n, trader, "0x", {value: minExecutionFee});

                // set a delay value to prevent expire
                await positionRouter.updateDelayValues(0n, 0n, 600n);

                await marketManager.setPayAmount(80n);
                await marketManager.setReceiveAmount(100n);
                const param = {
                    market: market.target,
                    account: trader.address,
                    exactIn: true,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                expect(
                    await gasUsed(positionRouter.connect(executor).executeBurnPUSD(param, executor.address)),
                ).toMatchSnapshot();
                const id = await burnPUSDRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("execute when exactIn is false and the market is weth", async () => {
                const {positionRouter, marketManager, weth, usd, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                await positionRouter
                    .connect(trader)
                    .createBurnPUSD(weth, false, 100n, 0n, trader, "0x", {value: minExecutionFee});

                // set a delay value to prevent expire
                await positionRouter.updateDelayValues(0n, 0n, 600n);

                await marketManager.setPayAmount(80n);
                await marketManager.setReceiveAmount(100n);
                const param = {
                    market: weth.target,
                    account: trader.address,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                expect(
                    await gasUsed(positionRouter.connect(executor).executeBurnPUSD(param, executor.address)),
                ).toMatchSnapshot();
                const id = await burnPUSDRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("execute when exactIn is false and market is not weth", async () => {
                const {positionRouter, marketManager, market, usd, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                await positionRouter
                    .connect(trader)
                    .createBurnPUSD(market, false, 100n, 0n, trader, "0x", {value: minExecutionFee});

                // set a delay value to prevent expire
                await positionRouter.updateDelayValues(0n, 0n, 600n);

                await marketManager.setPayAmount(80n);
                const param = {
                    market: market.target,
                    account: trader.address,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                expect(
                    await gasUsed(positionRouter.connect(executor).executeBurnPUSD(param, executor.address)),
                ).toMatchSnapshot();
                const id = await burnPUSDRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });

        describe("#executeOrCancelBurnPUSD", () => {
            it("cancel request if execution reverted", async () => {
                const {trader, executor, positionRouter, market} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                // _maxBlockDelay is 0, execution will revert immediately
                await positionRouter.updateDelayValues(0, 0, 0);

                // all requests should be cancelled because they reverted
                await positionRouter
                    .connect(trader)
                    .createBurnPUSD(market, false, 100n, 0n, trader, "0x", {value: minExecutionFee});

                const param = {
                    market: market.target,
                    account: trader.address,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                const tx = positionRouter.connect(executor).executeOrCancelBurnPUSD(param, executor.address);
                expect(await gasUsed(tx)).toMatchSnapshot();
                const id = await burnPUSDRequestId(param);
                await expect(tx).to.emit(positionRouter, "BurnPUSDCancelled").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("execute request if execution passed", async () => {
                const {trader, executor, positionRouter, market} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                await positionRouter
                    .connect(trader)
                    .createBurnPUSD(market, false, 100n, 0n, trader, "0x", {value: minExecutionFee});
                const param = {
                    market: market.target,
                    account: trader.address,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                await mine(await positionRouter.minBlockDelayExecutor());
                const tx = positionRouter.connect(executor).executeOrCancelBurnPUSD(param, executor.address);
                expect(await gasUsed(tx)).toMatchSnapshot();
                const id = await burnPUSDRequestId(param);
                await expect(tx).to.emit(positionRouter, "BurnPUSDExecuted").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });
    });

    describe("IncreasePosition", () => {
        describe("#createIncreasePosition", () => {
            it("first createIncreasePosition without permitData", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createIncreasePosition(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee}),
                    ),
                ).toMatchSnapshot();
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: false,
                };
                const id = await increasePositionRequestId(param);
                expect(await positionRouter.blockNumbers(id)).is.gt(0n);
            });
            it("createIncreasePosition without permitData again", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                await positionRouter
                    .connect(trader)
                    .createIncreasePosition(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee});
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createIncreasePosition(market, 200n, 200n, PRICE_1, "0x", {value: minExecutionFee}),
                    ),
                ).toMatchSnapshot();
                const param1 = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: false,
                };
                const param2 = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 200n,
                    sizeDelta: 200n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: false,
                };
                const id1 = await increasePositionRequestId(param1);
                const id2 = await increasePositionRequestId(param2);
                expect(await positionRouter.blockNumbers(id1)).is.gt(0n);
                expect(await positionRouter.blockNumbers(id2)).is.gt(0n);
            });
            it("first createIncreasePosition with permitData", async function () {
                const {trader, market, marketManager, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                await resetAllowance(market, trader, await marketManager.getAddress());
                const permitData = await genERC20PermitData(
                    market,
                    trader,
                    await marketManager.getAddress(),
                    100n,
                    deadline,
                );
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createIncreasePosition(market, 100n, 100n, PRICE_1, permitData, {value: minExecutionFee}),
                    ),
                ).toMatchSnapshot();
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: false,
                };
                const id = await increasePositionRequestId(param);
                expect(await positionRouter.blockNumbers(id)).is.gt(0n);
            });
            it("createIncreasePosition with permitData again", async function () {
                const {trader, market, marketManager, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                await resetAllowance(market, trader, await marketManager.getAddress());
                const permitData = await genERC20PermitData(
                    market,
                    trader,
                    await marketManager.getAddress(),
                    ethers.MaxUint256,
                    deadline,
                );
                await positionRouter
                    .connect(trader)
                    .createIncreasePosition(market, 100n, 100n, PRICE_1, permitData, {value: minExecutionFee});
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createIncreasePosition(market, 200n, 200n, PRICE_1, "0x", {value: minExecutionFee}),
                    ),
                ).toMatchSnapshot();
                const param1 = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: false,
                };
                const param2 = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 200n,
                    sizeDelta: 200n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: false,
                };
                const id1 = await increasePositionRequestId(param1);
                const id2 = await increasePositionRequestId(param2);
                expect(await positionRouter.blockNumbers(id1)).is.gt(0n);
                expect(await positionRouter.blockNumbers(id2)).is.gt(0n);
            });
        });
        describe("#createIncreasePositionETH", () => {
            it("first createIncreasePositionETH", async function () {
                const {trader, weth, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionETH);
                const amount = 100n;
                const value = minExecutionFee + amount;
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createIncreasePositionETH(100n, PRICE_1, minExecutionFee, {value}),
                    ),
                ).toMatchSnapshot();
                const param = {
                    account: trader.address,
                    market: weth.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: false,
                };
                const id = await increasePositionRequestId(param);
                expect(await positionRouter.blockNumbers(id)).is.gt(0n);
            });
            it("createIncreasePositionETH again", async function () {
                const {trader, weth, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionETH);
                const amount = 100n;
                const value = minExecutionFee + amount;
                await positionRouter.connect(trader).createIncreasePositionETH(100n, PRICE_1, minExecutionFee, {value});
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createIncreasePositionETH(200n, PRICE_1, minExecutionFee, {value}),
                    ),
                ).toMatchSnapshot();
                const param1 = {
                    account: trader.address,
                    market: weth.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: false,
                };
                const param2 = {
                    account: trader.address,
                    market: weth.target,
                    marginDelta: 100n,
                    sizeDelta: 200n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: false,
                };
                const id1 = await increasePositionRequestId(param1);
                const id2 = await increasePositionRequestId(param2);
                expect(await positionRouter.blockNumbers(id1)).is.gt(0n);
                expect(await positionRouter.blockNumbers(id2)).is.gt(0n);
            });
        });
        describe("#createIncreasePositionPayPUSD", () => {
            it("first createIncreasePositionPayPUSD without permitData", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionPayPUSD);
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createIncreasePositionPayPUSD(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee}),
                    ),
                ).toMatchSnapshot();
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: true,
                };
                const id = await increasePositionRequestId(param);
                expect(await positionRouter.blockNumbers(id)).is.gt(0n);
            });
            it("createIncreasePositionPayPUSD without permitData again", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionPayPUSD);
                await positionRouter
                    .connect(trader)
                    .createIncreasePositionPayPUSD(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee});
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createIncreasePositionPayPUSD(market, 200n, 200n, PRICE_1, "0x", {value: minExecutionFee}),
                    ),
                ).toMatchSnapshot();
                const param1 = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: true,
                };
                const param2 = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 200n,
                    sizeDelta: 200n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: true,
                };
                const id1 = await increasePositionRequestId(param1);
                const id2 = await increasePositionRequestId(param2);
                expect(await positionRouter.blockNumbers(id1)).is.gt(0n);
                expect(await positionRouter.blockNumbers(id2)).is.gt(0n);
            });
            it("first createIncreasePositionPayPUSD with permitData", async function () {
                const {trader, market, usd, marketManager, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionPayPUSD);
                await resetAllowance(usd, trader, await marketManager.getAddress());
                const permitData = await genERC20PermitData(
                    usd,
                    trader,
                    await marketManager.getAddress(),
                    100n,
                    deadline,
                );
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createIncreasePositionPayPUSD(market, 100n, 100n, PRICE_1, permitData, {
                                value: minExecutionFee,
                            }),
                    ),
                ).toMatchSnapshot();
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: true,
                };
                const id = await increasePositionRequestId(param);
                expect(await positionRouter.blockNumbers(id)).is.gt(0n);
            });
            it("createIncreasePositionPayPUSD with permitData again", async function () {
                const {trader, market, usd, marketManager, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionPayPUSD);
                await resetAllowance(usd, trader, await marketManager.getAddress());
                const permitData = await genERC20PermitData(
                    usd,
                    trader,
                    await marketManager.getAddress(),
                    ethers.MaxUint256,
                    deadline,
                );
                await positionRouter
                    .connect(trader)
                    .createIncreasePositionPayPUSD(market, 100n, 100n, PRICE_1, permitData, {value: minExecutionFee});
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createIncreasePositionPayPUSD(market, 200n, 200n, PRICE_1, "0x", {
                                value: minExecutionFee,
                            }),
                    ),
                ).toMatchSnapshot();
                const param1 = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: true,
                };
                const param2 = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 200n,
                    sizeDelta: 200n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: true,
                };
                const id1 = await increasePositionRequestId(param1);
                const id2 = await increasePositionRequestId(param2);
                expect(await positionRouter.blockNumbers(id1)).is.gt(0n);
                expect(await positionRouter.blockNumbers(id2)).is.gt(0n);
            });
        });
        describe("#cancelIncreasePosition", () => {
            it("cancel when request not exists", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionPayPUSD);
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: true,
                };
                expect(await gasUsed(positionRouter.cancelIncreasePosition(param, trader.address))).toMatchSnapshot();
            });

            it("cancel when executor cancel and market is not weth", async () => {
                const {positionRouter, market, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                await positionRouter
                    .connect(trader)
                    .createIncreasePosition(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee});
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: false,
                };
                expect(
                    await gasUsed(positionRouter.connect(executor).cancelIncreasePosition(param, executor.address)),
                ).toMatchSnapshot();
                const id = await increasePositionRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("cancel when executor cancel and market is weth", async () => {
                const {positionRouter, weth, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionETH);
                await positionRouter
                    .connect(trader)
                    .createIncreasePositionETH(100n, PRICE_1, minExecutionFee, {value: minExecutionFee + 100n});
                const param = {
                    account: trader.address,
                    market: weth.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: false,
                };
                expect(
                    await gasUsed(positionRouter.connect(executor).cancelIncreasePosition(param, executor.address)),
                ).toMatchSnapshot();
                const id = await increasePositionRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("cancel when executor cancel and payPUSD is true", async () => {
                const {positionRouter, market, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionPayPUSD);
                await positionRouter
                    .connect(trader)
                    .createIncreasePositionPayPUSD(market.target, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee});
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: true,
                };
                expect(
                    await gasUsed(positionRouter.connect(executor).cancelIncreasePosition(param, executor.address)),
                ).toMatchSnapshot();
                const id = await increasePositionRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });

            it("cancel when request owner calls and market is not weth", async () => {
                const {positionRouter, market, trader} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                await positionRouter
                    .connect(trader)
                    .createIncreasePosition(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee});
                await mine(await positionRouter.minBlockDelayPublic());
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: true,
                };
                expect(
                    await gasUsed(positionRouter.connect(trader).cancelIncreasePosition(param, trader.address)),
                ).toMatchSnapshot();
                const id = await increasePositionRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });

            it("cancel when request owner calls and market is weth", async () => {
                const {positionRouter, weth, trader} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionETH);
                await positionRouter
                    .connect(trader)
                    .createIncreasePositionETH(100n, PRICE_1, minExecutionFee, {value: minExecutionFee + 100n});
                await mine(await positionRouter.minBlockDelayPublic());
                const param = {
                    account: trader.address,
                    market: weth.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: false,
                };
                expect(
                    await gasUsed(positionRouter.connect(trader).cancelIncreasePosition(param, trader.address)),
                ).toMatchSnapshot();
                const id = await increasePositionRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });

            it("cancel when request owner calls and payPUSD is true", async () => {
                const {positionRouter, market, trader} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionPayPUSD);
                await positionRouter
                    .connect(trader)
                    .createIncreasePositionPayPUSD(market.target, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee});
                await mine(await positionRouter.minBlockDelayPublic());
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: true,
                };
                expect(
                    await gasUsed(positionRouter.connect(trader).cancelIncreasePosition(param, trader.address)),
                ).toMatchSnapshot();
                const id = await increasePositionRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });
        describe("#executeIncreasePosition", () => {
            it("execute when request is not exists", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: false,
                };
                expect(await gasUsed(positionRouter.executeIncreasePosition(param, trader.address))).toMatchSnapshot();
            });

            it("execute when request is exists", async () => {
                const {positionRouter, market, marketManager, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                await positionRouter
                    .connect(trader)
                    .createIncreasePosition(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee});
                // set a delay value to prevent expire
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await marketManager.setMaxPrice(PRICE_1);
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: false,
                };
                expect(
                    await gasUsed(positionRouter.connect(executor).executeIncreasePosition(param, executor.address)),
                ).toMatchSnapshot();
                const id = await increasePositionRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });
        describe("#executeOrCancelIncreasePosition", () => {
            it("cancel request if execution reverted", async () => {
                const {trader, executor, positionRouter, market} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                // _maxBlockDelay is 0, execution will revert immediately
                await positionRouter.updateDelayValues(0, 0, 0);

                // all requests should be cancelled because they reverted
                await positionRouter
                    .connect(trader)
                    .createIncreasePosition(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee});

                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: false,
                };
                const tx = positionRouter.connect(executor).executeOrCancelIncreasePosition(param, executor.address);
                expect(await gasUsed(tx)).toMatchSnapshot();
                const id = await increasePositionRequestId(param);
                await expect(tx).to.emit(positionRouter, "IncreasePositionCancelled").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("execute request if execution passed", async () => {
                const {trader, executor, positionRouter, market, marketManager} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                await positionRouter
                    .connect(trader)
                    .createIncreasePosition(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee});
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: false,
                };
                await mine(await positionRouter.minBlockDelayExecutor());
                await marketManager.setMaxPrice(PRICE_1);
                const tx = positionRouter.connect(executor).executeOrCancelIncreasePosition(param, executor.address);
                expect(await gasUsed(tx)).toMatchSnapshot();
                const id = await increasePositionRequestId(param);
                await expect(tx).to.emit(positionRouter, "IncreasePositionExecuted").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });
    });
    describe("DecreasePosition", () => {
        describe("#createDecreasePosition", () => {
            it("first createDecreasePosition", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createDecreasePosition(market, 100n, 100n, PRICE_1, trader, {value: minExecutionFee}),
                    ),
                ).toMatchSnapshot();
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                };
                const id = await decreasePositionRequestId(param);
                expect(await positionRouter.blockNumbers(id)).is.gt(0n);
            });
            it("createDecreasePosition again", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                await positionRouter
                    .connect(trader)
                    .createDecreasePosition(market, 100n, 100n, PRICE_1, trader, {value: minExecutionFee});
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createDecreasePosition(market, 200n, 200n, PRICE_1, trader, {value: minExecutionFee}),
                    ),
                ).toMatchSnapshot();
                const param1 = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                };
                const param2 = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                };
                const id1 = await decreasePositionRequestId(param1);
                const id2 = await decreasePositionRequestId(param2);
                expect(await positionRouter.blockNumbers(id1)).is.gt(0n);
                expect(await positionRouter.blockNumbers(id2)).is.gt(0n);
            });
        });
        describe("#createDecreasePositionReceivePUSD", () => {
            it("first createDecreasePositionReceivePUSD", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(
                    ExecutionFeeType.DecreasePositionReceivePUSD,
                );
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createDecreasePositionReceivePUSD(market, 100n, 100n, PRICE_1, trader, {
                                value: minExecutionFee,
                            }),
                    ),
                ).toMatchSnapshot();
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: true,
                };
                const id = await decreasePositionRequestId(param);
                expect(await positionRouter.blockNumbers(id)).is.gt(0n);
            });
            it("createDecreasePositionReceivePUSD again", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(
                    ExecutionFeeType.DecreasePositionReceivePUSD,
                );
                await positionRouter
                    .connect(trader)
                    .createDecreasePositionReceivePUSD(market, 100n, 100n, PRICE_1, trader, {
                        value: minExecutionFee,
                    });
                expect(
                    await gasUsed(
                        positionRouter
                            .connect(trader)
                            .createDecreasePositionReceivePUSD(market, 200n, 200n, PRICE_1, trader, {
                                value: minExecutionFee,
                            }),
                    ),
                ).toMatchSnapshot();
                const param1 = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: true,
                };
                const param2 = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 200n,
                    sizeDelta: 200n,
                    acceptableIndexPrice: PRICE_1,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: true,
                };
                const id1 = await decreasePositionRequestId(param1);
                const id2 = await decreasePositionRequestId(param2);
                expect(await positionRouter.blockNumbers(id1)).is.gt(0n);
                expect(await positionRouter.blockNumbers(id2)).is.gt(0n);
            });
        });
        describe("#cancelDecreasePosition", () => {
            it("cancel when request not exists", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                };
                expect(await gasUsed(positionRouter.cancelDecreasePosition(param, trader.address))).toMatchSnapshot();
            });

            it("cancel when executor cancel", async () => {
                const {positionRouter, market, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                await positionRouter
                    .connect(trader)
                    .createDecreasePosition(market, 100n, 100n, PRICE_1, trader, {value: minExecutionFee});
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                };
                expect(
                    await gasUsed(positionRouter.connect(executor).cancelDecreasePosition(param, executor.address)),
                ).toMatchSnapshot();
                const id = await decreasePositionRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });

            it("cancel when request owner calls", async () => {
                const {positionRouter, market, trader} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                await positionRouter
                    .connect(trader)
                    .createDecreasePosition(market, 100n, 100n, PRICE_1, trader, {value: minExecutionFee});
                await mine(await positionRouter.minBlockDelayPublic());
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                };
                expect(
                    await gasUsed(positionRouter.connect(trader).cancelDecreasePosition(param, trader.address)),
                ).toMatchSnapshot();
                const id = await decreasePositionRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });
        describe("#executeDecreasePosition", () => {
            it("execute when request is not exists", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                };
                expect(await gasUsed(positionRouter.executeDecreasePosition(param, trader.address))).toMatchSnapshot();
            });

            it("execute when the market is weth", async () => {
                const {positionRouter, weth, marketManager, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                await positionRouter
                    .connect(trader)
                    .createDecreasePosition(weth, 100n, 100n, PRICE_1, trader, {value: minExecutionFee});
                // set a delay value to prevent expire
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await marketManager.setMinPrice(PRICE_1);
                await marketManager.setActualMarginDelta(80n);
                const param = {
                    account: trader.address,
                    market: weth.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                };
                expect(
                    await gasUsed(positionRouter.connect(executor).executeDecreasePosition(param, executor.address)),
                ).toMatchSnapshot();
                const id = await decreasePositionRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("should emit event and distribute funds when the market is not weth", async () => {
                const {positionRouter, market, marketManager, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                await positionRouter
                    .connect(trader)
                    .createDecreasePosition(market, 100n, 100n, PRICE_1, trader, {value: minExecutionFee});
                // set a delay value to prevent expire
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await marketManager.setMinPrice(PRICE_1);
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                };
                expect(
                    await gasUsed(positionRouter.connect(executor).executeDecreasePosition(param, executor.address)),
                ).toMatchSnapshot();
                const id = await decreasePositionRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("should emit event and distribute funds when receivePUSD is true", async () => {
                const {positionRouter, market, marketManager, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(
                    ExecutionFeeType.DecreasePositionReceivePUSD,
                );
                await positionRouter
                    .connect(trader)
                    .createDecreasePositionReceivePUSD(market, 100n, 100n, PRICE_1, trader, {value: minExecutionFee});
                // set a delay value to prevent expire
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await marketManager.setMinPrice(PRICE_1);
                await marketManager.setReceivePUSD(true);
                await marketManager.setPayAmount(100n);
                await marketManager.setActualMarginDelta(100n);
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: true,
                };
                expect(
                    await gasUsed(positionRouter.connect(executor).executeDecreasePosition(param, executor.address)),
                ).toMatchSnapshot();
                const id = await decreasePositionRequestId(param);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });
        describe("#executeOrCancelDecreasePosition", () => {
            it("cancel request if execution reverted", async () => {
                const {trader, executor, positionRouter, market} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                // _maxBlockDelay is 0, execution will revert immediately
                await positionRouter.updateDelayValues(0, 0, 0);

                // all requests should be cancelled because they reverted
                await positionRouter
                    .connect(trader)
                    .createDecreasePosition(market, 100n, 100n, PRICE_1, trader, {value: minExecutionFee});

                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                };
                const tx = positionRouter.connect(executor).executeOrCancelDecreasePosition(param, executor.address);
                expect(await gasUsed(tx)).toMatchSnapshot();
                const id = await decreasePositionRequestId(param);
                await expect(tx).to.emit(positionRouter, "DecreasePositionCancelled").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("execute request if execution passed", async () => {
                const {trader, executor, positionRouter, market, marketManager} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                await positionRouter
                    .connect(trader)
                    .createDecreasePosition(market, 100n, 100n, PRICE_1, trader, {value: minExecutionFee});
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                    receivePUSD: false,
                };
                await mine(await positionRouter.minBlockDelayExecutor());
                await marketManager.setMinPrice(PRICE_1);
                const tx = positionRouter.connect(executor).executeOrCancelDecreasePosition(param, executor.address);
                expect(await gasUsed(tx)).toMatchSnapshot();
                const id = await decreasePositionRequestId(param);
                await expect(tx).to.emit(positionRouter, "DecreasePositionExecuted").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });
    });
});

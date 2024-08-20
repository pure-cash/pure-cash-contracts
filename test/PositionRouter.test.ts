import {loadFixture, mine, time} from "@nomicfoundation/hardhat-network-helpers";
import {expect} from "chai";
import {ethers} from "hardhat";
import {ExecutionFeeType, PRICE_1} from "./shared/Constants";
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

describe("PositionRouter", () => {
    describe("#receive", () => {
        it("should revert if msg.sender is not WETH", async () => {
            const {owner, weth, positionRouter} = await loadFixture(deployFixture);
            await expect(owner.sendTransaction({to: await positionRouter.getAddress(), value: 1}))
                .to.be.revertedWithCustomError(positionRouter, "InvalidCaller")
                .withArgs(weth.target);
        });

        it("should pass", async () => {
            const {trader, executor, market, positionRouter, weth} = await loadFixture(deployFixture);
            const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
            await expect(
                positionRouter.connect(trader).createMintPUSD(market.target, true, 100n, 0n, trader.address, "0x", {
                    value: minExecutionFee,
                }),
            ).to.be.emit(positionRouter, "MintPUSDCreated");

            expect(await market.balanceOf(await positionRouter.getAddress())).to.be.eq(100n);

            await positionRouter.connect(executor).cancelMintPUSD(
                {
                    account: trader.address,
                    market: market.target,
                    exactIn: true,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                },
                trader.address,
            );

            expect(await weth.balanceOf(await positionRouter.getAddress())).to.be.eq(0n);
        });
    });

    describe("#updatePositionExecutor", async () => {
        it("should revert with 'Forbidden' if caller is not gov", async () => {
            const {other, positionRouter} = await loadFixture(deployFixture);
            await expect(
                positionRouter.connect(other).updatePositionExecutor(other.address, true),
            ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
        });

        it("should emit correct event and update param", async () => {
            const {positionRouter, other} = await loadFixture(deployFixture);

            await expect(positionRouter.updatePositionExecutor(other.address, true))
                .to.emit(positionRouter, "PositionExecutorUpdated")
                .withArgs(other.address, true);
            expect(await positionRouter.positionExecutors(other.address)).to.eq(true);

            await expect(positionRouter.updatePositionExecutor(other.address, false))
                .to.emit(positionRouter, "PositionExecutorUpdated")
                .withArgs(other.address, false);
            expect(await positionRouter.positionExecutors(other.address)).to.eq(false);
        });
    });

    describe("#updateDelayValues", async () => {
        it("should revert with 'Forbidden' if caller is not gov", async () => {
            const {other, positionRouter} = await loadFixture(deployFixture);
            await expect(positionRouter.connect(other).updateDelayValues(0n, 0n, 0n)).to.be.revertedWithCustomError(
                positionRouter,
                "Forbidden",
            );
        });

        it("should emit correct event and update param", async () => {
            const {positionRouter} = await loadFixture(deployFixture);
            await expect(positionRouter.updateDelayValues(10n, 20n, 30n))
                .to.emit(positionRouter, "DelayValuesUpdated")
                .withArgs(10n, 20n, 30n);
            expect(await positionRouter.minBlockDelayExecutor()).to.eq(10n);
            expect(await positionRouter.minBlockDelayPublic()).to.eq(20n);
            expect(await positionRouter.maxBlockDelay()).to.eq(30n);
        });
    });

    describe("#updateMinExecutionFee", async () => {
        it("should revert with 'Forbidden' if caller is not gov", async () => {
            const {other, positionRouter} = await loadFixture(deployFixture);
            await expect(
                positionRouter.connect(other).updateMinExecutionFee(ExecutionFeeType.IncreasePosition, 3000n),
            ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
        });

        it("should emit correct event and update params", async () => {
            const {positionRouter} = await loadFixture(deployFixture);
            const executionFeeTypes = await positionRouterExecutionFeeTypes();
            const minExecutionFees = await positionRouterMinExecutionFees();
            expect(executionFeeTypes.length).to.eq(minExecutionFees.length);
            for (let i = 0; i < executionFeeTypes.length; i++) {
                expect(await positionRouter.minExecutionFees(executionFeeTypes[i])).to.eq(minExecutionFees[i]);
                await positionRouter.updateMinExecutionFee(executionFeeTypes[i], minExecutionFees[i] + 1000n);
                expect(await positionRouter.minExecutionFees(executionFeeTypes[i])).to.eq(minExecutionFees[i] + 1000n);
            }
        });
    });

    describe("#updateExecutionGasLimit", async () => {
        it("should revert with 'Forbidden' if caller is not gov", async () => {
            const {other, positionRouter} = await loadFixture(deployFixture);
            await expect(positionRouter.connect(other).updateExecutionGasLimit(2000000n)).to.be.revertedWithCustomError(
                positionRouter,
                "Forbidden",
            );
        });

        it("should update param", async () => {
            const {positionRouter} = await loadFixture(deployFixture);

            await positionRouter.updateExecutionGasLimit(2000000n);
            expect(await positionRouter.executionGasLimit()).to.eq(2000000n);
        });
    });

    describe("MintPUSD", () => {
        describe("#createMintPUSD", () => {
            it("should revert if msg.value is less than minExecutionFee", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                const value = minExecutionFee - 1n;
                await expect(
                    positionRouter
                        .connect(trader)
                        .createMintPUSD(market.target, false, 100n, 0n, trader.address, "0x", {value}),
                )
                    .to.be.revertedWithCustomError(positionRouter, "InsufficientExecutionFee")
                    .withArgs(value, minExecutionFee);
            });
            it("should revert if the same request exists", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
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
                await expect(
                    positionRouter
                        .connect(trader)
                        .createMintPUSD(market.target, false, 100n, 0n, trader.address, "0x", {value: minExecutionFee}),
                )
                    .to.be.revertedWithCustomError(positionRouter, "ConflictRequests")
                    .withArgs(await mintPUSDRequestId(param));
            });
            it("should pass if the same request is already cancelled", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
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
                await mine(await positionRouter.minBlockDelayPublic());
                await positionRouter.connect(trader).cancelMintPUSD(param, trader.address);
                await expect(
                    positionRouter
                        .connect(trader)
                        .createMintPUSD(market.target, false, 100n, 0n, trader.address, "0x", {value: minExecutionFee}),
                ).not.to.be.reverted;
            });
            it("should pass if the same request is already executed", async function () {
                const {trader, executor, market, positionRouter} = await loadFixture(deployFixture);
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
                await positionRouter.connect(executor).executeMintPUSD(param, executor.address);
                await expect(
                    positionRouter
                        .connect(trader)
                        .createMintPUSD(market.target, false, 100n, 0n, trader.address, "0x", {value: minExecutionFee}),
                ).not.to.be.reverted;
            });
            it("should revert if allowance is insufficient and permitData is empty", async function () {
                const {trader, market, marketManager, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                await resetAllowance(market, trader, await marketManager.getAddress());
                await expect(
                    positionRouter
                        .connect(trader)
                        .createMintPUSD(market.target, false, 100n, 0n, trader.address, "0x", {value: minExecutionFee}),
                )
                    .to.be.revertedWithCustomError(market, "ERC20InsufficientAllowance")
                    .withArgs(marketManager.target, 0, 100n);
            });
            it("should revert if allowance is insufficient and permitData is invalid", async function () {
                const {trader, market, marketManager, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                await resetAllowance(market, trader, await marketManager.getAddress());
                await expect(
                    positionRouter
                        .connect(trader)
                        .createMintPUSD(market.target, false, 100n, 0n, trader.address, "0xabcdef", {
                            value: minExecutionFee,
                        }),
                ).to.be.reverted;
            });
            it("should revert if allowance is insufficient and permitData is other's", async function () {
                const {trader, other, market, marketManager, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                await resetAllowance(market, trader, await marketManager.getAddress());
                const permitData = await genERC20PermitData(market, other, await marketManager.getAddress(), 100n);
                await expect(
                    positionRouter
                        .connect(trader)
                        .createMintPUSD(market.target, false, 100n, 0n, trader.address, permitData, {
                            value: minExecutionFee,
                        }),
                )
                    .to.be.revertedWithCustomError(market, "ERC20InsufficientAllowance")
                    .withArgs(marketManager.target, 0, 100n);
            });
            it("should pass if allowance is insufficient and permitData is valid", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                await resetAllowance(market, trader, await positionRouter.getAddress());
                const permitData = await genERC20PermitData(market, trader, await positionRouter.getAddress(), 100n);
                const tx = await positionRouter
                    .connect(trader)
                    .createMintPUSD(market.target, false, 100n, 0n, trader.address, permitData, {
                        value: minExecutionFee,
                    });
                await expect(tx).to.changeEtherBalances([trader, positionRouter], [-minExecutionFee, minExecutionFee]);
                await expect(tx).to.changeTokenBalances(market, [trader, positionRouter], [-100n, 100n]);
                const param = {
                    account: trader.address,
                    market: market.target,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                await expect(tx)
                    .to.emit(positionRouter, "MintPUSDCreated")
                    .withArgs(
                        trader.address,
                        market,
                        false,
                        100n,
                        0n,
                        trader.address,
                        minExecutionFee,
                        await mintPUSDRequestId(param),
                    );
            });
            it("should pass if allowance is sufficient and permitData is empty", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                const tx = await positionRouter
                    .connect(trader)
                    .createMintPUSD(market.target, false, 100n, 0n, trader.address, "0x", {value: minExecutionFee});
                await expect(tx).to.changeEtherBalances([trader, positionRouter], [-minExecutionFee, minExecutionFee]);
                await expect(tx).to.changeTokenBalances(market, [trader, positionRouter], [-100n, 100n]);
                const param = {
                    account: trader.address,
                    market: market.target,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                await expect(tx)
                    .to.emit(positionRouter, "MintPUSDCreated")
                    .withArgs(
                        trader.address,
                        market,
                        false,
                        100n,
                        0n,
                        trader.address,
                        minExecutionFee,
                        await mintPUSDRequestId(param),
                    );
            });
        });
        describe("#createMintPUSDETH", () => {
            it("should revert if msg.value is less than executionFee", async function () {
                const {trader, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSDETH);
                const value = minExecutionFee - 1n;
                await expect(
                    positionRouter
                        .connect(trader)
                        .createMintPUSDETH(false, 0n, trader.address, minExecutionFee, {value}),
                )
                    .to.be.revertedWithCustomError(positionRouter, "InsufficientExecutionFee")
                    .withArgs(value, minExecutionFee);
            });
            it("should revert if executionFee is less than minExecutionFee", async function () {
                const {trader, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSDETH);
                const value = minExecutionFee - 1n;
                await expect(
                    positionRouter
                        .connect(trader)
                        .createMintPUSDETH(false, 0n, trader.address, minExecutionFee, {value}),
                )
                    .to.be.revertedWithCustomError(positionRouter, "InsufficientExecutionFee")
                    .withArgs(value, minExecutionFee);
            });
            it("should revert if the same request exists", async function () {
                const {trader, weth, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSDETH);
                await positionRouter
                    .connect(trader)
                    .createMintPUSDETH(false, 0n, trader.address, minExecutionFee, {value: minExecutionFee + 100n});
                const param = {
                    account: trader.address,
                    market: weth.target,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                await expect(
                    positionRouter
                        .connect(trader)
                        .createMintPUSDETH(false, 0n, trader.address, minExecutionFee, {value: minExecutionFee + 100n}),
                )
                    .to.be.revertedWithCustomError(positionRouter, "ConflictRequests")
                    .withArgs(await mintPUSDRequestId(param));
            });
            it("should pass if the same request is already cancelled", async function () {
                const {trader, weth, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSDETH);
                await positionRouter
                    .connect(trader)
                    .createMintPUSDETH(false, 0n, trader.address, minExecutionFee, {value: minExecutionFee + 100n});
                const param = {
                    account: trader.address,
                    market: weth.target,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                await mine(await positionRouter.minBlockDelayPublic());
                await positionRouter.connect(trader).cancelMintPUSD(param, trader.address);
                await expect(
                    positionRouter
                        .connect(trader)
                        .createMintPUSDETH(false, 0n, trader.address, minExecutionFee, {value: minExecutionFee + 100n}),
                ).not.to.be.reverted;
            });
            it("should pass if the same request is already executed", async function () {
                const {trader, executor, weth, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSDETH);
                await positionRouter
                    .connect(trader)
                    .createMintPUSDETH(false, 0n, trader.address, minExecutionFee, {value: minExecutionFee + 100n});
                await mine(await positionRouter.minBlockDelayExecutor());
                const param = {
                    account: trader.address,
                    market: weth.target,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                await mine(await positionRouter.minBlockDelayExecutor());
                await positionRouter.connect(executor).executeMintPUSD(param, executor.address);
                await expect(
                    positionRouter
                        .connect(trader)
                        .createMintPUSDETH(false, 0n, trader.address, minExecutionFee, {value: minExecutionFee + 100n}),
                ).not.to.be.reverted;
            });
            it("should pass", async function () {
                const {trader, weth, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSDETH);
                const amount = 100n;
                const value = minExecutionFee + amount;
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
                const tx = await positionRouter
                    .connect(trader)
                    .createMintPUSDETH(false, 0n, trader.address, minExecutionFee, {value});
                await expect(tx).to.changeEtherBalances([trader, positionRouter], [-value, minExecutionFee]);
                await expect(tx).to.changeTokenBalance(weth, positionRouter, amount);
                await expect(tx)
                    .to.emit(positionRouter, "MintPUSDCreated")
                    .withArgs(trader.address, weth.target, false, amount, 0n, trader.address, minExecutionFee, id);
                expect(await positionRouter.blockNumbers(id)).is.gt(0n);
            });
        });
        describe("#cancelMintPUSD", () => {
            describe("shouldCancel/shouldExecuteOrCancel", function () {
                it("should revert if caller is not request owner nor executor", async () => {
                    const {positionRouter, market, trader, other} = await loadFixture(deployFixture);
                    const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                    // create a new request
                    await positionRouter
                        .connect(trader)
                        .createMintPUSD(market.target, false, 100n, 0n, trader.address, "0x", {value: minExecutionFee});

                    await expect(
                        positionRouter.connect(other).cancelMintPUSD(
                            {
                                account: trader.address,
                                market: market.target,
                                exactIn: false,
                                acceptableMaxPayAmount: 100n,
                                acceptableMinReceiveAmount: 0n,
                                receiver: trader.address,
                                executionFee: minExecutionFee,
                            },
                            other.address,
                        ),
                    ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
                });

                it("should wait at least minBlockDelayExecutor until executors can cancel", async () => {
                    const {positionRouter, market, trader, executor} = await loadFixture(deployFixture);
                    const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                    // executor has to wait 10 blocks
                    await positionRouter.updateDelayValues(10n, 3000n, 6000n);
                    // create a new request
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
                    // should fail to cancel
                    await positionRouter.connect(executor).cancelMintPUSD(param, executor.address);
                    expect(await positionRouter.blockNumbers(id)).is.gt(0n);

                    // mine 10 blocks
                    await mine(10);

                    // should be cancelled
                    await positionRouter.connect(executor).cancelMintPUSD(param, executor.address);
                    expect(await positionRouter.blockNumbers(id)).eq(0n);
                });

                it("should wait at least minBlockDelayPublic until public can cancel", async () => {
                    const {positionRouter, market, trader} = await loadFixture(deployFixture);
                    const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                    await expect(positionRouter.updateDelayValues(10n, 100n, 600n)).not.to.be.reverted;
                    // create a new request
                    await positionRouter
                        .connect(trader)
                        .createMintPUSD(market.target, false, 100n, 0n, trader.address, "0x", {value: minExecutionFee});
                    const earliest = (await time.latestBlock()) + 100;
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
                    await expect(positionRouter.connect(trader).cancelMintPUSD(param, trader.address))
                        .to.be.revertedWithCustomError(positionRouter, "TooEarly")
                        .withArgs(earliest);

                    await mine(100n);

                    expect(await positionRouter.blockNumbers(id)).is.gt(0n);
                    await positionRouter.connect(trader).cancelMintPUSD(param, trader.address);
                    expect(await positionRouter.blockNumbers(id)).eq(0n);
                });
            });

            it("should pass if request not exist", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                await positionRouter.cancelMintPUSD(
                    {
                        account: trader.address,
                        market: market.target,
                        exactIn: false,
                        acceptableMaxPayAmount: 100n,
                        acceptableMinReceiveAmount: 0n,
                        receiver: trader.address,
                        executionFee: minExecutionFee,
                    },
                    trader.address,
                );
            });

            it("should revert with 'Forbidden' if caller is not request owner", async () => {
                const {positionRouter, trader, other, market} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                await positionRouter
                    .connect(trader)
                    .createMintPUSD(market.target, false, 100n, 0n, trader.address, "0x", {value: minExecutionFee});
                await expect(
                    positionRouter.connect(other).cancelMintPUSD(
                        {
                            account: trader.address,
                            market: market.target,
                            exactIn: false,
                            acceptableMaxPayAmount: 100n,
                            acceptableMinReceiveAmount: 0n,
                            receiver: trader.address,
                            executionFee: minExecutionFee,
                        },
                        other.address,
                    ),
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
            });

            it("should be ok if executor cancel and market is not weth", async () => {
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
                const tx = positionRouter.connect(executor).cancelMintPUSD(param, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter, executor],
                    [-minExecutionFee, minExecutionFee],
                );
                const id = await mintPUSDRequestId(param);
                await expect(tx).to.changeTokenBalances(market, [positionRouter, trader], [-100n, 100n]);
                await expect(tx).to.emit(positionRouter, "MintPUSDCancelled").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("should be ok if executor cancel and market is weth", async () => {
                const {positionRouter, weth, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSDETH);
                await positionRouter.connect(trader).createMintPUSDETH(true, 0n, trader.address, minExecutionFee, {
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
                const tx = positionRouter.connect(executor).cancelMintPUSD(param, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter, executor, trader],
                    [-minExecutionFee, minExecutionFee, 100n],
                );
                await expect(tx).to.changeTokenBalance(weth, positionRouter, -100n);
                const id = await mintPUSDRequestId(param);
                await expect(tx).to.emit(positionRouter, "MintPUSDCancelled").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });

            it("should be ok if request owner calls", async () => {
                const {positionRouter, market, trader} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                await positionRouter
                    .connect(trader)
                    .createMintPUSD(market.target, false, 100n, 0n, trader.address, "0x", {value: minExecutionFee});
                await mine(await positionRouter.minBlockDelayPublic());
                const param = {
                    account: trader.address,
                    market: market.target,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                const tx = positionRouter.connect(trader).cancelMintPUSD(param, trader.address);
                const id = await mintPUSDRequestId(param);
                await expect(tx).to.changeEtherBalances([positionRouter, trader], [-minExecutionFee, minExecutionFee]);
                await expect(tx).to.changeTokenBalances(market, [positionRouter, trader], [-100n, 100n]);
                await expect(tx).to.emit(positionRouter, "MintPUSDCancelled").withArgs(id, trader.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });
        describe("#executeMintPUSD", () => {
            it("should pass if request is not exist", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                await positionRouter.executeMintPUSD(
                    {
                        account: trader.address,
                        market: market.target,
                        exactIn: false,
                        acceptableMaxPayAmount: 100n,
                        acceptableMinReceiveAmount: 0n,
                        receiver: trader.address,
                        executionFee: minExecutionFee,
                    },
                    trader.address,
                );
            });

            it("should revert with 'Forbidden' if caller is not executor nor request owner", async () => {
                const {trader, other, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                await positionRouter
                    .connect(trader)
                    .createMintPUSD(market.target, false, 100n, 0n, trader.address, "0x", {value: minExecutionFee});
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await expect(
                    positionRouter.connect(other).executeMintPUSD(
                        {
                            account: trader.address,
                            market: market.target,
                            exactIn: false,
                            acceptableMaxPayAmount: 100n,
                            acceptableMinReceiveAmount: 0n,
                            receiver: trader.address,
                            executionFee: minExecutionFee,
                        },
                        other.address,
                    ),
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
            });

            it("should revert with 'Expired' if maxBlockDelay passed", async () => {
                const {positionRouter, market, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await positionRouter
                    .connect(trader)
                    .createMintPUSD(market.target, false, 100n, 0n, trader.address, "0x", {value: minExecutionFee});
                const expiredAt = (await time.latestBlock()) + 600;
                await mine(600n);
                await expect(
                    positionRouter.connect(executor).executeMintPUSD(
                        {
                            account: trader.address,
                            market: market.target,
                            exactIn: false,
                            acceptableMaxPayAmount: 100n,
                            acceptableMinReceiveAmount: 0n,
                            receiver: trader.address,
                            executionFee: minExecutionFee,
                        },
                        executor.address,
                    ),
                )
                    .to.be.revertedWithCustomError(positionRouter, "Expired")
                    .withArgs(expiredAt);
            });

            it("should revert with 'TooEarly' if someone who are not the executor executes his own request and pass if sufficient time elapsed", async () => {
                const {positionRouter, market, trader} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                await positionRouter
                    .connect(trader)
                    .createMintPUSD(market.target, false, 100n, 0n, trader.address, "0x", {value: minExecutionFee});
                const current = BigInt(await time.latestBlock());
                const minBlockDelayPublic = await positionRouter.minBlockDelayPublic();
                await expect(
                    positionRouter.connect(trader).executeMintPUSD(
                        {
                            account: trader.address,
                            market: market.target,
                            exactIn: false,
                            acceptableMaxPayAmount: 100n,
                            acceptableMinReceiveAmount: 0n,
                            receiver: trader.address,
                            executionFee: minExecutionFee,
                        },
                        trader.address,
                    ),
                )
                    .to.be.revertedWithCustomError(positionRouter, "TooEarly")
                    .withArgs(current + minBlockDelayPublic);
                await mine(minBlockDelayPublic);
                await expect(
                    positionRouter.connect(trader).executeMintPUSD(
                        {
                            account: trader.address,
                            market: market.target,
                            exactIn: false,
                            acceptableMaxPayAmount: 100n,
                            acceptableMinReceiveAmount: 0n,
                            receiver: trader.address,
                            executionFee: minExecutionFee,
                        },
                        trader.address,
                    ),
                ).not.to.be.reverted;
            });

            it("should revert with 'TooLittleReceived' if receiveAmount is less than acceptableMinReceiveAmount", async () => {
                const {positionRouter, marketManager, market, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                await positionRouter
                    .connect(trader)
                    .createMintPUSD(market.target, false, 100n, 200n, trader.address, "0x", {value: minExecutionFee});
                // set a delay value to prevent expire
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await marketManager.setReceiveAmount(100n);
                const tx = positionRouter.connect(executor).executeMintPUSD(
                    {
                        account: trader.address,
                        market: market.target,
                        exactIn: false,
                        acceptableMaxPayAmount: 100n,
                        acceptableMinReceiveAmount: 200n,
                        receiver: trader.address,
                        executionFee: minExecutionFee,
                    },
                    executor.address,
                );
                await expect(tx)
                    .to.be.revertedWithCustomError(positionRouter, "TooLittleReceived")
                    .withArgs(200n, 100n);
            });

            it("should revert with 'TooMuchPaid' if payAmount is more than acceptableMaxPayAmount", async () => {
                const {positionRouter, marketManager, market, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                await positionRouter
                    .connect(trader)
                    .createMintPUSD(market.target, false, 100n, 0n, trader.address, "0x", {value: minExecutionFee});
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await marketManager.setPayAmount(200n);
                const tx = positionRouter.connect(executor).executeMintPUSD(
                    {
                        account: trader.address,
                        market: market.target,
                        exactIn: false,
                        acceptableMaxPayAmount: 100n,
                        acceptableMinReceiveAmount: 0n,
                        receiver: trader.address,
                        executionFee: minExecutionFee,
                    },
                    executor.address,
                );
                await expect(tx).to.be.revertedWithCustomError(positionRouter, "TooMuchPaid").withArgs(200n, 100n);
            });

            it("should emit event and distribute funds when the exactIn is true and market is weth", async () => {
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
                const tx = positionRouter.connect(executor).executeMintPUSD(param, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter, executor, trader],
                    [-minExecutionFee, minExecutionFee, 20n],
                );
                await expect(tx).to.changeTokenBalances(weth, [positionRouter, marketManager], [-100n, 80n]);
                const id = await mintPUSDRequestId(param);
                await expect(tx).to.emit(positionRouter, "MintPUSDExecuted").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("should emit event and distribute funds when the exactIn is true and market is not weth", async () => {
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
                const tx = positionRouter.connect(executor).executeMintPUSD(param, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter, executor],
                    [-minExecutionFee, minExecutionFee],
                );
                await expect(tx).to.changeTokenBalances(
                    market,
                    [positionRouter, marketManager, trader],
                    [-100n, 80n, 20n],
                );
                const id = await mintPUSDRequestId(param);
                await expect(tx).to.emit(positionRouter, "MintPUSDExecuted").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("should emit event and distribute funds when the exactIn is false and market is weth", async () => {
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
                const tx = positionRouter.connect(executor).executeMintPUSD(param, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter, executor, trader],
                    [-minExecutionFee, minExecutionFee, 20n],
                );
                await expect(tx).to.changeTokenBalances(weth, [positionRouter, marketManager], [-100n, 80n]);
                const id = await mintPUSDRequestId(param);
                await expect(tx).to.emit(positionRouter, "MintPUSDExecuted").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("should emit event and distribute funds when the exactIn is false and market is not weth", async () => {
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
                const tx = positionRouter.connect(executor).executeMintPUSD(param, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter, executor],
                    [-minExecutionFee, minExecutionFee],
                );
                const id = await mintPUSDRequestId(param);
                await expect(tx).to.emit(positionRouter, "MintPUSDExecuted").withArgs(id, executor.address);
                // delete request
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });
        describe("#executeOrCancelMintPUSD", () => {
            it("should revert with 'Forbidden' if caller is not executor", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.MintPUSD);
                await expect(
                    positionRouter.executeOrCancelMintPUSD(
                        {
                            account: trader.address,
                            market: market.target,
                            exactIn: false,
                            acceptableMaxPayAmount: 100n,
                            acceptableMinReceiveAmount: 0n,
                            receiver: trader.address,
                            executionFee: minExecutionFee,
                        },
                        trader.address,
                    ),
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
            });
            it("should cancel request if execution reverted", async () => {
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
                const tx = positionRouter.connect(executor).executeOrCancelMintPUSD(param, executor.address);
                const id = await mintPUSDRequestId(param);
                const reason = ethers.id("Expired(uint256)").substring(0, 10);
                await expect(tx)
                    .to.emit(positionRouter, "ExecuteFailed")
                    .withArgs(4, id, reason)
                    .to.emit(positionRouter, "MintPUSDCancelled")
                    .withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("should execute request if execution passed", async () => {
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
                const tx = positionRouter.connect(executor).executeOrCancelMintPUSD(param, executor.address);
                const id = await mintPUSDRequestId(param);
                await expect(tx).to.emit(positionRouter, "MintPUSDExecuted").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });
    });

    describe("BurnPUSD", () => {
        describe("#createBurnPUSD", () => {
            it("should transfer correct execution fee to position router", async () => {
                const {positionRouter, market, trader} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                const value = minExecutionFee - 1n;
                // insufficient execution fee
                await expect(
                    positionRouter.connect(trader).createBurnPUSD(market, false, 100n, 0n, trader, "0x", {value}),
                )
                    .to.be.revertedWithCustomError(positionRouter, "InsufficientExecutionFee")
                    .withArgs(value, minExecutionFee);
            });
            it("should revert if the same request exists", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
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
                await expect(
                    positionRouter
                        .connect(trader)
                        .createBurnPUSD(market, false, 100n, 0n, trader, "0x", {value: minExecutionFee}),
                )
                    .to.be.revertedWithCustomError(positionRouter, "ConflictRequests")
                    .withArgs(await burnPUSDRequestId(param));
            });
            it("should pass if the same request is already cancelled", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
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
                await mine(await positionRouter.minBlockDelayPublic());
                await positionRouter.connect(trader).cancelBurnPUSD(param, trader.address);
                await expect(
                    positionRouter
                        .connect(trader)
                        .createBurnPUSD(market, false, 100n, 0n, trader, "0x", {value: minExecutionFee}),
                ).not.to.be.reverted;
            });
            it("should pass if the same request is already executed", async () => {
                const {trader, executor, market, positionRouter} = await loadFixture(deployFixture);
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
                await positionRouter.connect(executor).executeBurnPUSD(param, executor.address);
                await expect(
                    positionRouter
                        .connect(trader)
                        .createBurnPUSD(market, false, 100n, 0n, trader, "0x", {value: minExecutionFee}),
                ).not.to.be.reverted;
            });
            it("should revert if allowance is insufficient and permitData is empty", async () => {
                const {trader, market, usd, marketManager, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                await resetAllowance(usd, trader, await marketManager.getAddress());
                await expect(
                    positionRouter
                        .connect(trader)
                        .createBurnPUSD(market, false, 100n, 0n, trader, "0x", {value: minExecutionFee}),
                )
                    .to.be.revertedWithCustomError(market, "ERC20InsufficientAllowance")
                    .withArgs(marketManager.target, 0, 100n);
            });
            it("should revert if allowance is insufficient and permitData is invalid", async () => {
                const {trader, market, usd, marketManager, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                await resetAllowance(usd, trader, await marketManager.getAddress());
                await expect(
                    positionRouter
                        .connect(trader)
                        .createBurnPUSD(market, false, 100n, 0n, trader, "0xabcdef", {value: minExecutionFee}),
                ).to.be.reverted;
            });
            it("should revert if allowance is insufficient and permitData is other's", async () => {
                const {trader, other, market, usd, marketManager, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                await resetAllowance(usd, trader, await marketManager.getAddress());
                const permitData = await genERC20PermitData(usd, other, await marketManager.getAddress(), 100n);
                await expect(
                    positionRouter
                        .connect(trader)
                        .createBurnPUSD(market, false, 100n, 0n, trader, permitData, {value: minExecutionFee}),
                )
                    .to.be.revertedWithCustomError(market, "ERC20InsufficientAllowance")
                    .withArgs(marketManager.target, 0, 100n);
            });
            it("should pass if allowance is insufficient and permitData is valid", async () => {
                const {positionRouter, market, usd, trader} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                await resetAllowance(usd, trader, await positionRouter.getAddress());
                const permitData = await genERC20PermitData(usd, trader, await positionRouter.getAddress(), 100n);
                const tx = positionRouter
                    .connect(trader)
                    .createBurnPUSD(market, false, 100n, 0n, trader, permitData, {value: minExecutionFee});
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
                await expect(tx)
                    .to.emit(positionRouter, "BurnPUSDCreated")
                    .withArgs(trader.address, market, false, 100n, 0n, trader.address, minExecutionFee, id);
                await expect(tx).to.changeEtherBalances([trader, positionRouter], [-minExecutionFee, minExecutionFee]);
                await expect(tx).to.changeTokenBalances(usd, [trader, positionRouter], [-100n, 100n]);
                expect(await positionRouter.blockNumbers(id)).is.gt(0n);
            });
            it("should pass if allowance is sufficient and permitData is empty", async () => {
                const {positionRouter, market, usd, trader} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                const tx = positionRouter
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
                const id = await burnPUSDRequestId(param);
                await expect(tx)
                    .to.emit(positionRouter, "BurnPUSDCreated")
                    .withArgs(trader.address, market, false, 100n, 0n, trader.address, minExecutionFee, id);
                await expect(tx).to.changeEtherBalances([trader, positionRouter], [-minExecutionFee, minExecutionFee]);
                await expect(tx).to.changeTokenBalances(usd, [trader, positionRouter], [-100n, 100n]);
                expect(await positionRouter.blockNumbers(id)).is.gt(0n);
            });
        });

        describe("#cancelBurnPUSD", () => {
            it("should pass if request not exist", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                await positionRouter.cancelBurnPUSD(
                    {
                        market: market.target,
                        account: trader.address,
                        exactIn: false,
                        acceptableMaxPayAmount: 100n,
                        acceptableMinReceiveAmount: 0n,
                        receiver: trader.address,
                        executionFee: minExecutionFee,
                    },
                    trader.address,
                );
            });

            it("should revert with 'Forbidden' if caller is not executor nor request owner", async () => {
                const {positionRouter, market, trader, other} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                await positionRouter
                    .connect(trader)
                    .createBurnPUSD(market, false, 100n, 0n, trader, "0x", {value: minExecutionFee});
                await mine(await positionRouter.minBlockDelayPublic());
                const param = {
                    market: market.target,
                    account: trader.address,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                await expect(
                    positionRouter.connect(other).cancelBurnPUSD(param, other.address),
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
                await positionRouter.connect(trader).cancelBurnPUSD(param, trader.address);
            });

            it("should emit event and refund", async () => {
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
                const tx = positionRouter.connect(executor).cancelBurnPUSD(param, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter, executor],
                    [-minExecutionFee, minExecutionFee],
                );
                await expect(tx).to.changeTokenBalances(usd, [positionRouter, trader], [-100n, 100n]);
                const id = await burnPUSDRequestId(param);
                await expect(tx).to.emit(positionRouter, "BurnPUSDCancelled").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });

        describe("#executeBurnPUSD", () => {
            it("should pass if request not exist", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                await positionRouter.executeBurnPUSD(
                    {
                        market: market.target,
                        account: trader.address,
                        exactIn: false,
                        acceptableMaxPayAmount: 100n,
                        acceptableMinReceiveAmount: 0n,
                        receiver: trader.address,
                        executionFee: minExecutionFee,
                    },
                    trader.address,
                );
            });

            it("should revert with 'Forbidden' if caller is not executor nor request owner", async () => {
                const {positionRouter, market, trader, other} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                await positionRouter
                    .connect(trader)
                    .createBurnPUSD(market, false, 100n, 0n, trader, "0x", {value: minExecutionFee});
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await expect(
                    positionRouter.connect(other).executeBurnPUSD(
                        {
                            market: market.target,
                            account: trader.address,
                            exactIn: false,
                            acceptableMaxPayAmount: 100n,
                            acceptableMinReceiveAmount: 0n,
                            receiver: trader.address,
                            executionFee: minExecutionFee,
                        },
                        other.address,
                    ),
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
            });

            it("should revert with 'Expired' if maxBlockDelay passed", async () => {
                const {positionRouter, market, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await positionRouter
                    .connect(trader)
                    .createBurnPUSD(market, false, 100n, 0n, trader, "0x", {value: minExecutionFee});
                const expiredAt = (await time.latestBlock()) + 600;
                await mine(600n);
                await expect(
                    positionRouter.connect(executor).executeBurnPUSD(
                        {
                            market: market.target,
                            account: trader.address,
                            exactIn: false,
                            acceptableMaxPayAmount: 100n,
                            acceptableMinReceiveAmount: 0n,
                            receiver: trader.address,
                            executionFee: minExecutionFee,
                        },
                        executor.address,
                    ),
                )
                    .to.be.revertedWithCustomError(positionRouter, "Expired")
                    .withArgs(expiredAt);
            });

            it("should revert with 'TooEarly' if someone who are not the executor executes his own request and pass if sufficient time elapsed", async () => {
                const {positionRouter, market, trader} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                await positionRouter
                    .connect(trader)
                    .createBurnPUSD(market, false, 100n, 0n, trader, "0x", {value: minExecutionFee});
                const current = BigInt(await time.latestBlock());
                const minBlockDelayPublic = await positionRouter.minBlockDelayPublic();
                const param = {
                    market: market.target,
                    account: trader.address,
                    exactIn: false,
                    acceptableMaxPayAmount: 100n,
                    acceptableMinReceiveAmount: 0n,
                    receiver: trader.address,
                    executionFee: minExecutionFee,
                };
                await expect(positionRouter.connect(trader).executeBurnPUSD(param, trader.address))
                    .to.be.revertedWithCustomError(positionRouter, "TooEarly")
                    .withArgs(current + minBlockDelayPublic);
                await mine(minBlockDelayPublic);
                await expect(positionRouter.connect(trader).executeBurnPUSD(param, trader.address)).not.to.be.reverted;
            });

            it("should revert with 'TooLittleReceived' if liquidity is less than acceptableMinLiquidity", async () => {
                const {positionRouter, marketManager, market, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                await positionRouter
                    .connect(trader)
                    .createBurnPUSD(market, false, 100n, 200n, trader, "0x", {value: minExecutionFee});
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await marketManager.setReceiveAmount(100n);
                const tx = positionRouter.connect(executor).executeBurnPUSD(
                    {
                        market: market.target,
                        account: trader.address,
                        exactIn: false,
                        acceptableMaxPayAmount: 100n,
                        acceptableMinReceiveAmount: 200n,
                        receiver: trader.address,
                        executionFee: minExecutionFee,
                    },
                    executor.address,
                );
                await expect(tx)
                    .to.be.revertedWithCustomError(positionRouter, "TooLittleReceived")
                    .withArgs(200n, 100n);
            });
            it("should revert with 'TooMuchPaid' if payAmount is more than acceptableMaxPayAmount", async () => {
                const {positionRouter, marketManager, market, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                await positionRouter
                    .connect(trader)
                    .createBurnPUSD(market, false, 100n, 200n, trader, "0x", {value: minExecutionFee});
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await marketManager.setPayAmount(200n);
                const tx = positionRouter.connect(executor).executeBurnPUSD(
                    {
                        market: market.target,
                        account: trader.address,
                        exactIn: false,
                        acceptableMaxPayAmount: 100n,
                        acceptableMinReceiveAmount: 200n,
                        receiver: trader.address,
                        executionFee: minExecutionFee,
                    },
                    executor.address,
                );
                await expect(tx).to.be.revertedWithCustomError(positionRouter, "TooMuchPaid").withArgs(200n, 100n);
            });

            it("should emit event and distribute funds when exactIn is true and the market is weth", async () => {
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
                const tx = positionRouter.connect(executor).executeBurnPUSD(param, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter, executor, trader],
                    [-minExecutionFee, minExecutionFee, 100n],
                );
                await expect(tx).to.changeTokenBalances(
                    usd,
                    [positionRouter, marketManager, trader],
                    [-100n, 80n, 20n],
                );
                const id = await burnPUSDRequestId(param);
                await expect(tx).to.emit(positionRouter, "BurnPUSDExecuted").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("should emit event and distribute funds when exactIn is true and the market is not weth", async () => {
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
                const tx = positionRouter.connect(executor).executeBurnPUSD(param, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter, executor],
                    [-minExecutionFee, minExecutionFee],
                );
                await expect(tx).to.changeTokenBalances(
                    usd,
                    [positionRouter, marketManager, trader],
                    [-100n, 80n, 20n],
                );
                const id = await burnPUSDRequestId(param);
                await expect(tx).to.emit(positionRouter, "BurnPUSDExecuted").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("should emit event and distribute funds when exactIn is false and the market is weth", async () => {
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
                const tx = positionRouter.connect(executor).executeBurnPUSD(param, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter, executor, trader],
                    [-minExecutionFee, minExecutionFee, 100n],
                );
                await expect(tx).to.changeTokenBalances(
                    usd,
                    [positionRouter, marketManager, trader],
                    [-100n, 80n, 20n],
                );
                const id = await burnPUSDRequestId(param);
                await expect(tx).to.emit(positionRouter, "BurnPUSDExecuted").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("should emit event and distribute funds when exactIn is false and market is not weth", async () => {
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
                const tx = positionRouter.connect(executor).executeBurnPUSD(param, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter, executor],
                    [-minExecutionFee, minExecutionFee],
                );
                await expect(tx).to.changeTokenBalances(
                    usd,
                    [positionRouter, marketManager, trader],
                    [-100n, 80n, 20n],
                );
                const id = await burnPUSDRequestId(param);
                await expect(tx).to.emit(positionRouter, "BurnPUSDExecuted").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });

        describe("#executeOrCancelBurnPUSD", () => {
            it("should revert with 'Forbidden' if caller is not executor", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.BurnPUSD);
                await expect(
                    positionRouter.executeOrCancelBurnPUSD(
                        {
                            market: market.target,
                            account: trader.address,
                            exactIn: false,
                            acceptableMaxPayAmount: 100n,
                            acceptableMinReceiveAmount: 0n,
                            receiver: trader.address,
                            executionFee: minExecutionFee,
                        },
                        trader.address,
                    ),
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
            });
            it("should cancel request if execution reverted", async () => {
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
                const id = await burnPUSDRequestId(param);
                const reason = ethers.id("Expired(uint256)").substring(0, 10);
                await expect(tx)
                    .to.emit(positionRouter, "ExecuteFailed")
                    .withArgs(5, id, reason)
                    .to.emit(positionRouter, "BurnPUSDCancelled")
                    .withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("should execute request if execution passed", async () => {
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
                const id = await burnPUSDRequestId(param);
                await expect(tx).to.emit(positionRouter, "BurnPUSDExecuted").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });
    });

    describe("IncreasePosition", () => {
        describe("#createIncreasePosition", () => {
            it("should revert if msg.value is less than minExecutionFee", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                const value = minExecutionFee - 1n;
                await expect(
                    positionRouter.connect(trader).createIncreasePosition(market, 100n, 100n, PRICE_1, "0x", {value}),
                )
                    .to.be.revertedWithCustomError(positionRouter, "InsufficientExecutionFee")
                    .withArgs(value, minExecutionFee);
            });
            it("should revert if the same request exists", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
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
                await expect(
                    positionRouter
                        .connect(trader)
                        .createIncreasePosition(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee}),
                )
                    .to.be.revertedWithCustomError(positionRouter, "ConflictRequests")
                    .withArgs(await increasePositionRequestId(param));
            });
            it("should pass if the same request is already cancelled", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
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
                await mine(await positionRouter.minBlockDelayPublic());
                await positionRouter.connect(trader).cancelIncreasePosition(param, trader.address);
                await expect(
                    positionRouter
                        .connect(trader)
                        .createIncreasePosition(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee}),
                ).not.to.be.reverted;
            });
            it("should pass if the same request is already executed", async function () {
                const {trader, executor, market, positionRouter} = await loadFixture(deployFixture);
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
                await positionRouter.connect(executor).executeIncreasePosition(param, executor.address);
                await expect(
                    positionRouter
                        .connect(trader)
                        .createIncreasePosition(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee}),
                ).not.to.be.reverted;
            });

            it("should revert if allowance is insufficient and permitData is empty", async function () {
                const {trader, market, positionRouter, marketManager} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                await resetAllowance(market, trader, await marketManager.getAddress());
                await expect(
                    positionRouter
                        .connect(trader)
                        .createIncreasePosition(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee}),
                )
                    .to.be.revertedWithCustomError(market, "ERC20InsufficientAllowance")
                    .withArgs(marketManager.target, 0, 100n);
            });
            it("should revert if allowance is insufficient and permitData is invalid", async function () {
                const {trader, market, positionRouter, marketManager} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                await resetAllowance(market, trader, await marketManager.getAddress());
                await expect(
                    positionRouter
                        .connect(trader)
                        .createIncreasePosition(market, 100n, 100n, PRICE_1, "0xabcdef", {value: minExecutionFee}),
                ).to.be.reverted;
            });
            it("should revert if allowance is insufficient and permitData is other's", async function () {
                const {trader, other, market, positionRouter, marketManager} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                await resetAllowance(market, trader, await marketManager.getAddress());
                const permitData = await genERC20PermitData(market, other, await marketManager.getAddress(), 100n);
                await expect(
                    positionRouter
                        .connect(trader)
                        .createIncreasePosition(market, 100n, 100n, PRICE_1, permitData, {value: minExecutionFee}),
                )
                    .to.be.revertedWithCustomError(market, "ERC20InsufficientAllowance")
                    .withArgs(marketManager.target, 0, 100n);
            });
            it("should pass if allowance is insufficient and permitData is valid", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                await resetAllowance(market, trader, await positionRouter.getAddress());
                const permitData = await genERC20PermitData(market, trader, await positionRouter.getAddress(), 100n);
                const tx = await positionRouter
                    .connect(trader)
                    .createIncreasePosition(market, 100n, 100n, PRICE_1, permitData, {value: minExecutionFee});
                await expect(tx).to.changeEtherBalances([trader, positionRouter], [-minExecutionFee, minExecutionFee]);
                await expect(tx).to.changeTokenBalances(market, [trader, positionRouter], [-100n, 100n]);
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
                await expect(tx)
                    .to.emit(positionRouter, "IncreasePositionCreated")
                    .withArgs(trader.address, market, 100n, 100n, PRICE_1, minExecutionFee, false, id);
                expect(await positionRouter.blockNumbers(id)).is.gt(0n);
            });
            it("should pass if allowance is sufficient and permitData is empty", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                const tx = await positionRouter
                    .connect(trader)
                    .createIncreasePosition(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee});
                await expect(tx).to.changeEtherBalances([trader, positionRouter], [-minExecutionFee, minExecutionFee]);
                await expect(tx).to.changeTokenBalances(market, [trader, positionRouter], [-100n, 100n]);
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
                await expect(tx)
                    .to.emit(positionRouter, "IncreasePositionCreated")
                    .withArgs(trader.address, market, 100n, 100n, PRICE_1, minExecutionFee, false, id);
                expect(await positionRouter.blockNumbers(id)).is.gt(0n);
            });
        });
        describe("#createIncreasePositionETH", () => {
            it("should revert if msg.value is less than executionFee", async function () {
                const {trader, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionETH);
                const value = minExecutionFee - 1n;
                await expect(
                    positionRouter.connect(trader).createIncreasePositionETH(100n, PRICE_1, minExecutionFee, {value}),
                )
                    .to.be.revertedWithCustomError(positionRouter, "InsufficientExecutionFee")
                    .withArgs(value, minExecutionFee);
            });
            it("should revert if executionFee is less than minExecutionFee", async function () {
                const {trader, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionETH);
                const value = minExecutionFee - 1n;
                await expect(
                    positionRouter.connect(trader).createIncreasePositionETH(100n, PRICE_1, minExecutionFee, {value}),
                )
                    .to.be.revertedWithCustomError(positionRouter, "InsufficientExecutionFee")
                    .withArgs(value, minExecutionFee);
            });
            it("should revert if the same request exists", async function () {
                const {trader, weth, positionRouter} = await loadFixture(deployFixture);
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
                await expect(
                    positionRouter
                        .connect(trader)
                        .createIncreasePositionETH(100n, PRICE_1, minExecutionFee, {value: minExecutionFee + 100n}),
                )
                    .to.be.revertedWithCustomError(positionRouter, "ConflictRequests")
                    .withArgs(await increasePositionRequestId(param));
            });
            it("should pass if the same request is already cancelled", async function () {
                const {trader, weth, positionRouter} = await loadFixture(deployFixture);
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
                await mine(await positionRouter.minBlockDelayPublic());
                await positionRouter.connect(trader).cancelIncreasePosition(param, trader.address);
                await expect(
                    positionRouter
                        .connect(trader)
                        .createIncreasePositionETH(100n, PRICE_1, minExecutionFee, {value: minExecutionFee + 100n}),
                ).not.to.be.reverted;
            });
            it("should pass if the same request is already executed", async function () {
                const {trader, executor, weth, positionRouter} = await loadFixture(deployFixture);
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
                await mine(await positionRouter.minBlockDelayExecutor());
                await positionRouter.connect(executor).executeIncreasePosition(param, executor.address);
                await expect(
                    positionRouter
                        .connect(trader)
                        .createIncreasePositionETH(100n, PRICE_1, minExecutionFee, {value: minExecutionFee + 100n}),
                ).not.to.be.reverted;
            });
            it("should pass", async function () {
                const {trader, weth, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionETH);
                const amount = 100n;
                const value = minExecutionFee + amount;
                const tx = await positionRouter
                    .connect(trader)
                    .createIncreasePositionETH(100n, PRICE_1, minExecutionFee, {value});
                await expect(tx).to.changeEtherBalances([trader, positionRouter], [-value, minExecutionFee]);
                await expect(tx).to.changeTokenBalance(weth, positionRouter, amount);
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
                await expect(tx)
                    .to.emit(positionRouter, "IncreasePositionCreated")
                    .withArgs(trader.address, weth.target, amount, 100n, PRICE_1, minExecutionFee, false, id);
                expect(await positionRouter.blockNumbers(id)).is.gt(0n);
            });
        });
        describe("#createIncreasePositionPayPUSD", () => {
            it("should revert if msg.value is less than minExecutionFee", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionPayPUSD);
                const value = minExecutionFee - 1n;
                await expect(
                    positionRouter
                        .connect(trader)
                        .createIncreasePositionPayPUSD(market, 100n, 100n, PRICE_1, "0x", {value}),
                )
                    .to.be.revertedWithCustomError(positionRouter, "InsufficientExecutionFee")
                    .withArgs(value, minExecutionFee);
            });
            it("should revert if the same request exists", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionPayPUSD);
                await positionRouter
                    .connect(trader)
                    .createIncreasePositionPayPUSD(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee});
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: true,
                };
                await expect(
                    positionRouter
                        .connect(trader)
                        .createIncreasePositionPayPUSD(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee}),
                )
                    .to.be.revertedWithCustomError(positionRouter, "ConflictRequests")
                    .withArgs(await increasePositionRequestId(param));
            });
            it("should pass if the same request is already cancelled", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionPayPUSD);
                await positionRouter
                    .connect(trader)
                    .createIncreasePositionPayPUSD(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee});
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: true,
                };
                await mine(await positionRouter.minBlockDelayPublic());
                await positionRouter.connect(trader).cancelIncreasePosition(param, trader.address);
                await expect(
                    positionRouter
                        .connect(trader)
                        .createIncreasePositionPayPUSD(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee}),
                ).not.to.be.reverted;
            });
            it("should pass if the same request is already executed", async function () {
                const {trader, executor, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionPayPUSD);
                await positionRouter
                    .connect(trader)
                    .createIncreasePositionPayPUSD(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee});
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: true,
                };
                await mine(await positionRouter.minBlockDelayExecutor());
                await positionRouter.connect(executor).executeIncreasePosition(param, executor.address);
                await expect(
                    positionRouter
                        .connect(trader)
                        .createIncreasePositionPayPUSD(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee}),
                ).not.to.be.reverted;
            });
            it("should revert if allowance is insufficient and permitData is empty", async function () {
                const {trader, market, usd, marketManager, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionPayPUSD);
                await resetAllowance(usd, trader, await marketManager.getAddress());
                await expect(
                    positionRouter
                        .connect(trader)
                        .createIncreasePositionPayPUSD(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee}),
                )
                    .to.be.revertedWithCustomError(usd, "ERC20InsufficientAllowance")
                    .withArgs(marketManager.target, 0, 100n);
            });
            it("should revert if allowance is insufficient and permitData is invalid", async function () {
                const {trader, market, usd, marketManager, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionPayPUSD);
                await resetAllowance(usd, trader, await marketManager.getAddress());
                await expect(
                    positionRouter
                        .connect(trader)
                        .createIncreasePositionPayPUSD(market, 100n, 100n, PRICE_1, "0xabcdef", {
                            value: minExecutionFee,
                        }),
                ).to.be.reverted;
            });
            it("should revert if allowance is insufficient and permitData is other's", async function () {
                const {trader, other, market, usd, marketManager, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionPayPUSD);
                await resetAllowance(usd, trader, await marketManager.getAddress());
                const permitData = await genERC20PermitData(usd, other, await marketManager.getAddress(), 100n);
                await expect(
                    positionRouter
                        .connect(trader)
                        .createIncreasePositionPayPUSD(market, 100n, 100n, PRICE_1, permitData, {
                            value: minExecutionFee,
                        }),
                )
                    .to.be.revertedWithCustomError(usd, "ERC20InsufficientAllowance")
                    .withArgs(marketManager.target, 0, 100n);
            });
            it("should pass if allowance is insufficient and permitData is valid", async function () {
                const {trader, market, usd, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionPayPUSD);
                await resetAllowance(usd, trader, await positionRouter.getAddress());
                const permitData = await genERC20PermitData(usd, trader, await positionRouter.getAddress(), 100n);
                const tx = await positionRouter
                    .connect(trader)
                    .createIncreasePositionPayPUSD(market, 100n, 100n, PRICE_1, permitData, {
                        value: minExecutionFee,
                    });
                await expect(tx).to.changeEtherBalances([trader, positionRouter], [-minExecutionFee, minExecutionFee]);
                await expect(tx).to.changeTokenBalances(usd, [trader, positionRouter], [-100n, 100n]);
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
                await expect(tx)
                    .to.emit(positionRouter, "IncreasePositionCreated")
                    .withArgs(trader.address, market, 100n, 100n, PRICE_1, minExecutionFee, true, id);
                expect(await positionRouter.blockNumbers(id)).is.gt(0n);
            });
            it("should pass if allowance is sufficient and permitData is empty", async function () {
                const {trader, market, positionRouter, usd} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePositionPayPUSD);
                const tx = await positionRouter
                    .connect(trader)
                    .createIncreasePositionPayPUSD(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee});
                await expect(tx).to.changeEtherBalances([trader, positionRouter], [-minExecutionFee, minExecutionFee]);
                await expect(tx).to.changeTokenBalances(usd, [trader, positionRouter], [-100n, 100n]);
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
                await expect(tx)
                    .to.emit(positionRouter, "IncreasePositionCreated")
                    .withArgs(trader.address, market, 100n, 100n, PRICE_1, minExecutionFee, true, id);
                expect(await positionRouter.blockNumbers(id)).is.gt(0n);
            });
        });
        describe("#cancelIncreasePosition", () => {
            describe("shouldCancel/shouldExecuteOrCancel", function () {
                it("should revert if caller is not request owner nor executor", async () => {
                    const {positionRouter, market, trader, other} = await loadFixture(deployFixture);
                    const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                    // create a new request
                    await positionRouter
                        .connect(trader)
                        .createIncreasePosition(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee});

                    await expect(
                        positionRouter.connect(other).cancelIncreasePosition(
                            {
                                account: trader.address,
                                market: market.target,
                                marginDelta: 100n,
                                sizeDelta: 100n,
                                acceptableIndexPrice: PRICE_1,
                                executionFee: minExecutionFee,
                                payPUSD: false,
                            },
                            other.address,
                        ),
                    ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
                });

                it("should wait at least minBlockDelayExecutor until executors can cancel", async () => {
                    const {positionRouter, market, trader, executor} = await loadFixture(deployFixture);
                    const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                    // executor has to wait 10 blocks
                    await positionRouter.updateDelayValues(10n, 3000n, 6000n);
                    // create a new request
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
                    const id = await increasePositionRequestId(param);

                    // should fail to cancel
                    await positionRouter.connect(executor).cancelIncreasePosition(param, executor.address);
                    expect(await positionRouter.blockNumbers(id)).is.gt(0n);

                    // mine 10 blocks
                    await mine(10);

                    // should be cancelled
                    await positionRouter.connect(executor).cancelIncreasePosition(param, executor.address);
                    expect(await positionRouter.blockNumbers(id)).eq(0n);
                });

                it("should wait at least minBlockDelayPublic until public can cancel", async () => {
                    const {positionRouter, market, trader} = await loadFixture(deployFixture);
                    const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                    await expect(positionRouter.updateDelayValues(10n, 100n, 600n)).not.to.be.reverted;
                    // create a new request
                    await positionRouter
                        .connect(trader)
                        .createIncreasePosition(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee});
                    const earliest = (await time.latestBlock()) + 100;
                    const param = {
                        account: trader.address,
                        market: market.target,
                        marginDelta: 100n,
                        sizeDelta: 100n,
                        acceptableIndexPrice: PRICE_1,
                        executionFee: minExecutionFee,
                        payPUSD: false,
                    };
                    await expect(positionRouter.connect(trader).cancelIncreasePosition(param, trader.address))
                        .to.be.revertedWithCustomError(positionRouter, "TooEarly")
                        .withArgs(earliest);
                    const id = await increasePositionRequestId(param);
                    await mine(100n);
                    expect(await positionRouter.blockNumbers(id)).is.gt(0n);
                    await positionRouter.connect(trader).cancelIncreasePosition(param, trader.address);
                    expect(await positionRouter.blockNumbers(id)).eq(0n);
                });
            });

            it("should pass if request not exist", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                await positionRouter.cancelIncreasePosition(
                    {
                        account: trader.address,
                        market: market.target,
                        marginDelta: 100n,
                        sizeDelta: 100n,
                        acceptableIndexPrice: PRICE_1,
                        executionFee: minExecutionFee,
                        payPUSD: false,
                    },
                    trader.address,
                );
            });

            it("should revert with 'Forbidden' if caller is not request owner", async () => {
                const {positionRouter, trader, other, market} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                await positionRouter
                    .connect(trader)
                    .createIncreasePosition(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee});
                await expect(
                    positionRouter.connect(other).cancelIncreasePosition(
                        {
                            account: trader.address,
                            market: market.target,
                            marginDelta: 100n,
                            sizeDelta: 100n,
                            acceptableIndexPrice: PRICE_1,
                            executionFee: minExecutionFee,
                            payPUSD: false,
                        },
                        other.address,
                    ),
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
            });

            it("should be ok if executor cancel and market is not weth", async () => {
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
                const tx = positionRouter.connect(executor).cancelIncreasePosition(param, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter, executor],
                    [-minExecutionFee, minExecutionFee],
                );
                await expect(tx).to.changeTokenBalances(market, [positionRouter, trader], [-100n, 100n]);
                const id = await increasePositionRequestId(param);
                await expect(tx).to.emit(positionRouter, "IncreasePositionCancelled").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("should be ok if executor cancel and market is weth", async () => {
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
                const tx = positionRouter.connect(executor).cancelIncreasePosition(param, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter, executor, trader],
                    [-minExecutionFee, minExecutionFee, 100n],
                );
                await expect(tx).to.changeTokenBalance(weth, positionRouter, -100n);
                const id = await increasePositionRequestId(param);
                await expect(tx).to.emit(positionRouter, "IncreasePositionCancelled").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("should be ok if executor cancel and payPUSD is true", async () => {
                const {positionRouter, market, usd, trader, executor} = await loadFixture(deployFixture);
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
                const tx = positionRouter.connect(executor).cancelIncreasePosition(param, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter, executor],
                    [-minExecutionFee, minExecutionFee],
                );
                await expect(tx).to.changeTokenBalances(usd, [positionRouter, trader], [-100n, 100n]);
                const id = await increasePositionRequestId(param);
                await expect(tx).to.emit(positionRouter, "IncreasePositionCancelled").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });

            it("should be ok if request owner calls and market is not weth", async () => {
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
                    payPUSD: false,
                };
                const tx = positionRouter.connect(trader).cancelIncreasePosition(param, trader.address);
                await expect(tx).to.changeEtherBalances([positionRouter, trader], [-minExecutionFee, minExecutionFee]);
                await expect(tx).to.changeTokenBalances(market, [positionRouter, trader], [-100n, 100n]);
                const id = await increasePositionRequestId(param);
                await expect(tx).to.emit(positionRouter, "IncreasePositionCancelled").withArgs(id, trader.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });

            it("should be ok if request owner calls and market is weth", async () => {
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
                const tx = positionRouter.connect(trader).cancelIncreasePosition(param, trader.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter, trader],
                    [-minExecutionFee, minExecutionFee + 100n],
                );
                await expect(tx).to.changeTokenBalance(weth, positionRouter, -100n);
                const id = await increasePositionRequestId(param);
                await expect(tx).to.emit(positionRouter, "IncreasePositionCancelled").withArgs(id, trader.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });

            it("should be ok if request owner calls and payPUSD is true", async () => {
                const {positionRouter, market, usd, trader} = await loadFixture(deployFixture);
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
                const tx = positionRouter.connect(trader).cancelIncreasePosition(param, trader.address);
                await expect(tx).to.changeEtherBalances([positionRouter, trader], [-minExecutionFee, minExecutionFee]);
                await expect(tx).to.changeTokenBalances(usd, [positionRouter, trader], [-100n, 100n]);
                const id = await increasePositionRequestId(param);
                await expect(tx).to.emit(positionRouter, "IncreasePositionCancelled").withArgs(id, trader.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });
        describe("#executeIncreasePosition", () => {
            it("should pass if request is not exist", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                await positionRouter.executeIncreasePosition(
                    {
                        account: trader.address,
                        market: market.target,
                        marginDelta: 100n,
                        sizeDelta: 100n,
                        acceptableIndexPrice: PRICE_1,
                        executionFee: minExecutionFee,
                        payPUSD: false,
                    },
                    trader.address,
                );
            });

            it("should revert with 'Forbidden' if caller is not executor nor request owner", async () => {
                const {trader, other, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                await positionRouter
                    .connect(trader)
                    .createIncreasePosition(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee});
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await expect(
                    positionRouter.connect(other).executeIncreasePosition(
                        {
                            account: trader.address,
                            market: market.target,
                            marginDelta: 100n,
                            sizeDelta: 100n,
                            acceptableIndexPrice: PRICE_1,
                            executionFee: minExecutionFee,
                            payPUSD: false,
                        },
                        other.address,
                    ),
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
            });

            it("should revert with 'Expired' if maxBlockDelay passed", async () => {
                const {positionRouter, market, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await positionRouter
                    .connect(trader)
                    .createIncreasePosition(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee});
                const expiredAt = (await time.latestBlock()) + 600;
                await mine(600n);
                await expect(
                    positionRouter.connect(executor).executeIncreasePosition(
                        {
                            account: trader.address,
                            market: market.target,
                            marginDelta: 100n,
                            sizeDelta: 100n,
                            acceptableIndexPrice: PRICE_1,
                            executionFee: minExecutionFee,
                            payPUSD: false,
                        },
                        executor.address,
                    ),
                )
                    .to.be.revertedWithCustomError(positionRouter, "Expired")
                    .withArgs(expiredAt);
            });

            it("should revert with 'TooEarly' if someone who are not the executor executes his own request and pass if sufficient time elapsed", async () => {
                const {positionRouter, market, marketManager, trader} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                await positionRouter
                    .connect(trader)
                    .createIncreasePosition(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee});
                const current = BigInt(await time.latestBlock());
                await marketManager.setMaxPrice(PRICE_1);
                const minBlockDelayPublic = await positionRouter.minBlockDelayPublic();
                const param = {
                    account: trader.address,
                    market: market.target,
                    marginDelta: 100n,
                    sizeDelta: 100n,
                    acceptableIndexPrice: PRICE_1,
                    executionFee: minExecutionFee,
                    payPUSD: false,
                };
                await expect(positionRouter.connect(trader).executeIncreasePosition(param, trader.address))
                    .to.be.revertedWithCustomError(positionRouter, "TooEarly")
                    .withArgs(current + minBlockDelayPublic);
                await mine(minBlockDelayPublic);
                await expect(positionRouter.connect(trader).executeIncreasePosition(param, trader.address)).not.to.be
                    .reverted;
            });

            it("should revert with 'InvalidIndexPrice' if indexPrice > acceptableIndexPrice", async () => {
                const {positionRouter, marketManager, market, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                await positionRouter
                    .connect(trader)
                    .createIncreasePosition(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee});
                // set a delay value to prevent expire
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await marketManager.setMaxPrice(PRICE_1 + 1n);
                const tx = positionRouter.connect(executor).executeIncreasePosition(
                    {
                        account: trader.address,
                        market: market.target,
                        marginDelta: 100n,
                        sizeDelta: 100n,
                        acceptableIndexPrice: PRICE_1,
                        executionFee: minExecutionFee,
                        payPUSD: false,
                    },
                    executor.address,
                );
                await expect(tx)
                    .to.be.revertedWithCustomError(positionRouter, "InvalidIndexPrice")
                    .withArgs(PRICE_1 + 1n, PRICE_1);
            });

            it("should emit event and distribute funds", async () => {
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
                const tx = positionRouter.connect(executor).executeIncreasePosition(param, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter, executor],
                    [-minExecutionFee, minExecutionFee],
                );
                await expect(tx).to.changeTokenBalances(market, [positionRouter, marketManager], [-100n, 100n]);
                const id = await increasePositionRequestId(param);
                await expect(tx).to.emit(positionRouter, "IncreasePositionExecuted").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });
        describe("#executeOrCancelIncreasePosition", () => {
            it("should revert with 'Forbidden' if caller is not executor", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                await expect(
                    positionRouter.executeOrCancelIncreasePosition(
                        {
                            account: trader.address,
                            market: market.target,
                            marginDelta: 100n,
                            sizeDelta: 100n,
                            acceptableIndexPrice: PRICE_1,
                            executionFee: minExecutionFee,
                            payPUSD: false,
                        },
                        trader.address,
                    ),
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
            });
            it("should cancel request if execution reverted", async () => {
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
                const id = await increasePositionRequestId(param);
                const reason = ethers.id("Expired(uint256)").substring(0, 10);
                await expect(tx)
                    .to.emit(positionRouter, "ExecuteFailed")
                    .withArgs(2, id, reason)
                    .to.emit(positionRouter, "IncreasePositionCancelled")
                    .withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("should execute request if execution passed", async () => {
                const {trader, executor, positionRouter, market, marketManager} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.IncreasePosition);
                await positionRouter
                    .connect(trader)
                    .createIncreasePosition(market, 100n, 100n, PRICE_1, "0x", {value: minExecutionFee});
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
                await mine(await positionRouter.minBlockDelayExecutor());
                const tx = positionRouter.connect(executor).executeOrCancelIncreasePosition(param, executor.address);
                const id = await increasePositionRequestId(param);
                await expect(tx).to.emit(positionRouter, "IncreasePositionExecuted").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });
    });
    describe("DecreasePosition", () => {
        describe("#createDecreasePosition", () => {
            it("should revert if msg.value is less than minExecutionFee", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                const value = minExecutionFee - 1n;
                await expect(
                    positionRouter.connect(trader).createDecreasePosition(market, 100n, 100n, PRICE_1, trader, {value}),
                )
                    .to.be.revertedWithCustomError(positionRouter, "InsufficientExecutionFee")
                    .withArgs(value, minExecutionFee);
            });
            it("should revert if the same request exists", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
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
                await expect(
                    positionRouter.connect(trader).createDecreasePosition(market, 100n, 100n, PRICE_1, trader, {
                        value: minExecutionFee,
                    }),
                )
                    .to.be.revertedWithCustomError(positionRouter, "ConflictRequests")
                    .withArgs(await decreasePositionRequestId(param));
            });
            it("should pass if the same request is already cancelled", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
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
                await mine(await positionRouter.minBlockDelayPublic());
                await positionRouter.connect(trader).cancelDecreasePosition(param, trader.address);
                await expect(
                    positionRouter.connect(trader).createDecreasePosition(market, 100n, 100n, PRICE_1, trader, {
                        value: minExecutionFee,
                    }),
                ).not.to.be.reverted;
            });
            it("should pass if the same request is already executed", async () => {
                const {trader, executor, market, marketManager, positionRouter} = await loadFixture(deployFixture);
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
                await marketManager.setActualMarginDelta(80n);
                await positionRouter.connect(executor).executeDecreasePosition(param, executor.address);
                await expect(
                    positionRouter.connect(trader).createDecreasePosition(market, 100n, 100n, PRICE_1, trader, {
                        value: minExecutionFee,
                    }),
                ).not.to.be.reverted;
            });
            it("should pass", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                const tx = await positionRouter
                    .connect(trader)
                    .createDecreasePosition(market, 100n, 100n, PRICE_1, trader, {value: minExecutionFee});
                await expect(tx).to.changeEtherBalances([trader, positionRouter], [-minExecutionFee, minExecutionFee]);
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
                await expect(tx)
                    .to.emit(positionRouter, "DecreasePositionCreated")
                    .withArgs(trader.address, market, 100n, 100n, PRICE_1, trader.address, minExecutionFee, false, id);
                expect(await positionRouter.blockNumbers(id)).is.gt(0n);
            });
        });
        describe("#createDecreasePositionReceivePUSD", () => {
            it("should revert if msg.value is less than minExecutionFee", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(
                    ExecutionFeeType.DecreasePositionReceivePUSD,
                );
                const value = minExecutionFee - 1n;
                await expect(
                    positionRouter
                        .connect(trader)
                        .createDecreasePositionReceivePUSD(market, 100n, 100n, PRICE_1, trader, {value}),
                )
                    .to.be.revertedWithCustomError(positionRouter, "InsufficientExecutionFee")
                    .withArgs(value, minExecutionFee);
            });
            it("should revert if the same request exists", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(
                    ExecutionFeeType.DecreasePositionReceivePUSD,
                );
                await positionRouter
                    .connect(trader)
                    .createDecreasePositionReceivePUSD(market, 100n, 100n, PRICE_1, trader, {value: minExecutionFee});
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
                await expect(
                    positionRouter
                        .connect(trader)
                        .createDecreasePositionReceivePUSD(market, 100n, 100n, PRICE_1, trader, {
                            value: minExecutionFee,
                        }),
                )
                    .to.be.revertedWithCustomError(positionRouter, "ConflictRequests")
                    .withArgs(await decreasePositionRequestId(param));
            });
            it("should pass if the same request is already cancelled", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(
                    ExecutionFeeType.DecreasePositionReceivePUSD,
                );
                await positionRouter
                    .connect(trader)
                    .createDecreasePositionReceivePUSD(market, 100n, 100n, PRICE_1, trader, {value: minExecutionFee});
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
                await mine(await positionRouter.minBlockDelayPublic());
                await positionRouter.connect(trader).cancelDecreasePosition(param, trader.address);
                await expect(
                    positionRouter
                        .connect(trader)
                        .createDecreasePositionReceivePUSD(market, 100n, 100n, PRICE_1, trader, {
                            value: minExecutionFee,
                        }),
                ).not.to.be.reverted;
            });
            it("should pass if the same request is already executed", async () => {
                const {trader, executor, market, marketManager, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(
                    ExecutionFeeType.DecreasePositionReceivePUSD,
                );
                await positionRouter
                    .connect(trader)
                    .createDecreasePositionReceivePUSD(market, 100n, 100n, PRICE_1, trader, {value: minExecutionFee});
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
                await mine(await positionRouter.minBlockDelayExecutor());
                await marketManager.setMinPrice(PRICE_1);
                await marketManager.setReceivePUSD(true);
                await marketManager.setPayAmount(100n);
                await marketManager.setActualMarginDelta(100n);
                await positionRouter.connect(executor).executeDecreasePosition(param, executor.address);
                await expect(
                    positionRouter
                        .connect(trader)
                        .createDecreasePositionReceivePUSD(market, 100n, 100n, PRICE_1, trader, {
                            value: minExecutionFee,
                        }),
                ).not.to.be.reverted;
            });
            it("should pass", async function () {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(
                    ExecutionFeeType.DecreasePositionReceivePUSD,
                );
                const tx = await positionRouter
                    .connect(trader)
                    .createDecreasePositionReceivePUSD(market, 100n, 100n, PRICE_1, trader, {
                        value: minExecutionFee,
                    });
                await expect(tx).to.changeEtherBalances([trader, positionRouter], [-minExecutionFee, minExecutionFee]);
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
                await expect(tx)
                    .to.emit(positionRouter, "DecreasePositionCreated")
                    .withArgs(trader.address, market, 100n, 100n, PRICE_1, trader.address, minExecutionFee, true, id);
                expect(await positionRouter.blockNumbers(id)).is.gt(0n);
            });
        });
        describe("#cancelDecreasePosition", () => {
            describe("shouldCancel/shouldExecuteOrCancel", function () {
                it("should revert if caller is not request owner nor executor", async () => {
                    const {positionRouter, market, trader, other} = await loadFixture(deployFixture);
                    const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                    // create a new request
                    await positionRouter
                        .connect(trader)
                        .createDecreasePosition(market, 100n, 100n, PRICE_1, trader, {value: minExecutionFee});

                    await expect(
                        positionRouter.connect(other).cancelDecreasePosition(
                            {
                                account: trader.address,
                                market: market.target,
                                marginDelta: 100n,
                                sizeDelta: 100n,
                                acceptableIndexPrice: PRICE_1,
                                receiver: trader.address,
                                executionFee: minExecutionFee,
                                receivePUSD: false,
                            },
                            other.address,
                        ),
                    ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
                });

                it("should wait at least minBlockDelayExecutor until executors can cancel", async () => {
                    const {positionRouter, market, trader, executor} = await loadFixture(deployFixture);
                    const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                    // executor has to wait 10 blocks
                    await positionRouter.updateDelayValues(10n, 3000n, 6000n);
                    // create a new request
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
                    const id = await decreasePositionRequestId(param);

                    // should fail to cancel
                    await positionRouter.connect(executor).cancelDecreasePosition(param, executor.address);
                    expect(await positionRouter.blockNumbers(id)).is.gt(0n);

                    // mine 10 blocks
                    await mine(10);

                    // should be cancelled
                    await positionRouter.connect(executor).cancelDecreasePosition(param, executor.address);
                    expect(await positionRouter.blockNumbers(id)).eq(0n);
                });

                it("should wait at least minBlockDelayPublic until public can cancel", async () => {
                    const {positionRouter, market, trader} = await loadFixture(deployFixture);
                    const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                    await expect(positionRouter.updateDelayValues(10n, 100n, 600n)).not.to.be.reverted;
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
                    // create a new request
                    await positionRouter
                        .connect(trader)
                        .createDecreasePosition(market, 100n, 100n, PRICE_1, trader, {value: minExecutionFee});
                    const earliest = (await time.latestBlock()) + 100;
                    await expect(positionRouter.connect(trader).cancelDecreasePosition(param, trader.address))
                        .to.be.revertedWithCustomError(positionRouter, "TooEarly")
                        .withArgs(earliest);

                    await mine(100n);
                    const id = await decreasePositionRequestId(param);
                    expect(await positionRouter.blockNumbers(id)).is.gt(0n);
                    await positionRouter.connect(trader).cancelDecreasePosition(param, trader.address);
                    expect(await positionRouter.blockNumbers(id)).eq(0n);
                });
            });

            it("should pass if request not exist", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                await positionRouter.cancelDecreasePosition(
                    {
                        account: trader.address,
                        market: market.target,
                        marginDelta: 100n,
                        sizeDelta: 100n,
                        acceptableIndexPrice: PRICE_1,
                        receiver: trader.address,
                        executionFee: minExecutionFee,
                        receivePUSD: false,
                    },
                    trader.address,
                );
            });

            it("should revert with 'Forbidden' if caller is not request owner", async () => {
                const {positionRouter, trader, other, market} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                await positionRouter
                    .connect(trader)
                    .createDecreasePosition(market, 100n, 100n, PRICE_1, trader, {value: minExecutionFee});
                await expect(
                    positionRouter.connect(other).cancelDecreasePosition(
                        {
                            account: trader.address,
                            market: market.target,
                            marginDelta: 100n,
                            sizeDelta: 100n,
                            acceptableIndexPrice: PRICE_1,
                            receiver: trader.address,
                            executionFee: minExecutionFee,
                            receivePUSD: false,
                        },
                        other.address,
                    ),
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
            });

            it("should be ok if executor cancel", async () => {
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
                const tx = positionRouter.connect(executor).cancelDecreasePosition(param, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter, executor],
                    [-minExecutionFee, minExecutionFee],
                );
                const id = await decreasePositionRequestId(param);
                await expect(tx).to.emit(positionRouter, "DecreasePositionCancelled").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });

            it("should be ok if request owner calls", async () => {
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
                const tx = positionRouter.connect(trader).cancelDecreasePosition(param, trader.address);
                await expect(tx).to.changeEtherBalances([positionRouter, trader], [-minExecutionFee, minExecutionFee]);
                const id = await decreasePositionRequestId(param);
                await expect(tx).to.emit(positionRouter, "DecreasePositionCancelled").withArgs(id, trader.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });
        describe("#executeDecreasePosition", () => {
            it("should pass if request is not exist", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                await positionRouter.executeDecreasePosition(
                    {
                        account: trader.address,
                        market: market.target,
                        marginDelta: 100n,
                        sizeDelta: 100n,
                        acceptableIndexPrice: PRICE_1,
                        receiver: trader.address,
                        executionFee: minExecutionFee,
                        receivePUSD: false,
                    },
                    trader.address,
                );
            });

            it("should revert with 'Forbidden' if caller is not executor nor request owner", async () => {
                const {trader, other, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                await positionRouter
                    .connect(trader)
                    .createDecreasePosition(market, 100n, 100n, PRICE_1, trader, {value: minExecutionFee});
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await expect(
                    positionRouter.connect(other).executeDecreasePosition(
                        {
                            account: trader.address,
                            market: market.target,
                            marginDelta: 100n,
                            sizeDelta: 100n,
                            acceptableIndexPrice: PRICE_1,
                            receiver: trader.address,
                            executionFee: minExecutionFee,
                            receivePUSD: false,
                        },
                        other.address,
                    ),
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
            });

            it("should revert with 'Expired' if maxBlockDelay passed", async () => {
                const {positionRouter, market, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await positionRouter
                    .connect(trader)
                    .createDecreasePosition(market, 100n, 100n, PRICE_1, trader, {value: minExecutionFee});
                const expiredAt = (await time.latestBlock()) + 600;
                await mine(600n);
                await expect(
                    positionRouter.connect(executor).executeDecreasePosition(
                        {
                            account: trader.address,
                            market: market.target,
                            marginDelta: 100n,
                            sizeDelta: 100n,
                            acceptableIndexPrice: PRICE_1,
                            receiver: trader.address,
                            executionFee: minExecutionFee,
                            receivePUSD: false,
                        },
                        executor.address,
                    ),
                )
                    .to.be.revertedWithCustomError(positionRouter, "Expired")
                    .withArgs(expiredAt);
            });

            it("should revert with 'TooEarly' if someone who are not the executor executes his own request and pass if sufficient time elapsed", async () => {
                const {positionRouter, market, marketManager, trader} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                await positionRouter
                    .connect(trader)
                    .createDecreasePosition(market, 100n, 100n, PRICE_1, trader, {value: minExecutionFee});
                const current = BigInt(await time.latestBlock());
                await marketManager.setMinPrice(PRICE_1);
                const minBlockDelayPublic = await positionRouter.minBlockDelayPublic();
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
                await expect(positionRouter.connect(trader).executeDecreasePosition(param, trader.address))
                    .to.be.revertedWithCustomError(positionRouter, "TooEarly")
                    .withArgs(current + minBlockDelayPublic);
                await mine(minBlockDelayPublic);
                await expect(positionRouter.connect(trader).executeDecreasePosition(param, trader.address)).not.to.be
                    .reverted;
            });

            it("should revert with 'InvalidIndexPrice' if indexPrice < acceptableIndexPrice", async () => {
                const {positionRouter, marketManager, market, trader, executor} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                await positionRouter
                    .connect(trader)
                    .createDecreasePosition(market, 100n, 100n, PRICE_1, trader, {value: minExecutionFee});
                // set a delay value to prevent expire
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await marketManager.setMinPrice(PRICE_1 - 1n);
                const tx = positionRouter.connect(executor).executeDecreasePosition(
                    {
                        account: trader.address,
                        market: market.target,
                        marginDelta: 100n,
                        sizeDelta: 100n,
                        acceptableIndexPrice: PRICE_1,
                        receiver: trader.address,
                        executionFee: minExecutionFee,
                        receivePUSD: false,
                    },
                    executor.address,
                );
                await expect(tx)
                    .to.be.revertedWithCustomError(positionRouter, "InvalidIndexPrice")
                    .withArgs(PRICE_1 - 1n, PRICE_1);
            });

            it("should emit event and distribute funds when the market is weth", async () => {
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
                const tx = positionRouter.connect(executor).executeDecreasePosition(param, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter, executor, trader],
                    [-minExecutionFee, minExecutionFee, 80n],
                );
                const id = await decreasePositionRequestId(param);
                await expect(tx).to.emit(positionRouter, "DecreasePositionExecuted").withArgs(id, executor.address);
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
                const tx = positionRouter.connect(executor).executeDecreasePosition(param, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter, executor],
                    [-minExecutionFee, minExecutionFee],
                );
                const id = await decreasePositionRequestId(param);
                await expect(tx).to.emit(positionRouter, "DecreasePositionExecuted").withArgs(id, executor.address);
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
                const tx = positionRouter.connect(executor).executeDecreasePosition(param, executor.address);
                await expect(tx).to.changeEtherBalances(
                    [positionRouter, executor],
                    [-minExecutionFee, minExecutionFee],
                );
                const id = await decreasePositionRequestId(param);
                await expect(tx).to.emit(positionRouter, "DecreasePositionExecuted").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });
        describe("#executeOrCancelDecreasePosition", () => {
            it("should revert with 'Forbidden' if caller is not executor", async () => {
                const {trader, market, positionRouter} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                await expect(
                    positionRouter.executeOrCancelDecreasePosition(
                        {
                            account: trader.address,
                            market: market.target,
                            marginDelta: 100n,
                            sizeDelta: 100n,
                            acceptableIndexPrice: PRICE_1,
                            receiver: trader.address,
                            executionFee: minExecutionFee,
                            receivePUSD: false,
                        },
                        trader.address,
                    ),
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
            });
            it("should cancel request if execution reverted", async () => {
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
                const id = await decreasePositionRequestId(param);
                const reason = ethers.id("Expired(uint256)").substring(0, 10);
                await expect(tx)
                    .to.emit(positionRouter, "ExecuteFailed")
                    .withArgs(3, id, reason)
                    .to.emit(positionRouter, "DecreasePositionCancelled")
                    .withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
            it("should execute request if execution passed", async () => {
                const {trader, executor, positionRouter, market, marketManager} = await loadFixture(deployFixture);
                const minExecutionFee = await positionRouter.minExecutionFees(ExecutionFeeType.DecreasePosition);
                await positionRouter
                    .connect(trader)
                    .createDecreasePosition(market, 100n, 100n, PRICE_1, trader, {value: minExecutionFee});
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
                await mine(await positionRouter.minBlockDelayExecutor());
                const tx = positionRouter.connect(executor).executeOrCancelDecreasePosition(param, executor.address);
                const id = await decreasePositionRequestId(param);
                await expect(tx).to.emit(positionRouter, "DecreasePositionExecuted").withArgs(id, executor.address);
                expect(await positionRouter.blockNumbers(id)).eq(0n);
            });
        });
    });
});

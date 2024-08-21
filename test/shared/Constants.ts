import Decimal from "decimal.js";
import {BigNumberish, toBigInt} from "ethers";

export const Q32 = 1n << 32n;
export const Q64 = 1n << 64n;
export const Q96 = 1n << 96n;

export const BASIS_POINTS_DIVISOR = 10_000_000n;

export const DECIMALS_18: number = 18;
export const DECIMALS_6: number = 6;

export const PRICE_DECIMALS: number = 10;
export const PRICE_1: bigint = 10n ** BigInt(PRICE_DECIMALS);

export type Side = number;

export enum Rounding {
    Down,
    Up,
}

export enum EstimatedGasLimitType {
    MintLPT,
    MintLPTPayPUSD,
    BurnLPT,
    BurnLPTReceivePUSD,
    IncreasePosition,
    IncreasePositionPayPUSD,
    DecreasePosition,
    DecreasePositionReceivePUSD,
    MintPUSD,
    BurnPUSD,
    IncreaseBalanceRate,
}

export function mulDiv(a: BigNumberish, b: BigNumberish, c: BigNumberish, rounding?: Rounding): bigint {
    const mul = toBigInt(a) * toBigInt(b);
    let ans = mul / toBigInt(c);
    if (rounding != undefined && rounding == Rounding.Up) {
        if (ans * toBigInt(c) != mul) {
            ans = ans + 1n;
        }
    }
    return ans;
}

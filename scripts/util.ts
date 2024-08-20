import Decimal from "decimal.js";
import {randomBytes} from "crypto";

export function parsePercent(val: string): bigint {
    if (!val.endsWith("%")) {
        throw new Error("invalid percent, should end with %");
    }
    val = val.slice(0, -1);
    return BigInt(new Decimal(val).mul(new Decimal(1e5)).toFixed(0));
}

export function generateRandomBytes32(): string {
    const randomBuffer = randomBytes(32); // Generates 32 random bytes
    return "0x" + randomBuffer.toString("hex"); // Convert to hexadecimal string and add 0x prefix
}

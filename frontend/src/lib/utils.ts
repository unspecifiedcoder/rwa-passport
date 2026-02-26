import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function truncateAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

export function formatValue(value: bigint, decimals = 18): string {
  const divisor = BigInt(10 ** decimals);
  const intPart = value / divisor;
  return intPart.toLocaleString();
}

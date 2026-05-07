import {
  sepolia,
  arbitrumSepolia,
  baseSepolia,
  avalancheFuji,
  bscTestnet,
} from "wagmi/chains";
import { type Chain } from "viem";

// Monad Testnet (not in wagmi/chains — custom definition)
export const monadTestnet: Chain = {
  id: 10143,
  name: "Monad Testnet",
  nativeCurrency: { name: "Monad", symbol: "MON", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://testnet-rpc.monad.xyz"] },
  },
  blockExplorers: {
    default: {
      name: "MonadVision",
      url: "https://testnet.monadvision.com",
    },
  },
  testnet: true,
};

export const SUPPORTED_CHAINS = [
  avalancheFuji,
  bscTestnet,
  monadTestnet,
  sepolia,
  arbitrumSepolia,
  baseSepolia,
] as const;

export const CHAIN_NAMES: Record<number, string> = {
  [avalancheFuji.id]: "Avalanche Fuji",
  [bscTestnet.id]: "BNB Chain Testnet",
  [monadTestnet.id]: "Monad Testnet",
  [sepolia.id]: "Ethereum Sepolia",
  [arbitrumSepolia.id]: "Arbitrum Sepolia",
  [baseSepolia.id]: "Base Sepolia",
};

export const CHAIN_COLORS: Record<number, string> = {
  [avalancheFuji.id]: "bg-red-500",
  [bscTestnet.id]: "bg-yellow-500",
  [monadTestnet.id]: "bg-purple-500",
  [sepolia.id]: "bg-blue-500",
  [arbitrumSepolia.id]: "bg-sky-500",
  [baseSepolia.id]: "bg-indigo-500",
};

export function getChainName(chainId: number): string {
  return CHAIN_NAMES[chainId] || `Chain ${chainId}`;
}

export function getChainColor(chainId: number): string {
  return CHAIN_COLORS[chainId] || "bg-gray-500";
}

const EXPLORER_BASE: Record<number, string> = {
  [avalancheFuji.id]: "https://testnet.snowtrace.io",
  [bscTestnet.id]: "https://testnet.bscscan.com",
  [monadTestnet.id]: "https://testnet.monadexplorer.com",
  [sepolia.id]: "https://sepolia.etherscan.io",
  [arbitrumSepolia.id]: "https://sepolia.arbiscan.io",
  [baseSepolia.id]: "https://sepolia.basescan.org",
};

export function getExplorerUrl(
  chainId: number,
  hash: string,
  kind: "tx" | "address" = "tx",
): string | undefined {
  const base = EXPLORER_BASE[chainId];
  if (!base) return undefined;
  return `${base}/${kind}/${hash}`;
}

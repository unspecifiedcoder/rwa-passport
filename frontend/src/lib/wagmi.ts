import { createConfig, http } from "wagmi";
import {
  sepolia,
  arbitrumSepolia,
  baseSepolia,
  avalancheFuji,
  bscTestnet,
} from "wagmi/chains";
import { monadTestnet } from "./chains";

const ALCHEMY_KEY = process.env.NEXT_PUBLIC_ALCHEMY_API_KEY || "";

export const config = createConfig({
  chains: [avalancheFuji, bscTestnet, monadTestnet, sepolia, arbitrumSepolia, baseSepolia],
  transports: {
    [avalancheFuji.id]: http(
      "https://api.avax-test.network/ext/bc/C/rpc"
    ),
    [bscTestnet.id]: http(
      "https://data-seed-prebsc-1-s1.bnbchain.org:8545"
    ),
    [monadTestnet.id]: http(
      "https://testnet-rpc.monad.xyz"
    ),
    [sepolia.id]: http(
      `https://eth-sepolia.g.alchemy.com/v2/${ALCHEMY_KEY}`
    ),
    [arbitrumSepolia.id]: http(
      `https://arb-sepolia.g.alchemy.com/v2/${ALCHEMY_KEY}`
    ),
    [baseSepolia.id]: http(
      `https://base-sepolia.g.alchemy.com/v2/${ALCHEMY_KEY}`
    ),
  },
});

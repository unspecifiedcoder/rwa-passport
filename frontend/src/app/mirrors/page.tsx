"use client";

import { useReadContract, useReadContracts } from "wagmi";
import { bscTestnet, avalancheFuji } from "wagmi/chains";
import { MirrorTable, type MirrorEntry } from "@/components/MirrorTable";
import { XYTHUM_TOKEN_ABI, CANONICAL_FACTORY_ABI, CONTRACTS } from "@/lib/contracts";
import { getChainName, monadTestnet } from "@/lib/chains";
import { useState, useMemo } from "react";

const ACTIVE_CHAINS = [
  { chain: avalancheFuji, key: "avalancheFuji" },
  { chain: bscTestnet, key: "bscTestnet" },
  { chain: monadTestnet, key: "monadTestnet" },
] as const;

const POLL_INTERVAL = 15_000; // 15s auto-refresh

export default function MirrorsPage() {
  const [isRefreshing, setIsRefreshing] = useState(false);

  // ── Fetch all mirror addresses from both factories ──
  const {
    data: fujiMirrors,
    refetch: refetchFuji,
    isLoading: fujiLoading,
  } = useReadContract({
    address: CONTRACTS.avalancheFuji.canonicalFactory,
    abi: CANONICAL_FACTORY_ABI,
    functionName: "getAllMirrors",
    chainId: avalancheFuji.id,
    query: { refetchInterval: POLL_INTERVAL },
  });

  const {
    data: bnbMirrors,
    refetch: refetchBnb,
    isLoading: bnbLoading,
  } = useReadContract({
    address: CONTRACTS.bscTestnet.canonicalFactory,
    abi: CANONICAL_FACTORY_ABI,
    functionName: "getAllMirrors",
    chainId: bscTestnet.id,
    query: { refetchInterval: POLL_INTERVAL },
  });

  const {
    data: monadMirrors,
    refetch: refetchMonad,
    isLoading: monadLoading,
  } = useReadContract({
    address: CONTRACTS.monadTestnet.canonicalFactory,
    abi: CANONICAL_FACTORY_ABI,
    functionName: "getAllMirrors",
    chainId: monadTestnet.id,
    query: { refetchInterval: POLL_INTERVAL },
  });

  // ── Build multicall contracts for metadata reads ──
  const metadataCalls = useMemo(() => {
    const calls: {
      address: `0x${string}`;
      abi: typeof XYTHUM_TOKEN_ABI;
      functionName: "symbol" | "name" | "originContract" | "originChainId";
      chainId: number;
    }[] = [];

    const addCalls = (addresses: readonly `0x${string}`[] | undefined, chainId: number) => {
      if (!addresses) return;
      for (const addr of addresses) {
        calls.push({ address: addr, abi: XYTHUM_TOKEN_ABI, functionName: "symbol", chainId });
        calls.push({ address: addr, abi: XYTHUM_TOKEN_ABI, functionName: "name", chainId });
        calls.push({ address: addr, abi: XYTHUM_TOKEN_ABI, functionName: "originContract", chainId });
        calls.push({ address: addr, abi: XYTHUM_TOKEN_ABI, functionName: "originChainId", chainId });
      }
    };

    addCalls(fujiMirrors as readonly `0x${string}`[] | undefined, avalancheFuji.id);
    addCalls(bnbMirrors as readonly `0x${string}`[] | undefined, bscTestnet.id);
    addCalls(monadMirrors as readonly `0x${string}`[] | undefined, monadTestnet.id);

    return calls;
  }, [fujiMirrors, bnbMirrors, monadMirrors]);

  const { data: metadataResults, refetch: refetchMetadata } = useReadContracts({
    contracts: metadataCalls,
    query: {
      enabled: metadataCalls.length > 0,
      refetchInterval: POLL_INTERVAL,
    },
  });

  // ── Assemble mirror entries from results ──
  const mirrors = useMemo(() => {
    const entries: MirrorEntry[] = [];
    let resultIdx = 0;

    const processMirrors = (
      addresses: readonly `0x${string}`[] | undefined,
      targetChainId: number,
    ) => {
      if (!addresses || !metadataResults) return;
      for (const addr of addresses) {
        const symbol = metadataResults[resultIdx]?.result as string | undefined;
        const name = metadataResults[resultIdx + 1]?.result as string | undefined;
        const originContract = metadataResults[resultIdx + 2]?.result as string | undefined;
        const originChainId = metadataResults[resultIdx + 3]?.result as bigint | undefined;
        resultIdx += 4;

        if (symbol) {
          entries.push({
            address: addr,
            symbol,
            targetChainId,
            originChainId: originChainId ? Number(originChainId) : 0,
            originContract: originContract || "0x",
            status: "active",
          });
        }
      }
    };

    processMirrors(fujiMirrors as readonly `0x${string}`[] | undefined, avalancheFuji.id);
    processMirrors(bnbMirrors as readonly `0x${string}`[] | undefined, bscTestnet.id);
    processMirrors(monadMirrors as readonly `0x${string}`[] | undefined, monadTestnet.id);

    return entries;
  }, [fujiMirrors, bnbMirrors, monadMirrors, metadataResults]);

  // ── Manual refresh ──
  const handleRefresh = async () => {
    setIsRefreshing(true);
    await Promise.all([refetchFuji(), refetchBnb(), refetchMonad(), refetchMetadata()]);
    setIsRefreshing(false);
  };

  const isLoading = fujiLoading || bnbLoading || monadLoading;

  return (
    <div className="space-y-6">
      <div>
        <div className="flex items-center justify-between">
          <h1 className="text-2xl font-bold mb-2">Mirror Explorer</h1>
          <button
            onClick={handleRefresh}
            disabled={isRefreshing}
            className="text-sm px-3 py-1.5 rounded-lg bg-gray-800 border border-gray-700 text-gray-300 hover:text-white hover:border-gray-600 transition-colors disabled:opacity-50"
          >
            {isRefreshing ? "Refreshing..." : "Refresh"}
          </button>
        </div>
        <p className="text-gray-400 text-sm">
          Browse all canonical Xythum mirror tokens deployed across chains.
        </p>
        {isLoading && (
          <p className="text-xs text-yellow-400 mt-1">
            Loading mirrors from on-chain factories...
          </p>
        )}
        {!isLoading && mirrors.length > 0 && (
          <p className="text-xs text-green-400 mt-1">
            {mirrors.length} canonical mirror{mirrors.length > 1 ? "s" : ""} found on-chain
          </p>
        )}
        <p className="text-xs text-gray-500 mt-1">
          Auto-refreshes every 15 seconds. New mirrors deployed via the Attest page will appear here
          after deployment confirms on-chain.
        </p>
      </div>

      <MirrorTable mirrors={mirrors} />

      {/* Mirror details */}
      {mirrors.map((m) => (
        <div key={`${m.targetChainId}-${m.address}`} className="bg-gray-900 border border-gray-800 rounded-xl p-6">
          <h3 className="text-sm font-medium text-gray-400 mb-3">
            Mirror Details: {m.symbol}
          </h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
            <div>
              <p className="text-gray-500">Token Address</p>
              <p className="font-mono text-xs text-white break-all">{m.address}</p>
            </div>
            <div>
              <p className="text-gray-500">Symbol</p>
              <p className="text-white">{m.symbol}</p>
            </div>
            <div>
              <p className="text-gray-500">Target Chain</p>
              <p className="text-yellow-400">{getChainName(m.targetChainId)} ({m.targetChainId})</p>
            </div>
            <div>
              <p className="text-gray-500">Origin RWA</p>
              <p className="font-mono text-xs text-white break-all">{m.originContract}</p>
              <p className="text-red-400 text-xs mt-0.5">
                {getChainName(m.originChainId)} ({m.originChainId})
              </p>
            </div>
          </div>
        </div>
      ))}

      <div className="bg-gray-900/50 border border-gray-800 rounded-xl p-6">
        <h3 className="text-sm font-medium text-gray-400 mb-2">How Mirrors Work</h3>
        <ul className="text-sm text-gray-500 space-y-1 list-disc list-inside">
          <li>Each mirror is a canonical ERC-20 token on the target chain</li>
          <li>Deployed at a deterministic CREATE2 address derived from the attestation</li>
          <li>Verified by threshold signature from the signer network</li>
          <li>Compliance-enforced on every transfer via pluggable compliance contracts</li>
          <li>One mirror per origin/target chain pair (CREATE2 salt is deterministic)</li>
        </ul>
      </div>
    </div>
  );
}

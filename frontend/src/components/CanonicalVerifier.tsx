"use client";

import { useState } from "react";
import { useReadContract } from "wagmi";
import { bscTestnet, avalancheFuji } from "wagmi/chains";
import { CANONICAL_FACTORY_ABI, XYTHUM_TOKEN_ABI, CONTRACTS } from "@/lib/contracts";
import { getChainName } from "@/lib/chains";

const VERIFY_CHAINS = [
  { chain: bscTestnet, factory: CONTRACTS.bscTestnet.canonicalFactory },
  { chain: avalancheFuji, factory: CONTRACTS.avalancheFuji.canonicalFactory },
];

export function CanonicalVerifier() {
  const [address, setAddress] = useState("");
  const [checked, setChecked] = useState(false);
  const [selectedChainIdx, setSelectedChainIdx] = useState(0);

  const verifyChain = VERIFY_CHAINS[selectedChainIdx];
  const isValidAddress = /^0x[a-fA-F0-9]{40}$/.test(address);

  const { data: isCanonical, isLoading } = useReadContract({
    address: verifyChain.factory,
    abi: CANONICAL_FACTORY_ABI,
    functionName: "isCanonical",
    args: isValidAddress && checked ? [address as `0x${string}`] : undefined,
    chainId: verifyChain.chain.id,
    query: { enabled: isValidAddress && checked },
  });

  const { data: tokenName } = useReadContract({
    address: isValidAddress && checked ? (address as `0x${string}`) : undefined,
    abi: XYTHUM_TOKEN_ABI,
    functionName: "name",
    chainId: verifyChain.chain.id,
    query: { enabled: isCanonical === true },
  });

  const { data: tokenSymbol } = useReadContract({
    address: isValidAddress && checked ? (address as `0x${string}`) : undefined,
    abi: XYTHUM_TOKEN_ABI,
    functionName: "symbol",
    chainId: verifyChain.chain.id,
    query: { enabled: isCanonical === true },
  });

  const { data: originContract } = useReadContract({
    address: isValidAddress && checked ? (address as `0x${string}`) : undefined,
    abi: XYTHUM_TOKEN_ABI,
    functionName: "originContract",
    chainId: verifyChain.chain.id,
    query: { enabled: isCanonical === true },
  });

  const { data: originChainId } = useReadContract({
    address: isValidAddress && checked ? (address as `0x${string}`) : undefined,
    abi: XYTHUM_TOKEN_ABI,
    functionName: "originChainId",
    chainId: verifyChain.chain.id,
    query: { enabled: isCanonical === true },
  });

  const handleVerify = () => {
    if (isValidAddress) setChecked(true);
  };

  const handlePrefill = () => {
    if (selectedChainIdx === 0 && CONTRACTS.bscTestnet.mirrorToken) {
      setAddress(CONTRACTS.bscTestnet.mirrorToken);
    }
    setChecked(false);
  };

  return (
    <div className="bg-gray-900 border border-gray-800 rounded-xl p-6 max-w-xl">
      <h2 className="text-lg font-semibold mb-4">Verify Canonical Token</h2>
      <p className="text-sm text-gray-400 mb-4">
        Check if a token address is a canonical Xythum mirror deployed by the
        official factory.
      </p>

      {/* Chain selector */}
      <div className="mb-4">
        <label className="block text-xs text-gray-400 mb-1">Verify on chain</label>
        <div className="flex gap-2">
          {VERIFY_CHAINS.map((vc, i) => (
            <button
              key={vc.chain.id}
              onClick={() => { setSelectedChainIdx(i); setChecked(false); }}
              className={`flex-1 px-3 py-2 rounded-md text-sm transition-colors ${
                selectedChainIdx === i
                  ? "bg-brand-600 text-white"
                  : "bg-gray-800 text-gray-400 hover:text-white"
              }`}
            >
              {getChainName(vc.chain.id)}
            </button>
          ))}
        </div>
      </div>

      {/* Quick-fill */}
      {selectedChainIdx === 0 && CONTRACTS.bscTestnet.mirrorToken && (
        <button
          onClick={handlePrefill}
          className="text-xs text-brand-400 hover:text-brand-300 mb-3 underline underline-offset-2"
        >
          Try deployed mirror: {CONTRACTS.bscTestnet.mirrorToken.slice(0, 10)}...
        </button>
      )}

      <div className="flex gap-2 mb-4">
        <input
          type="text"
          placeholder="0x... token address"
          value={address}
          onChange={(e) => { setAddress(e.target.value); setChecked(false); }}
          className="flex-1 bg-gray-800 border border-gray-700 rounded-md px-3 py-2 text-sm font-mono text-white placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-brand-500"
        />
        <button
          onClick={handleVerify}
          disabled={!isValidAddress || isLoading}
          className="px-4 py-2 text-sm font-medium bg-brand-600 hover:bg-brand-700 disabled:bg-gray-700 disabled:text-gray-500 rounded-md transition-colors"
        >
          {isLoading ? "Checking..." : "Verify"}
        </button>
      </div>

      {checked && !isLoading && isCanonical !== undefined && (
        <div
          className={`p-4 rounded-lg border ${
            isCanonical
              ? "bg-green-500/10 border-green-500/30"
              : "bg-red-500/10 border-red-500/30"
          }`}
        >
          {isCanonical ? (
            <div>
              <p className="text-green-400 font-medium">Canonical Xythum Mirror</p>
              <p className="text-sm text-green-300/70 mt-1">
                This token was deployed by the official Xythum CanonicalFactory with a valid attestation.
              </p>
              <div className="mt-3 space-y-1 text-sm text-gray-300">
                {tokenName && <p>Name: <span className="text-white font-mono">{tokenName}</span></p>}
                {tokenSymbol && <p>Symbol: <span className="text-white font-mono">{tokenSymbol}</span></p>}
                {originContract && <p>Origin: <span className="text-white font-mono text-xs">{originContract}</span></p>}
                {originChainId !== undefined && (
                  <p>Origin Chain: <span className="text-white">{getChainName(Number(originChainId))} ({Number(originChainId)})</span></p>
                )}
                <p>Factory: <span className="text-white font-mono text-xs">{verifyChain.factory}</span></p>
                <p>Verified on: <span className="text-yellow-400">{getChainName(verifyChain.chain.id)}</span></p>
              </div>
            </div>
          ) : (
            <div>
              <p className="text-red-400 font-medium">Not Canonical</p>
              <p className="text-sm text-red-300/70 mt-1">
                This token was NOT deployed by the Xythum factory on {getChainName(verifyChain.chain.id)}.
              </p>
            </div>
          )}
        </div>
      )}

      <p className="text-xs text-gray-500 mt-3">
        Reading from CanonicalFactory at{" "}
        <code className="bg-gray-800 px-1 rounded text-xs">{verifyChain.factory.slice(0, 10)}...</code>{" "}
        on {getChainName(verifyChain.chain.id)} (chain {verifyChain.chain.id}).
      </p>
    </div>
  );
}

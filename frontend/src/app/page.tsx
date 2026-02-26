"use client";

import { useReadContract } from "wagmi";
import { bscTestnet, avalancheFuji } from "wagmi/chains";
import { StatCard } from "@/components/StatCard";
import { SignerHealth } from "@/components/SignerHealth";
import {
  SIGNER_REGISTRY_ABI,
  CANONICAL_FACTORY_ABI,
  CONTRACTS,
} from "@/lib/contracts";

export default function DashboardPage() {
  // ── BNB Testnet signer data ──
  const { data: bnbSignerCount } = useReadContract({
    address: CONTRACTS.bscTestnet.signerRegistry,
    abi: SIGNER_REGISTRY_ABI,
    functionName: "getSignerCount",
    chainId: bscTestnet.id,
  });

  const { data: bnbThreshold } = useReadContract({
    address: CONTRACTS.bscTestnet.signerRegistry,
    abi: SIGNER_REGISTRY_ABI,
    functionName: "threshold",
    chainId: bscTestnet.id,
  });

  // ── Fuji signer data ──
  const { data: fujiSignerCount } = useReadContract({
    address: CONTRACTS.avalancheFuji.signerRegistry,
    abi: SIGNER_REGISTRY_ABI,
    functionName: "getSignerCount",
    chainId: avalancheFuji.id,
  });

  const { data: fujiThreshold } = useReadContract({
    address: CONTRACTS.avalancheFuji.signerRegistry,
    abi: SIGNER_REGISTRY_ABI,
    functionName: "threshold",
    chainId: avalancheFuji.id,
  });

  // ── Check existing mirror on BNB ──
  const { data: bnbMirrorCanonical } = useReadContract({
    address: CONTRACTS.bscTestnet.canonicalFactory,
    abi: CANONICAL_FACTORY_ABI,
    functionName: "isCanonical",
    args: [CONTRACTS.bscTestnet.mirrorToken!],
    chainId: bscTestnet.id,
    query: { enabled: !!CONTRACTS.bscTestnet.mirrorToken },
  });

  const bnbSigners = bnbSignerCount ? Number(bnbSignerCount) : 0;
  const bnbThresholdVal = bnbThreshold ? Number(bnbThreshold) : 0;
  const fujiSigners = fujiSignerCount ? Number(fujiSignerCount) : 0;
  const fujiThresholdVal = fujiThreshold ? Number(fujiThreshold) : 0;
  const mirrorsOnBnb = bnbMirrorCanonical ? 1 : 0;

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-bold mb-2">Xythum RWA Passport</h1>
        <p className="text-gray-400">
          One original RWA &mdash; Native &amp; trusted on every chain.
        </p>
        <p className="text-xs text-gray-500 mt-1">
          Bidirectional: Avalanche Fuji &harr; BNB Chain Testnet | Live on-chain data
        </p>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          title="Mirrors on BNB"
          value={String(mirrorsOnBnb)}
          subtitle="Canonical mirrors deployed"
        />
        <StatCard
          title="Total Value Attested"
          value="$1,000,000"
          subtitle="MockRWA locked amount"
          color="text-green-400"
        />
        <StatCard
          title="Signers (BNB)"
          value={bnbThresholdVal ? `${bnbThresholdVal}/${bnbSigners}` : "..."}
          subtitle="Threshold / registered"
          color="text-purple-400"
        />
        <StatCard
          title="Signers (Fuji)"
          value={fujiThresholdVal ? `${fujiThresholdVal}/${fujiSigners}` : "..."}
          subtitle="Threshold / registered"
          color="text-cyan-400"
        />
      </div>

      {/* Chain Status */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {/* BNB Testnet */}
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
          <div className="flex items-center gap-2 mb-3">
            <span className="w-2 h-2 rounded-full bg-yellow-400"></span>
            <h3 className="text-sm font-medium text-gray-400">BNB Chain Testnet (chain 97)</h3>
          </div>
          <SignerHealth
            activeSigners={bnbSigners}
            totalSigners={bnbSigners}
            threshold={bnbThresholdVal}
          />
          <div className="mt-3 space-y-2 text-xs text-gray-400">
            <div className="flex justify-between">
              <span>CanonicalFactory</span>
              <span className="font-mono text-white">{CONTRACTS.bscTestnet.canonicalFactory.slice(0, 14)}...</span>
            </div>
            <div className="flex justify-between">
              <span>CCIPReceiver (from Fuji)</span>
              <span className="font-mono text-white">{CONTRACTS.bscTestnet.ccipReceiver?.slice(0, 14)}...</span>
            </div>
            <div className="flex justify-between">
              <span>CCIPSender (to Fuji)</span>
              <span className="font-mono text-white">{CONTRACTS.bscTestnet.ccipSender?.slice(0, 14)}...</span>
            </div>
            {CONTRACTS.bscTestnet.mirrorToken && (
              <div className="flex justify-between">
                <span>Mirror Token (xRWA)</span>
                <span className="font-mono text-green-400">{CONTRACTS.bscTestnet.mirrorToken.slice(0, 14)}...</span>
              </div>
            )}
          </div>
        </div>

        {/* Avalanche Fuji */}
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
          <div className="flex items-center gap-2 mb-3">
            <span className="w-2 h-2 rounded-full bg-red-400"></span>
            <h3 className="text-sm font-medium text-gray-400">Avalanche Fuji (chain 43113)</h3>
          </div>
          <SignerHealth
            activeSigners={fujiSigners}
            totalSigners={fujiSigners}
            threshold={fujiThresholdVal}
          />
          <div className="mt-3 space-y-2 text-xs text-gray-400">
            <div className="flex justify-between">
              <span>CanonicalFactory</span>
              <span className="font-mono text-white">{CONTRACTS.avalancheFuji.canonicalFactory.slice(0, 14)}...</span>
            </div>
            <div className="flex justify-between">
              <span>CCIPSender (to BNB)</span>
              <span className="font-mono text-white">{CONTRACTS.avalancheFuji.ccipSender?.slice(0, 14)}...</span>
            </div>
            <div className="flex justify-between">
              <span>CCIPReceiver (from BNB)</span>
              <span className="font-mono text-white">{CONTRACTS.avalancheFuji.ccipReceiver?.slice(0, 14)}...</span>
            </div>
            <div className="flex justify-between">
              <span>MockRWA (mTBILL)</span>
              <span className="font-mono text-white">{CONTRACTS.avalancheFuji.mockRwa?.slice(0, 14)}...</span>
            </div>
          </div>
        </div>
      </div>

      {/* Architecture */}
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
        <h3 className="text-sm font-medium text-gray-400 mb-4">
          Bidirectional Protocol Architecture
        </h3>
        <pre className="text-xs text-gray-500 font-mono leading-relaxed overflow-x-auto">
{`Avalanche Fuji (43113)              BNB Chain Testnet (97)
+-------------------+              +-------------------+
| MockRWA (mTBILL)  |              | MockRWA (mTBILL)  |
+--------+----------+              +--------+----------+
         |                                  |
    [Attestation]                      [Attestation]
         |                                  |
+--------v----------+              +--------v----------+
| AttestationRegistry|              | AttestationRegistry|
| (3/3 Threshold)   |              | (3/3 Threshold)   |
+--------+----------+              +--------+----------+
         |                                  |
+--------v----------+              +--------v----------+
| CCIPSender        +--- CCIP --->+ CCIPReceiver       |
|                   |              +--------+----------+
| CCIPReceiver      +<-- CCIP ----+ CCIPSender         |
+--------+----------+              +--------+----------+
         |                                  |
+--------v----------+              +--------v----------+
| CanonicalFactory  |              | CanonicalFactory   |
| (CREATE2 Deploy)  |              | (CREATE2 Deploy)   |
+-------------------+              +-------------------+`}
        </pre>
      </div>
    </div>
  );
}

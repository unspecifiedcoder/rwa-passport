"use client";

import { useReadContract } from "wagmi";
import { bscTestnet, avalancheFuji } from "wagmi/chains";
import { MirrorTable, type MirrorEntry } from "@/components/MirrorTable";
import { XYTHUM_TOKEN_ABI, CANONICAL_FACTORY_ABI, CONTRACTS } from "@/lib/contracts";
import { getChainName } from "@/lib/chains";

export default function MirrorsPage() {
  // ── Known mirror on BNB Testnet ──
  const bnbMirrorAddr = CONTRACTS.bscTestnet.mirrorToken as `0x${string}`;

  const { data: bnbIsCanonical } = useReadContract({
    address: CONTRACTS.bscTestnet.canonicalFactory,
    abi: CANONICAL_FACTORY_ABI,
    functionName: "isCanonical",
    args: [bnbMirrorAddr],
    chainId: bscTestnet.id,
  });

  const { data: bnbName } = useReadContract({
    address: bnbMirrorAddr,
    abi: XYTHUM_TOKEN_ABI,
    functionName: "name",
    chainId: bscTestnet.id,
  });

  const { data: bnbSymbol } = useReadContract({
    address: bnbMirrorAddr,
    abi: XYTHUM_TOKEN_ABI,
    functionName: "symbol",
    chainId: bscTestnet.id,
  });

  const { data: bnbOriginContract } = useReadContract({
    address: bnbMirrorAddr,
    abi: XYTHUM_TOKEN_ABI,
    functionName: "originContract",
    chainId: bscTestnet.id,
  });

  const { data: bnbOriginChainId } = useReadContract({
    address: bnbMirrorAddr,
    abi: XYTHUM_TOKEN_ABI,
    functionName: "originChainId",
    chainId: bscTestnet.id,
  });

  // Build mirror entries
  const mirrors: MirrorEntry[] = [];

  if (bnbIsCanonical && bnbSymbol) {
    mirrors.push({
      address: bnbMirrorAddr,
      symbol: bnbSymbol,
      targetChainId: bscTestnet.id,
      originChainId: bnbOriginChainId ? Number(bnbOriginChainId) : avalancheFuji.id,
      originContract: bnbOriginContract || CONTRACTS.avalancheFuji.mockRwa || "0x",
      status: "active",
    });
  }

  // TODO: In a production version, we'd scan MirrorDeployed events from both factories
  // to dynamically discover all mirrors. For the testnet demo, we enumerate known mirrors.

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold mb-2">Mirror Explorer</h1>
        <p className="text-gray-400 text-sm">
          Browse all canonical Xythum mirror tokens deployed across chains.
        </p>
        {mirrors.length > 0 && (
          <p className="text-xs text-green-400 mt-1">
            {mirrors.length} canonical mirror{mirrors.length > 1 ? "s" : ""} found on-chain
          </p>
        )}
        <p className="text-xs text-gray-500 mt-1">
          New mirrors deployed via the Attest page will appear here after CCIP delivery (~20-35 min).
          Refresh the page to check for newly deployed mirrors.
        </p>
      </div>

      <MirrorTable mirrors={mirrors} />

      {/* Mirror details */}
      {mirrors.map((m) => (
        <div key={m.address} className="bg-gray-900 border border-gray-800 rounded-xl p-6">
          <h3 className="text-sm font-medium text-gray-400 mb-3">
            Mirror Details: {m.symbol}
          </h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
            <div>
              <p className="text-gray-500">Token Address</p>
              <p className="font-mono text-xs text-white break-all">{m.address}</p>
            </div>
            <div>
              <p className="text-gray-500">Name / Symbol</p>
              <p className="text-white">
                {m.address === bnbMirrorAddr ? bnbName : "..."} ({m.symbol})
              </p>
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

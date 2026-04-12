"use client";

import { useEffect, useState } from "react";
import { useAccount, useReadContracts } from "wagmi";
import { formatEther } from "viem";

import {
  CONTRACTS,
  RWA_LOCK_ESCROW_ABI,
  CANONICAL_FACTORY_MINT_FROM_LOCK_ABI,
} from "@/lib/contracts";
import { getChainName } from "@/lib/chains";
import { TerminalPanel } from "@/components/primitives/TerminalPanel";
import { Hash } from "@/components/primitives/Hash";

const STORAGE_KEY = "xythum.lockHistory.v1";

export interface LockEntry {
  lockId: `0x${string}`;
  amount: string; // wei string
  rwaToken: `0x${string}`;
  originChainId: number;
  targetChainId: number;
  createdAt: number; // unix seconds
  mirror?: `0x${string}`; // populated after mintFromLock succeeds on target
}

type ChainSlug = keyof typeof CONTRACTS;

function chainSlugFor(id: number): ChainSlug | undefined {
  if (id === 43113) return "avalancheFuji";
  if (id === 97) return "bscTestnet";
  if (id === 10143) return "monadTestnet";
  return undefined;
}

export function loadLockHistory(): LockEntry[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as LockEntry[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export function saveLockHistory(entries: LockEntry[]) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(entries));
}

export function appendLock(entry: LockEntry) {
  const cur = loadLockHistory();
  if (cur.find((e) => e.lockId.toLowerCase() === entry.lockId.toLowerCase())) return;
  saveLockHistory([entry, ...cur].slice(0, 25));
}

/// Update the mirror address on an existing lock entry (called post-mintFromLock).
export function setMirrorForLock(lockId: `0x${string}`, mirror: `0x${string}`) {
  const cur = loadLockHistory();
  const idx = cur.findIndex((e) => e.lockId.toLowerCase() === lockId.toLowerCase());
  if (idx === -1) return;
  cur[idx] = { ...cur[idx], mirror };
  saveLockHistory(cur);
}

export function MyLocks() {
  const { address } = useAccount();
  const [entries, setEntries] = useState<LockEntry[]>([]);

  useEffect(() => {
    setEntries(loadLockHistory());
    const onStorage = () => setEntries(loadLockHistory());
    window.addEventListener("storage", onStorage);
    const interval = setInterval(() => setEntries(loadLockHistory()), 2000);
    return () => {
      window.removeEventListener("storage", onStorage);
      clearInterval(interval);
    };
  }, []);

  // Build batch calls: per entry, query escrow.lockState + factory.mintedFromLock.
  const calls = entries.flatMap((e) => {
    const originSlug = chainSlugFor(e.originChainId);
    const targetSlug = chainSlugFor(e.targetChainId);
    const escrow = originSlug ? CONTRACTS[originSlug].lockEscrow : undefined;
    const factory = targetSlug ? CONTRACTS[targetSlug].canonicalFactory : undefined;
    return [
      escrow
        ? {
            address: escrow,
            abi: RWA_LOCK_ESCROW_ABI,
            functionName: "lockState" as const,
            args: [e.lockId] as const,
            chainId: e.originChainId,
          }
        : null,
      factory
        ? {
            address: factory,
            abi: CANONICAL_FACTORY_MINT_FROM_LOCK_ABI,
            functionName: "mintedFromLock" as const,
            args: [e.lockId] as const,
            chainId: e.targetChainId,
          }
        : null,
    ].filter(Boolean) as {
      address: `0x${string}`;
      abi: typeof RWA_LOCK_ESCROW_ABI | typeof CANONICAL_FACTORY_MINT_FROM_LOCK_ABI;
      functionName: "lockState" | "mintedFromLock";
      args: readonly [`0x${string}`];
      chainId: number;
    }[];
  });

  const { data: results } = useReadContracts({
    contracts: calls,
    query: { enabled: calls.length > 0, refetchInterval: 8000 },
  });

  if (!address || entries.length === 0) return null;

  return (
    <TerminalPanel label="MY LOCKS · LOCAL HISTORY" status="live" meta="POLLING · 8s">
      <div className="divide-y divide-cover-3">
        {entries.map((e, i) => {
          const lockState = results?.[i * 2]?.result as
            | readonly [string, string, bigint, bigint, boolean]
            | undefined;
          const mintedFromLock = results?.[i * 2 + 1]?.result as boolean | undefined;
          const released = lockState?.[4] ?? false;
          const minted = !!mintedFromLock;

          let status: "LOCKED" | "MINTED" | "RELEASED" = "LOCKED";
          if (released) status = "RELEASED";
          else if (minted) status = "MINTED";

          return (
            <div
              key={e.lockId}
              className="grid grid-cols-12 gap-3 px-5 py-4 items-center"
            >
              <div className="col-span-12 md:col-span-2">
                <StatusPill status={status} />
              </div>
              <div className="col-span-12 md:col-span-3 font-mono text-[11px] text-ink-page">
                <div>
                  <Hash addr={e.lockId} chainId={e.originChainId} kind="tx" prefix={10} />
                </div>
                <div className="text-ink-faint text-[9px] uppercase tracking-stamp mt-1">
                  LOCK ID
                </div>
                {e.mirror && (
                  <>
                    <div className="mt-2">
                      <Hash addr={e.mirror} chainId={e.targetChainId} kind="address" prefix={10} />
                    </div>
                    <div className="text-ink-faint text-[9px] uppercase tracking-stamp mt-1">
                      MIRROR (TARGET)
                    </div>
                  </>
                )}
              </div>
              <div className="col-span-6 md:col-span-2 font-mono text-[11px] text-ink-page">
                <div>
                  {formatEther(BigInt(e.amount))}{" "}
                  <span className="text-ink-faint text-[9px] uppercase tracking-stamp">
                    MTBILL
                  </span>
                </div>
                <div className="text-ink-faint text-[9px] uppercase tracking-stamp mt-1">
                  AMOUNT
                </div>
              </div>
              <div className="col-span-6 md:col-span-5 font-mono text-[10px] text-ink-muted text-right">
                {getChainName(e.originChainId)} →{" "}
                {getChainName(e.targetChainId)}
                <div className="text-ink-faint text-[8px] uppercase tracking-stamp mt-1">
                  {new Date(e.createdAt * 1000).toLocaleString()}
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </TerminalPanel>
  );
}

function StatusPill({ status }: { status: "LOCKED" | "MINTED" | "RELEASED" }) {
  const map = {
    LOCKED: { bg: "bg-wax-0/15", border: "border-wax-0", text: "text-wax-0" },
    MINTED: { bg: "bg-leaf-0/15", border: "border-leaf-0", text: "text-leaf-0" },
    RELEASED: { bg: "bg-verde-0/15", border: "border-verde-0", text: "text-verde-0" },
  } as const;
  const c = map[status];
  return (
    <span
      className={`inline-block px-3 py-1 border ${c.bg} ${c.border} ${c.text} font-mono text-[10px] uppercase tracking-stamp`}
    >
      {status}
    </span>
  );
}

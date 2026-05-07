"use client";

import { useReadContract, useReadContracts } from "wagmi";
import { bscTestnet, avalancheFuji } from "wagmi/chains";
import { MirrorTable, type MirrorEntry } from "@/components/MirrorTable";
import { XYTHUM_TOKEN_ABI, CANONICAL_FACTORY_ABI, CONTRACTS } from "@/lib/contracts";
import { monadTestnet } from "@/lib/chains";
import { useState, useMemo, useEffect, useRef } from "react";
import { PageHeader } from "@/components/primitives/PageHeader";
import { PaperButton } from "@/components/primitives/PaperButton";
import { TerminalPanel } from "@/components/primitives/TerminalPanel";
import { Numeric } from "@/components/primitives/Numeric";

const POLL_INTERVAL = 15_000;

export default function MirrorsPage() {
  const [isRefreshing, setIsRefreshing] = useState(false);

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

  const mirrors = useMemo(() => {
    const entries: (MirrorEntry & { deployIndex: number })[] = [];
    let resultIdx = 0;

    const processMirrors = (
      addresses: readonly `0x${string}`[] | undefined,
      targetChainId: number,
    ) => {
      if (!addresses || !metadataResults) return;
      addresses.forEach((addr, i) => {
        const symbol = metadataResults[resultIdx]?.result as string | undefined;
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
            // higher index = more recent (factory pushes in order)
            deployIndex: i,
          });
        }
      });
    };

    processMirrors(fujiMirrors as readonly `0x${string}`[] | undefined, avalancheFuji.id);
    processMirrors(bnbMirrors as readonly `0x${string}`[] | undefined, bscTestnet.id);
    processMirrors(monadMirrors as readonly `0x${string}`[] | undefined, monadTestnet.id);

    // Sort by deployIndex desc per chain → newest first within each chain.
    // Then interleave by chain so the very latest from any chain bubbles up.
    return entries.sort((a, b) => {
      if (a.targetChainId !== b.targetChainId) {
        return b.deployIndex - a.deployIndex;
      }
      return b.deployIndex - a.deployIndex;
    });
  }, [fujiMirrors, bnbMirrors, monadMirrors, metadataResults]);

  // Track which mirror addresses are new since the last render — flag them
  // for a one-shot "fresh" highlight + stamp animation.
  const seenAddrs = useRef<Set<string>>(new Set());
  const [freshAddrs, setFreshAddrs] = useState<Set<string>>(new Set());
  useEffect(() => {
    const currentAddrs = new Set(mirrors.map((m) => m.address));
    const newOnes = new Set<string>();
    for (const a of currentAddrs) {
      if (!seenAddrs.current.has(a)) newOnes.add(a);
    }
    if (seenAddrs.current.size > 0 && newOnes.size > 0) {
      setFreshAddrs(newOnes);
      const t = setTimeout(() => setFreshAddrs(new Set()), 4500);
      seenAddrs.current = currentAddrs;
      return () => clearTimeout(t);
    }
    seenAddrs.current = currentAddrs;
  }, [mirrors]);

  const handleRefresh = async () => {
    setIsRefreshing(true);
    await Promise.all([refetchFuji(), refetchBnb(), refetchMonad(), refetchMetadata()]);
    setIsRefreshing(false);
  };

  const isLoading = fujiLoading || bnbLoading || monadLoading;

  const fujiCount = (fujiMirrors as readonly unknown[] | undefined)?.length ?? 0;
  const bnbCount = (bnbMirrors as readonly unknown[] | undefined)?.length ?? 0;
  const monadCount = (monadMirrors as readonly unknown[] | undefined)?.length ?? 0;

  return (
    <div className="space-y-10">
      <PageHeader
        article="ARTICLE VI"
        kicker="OFFICE OF THE REGISTRAR"
        title={
          <>
            The mirror <em className="italic">registry</em>.
          </>
        }
        lede={
          <>
            A live ledger of every canonical mirror issued by the protocol,
            across every target chain. Auto-refreshes every fifteen seconds.
          </>
        }
        stamp={{
          text: isLoading ? "FETCHING" : `${mirrors.length} ENTRIES`,
          meta: "TRI-CHAIN · LIVE",
          tone: "leaf",
        }}
        meta={
          <PaperButton tone="ghost" size="sm" disabled={isRefreshing} onClick={handleRefresh}>
            {isRefreshing ? "Refreshing…" : "↻ Refresh"}
          </PaperButton>
        }
      />

      {/* Per-chain counts */}
      <section className="grid grid-cols-12 gap-px bg-cover-3 border border-cover-3">
        <ChainStat name="AVALANCHE FUJI" id={43113} count={fujiCount} tone="wax" />
        <ChainStat name="BNB TESTNET" id={97} count={bnbCount} tone="leaf" />
        <ChainStat name="MONAD TESTNET" id={10143} count={monadCount} tone="verde" />
      </section>

      {!isLoading && mirrors.length === 0 && (
        <div className="bg-leaf-0/5 border-2 border-leaf-1 border-dashed px-6 py-5 font-mono text-[12px] text-ink-page">
          <div className="text-leaf-0 text-[10px] uppercase tracking-stamp mb-2">
            FRESH FACTORY DEPLOYMENT · NO MIRRORS YET
          </div>
          <p className="font-body text-[13px] text-ink-muted leading-relaxed">
            The CanonicalFactory contracts on all three chains were redeployed
            with the new <code className="text-ink-page">mintFromLock</code>{" "}
            entry-point. The registry below is empty because the new factories
            haven&apos;t issued any mirrors yet.{" "}
            <a href="/attest" className="text-leaf-0 underline hover:text-leaf-1">
              Issue a fresh mirror via /attest →
            </a>{" "}
            or run the round-trip flow on{" "}
            <a href="/lock" className="text-leaf-0 underline hover:text-leaf-1">
              /lock
            </a>{" "}
            to populate this list.
          </p>
        </div>
      )}

      <MirrorTable mirrors={mirrors} freshAddrs={freshAddrs} />

      {/* Detailed cards — also recent-first */}
      {mirrors.length > 0 && (
        <section>
          <div className="flex items-baseline justify-between mb-4">
            <div className="font-mono text-[10px] uppercase tracking-stamp text-leaf-2">
              §  ACTIVITY · NEWEST FIRST
            </div>
            <div className="font-mono text-[9px] uppercase tracking-stamp text-ink-faint">
              {freshAddrs.size > 0 ? `${freshAddrs.size} JUST ISSUED` : "POLLING · 15s"}
            </div>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {mirrors.map((m, idx) => (
              <MirrorCard
                key={`${m.targetChainId}-${m.address}`}
                mirror={m}
                isFresh={freshAddrs.has(m.address)}
                rank={idx + 1}
              />
            ))}
          </div>
        </section>
      )}

      <section className="grid grid-cols-12 gap-6">
        <div className="col-span-12 lg:col-span-7">
          <TerminalPanel label="HOW THE REGISTRY WORKS" status="idle">
            <div className="p-6 space-y-3 text-[13px] text-ink-page leading-relaxed font-body">
              <Item>Each mirror is a canonical ERC-20 on its target chain.</Item>
              <Item>
                Deployed at a deterministic CREATE2 address derived from the
                attestation tuple — predictable before deployment.
              </Item>
              <Item>
                Issued only against a threshold-signed attestation (3-of-5
                ECDSA, EIP-712 typed data).
              </Item>
              <Item>
                One mirror per (origin · srcChain · dstChain) triple. Salt
                guarantees uniqueness.
              </Item>
            </div>
          </TerminalPanel>
        </div>
        <div className="col-span-12 lg:col-span-5">
          <div className="parchment passport-corner p-6 h-full">
            <div className="font-mono text-[9px] uppercase tracking-stamp text-leaf-2 mb-2">
              REGISTRY GUARANTEE
            </div>
            <div className="font-display italic text-2xl md:text-3xl text-ink-deep leading-tight">
              &ldquo;The registry is the source of truth. Look up the address —
              if it isn&apos;t here, it isn&apos;t a mirror.&rdquo;
            </div>
            <div className="mt-4 font-mono text-[9px] uppercase tracking-stamp text-ink-deep/50">
              REGISTRAR · OFFICIAL SEAL
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}

function ChainStat({
  name,
  id,
  count,
  tone,
}: {
  name: string;
  id: number;
  count: number;
  tone: "wax" | "leaf" | "verde";
}) {
  const dot = tone === "wax" ? "bg-wax-0" : tone === "leaf" ? "bg-leaf-0" : "bg-verde-0";
  return (
    <div className="col-span-12 md:col-span-4 bg-cover-1 px-6 py-5 flex items-center justify-between">
      <div>
        <div className="font-mono text-[9px] uppercase tracking-stamp text-ink-muted flex items-center gap-2">
          <span className={`w-1.5 h-1.5 rounded-full ${dot} pulse-leaf`} />
          {name}
        </div>
        <div className="font-mono text-[9px] uppercase tracking-stamp text-ink-faint mt-1">
          CHAIN № {id}
        </div>
      </div>
      <Numeric value={count} size="xl" tone={tone} embossed />
    </div>
  );
}

function Item({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex gap-3">
      <span className="font-display italic text-leaf-1 text-lg leading-none flex-shrink-0">※</span>
      <span>{children}</span>
    </div>
  );
}

function MirrorCard({
  mirror,
  isFresh,
  rank,
}: {
  mirror: MirrorEntry;
  isFresh?: boolean;
  rank?: number;
}) {
  const targetTone =
    mirror.targetChainId === 97 ? "leaf" : mirror.targetChainId === 43113 ? "wax" : "verde";
  const targetColor =
    targetTone === "leaf" ? "text-leaf-0" : targetTone === "wax" ? "text-wax-0" : "text-verde-0";

  return (
    <div
      className={`parchment passport-corner-tr p-6 relative overflow-hidden ${
        isFresh ? "ring-2 ring-verde-0 ring-offset-2 ring-offset-cover-0" : ""
      }`}
    >
      <div className="absolute top-3 right-3">
        {isFresh ? (
          <div className="stamp stamp-fresh text-verde-0 text-[10px] tracking-stamp">
            <span className="block leading-tight">JUST ISSUED</span>
            <span className="block leading-none text-[7px] mt-0.5 opacity-80">
              REGISTRY № {mirror.targetChainId}
            </span>
          </div>
        ) : (
          <div className="stamp text-verde-0 text-[10px] tracking-stamp">
            <span className="block leading-tight">CANONICAL</span>
            <span className="block leading-none text-[7px] mt-0.5 opacity-80">
              REGISTRY № {mirror.targetChainId}
            </span>
          </div>
        )}
      </div>
      <div className="font-mono text-[9px] uppercase tracking-stamp text-ink-deep/55 flex items-center gap-2">
        {rank && <span className="text-leaf-1">#{String(rank).padStart(2, "0")}</span>}
        <span>ISSUED MIRROR · NO. {mirror.address.slice(2, 8).toUpperCase()}</span>
      </div>
      <div className={`font-display text-5xl ${targetColor} leading-none mt-1`}>
        {mirror.symbol}
      </div>
      <div className="mt-4 pt-4 border-t border-ink-deep/15 space-y-2 font-mono text-[11px] text-ink-deep">
        <Row label="ADDRESS" value={mirror.address} />
        <Row label="ORIGIN" value={mirror.originContract} />
        <Row label="SOURCE CHAIN" value={`№ ${mirror.originChainId}`} />
        <Row label="TARGET CHAIN" value={`№ ${mirror.targetChainId}`} />
      </div>
      <div className="mt-5 flex items-end justify-between">
        <span className="microprint">XYTHUM·MIRROR·CANONICAL·VERIFIED·</span>
        <div className="wax-seal w-8 h-8" />
      </div>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <span className="font-mono text-[9px] uppercase tracking-stamp text-ink-deep/50">{label}</span>
      <span className="font-mono text-[10px] text-ink-deep truncate">
        {value.length > 28 ? `${value.slice(0, 14)}…${value.slice(-6)}` : value}
      </span>
    </div>
  );
}

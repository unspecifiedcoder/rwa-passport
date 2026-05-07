"use client";

import { useReadContract } from "wagmi";
import { bscTestnet, avalancheFuji } from "wagmi/chains";
import {
  SIGNER_REGISTRY_ABI,
  CANONICAL_FACTORY_ABI,
  CONTRACTS,
} from "@/lib/contracts";
import { monadTestnet } from "@/lib/chains";
import { TerminalPanel } from "@/components/primitives/TerminalPanel";
import { Hash } from "@/components/primitives/Hash";
import { Numeric } from "@/components/primitives/Numeric";
import { SignerBitmap } from "@/components/primitives/SignerBitmap";
import { ChainBadge } from "@/components/ChainBadge";
import { Stamp } from "@/components/primitives/Stamp";

type ChainSlug = "bscTestnet" | "avalancheFuji" | "monadTestnet";

const CHAIN_META: Record<ChainSlug, { id: number; name: string }> = {
  bscTestnet: { id: 97, name: "BNB TESTNET" },
  avalancheFuji: { id: 43113, name: "AVALANCHE FUJI" },
  monadTestnet: { id: 10143, name: "MONAD TESTNET" },
};

export default function PulsePage() {
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
  const { data: bnbMirrorCount } = useReadContract({
    address: CONTRACTS.bscTestnet.canonicalFactory,
    abi: CANONICAL_FACTORY_ABI,
    functionName: "getMirrorCount",
    chainId: bscTestnet.id,
  });
  const { data: fujiMirrorCount } = useReadContract({
    address: CONTRACTS.avalancheFuji.canonicalFactory,
    abi: CANONICAL_FACTORY_ABI,
    functionName: "getMirrorCount",
    chainId: avalancheFuji.id,
  });
  const { data: monadMirrorCount } = useReadContract({
    address: CONTRACTS.monadTestnet.canonicalFactory,
    abi: CANONICAL_FACTORY_ABI,
    functionName: "getMirrorCount",
    chainId: monadTestnet.id,
  });

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

  const { data: monadSignerCount } = useReadContract({
    address: CONTRACTS.monadTestnet.signerRegistry,
    abi: SIGNER_REGISTRY_ABI,
    functionName: "getSignerCount",
    chainId: monadTestnet.id,
  });
  const { data: monadThreshold } = useReadContract({
    address: CONTRACTS.monadTestnet.signerRegistry,
    abi: SIGNER_REGISTRY_ABI,
    functionName: "threshold",
    chainId: monadTestnet.id,
  });

  const chains: Array<{
    slug: ChainSlug;
    signers: number;
    threshold: number;
  }> = [
    { slug: "bscTestnet", signers: Number(bnbSignerCount ?? 0), threshold: Number(bnbThreshold ?? 0) },
    { slug: "avalancheFuji", signers: Number(fujiSignerCount ?? 0), threshold: Number(fujiThreshold ?? 0) },
    { slug: "monadTestnet", signers: Number(monadSignerCount ?? 0), threshold: Number(monadThreshold ?? 0) },
  ];

  const totalSigners = chains.reduce((a, c) => a + c.signers, 0);
  const mirrorsLive =
    Number(bnbMirrorCount ?? 0) +
    Number(fujiMirrorCount ?? 0) +
    Number(monadMirrorCount ?? 0);

  return (
    <div className="space-y-16">
      {/* ═══ HERO ════════════════════════════════════════════════════ */}
      <section className="relative overflow-hidden">
        <span className="watermark top-12 right-8" aria-hidden>X</span>
        <div className="grid grid-cols-12 gap-8 items-end">
          <div className="col-span-12 lg:col-span-8 relative z-10">
            <div className="font-mono text-[10px] uppercase tracking-stamp text-leaf-1 mb-4 flex items-center gap-2">
              <span className="w-1 h-1 bg-verde-0 pulse-leaf" />
              ISSUED · CROSS-CHAIN PROTOCOL · NO. 0001
            </div>
            <h1 className="font-display text-[clamp(48px,8vw,108px)] leading-[0.92] tracking-tight text-ink-page">
              One original asset.
              <br />
              <em className="italic text-leaf-0">Native</em> on every chain.
            </h1>
            <p className="font-body text-[15px] md:text-[17px] text-ink-muted mt-6 max-w-xl leading-relaxed">
              Xythum issues a cryptographic passport for real-world assets. A
              threshold-signed attestation deploys a deterministic mirror at the
              same address on every EVM chain. No bridges. No wrapped tokens.
              No fork ambiguity. <em className="italic text-leaf-0/80">Verified by mathematics.</em>
            </p>
            <div className="flex items-center gap-6 mt-8">
              <Stamp text="VERIFIED" meta="3 / 5 ECDSA THRESHOLD" tone="verde" />
              <Stamp text="CANONICAL" meta="CREATE2 DETERMINISTIC" tone="wax" />
              <Stamp text="ISSUED" meta="TRI-CHAIN" tone="leaf" />
            </div>
          </div>

          {/* Right cover panel */}
          <aside className="col-span-12 lg:col-span-4 relative z-10">
            <div className="parchment passport-corner-tr p-6 relative">
              <div className="font-mono text-[8px] uppercase tracking-stamp text-ink-deep/50 mb-4 flex items-center justify-between">
                <span>BEARER · PROTOCOL STATE</span>
                <span>BLOCK · LIVE</span>
              </div>
              <div className="space-y-5">
                <KPI label="MIRRORS ISSUED" value={mirrorsLive} note="ACROSS TARGET CHAINS" tone="wax" />
                <hr className="border-ink-deep/15" />
                <KPI label="ENDORSING SIGNERS" value={totalSigners} note="REGISTERED · TRI-CHAIN" tone="leaf" />
                <hr className="border-ink-deep/15" />
                <KPI label="CHAINS WIRED" value={3} note="FUJI · BNB · MONAD" tone="verde" />
              </div>
              <div className="mt-6 pt-4 border-t border-ink-deep/20 flex items-center justify-between font-mono text-[8px] uppercase tracking-stamp text-ink-deep/60">
                <span>ISSUING AUTHORITY</span>
                <span className="font-display text-base text-wax-0">⌒X⌒</span>
              </div>
            </div>
          </aside>
        </div>
      </section>

      {/* ═══ THE WEDGE — 10-second explainer ════════════════════════ */}
      <section className="grid grid-cols-12 gap-6">
        <header className="col-span-12 mb-2">
          <div className="flex items-end justify-between border-b border-cover-3 pb-3">
            <div>
              <div className="font-mono text-[9px] uppercase tracking-stamp text-leaf-2 mb-2">
                ARTICLE I · WHAT THIS IS
              </div>
              <h2 className="font-display text-3xl md:text-4xl text-ink-page leading-none">
                <em className="italic">Lock</em> on chain A · <em className="italic">Mint</em> on chain B · <em className="italic">Burn</em> · <em className="italic">Redeem</em>.
              </h2>
            </div>
            <div className="font-mono text-[9px] uppercase tracking-stamp text-ink-muted text-right">
              ~30 SECONDS · ROUND TRIP<br />
              <span className="text-leaf-1">VS. 40–70 MIN VIA CCIP</span>
            </div>
          </div>
        </header>

        <div className="col-span-12">
          <TerminalPanel label="ROUND-TRIP PRIMITIVE" status="live" meta="MONAD ↔ FUJI ↔ BNB">
            <div className="grid grid-cols-1 md:grid-cols-4 divide-y md:divide-y-0 md:divide-x divide-cover-3">
              <Step
                idx="1"
                title="Lock"
                body="Original RWA enters escrow on the origin chain. One lockId tags the deposit. One-shot."
                tone="wax"
              />
              <Step
                idx="2"
                title="Mint"
                body="3-of-5 signers attest the lock. Factory on the target chain CREATE2-deploys a 1:1 mirror ERC-20 in one tx. Use it in any DeFi protocol."
                tone="leaf"
              />
              <Step
                idx="3"
                title="Burn"
                body="When done, burn the mirror against the original lockId. Signal to signers: release the original."
                tone="wax"
              />
              <Step
                idx="4"
                title="Redeem"
                body="Signers attest the burn. Escrow on origin chain releases the original RWA back to the user."
                tone="verde"
              />
            </div>
            <div className="px-6 py-4 border-t border-cover-3 flex items-center justify-between font-mono text-[11px]">
              <span className="text-ink-muted">
                NO BRIDGE · NO WRAPPED TOKEN · NO FEE PER HOP · NO DON LATENCY
              </span>
              <a
                href="/lock"
                className="text-leaf-0 hover:text-leaf-1 transition-colors uppercase tracking-stamp text-[10px]"
              >
                ▶ Try the demo →
              </a>
            </div>
          </TerminalPanel>
        </div>
      </section>

      {/* ═══ ENDORSEMENTS ═══════════════════════════════════════════ */}
      <section className="grid grid-cols-12 gap-6">
        <header className="col-span-12 mb-2">
          <div className="flex items-end justify-between border-b border-cover-3 pb-3">
            <div>
              <div className="font-mono text-[9px] uppercase tracking-stamp text-leaf-2 mb-2">
                ARTICLE II
              </div>
              <h2 className="font-display text-3xl md:text-4xl text-ink-page leading-none">
                <em className="italic">Endorsements</em> · per chain
              </h2>
            </div>
            <div className="font-mono text-[9px] uppercase tracking-stamp text-ink-muted text-right">
              3-OF-N THRESHOLD ECDSA<br />
              <span className="text-leaf-1">EIP-712 TYPED DATA</span>
            </div>
          </div>
        </header>

        <div className="col-span-12">
          <TerminalPanel label="SIGNER REGISTRY · TRI-CHAIN" status="live" meta="LIVE · WAGMI">
            <div className="divide-y divide-cover-3">
              {chains.map(({ slug, signers, threshold }) => {
                const meta = CHAIN_META[slug];
                const factory = CONTRACTS[slug].canonicalFactory;
                return (
                  <div key={slug} className="grid grid-cols-12 gap-5 items-center px-5 py-5">
                    <div className="col-span-12 md:col-span-3">
                      <ChainBadge chainId={meta.id} />
                      <div className="mt-2"><Hash addr={factory} /></div>
                    </div>
                    <div className="col-span-12 md:col-span-6">
                      <SignerBitmap active={signers} total={signers} threshold={threshold} />
                    </div>
                    <div className="col-span-12 md:col-span-3 text-right">
                      <Numeric
                        value={signers > 0 ? `${threshold}/${signers}` : null}
                        size="lg"
                        tone="leaf"
                        embossed
                      />
                      <div className="font-mono text-[9px] uppercase tracking-stamp text-ink-faint mt-1">
                        QUORUM REQUIRED
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </TerminalPanel>
        </div>
      </section>

      {/* ═══ CONTRACT MAP ═══════════════════════════════════════════ */}
      <section>
        <div className="font-mono text-[10px] uppercase tracking-stamp text-leaf-2 mb-4">
          §  ARTICLE III · CONTRACT REGISTRY
        </div>
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <ChainCard
            slug="bscTestnet"
            label="BNB TESTNET"
            chainId={97}
            tone="leaf"
            rows={[
              { name: "CanonicalFactory", addr: CONTRACTS.bscTestnet.canonicalFactory, accent: true },
              { name: "LockEscrow", addr: CONTRACTS.bscTestnet.lockEscrow },
              { name: "CCIPReceiver", addr: CONTRACTS.bscTestnet.ccipReceiver },
              { name: "CCIPSender", addr: CONTRACTS.bscTestnet.ccipSender },
            ]}
          />
          <ChainCard
            slug="avalancheFuji"
            label="AVALANCHE FUJI"
            chainId={43113}
            tone="wax"
            rows={[
              { name: "CanonicalFactory", addr: CONTRACTS.avalancheFuji.canonicalFactory, accent: true },
              { name: "LockEscrow", addr: CONTRACTS.avalancheFuji.lockEscrow },
              { name: "CCIPSender", addr: CONTRACTS.avalancheFuji.ccipSender },
              { name: "CCIPReceiver", addr: CONTRACTS.avalancheFuji.ccipReceiver },
              { name: "MockRWA (mTBILL)", addr: CONTRACTS.avalancheFuji.mockRwa },
            ]}
          />
          <ChainCard
            slug="monadTestnet"
            label="MONAD TESTNET"
            chainId={10143}
            tone="verde"
            rows={[
              { name: "CanonicalFactory", addr: CONTRACTS.monadTestnet.canonicalFactory, accent: true },
              { name: "LockEscrow", addr: CONTRACTS.monadTestnet.lockEscrow },
              { name: "CCIP", addr: undefined, note: "DIRECT ONLY" },
              { name: "MockRWA (mTBILL)", addr: CONTRACTS.monadTestnet.mockRwa },
            ]}
          />
        </div>
      </section>
    </div>
  );
}

function Step({
  idx,
  title,
  body,
  tone,
}: {
  idx: string;
  title: string;
  body: string;
  tone: "wax" | "leaf" | "verde";
}) {
  const dotCls =
    tone === "wax" ? "bg-wax-0" : tone === "leaf" ? "bg-leaf-0" : "bg-verde-0";
  const numCls =
    tone === "wax" ? "text-wax-0" : tone === "leaf" ? "text-leaf-0" : "text-verde-0";
  return (
    <div className="p-6">
      <div className="flex items-center gap-3 mb-3">
        <span className={`w-1.5 h-1.5 rounded-full ${dotCls} pulse-leaf`} />
        <span className={`font-display italic text-3xl ${numCls}`}>{idx}</span>
        <span className="font-mono text-[10px] uppercase tracking-stamp text-ink-muted">
          {title}
        </span>
      </div>
      <p className="font-body text-[13px] text-ink-page leading-relaxed">{body}</p>
    </div>
  );
}

function KPI({
  label,
  value,
  note,
  tone,
}: {
  label: string;
  value: number;
  note: string;
  tone: "wax" | "leaf" | "verde";
}) {
  return (
    <div>
      <div className="font-mono text-[9px] uppercase tracking-stamp text-ink-deep/55">{label}</div>
      <Numeric value={value} size="xl" tone={tone} embossed className="block mt-1" />
      <div className="font-mono text-[9px] uppercase tracking-stamp text-ink-deep/50 mt-1">
        {note}
      </div>
    </div>
  );
}

function ChainCard({
  label,
  chainId,
  tone,
  rows,
}: {
  slug: ChainSlug;
  label: string;
  chainId: number;
  tone: "leaf" | "wax" | "verde";
  rows: Array<{ name: string; addr?: string | undefined; accent?: boolean; note?: string }>;
}) {
  const dotCls = tone === "leaf" ? "bg-leaf-0" : tone === "wax" ? "bg-wax-0" : "bg-verde-0";
  return (
    <div className="bg-cover-1 border border-cover-3 bracket-leaf p-5">
      <div className="flex items-center gap-2 mb-3">
        <span className={`w-1.5 h-1.5 rounded-full ${dotCls} pulse-leaf`} />
        <span className="font-mono text-[10px] uppercase tracking-stamp text-leaf-2">
          {label} · № {chainId}
        </span>
      </div>
      <div className="space-y-2 font-mono text-[11px]">
        {rows.map((r) => (
          <div key={r.name} className="flex items-center justify-between gap-2">
            <span className="text-ink-faint text-[10px] uppercase tracking-stamp">{r.name}</span>
            {r.addr ? (
              <Hash addr={r.addr} className={r.accent ? "!text-verde-0 hover:!text-verde-0" : ""} />
            ) : (
              <span className="text-ink-faint text-[10px] uppercase tracking-stamp">{r.note || "—"}</span>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

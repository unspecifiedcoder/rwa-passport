"use client";

import { useState } from "react";
import { useReadContract } from "wagmi";
import { bscTestnet, avalancheFuji } from "wagmi/chains";
import { CANONICAL_FACTORY_ABI, XYTHUM_TOKEN_ABI, CONTRACTS } from "@/lib/contracts";
import { getChainName, monadTestnet } from "@/lib/chains";
import { PaperButton } from "./primitives/PaperButton";
import { PaperInput } from "./primitives/PaperInput";
import { Hash } from "./primitives/Hash";

const VERIFY_CHAINS = [
  { chain: bscTestnet, factory: CONTRACTS.bscTestnet.canonicalFactory, tone: "leaf" as const },
  { chain: avalancheFuji, factory: CONTRACTS.avalancheFuji.canonicalFactory, tone: "wax" as const },
  { chain: monadTestnet, factory: CONTRACTS.monadTestnet.canonicalFactory, tone: "verde" as const },
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
    <div className="parchment passport-corner-tr p-8 md:p-10 relative overflow-hidden max-w-3xl">
      <span
        className="absolute -top-6 right-4 font-display italic text-[140px] leading-none text-leaf-1/12 select-none pointer-events-none"
        aria-hidden
      >
        ?
      </span>

      <div className="font-mono text-[9px] uppercase tracking-stamp text-leaf-2 mb-2">
        OFFICE OF VERIFICATION · CANONICAL CHECK
      </div>
      <h2 className="font-display text-3xl md:text-4xl text-ink-deep mb-2">
        Is this address <em className="italic">authentic</em>?
      </h2>
      <p className="font-body text-[14px] text-ink-deep/70 mb-6 max-w-xl">
        One on-chain call. The factory keeps a registry of every mirror it has
        deployed. Anything else is a forgery.
      </p>

      {/* Chain selector */}
      <div className="mb-5">
        <span className="block font-mono text-[9px] uppercase tracking-stamp text-leaf-2 mb-2">
          Verify on chain
        </span>
        <div className="flex gap-2">
          {VERIFY_CHAINS.map((vc, i) => {
            const active = selectedChainIdx === i;
            const dot =
              vc.tone === "leaf" ? "bg-leaf-0" : vc.tone === "wax" ? "bg-wax-0" : "bg-verde-0";
            return (
              <button
                key={vc.chain.id}
                onClick={() => { setSelectedChainIdx(i); setChecked(false); }}
                className={`flex-1 px-3 py-2.5 font-mono text-[10px] uppercase tracking-stamp transition-all border ${
                  active
                    ? "border-ink-deep bg-ink-deep text-parchment-0"
                    : "border-ink-deep/20 bg-transparent text-ink-deep/60 hover:border-ink-deep/50"
                }`}
              >
                <span className="inline-flex items-center gap-2">
                  <span className={`w-1.5 h-1.5 ${dot} rounded-full`} />
                  {getChainName(vc.chain.id)}
                </span>
              </button>
            );
          })}
        </div>
      </div>

      {selectedChainIdx === 0 && CONTRACTS.bscTestnet.mirrorToken && (
        <button
          onClick={handlePrefill}
          className="font-mono text-[9px] uppercase tracking-stamp text-wax-0 hover:text-wax-1 mb-4 underline underline-offset-4 decoration-dotted"
        >
          ↪ TRY THE LIVE MIRROR · {CONTRACTS.bscTestnet.mirrorToken.slice(0, 10)}…
        </button>
      )}

      <div className="grid grid-cols-12 gap-3 items-end mb-2">
        <div className="col-span-12 md:col-span-9">
          <PaperInput
            label="Token address"
            surface="parchment"
            placeholder="0x…"
            value={address}
            onChange={(e) => { setAddress(e.target.value); setChecked(false); }}
          />
        </div>
        <div className="col-span-12 md:col-span-3">
          <PaperButton
            tone="wax"
            size="lg"
            fullWidth
            disabled={!isValidAddress || isLoading}
            onClick={handleVerify}
          >
            {isLoading ? "Checking…" : "Stamp ↓"}
          </PaperButton>
        </div>
      </div>

      {checked && !isLoading && isCanonical !== undefined && (
        <div className="mt-6 relative">
          {isCanonical ? (
            <div className="bg-cover-0 border-2 border-verde-0 p-6 relative">
              <div className="absolute -top-4 -right-4">
                <div className="stamp stamp-fresh text-verde-0 text-[12px] tracking-stamp bg-cover-0">
                  <span className="block leading-tight">CANONICAL</span>
                  <span className="block leading-none text-[7px] mt-0.5">
                    AUTHENTICATED · BY FACTORY
                  </span>
                </div>
              </div>
              <div className="font-display italic text-3xl text-leaf-0 mb-1">
                Verified.
              </div>
              <div className="font-body text-[13px] text-ink-page/80 mb-4 max-w-md">
                This token was deployed by the official Xythum factory. Threshold-signed attestation, deterministic address.
              </div>
              <div className="grid grid-cols-2 gap-x-6 gap-y-2 mt-4 pt-4 border-t border-cover-3">
                {tokenName && <Field label="NAME" value={tokenName as string} />}
                {tokenSymbol && <Field label="SYMBOL" value={tokenSymbol as string} />}
                {originContract && (
                  <Field label="ORIGIN" value={<Hash addr={originContract as string} />} />
                )}
                {originChainId !== undefined && (
                  <Field
                    label="ORIGIN CHAIN"
                    value={
                      <span className="font-mono text-[11px] text-ink-page">
                        {getChainName(Number(originChainId))} · {Number(originChainId)}
                      </span>
                    }
                  />
                )}
              </div>
            </div>
          ) : (
            <div className="bg-cover-0 border-2 border-wax-0 p-6 relative">
              <div className="absolute -top-4 -right-4">
                <div className="stamp stamp-fresh text-wax-0 text-[12px] tracking-stamp bg-cover-0">
                  <span className="block leading-tight">DENIED</span>
                  <span className="block leading-none text-[7px] mt-0.5">
                    NOT IN REGISTRY
                  </span>
                </div>
              </div>
              <div className="font-display italic text-3xl text-wax-0 mb-1">
                Forgery.
              </div>
              <div className="font-body text-[13px] text-ink-page/80">
                This address is NOT in the factory&apos;s canonical registry on{" "}
                {getChainName(verifyChain.chain.id)}. Treat as untrusted.
              </div>
            </div>
          )}
        </div>
      )}

      <div className="mt-6 pt-4 border-t border-ink-deep/15 font-mono text-[9px] uppercase tracking-stamp text-ink-deep/55 flex items-center justify-between">
        <span>FACTORY · {verifyChain.factory.slice(0, 10)}…</span>
        <span>{getChainName(verifyChain.chain.id)} · № {verifyChain.chain.id}</span>
      </div>
    </div>
  );
}

function Field({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div>
      <div className="font-mono text-[9px] uppercase tracking-stamp text-ink-faint mb-0.5">
        {label}
      </div>
      <div className="text-[13px] text-ink-page">{value}</div>
    </div>
  );
}

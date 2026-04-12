"use client";

import { ChainBadge } from "./ChainBadge";
import { Hash } from "./primitives/Hash";
import { Pill } from "./primitives/Pill";
import { TerminalPanel } from "./primitives/TerminalPanel";

export interface MirrorEntry {
  address: string;
  originContract: string;
  originChainId: number;
  targetChainId: number;
  symbol: string;
  status: "active" | "paused";
}

interface MirrorTableProps {
  mirrors: MirrorEntry[];
  freshAddrs?: Set<string>;
}

export function MirrorTable({ mirrors, freshAddrs }: MirrorTableProps) {
  if (mirrors.length === 0) {
    return (
      <TerminalPanel label="REGISTRY · LIVE" status="idle" meta="0 ENTRIES">
        <div className="p-12 text-center">
          <div className="font-display italic text-3xl text-ink-muted mb-2">
            No mirrors yet.
          </div>
          <div className="font-mono text-[10px] uppercase tracking-stamp text-ink-faint">
            ISSUE A MIRROR FROM /attest TO POPULATE THE REGISTRY
          </div>
        </div>
      </TerminalPanel>
    );
  }

  return (
    <TerminalPanel label="REGISTRY · ENUMERATION" status="live" meta={`${mirrors.length} ENTRIES`}>
      <div className="overflow-x-auto">
        <table className="w-full">
          <thead>
            <tr className="border-b border-cover-3">
              <th className="text-left font-mono text-[9px] uppercase tracking-stamp text-leaf-2 px-5 py-3">
                Symbol
              </th>
              <th className="text-left font-mono text-[9px] uppercase tracking-stamp text-leaf-2 px-5 py-3">
                Origin
              </th>
              <th className="text-left font-mono text-[9px] uppercase tracking-stamp text-leaf-2 px-5 py-3">
                Target
              </th>
              <th className="text-left font-mono text-[9px] uppercase tracking-stamp text-leaf-2 px-5 py-3">
                Status
              </th>
              <th className="text-left font-mono text-[9px] uppercase tracking-stamp text-leaf-2 px-5 py-3">
                Address
              </th>
            </tr>
          </thead>
          <tbody>
            {mirrors.map((m) => {
              const isFresh = freshAddrs?.has(m.address);
              return (
                <tr
                  key={`${m.targetChainId}-${m.address}`}
                  className={`border-b border-cover-3/50 hover:bg-cover-2/40 transition-colors ${isFresh ? "fresh-row" : ""}`}
                >
                  <td className="px-5 py-3 font-display text-xl text-leaf-0 flex items-center gap-2">
                    {m.symbol}
                    {isFresh && <Pill label="NEW" tone="verde" className="!text-[8px]" />}
                  </td>
                  <td className="px-5 py-3"><ChainBadge chainId={m.originChainId} /></td>
                  <td className="px-5 py-3"><ChainBadge chainId={m.targetChainId} /></td>
                  <td className="px-5 py-3">
                    <Pill
                      label={m.status === "active" ? "ACTIVE" : "PAUSED"}
                      tone={m.status === "active" ? "verde" : "wax"}
                    />
                  </td>
                  <td className="px-5 py-3"><Hash addr={m.address} /></td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </TerminalPanel>
  );
}

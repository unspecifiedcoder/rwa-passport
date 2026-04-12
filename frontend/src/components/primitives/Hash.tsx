"use client";

import { useState } from "react";
import { getExplorerUrl } from "@/lib/chains";

interface HashProps {
  addr?: string | null;
  prefix?: number;
  suffix?: number;
  className?: string;
  /** If set, renders an explorer link next to the hash. */
  chainId?: number;
  /** What kind of explorer URL to build. Default "tx". */
  kind?: "tx" | "address";
}

export function Hash({
  addr,
  prefix = 6,
  suffix = 4,
  className = "",
  chainId,
  kind = "tx",
}: HashProps) {
  const [copied, setCopied] = useState(false);

  if (!addr) {
    return <span className={`font-mono text-ink-faint ${className}`}>0x···</span>;
  }

  const truncated = `${addr.slice(0, prefix)}…${addr.slice(-suffix)}`;
  const explorerUrl = chainId !== undefined ? getExplorerUrl(chainId, addr, kind) : undefined;

  const onCopy = async (e: React.MouseEvent) => {
    e.stopPropagation();
    e.preventDefault();
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(addr);
      } else {
        const ta = document.createElement("textarea");
        ta.value = addr;
        ta.style.position = "fixed";
        ta.style.opacity = "0";
        document.body.appendChild(ta);
        ta.select();
        document.execCommand("copy");
        document.body.removeChild(ta);
      }
      setCopied(true);
      setTimeout(() => setCopied(false), 1200);
    } catch {
      /* clipboard blocked — silent */
    }
  };

  return (
    <span
      className={`group font-mono text-[11px] tracking-tight text-ink-muted inline-flex items-center gap-1 ${className}`}
    >
      <button
        onClick={onCopy}
        title={`${addr} — click to copy`}
        className="hover:text-leaf-0 transition-colors"
      >
        {truncated}
      </button>
      {explorerUrl && (
        <a
          href={explorerUrl}
          target="_blank"
          rel="noopener noreferrer"
          className="opacity-50 group-hover:opacity-100 hover:text-leaf-0 transition-all text-[9px] uppercase tracking-stamp"
          title="View on block explorer"
        >
          ↗ EXPLORER
        </a>
      )}
      <span className="opacity-0 group-hover:opacity-100 transition-opacity text-[8px] uppercase tracking-stamp text-leaf-2">
        {copied ? "✓ COPIED" : "✎ COPY"}
      </span>
    </span>
  );
}

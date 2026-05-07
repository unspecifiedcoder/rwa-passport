"use client";

import { useState, useEffect, useRef } from "react";
import { useAccount, useConnect, useDisconnect } from "wagmi";
import { truncateAddress } from "@/lib/utils";

export function ConnectButton() {
  const { address, isConnected } = useAccount();
  const { connectors, connect } = useConnect();
  const { disconnect } = useDisconnect();
  const [mounted, setMounted] = useState(false);
  const [showOptions, setShowOptions] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setMounted(true);
  }, []);

  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setShowOptions(false);
      }
    }
    if (showOptions) {
      document.addEventListener("mousedown", handleClickOutside);
      return () => document.removeEventListener("mousedown", handleClickOutside);
    }
  }, [showOptions]);

  const baseBtn =
    "px-4 py-2 font-mono text-[10px] uppercase tracking-stamp font-semibold transition-all border";

  if (!mounted) {
    return (
      <button className={`${baseBtn} bg-leaf-0 text-cover-0 border-leaf-2`} disabled>
        Connect Wallet
      </button>
    );
  }

  if (isConnected && address) {
    return (
      <div className="flex items-center gap-3">
        <span className="font-mono text-[11px] text-ink-page tracking-tight">
          <span className="text-leaf-1">⌬</span> {truncateAddress(address)}
        </span>
        <button
          onClick={() => disconnect()}
          className={`${baseBtn} bg-transparent text-ink-muted border-cover-3 hover:border-wax-0 hover:text-wax-0`}
        >
          Disconnect
        </button>
      </div>
    );
  }

  const seen = new Set<string>();
  const uniqueConnectors = connectors.filter((c) => {
    const key = c.name;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });

  return (
    <div className="relative" ref={dropdownRef}>
      <button
        onClick={() => setShowOptions(!showOptions)}
        className={`${baseBtn} bg-leaf-0 text-cover-0 border-leaf-2 hover:shadow-[0_0_0_2px_rgba(232,201,119,0.25)]`}
      >
        Connect Wallet
      </button>

      {showOptions && (
        <div className="absolute right-0 mt-2 bg-cover-1 border border-cover-3 bracket-leaf min-w-[240px] z-50 p-2">
          <p className="px-3 py-1.5 font-mono text-[9px] uppercase tracking-stamp text-leaf-2">
            §  Select Wallet
          </p>
          {uniqueConnectors.map((connector) => (
            <button
              key={connector.uid}
              onClick={() => {
                connect({ connector });
                setShowOptions(false);
              }}
              className="w-full flex items-center gap-3 px-3 py-2.5 font-mono text-[11px] text-ink-page hover:bg-cover-2 hover:text-leaf-0 transition-colors text-left"
            >
              <WalletIcon name={connector.name} />
              <span>{connector.name}</span>
            </button>
          ))}
          {uniqueConnectors.length === 0 && (
            <p className="px-3 py-2.5 font-mono text-[10px] text-ink-faint">
              No wallets detected. Install MetaMask or another browser wallet.
            </p>
          )}
        </div>
      )}
    </div>
  );
}

function WalletIcon({ name }: { name: string }) {
  const lower = name.toLowerCase();
  let bg = "bg-cover-3";
  let label = name.charAt(0).toUpperCase();
  if (lower.includes("metamask")) {
    bg = "bg-wax-0";
    label = "M";
  } else if (lower.includes("core")) {
    bg = "bg-leaf-1";
    label = "C";
  } else if (lower.includes("coinbase")) {
    bg = "bg-leaf-0 text-cover-0";
    label = "CB";
  } else if (lower.includes("walletconnect")) {
    bg = "bg-verde-1";
    label = "W";
  }
  return (
    <span
      className={`inline-flex items-center justify-center w-7 h-7 font-mono font-bold text-[10px] text-parchment-0 ${bg}`}
    >
      {label}
    </span>
  );
}

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

  // Close dropdown when clicking outside
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (
        dropdownRef.current &&
        !dropdownRef.current.contains(event.target as Node)
      ) {
        setShowOptions(false);
      }
    }
    if (showOptions) {
      document.addEventListener("mousedown", handleClickOutside);
      return () =>
        document.removeEventListener("mousedown", handleClickOutside);
    }
  }, [showOptions]);

  // Render a placeholder with the same structure on server and first client render
  // to avoid hydration mismatch
  if (!mounted) {
    return (
      <button
        className="px-4 py-2 text-sm font-medium bg-brand-600 hover:bg-brand-700 rounded-md transition-colors"
        disabled
      >
        Connect Wallet
      </button>
    );
  }

  if (isConnected && address) {
    return (
      <div className="flex items-center gap-3">
        <span className="text-sm text-gray-400 font-mono">
          {truncateAddress(address)}
        </span>
        <button
          onClick={() => disconnect()}
          className="px-3 py-1.5 text-sm bg-gray-800 hover:bg-gray-700 rounded-md transition-colors"
        >
          Disconnect
        </button>
      </div>
    );
  }

  // Deduplicate connectors by name — browser extensions can register multiple
  // providers with the same name (e.g. two "Injected" entries)
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
        className="px-4 py-2 text-sm font-medium bg-brand-600 hover:bg-brand-700 rounded-md transition-colors"
      >
        Connect Wallet
      </button>

      {showOptions && (
        <div className="absolute right-0 mt-2 bg-gray-900 border border-gray-700 rounded-xl shadow-xl p-1.5 min-w-[220px] z-50">
          <p className="px-3 py-1.5 text-xs text-gray-500 font-medium uppercase tracking-wide">
            Select Wallet
          </p>
          {uniqueConnectors.map((connector) => (
            <button
              key={connector.uid}
              onClick={() => {
                connect({ connector });
                setShowOptions(false);
              }}
              className="w-full flex items-center gap-3 px-3 py-2.5 text-sm text-gray-200 hover:bg-gray-800 rounded-lg transition-colors text-left"
            >
              <WalletIcon name={connector.name} />
              <span>{connector.name}</span>
            </button>
          ))}
          {uniqueConnectors.length === 0 && (
            <p className="px-3 py-2.5 text-sm text-gray-500">
              No wallets detected. Install MetaMask or another browser wallet.
            </p>
          )}
        </div>
      )}
    </div>
  );
}

/** Simple icon resolver — shows a colored dot per known wallet, fallback for unknown */
function WalletIcon({ name }: { name: string }) {
  const lower = name.toLowerCase();

  let color = "bg-gray-500";
  let label = name.charAt(0).toUpperCase();

  if (lower.includes("metamask")) {
    color = "bg-orange-500";
    label = "M";
  } else if (lower.includes("core")) {
    color = "bg-blue-500";
    label = "C";
  } else if (lower.includes("coinbase")) {
    color = "bg-blue-600";
    label = "CB";
  } else if (lower.includes("brave")) {
    color = "bg-orange-600";
    label = "B";
  } else if (lower.includes("walletconnect")) {
    color = "bg-indigo-500";
    label = "W";
  }

  return (
    <span
      className={`inline-flex items-center justify-center w-7 h-7 rounded-md text-xs font-bold text-white ${color}`}
    >
      {label}
    </span>
  );
}

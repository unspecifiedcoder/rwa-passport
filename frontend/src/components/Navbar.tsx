"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ConnectButton } from "./ConnectButton";

const NAV_PRIMARY = [
  { href: "/", label: "Pulse" },
  { href: "/attest", label: "Attest" },
  { href: "/lock", label: "Lock" },
  { href: "/lend", label: "Lend" },
  { href: "/mirrors", label: "Mirrors" },
  { href: "/verify", label: "Verify" },
];

const NAV_SECONDARY = [
  { href: "/governance", label: "Gov" },
  { href: "/staking", label: "Stake" },
  { href: "/portfolio", label: "Port" },
  { href: "/analytics", label: "Stats" },
];

export function Navbar() {
  const pathname = usePathname();

  const renderItem = (item: { href: string; label: string }) => {
    const active = pathname === item.href;
    return (
      <Link
        key={item.href}
        href={item.href}
        className={`relative px-3 py-1.5 font-mono text-[11px] tracking-stamp uppercase transition-colors ${
          active ? "text-leaf-0" : "text-ink-muted hover:text-ink-page"
        }`}
      >
        {item.label}
        {active && (
          <>
            <span className="absolute -bottom-px left-0 right-0 h-px bg-leaf-0" />
            <span className="absolute -top-1 left-1/2 -translate-x-1/2 w-1 h-1 bg-leaf-0 pulse-leaf" />
          </>
        )}
      </Link>
    );
  };

  return (
    <nav className="sticky top-0 z-50 border-b border-cover-3 bg-cover-0">
      <div className="max-w-[1480px] mx-auto px-6 lg:px-10">
        <div className="flex items-center justify-between h-16">
          <div className="flex items-center gap-10">
            <Link href="/" className="flex items-center gap-3 group">
              <div className="wax-seal w-9 h-9 group-hover:scale-105 transition-transform" />
              <div className="flex flex-col leading-none">
                <span className="font-display text-[22px] tracking-tight text-leaf-0 italic leading-none">
                  Xythum
                </span>
                <span className="font-mono text-[8px] uppercase tracking-stamp text-ink-faint mt-1">
                  R W A · P A S S P O R T · v.0.1
                </span>
              </div>
            </Link>
            <div className="hidden md:flex items-center gap-1">
              {NAV_PRIMARY.map(renderItem)}
              <span className="mx-2 h-4 w-px bg-cover-3" />
              {NAV_SECONDARY.map(renderItem)}
            </div>
          </div>
          <ConnectButton />
        </div>
      </div>
    </nav>
  );
}

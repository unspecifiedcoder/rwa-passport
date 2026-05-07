"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ConnectButton } from "./ConnectButton";

const NAV_ITEMS = [
  { href: "/", label: "Dashboard" },
  { href: "/mirrors", label: "Mirrors" },
  { href: "/verify", label: "Verify" },
  { href: "/attest", label: "Attest" },
  { href: "/governance", label: "Governance" },
  { href: "/staking", label: "Staking" },
  { href: "/analytics", label: "Analytics" },
  { href: "/portfolio", label: "Portfolio" },
];

export function Navbar() {
  const pathname = usePathname();

  return (
    <nav className="border-b border-gray-800 bg-gray-950/80 backdrop-blur-sm sticky top-0 z-50">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16">
          <div className="flex items-center gap-8">
            <Link href="/" className="text-xl font-bold text-brand-400">
              Xythum
            </Link>
            <div className="hidden md:flex items-center gap-1">
              {NAV_ITEMS.map((item) => (
                <Link
                  key={item.href}
                  href={item.href}
                  className={`px-3 py-2 rounded-md text-sm font-medium transition-colors ${
                    pathname === item.href
                      ? "bg-gray-800 text-white"
                      : "text-gray-400 hover:text-white hover:bg-gray-800/50"
                  }`}
                >
                  {item.label}
                </Link>
              ))}
            </div>
          </div>
          <ConnectButton />
        </div>
      </div>
    </nav>
  );
}

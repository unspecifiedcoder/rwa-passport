import type { Metadata } from "next";
import { Geist, Geist_Mono, Instrument_Serif } from "next/font/google";
import "./globals.css";
import { Providers } from "./providers";
import { Navbar } from "@/components/Navbar";

const display = Instrument_Serif({
  subsets: ["latin"],
  variable: "--font-display",
  weight: ["400"],
  style: ["normal", "italic"],
});

const body = Geist({
  subsets: ["latin"],
  variable: "--font-body",
  weight: ["400", "500", "600", "700"],
});

const mono = Geist_Mono({
  subsets: ["latin"],
  variable: "--font-mono",
  weight: ["400", "500", "600"],
});

export const metadata: Metadata = {
  title: "Xythum RWA Passport",
  description:
    "One original RWA — native and trusted on every chain. Cross-chain canonical mirror protocol with threshold-signed attestations.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html
      lang="en"
      suppressHydrationWarning
      className={`${display.variable} ${body.variable} ${mono.variable}`}
    >
      <body className="min-h-screen font-body bg-cover-0 text-ink-page antialiased">
        {/* Microprint band — top edge of the document */}
        <div className="microprint border-b border-leaf-2/20 px-4 py-1 leading-none text-center">
          {Array.from({ length: 60 })
            .map(() => "XYTHUM·RWA·PASSPORT·CANONICAL·CROSS·CHAIN·V1·")
            .join("")}
        </div>

        <Providers>
          <Navbar />
          <main className="max-w-[1480px] mx-auto px-6 lg:px-10 py-12">
            {children}
          </main>

          {/* Security thread */}
          <div className="security-thread h-1 mt-20 opacity-70" />

          <footer className="py-6 px-6 lg:px-10">
            <div className="max-w-[1480px] mx-auto flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="wax-seal w-7 h-7" />
                <div>
                  <div className="font-display italic text-base text-leaf-0 leading-none">
                    Xythum
                  </div>
                  <div className="font-mono text-[8px] uppercase tracking-stamp text-ink-faint mt-1">
                    Issued under protocol authority · v0.1
                  </div>
                </div>
              </div>
              <div className="font-mono text-[9px] uppercase tracking-stamp text-ink-faint flex items-center gap-3">
                <span className="w-1 h-1 bg-verde-0 pulse-leaf" />
                TESTNET LIVE · MAINNET PENDING
              </div>
            </div>
            <div className="microprint mt-4 leading-none text-center">
              {Array.from({ length: 60 })
                .map(() => "BEARER·HOLDS·CANONICAL·MIRROR·DETERMINISTIC·CREATE2·")
                .join("")}
            </div>
          </footer>
        </Providers>
      </body>
    </html>
  );
}

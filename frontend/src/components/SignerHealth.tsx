"use client";

interface SignerHealthProps {
  activeSigners: number;
  totalSigners: number;
  threshold: number;
}

export function SignerHealth({ activeSigners, totalSigners, threshold }: SignerHealthProps) {
  const pct = totalSigners > 0 ? (activeSigners / totalSigners) * 100 : 0;
  const healthy = activeSigners >= threshold;
  return (
    <div className="bg-cover-1 border border-cover-3 bracket-leaf p-5">
      <div className="flex items-center justify-between mb-3">
        <h3 className="font-mono text-[10px] uppercase tracking-stamp text-leaf-2">Signer Health</h3>
        <span
          className={`font-mono text-[9px] uppercase tracking-stamp px-2 py-0.5 border ${
            healthy
              ? "border-verde-0/50 text-verde-0 bg-verde-0/10"
              : "border-wax-0/50 text-wax-0 bg-wax-0/10"
          }`}
        >
          {healthy ? "Healthy" : "Degraded"}
        </span>
      </div>
      <p className="font-mono text-2xl text-ink-page tabular-nums">
        {activeSigners}/{totalSigners}
      </p>
      <p className="font-mono text-[9px] uppercase tracking-stamp text-ink-muted mt-1 mb-3">
        Threshold · {threshold} signatures required
      </p>
      <div className="w-full h-1.5 bg-cover-2">
        <div
          className={`h-full transition-all ${healthy ? "bg-verde-0" : "bg-wax-0"}`}
          style={{ width: `${pct}%` }}
        />
      </div>
    </div>
  );
}

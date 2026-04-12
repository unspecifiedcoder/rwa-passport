interface SignerBitmapProps {
  active: number;
  total: number;
  threshold: number;
  className?: string;
}

export function SignerBitmap({ active, total, threshold, className = "" }: SignerBitmapProps) {
  const slots = Array.from({ length: Math.max(total, threshold, 5) });
  return (
    <div className={`flex items-center gap-1 ${className}`}>
      {slots.map((_, i) => {
        const isActive = i < active;
        const isBelowThreshold = i < threshold;
        const cls = isActive
          ? "bg-verde-0"
          : isBelowThreshold
            ? "bg-wax-0/40 border border-wax-0"
            : "bg-cover-3";
        return <span key={i} className={`w-3 h-3 ${cls}`} style={{ animationDelay: `${i * 0.12}s` }} />;
      })}
      <span className="ml-2 font-mono text-[9px] uppercase tracking-stamp text-ink-faint">
        {active}/{total}
      </span>
    </div>
  );
}

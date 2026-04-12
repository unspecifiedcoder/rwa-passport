interface PillProps {
  label: string;
  tone?: "wax" | "leaf" | "verde" | "muted";
  className?: string;
}

const TONES = {
  wax: "border-wax-0/50 text-wax-0 bg-wax-0/10",
  leaf: "border-leaf-1/50 text-leaf-0 bg-leaf-0/10",
  verde: "border-verde-0/50 text-verde-0 bg-verde-0/10",
  muted: "border-ink-faint/40 text-ink-muted bg-cover-2",
} as const;

export function Pill({ label, tone = "muted", className = "" }: PillProps) {
  return (
    <span
      className={`inline-flex items-center px-2 py-0.5 font-mono text-[9px] uppercase tracking-stamp border ${TONES[tone]} ${className}`}
    >
      {label}
    </span>
  );
}

interface StatCardProps {
  title: string;
  value: string | number;
  subtitle?: string;
  color?: string;
}

const COLOR_MAP: Record<string, string> = {
  "text-brand-400": "text-leaf-0",
  "text-blue-400": "text-leaf-0",
  "text-purple-400": "text-leaf-1",
  "text-green-400": "text-verde-0",
  "text-cyan-400": "text-leaf-1",
  "text-violet-400": "text-leaf-1",
  "text-yellow-400": "text-leaf-0",
  "text-red-400": "text-wax-0",
};

export function StatCard({ title, value, subtitle, color = "text-leaf-0" }: StatCardProps) {
  const accent = COLOR_MAP[color] || color;
  return (
    <div className="bg-cover-1 border border-cover-3 bracket-leaf p-5">
      <p className="font-mono text-[9px] uppercase tracking-stamp text-ink-faint">{title}</p>
      <p className={`font-mono tabular-nums text-3xl mt-1 embossed-leaf ${accent}`}>{value}</p>
      {subtitle && (
        <p className="font-mono text-[9px] uppercase tracking-stamp text-ink-muted mt-1">{subtitle}</p>
      )}
    </div>
  );
}

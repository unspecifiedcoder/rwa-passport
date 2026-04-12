interface TerminalPanelProps {
  label: string;
  status?: "idle" | "live" | "danger";
  meta?: string;
  children: React.ReactNode;
  className?: string;
}

const STATUS_DOT = {
  idle: "bg-ink-faint",
  live: "bg-verde-0 pulse-leaf",
  danger: "bg-wax-0 pulse-leaf",
} as const;

export function TerminalPanel({
  label,
  status = "idle",
  meta,
  children,
  className = "",
}: TerminalPanelProps) {
  return (
    <section className={`bg-cover-1 border border-cover-3 bracket-leaf ${className}`}>
      <header className="px-5 py-2.5 border-b border-cover-3 flex items-center justify-between">
        <div className="flex items-center gap-2 font-mono text-[10px] uppercase tracking-stamp text-leaf-2">
          <span className={`w-1.5 h-1.5 rounded-full ${STATUS_DOT[status]}`} />
          [ {label} ]
        </div>
        {meta && (
          <span className="font-mono text-[9px] uppercase tracking-stamp text-ink-faint">
            {meta}
          </span>
        )}
      </header>
      {children}
    </section>
  );
}

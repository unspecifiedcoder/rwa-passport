import type { ReactNode } from "react";
import { Stamp } from "./Stamp";

interface PageHeaderProps {
  article: string;
  kicker: string;
  title: ReactNode;
  lede?: ReactNode;
  stamp?: { text: string; meta?: string; tone?: "verde" | "wax" | "leaf" };
  meta?: ReactNode;
}

export function PageHeader({ article, kicker, title, lede, stamp, meta }: PageHeaderProps) {
  return (
    <header className="relative">
      <span className="watermark -top-12 right-0" aria-hidden>
        X
      </span>
      <div className="grid grid-cols-12 gap-6 items-end relative z-10 border-b border-cover-3 pb-6">
        <div className="col-span-12 lg:col-span-9">
          <div className="font-mono text-[9px] uppercase tracking-stamp text-leaf-2 mb-2">
            {article} · {kicker}
          </div>
          <h1 className="font-display text-4xl md:text-5xl lg:text-6xl text-ink-page leading-[1.05] tracking-tight">
            {title}
          </h1>
          {lede && (
            <p className="font-body text-[14px] md:text-[15px] text-ink-muted mt-3 max-w-2xl leading-relaxed">
              {lede}
            </p>
          )}
        </div>
        <div className="col-span-12 lg:col-span-3 flex flex-col items-end gap-3">
          {stamp && <Stamp text={stamp.text} meta={stamp.meta} tone={stamp.tone ?? "leaf"} />}
          {meta && (
            <div className="font-mono text-[9px] uppercase tracking-stamp text-ink-faint text-right">
              {meta}
            </div>
          )}
        </div>
      </div>
    </header>
  );
}

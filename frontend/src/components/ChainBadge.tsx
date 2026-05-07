import { getChainName } from "@/lib/chains";

const CHAIN_TONE: Record<number, "wax" | "leaf" | "verde" | "ink"> = {
  43113: "wax",
  97: "leaf",
  10143: "verde",
  11155111: "ink",
  421614: "ink",
  84532: "ink",
};

const TONE_DOT = {
  wax: "bg-wax-0",
  leaf: "bg-leaf-0",
  verde: "bg-verde-0",
  ink: "bg-ink-page",
} as const;

interface ChainBadgeProps {
  chainId: number;
  showId?: boolean;
  className?: string;
}

export function ChainBadge({ chainId, showId = true, className = "" }: ChainBadgeProps) {
  const tone = CHAIN_TONE[chainId] ?? "ink";
  const name = getChainName(chainId);
  return (
    <span
      className={`inline-flex items-center gap-2 font-mono text-[10px] uppercase tracking-stamp text-ink-page ${className}`}
    >
      <span className={`w-1.5 h-1.5 rounded-full ${TONE_DOT[tone]} pulse-leaf`} />
      {name}
      {showId && (
        <>
          <span className="text-leaf-2">·</span>
          <span className="text-ink-muted">№ {chainId}</span>
        </>
      )}
    </span>
  );
}

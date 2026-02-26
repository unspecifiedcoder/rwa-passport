import { getChainName, getChainColor } from "@/lib/chains";

interface ChainBadgeProps {
  chainId: number;
}

export function ChainBadge({ chainId }: ChainBadgeProps) {
  const name = getChainName(chainId);
  const color = getChainColor(chainId);

  return (
    <span
      className={`inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-medium text-white ${color}`}
    >
      <span className="w-1.5 h-1.5 rounded-full bg-white/80" />
      {name}
    </span>
  );
}

interface NumericProps {
  value: number | bigint | string | null | undefined;
  unit?: string;
  decimals?: number;
  className?: string;
  size?: "sm" | "md" | "lg" | "xl";
  tone?: "default" | "leaf" | "wax" | "verde" | "muted";
  embossed?: boolean;
}

const SIZE_CLASSES = {
  sm: "text-sm",
  md: "text-lg",
  lg: "text-2xl",
  xl: "text-5xl",
} as const;

const TONE_CLASSES = {
  default: "text-ink-page",
  leaf: "text-leaf-0",
  wax: "text-wax-0",
  verde: "text-verde-0",
  muted: "text-ink-muted",
} as const;

function format(value: number | bigint | string, decimals: number) {
  if (typeof value === "string") return value;
  if (typeof value === "bigint") return value.toLocaleString("en-US");
  return value.toLocaleString("en-US", {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });
}

export function Numeric({
  value,
  unit,
  decimals = 0,
  className = "",
  size = "md",
  tone = "default",
  embossed = false,
}: NumericProps) {
  if (value === null || value === undefined) {
    return (
      <span className={`font-mono tabular-nums ${SIZE_CLASSES[size]} text-ink-faint ${className}`}>···</span>
    );
  }
  return (
    <span
      className={`font-mono tabular-nums tracking-tight ${SIZE_CLASSES[size]} ${TONE_CLASSES[tone]} ${embossed ? "embossed-leaf" : ""} ${className}`}
    >
      {format(value, decimals)}
      {unit && (
        <span className="ml-1.5 text-[0.45em] uppercase tracking-stamp text-ink-faint align-baseline">
          {unit}
        </span>
      )}
    </span>
  );
}

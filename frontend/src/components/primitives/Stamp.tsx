interface StampProps {
  text: string;
  meta?: string;
  tone?: "verde" | "wax" | "leaf";
  className?: string;
}

const TONES = {
  verde: "text-verde-0",
  wax: "text-wax-0",
  leaf: "text-leaf-0",
} as const;

export function Stamp({ text, meta, tone = "leaf", className = "" }: StampProps) {
  return (
    <div className={`stamp ${TONES[tone]} text-[10px] tracking-stamp ${className}`}>
      <span className="block leading-tight">{text}</span>
      {meta && (
        <span className="block leading-none text-[7px] mt-0.5 opacity-80">{meta}</span>
      )}
    </div>
  );
}

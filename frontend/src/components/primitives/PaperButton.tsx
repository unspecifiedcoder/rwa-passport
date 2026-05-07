import { forwardRef } from "react";

type Tone = "leaf" | "wax" | "verde" | "ghost";
type Size = "sm" | "md" | "lg";

interface PaperButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  tone?: Tone;
  size?: Size;
  fullWidth?: boolean;
}

const TONES: Record<Tone, string> = {
  leaf: "bg-leaf-0 text-cover-0 border-leaf-2 hover:bg-leaf-1 hover:shadow-[0_0_0_2px_rgba(232,201,119,0.25)]",
  wax: "bg-wax-0 text-parchment-0 border-wax-1 hover:bg-wax-1 hover:shadow-[0_0_0_2px_rgba(200,58,43,0.25)]",
  verde: "bg-verde-0 text-parchment-0 border-verde-1 hover:bg-verde-1",
  ghost: "bg-transparent text-ink-page border-cover-3 hover:border-leaf-2 hover:text-leaf-0",
};
const SIZES: Record<Size, string> = {
  sm: "px-3 py-1.5 text-[10px]",
  md: "px-4 py-2 text-[11px]",
  lg: "px-5 py-3 text-[12px]",
};

export const PaperButton = forwardRef<HTMLButtonElement, PaperButtonProps>(
  ({ tone = "leaf", size = "md", fullWidth, className = "", children, ...rest }, ref) => {
    return (
      <button
        ref={ref}
        {...rest}
        className={`font-mono uppercase tracking-stamp font-semibold border transition-all disabled:opacity-40 disabled:cursor-not-allowed ${TONES[tone]} ${SIZES[size]} ${fullWidth ? "w-full" : ""} ${className}`}
      >
        {children}
      </button>
    );
  },
);
PaperButton.displayName = "PaperButton";

import { forwardRef } from "react";

interface PaperInputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  hint?: string;
  suffix?: string;
  surface?: "default" | "parchment";
}

export const PaperInput = forwardRef<HTMLInputElement, PaperInputProps>(
  ({ label, hint, suffix, surface = "default", className = "", ...rest }, ref) => {
    const inputCls =
      surface === "parchment"
        ? "bg-parchment-1/60 border-b-2 border-ink-deep/40 focus:border-wax-0 text-ink-deep placeholder:text-ink-deep/30"
        : "bg-cover-2 border border-cover-3 focus:border-leaf-2 text-ink-page placeholder:text-ink-faint";

    return (
      <label className="block">
        {label && (
          <span className="block font-mono text-[9px] uppercase tracking-stamp text-leaf-2 mb-1.5">
            {label}
          </span>
        )}
        <div className="relative">
          <input
            ref={ref}
            {...rest}
            className={`w-full px-3 py-2.5 font-mono text-[12px] outline-none transition-colors ${inputCls} ${className}`}
          />
          {suffix && (
            <span className="absolute right-2 top-1/2 -translate-y-1/2 font-mono text-[9px] uppercase tracking-stamp text-ink-faint">
              {suffix}
            </span>
          )}
        </div>
        {hint && (
          <span className="block font-mono text-[9px] uppercase tracking-stamp text-ink-faint mt-1">
            {hint}
          </span>
        )}
      </label>
    );
  },
);
PaperInput.displayName = "PaperInput";

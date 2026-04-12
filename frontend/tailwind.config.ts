import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        cover: {
          0: "#0A0E1A",
          1: "#11172A",
          2: "#1A2138",
          3: "#232C47",
          4: "#303A58",
        },
        parchment: {
          0: "#F4EAD5",
          1: "#EBDFC4",
          2: "#D8C89F",
        },
        leaf: {
          0: "#E8C977",
          1: "#C9A24A",
          2: "#8A6A28",
        },
        wax: {
          0: "#C83A2B",
          1: "#962A1F",
        },
        verde: {
          0: "#4A8A5C",
          1: "#2D5A3A",
        },
        ink: {
          page: "#E6DFC8",
          muted: "#8B8366",
          faint: "#4F4D3D",
          deep: "#0A0E1A",
        },
      },
      fontFamily: {
        display: ["var(--font-display)", "Instrument Serif", "Georgia", "serif"],
        body: ["var(--font-body)", "Geist", "ui-sans-serif", "sans-serif"],
        mono: ["var(--font-mono)", "Geist Mono", "ui-monospace", "monospace"],
      },
      letterSpacing: {
        terminal: "0.18em",
        stamp: "0.22em",
      },
      borderColor: {
        DEFAULT: "#232C47",
      },
    },
  },
  plugins: [],
};
export default config;

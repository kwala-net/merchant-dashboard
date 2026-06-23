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
        bg: "#0a0a0a",
        card: "#111111",
        border: "#1e1e1e",
        muted: "#6b7280",
        green: { 400: "#22c55e", 500: "#16a34a" },
        red: { 400: "#ef4444", 500: "#dc2626" },
        yellow: { 400: "#eab308", 500: "#ca8a04" },
        blue: { 400: "#60a5fa", 500: "#3b82f6" },
        purple: { 400: "#c084fc", 500: "#a855f7" },
      },
    },
  },
  plugins: [],
};
export default config;

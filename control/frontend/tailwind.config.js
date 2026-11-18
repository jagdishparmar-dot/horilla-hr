/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["../templates/**/*.html", "../templatetags/**/*.py"],
  theme: {
    extend: {
      fontFamily: {
        sans: ["DM Sans", "ui-sans-serif", "system-ui", "sans-serif"],
        display: ["Plus Jakarta Sans", "DM Sans", "sans-serif"],
        mono: ["JetBrains Mono", "ui-monospace", "SFMono-Regular", "Menlo", "monospace"],
      },
      colors: {
        canvas: "#f8fafc",
        ink: "#0f172a",
        sidebar: "#ffffff",
      },
      boxShadow: {
        card: "0 1px 2px rgba(28, 25, 23, 0.04), 0 12px 32px rgba(28, 25, 23, 0.04)",
      },
    },
  },
  plugins: [require("@tailwindcss/forms")],
};

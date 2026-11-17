/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["../templates/**/*.html"],
  theme: {
    extend: {
      fontFamily: {
        sans: ["Source Sans 3", "ui-sans-serif", "system-ui", "sans-serif"],
        display: ["Outfit", "Source Sans 3", "sans-serif"],
        mono: ["IBM Plex Mono", "ui-monospace", "SFMono-Regular", "Menlo", "monospace"],
      },
      colors: {
        canvas: "#f3f0e8",
        ink: "#1c1917",
        sidebar: "#161a21",
      },
      boxShadow: {
        card: "0 1px 2px rgba(28, 25, 23, 0.04), 0 12px 32px rgba(28, 25, 23, 0.04)",
      },
    },
  },
  plugins: [require("@tailwindcss/forms")],
};

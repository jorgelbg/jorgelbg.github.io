module.exports = {
  purge: [],
  theme: {
    extend: {
      scale: {
        "-1": "-1",
      },
      screens: {
        dark: { raw: "(prefers-color-scheme: dark)" },
        // => @media (prefers-color-scheme: dark) { ... }
      },
    },
  },
  variants: {},
  plugins: [],
};

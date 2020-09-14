const tailwindcss = require("tailwindcss");
const autoprefixer = require("autoprefixer");
const { theme } = require("tailwindcss/stubs/defaultConfig.stub");
module.exports = {
  plugins: [
    tailwindcss,
    autoprefixer,
    require("cssnano")({
      preset: "default",
    }),
  ],
};

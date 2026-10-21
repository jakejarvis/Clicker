// @ts-check
import { defineConfig, fontProviders } from "astro/config";
import vercel from "@astrojs/vercel";

// Every page is prerendered, so the adapter only lays out the static build for
// Vercel; there is no server function. /appcast.xml is a rewrite in vercel.json.
// https://astro.build/config
export default defineConfig({
  site: "https://clicker.jarv.is",
  trailingSlash: "never",
  adapter: vercel(),
  build: {
    inlineStylesheets: "always",
  },
  fonts: [
    {
      name: "Inter Variable",
      cssVariable: "--font-inter",
      provider: fontProviders.local(),
      options: {
        variants: [
          {
            src: ["./node_modules/@fontsource-variable/inter/files/inter-latin-wght-normal.woff2"],
            weight: "100 900",
            style: "normal",
          },
        ],
      },
    },
    {
      name: "Monaspace Neon",
      cssVariable: "--font-monaspace-neon",
      provider: fontProviders.local(),
      options: {
        variants: [
          {
            src: [
              "./node_modules/@fontsource/monaspace-neon/files/monaspace-neon-latin-400-normal.woff2",
            ],
            weight: 400,
            style: "normal",
          },
          {
            src: [
              "./node_modules/@fontsource/monaspace-neon/files/monaspace-neon-latin-500-normal.woff2",
            ],
            weight: 500,
            style: "normal",
          },
        ],
      },
      fallbacks: ["monospace"],
    },
  ],
});

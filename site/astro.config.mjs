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
      name: "Geist Variable",
      cssVariable: "--font-geist",
      provider: fontProviders.local(),
      options: {
        variants: [
          {
            src: ["./node_modules/@fontsource-variable/geist/files/geist-latin-wght-normal.woff2"],
            weight: "100 900",
            style: "normal",
          },
        ],
      },
    },
    {
      name: "Geist Mono Variable",
      cssVariable: "--font-geist-mono",
      provider: fontProviders.local(),
      options: {
        variants: [
          {
            src: [
              "./node_modules/@fontsource-variable/geist-mono/files/geist-mono-latin-wght-normal.woff2",
            ],
            weight: "100 900",
            style: "normal",
          },
        ],
      },
      fallbacks: ["monospace"],
    },
  ],
});

# clicker.jarv.is

The download page for Clicker, built with [Astro](https://astro.build) and deployed to Vercel from this directory. Every page is prerendered; there is no server code.

```sh
npm install
npm run dev      # http://localhost:4321
npm run build    # writes dist/ and .vercel/output/
```

`/changelog` is rendered at build time from the GitHub releases API. Set `GITHUB_TOKEN` (a read-only token) as a build-time environment variable to lift the unauthenticated rate limit; without it the build works while the GitHub API is available. The page only changes when the site is redeployed, so a release needs a new deployment to show up.

`/appcast.xml` (the app's Sparkle feed) is not part of this build: `vercel.json` rewrites it to `appcast.xml` on the repository's `gh-pages` branch, which the release workflow updates.

# The website

`site/` is the Astro site for clicker.jarv.is, deployed on Vercel from that directory. Every page is prerendered; the only server code is the `/appcast.xml` route.

```bash
cd site
npm install
npm run dev      # http://localhost:4321
npm run build    # writes dist/ and .vercel/output/
```

## Pages

- `/`: the homepage, with the download button, the Homebrew command and the shot of the panel under a mock menu bar.
- `/changelog`: every published release's notes.
- `/help`: a short FAQ, the keyboard shortcuts and a Report an Issue button (GitHub's new-issue page). The app's Help › Clicker Help opens it, so keep that path. Check each answer against the app and its docs before adding it, and keep longer troubleshooting in the README. The shortcuts table is the README's, so a key added to the remote ([input.md](input.md#keyboard)) goes in both.
- `/privacy` and `/terms`. The App Store listing links `/privacy` as the privacy policy ([app-store.md](app-store.md)), so keep that path.
- A 404 page.

## Keep it static

The Vercel adapter lays out the static build plus one function, for `/appcast.xml` ([update check counts](#update-check-counts)). Keep every page prerendered: a server-rendered version once crashed on cold start (the adapter's build-time import got bundled into the function), which turned every non-prerendered path, 404s included, into a 500. The appcast route imports nothing from `src/lib`, so the releases code stays out of the function. After `npm run build`, `.vercel/output/config.json` should send only `/appcast.xml` and Astro's own `/_image` and `/_server-islands` to `_render`; a page that lost its prerendering shows up there.

## Release data

The homepage's download button and `/changelog` are built from the GitHub releases API at build time, with one request shared by both (`site/src/lib/releases.ts`). The button links straight to the newest release's DMG, or to the releases page when no release has one. A failed request fails the build, so a broken page is never deployed. Set `GITHUB_TOKEN` (a read-only token) as a build-time variable to lift the unauthenticated rate limit.

The pages only change when the site is rebuilt, so the release workflow asks Vercel to redeploy after each release (`VERCEL_DEPLOY_HOOK_URL`, see [releasing.md](releasing.md#secrets)); without the hook the site catches up on the next push to `main`.

`/appcast.xml`, the app's Sparkle feed, is not part of the build: on each request `src/pages/appcast.xml.ts` fetches `appcast.xml` from the repository's `gh-pages` branch on GitHub Pages, which the release workflow updates, and returns it. A feed GitHub can't serve comes back with GitHub's status, or as a 502 when GitHub doesn't answer within 10 seconds, and Sparkle reports a failed check.

## Update check counts

The appcast route counts update checks, the only usage figure the direct download has. Every copy with Check Automatically on fetches the feed about once a day while it runs. Each GET whose user agent is Sparkle's (`Clicker/<version> Sparkle/<version>`) and that gets the feed becomes one PostHog `update_check` event, sent after the response (`waitUntil` from `@vercel/functions`) with a 2-second timeout; a failure is dropped, so counting never delays or breaks the feed, and a non-2xx answer from PostHog is logged in the function's logs. Checks that get an error instead of the feed aren't counted, nor are Homebrew's livecheck, browsers and HEAD requests, which are served.

- Properties: `app_version` and `sparkle_version` from the user agent, `check` (`background` for Sparkle's scheduled check, `user` for Check for Updates…, `unknown` from releases that don't send it) and `first_check` (the install's first check ever).
- `check` and `first` come from the app: `UpdateController` adds them to the feed URL through Sparkle's `feedParameters(for:sendingSystemProfile:)`, after `updater(_:mayPerform:)` has recorded which kind of check it is. `first` is decided when the updater starts, since Sparkle stamps `lastUpdateCheckDate` before it asks for the parameters. Sparkle's system profile stays off.
- Anonymous by construction: a fresh random `distinct_id` per event, `$process_person_profile` false (no person profiles) and `$geoip_disable`. The function makes the request, so PostHog sees Vercel's address, never the Mac's. Turn on "Discard client IP data" in the PostHog project as well.
- Configuration, as Vercel environment variables for Production: `POSTHOG_PROJECT_TOKEN` (without it nothing is sent and the feed is served as before) and `POSTHOG_HOST` (default `https://eu.i.posthog.com`; `https://us.i.posthog.com` for a US project). The function reads them at runtime; a change takes effect with the next deployment.
- Reading them: a day's `background` checks approximate the installs that ran that day with automatic checks on. There is no identifier, so days can't be deduplicated into weekly or monthly users, and installs with automatic checks off only show up when someone checks by hand. The App Store build has no Sparkle and is never counted; App Store Connect's own analytics cover it.

The privacy policy (`/privacy`) describes exactly what is sent, so a new property or parameter changes it too.

To try the route locally, run a listener on port 9999 that prints what it receives, start `POSTHOG_PROJECT_TOKEN=test POSTHOG_HOST=http://127.0.0.1:9999 npm run dev`, then `curl -A "Clicker/1.0 Sparkle/2.10.0" "http://localhost:4321/appcast.xml?check=background&first=1"`.

## The homepage shot

The shot is two inline SVGs, so it is sharp at any scale and needs none of Apple's fonts on the visitor's machine. Both are snapshots of one capture: the black-wallpaper App Store screenshot (`script/screenshots.sh --appearance dark --out dist/screenshots-black` with the sandbox off), whose panel is the 544×1026 pixels of `raw/01-ready-dark.png` from (66, 1966). When the panel's look or size changes, recapture it and redo both.

- The panel is `site/src/components/Panel.astro`, a vector copy of the capture. Its viewBox is 272×513 at one unit per point, with the panel at (4, 0), and its IDs are prefixed `panel-` because it's inlined into the page.
  - The glyphs are SF Symbols from `npx sf-symbols-svg --size 16 --padding 0` (which reads the SF Pro Text fonts in `/Library/Fonts`), at the sizes and weights the app uses.
  - The text is the system font's CoreText outlines with a 0.3pt stroke, since macOS draws light text on dark slightly heavier than its outlines.
  - The shapes are SwiftUI's own continuous-corner paths.
  - Liquid Glass has no SVG equivalent, so each surface is a fill, a rim whose vertical gradient is bright where the edge faces up or down and a dark hairline where it faces sideways, a blurred inner glow, and a soft shadow under the clickpad, with the values fitted to the capture pixel by pixel.
- The menu bar above it is `site/src/components/MenuBar.astro`, sized and spaced at 1px per point to match the capture. The panel is centred under it for the page, not hung under Clicker's item as on screen.
  - The Wi-Fi, battery and Control Center glyphs are SF Symbols from `npx sf-symbols-svg --size 13 --padding 0`. Siri isn't an SF Symbol, so it's drawn by hand.
  - The clock is SF Pro's outline of "9:41 AM" at 13.5px, in the box the live text took (line height 1.75, baseline 16.5px down).

## Icons

`site/public/icon.png`, `site/src/assets/icon.png` and `site/public/favicon.png` are renders of the app icon. `./script/render_icon.sh` refreshes them along with its previews ([development.md](development.md#icons)).

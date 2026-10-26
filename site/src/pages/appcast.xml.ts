import type { APIRoute } from "astro";
import { waitUntil } from "@vercel/functions";

// The app's Sparkle feed (SUFeedURL), served from the gh-pages branch, where
// the release workflow commits it. This is the site's one on-demand route: it
// returns the feed and counts the check (see docs/site.md#update-check-counts).
export const prerender = false;

const FEED_URL = "https://jakejarvis.github.io/Clicker/appcast.xml";
const FEED_TIMEOUT_MS = 10_000;
const CAPTURE_TIMEOUT_MS = 2_000;
const DEFAULT_POSTHOG_HOST = "https://eu.i.posthog.com";
// Sparkle's user agent: CFBundleName/CFBundleShortVersionString Sparkle/version.
// Anything else (Homebrew's livecheck, browsers) is served but not counted.
const SPARKLE_AGENT_PATTERN = /^Clicker\/([A-Za-z0-9.+-]{1,32}) Sparkle\/([A-Za-z0-9.+-]{1,32})$/;
// Query parameters the app adds (UpdateController.feedParameters).
const CHECK_KINDS = new Set(["background", "user"]);

export const GET: APIRoute = async ({ request, url }) => {
  let feed: Response;
  try {
    feed = await fetch(FEED_URL, { signal: AbortSignal.timeout(FEED_TIMEOUT_MS) });
  } catch {
    return new Response("The update feed is unavailable.", { status: 502 });
  }

  const agent = request.headers.get("user-agent")?.match(SPARKLE_AGENT_PATTERN);
  if (feed.ok && agent && request.method === "GET") {
    const check = url.searchParams.get("check") ?? "";
    waitUntil(
      countCheck({
        app_version: agent[1],
        sparkle_version: agent[2],
        // Releases before the app sent `check` count as "unknown".
        check: CHECK_KINDS.has(check) ? check : "unknown",
        first_check: url.searchParams.get("first") === "1",
      }),
    );
  }

  // No s-maxage, so Vercel's CDN never answers in the function's place and
  // every check is counted. Sparkle ignores the local cache anyway.
  return new Response(feed.body, {
    status: feed.status,
    headers: {
      "content-type": "application/xml; charset=utf-8",
      "cache-control": "max-age=600",
    },
  });
};

// One anonymous PostHog event per check: no person profile, a throwaway
// distinct ID and no GeoIP. PostHog sees Vercel's address, never the Mac's.
// Without a project token nothing is sent. Failures are dropped: counting
// must never hold up or break the feed.
async function countCheck(properties: Record<string, string | boolean>): Promise<void> {
  const token = process.env.POSTHOG_PROJECT_TOKEN;
  if (!token) return;
  const host = process.env.POSTHOG_HOST || DEFAULT_POSTHOG_HOST;

  try {
    await fetch(new URL("/i/v0/e/", host), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        api_key: token,
        event: "update_check",
        distinct_id: crypto.randomUUID(),
        properties: {
          ...properties,
          $process_person_profile: false,
          $geoip_disable: true,
        },
      }),
      signal: AbortSignal.timeout(CAPTURE_TIMEOUT_MS),
    });
  } catch {
    // Dropped.
  }
}

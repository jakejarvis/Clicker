const GITHUB_RELEASES_URL = "https://api.github.com/repos/jakejarvis/Clicker/releases?per_page=50";
const GITHUB_RELEASE_URL_PREFIX = "https://github.com/jakejarvis/Clicker/releases/";
const FETCH_TIMEOUT_MS = 10_000;
const MAX_RELEASE_TEXT_LENGTH = 200_000;
const RELEASE_TAG_PATTERN = /^[A-Za-z0-9._-]{1,128}$/;

export interface ReleaseAsset {
  url: string;
  // In bytes.
  size: number;
}

export interface ReleaseDownloads {
  dmg: ReleaseAsset | null;
  zip: ReleaseAsset | null;
}

export interface Release {
  tag_name: string;
  body_html: string | null;
  published_at: string | null;
  html_url: string;
  downloads: ReleaseDownloads;
}

// Published, non-prerelease releases, newest first (GitHub's order). One request
// per build: the homepage (download button) and the changelog both read it.
export function fetchReleases(): Promise<Release[]> {
  releasesPromise ??= requestReleases();
  return releasesPromise;
}

// The newest release that has a DMG, or null when none does yet.
export async function fetchLatestDownload(): Promise<{ tag_name: string; dmgUrl: string } | null> {
  for (const { tag_name, downloads } of await fetchReleases()) {
    if (downloads.dmg) return { tag_name, dmgUrl: downloads.dmg.url };
  }
  return null;
}

let releasesPromise: Promise<Release[]> | undefined;

async function requestReleases(): Promise<Release[]> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);

  try {
    const response = await fetch(GITHUB_RELEASES_URL, {
      headers: githubHeaders(),
      signal: controller.signal,
    });

    if (!response.ok) {
      throw new Error(`GitHub releases request failed with ${response.status}`);
    }

    return parseReleases(await response.json());
  } finally {
    clearTimeout(timeout);
  }
}

function githubHeaders(): Headers {
  const headers = new Headers({
    // "full" adds body_html, rendered by GitHub, next to the Markdown body.
    Accept: "application/vnd.github.full+json",
  });

  const token = process.env.GITHUB_TOKEN;
  if (token) {
    headers.set("Authorization", `Bearer ${token}`);
  }

  return headers;
}

function parseReleases(payload: unknown): Release[] {
  if (!Array.isArray(payload)) {
    throw new Error("GitHub releases response was not an array");
  }

  return payload.flatMap((item) => {
    const release = parseRelease(item);
    return release ? [release] : [];
  });
}

function parseRelease(item: unknown): Release | null {
  if (!isRecord(item)) return null;
  if (item.draft !== false || item.prerelease !== false) return null;
  if (!isReleaseTag(item.tag_name)) return null;
  if (!isReleaseUrl(item.html_url)) return null;

  return {
    tag_name: item.tag_name,
    body_html: withoutTitleLine(optionalText(item.body_html, MAX_RELEASE_TEXT_LENGTH)),
    published_at: optionalDate(item.published_at),
    html_url: item.html_url,
    downloads: {
      dmg: findAsset(item.assets, ".dmg"),
      zip: findAsset(item.assets, ".zip"),
    },
  };
}

// The release workflow attaches Clicker-X.Y.Z.dmg and Clicker-X.Y.Z.zip.
function findAsset(assets: unknown, extension: string): ReleaseAsset | null {
  if (!Array.isArray(assets)) return null;

  for (const asset of assets) {
    if (!isRecord(asset)) continue;
    const { name, browser_download_url: url, size } = asset;
    if (typeof name !== "string" || !name.endsWith(extension)) continue;
    if (isReleaseUrl(url) && typeof size === "number") return { url, size };
  }

  return null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function isReleaseTag(value: unknown): value is string {
  return typeof value === "string" && RELEASE_TAG_PATTERN.test(value);
}

function isReleaseUrl(value: unknown): value is string {
  return typeof value === "string" && value.startsWith(GITHUB_RELEASE_URL_PREFIX);
}

function optionalText(value: unknown, maxLength: number): string | null {
  if (typeof value !== "string") return null;
  if (value.length === 0 || value.length > maxLength) return null;
  return value;
}

// The tag message opens with "Clicker X.Y.Z", which the changelog's heading
// already says.
function withoutTitleLine(html: string | null): string | null {
  if (html === null) return null;
  const rest = html.replace(/^\s*<p>Clicker v?[\d.]+<\/p>\s*/, "");
  return rest.length > 0 ? rest : null;
}

function optionalDate(value: unknown): string | null {
  if (typeof value !== "string") return null;
  return Number.isNaN(Date.parse(value)) ? null : value;
}

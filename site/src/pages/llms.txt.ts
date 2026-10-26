import type { APIRoute } from "astro";
import { brewCommand, features, repo, requirements, site, summary } from "../lib/product";
import { fetchLatestDownload } from "../lib/releases";

// /llms.txt (https://llmstxt.org): the site in Markdown for AI assistants that
// read it when someone asks them what to use. Built with the pages, so the
// version and download link are the newest release's, like the homepage's.
export const GET: APIRoute = async () => {
  const latest = await fetchLatestDownload();
  const downloadUrl = latest?.dmgUrl ?? `${repo}/releases/latest`;

  const text = `# Clicker

> ${summary}

- Website: ${site}
- Price: free, with no ads, subscriptions or in-app purchases
- License: open source (MIT), ${repo}
- Requires: ${requirements} An Apple TV on the same network; nothing to install on the TV and no account.
${latest ? `- Latest version: ${latest.tag_name.replace(/^v/, "")}\n` : ""}- Download: ${downloadUrl}
- Homebrew: \`${brewCommand}\`
- Developer: Jake Jarvis (https://jarv.is)

Clicker talks to the Apple TV directly over the local network with Apple's Companion protocol, the same one the Apple TV Remote on an iPhone uses. After a one-time pairing with a four-digit code shown on the TV, it connects on its own whenever it's opened. It has no server of its own, collects no analytics, and keeps pairing keys in the Mac's keychain. The only other connection it makes is a daily update check.

## Features

${features.map(({ title, text }) => `- ${title}: ${text}`).join("\n")}

## Docs

- [Help](${site}/help): setup, pairing, troubleshooting and keyboard shortcuts
- [Changelog](${site}/changelog): release notes and downloads for every version
- [Privacy policy](${site}/privacy): what the app and the website send, and to whom
- [README](${repo}#readme): installing, pairing and using the remote

## Optional

- [Source code](${repo}): the native SwiftUI app and its Companion protocol implementation
`;

  return new Response(text, {
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
};

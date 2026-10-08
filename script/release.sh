#!/usr/bin/env bash
# Build, sign, notarize and package a Clicker release into dist/release/:
# Clicker-X.Y.Z.dmg (first installs), Clicker-X.Y.Z.zip (Sparkle), appcast.xml
# and notes.md. Runs the same way locally and in .github/workflows/release.yml.
# Usage: script/release.sh --version X.Y.Z [--identity <name|SHA-1>]
#
#   --identity            Developer ID Application identity; defaults to
#                         $SIGNING_IDENTITY. Locally, pass the certificate's SHA-1
#                         when several certificates share a name.
#   NOTARY_PROFILE        notarytool keychain profile (local runs), otherwise an
#                         App Store Connect API key in ASC_KEY_PATH, ASC_KEY_ID
#                         and ASC_ISSUER_ID (CI).
#   SPARKLE_ED_PRIVATE_KEY  EdDSA private key (CI); otherwise the login keychain.
#   NOTES_FILE            release notes in Markdown; defaults to the annotated
#                         tag vX.Y.Z's message.
#   DOWNLOAD_URL_PREFIX   where the appcast points for the zip; defaults to the
#                         GitHub release (override for local update testing).
set -euo pipefail

usage() {
  echo "usage: $0 --version X.Y.Z [--identity <name|SHA-1>]" >&2
  exit 2
}

VERSION=""
IDENTITY="${SIGNING_IDENTITY:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift ;;
    --identity) IDENTITY="$2"; shift ;;
    *) usage ;;
  esac
  shift
done
[[ -n "$VERSION" && -n "$IDENTITY" ]] || usage

TEAM_ID="B5ZWKBCUTU"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT_DIR/dist/Clicker.app"
OUT="$ROOT_DIR/dist/release"
ZIP="$OUT/Clicker-$VERSION.zip"
DMG="$OUT/Clicker-$VERSION.dmg"
NOTES="$OUT/notes.md"
SPARKLE_BIN="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/jakejarvis/Clicker/releases/download/v$VERSION/}"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
else
  NOTARY_AUTH=(
    --key "${ASC_KEY_PATH:?set NOTARY_PROFILE, or ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID}"
    --key-id "${ASC_KEY_ID:?}"
    --issuer "${ASC_ISSUER_ID:?}"
  )
fi

# Submits a file and waits. Apple's log is always saved next to the output, and
# anything but Accepted fails the release.
notarize() {
  local file="$1" name result id status
  name="$(basename "$file")"
  echo "==> Notarizing $name"
  result="$(xcrun notarytool submit "$file" "${NOTARY_AUTH[@]}" --wait --timeout 45m --output-format json)" || true
  id="$(plutil -extract id raw - <<<"$result" 2>/dev/null)" || { echo "notarytool submit failed: $result" >&2; exit 1; }
  status="$(plutil -extract status raw - <<<"$result" 2>/dev/null)" || status="unknown"
  xcrun notarytool log "$id" "${NOTARY_AUTH[@]}" "$OUT/notary-$name.json" >/dev/null || true
  if [[ "$status" != "Accepted" ]]; then
    echo "Notarization of $name is $status (submission $id):" >&2
    cat "$OUT/notary-$name.json" >&2 || true
    exit 1
  fi
}

rm -rf "$OUT"
mkdir -p "$OUT"

"$ROOT_DIR/script/package_app.sh" --release --universal --sign "$IDENTITY" --version "$VERSION"

# A zip can't be stapled, so notarize the app inside a throwaway zip, staple
# the app itself, then archive the stapled app.
ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
notarize "$OUT/notarize.zip"
rm "$OUT/notarize.zip"
xcrun stapler staple "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> Building $(basename "$DMG")"
STAGING="$(mktemp -d)"
ditto "$APP" "$STAGING/Clicker.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname Clicker -srcfolder "$STAGING" -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGING"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

echo "==> Verifying"
codesign --verify --deep --strict "$APP"
SIGNATURE="$(codesign -dvv "$APP" 2>&1)"
grep -q "TeamIdentifier=$TEAM_ID" <<<"$SIGNATURE" || { echo "app is not signed by team $TEAM_ID" >&2; exit 1; }
grep -q "flags=.*runtime" <<<"$SIGNATURE" || { echo "app is missing the hardened runtime" >&2; exit 1; }
xcrun stapler validate "$APP"
xcrun stapler validate "$DMG"
syspolicy_check distribution "$APP"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

echo "==> Writing appcast"
if [[ -n "${NOTES_FILE:-}" ]]; then
  cp "$NOTES_FILE" "$NOTES"
elif [[ "$(git -C "$ROOT_DIR" cat-file -t "v$VERSION" 2>/dev/null)" == "tag" ]]; then
  git -C "$ROOT_DIR" tag -l --format='%(contents:subject)%0a%0a%(contents:body)' "v$VERSION" >"$NOTES"
else
  : >"$NOTES"
fi
FEED_DIR="$(mktemp -d)"
cp "$ZIP" "$FEED_DIR/"
if [[ -s "$NOTES" ]]; then
  cp "$NOTES" "$FEED_DIR/Clicker-$VERSION.md"
fi
FEED_ARGS=(
  --download-url-prefix "$DOWNLOAD_URL_PREFIX"
  --embed-release-notes
  --link "https://clicker.jarv.is"
  -o "$OUT/appcast.xml"
  "$FEED_DIR"
)
if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$SPARKLE_BIN/generate_appcast" --ed-key-file - "${FEED_ARGS[@]}"
else
  "$SPARKLE_BIN/generate_appcast" "${FEED_ARGS[@]}"
fi
rm -rf "$FEED_DIR"

echo "Release $VERSION is in $OUT"

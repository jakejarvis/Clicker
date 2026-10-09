#!/usr/bin/env bash
# Renders Resources/AppIcon.icon with Icon Composer's ictool and refreshes the
# site's icon PNGs. Previews land in dist/icon/<rendition>.png; open them to
# check every appearance without installing the app.
# Usage: script/render_icon.sh [size]   (preview size in px, default 512)
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON="$ROOT_DIR/Resources/AppIcon.icon"
ICTOOL="$(dirname "$(xcode-select -p)")/Applications/Icon Composer.app/Contents/Executables/ictool"
[[ -x "$ICTOOL" ]] || ICTOOL="/Applications/Icon Composer.app/Contents/Executables/ictool"
[[ -x "$ICTOOL" ]] || { echo "ictool not found: install Icon Composer (ships with Xcode 26+)" >&2; exit 1; }
SIZE="${1:-512}"
OUT="$ROOT_DIR/dist/icon"
mkdir -p "$OUT"

render() { # <output> <rendition> <size>
  "$ICTOOL" "$ICON" --export-image --output-file "$1" --platform macOS --rendition "$2" \
    --width "$3" --height "$3" --scale 1 >/dev/null
}

for rendition in Default Dark ClearLight ClearDark TintedLight TintedDark; do
  render "$OUT/$rendition.png" "$rendition" "$SIZE"
done
render "$OUT/Default-64.png" Default 64
echo "wrote previews to $OUT"

render "$ROOT_DIR/site/public/icon.png" Default 160
render "$ROOT_DIR/site/src/assets/icon.png" Default 160
render "$ROOT_DIR/site/public/favicon.png" Default 64
echo "refreshed site icons"

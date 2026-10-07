#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from script/make_icon.swift.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

swift "$ROOT_DIR/script/make_icon.swift" "$WORK/icon_1024.png" >/dev/null

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$WORK/icon_1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$WORK/icon_1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

mkdir -p "$ROOT_DIR/Resources"
iconutil -c icns "$ICONSET" -o "$ROOT_DIR/Resources/AppIcon.icns"
cp "$WORK/icon_1024.png" "$ROOT_DIR/Resources/AppIcon-1024.png"
rm -rf "$WORK"
echo "wrote Resources/AppIcon.icns"

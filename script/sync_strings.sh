#!/usr/bin/env bash
# Bring Sources/ClickerApp/Resources/Localizable.xcstrings in line with the code.
# Usage: script/sync_strings.sh [--check]
#   --check  change nothing; fail if the catalog is missing strings the code
#            uses or still lists strings it no longer does (CI runs this)
#
# The compiler writes a .stringsdata file next to each object file, listing
# every literal it typed as LocalizedStringKey, LocalizedStringResource or
# String(localized:), with the right format specifiers. xcstringstool merges
# those into the catalog: new strings are added, vanished ones marked stale,
# and translations are kept. This is what Xcode does on build; SwiftPM only
# emits the files.
set -euo pipefail

CHECK=0
case "${1:-}" in
  --check) CHECK=1 ;;
  "") ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="$ROOT_DIR/Sources/ClickerApp/Resources/Localizable.xcstrings"
cd "$ROOT_DIR"

# ClickerApp builds ClickerCompanion too, whose error messages reach the UI.
# The demo target's strings are made up and stay out of the catalog.
swift build --target ClickerApp
INTERMEDIATES="$(dirname "$(swift build --show-bin-path)")"
INTERMEDIATES="${INTERMEDIATES%/Products}/Intermediates.noindex"
STRINGSDATA=()
while IFS= read -r file; do
  # A deleted source file's stringsdata lingers in the build directory.
  source="$(plutil -extract source raw -o - "$file")"
  [[ -f "$source" ]] && STRINGSDATA+=("$file")
done < <(find "$INTERMEDIATES" -path "*/Debug/ClickerApp-t.build/*" -name "*.stringsdata" -o \
  -path "*/Debug/ClickerCompanion-t.build/*" -name "*.stringsdata")
if [[ ${#STRINGSDATA[@]} == 0 ]]; then
  echo "no .stringsdata under $INTERMEDIATES; did the build layout change?" >&2
  exit 1
fi

if [[ "$CHECK" == 1 ]]; then
  # xcstringstool names the table after the file, so the copy keeps the name.
  SCRATCH="$(mktemp -d)"
  trap 'rm -rf "$SCRATCH"' EXIT
  cp "$CATALOG" "$SCRATCH/"
  xcrun xcstringstool sync "$SCRATCH/$(basename "$CATALOG")" --stringsdata "${STRINGSDATA[@]}"
  if ! diff -u "$CATALOG" "$SCRATCH/$(basename "$CATALOG")"; then
    echo "Localizable.xcstrings is out of date; run script/sync_strings.sh and commit the result." >&2
    exit 1
  fi
  echo "Localizable.xcstrings is up to date"
else
  xcrun xcstringstool sync "$CATALOG" --stringsdata "${STRINGSDATA[@]}"
  echo "Synced $(xcrun xcstringstool print "$CATALOG" | wc -l | tr -d ' ') strings into $CATALOG"
fi

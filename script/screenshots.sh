#!/usr/bin/env bash
# Shoot the Mac App Store screenshots from the demo build into dist/screenshots/:
# one 2880×1800 PNG (2560×1600 on a display under 1440×900 points) per line of
# script/screenshots.txt and appearance, plus the raw captures in raw/.
# Usage: script/screenshots.sh [--version X.Y.Z] [--no-build] [--appearance dark|light] [--out <dir>]
#                              [--keep-menu-bar] [scenario...]
#   --version        the version Settings shows; defaults to the latest tag's
#   --no-build       reuse dist/Clicker.app (it must be an --app-store --with-demo build)
#   --appearance     only this set; both by default (dark needs the system in Dark Mode)
#   --out            write here instead of dist/screenshots, which is replaced on every run
#   --keep-menu-bar  leave the menu bar as it is instead of emptying it
#   scenario...      only these lines of screenshots.txt
# Needs Screen Recording for the terminal, and every window on the main
# display closed or hidden while it runs; see docs/app-store.md.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/Clicker.app"
CAPTIONS="$ROOT_DIR/script/screenshots.txt"
# Seconds from launch to capture: the panel opens after half a second and the
# scenario's steps (a popover, pair-setup) take up to about two more.
SETTLE="${SCREENSHOT_SETTLE:-4}"

BUILD=1
VERSION=""
APPEARANCE=""
OUT_DIR="$ROOT_DIR/dist/screenshots"
FRAME_FLAGS=()
ONLY=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift ;;
    --no-build) BUILD=0 ;;
    --appearance) APPEARANCE="$2"; shift ;;
    --out) OUT_DIR="$2"; shift ;;
    --keep-menu-bar) FRAME_FLAGS+=(--keep-menu-bar) ;;
    -*)
      echo "usage: $0 [--version X.Y.Z] [--no-build] [--appearance dark|light] [--out <dir>] [--keep-menu-bar] [scenario...]" >&2
      exit 2
      ;;
    *) ONLY+=("$1") ;;
  esac
  shift
done
RAW_DIR="$OUT_DIR/raw"

SCENARIOS=()
HEADLINES=()
SUBHEADS=()
while IFS='|' read -r scenario headline subhead; do
  scenario="$(echo "$scenario" | xargs)"
  [[ -z "$scenario" || "$scenario" == \#* ]] && continue
  if [[ ${#ONLY[@]} -gt 0 && " ${ONLY[*]} " != *" $scenario "* ]]; then continue; fi
  SCENARIOS+=("$scenario")
  HEADLINES+=("$(echo "$headline" | sed -e 's/^ *//' -e 's/ *$//')")
  SUBHEADS+=("$(echo "$subhead" | sed -e 's/^ *//' -e 's/ *$//')")
done < "$CAPTIONS"
if [[ ${#SCENARIOS[@]} -eq 0 ]]; then
  echo "no scenarios to shoot; check $CAPTIONS" >&2
  exit 2
fi

# The App Store flavor, so Settings has no Updates section, at the version
# the listing is for.
if [[ "$BUILD" == 1 ]]; then
  [[ -z "$VERSION" ]] && VERSION="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 | sed 's/^v//')"
  "$ROOT_DIR/script/package_app.sh" --app-store --with-demo --version "$VERSION"
fi
WORK_DIR="$(mktemp -d)"
TOOL="$WORK_DIR/screenshot_tool"
swiftc -O "$ROOT_DIR/script/screenshot_tool.swift" -o "$TOOL"
"$TOOL" check

# The light set is forced per process; a dark one needs the system in Dark Mode.
SYSTEM_DARK=0
[[ "$(defaults read -g AppleInterfaceStyle 2>/dev/null || true)" == "Dark" ]] && SYSTEM_DARK=1
case "$APPEARANCE" in
  "")
    if [[ "$SYSTEM_DARK" == 1 ]]; then
      APPEARANCES=(dark light)
    else
      APPEARANCES=(light)
      echo "The system is in Light Mode, so only the light set will be shot. Switch to Dark Mode for both."
    fi
    ;;
  dark)
    if [[ "$SYSTEM_DARK" != 1 ]]; then
      echo "the dark set needs the system in Dark Mode" >&2
      exit 2
    fi
    APPEARANCES=(dark)
    ;;
  light) APPEARANCES=(light) ;;
  *)
    echo "--appearance must be dark or light: $APPEARANCE" >&2
    exit 2
    ;;
esac

# A copy of Clicker that was already running (an installed one) is quit for
# the duration, since its status item would show too, and reopened after.
RUNNING_APP=""
if pids="$(pgrep -x Clicker)"; then
  RUNNING_APP="$(ps -o comm= -p "${pids%%$'\n'*}" | sed 's#/Contents/MacOS/.*##')"
  [[ "$RUNNING_APP" == "$APP_BUNDLE" ]] && RUNNING_APP=""
fi
DESKTOP_ICONS="$(defaults read com.apple.finder CreateDesktop 2>/dev/null || echo unset)"

quit_clicker() {
  pkill -x Clicker >/dev/null 2>&1 || true
  while pgrep -x Clicker >/dev/null; do sleep 0.2; done
}

restore() {
  quit_clicker
  case "$DESKTOP_ICONS" in
    unset) defaults delete com.apple.finder CreateDesktop 2>/dev/null || true ;;
    1|true|YES) defaults write com.apple.finder CreateDesktop -bool true ;;
    *) defaults write com.apple.finder CreateDesktop -bool false ;;
  esac
  killall Finder 2>/dev/null || true
  [[ -n "$RUNNING_APP" ]] && /usr/bin/open "$RUNNING_APP"
  rm -rf "$WORK_DIR"
}
trap restore EXIT

quit_clicker
defaults write com.apple.finder CreateDesktop -bool false
killall Finder 2>/dev/null || true
rm -rf "$OUT_DIR"
mkdir -p "$RAW_DIR"

echo "Close or hide (⌘H) every window on the main display, this terminal's too. The panel's glass shows what's behind it."
"$TOOL" wait-clear 300
"$TOOL" park-pointer
sleep 1
screencapture -x -D 1 "$RAW_DIR/clean.png"

for appearance in "${APPEARANCES[@]}"; do
  for i in "${!SCENARIOS[@]}"; do
    scenario="${SCENARIOS[$i]}"
    name="$(printf '%02d' $((i + 1)))-$scenario-$appearance"
    arguments=(--demo "$scenario")
    [[ "$appearance" == light ]] && arguments+=(-NSRequiresAquaSystemAppearance YES)
    /usr/bin/open -n "$APP_BUNDLE" --args "${arguments[@]}"
    sleep "$SETTLE"
    "$TOOL" wait-clear 300
    "$TOOL" park-pointer
    screencapture -x -D 1 "$RAW_DIR/$name.png"
    subhead=()
    [[ -n "${SUBHEADS[$i]}" ]] && subhead=(--subhead "${SUBHEADS[$i]}")
    "$TOOL" frame --pid "$(pgrep -x Clicker | head -1)" --clean "$RAW_DIR/clean.png" --shot "$RAW_DIR/$name.png" \
      --out "$OUT_DIR/$name.png" --headline "${HEADLINES[$i]}" ${subhead[@]+"${subhead[@]}"} \
      ${FRAME_FLAGS[@]+"${FRAME_FLAGS[@]}"}
    quit_clicker
    echo "$OUT_DIR/$name.png"
  done
done

afplay /System/Library/Sounds/Glass.aiff 2>/dev/null || true

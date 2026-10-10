#!/usr/bin/env bash
# Captures Clicker's --demo scenarios in a VMPal macOS VM, in light and dark
# mode, as lossless PNGs at the guest's native resolution, with the stock menu
# bar and wallpaper and the clock at 9:41. Each scenario gives three:
#   <scenario>.png         the whole screen
#   <scenario>-corner.png  the menu bar's right end with the panel below it
#   <scenario>-panel.png   the panel on the wallpaper, a little room around it
# The crops come from the one full capture: a window capture alone loses the
# glass, which shows what is behind it, and macOS puts its screen recording
# dot in the menu bar from the second capture in a row.
#
# Usage: script/screenshots.sh [--install] <VM> [scenario...]
#   --install      build a release app and install it in the VM first
#   OUT=<dir>      where the PNGs go (default dist/screenshots)
#   APPEARANCES    "light dark" by default
#   VMPAL          the vmpal command (default: the one on PATH)
#
# The VM needs, once: agent control (VMPal › the VM's Settings › AI Agents),
# administrator commands approved there (for the clock; without them the real
# time shows), and Screen Recording allowed for VMPal Tools in the guest (so
# screencapture works). Leave the guest's desktop as it should appear.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${OUT:-$ROOT_DIR/dist/screenshots}"
read -r -a APPEARANCES <<<"${APPEARANCES:-light dark}"
GUEST_DIR=/tmp/clicker-screenshots
# By absolute path: vmpal cp refuses to run when invoked by bare name.
VMPAL="${VMPAL:-$(command -v vmpal || true)}"
[[ -n "$VMPAL" ]] || { echo "vmpal not found; link it from VMPal.app (vmpal.com/docs/command-line)" >&2; exit 1; }

INSTALL=0
VM=""
SCENARIOS=()
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    *) if [[ -z "$VM" ]]; then VM="$arg"; else SCENARIOS+=("$arg"); fi ;;
  esac
done
[[ -n "$VM" ]] || { echo "usage: script/screenshots.sh [--install] <VM> [scenario...]" >&2; exit 2; }
if [[ ${#SCENARIOS[@]} -eq 0 ]]; then
  SCENARIOS=(ready asleep typing settings pair pin paired offline searching choose)
fi

guest() { "$VMPAL" exec "$VM" -- /bin/sh -c "$1"; }

# The panel's frame in points, "x y width height", then the screen's width in
# points and its scale: Clicker's on-screen window at pop-up menu level (101).
# JXA reads the window list without Screen Recording or Apple Events access.
PANEL_FRAME_JXA='ObjC.import("CoreGraphics"); ObjC.import("AppKit");
const list = ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly, 0));
let frame = "";
for (let i = 0; i < list.count; i++) {
  const w = list.objectAtIndex(i);
  if (ObjC.unwrap(w.objectForKey("kCGWindowOwnerName")) === "Clicker"
    && ObjC.unwrap(w.objectForKey("kCGWindowLayer")) === 101) {
    const b = ObjC.deepUnwrap(w.objectForKey("kCGWindowBounds"));
    frame = [b.X, b.Y, b.Width, b.Height].map(Math.round).join(" ");
  }
}
frame && [frame, $.CGDisplayPixelsWide($.CGMainDisplayID()), $.NSScreen.mainScreen.backingScaleFactor].join(" ")'

if [[ "$INSTALL" == 1 ]]; then
  "$ROOT_DIR/script/package_app.sh" --release --with-demo
  # A zip keeps Sparkle.framework's symlinks intact on the way in.
  zip_dir="$(mktemp -d)"
  ditto -c -k --keepParent "$ROOT_DIR/dist/Clicker.app" "$zip_dir/Clicker.zip"
  "$VMPAL" cp "$zip_dir/Clicker.zip" "$VM:/tmp/Clicker.zip"
  rm -rf "$zip_dir"
  guest "pkill -x Clicker; rm -rf /Applications/Clicker.app && ditto -x -k /tmp/Clicker.zip /Applications && rm /tmp/Clicker.zip"
fi

# 9:41 needs root; network time goes back on at the end.
CLOCK=0
if "$VMPAL" exec --admin "$VM" -- /usr/sbin/systemsetup -setusingnetworktime off >/dev/null 2>&1; then
  CLOCK=1
else
  echo "Administrator commands are not approved in this VM; the real time will show." >&2
fi

cleanup() {
  guest "pkill -x Clicker; rm -rf $GUEST_DIR" || true
  if [[ "$CLOCK" == 1 ]]; then
    "$VMPAL" exec --admin "$VM" -- /usr/sbin/systemsetup -setusingnetworktime on >/dev/null || true
  fi
}
trap cleanup EXIT

set_clock() {
  [[ "$CLOCK" == 1 ]] || return 0
  "$VMPAL" exec --admin "$VM" -- /bin/sh -c 'date "$(date +%m%d)0941$(date +%Y).00"' >/dev/null
}

# Appearance through System Settings, which needs no Apple Events permission.
set_appearance() {
  local label
  case "$1" in
    light) label="Light" ;;
    dark) label="Dark" ;;
    *) echo "unknown appearance: $1" >&2; exit 2 ;;
  esac
  guest "open 'x-apple.systempreferences:com.apple.Appearance-Settings.extension'"
  # The first match is the Appearance row; "Dark" also labels an icon style.
  "$VMPAL" ui "$VM" act --observe none "[
    {\"action\": \"wait\", \"until\": {\"text\": \"Auto\"}, \"timeoutMs\": 15000},
    {\"action\": \"left_click\", \"target\": {\"text\": \"$label\", \"nth\": 1}},
    {\"action\": \"wait\", \"duration\": 1.5}]" >/dev/null
  guest "killall 'System Settings'"
  sleep 1
}

shoot() {
  local appearance="$1" scenario="$2"
  local dir="$GUEST_DIR/$appearance"
  guest "pkill -x Clicker; open -n /Applications/Clicker.app --args --demo $scenario"
  # Keep the pointer off the panel so no hover state or tooltip shows.
  "$VMPAL" ui "$VM" move 1279 400 >/dev/null
  # The panel opens half a second after launch, then animates its height.
  sleep 3
  set_clock
  local frame x y w h screen_width scale
  frame="$("$VMPAL" exec "$VM" -- /usr/bin/osascript -l JavaScript -e "$PANEL_FRAME_JXA")"
  [[ -n "$frame" ]] || { echo "$scenario: the panel did not open" >&2; return 1; }
  read -r x y w h screen_width scale <<<"$frame"
  scale="${scale%.*}"
  # Crops in pixels, as sips takes them: height width top left. The panel sits
  # right under the menu bar, so its crop starts at its top edge; the sides and
  # bottom leave room for the shadow.
  local corner_left=$((x - 200))
  local corner="$(((y + h + 60) * scale)) $(((screen_width - corner_left) * scale)) 0 $((corner_left * scale))"
  local panel="$(((h + 50) * scale)) $(((w + 80) * scale)) $((y * scale)) $(((x - 40) * scale))"
  guest "mkdir -p $dir && cd $dir && screencapture -x -t png $scenario.png \
    && crop() { sips -c \$1 \$2 --cropOffset \$3 \$4 $scenario.png --out \$5 >/dev/null; } \
    && crop $corner $scenario-corner.png && crop $panel $scenario-panel.png"
  echo "  $appearance/$scenario"
}

guest "rm -rf $GUEST_DIR"
for appearance in "${APPEARANCES[@]}"; do
  set_appearance "$appearance"
  for scenario in "${SCENARIOS[@]}"; do
    shoot "$appearance" "$scenario"
  done
done
set_appearance light

mkdir -p "$OUT"
"$VMPAL" cp "$VM:$GUEST_DIR/." "$OUT"
echo "Screenshots in $OUT"

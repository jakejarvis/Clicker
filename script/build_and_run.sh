#!/usr/bin/env bash
# Kill, build, stage a .app bundle and launch Clicker.
# Usage: script/build_and_run.sh [run|--debug|--logs|--telemetry|--verify] [--release] [--install]
#   --release  optimized build
#   --install  copy the bundle to /Applications and launch it from there
# Bundle assembly and signing live in script/package_app.sh.
set -euo pipefail

MODE="run"
RELEASE_FLAG=""
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --release) RELEASE_FLAG="--release" ;;
    --install) INSTALL=1 ;;
    *) MODE="$arg" ;;
  esac
done

APP_NAME="Clicker"
BUNDLE_ID="com.jakejarvis.Clicker"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

# Builds, stages dist/Clicker.app with Sparkle embedded and signs it ad hoc.
"$ROOT_DIR/script/package_app.sh" $RELEASE_FLAG

if [[ "$INSTALL" == 1 ]]; then
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
  APP_BUNDLE="/Applications/$APP_NAME.app"
  APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    echo "$APP_NAME is running"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify] [--release] [--install]" >&2
    exit 2
    ;;
esac

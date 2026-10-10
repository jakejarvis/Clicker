#!/usr/bin/env bash
# Build Clicker and assemble a signed dist/Clicker.app with Sparkle embedded.
# Usage: script/package_app.sh [--release] [--with-demo] [--universal] [--sign <identity>] [--version X.Y.Z]
#   --release    optimized build; leaves out --demo unless --with-demo is also given
#   --with-demo  compile the --demo scenarios in (debug builds always have them)
#   --universal  arm64 + x86_64
#   --sign       codesigning identity (name or SHA-1). The default "-" signs ad hoc
#                for local runs and drops SUFeedURL so dev builds never update.
#                A real identity also embeds Resources/Clicker.provisionprofile and
#                signs with Resources/Clicker.entitlements so the app can use the
#                data protection keychain for pairings.
#   --version    marketing version; defaults to $CLICKER_VERSION or 0.1.0
set -euo pipefail

CONFIGURATION="debug"
WITH_DEMO=0
UNIVERSAL=0
IDENTITY="-"
VERSION="${CLICKER_VERSION:-0.1.0}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) CONFIGURATION="release" ;;
    --with-demo) WITH_DEMO=1 ;;
    --universal) UNIVERSAL=1 ;;
    --sign) IDENTITY="$2"; shift ;;
    --version) VERSION="$2"; shift ;;
    *)
      echo "usage: $0 [--release] [--with-demo] [--universal] [--sign <identity>] [--version X.Y.Z]" >&2
      exit 2
      ;;
  esac
  shift
done

# Sparkle compares CFBundleVersion, so derive an integer that grows with the
# version: 1.2.3 -> 10203. Minor and patch stay below 100 to keep it monotonic.
if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]?)\.(0|[1-9][0-9]?)$ ]]; then
  echo "version must be X.Y.Z with minor and patch below 100: $VERSION" >&2
  exit 2
fi
BUILD_NUMBER=$(( BASH_REMATCH[1] * 10000 + BASH_REMATCH[2] * 100 + BASH_REMATCH[3] ))

APP_NAME="Clicker"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
APP_BINARY="$CONTENTS/MacOS/$APP_NAME"
INFO_PLIST="$CONTENTS/Info.plist"
SPARKLE_SOURCE="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
SPARKLE="$CONTENTS/Frameworks/Sparkle.framework"
ENTITLEMENTS="$ROOT_DIR/Resources/Clicker.entitlements"
PROFILE="$ROOT_DIR/Resources/Clicker.provisionprofile"

BUILD_FLAGS=(-c "$CONFIGURATION")
if [[ "$WITH_DEMO" == 1 && "$CONFIGURATION" == "release" ]]; then
  # Package.swift already defines DEMO for debug builds; this adds it to release ones.
  BUILD_FLAGS+=(-Xswiftc -DDEMO)
fi
if [[ "$UNIVERSAL" == 1 ]]; then
  BUILD_FLAGS+=(--arch arm64 --arch x86_64)
fi

cd "$ROOT_DIR"
swift build "${BUILD_FLAGS[@]}"
BUILD_BINARY="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)/$APP_NAME"
if [[ "$UNIVERSAL" == 1 ]]; then
  for arch in arm64 x86_64; do
    lipo "$BUILD_BINARY" -verify_arch "$arch" || { echo "missing $arch slice" >&2; exit 1; }
  done
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"
cp "$BUILD_BINARY" "$APP_BINARY"
# The app icon is an Icon Composer document. actool compiles it into Assets.car
# (the Liquid Glass icon macOS 26+ renders live) plus AppIcon.icns for macOS 15.
xcrun actool "$ROOT_DIR/Resources/AppIcon.icon" --compile "$CONTENTS/Resources" \
  --app-icon AppIcon --include-all-app-icons \
  --platform macosx --minimum-deployment-target 15.0 \
  --output-partial-info-plist "$ROOT_DIR/dist/AppIcon-Info.plist" \
  --output-format human-readable-text >/dev/null
mkdir -p "$CONTENTS/Resources/StatusIcon"
cp "$ROOT_DIR"/Resources/StatusIcon/*.pdf "$CONTENTS/Resources/StatusIcon/"

cp "$ROOT_DIR/Resources/Info.plist" "$INFO_PLIST"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$INFO_PLIST"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$INFO_PLIST"
plutil -replace NSHumanReadableCopyright -string "Copyright © $(date +%Y) Jake Jarvis" "$INFO_PLIST"
if [[ "$IDENTITY" == "-" ]]; then
  plutil -remove SUFeedURL "$INFO_PLIST"
else
  # The keychain entitlements are restricted: macOS only honors them when a
  # provisioning profile vouches for them, and kills a Developer ID app that
  # carries them without one. Ad-hoc builds get neither and store pairings in a
  # file instead.
  [[ -f "$PROFILE" ]] || { echo "missing $PROFILE (Developer ID profile for com.jakejarvis.Clicker)" >&2; exit 1; }
  cp "$PROFILE" "$CONTENTS/embedded.provisionprofile"
fi

# ditto keeps the framework's symlinks. The XPC services are only for sandboxed
# apps, and headers are build-time only.
ditto "$SPARKLE_SOURCE" "$SPARKLE"
for item in XPCServices Headers PrivateHeaders Modules; do
  rm -rf "${SPARKLE:?}/$item" "${SPARKLE:?}/Versions/B/$item"
done

# SwiftPM leaves rpaths into .build and the toolchain. Keep only the system Swift
# runtime and point @rpath at Contents/Frameworks so the bundled Sparkle loads.
# The linker's signature goes first; editing a signed binary only adds warnings.
codesign --remove-signature "$APP_BINARY"
otool -l "$APP_BINARY" |
  awk '/cmd LC_RPATH/ { getline; getline; sub(/^ *path /, ""); sub(/ \(offset [0-9]+\)$/, ""); print }' | sort -u |
  while read -r rpath; do
    if [[ "$rpath" != "/usr/lib/swift" ]]; then
      install_name_tool -delete_rpath "$rpath" "$APP_BINARY"
    fi
  done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"

# Sign inside out and never with --deep (Sparkle's and Apple's guidance). A real
# identity gets the hardened runtime and a secure timestamp for notarization;
# ad-hoc keeps TCC (local network) and launch at login stable between dev runs.
SIGN_FLAGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then
  SIGN_FLAGS+=(--options runtime --timestamp)
fi
for item in "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app" "$SPARKLE"; do
  codesign "${SIGN_FLAGS[@]}" "$item"
done
if [[ "$IDENTITY" != "-" ]]; then
  SIGN_FLAGS+=(--entitlements "$ENTITLEMENTS")
fi
codesign "${SIGN_FLAGS[@]}" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

# The profile vouches for particular certificates. A Developer ID certificate
# it does not list (the keychain can hold several for one team) signs without
# complaint and leaves an app launchd refuses to spawn ("Launch failed", POSIX
# error 163) with nothing in the AMFI log, so compare them here.
if [[ "$IDENTITY" != "-" ]]; then
  CHECK_DIR="$(mktemp -d)"
  codesign -d --extract-certificates="$CHECK_DIR/cert" "$APP_BUNDLE" 2>/dev/null
  [[ -f "$CHECK_DIR/cert0" ]] || { echo "could not read the signing certificate from $APP_BUNDLE" >&2; exit 1; }
  SIGNER="$(shasum "$CHECK_DIR/cert0" | awk '{print toupper($1)}')"
  security cms -D -i "$PROFILE" > "$CHECK_DIR/profile.plist"
  CERT_COUNT="$(plutil -extract DeveloperCertificates raw "$CHECK_DIR/profile.plist")"
  LISTED=0
  for ((i = 0; i < CERT_COUNT; i++)); do
    FINGERPRINT="$(plutil -extract "DeveloperCertificates.$i" raw "$CHECK_DIR/profile.plist" | base64 -d | shasum | awk '{print toupper($1)}')"
    [[ "$FINGERPRINT" == "$SIGNER" ]] && LISTED=1
  done
  rm -rf "$CHECK_DIR"
  if [[ "$LISTED" == 0 ]]; then
    echo "signing certificate $SIGNER is not in $PROFILE; macOS will refuse to launch the app." >&2
    echo "Sign with one the profile lists (security find-identity -v -p codesigning) or regenerate the profile." >&2
    exit 1
  fi
fi

echo "Packaged $APP_BUNDLE ($VERSION, build $BUILD_NUMBER)"

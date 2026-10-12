#!/usr/bin/env bash
# Build Clicker and assemble a signed dist/Clicker.app with Sparkle embedded.
# Usage: script/package_app.sh [--release] [--with-demo] [--universal] [--native] [--sign <identity>] [--version X.Y.Z]
#                              [--app-store [--installer <identity>]]
#   --release    optimized build; leaves out --demo unless --with-demo is also given
#   --with-demo  compile the --demo scenarios in (debug builds always have them)
#   --universal  arm64 + x86_64
#   --native     SwiftPM's native build system, which links against the installed
#                SDK like CI does; the default (Swift Build on 6.4) records sdk 15.0,
#                under which AppKit draws some controls differently (see AGENTS.md)
#   --sign       codesigning identity (name or SHA-1). The default "-" signs ad hoc
#                for local runs and drops SUFeedURL so dev builds never update.
#                A real identity also embeds Resources/Clicker.provisionprofile and
#                signs with Resources/Clicker.entitlements so the app can use the
#                data protection keychain for pairings.
#   --version    marketing version; defaults to $CLICKER_VERSION or 0.1.0
#   --app-store  Mac App Store flavor: built without the Sparkle trait (no
#                updater, no framework, no SU* keys) and sandboxed with
#                Resources/Clicker-AppStore.entitlements. With a real identity
#                (Apple Distribution) it embeds Resources/Clicker-AppStore.provisionprofile;
#                ad hoc it keeps only the sandbox keys, for trying the sandbox locally.
#   --installer  Mac Installer Distribution identity; with --app-store, also
#                writes dist/Clicker.pkg for upload with Transporter
set -euo pipefail

CONFIGURATION="debug"
WITH_DEMO=0
UNIVERSAL=0
NATIVE=0
IDENTITY="-"
APP_STORE=0
INSTALLER=""
VERSION="${CLICKER_VERSION:-0.1.0}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) CONFIGURATION="release" ;;
    --with-demo) WITH_DEMO=1 ;;
    --universal) UNIVERSAL=1 ;;
    --native) NATIVE=1 ;;
    --sign) IDENTITY="$2"; shift ;;
    --version) VERSION="$2"; shift ;;
    --app-store) APP_STORE=1 ;;
    --installer) INSTALLER="$2"; shift ;;
    *)
      echo "usage: $0 [--release] [--with-demo] [--universal] [--native] [--sign <identity>] [--version X.Y.Z] [--app-store [--installer <identity>]]" >&2
      exit 2
      ;;
  esac
  shift
done
if [[ -n "$INSTALLER" && "$APP_STORE" != 1 ]]; then
  echo "--installer only applies to --app-store" >&2
  exit 2
fi
if [[ -n "$INSTALLER" && "$IDENTITY" == "-" ]]; then
  echo "--installer needs --sign with an Apple Distribution identity" >&2
  exit 2
fi

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
PROFILE_KIND="Developer ID"
PKG="$ROOT_DIR/dist/$APP_NAME.pkg"

BUILD_FLAGS=(-c "$CONFIGURATION")
if [[ "$WITH_DEMO" == 1 && "$CONFIGURATION" == "release" ]]; then
  # Package.swift already defines DEMO for debug builds; this adds it to release ones.
  BUILD_FLAGS+=(-Xswiftc -DDEMO)
fi
if [[ "$APP_STORE" == 1 ]]; then
  # The App Store updates the app, and rule 2.4.5(vii) allows no other updater,
  # so Sparkle stays out of the binary entirely, not just switched off.
  BUILD_FLAGS+=(--disable-default-traits)
  ENTITLEMENTS="$ROOT_DIR/Resources/Clicker-AppStore.entitlements"
  PROFILE="$ROOT_DIR/Resources/Clicker-AppStore.provisionprofile"
  PROFILE_KIND="Mac App Store"
fi
if [[ "$UNIVERSAL" == 1 ]]; then
  BUILD_FLAGS+=(--arch arm64 --arch x86_64)
fi
if [[ "$NATIVE" == 1 ]]; then
  BUILD_FLAGS+=(--build-system native)
fi

cd "$ROOT_DIR"
swift build "${BUILD_FLAGS[@]}"
BUILD_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"
# KeyboardShortcuts localizes its recorder from a SwiftPM resource bundle whose
# generated accessor looks only in Contents/Resources and crashes without it.
SHORTCUTS_BUNDLE="$BUILD_DIR/KeyboardShortcuts_KeyboardShortcuts.bundle"
[[ -d "$SHORTCUTS_BUNDLE" ]] || { echo "missing $SHORTCUTS_BUNDLE" >&2; exit 1; }
if [[ "$UNIVERSAL" == 1 ]]; then
  for arch in arm64 x86_64; do
    lipo "$BUILD_BINARY" -verify_arch "$arch" || { echo "missing $arch slice" >&2; exit 1; }
  done
fi

rm -rf "$APP_BUNDLE" "$PKG"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BUILD_BINARY" "$APP_BINARY"
# The app icon is an Icon Composer document. actool compiles it into Assets.car
# (the Liquid Glass icon macOS 26+ renders live) plus AppIcon.icns for macOS 15.
xcrun actool "$ROOT_DIR/Resources/AppIcon.icon" --compile "$CONTENTS/Resources" \
  --app-icon AppIcon --include-all-app-icons \
  --platform macosx --minimum-deployment-target 15.0 \
  --output-partial-info-plist "$ROOT_DIR/dist/AppIcon-Info.plist" \
  --output-format human-readable-text >/dev/null
cp "$ROOT_DIR/Resources/PrivacyInfo.xcprivacy" "$CONTENTS/Resources/PrivacyInfo.xcprivacy"
mkdir -p "$CONTENTS/Resources/StatusIcon"
cp "$ROOT_DIR"/Resources/StatusIcon/*.pdf "$CONTENTS/Resources/StatusIcon/"
ditto "$SHORTCUTS_BUNDLE" "$CONTENTS/Resources/$(basename "$SHORTCUTS_BUNDLE")"

cp "$ROOT_DIR/Resources/Info.plist" "$INFO_PLIST"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$INFO_PLIST"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$INFO_PLIST"
plutil -replace NSHumanReadableCopyright -string "Copyright © $(date +%Y) Jake Jarvis" "$INFO_PLIST"
if [[ "$APP_STORE" == 1 ]]; then
  for key in SUFeedURL SUPublicEDKey SUEnableAutomaticChecks SUAllowsAutomaticUpdates; do
    plutil -remove "$key" "$INFO_PLIST"
  done
elif [[ "$IDENTITY" == "-" ]]; then
  plutil -remove SUFeedURL "$INFO_PLIST"
fi
if [[ "$IDENTITY" != "-" ]]; then
  # The keychain entitlements are restricted: macOS only honors them when a
  # provisioning profile vouches for them, and kills an app that carries them
  # without one. Ad-hoc builds get neither and store pairings in a file instead.
  [[ -f "$PROFILE" ]] || { echo "missing $PROFILE ($PROFILE_KIND profile for com.jakejarvis.Clicker)" >&2; exit 1; }
  cp "$PROFILE" "$CONTENTS/embedded.provisionprofile"
elif [[ "$APP_STORE" == 1 ]]; then
  # The sandbox keys are not restricted, so an ad-hoc App Store build keeps
  # them and runs sandboxed locally; only the keychain keys need a profile.
  ADHOC_ENTITLEMENTS="$(mktemp -d)/Clicker.entitlements"
  cp "$ENTITLEMENTS" "$ADHOC_ENTITLEMENTS"
  for key in com.apple.application-identifier com.apple.developer.team-identifier keychain-access-groups; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$ADHOC_ENTITLEMENTS"
  done
  ENTITLEMENTS="$ADHOC_ENTITLEMENTS"
fi

if [[ "$APP_STORE" != 1 ]]; then
  # ditto keeps the framework's symlinks. The XPC services are only for
  # sandboxed apps, and headers are build-time only.
  mkdir -p "$CONTENTS/Frameworks"
  ditto "$SPARKLE_SOURCE" "$SPARKLE"
  for item in XPCServices Headers PrivateHeaders Modules; do
    rm -rf "${SPARKLE:?}/$item" "${SPARKLE:?}/Versions/B/$item"
  done
fi

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
if [[ "$APP_STORE" != 1 ]]; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"
fi

# Sign inside out and never with --deep (Sparkle's and Apple's guidance). A real
# identity gets the hardened runtime and a secure timestamp for notarization;
# ad-hoc keeps TCC (local network) and launch at login stable between dev runs.
SIGN_FLAGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then
  SIGN_FLAGS+=(--options runtime --timestamp)
fi
if [[ "$APP_STORE" != 1 ]]; then
  for item in "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app" "$SPARKLE"; do
    codesign "${SIGN_FLAGS[@]}" "$item"
  done
fi
codesign "${SIGN_FLAGS[@]}" "$CONTENTS/Resources/$(basename "$SHORTCUTS_BUNDLE")"
if [[ "$IDENTITY" != "-" || "$APP_STORE" == 1 ]]; then
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

if [[ -n "$INSTALLER" ]]; then
  productbuild --component "$APP_BUNDLE" /Applications --sign "$INSTALLER" "$PKG"
  echo "Packaged $PKG"
fi

echo "Packaged $APP_BUNDLE ($VERSION, build $BUILD_NUMBER)"

#!/usr/bin/env bash
# Build Clicker and assemble a signed dist/Clicker.app with Sparkle embedded.
# Usage: script/package_app.sh [--release] [--with-demo] [--universal] [--sign <identity>] [--version X.Y.Z]
#                              [--app-store [--installer <identity>] [--build N]]
#   --release    optimized build
#   --with-demo  stage the ClickerDemo executable (the app plus the --demo scenarios)
#                instead of Clicker; for development only, never for a release
#   --universal  arm64 + x86_64
#   --sign       codesigning identity (name or SHA-1). The default "-" signs ad hoc
#                for local runs and drops SUFeedURL so dev builds never update.
#                Every build is sandboxed (Resources/Clicker.entitlements). A real
#                identity also embeds Resources/Clicker.provisionprofile and keeps the
#                file's keychain entitlements so the app can use the data protection
#                keychain for pairings; ad-hoc builds sign without them.
#   --version    marketing version; defaults to $CLICKER_VERSION or 0.1.0
#   --app-store  Mac App Store flavor: built without the Sparkle trait (no updater,
#                no framework, no SU* keys) and signed without Sparkle's mach-lookup
#                exceptions. A real identity (Apple Distribution) embeds
#                Resources/Clicker-AppStore.provisionprofile instead. See docs/app-store.md.
#   --installer  Mac Installer Distribution identity; with --app-store, also writes
#                dist/Clicker.pkg for upload with Transporter
#   --build      with --app-store, resubmission number N (1-99): CFBundleVersion becomes
#                the version's own (1.2.3 -> 10203) plus .N, so a rejected build
#                can be uploaded again without a new version
set -euo pipefail

CONFIGURATION="debug"
WITH_DEMO=0
UNIVERSAL=0
IDENTITY="-"
APP_STORE=0
INSTALLER=""
RESUBMISSION=""
VERSION="${CLICKER_VERSION:-0.1.0}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) CONFIGURATION="release" ;;
    --with-demo) WITH_DEMO=1 ;;
    --universal) UNIVERSAL=1 ;;
    --sign) IDENTITY="$2"; shift ;;
    --version) VERSION="$2"; shift ;;
    --app-store) APP_STORE=1 ;;
    --installer) INSTALLER="$2"; shift ;;
    --build) RESUBMISSION="$2"; shift ;;
    *)
      echo "usage: $0 [--release] [--with-demo] [--universal] [--sign <identity>] [--version X.Y.Z] [--app-store [--installer <identity>] [--build N]]" >&2
      exit 2
      ;;
  esac
  shift
done
if [[ "$WITH_DEMO" == 1 && ( "$IDENTITY" != "-" || "$APP_STORE" == 1 ) ]]; then
  echo "--with-demo is for ad-hoc development builds; it can't be signed or built for the App Store" >&2
  exit 2
fi
if [[ -n "$INSTALLER" && "$APP_STORE" != 1 ]]; then
  echo "--installer only applies to --app-store" >&2
  exit 2
fi
if [[ -n "$INSTALLER" && "$IDENTITY" == "-" ]]; then
  echo "--installer needs --sign with an Apple Distribution identity" >&2
  exit 2
fi
if [[ -n "$RESUBMISSION" && "$APP_STORE" != 1 ]]; then
  # Sparkle compares CFBundleVersion too; its builds keep the plain number.
  echo "--build only applies to --app-store" >&2
  exit 2
fi
# Two digits keep CFBundleVersion short (10203.99 at most) and are plenty.
if [[ -n "$RESUBMISSION" && ! "$RESUBMISSION" =~ ^[1-9][0-9]?$ ]]; then
  echo "--build must be a number from 1 to 99: $RESUBMISSION" >&2
  exit 2
fi

# Sparkle compares CFBundleVersion, so derive an integer that grows with the
# version: 1.2.3 -> 10203. Minor and patch stay below 100 to keep it monotonic.
if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]?)\.(0|[1-9][0-9]?)$ ]]; then
  echo "version must be X.Y.Z with minor and patch below 100: $VERSION" >&2
  exit 2
fi
BUILD_NUMBER=$(( BASH_REMATCH[1] * 10000 + BASH_REMATCH[2] * 100 + BASH_REMATCH[3] ))
# App Store Connect refuses a build number it has seen. 10203.1 sorts after
# 10203 and before the next version's 10204.
if [[ -n "$RESUBMISSION" ]]; then
  BUILD_NUMBER="$BUILD_NUMBER.$RESUBMISSION"
fi

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
SIGNING_ENTITLEMENTS="$ROOT_DIR/dist/$APP_NAME.entitlements"
PKG="$ROOT_DIR/dist/$APP_NAME.pkg"

cd "$ROOT_DIR"
# AppKit and SwiftUI pick some looks by the SDK recorded in LC_BUILD_VERSION,
# and Swift Build (SwiftPM 6.4's default) records the deployment target there
# instead of the SDK it compiled against. Pass the real pair to the linker so
# local builds look like the ones users get; the check after the build keeps
# it that way.
[[ "$(swift package dump-package | plutil -extract platforms.0.platformName raw -o - -)" == "macos" ]] ||
  { echo "expected macOS as the package's first platform" >&2; exit 1; }
DEPLOYMENT_TARGET="$(swift package dump-package | plutil -extract platforms.0.version raw -o - -)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
BUILD_FLAGS=(-c "$CONFIGURATION"
  -Xlinker -platform_version -Xlinker macos -Xlinker "$DEPLOYMENT_TARGET" -Xlinker "$SDK_VERSION")
if [[ "$APP_STORE" == 1 ]]; then
  # The App Store updates the app, and rule 2.4.5(vii) allows no other updater,
  # so Sparkle stays out of the binary entirely, not just switched off.
  # Resolving without the trait would rewrite Package.resolved without Sparkle's
  # pin; take the pinned versions as they are instead.
  BUILD_FLAGS+=(--disable-default-traits --force-resolved-versions)
  PROFILE="$ROOT_DIR/Resources/Clicker-AppStore.provisionprofile"
  PROFILE_KIND="Mac App Store"
fi
if [[ "$UNIVERSAL" == 1 ]]; then
  BUILD_FLAGS+=(--arch arm64 --arch x86_64)
fi

# Clicker is what ships. ClickerDemo is the same app with the demo scenarios,
# a separate executable so they never reach a release.
PRODUCT="$APP_NAME"
if [[ "$WITH_DEMO" == 1 ]]; then
  PRODUCT="ClickerDemo"
fi
swift build "${BUILD_FLAGS[@]}" --product "$PRODUCT"
BUILD_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$PRODUCT"
# Every slice must record the SDK it was built against (docs/development.md).
LINKED_SDKS="$(xcrun vtool -show-build "$BUILD_BINARY" | awk '$1 == "sdk" { print $2 }' | sort -u)"
if [[ "$LINKED_SDKS" != "$SDK_VERSION" ]]; then
  echo "$APP_NAME records sdk $(echo $LINKED_SDKS) but was built with the $SDK_VERSION SDK" >&2
  exit 1
fi
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
  --platform macosx --minimum-deployment-target "$DEPLOYMENT_TARGET" \
  --output-partial-info-plist "$ROOT_DIR/dist/AppIcon-Info.plist" \
  --output-format human-readable-text >/dev/null
mkdir -p "$CONTENTS/Resources/StatusIcon"
cp "$ROOT_DIR"/Resources/StatusIcon/*.pdf "$CONTENTS/Resources/StatusIcon/"
ditto "$SHORTCUTS_BUNDLE" "$CONTENTS/Resources/$(basename "$SHORTCUTS_BUNDLE")"
# Required-reason APIs (UserDefaults), which App Store uploads check.
cp "$ROOT_DIR/Resources/PrivacyInfo.xcprivacy" "$CONTENTS/Resources/"
# Moves what an unsandboxed Clicker (0.2.x) kept in ~/Library into the new
# container the first time a sandboxed one launches.
cp "$ROOT_DIR/Resources/container-migration.plist" "$CONTENTS/Resources/"

cp "$ROOT_DIR/Resources/Info.plist" "$INFO_PLIST"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$INFO_PLIST"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$INFO_PLIST"
plutil -replace NSHumanReadableCopyright -string "Copyright © $(date +%Y) Jake Jarvis" "$INFO_PLIST"
if [[ "$APP_STORE" == 1 ]]; then
  for key in SUFeedURL SUPublicEDKey SUEnableAutomaticChecks SUAllowsAutomaticUpdates SUEnableInstallerLauncherService; do
    plutil -remove "$key" "$INFO_PLIST"
  done
  # Export compliance: declared exempt so App Store Connect stops asking on
  # every upload. A choice made before the first upload, not Apple's verdict.
  plutil -insert ITSAppUsesNonExemptEncryption -bool NO "$INFO_PLIST"
elif [[ "$IDENTITY" == "-" ]]; then
  plutil -remove SUFeedURL "$INFO_PLIST"
fi
if [[ "$IDENTITY" != "-" ]]; then
  # The keychain entitlements are restricted: macOS only honors them when a
  # provisioning profile vouches for them, and kills an app that carries them
  # without one. Ad-hoc builds get neither and store pairings in a file instead.
  [[ -f "$PROFILE" ]] || { echo "missing $PROFILE ($PROFILE_KIND profile for com.jakejarvis.Clicker)" >&2; exit 1; }
  cp "$PROFILE" "$CONTENTS/embedded.provisionprofile"
fi

if [[ "$APP_STORE" != 1 ]]; then
  # ditto keeps the framework's symlinks. A sandboxed app cannot launch Sparkle's
  # installer itself, so it keeps Installer.xpc (SUEnableInstallerLauncherService
  # in Info.plist, the -spks/-spki mach-lookup exceptions in the entitlements).
  # Downloader.xpc is only for apps without network.client, and headers are
  # build-time only.
  mkdir -p "$CONTENTS/Frameworks"
  ditto "$SPARKLE_SOURCE" "$SPARKLE"
  rm -rf "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
  for item in Headers PrivateHeaders Modules; do
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

# Files copied from Resources keep their extended attributes, and a profile
# downloaded in a browser carries com.apple.quarantine, which App Store
# Connect rejects (error 91109). Nothing in the bundle needs any, so clear them
# all before signing.
xattr -cr "$APP_BUNDLE"

# Sign inside out and never with --deep (Sparkle's and Apple's guidance). A real
# identity gets the hardened runtime and a secure timestamp for notarization;
# ad-hoc keeps TCC (local network) and launch at login stable between dev runs.
SIGN_FLAGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then
  SIGN_FLAGS+=(--options runtime --timestamp)
fi
if [[ "$APP_STORE" != 1 ]]; then
  for item in "$SPARKLE/Versions/B/XPCServices/Installer.xpc" \
    "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app" "$SPARKLE"; do
    codesign "${SIGN_FLAGS[@]}" "$item"
  done
fi
codesign "${SIGN_FLAGS[@]}" "$CONTENTS/Resources/$(basename "$SHORTCUTS_BUNDLE")"
# Resources/Clicker.entitlements is the whole set; each flavor signs with a copy
# minus what it can't carry.
UNSIGNED_KEYS=()
if [[ "$APP_STORE" == 1 ]]; then
  # Only Sparkle's installer services need these, and App Review questions
  # temporary exceptions.
  UNSIGNED_KEYS+=(com.apple.security.temporary-exception.mach-lookup.global-name)
fi
if [[ "$IDENTITY" == "-" ]]; then
  # The restricted keychain entitlements would get an ad-hoc binary killed by
  # AMFI; the sandbox ones are fine without a profile.
  UNSIGNED_KEYS+=(com.apple.application-identifier com.apple.developer.team-identifier keychain-access-groups)
fi
cp "$ENTITLEMENTS" "$SIGNING_ENTITLEMENTS"
for key in ${UNSIGNED_KEYS[@]+"${UNSIGNED_KEYS[@]}"}; do
  /usr/libexec/PlistBuddy -c "Delete :$key" "$SIGNING_ENTITLEMENTS"
done
SIGN_FLAGS+=(--entitlements "$SIGNING_ENTITLEMENTS")
codesign "${SIGN_FLAGS[@]}" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

# The profile vouches for particular certificates. A signing certificate
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

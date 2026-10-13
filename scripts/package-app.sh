#!/usr/bin/env bash
# Makes Canteiro.app and installs it to /Applications. Re-run it after code
# changes to update the installed app.
#
# --release signs it with a Developer ID, has Apple notarize it, and leaves
# dist/Canteiro-<version>.zip, ready for GitHub Releases. It needs a
# "Developer ID Application" certificate in the keychain and notarytool
# credentials saved once with:
#   xcrun notarytool store-credentials canteiro-notary --apple-id <email> --team-id <team>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Canteiro"
BUNDLE_ID="com.amongthestones.canteiro"
BINARY_NAME="Canteiro"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
INSTALL_DIR="${CANTEIRO_INSTALL_DIR:-/Applications}"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ICON_SOURCE="$ROOT/Resources/AppIcon.icon"
INSTALL=1
RELEASE=0
# The Developer ID to sign with (the first one in the keychain unless set),
# and the notarytool credentials' name.
SIGN_ID="${CANTEIRO_SIGN_ID:-}"
NOTARY_PROFILE="${CANTEIRO_NOTARY_PROFILE:-canteiro-notary}"

# Prefer an annotated release tag (vX.Y.Z); fall back for untagged checkouts.
VERSION="$(git -C "$ROOT" describe --tags --match 'v*' --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
VERSION="${CANTEIRO_VERSION:-${VERSION:-0.1.0}}"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"

for arg in "$@"; do
  case "$arg" in
    --no-install) INSTALL=0 ;;
    --release) RELEASE=1; INSTALL=0 ;;
    -h|--help)
      echo "Usage: $0 [--no-install] [--release]"
      echo "  Builds dist/Canteiro.app and copies it to $INSTALL_DIR"
      echo "  Compiles the icon from Resources/AppIcon.icon (made by scripts/make-icon.py)."
      echo "  CANTEIRO_INSTALL_DIR overrides the install location."
      echo "  --release: Developer ID signing, notarizing and a zip in dist/; doesn't install."
      echo "  CANTEIRO_SIGN_ID and CANTEIRO_NOTARY_PROFILE pick the identity and credentials."
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (try --help)" >&2
      exit 1
      ;;
  esac
done

cd "$ROOT"
swift build -c release --product "$BINARY_NAME"

BINARY="$(swift build -c release --show-bin-path)/$BINARY_NAME"
if [[ ! -x "$BINARY" ]]; then
  echo "error: built binary not found at $BINARY" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BINARY" "$MACOS/$BINARY_NAME"

# SwiftPM records the deployment target as the SDK version, and macOS
# uses that number to pick the design: an app "built for" an older macOS runs in
# compatibility mode, without Liquid Glass or the floating sidebar. Stamp
# the SDK it was actually built with.
SDK_VERSION="$(xcrun --show-sdk-version)"
MIN_VERSION="$(sed -n 's/.*\.macOS(\.v\([0-9]*\)).*/\1/p' "$ROOT/Package.swift").0"
xcrun vtool -set-build-version macos "$MIN_VERSION" "$SDK_VERSION" -replace \
  -output "$MACOS/$BINARY_NAME" "$MACOS/$BINARY_NAME"
chmod +x "$MACOS/$BINARY_NAME"

# The schema reader runs with the site's Node; the app finds it in Resources.
cp "$ROOT/scripts/schema-dump.mjs" "$RESOURCES/schema-dump.mjs"

# The Icon Composer icon becomes Assets.car, which macOS 26 draws in light,
# dark and tinted styles, plus AppIcon.icns for anything older that looks.
HAS_ICON=0
if [[ -d "$ICON_SOURCE" ]]; then
  icon_work="$(mktemp -d "${TMPDIR:-/tmp}/canteiro-icon.XXXXXX")"
  xcrun actool "$ICON_SOURCE" --compile "$RESOURCES" --platform macosx \
    --minimum-deployment-target "$MIN_VERSION" --app-icon AppIcon \
    --output-partial-info-plist "$icon_work/icon.plist" >/dev/null
  rm -rf "$icon_work"
  HAS_ICON=1
  echo "Icon: compiled Resources/AppIcon.icon"
else
  echo "warning: no Resources/AppIcon.icon; run scripts/make-icon.py. The app gets the default icon." >&2
fi

{
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>${BINARY_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key>
	<string>${APP_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${BUILD_NUMBER}</string>
EOF
  if [[ "$HAS_ICON" -eq 1 ]]; then
    cat <<'EOF'
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIconName</key>
	<string>AppIcon</string>
EOF
  fi
  cat <<EOF
	<key>LSMinimumSystemVersion</key>
	<string>${MIN_VERSION}</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.productivity</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
EOF
} > "$CONTENTS/Info.plist"

if [[ "$RELEASE" -eq 0 ]]; then
  # Ad-hoc sign so macOS will launch it from Finder on this machine.
  codesign --force --sign - --timestamp=none "$APP"
  echo "Made: $APP (version $VERSION, build $BUILD_NUMBER)"
else
  if [[ -z "$SIGN_ID" ]]; then
    SIGN_ID="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
  fi
  if [[ -z "$SIGN_ID" ]]; then
    echo "error: no Developer ID Application certificate in the keychain" >&2
    exit 1
  fi
  # The hardened runtime, which notarizing requires. Canteiro runs node, git
  # and cwebp as their own programs, which it allows without entitlements.
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
  codesign --verify --strict --verbose=1 "$APP"
  echo "Signed: $APP with $SIGN_ID"

  ZIP="$DIST/$APP_NAME-$VERSION.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Notarizing (this usually takes a few minutes)…"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  # Attach Apple's ticket to the app so it opens offline too, then zip the
  # stapled app for release.
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  spctl --assess --type execute --verbose=2 "$APP"
  echo "Ready: $ZIP (version $VERSION, build $BUILD_NUMBER)"
  exit 0
fi

if [[ "$INSTALL" -eq 1 ]]; then
  # Quit a running copy so Finder/LaunchServices pick up the new binary.
  if pgrep -xq "$BINARY_NAME" >/dev/null 2>&1; then
    echo "Quitting running Canteiro…"
    pkill -x "$BINARY_NAME" || true
    sleep 0.5
  fi
  mkdir -p "$INSTALL_DIR"
  rm -rf "$INSTALL_DIR/$APP_NAME.app"
  cp -R "$APP" "$INSTALL_DIR/"
  # Nudge LaunchServices / Finder to refresh the icon.
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true
  echo "Installed: $INSTALL_DIR/$APP_NAME.app"
  echo "Launch from Spotlight or Applications. Re-run this script to update."
else
  echo "Skipped install (--no-install). Copy manually if needed:"
  echo "  cp -R \"$APP\" \"$INSTALL_DIR/\""
fi

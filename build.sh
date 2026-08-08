#!/bin/zsh
# Builds "iPod Connect.app" into ./build, with Sparkle embedded for auto-updates.
# For local development only — ad-hoc signed, not notarized. See release.sh
# for producing a distributable, appcast-published build.
set -e
cd "$(dirname "$0")"

swift build -c release

APP="build/iPod Connect.app"
FRAMEWORK_SRC=$(find .build/artifacts -type d -iname "Sparkle.framework" -path "*macos*" | head -1)
if [[ -z "$FRAMEWORK_SRC" ]]; then
  echo "error: couldn't find built Sparkle.framework — run 'swift package resolve' first" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp .build/release/iPodConnect "$APP/Contents/MacOS/iPodConnect"
cp Resources/Info.plist "$APP/Contents/Info.plist"
ditto "$FRAMEWORK_SRC" "$APP/Contents/Frameworks/Sparkle.framework"

# ipodpatcher: a separate GPL executable, launched as a subprocess for the
# Rockbox bootloader step. Never linked into the app binary — see
# Vendor/ipodpatcher/README.md.
Vendor/ipodpatcher/build.sh >/dev/null
cp build/ipodpatcher "$APP/Contents/Resources/ipodpatcher"
chmod +x "$APP/Contents/Resources/ipodpatcher"

# The executable's Sparkle reference is @rpath-relative; point that rpath at
# the standard app-bundle Frameworks location.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/iPodConnect"

VERSION=$(cat VERSION 2>/dev/null || echo "0.0.0")
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo "1")
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"

# Ad-hoc sign: fine for running locally: not sufficient for a clean
# Gatekeeper experience on a machine that isn't this one. See release.sh /
# docs/DISTRIBUTION.md for the notarized path once you have a Developer ID.
codesign --force --deep --sign - "$APP"

echo "Built $APP  (version $VERSION, build $BUILD_NUMBER)"

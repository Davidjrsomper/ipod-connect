#!/bin/zsh
# Builds Fidelity.app into ./build
set -e
cd "$(dirname "$0")"

swift build -c release

APP=build/Fidelity.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Fidelity "$APP/Contents/MacOS/Fidelity"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"

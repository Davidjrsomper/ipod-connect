#!/bin/zsh
# Cuts a release: builds Fidelity.app, zips it, signs the update with the
# Sparkle EdDSA key from Keychain (see generate_update_keys.sh), and
# regenerates releases/appcast.xml.
#
# Usage:
#   scripts/release.sh [version]        # defaults to the VERSION file
#   scripts/release.sh 1.1.0            # also updates the VERSION file
#
# After this finishes, publish the contents of releases/ (the new .zip
# and the updated appcast.xml) to wherever SUFeedURL in Info.plist points
# — see docs/DISTRIBUTION.md. This script does not push or upload anything
# itself.
set -e
cd "$(dirname "$0")/.."

./scripts/fetch_sparkle_tools.sh

if [[ -n "$1" ]]; then
  echo "$1" > VERSION
fi
VERSION=$(cat VERSION)
APP_NAME="Fidelity"

# Where the zip will actually be downloaded from once published — a GitHub
# Release's asset URL, one directory per tag. Override by exporting
# GITHUB_REPO=you/your-repo before running, or by editing this default.
GITHUB_REPO="${GITHUB_REPO:-davidsomper/fidelity}"
DOWNLOAD_URL_PREFIX="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/"

if grep -q "__SPARKLE_PUBLIC_ED_KEY__" Resources/Info.plist; then
  echo "error: Resources/Info.plist still has the placeholder SUPublicEDKey." >&2
  echo "Run scripts/generate_update_keys.sh once before your first release." >&2
  exit 1
fi

echo "Building $APP_NAME $VERSION…"
./build.sh

mkdir -p releases
ZIP="releases/${APP_NAME}-${VERSION}.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "build/${APP_NAME}.app" "$ZIP"
echo "Archived $ZIP"

NOTES="releases/${APP_NAME}-${VERSION}.html"
if [[ ! -f "$NOTES" ]]; then
  cat > "$NOTES" <<EOF
<h3>${APP_NAME} ${VERSION}</h3>
<ul>
  <li>See the commit log for what changed.</li>
</ul>
EOF
  echo "Wrote placeholder release notes to $NOTES — edit before publishing."
fi

echo "Signing update and regenerating appcast…"
.tools/bin/generate_appcast --download-url-prefix "$DOWNLOAD_URL_PREFIX" releases/

echo ""
echo "Done. Two separate places to publish to:"
echo "  1. Upload $ZIP as a GitHub Release asset tagged v${VERSION}"
echo "     (gh release create v${VERSION} '$ZIP' '$NOTES' --title 'Fidelity ${VERSION}')"
echo "  2. Publish releases/appcast.xml wherever SUFeedURL points"
echo "     (see docs/DISTRIBUTION.md)"

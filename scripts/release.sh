#!/bin/zsh
# Cuts a release: builds "iPod Connect.app", zips it, signs the update with the
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
APP_NAME="iPodConnect"
APP_BUNDLE="iPod Connect"

# Where the zip will actually be downloaded from once published — a GitHub
# Release's asset URL, one directory per tag. Override by exporting
# GITHUB_REPO=you/your-repo before running, or by editing this default.
GITHUB_REPO="${GITHUB_REPO:-Davidjrsomper/ipod-connect}"
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
ditto -c -k --sequesterRsrc --keepParent "build/${APP_BUNDLE}.app" "$ZIP"
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
# --maximum-deltas 0: no binary delta patches. GitHub rewrites spaces in
# asset filenames to dots ("iPod Connect12-9.delta" becomes
# "iPod.Connect12-9.delta"), so the URL the appcast generates 404s. The app is
# only ~2 MB, so full-zip updates cost little and never break.
# --maximum-versions 1: only the newest build belongs in the feed. Older
# entries keep the current tag's URL prefix, which 404s, and Sparkle only
# needs the latest version to decide whether to offer an update.
.tools/bin/generate_appcast --maximum-deltas 0 --maximum-versions 1 \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" releases/

# A stable-named copy for the website's Download button. Uploading this to
# every release means https://github.com/<repo>/releases/latest/download/
# iPodConnect.zip always fetches the newest build, so the site never needs
# editing when you ship an update. Kept outside releases/ so it doesn't
# confuse generate_appcast, which treats every archive in there as a version.
mkdir -p dist
cp "$ZIP" "dist/${APP_NAME}.zip"
echo "Stable download copy: dist/${APP_NAME}.zip"

# docs/ is what GitHub Pages serves: the website and the Sparkle feed live
# together, so SUFeedURL keeps resolving after every release.
mkdir -p docs
cp releases/appcast.xml docs/appcast.xml
cp web/index.html docs/index.html
echo "Updated docs/ for GitHub Pages (site + appcast)"

echo ""
echo "Done. Two separate places to publish to:"
echo "  1. Upload $ZIP as a GitHub Release asset tagged v${VERSION}"
echo "     (gh release create v${VERSION} '$ZIP' '$NOTES' --title 'iPod Connect ${VERSION}')"
echo "  2. Publish releases/appcast.xml wherever SUFeedURL points"
echo "     (see docs/DISTRIBUTION.md)"

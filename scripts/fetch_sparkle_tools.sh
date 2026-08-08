#!/bin/zsh
# Downloads Sparkle's prebuilt CLI tools (generate_keys, sign_update,
# generate_appcast) into .tools/bin — not vendored in git, fetched on demand
# so release.sh and generate_update_keys.sh work on a clean checkout.
set -e
cd "$(dirname "$0")/.."

SPARKLE_VERSION="2.9.5"
if [[ -x .tools/bin/sign_update ]]; then
  exit 0
fi

echo "Fetching Sparkle $SPARKLE_VERSION CLI tools…"
mkdir -p .tools
curl -sL -o .tools/sparkle-tools.tar.xz \
  "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
tar -xf .tools/sparkle-tools.tar.xz -C .tools
chmod +x .tools/bin/generate_keys .tools/bin/sign_update .tools/bin/generate_appcast
echo "Done."

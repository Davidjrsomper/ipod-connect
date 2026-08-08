#!/bin/zsh
# One-time setup: generates the EdDSA keypair Sparkle uses to sign and
# verify updates. The private key goes in this Mac's Keychain (never on
# disk, never in git). The public key gets baked into Info.plist so the
# app can verify updates signed with the matching private key.
#
# Run this once, before your first release.sh. If you ever rebuild on a
# different machine, either export the Keychain item (Keychain Access →
# search "Private key for signing Sparkle updates" → export) or re-run
# this and re-publish the new public key (old update packages signed with
# the previous key will stop verifying, so only do this if you have to).
set -e
cd "$(dirname "$0")/.."

./scripts/fetch_sparkle_tools.sh

echo "Generating Sparkle EdDSA signing key in this Mac's Keychain…"
KEYGEN_OUTPUT=$(.tools/bin/generate_keys 2>&1)
echo "$KEYGEN_OUTPUT"
PUBLIC_KEY=$(echo "$KEYGEN_OUTPUT" | grep -o '<string>[^<]*</string>' | sed -e 's/<string>//' -e 's/<\/string>//')

if [[ -z "$PUBLIC_KEY" ]]; then
  echo ""
  echo "Couldn't auto-detect the public key line above — copy the value"
  echo "generate_keys printed for SUPublicEDKey and paste it into"
  echo "Resources/Info.plist yourself, replacing __SPARKLE_PUBLIC_ED_KEY__."
  exit 1
fi

/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC_KEY" Resources/Info.plist
echo ""
echo "Public key written to Resources/Info.plist:"
echo "  $PUBLIC_KEY"
echo ""
echo "Commit that change. The private key stays in Keychain — do not export"
echo "it into the repo."

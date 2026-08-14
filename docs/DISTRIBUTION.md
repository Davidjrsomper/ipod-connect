# Distribution & Updates

How iPod Connect gets built, published, and how existing installs receive
updates.

## One-time setup

### 1. Generate the update signing key

```bash
scripts/generate_update_keys.sh
```

This creates an EdDSA keypair. The **private key** is stored in this Mac's
Keychain (as "Private key for signing Sparkle updates") and never touches
the repo. The **public key** is written into `Resources/Info.plist` as
`SUPublicEDKey`.

Every update is signed with the private key; the app verifies it against
the embedded public key before installing. This is what stops someone
from serving a malicious "update": it works entirely independently of
Apple.

> **Back up the private key.** Keychain Access → search "Sparkle" →
> export. If you lose it, existing installs can never be updated again;
> you'd have to ship a new public key, which only reaches people who
> download fresh.

### 2. Pick where the appcast lives

`SUFeedURL` in `Resources/Info.plist` currently points at:

```
https://davidsomper.github.io/ipod-connect/appcast.xml
```

The appcast is a small XML file listing available versions. It must be
served over **HTTPS** at a stable URL. GitHub Pages is the easy option:
create a `gh-pages` branch (or `/docs` folder) in the repo and publish
`appcast.xml` there.

Change `SUFeedURL` if you host it elsewhere. It has to be set *before*
you ship v1.0.0. Installs check whatever URL was baked in at build time.

## Cutting a release

```bash
scripts/release.sh 1.1.0
```

That will:

1. Write `1.1.0` to `VERSION`
2. Build `build/iPod Connect.app` with Sparkle embedded
3. Zip it to `releases/iPodConnect-1.1.0.zip`
4. Sign the zip with the Keychain private key
5. Regenerate `releases/appcast.xml` with the new entry

Edit `releases/iPodConnect-1.1.0.html` (the release notes shown inside
the update dialog) before publishing; it's generated with a placeholder.

Then publish, in two places:

```bash
# 1. The app itself, as a GitHub Release asset
gh release create v1.1.0 "releases/iPodConnect-1.1.0.zip" \
  --title "iPod Connect 1.1.0" \
  --notes-file "releases/iPodConnect-1.1.0.html"

# 2. The appcast, wherever SUFeedURL points
cp releases/appcast.xml /path/to/gh-pages/ && (cd /path/to/gh-pages && git add -A && git commit -m "appcast 1.1.0" && git push)
```

The download URL baked into the appcast assumes the GitHub Release asset
layout above. Override the repo with `GITHUB_REPO=you/your-repo` if it
differs.

## How users receive updates

- On launch and every 24 hours (`SUScheduledCheckInterval`), the app
  fetches the appcast.
- If a newer `sparkle:shortVersionString` is listed, the user gets the
  standard Sparkle "A new version is available" dialog with release notes.
- They click Install; Sparkle verifies the signature, swaps the app, and
  relaunches.
- **Help → Check for Updates…** triggers a manual check.

Users on 1.0.0 will only ever see updates if 1.0.0 shipped with the
correct `SUFeedURL` and `SUPublicEDKey`. **Verify both before the first
public download.**

## The Gatekeeper problem

The build is **ad-hoc signed** (`codesign --sign -`), not signed with an
Apple Developer ID and not notarized. Consequences for anyone who is not
you:

- First launch shows *"Apple could not verify 'iPod Connect' is free of
  malware."*
- They must go to **System Settings → Privacy & Security** and click
  **"Open Anyway"**, then confirm again.
- On some macOS versions the app must be right-click → Open rather than
  double-clicked.

This does not block auto-updates (Sparkle's own signature check is what
matters there), but it *is* the biggest drop-off point for new users.
Your install instructions must spell out these steps or people will
assume the app is broken.

### Fixing it later

With an Apple Developer Program membership ($99/yr):

1. Create a "Developer ID Application" certificate.
2. In `build.sh`, replace `codesign --force --deep --sign -` with:
   ```
   codesign --force --options runtime --sign "Developer ID Application: Your Name (TEAMID)" "$APP"
   ```
   (Sign the embedded `Sparkle.framework` first, inside-out.)
3. Notarize and staple:
   ```
   xcrun notarytool submit "$ZIP" --apple-id you@example.com --team-id TEAMID --wait
   xcrun stapler staple "build/iPod Connect.app"
   ```
   then re-zip and re-run `generate_appcast`.

After that, downloads open with a normal double-click and no warnings.

## Architecture support

The current build is **Apple Silicon only**: it targets whatever
architecture the build machine has. Intel Mac users cannot run it.

Building universal (`swift build --arch arm64 --arch x86_64`) requires
full Xcode; the Command Line Tools alone are not enough, which is what
this machine has. To ship universal, either install Xcode or build the
two slices separately and merge with `lipo`. The appcast advertises
`sparkle:hardwareRequirements` so Intel users are correctly told the
update does not apply, rather than downloading something that won't run.

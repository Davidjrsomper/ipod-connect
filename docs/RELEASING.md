# Shipping a release

Everything below assumes the repo is `github.com/Davidjrsomper/ipod-connect`.
If you use a different name, change `GITHUB_REPO` in `scripts/release.sh`,
`SUFeedURL` in `Resources/Info.plist`, and the download links in
`web/index.html`.

## One-time setup

1. **Create the repo** on GitHub named `ipod-connect` (public).
2. **Push the code:**
   ```
   git remote add origin https://github.com/Davidjrsomper/ipod-connect.git
   git push -u origin main
   ```
3. **Turn on GitHub Pages:** repo Settings → Pages → Source: `main`, folder
   `/docs`. This publishes both the website and the Sparkle update feed at
   `https://davidjrsomper.github.io/ipod-connect/`.

## Every release

```
scripts/release.sh 1.0.0        # build, archive, sign, regenerate appcast
git add -A && git commit -m "Release 1.0.0" && git push
```

Then create the GitHub release and upload **both** archives:

```
gh release create v1.0.0 \
  "dist/iPodConnect.zip" \
  "releases/iPodConnect-1.0.0.zip" \
  --title "iPod Connect 1.0.0" \
  --notes-file "releases/iPodConnect-1.0.0.html"
```

(No `gh`? Do it in the browser: Releases → Draft a new release → tag `v1.0.0`
→ drag both zips in.)

Why two files:

| File | Purpose |
|---|---|
| `dist/iPodConnect.zip` | Stable name. The website's Download button points at `/releases/latest/download/iPodConnect.zip`, which always resolves to the newest release — so the site never needs editing. |
| `releases/iPodConnect-<version>.zip` | Versioned name. This is what `appcast.xml` references, so Sparkle can tell versions apart. |

## The Gatekeeper problem

Right now the app is **ad-hoc signed and not notarized**. `spctl -a` rejects
it, so anyone who downloads it sees *"iPod Connect cannot be opened because
Apple cannot verify it is free of malware."* They have to right-click → Open,
or approve it in System Settings → Privacy & Security.

Technical users will push through. Most people won't — and **paying**
customers definitely won't.

To fix it you need an Apple Developer account ($99/year), then:

```
codesign --force --deep --options runtime \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" "build/iPod Connect.app"

xcrun notarytool submit "dist/iPodConnect.zip" \
  --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PASSWORD --wait

xcrun stapler staple "build/iPod Connect.app"
```

Re-zip after stapling. Once that passes, the app opens with a normal
double-click and the Download button becomes a real product.

## If you later charge for it

- **Not the Mac App Store.** The app needs raw disk access (sandbox forbids
  it) and bundles GPL code (incompatible with App Store terms).
- **GPL compliance:** `ipodpatcher` is GPL v2 and ships inside the bundle. You
  may sell the app, but you must offer that tool's source to anyone who gets a
  copy and mustn't restrict them passing it on. It's a separate executable, not
  linked into the app binary, so the copyleft stops there. Link
  `Vendor/ipodpatcher/` from your sales page and you're covered.
- **Notarize first.** Selling an app that trips Gatekeeper generates refunds.
- **Wait for a confirmed flash.** The bootloader install is still unverified on
  real hardware and can brick a device. Charging for that before someone
  confirms it works is a support and liability problem.

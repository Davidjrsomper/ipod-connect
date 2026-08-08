# iPod Connect

A native macOS music player for local libraries — plays FLAC (which
macOS's own Music app still won't), browses your collection the way
iTunes used to, and turns into a working iPod classic when you want it
to.

<!-- TODO: screenshot / demo gif -->

## Features

- **Real FLAC support** — tags, cover art, sample rate and bit depth
  parsed natively from the FLAC container. No ffmpeg, no libFLAC.
- **Your existing folder** — point it at your music directory; nothing is
  moved, copied, or renamed. MP3, M4A, AAC, WAV, AIFF work too.
- **Three ways to browse** — a sortable song list, an artist column
  browser with album track listings, and an album cover grid.
- **iPod classic mode** — a working click wheel (drag it, or use a
  trackpad two-finger scroll), the split-screen menus, Now Playing,
  Cover art, Clock, and Settings.
- **Light and dark** — dark mode follows Apple's HIG palette; the iPod
  becomes the black anodized model.
- **Media keys and Now Playing** — the macOS Now Playing widget and your
  keyboard's play/pause keys work as expected.

## Requirements

macOS 14 or later, Apple Silicon.

## Installing

1. Download the latest `.zip` from
   [Releases](https://github.com/davidsomper/ipod-connect/releases).
2. Unzip and drag **iPod Connect** to your Applications folder.
3. **First launch:** macOS will say it "cannot verify" the app. This is
   because it isn't signed with a paid Apple Developer certificate — not
   because anything is wrong with it. To open it:
   - Right-click the app → **Open** → **Open**, or
   - **System Settings → Privacy & Security** → scroll down → **Open
     Anyway**

   You only have to do this once.

Once installed, the app checks for updates automatically and will offer
to install them.

## Building from source

Requires the Swift toolchain (Xcode or Command Line Tools).

```bash
git clone https://github.com/davidsomper/ipod-connect
cd ipod-connect
./build.sh
open "build/iPod Connect.app"
```

## Usage

| | |
|---|---|
| Choose your music folder | ⌘O |
| Rescan library | ⌘R |
| Play / pause | Space |
| Next / previous track | ⌘→ / ⌘← |
| Volume | ⌘↑ / ⌘↓ |
| Dark mode | ⇧⌘D |
| iPod view | ⇧⌘I |

In iPod view, drag around the click wheel to scroll, or use a two-finger
trackpad scroll. Tap MENU, ⏮, ⏭, ⏯ or the center button; menu rows are
also clickable directly.

## Documentation

- [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md) — releases, code
  signing, and how auto-updates work
- [`docs/GTM.md`](docs/GTM.md) — positioning and launch plan

## A note on the name

This project is not affiliated with, endorsed by, or connected to Apple
Inc. "iPod" and "iTunes" are trademarks of Apple Inc.

## License

TBD — see `docs/GTM.md` for the licensing discussion.

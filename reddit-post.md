# Reddit post draft — r/Modded_iPods

**Suggested title** (yours works; these are punchier for this crowd):

- `I built a native Apple Silicon iPod tool because ipodpatcher still ships as a 2010 PPC binary`
- `Native Mac app for Rockbox + FLAC — and a working arm64 ipodpatcher`
- `Building Mac Silicon software for iPod modders / lossless — looking for testers`

---

## Body

If you've tried to Rockbox an iPod from a modern Mac, you've probably hit this: the
only macOS `ipodpatcher` build Rockbox distributes is a **PPC/i386 binary from May
2010**. It hasn't run since Catalina killed 32-bit. On Apple Silicon you get `bad CPU
type in executable` and that's the end of it. The usual advice is "borrow a Windows
machine" or "boot a Linux VM."

That annoyed me enough to build something. It's a native SwiftUI Mac app that does
four things:

**1. Compiles ipodpatcher for arm64.** I built the Rockbox sources natively for Apple
Silicon and bundle it. It runs, and `--scan` correctly identifies devices and
permission state. As far as I can tell there hasn't been a working native macOS build
of this in years.

**2. Rockbox installer with a built-in theme browser.** Pulls the live catalogue from
themes.rockbox.org — 735 themes for iPod Video, filtered per target so you only see
skins that fit your screen — with previews, one-click install, and instant switching
between themes already on the device. Installs Rockbox 4.0 firmware too.

**3. Plays FLAC properly on the Mac side.** I wrote a native FLAC parser (Vorbis
comments, embedded cover art) so the library reads tags and artwork without any
third-party decoder. Native Core Audio playback, no transcoding.

**4. Syncs music to a Rockboxed iPod without iTunes or Finder.** Drag your library
across, remove tracks, see real free space. Since Rockbox reads plain files, it's just
a clean Artist/Album tree — no iTunesDB involved.

The UI is deliberately iTunes 10: brushed metal, the green LCD readout, Cover Flow with
reflections, the source list. There's also an iPod classic emulator mode where the whole
window becomes a 6G with a working click wheel you drive by dragging in circles.

---

### ⚠️ Read this before you flash anything

**I have not tested the bootloader install on real hardware.** I don't currently have an
iPod to test with. Everything else — theme install, firmware extraction, sync, detection,
capacity — I verified against a simulated FAT32 volume using the real Rockbox archives and
real music files. But the actual firmware-partition write is **unverified code that can
brick a device.** Don't run it on an iPod you care about until someone (maybe you, and
please report back) has confirmed it on a device they're willing to lose.

It does back up your firmware partition before writing and aborts if the backup fails,
but that's a safety net, not a substitute for testing.

Other honest limitations:

- **iPod Classic 6G/7G bootloader can't be automated** — it needs DFU mode + libusb, so
  the app links you to the proper instructions instead of pretending. Themes and firmware
  work fine on a Classic that's already Rockboxed.
- **Stock Apple firmware sync isn't supported.** Adding music to a non-Rockboxed iPod means
  writing iTunesDB (plus a device-specific hash on 6G/nano 3G+). Files alone are invisible
  to Apple's firmware, so I'd rather not half-do it.
- **Not notarized yet**, so Gatekeeper will warn on first launch and you'll need to
  right-click → Open. No Apple Developer account.

---

### What I'd genuinely like feedback on

1. **Does the bootloader install actually work on your hardware?** This is the big one.
   Mini, nano 1G/2G, 4G, Color, Video — any confirmation or failure report is valuable.
2. Is a native theme browser actually useful, or do you all just drop zips on the disk?
3. What's missing that would make this replace your current workflow — playlists,
   database rebuild, disk-mode toggling, battery info?
4. Would sync for stock (non-Rockboxed) iPods be worth the iTunesDB work, or has
   everyone here moved to Rockbox anyway?

Happy to answer anything technical about the arm64 build or the theme API — both had
some sharp edges I'd be glad to save someone else from.

# ipodpatcher (vendored)

Source for `ipodpatcher`, the tool that installs the Rockbox bootloader onto
the firmware partition of an iPod (1G–5.5G, mini, nano 1G/2G, colour, 4G).

Taken from the Rockbox source tree: `utils/ipodpatcher`.
Upstream: <https://git.rockbox.org/cgit/rockbox.git/tree/utils/ipodpatcher>

## Why it's vendored

The only macOS binary Rockbox distributes
(`download.rockbox.org/bootloader/ipod/ipodpatcher/macosx/ipodpatcher.dmg`)
is a **ppc/i386 build from May 2010**. It fails with `bad CPU type in
executable` on any Mac since macOS Catalina dropped 32-bit support, and
cannot run on Apple Silicon at all. Building from source is the only way
to get a working arm64 tool.

## Licence — important

ipodpatcher is **GPL v2**. It is built as a **standalone executable** that
iPod Connect launches as a subprocess. It is deliberately *not* linked into
the app binary, so the GPL's copyleft applies to this tool alone and does
not reach the rest of the app. Do not statically link these sources into
the main target.

## Building

```bash
Vendor/ipodpatcher/build.sh
```

Produces `build/ipodpatcher` (arm64), which `build.sh` copies into
`iPod Connect.app/Contents/Resources/`.

Built **without** `BOOTOBJS`, so it has no embedded bootloaders and no
interactive mode. iPod Connect downloads the bootloader from
`download.rockbox.org` and passes it with `-a <file>`.

## Commands used by the app

| Purpose | Command |
|---|---|
| Identify connected iPods | `ipodpatcher --scan` |
| Back up firmware partition | `ipodpatcher <dev> -r <backup.bin>` |
| Install bootloader | `ipodpatcher <dev> -a <bootloader.ipod>` |
| Remove bootloader | `ipodpatcher <dev> -d` |

All of these need raw disk access, so the app runs them via an
administrator prompt.

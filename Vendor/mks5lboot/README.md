# mks5lboot (vendored)

Source for `mks5lboot`, the tool that installs the Rockbox bootloader onto
an iPod Classic (6th/7th generation) over USB while the device is in DFU
mode.

Taken from the Rockbox source tree: `utils/mks5lboot`.
Upstream: <https://git.rockbox.org/cgit/rockbox.git/tree/utils/mks5lboot>

## Why it's vendored

Rockbox distributes this as source only for macOS — there's no prebuilt
binary. It's built here as a **universal (arm64 + x86_64) executable**,
using the native IOKit USB backend already present in the source, so it
needs no libusb and no third-party dependency.

## Licence — important

Like `ipodpatcher`, this is **GPL v2**. It is built as a **standalone
executable** that iPod Connect launches as a subprocess, deliberately
kept out of the app binary, so the GPL's copyleft applies to this tool
alone. Do not statically link these sources into the main target.

## Building

```bash
Vendor/mks5lboot/build.sh
```

Produces `build/mks5lboot` (universal), which `build.sh` copies into
`iPod Connect.app/Contents/Resources/`.

## Commands used by the app

| Purpose | Command |
|---|---|
| Scan for an iPod in DFU mode | `mks5lboot --dfuscan` |
| Install the bootloader | `mks5lboot --bl-inst <bootloader.ipod>` |

Unlike `ipodpatcher`, this needs no administrator password — the IOKit
USB backend doesn't require raw disk access.

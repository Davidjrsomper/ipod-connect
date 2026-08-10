# hash58 reference implementation

A self-contained C build of libgpod's `itdb_hash58.c` algorithm, used to
verify the Swift port in `Sources/iPodConnect/ITunesDB/ITunesDBHash58.swift`.

Without a real iPod there's no way to test the checksum against a device, but
libgpod's implementation is the de-facto reference — so the port is checked
against it directly rather than against assumptions.

```bash
clang -w -o ref58 ref58.c
./ref58 000A27001A2B3C4D 1024                     # C reference
"build/iPod Connect.app/Contents/MacOS/iPodConnect" \
    --verify-hash58 000A27001A2B3C4D 1024         # Swift port
```

Both print the same 20-byte hex digest. Verified across 5 FireWire IDs
(including all-zero and all-0xFF) at 108, 1024 and 65536 byte payloads:
15 of 15 matched.

Licence: derived from libgpod, LGPL v2.1. Kept out of the app target — it's a
test reference, never shipped.

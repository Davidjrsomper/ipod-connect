#!/bin/zsh
# Builds mks5lboot (universal) from the vendored Rockbox sources.
#
# This is the tool that installs the Rockbox bootloader on iPod Classic 6G/7G
# (and nano 3G/4G/5G), which use USB DFU rather than a firmware-partition
# write. Like ipodpatcher it is GPL v2 and is shipped as a SEPARATE executable
# launched as a subprocess — never linked into the app binary.
#
# Note it needs no libusb on macOS: the sources include a native IOKit USB
# backend, so there is nothing for the user to install. It also runs without
# root, unlike the ipodpatcher path.
set -e
cd "$(dirname "$0")"

OUT="../../build/mks5lboot"
mkdir -p "$(dirname "$OUT")"

clang -arch arm64 -arch x86_64 -O2 -DVERSION='"1.0-ipodconnect"' -o "$OUT" \
  main.c dualboot.c mkdfu.c ipoddfu.c \
  -framework IOKit -framework CoreFoundation

echo "Built $OUT ($(lipo -archs "$OUT"))"

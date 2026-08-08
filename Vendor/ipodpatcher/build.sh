#!/bin/zsh
# Builds ipodpatcher (arm64) from the vendored Rockbox sources.
# See README.md — this is a separate GPL-licensed executable, never linked
# into the app binary.
set -e
cd "$(dirname "$0")"

OUT="../../build/ipodpatcher"
mkdir -p "$(dirname "$OUT")"

# Universal: the app runs on Intel Macs too, so the bootloader tool must.
clang -arch arm64 -arch x86_64 -O2 -Wall -DVERSION='"5.0-ipodconnect"' -o "$OUT" \
  main.c ipodpatcher.c fat32format.c arc4.c ipodio-posix.c ipodpatcher_aupd.c \
  -framework CoreFoundation -framework IOKit

echo "Built $OUT ($(lipo -archs "$OUT"))"

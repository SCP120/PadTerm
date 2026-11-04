#!/bin/bash
# The app icon and the launch images from the app's own drawing code. No third-party art. Output: assets/art/build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
A="$ROOT/assets/art/build"; T="$ROOT/build/art"
mkdir -p "$A" "$T"
xcrun clang -fblocks -w -framework CoreGraphics -framework ImageIO -framework CoreFoundation "$ROOT/tools/make_art.c" -o "$T/make_art"
"$T/make_art" launch "$A"
for px in 72 144 152 167; do "$T/make_art" icon "$A/Icon-$px.png" "$px"; done  # iOS 6 iPad, its retina size, modern iPad, iPad Pro

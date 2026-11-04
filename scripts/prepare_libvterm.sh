#!/bin/bash
# Unpack libvterm 0.3.3 from its tarball and apply the PadTerm patch (SGR 2 dim; xterm 256-colour tables).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARBALL="$ROOT/third_party/src/dl-libvterm/libvterm-0.3.3.tar.gz"
# SHA-256 of the tarball as downloaded from https://www.leonerd.org.uk/code/libvterm/ on 2026-11-03.
SHA="09156f43dd2128bd347cbeebe50d9a571d32c64e0cf18d211197946aff7226e0"
OUT="$ROOT/third_party/src/libvterm-0.3.3-pt"
if [ ! -f "$TARBALL" ]; then
  mkdir -p "$(dirname "$TARBALL")"
  curl -fsSL -o "$TARBALL" https://www.leonerd.org.uk/code/libvterm/libvterm-0.3.3.tar.gz
fi
echo "$SHA  $TARBALL" | shasum -a 256 -c - >/dev/null
if [ -d "$OUT" ]; then
  echo "libvterm already prepared: $OUT (delete it to prepare again)"
  exit 0
fi
mkdir -p "$OUT"
tar xzf "$TARBALL" -C "$OUT" --strip-components 1
(cd "$OUT" && patch -s -p1 < "$ROOT/third_party/patches/libvterm-0.3.3-pt.patch")
echo "libvterm ready: $OUT"

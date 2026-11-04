#!/bin/bash
# Build a flat APT source for Cydia in build/cydia-repo from the newest .deb (no root needed).
# Cydia source URL: http://<this Mac's LAN address>:8000/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
R="$ROOT/build/cydia-repo"
mkdir -p "$R"
cp "$(ls -t "$ROOT"/ios/packages/*.deb | head -1)" "$R/"
cd "$R"
dpkg-scanpackages -m . /dev/null > Packages 2>/dev/null
gzip -9 -k -f Packages
bzip2 -9 -k -f Packages
cat > Release <<REL
Origin: PadTerm
Label: PadTerm
Suite: stable
Version: 0.1
Codename: padterm
Architectures: iphoneos-arm
Components: main
Description: PadTerm local source
REL
echo "repo ready: $R"

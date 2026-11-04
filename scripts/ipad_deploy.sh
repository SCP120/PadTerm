#!/bin/bash
# Install an app .deb on the USB-connected iPad through the normal install service (no root).
# usage: ipad_deploy.sh [deb] [--no-persistent-wifi]   Writes the app container path to build/ipad/container.txt.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
I="$ROOT/build/ipad/ipa"
DEB="${1:-$(ls -t "$ROOT"/ios/packages/*.deb | head -1)}"
mkdir -p "$I"
find "$I" -mindepth 1 -delete
dpkg-deb -x "$DEB" "$I/x"
mkdir -p "$I/Payload"
ditto "$I/x/Applications/PadTerm.app" "$I/Payload/PadTerm.app"
if [ "${2:-}" = "--no-persistent-wifi" ]; then
  /usr/libexec/PlistBuddy -c "Delete :UIRequiresPersistentWiFi" "$I/Payload/PadTerm.app/Info.plist"
fi
rm -f "$ROOT/build/ipad/PadTerm.ipa"
(cd "$I" && zip -qry ../PadTerm.ipa Payload)
LOG="$ROOT/build/ipad/install_syslog.txt"
idevicesyslog > "$LOG" 2>&1 &
SYS=$!
sleep 1
ideviceinstaller install "$ROOT/build/ipad/PadTerm.ipa" 2>/dev/null | tail -1
sleep 1
kill "$SYS"
grep -aoE '/private/var/mobile/Applications/[0-9A-F-]{36}' "$LOG" | tail -1 > "$ROOT/build/ipad/container.txt"
echo "container: $(cat "$ROOT/build/ipad/container.txt")"

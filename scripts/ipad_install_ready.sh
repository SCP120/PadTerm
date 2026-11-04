#!/bin/bash
# Install the release on the USB-connected iPad with the Wi-Fi server profile (PT_WIFI_HOST) already in it. A SELFTEST build writes the
# profile; the release is installed on top, and iOS keeps the app's data. No test code stays. usage: ipad_install_ready.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export THEOS="${THEOS:-$HOME/theos}" PATH="/opt/homebrew/opt/make/libexec/gnubin:$PATH"
MINI="${PT_WIFI_HOST:?set PT_WIFI_HOST to the server address}"; WIFI_USER="${PT_WIFI_USER:?set PT_WIFI_USER to the login on that server}"
PKG="$ROOT/build/ipad/selftest-pkg"
make -s -C ios clean package FINALPACKAGE=1 SELFTEST=1 THEOS_PACKAGE_DIR="$PKG" >/dev/null 2>&1
scripts/ipad_deploy.sh "$(ls -t "$PKG"/*.deb | head -1)" | tail -1
CON="$(cat build/ipad/container.txt)"
iproxy 5024:5024 >/dev/null 2>&1 &
P=$!
trap 'kill $P 2>/dev/null' EXIT
sleep 1
build/ipad/ptlaunch "$CON/PadTerm.app/PadTerm" "$CON" >/dev/null
sleep 5
FP="$(ssh -i build/ipad/id_ed25519_mini -o IdentitiesOnly=yes -o BatchMode=yes -o UserKnownHostsFile="$ROOT/build/ipad/known_hosts_mini" -o LogLevel=ERROR $WIFI_USER@$MINI 'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub' | awk '{print $2}')"
HEX="$(xxd -p build/ipad/id_ed25519_mini | tr -d '\n')"
printf 'resetprofiles\n' | nc -w 3 127.0.0.1 5024 | head -1 # test profiles and test settings must not stay
printf 'profile %s ~/padterm-test %s %s %s 22\n' "$WIFI_USER" "$FP" "$HEX" "$MINI" | nc -w 3 127.0.0.1 5024 | head -1
printf 'screen launch\n' | nc -w 2 127.0.0.1 5024 >/dev/null
sleep 1
idevicescreenshot tests/artifacts/device/launch_screen.tiff >/dev/null 2>&1
sips -s format png tests/artifacts/device/launch_screen.tiff --out tests/artifacts/device/launch_screen.png >/dev/null
rm -f tests/artifacts/device/launch_screen.tiff
make -s -C ios clean package FINALPACKAGE=1 >/dev/null 2>&1
scripts/ipad_deploy.sh "ios/packages/dev.padterm.app_0.1.0_iphoneos-arm.deb" | tail -1

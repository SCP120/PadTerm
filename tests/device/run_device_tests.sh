#!/bin/bash
# Full device test on the USB-connected iPad: SELFTEST build -> install -> start -> test -> install the release build.
# No root on this Mac and none needed on the iPad. Needs: libimobiledevice, tmux, claude, codex, scripts/test_sshd.sh.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
export THEOS="${THEOS:-$HOME/theos}" PATH="/opt/homebrew/opt/make/libexec/gnubin:$PATH"
PKG="$ROOT/build/ipad/selftest-pkg"
mkdir -p "$PKG"
[ -x build/ipad/ptlaunch ] || xcrun clang -w -I/opt/homebrew/include -L/opt/homebrew/lib tools/ptlaunch.c -limobiledevice-1.0 -lplist-2.0 -o build/ipad/ptlaunch
[ -x build/ipad/ptmount ] || xcrun clang -w -I/opt/homebrew/include -L/opt/homebrew/lib tools/ptmount.c -limobiledevice-1.0 -lplist-2.0 -o build/ipad/ptmount
# On iOS 6 "ImagePresent" is not reliable: test the service that the image provides.
image_ok() { idevicescreenshot build/ipad/probe.tiff >/dev/null 2>&1; }
if ! image_ok; then
  ideviceimagemounter mount build/ipad/ddi/dmg build/ipad/ddi/sig >/dev/null 2>&1   # uploads the staged image
  build/ipad/ptmount build/ipad/ddi/sig >/dev/null
fi
image_ok || { echo "developer image not mounted" >&2; exit 2; }
make -s -C ios clean package FINALPACKAGE=1 SELFTEST=1 THEOS_PACKAGE_DIR="$PKG" >/dev/null 2>&1 || { echo "selftest build failed" >&2; exit 2; }
scripts/ipad_deploy.sh "$(ls -t "$PKG"/*.deb | head -1)" --no-persistent-wifi || exit 2
CON="$(cat build/ipad/container.txt)"
scripts/test_sshd.sh >/dev/null || exit 2
iproxy 5022:5022 5024:5024 >/dev/null 2>&1 &
PROXY=$!
idevicesyslog > build/ipad/device_syslog.txt 2>&1 &
SYS=$!
sleep 1
build/ipad/ptlaunch "$CON/PadTerm.app/PadTerm" "$CON" >/dev/null
sleep 5
python3 -I tests/device/device_test.py
status=$?
kill "$SYS" "$PROXY" 2>/dev/null
echo "--- crashes in the log:"; grep -aE "PadTerm.*(crashed|exited abnormally)|padterm.*(crashed|exited abnormally)" build/ipad/device_syslog.txt | tail -5
exit $status

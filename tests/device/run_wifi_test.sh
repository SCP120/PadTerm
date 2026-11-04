#!/bin/bash
# Install a SELFTEST build, start it, run a Wi-Fi test. usage: run_wifi_test.sh <label> [claude|soak]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
LABEL="$1"
KIND="${2:-claude}"
export THEOS="${THEOS:-$HOME/theos}" PATH="/opt/homebrew/opt/make/libexec/gnubin:$PATH"
PKG="$ROOT/build/ipad/selftest-pkg"
make -s -C ios clean package FINALPACKAGE=1 SELFTEST=1 THEOS_PACKAGE_DIR="$PKG" >/dev/null 2>&1 || { echo "selftest build failed" >&2; exit 2; }
scripts/ipad_deploy.sh "$(ls -t "$PKG"/*.deb | head -1)" || exit 2
CON="$(cat build/ipad/container.txt)"
mkdir -p "tests/artifacts/wifi/$LABEL"
iproxy 5024:5024 >/dev/null 2>&1 &
PROXY=$!
idevicesyslog > "tests/artifacts/wifi/$LABEL/syslog.txt" 2>&1 &
SYS=$!
sleep 1
build/ipad/ptlaunch "$CON/PadTerm.app/PadTerm" "$CON" >/dev/null
sleep 5
python3 -I "tests/device/wifi_${KIND}_test.py" "$LABEL"
status=$?
kill "$SYS" "$PROXY" 2>/dev/null
echo "--- crashes in the log:"; grep -aE "PadTerm.*(crashed)|padterm.*(crashed|exited abnormally)" "tests/artifacts/wifi/$LABEL/syslog.txt" | tail -5 | cut -c1-170
exit $status

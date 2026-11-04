#!/bin/bash
# Run the full UI test against the Catalyst build (modern UIKit) on this Mac. HOME is redirected: the app must not touch the real ~/Documents.
# usage: tests/modern/run_bench.sh [light|dark ...]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
scripts/build_catalyst.sh selftest 2>&1 | tail -1
scripts/test_sshd.sh start
H="$ROOT/build/catalyst/home"; rm -rf "$H"; mkdir -p "$H/Documents"
pkill -f catalyst/PadTerm.app || true; sleep 1
open -n --env CFFIXED_USER_HOME="$H" --stdout "$ROOT/build/catalyst/run.log" --stderr "$ROOT/build/catalyst/run.log" build/catalyst/PadTerm.app
sleep 4
APP="$(pgrep -f catalyst/PadTerm.app | head -1)"
[ -n "$APP" ] || { echo "app stopped at launch"; tail -20 build/catalyst/run.log; exit 1; }
PT_UI_OUT=tests/artifacts/modern python3 tests/device/ui_full_test.py "$@"; rc=$?
kill -0 $APP && echo "app alive at end" || echo "APP STOPPED"
kill $APP 2>/dev/null
scripts/test_sshd.sh stop
exit $rc

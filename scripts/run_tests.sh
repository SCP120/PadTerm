#!/bin/bash
# Build and run every PadTerm test suite on this Mac; write tests/artifacts/test_results.json.
#   unit  - core + renderer (build/host/unit_tests)
#   profile - profile model + store (Objective-C, Foundation only)
#   e2e   - real sshd on 127.0.0.1:2222 + tmux + claude + codex (build/host/e2e_tests)
#   ios   - static checks of the armv7 / iOS 6 .deb (scripts/check_ios_binary.py)
# The iOS app itself runs only on the iPad; nothing here proves it runs there.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export THEOS="${THEOS:-$HOME/theos}" PATH="/opt/homebrew/opt/make/libexec/gnubin:$PATH"
OUT=build/host/results.jsonl
mkdir -p build/host tests/artifacts
: > "$OUT"
scripts/prepare_libvterm.sh >/dev/null
scripts/make_ios_sdk.sh >/dev/null
make -s -j8 all || { echo "host build failed" >&2; exit 2; }
make -s -C ios clean package FINALPACKAGE=1 >/dev/null 2>&1 || { echo "iOS build failed" >&2; exit 2; }
scripts/test_sshd.sh >/dev/null || { echo "test sshd did not start" >&2; exit 2; }
status=0
build/host/unit_tests unit "$OUT" || status=1
build/host/profile_tests profile "$OUT" || status=1
build/host/e2e_tests e2e "$OUT" || status=1
DEB="$(ls -t ios/packages/*.deb | head -1)"
python3 -I scripts/check_ios_binary.py "$DEB" "$HOME/theos/sdks/iPhoneOS9.3-armv7.sdk" "$OUT" || status=1
python3 -I scripts/coverage.py "$OUT" docs/business/requirements/padterm.md tests/artifacts/test_results.json || status=1
exit $status

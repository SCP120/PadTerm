#!/bin/bash
# Start (or stop) a private sshd for the E2E tests: 127.0.0.1:2222, this user only, keys in build/e2e-sshd.
# No sudo, no change to macOS Remote Login. tmux sockets go to build/e2e-sshd/tmux (SetEnv TMUX_TMPDIR),
# so the tests never touch the user's own tmux servers.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
D="$ROOT/build/e2e-sshd"
PORT=2222
if [ "${1:-start}" = "stop" ]; then
  [ -f "$D/sshd.pid" ] && kill "$(cat "$D/sshd.pid")" 2>/dev/null || true
  exit 0
fi
mkdir -p "$D/tmux"
chmod 700 "$D" "$D/tmux"
[ -f "$D/host_ed25519" ] || ssh-keygen -q -t ed25519 -N "" -C padterm-test-host -f "$D/host_ed25519"
[ -f "$D/client_ed25519" ] || ssh-keygen -q -t ed25519 -N "" -C padterm-test-client -f "$D/client_ed25519"
[ -f "$D/other_ed25519" ] || ssh-keygen -q -t ed25519 -N "" -C padterm-test-other -f "$D/other_ed25519"
cp "$D/client_ed25519.pub" "$D/authorized_keys"
chmod 600 "$D/authorized_keys"
ssh-keygen -lf "$D/host_ed25519.pub" | awk '{print $2}' > "$D/expected_fingerprint"
cat > "$D/sshd_config" <<CFG
Port $PORT
ListenAddress 127.0.0.1
HostKey $D/host_ed25519
AuthorizedKeysFile $D/authorized_keys
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
StrictModes no
PidFile $D/sshd.pid
SetEnv TMUX_TMPDIR=$D/tmux
LogLevel VERBOSE
CFG
if [ -f "$D/sshd.pid" ] && kill -0 "$(cat "$D/sshd.pid")" 2>/dev/null; then
  echo "test sshd already running (pid $(cat "$D/sshd.pid"))"; exit 0
fi
/usr/sbin/sshd -f "$D/sshd_config" -E "$D/sshd.log"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  nc -z 127.0.0.1 $PORT 2>/dev/null && { echo "test sshd on 127.0.0.1:$PORT"; exit 0; }
  sleep 0.3
done
echo "test sshd did not start; see $D/sshd.log" >&2; tail -5 "$D/sshd.log" >&2; exit 1

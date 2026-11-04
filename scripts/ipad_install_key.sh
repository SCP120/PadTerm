#!/bin/bash
# Copy a private key to the app's Documents folder on the USB-connected iPad (no root; same as iTunes File Sharing).
# usage: ipad_install_key.sh <private key file> <profile name>
# Then in the app: edit the profile with that name, tap Import, tap Save. The app deletes the copy in Documents.
set -euo pipefail
KEY="$1"; NAME="$2"
case "$NAME" in *[!A-Za-z0-9._-]*|"") echo "profile name may use only letters, digits, . _ -" >&2; exit 2;; esac
ssh-keygen -y -P "" -f "$KEY" >/dev/null || { echo "$KEY: not a private key without a passphrase" >&2; exit 2; }
# --container, not --documents: on iOS 6 that mode opens the container root, not Documents.
printf 'put %s Documents/%s.key\nls Documents\nquit\n' "$KEY" "$NAME" | afcclient --container dev.padterm.app | sed 's/\x1b\[[0-9;]*m//g' | grep -q "$NAME.key"
echo "copied: $NAME.key is in the PadTerm Documents folder. In the app: Import, then Save."

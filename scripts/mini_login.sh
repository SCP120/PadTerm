#!/bin/bash
# Log Claude Code in on a macOS server FROM AN SSH SESSION. macOS keeps the login keychain from SSH, so a login made in
# the Mac's own Terminal does not reach SSH sessions; a login made here is stored where SSH sessions can read it.
# usage: mini_login.sh user@host [key file]
TARGET="${1:?usage: mini_login.sh user@host [key file]}"
KEY=(); [ -n "${2:-}" ] && KEY=(-i "$2" -o IdentitiesOnly=yes)
echo "Open the link it prints in your browser, sign in, and paste the code back here."
ssh -t ${KEY[@]+"${KEY[@]}"} -o LogLevel=ERROR "$TARGET" \
  'export PATH="$PATH:$HOME/.local/bin:/opt/homebrew/bin"; claude auth login; echo; claude auth status | grep -E "loggedIn|authMethod"'
echo; echo "You can close this window."

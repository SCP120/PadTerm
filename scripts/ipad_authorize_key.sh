#!/bin/bash
# Add this Mac's dev key to root on the USB-connected iPad. It asks for the iPad root password once.
# Needs: iproxy 2200:22 running (USB tunnel).
set -euo pipefail
D="$HOME/padterm/build/ipad"
ssh -F "$D/ssh.conf" -o PreferredAuthentications=password,keyboard-interactive -o PubkeyAuthentication=no ipad \
  'mkdir -p /var/root/.ssh && chmod 700 /var/root/.ssh && cat >> /var/root/.ssh/authorized_keys && chmod 600 /var/root/.ssh/authorized_keys && echo "key added"' \
  < "$D/id_ed25519.pub"

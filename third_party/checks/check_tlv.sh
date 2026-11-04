#!/usr/bin/env bash
# Scan every object in the static libs of a prefix for TLS (thread-local) markers.
set -euo pipefail
P="$(cd "${1:?prefix dir}" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
for l in ssl crypto ssh2; do
  mkdir "$tmp/$l"; ( cd "$tmp/$l" && ar x "$P/lib/lib$l.a" )
  n=0; hits=0
  for f in "$tmp/$l"/*.o; do
    n=$((n+1))
    c=$( { otool -l "$f" 2>/dev/null | grep -E '__thread_vars|__thread_data|__thread_bss' || true; nm -u "$f" 2>/dev/null | grep '__tlv_bootstrap' || true; } | wc -l )
    hits=$((hits + c))
  done
  echo "lib$l.a: $n objects, TLV markers: $hits"
done

# Sourced by the dependency builds. OpenSSL: the SHA-256 that the project publishes on its release page.
OPENSSL_VER=3.5.9
OPENSSL_SHA256=603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
# libssh2: a commit on the main branch, not a release. Release 1.11.1 has CVE-2026-55200 (critical), CVE-2026-55199, CVE-2025-15661
# and CVE-2026-66032 to 66035; on 2026-11-04 no release has the fixes. Move to the next release when it exists.
LIBSSH2_COMMIT=fef2c46871fd7901b7d763ca833c16a58cb536bb
fetch_libssh2() { # third_party/src folder -> tree in <folder>/libssh2-git; git checks the content against the commit hash
  local d="$1/libssh2-git"
  if [ "$(git -C "$d" rev-parse HEAD 2>/dev/null)" != "$LIBSSH2_COMMIT" ]; then
    rm -rf "$d"; mkdir -p "$d"
    git -C "$d" init -q
    git -C "$d" fetch -q --depth 1 https://github.com/libssh2/libssh2.git "$LIBSSH2_COMMIT"
    git -C "$d" checkout -q FETCH_HEAD
  fi
  [ "$(git -C "$d" rev-parse HEAD)" = "$LIBSSH2_COMMIT" ] || { echo "libssh2 is not at the pinned commit" >&2; exit 1; }
  git -C "$d" diff --quiet HEAD || { echo "libssh2 tree was changed" >&2; exit 1; }
}
verify_deps() { # third_party/src folder
  printf '%s  %s\n' "$OPENSSL_SHA256" "$1/openssl-$OPENSSL_VER/openssl-$OPENSSL_VER.tar.gz" | shasum -a 256 -c - >/dev/null
  fetch_libssh2 "$1"
}

#!/usr/bin/env bash
# Download, verify, build and install OpenSSL + libssh2 as static libs for
#   ios-armv7   (iOS 6.0 deployment target, armv7, theos 9.3 armv7 SDK)
#   macos-arm64 (host build for host-side tests)
# Re-runnable: archives are re-verified, sources re-extracted, build dirs and
# prefixes rebuilt from scratch on every run.
set -euo pipefail

TP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../third_party" && pwd)"
SRC="$TP/src"
BUILD="$TP/build"
PREFIX="$TP/prefix"
IOS_SDK="${IOS_SDK:-$HOME/theos/sdks/iPhoneOS9.3-armv7.sdk}"
JOBS="$(sysctl -n hw.ncpu)"

. "$(dirname "${BASH_SOURCE[0]}")/dep_pins.sh"
# SHA-256 published by the project: openssl-3.5.9.tar.gz.sha256 on the GitHub release page.
OPENSSL_URL="https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VER/openssl-$OPENSSL_VER.tar.gz"

OPENSSL_OPTS=(no-shared no-tests no-apps no-docs no-engine no-dso no-async no-ui-console)

# PT_HOST_ONLY=1: only the macOS libraries for the host tests (CI has no iOS SDK).
[ -n "${PT_HOST_ONLY:-}" ] || [ -d "$IOS_SDK" ] || { echo "iOS SDK not found: $IOS_SDK" >&2; exit 1; }

fetch() { # name version url sha256 -> extracted tree in $SRC/<name>-<version>/<name>-<version>
  local name=$1 ver=$2 url=$3 sha=$4
  local dir="$SRC/$name-$ver" tgz="$SRC/$name-$ver/$name-$ver.tar.gz"
  mkdir -p "$dir"
  if [ ! -f "$tgz" ] || [ "$(shasum -a 256 "$tgz" | cut -d' ' -f1)" != "$sha" ]; then
    curl -fL --retry 3 -o "$tgz" "$url"
  fi
  local got; got="$(shasum -a 256 "$tgz" | cut -d' ' -f1)"
  [ "$got" = "$sha" ] || { echo "SHA-256 mismatch for $tgz: $got != $sha" >&2; exit 1; }
  echo "verified $name-$ver sha256=$sha"
  rm -rf "$dir/$name-$ver"
  tar -xzf "$tgz" -C "$dir"
}

build_openssl() { # target ossl_config_target prefix cc cflags [extra configure opts]
  local target=$1 conf=$2 prefix=$3 cc=$4 cflags=$5; shift 5
  local bdir="$BUILD/openssl-$target"
  rm -rf "$bdir" "$prefix"; mkdir -p "$bdir" "$prefix"
  ( cd "$bdir"
    CC="$cc" CFLAGS="$cflags" perl "$SRC/openssl-$OPENSSL_VER/openssl-$OPENSSL_VER/Configure" \
      "$conf" "${OPENSSL_OPTS[@]}" ${1+"$@"} --prefix=/padterm --openssldir=/padterm/ssl --libdir=lib
    # A shipped binary must not name this machine's folders: OpenSSL records its paths and its compiler flags.
    make crypto/buildinf.h
    printf '%s\n' '#define PLATFORM "platform: padterm"' '#define DATE "built on: release"' \
      'static const char compiler_flags[] = "compiler: clang";' > crypto/buildinf.h
    make -j"$JOBS" build_libs
    make DESTDIR="$bdir/stage" install_dev
    ditto "$bdir/stage/padterm" "$prefix" )
}

build_libssh2() { # target prefix cflags arch
  local target=$1 prefix=$2 cflags=$3 arch=$4
  local bdir="$BUILD/libssh2-$target"
  rm -rf "$bdir"; mkdir -p "$bdir"
  local args=(
    -DCMAKE_SYSTEM_NAME=Darwin
    -DCMAKE_C_COMPILER="$(xcrun --find clang)"
    -DCMAKE_AR="$(xcrun --find ar)" -DCMAKE_RANLIB="$(xcrun --find ranlib)"
    -DCMAKE_C_FLAGS="$cflags -ffile-prefix-map=$SRC=."
    -DCMAKE_OSX_ARCHITECTURES="$arch"
    -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_INSTALL_LIBDIR=lib
    -DCMAKE_BUILD_TYPE=Release
    -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF
    -DCRYPTO_BACKEND=OpenSSL -DENABLE_ZLIB_COMPRESSION=OFF
    -DOPENSSL_ROOT_DIR="$prefix" -DOPENSSL_USE_STATIC_LIBS=ON
    -DOPENSSL_INCLUDE_DIR="$prefix/include"
    -DOPENSSL_CRYPTO_LIBRARY="$prefix/lib/libcrypto.a"
    -DOPENSSL_SSL_LIBRARY="$prefix/lib/libssl.a"
    -DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew\;/usr/local
    -DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF
    -DCMAKE_DISABLE_FIND_PACKAGE_ZLIB=ON # else its zlib lookup adds the macOS headers to an iOS build
    "${@:5}"
  )
  cmake -S "$SRC/libssh2-git" -B "$bdir" "${args[@]}"
  cmake --build "$bdir" -j "$JOBS"
  cmake --install "$bdir"
}

fetch openssl "$OPENSSL_VER" "$OPENSSL_URL" "$OPENSSL_SHA256"
fetch_libssh2 "$SRC"

CLANG="$(xcrun --find clang)"

# ---- ios-armv7 -------------------------------------------------------------
IOS_PREFIX="$PREFIX/ios-armv7"
# -mno-thumb: this linker (ld-27037) writes code pointers without the Thumb bit, so all code must be ARM.
IOS_FLAGS="-arch armv7 -mno-thumb -isysroot $IOS_SDK -miphoneos-version-min=6.0"
# ios-xcrun target supplies -arch armv7; we override CC/CFLAGS to use the CLT + theos SDK.
# no-asm: the ios32 perlasm output (".word OPENSSL_armcap_P-.") is rejected by the
# integrated assembler of current Apple clang ("symbol can not be undefined in a
# subtraction expression"), so the portable C code is used on armv7.
# -DBROKEN_CLANG_ATOMICS: with the default path clang emits a call to ___atomic_is_lock_free
# on armv7, which no iOS 6 dylib exports (found with nm -u); the macro selects OpenSSL's
# mutex-based fallback instead.
if [ -z "${PT_HOST_ONLY:-}" ]; then
build_openssl ios-armv7 ios-xcrun "$IOS_PREFIX" "$CLANG" "-mno-thumb -isysroot $IOS_SDK -miphoneos-version-min=6.0 -DBROKEN_CLANG_ATOMICS" no-asm
build_libssh2 ios-armv7 "$IOS_PREFIX" "$IOS_FLAGS" armv7 \
  -DCMAKE_OSX_SYSROOT="" -DCMAKE_OSX_DEPLOYMENT_TARGET="" \
  -DHAVE_EXPLICIT_BZERO=0 -DHAVE_EXPLICIT_MEMSET=0 -DHAVE_MEMSET_S=0
fi

# ---- macos-arm64 -----------------------------------------------------------
MAC_PREFIX="$PREFIX/macos-arm64"
MAC_SDK="$(xcrun --sdk macosx --show-sdk-path)"
build_openssl macos-arm64 darwin64-arm64-cc "$MAC_PREFIX" "$CLANG" "-isysroot $MAC_SDK"
build_libssh2 macos-arm64 "$MAC_PREFIX" "-arch arm64 -isysroot $MAC_SDK" arm64

echo "done: $IOS_PREFIX $MAC_PREFIX"

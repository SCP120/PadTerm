#!/bin/bash
# OpenSSL + libssh2 for iOS arm64 (modern iPads), with the theos iPhoneOS16.5 SDK and no Xcode. Same source tarballs as
# scripts/build_deps.sh. Output: third_party/prefix/ios-arm64. arm64 needs no -mno-thumb: it has no Thumb state.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$HOME/theos/sdks/iPhoneOS16.5.sdk"
MINOS=10.0  # libssh2 calls clock_gettime (iOS 10). Every arm64 iPad can update to iOS 10 or later
PREFIX="$ROOT/third_party/prefix/ios-arm64"
W="$ROOT/build/deps-arm64"
TP="$ROOT/third_party/src"
FLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=$MINOS"
JOBS="$(sysctl -n hw.ncpu)"
. "$ROOT/scripts/dep_pins.sh"; verify_deps "$TP"
[ -d "$SDK" ] || { echo "missing $SDK (git clone https://github.com/theos/sdks and copy it)" >&2; exit 1; }
if [ -f "$PREFIX/lib/libssh2.a" ]; then echo "already built: $PREFIX"; exit 0; fi
mkdir -p "$W/ossl-src" "$W/ossl" "$W/ssh2-src" "$W/ssh2" "$PREFIX"
tar -xzf "$TP/openssl-3.5.9/openssl-3.5.9.tar.gz" -C "$W/ossl-src"
( cd "$W/ossl"
  CC=/usr/bin/clang CFLAGS="$FLAGS" perl "$W/ossl-src/openssl-3.5.9/Configure" ios64-xcrun \
    no-shared no-tests no-apps no-docs no-engine no-dso no-async no-ui-console \
    --prefix=/padterm --openssldir=/padterm/ssl --libdir=lib >/dev/null
  # A shipped binary must not name this machine's folders: OpenSSL records its paths and its compiler flags.
  make crypto/buildinf.h >/dev/null
  printf '%s\n' '#define PLATFORM "platform: padterm"' '#define DATE "built on: release"' \
    'static const char compiler_flags[] = "compiler: clang";' > crypto/buildinf.h
  make -j"$JOBS" build_libs >/dev/null
  make DESTDIR="$W/ossl/stage" install_dev >/dev/null
  ditto "$W/ossl/stage/padterm" "$PREFIX" )
cmake -S "$TP/libssh2-git" -B "$W/ssh2" \
  -DCMAKE_SYSTEM_NAME=Darwin -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_C_FLAGS="$FLAGS -ffile-prefix-map=$TP=. -ffile-prefix-map=$W=." \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_SYSROOT="" -DCMAKE_OSX_DEPLOYMENT_TARGET="" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF \
  -DCRYPTO_BACKEND=OpenSSL -DENABLE_ZLIB_COMPRESSION=OFF \
  -DOPENSSL_ROOT_DIR="$PREFIX" -DOPENSSL_USE_STATIC_LIBS=ON -DOPENSSL_INCLUDE_DIR="$PREFIX/include" \
  -DOPENSSL_CRYPTO_LIBRARY="$PREFIX/lib/libcrypto.a" -DOPENSSL_SSL_LIBRARY="$PREFIX/lib/libssl.a" \
  -DCMAKE_IGNORE_PREFIX_PATH='/opt/homebrew;/usr/local' -DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF -DCMAKE_DISABLE_FIND_PACKAGE_ZLIB=ON \
  -DHAVE_EXPLICIT_BZERO=0 -DHAVE_EXPLICIT_MEMSET=0 -DHAVE_MEMSET_S=0 >/dev/null
cmake --build "$W/ssh2" -j "$JOBS" >/dev/null
cmake --install "$W/ssh2" >/dev/null
echo "built: $PREFIX"

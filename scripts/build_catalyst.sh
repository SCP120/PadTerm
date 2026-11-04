#!/bin/bash
# Test bench for modern UIKit: the same sources as a Mac Catalyst app, run on this Apple Silicon Mac. No Xcode, no device.
# It proves what modern UIKit does with the app's controls. It does not replace a run on an iPad: no touch, no on-screen keyboard.
# usage: scripts/build_catalyst.sh [selftest]   -> build/catalyst/PadTerm.app
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
MODE="${1:-release}"
SDK="$(xcrun --show-sdk-path)"
UIKIT="$SDK/System/iOSSupport"
TARGET=arm64-apple-ios15.0-macabi
FL="-target $TARGET -isysroot $SDK -iframework $UIKIT/System/Library/Frameworks -isystem $UIKIT/usr/include"
O=build/catalyst; P="$ROOT/third_party/prefix/catalyst-arm64"; VT=third_party/src/libvterm-0.3.3-pt; TP=third_party/src
if [ ! -f "$P/lib/libssh2.a" ]; then
  . scripts/dep_pins.sh; verify_deps "$TP"
  W="$ROOT/build/deps-catalyst"; rm -rf "$W"; mkdir -p "$W/ossl-src" "$W/ossl" "$W/ssh2-src" "$W/ssh2" "$P"
  tar -xzf "$TP/openssl-3.5.9/openssl-3.5.9.tar.gz" -C "$W/ossl-src"
  ( cd "$W/ossl"
    CC=/usr/bin/clang CFLAGS="$FL" perl "$W/ossl-src/openssl-3.5.9/Configure" darwin64-arm64-cc \
      no-shared no-tests no-apps no-docs no-engine no-dso no-async no-ui-console --prefix="$P" --openssldir="$P/ssl" --libdir=lib >/dev/null
    make -j"$(sysctl -n hw.ncpu)" build_libs >/dev/null; make install_dev >/dev/null )
  cmake -S "$TP/libssh2-git" -B "$W/ssh2" -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_C_FLAGS="$FL" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_SYSROOT="" -DCMAKE_OSX_DEPLOYMENT_TARGET="" -DCMAKE_INSTALL_PREFIX="$P" -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF -DCRYPTO_BACKEND=OpenSSL -DENABLE_ZLIB_COMPRESSION=OFF \
    -DOPENSSL_ROOT_DIR="$P" -DOPENSSL_USE_STATIC_LIBS=ON -DOPENSSL_INCLUDE_DIR="$P/include" -DOPENSSL_CRYPTO_LIBRARY="$P/lib/libcrypto.a" -DOPENSSL_SSL_LIBRARY="$P/lib/libssl.a" \
    -DCMAKE_IGNORE_PREFIX_PATH='/opt/homebrew;/usr/local' -DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF -DCMAKE_DISABLE_FIND_PACKAGE_ZLIB=ON >/dev/null
  cmake --build "$W/ssh2" -j "$(sysctl -n hw.ncpu)" >/dev/null; cmake --install "$W/ssh2" >/dev/null
fi
rm -rf "$O/obj" "$O/PadTerm.app"; mkdir -p "$O/obj" "$O/PadTerm.app/Contents/MacOS" "$O/PadTerm.app/Contents/Resources"
for f in core/*.c render/pt_render.c; do xcrun clang -std=c99 -Os -w $FL -I"$VT/include" -I"$P/include" -Icore -Irender -c "$f" -o "$O/obj/c_$(basename "$f" .c).o"; done
for f in "$VT"/src/*.c; do xcrun clang -std=c99 -Os -w $FL -I"$VT/include" -c "$f" -o "$O/obj/v_$(basename "$f" .c).o"; done
SRC=(ios/src/*.m); DEF=()
if [ "$MODE" = selftest ]; then SRC+=(ios/selftest/PTSelfTest.m ios/selftest/pt_metrics.m); DEF=(-DPT_SELFTEST -Iios/selftest); fi
for f in "${SRC[@]}"; do xcrun clang -fobjc-arc -Os -Wno-deprecated-declarations -Wno-unused-parameter $FL ${DEF[@]+"${DEF[@]}"} -Icore -Irender -I"$VT/include" -Iios/src -c "$f" -o "$O/obj/m_$(basename "$f" .m).o"; done
xcrun clang $FL -L"$UIKIT/usr/lib" -F"$UIKIT/System/Library/Frameworks" "$O"/obj/*.o "$P/lib/libssh2.a" "$P/lib/libssl.a" "$P/lib/libcrypto.a" \
  -framework UIKit -framework Foundation -framework CoreGraphics -framework CoreText -framework QuartzCore -framework CoreFoundation \
  -o "$O/PadTerm.app/Contents/MacOS/PadTerm"
cp ios/Resources/Info.plist "$O/PadTerm.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 12.0' -c 'Set :MinimumOSVersion 15.0' "$O/PadTerm.app/Contents/Info.plist"
cp assets/fonts/DejaVuSansMono.ttf assets/fonts/DejaVuSansMono-Bold.ttf "$O/PadTerm.app/Contents/Resources/"
codesign -s - -f --deep "$O/PadTerm.app" 2>&1 | tail -1
echo "built $O/PadTerm.app ($MODE)"

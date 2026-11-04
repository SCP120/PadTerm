#!/bin/bash
# Build the release files in dist/. PadTerm supports iOS 6 to 12; both files are fat, armv7 + arm64.
#   PadTerm-<v>-iOS7-12-sideload.ipa     not jailbroken: a tool signs it with your Apple Account (iOS 6 has no such tool)
#   PadTerm-<v>-iOS6-12-jailbreak.deb    rootful jailbreak; its control file refuses iOS 13 and later
# Only the armv7 slice has run on a device (iPad mini 1, iOS 6.1.3). See docs/design/ios-version-support.md.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export THEOS="${THEOS:-$HOME/theos}" PATH="/opt/homebrew/opt/make/libexec/gnubin:$PATH"
SDK="$HOME/theos/sdks/iPhoneOS16.5.sdk"; MINOS=10.0 # scripts/build_deps_arm64.sh says why
VT="$ROOT/third_party/src/libvterm-0.3.3-pt"; P="$ROOT/third_party/prefix/ios-arm64"
O="$ROOT/build/arm64"; D="$ROOT/dist"; W="$ROOT/build/package"
V="$(awk '/^Version:/{print $2}' ios/control)"
scripts/build_deps_arm64.sh
make -s -C ios clean package FINALPACKAGE=1 >/dev/null 2>&1
A7="$(ls -t ios/packages/*iphoneos-arm.deb | head -1)"
find "$W" "$O" "$D" -mindepth 1 -delete 2>/dev/null || true
mkdir -p "$W/app" "$O" "$D"
dpkg-deb -x "$A7" "$W/app"
APP="$W/app/Applications/PadTerm.app"
FL="-arch arm64 -isysroot $SDK -miphoneos-version-min=$MINOS"
for f in core/*.c render/pt_render.c; do
  xcrun clang -std=c99 -Os -Wall -Wextra -Werror -Wno-unused-parameter $FL -I"$VT/include" -I"$P/include" -Icore -Irender -c "$f" -o "$O/c_$(basename "$f" .c).o"
done
for f in "$VT"/src/*.c; do xcrun clang -std=c99 -Os -w $FL -I"$VT/include" -c "$f" -o "$O/v_$(basename "$f" .c).o"; done
for f in ios/src/*.m; do
  xcrun clang -fobjc-arc -Os -Wall -Wno-unused-parameter -Wno-deprecated-declarations -Werror=unguarded-availability $FL -Icore -Irender -I"$VT/include" -Iios/src -c "$f" -o "$O/m_$(basename "$f" .m).o"
done
# -fobjc-arc only on compile: on the link line clang asks for libarclite, which this toolchain does not have.
xcrun clang $FL -dead_strip "$O"/*.o "$P/lib/libssh2.a" "$P/lib/libssl.a" "$P/lib/libcrypto.a" \
  -framework UIKit -framework Foundation -framework CoreGraphics -framework CoreText -framework QuartzCore -framework CoreFoundation \
  -o "$O/PadTerm.arm64"
strip -x "$O/PadTerm.arm64"
cp "$APP/PadTerm" "$O/PadTerm.armv7"
lipo -create "$O/PadTerm.armv7" "$O/PadTerm.arm64" -output "$APP/PadTerm"
ldid -S "$APP/PadTerm"
lipo -info "$APP/PadTerm"
mkdir -p "$W/app/DEBIAN"
sed -e "/^Architecture:/s/.*/Architecture: iphoneos-arm/" ios/control > "$W/app/DEBIAN/control"
dpkg-deb --root-owner-group -Zgzip -b "$W/app" "$D/PadTerm-${V}-iOS6-12-jailbreak.deb" >/dev/null
mkdir -p "$W/ipa/Payload"
ditto "$APP" "$W/ipa/Payload/PadTerm.app"
(cd "$W/ipa" && zip -qryX "$D/PadTerm-${V}-iOS7-12-sideload.ipa" Payload)
ls -l "$D" | awk 'NR>1{print $5, $9}'

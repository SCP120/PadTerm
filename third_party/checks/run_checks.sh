#!/usr/bin/env bash
# Verification for build_deps.sh output. Run after scripts/build_deps.sh.
set -euo pipefail
cd "$(dirname "$0")"
PFX=../prefix
SDK="${IOS_SDK:-$HOME/theos/sdks/iPhoneOS9.3-armv7.sdk}"
echo "### lipo / file"
for t in ios-armv7 macos-arm64; do for l in ssl crypto ssh2; do lipo -info $PFX/$t/lib/lib$l.a; done; done
file $PFX/ios-armv7/lib/libssh2.a $PFX/macos-arm64/lib/libssh2.a
echo "### TLV scan"
for t in ios-armv7 macos-arm64; do echo "-- $t"; ./check_tlv.sh $PFX/$t; done
echo "### ios-armv7 link"
./make_linksdk.sh >/dev/null
P=$PFX/ios-armv7
xcrun clang -arch armv7 -isysroot "$PWD/linksdk/iPhoneOS9.3-armv7.sdk" -miphoneos-version-min=6.0 -I$P/include \
  ssh_check.c $P/lib/libssh2.a $P/lib/libssl.a $P/lib/libcrypto.a -o ssh_check_ios_armv7 2>&1 | grep -v liblaunch || true
file ssh_check_ios_armv7
otool -l ssh_check_ios_armv7 | grep -A3 -E "LC_VERSION_MIN_IPHONEOS|LC_BUILD_VERSION|LC_DYLD_CHAINED_FIXUPS" || true
echo "LC_BUILD_VERSION/LC_DYLD_CHAINED_FIXUPS count: $(otool -l ssh_check_ios_armv7 | grep -cE 'LC_BUILD_VERSION|LC_DYLD_CHAINED_FIXUPS' || true)"
echo "__thread_vars/data/bss count: $(otool -l ssh_check_ios_armv7 | grep -cE '__thread_(vars|data|bss)' || true)"
otool -L ssh_check_ios_armv7
echo "### nm -u availability"
python3 -I ios6_syms.py "$SDK" ssh_check_ios_armv7
echo "entropy-API imports (getentropy|CCRandom|SecRandom|arc4random|clock_gettime|memset_s|explicit_bzero): $(nm -u ssh_check_ios_armv7 | grep -ciE 'getentropy|CCRandom|SecRandom|arc4random|clock_gettime|memset_s|explicit_bzero' || true)"
echo "### macos-arm64 run"
M=$PFX/macos-arm64
xcrun clang -arch arm64 -isysroot "$(xcrun --show-sdk-path)" -I$M/include ssh_check.c $M/lib/libssh2.a $M/lib/libssl.a $M/lib/libcrypto.a -o ssh_check_macos_arm64
./ssh_check_macos_arm64

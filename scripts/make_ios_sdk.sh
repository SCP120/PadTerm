#!/bin/bash
# Make ~/theos/sdks/iPhoneOS9.3-armv7.sdk: a copy of the theos iPhoneOS9.3.sdk that the current Apple linker
# (ld-27037) accepts for armv7 / iOS 6. The original SDK is never changed. Both fixes are link-time only.
#  1. .tbd "archs" without i386/x86_64: else ld reads the stubs as iOS-simulator and refuses them.
#  2. libsystem_platform.tbd lists _memchr _memcmp _memcpy _memmove _memset _strchr _strcmp _strncmp:
#     the theos stubs omit them for armv7. At run time the app binds them to libSystem.B.dylib, which
#     exports them on iOS 6 through its sub-libraries.
set -euo pipefail
SRC="$HOME/theos/sdks/iPhoneOS9.3.sdk"
DST="$HOME/theos/sdks/iPhoneOS9.3-armv7.sdk"
[ -d "$SRC" ] || { echo "missing $SRC (git clone https://github.com/theos/sdks and copy iPhoneOS9.3.sdk)" >&2; exit 1; }
[ -d "$DST" ] || cp -cR "$SRC" "$DST"
find "$DST" -type f -name '*.tbd' -exec sed -i '' -E 's/(archs: *\[ *armv7, *armv7s, *arm64), *i386, *x86_64 *\]/\1 ]/' {} +
T="$DST/usr/lib/system/libsystem_platform.tbd"
if ! grep -q '_memcpy' "$T"; then
  # The file can be an APFS clone shared with the original; write a new file, do not edit in place.
  sed -E '0,/symbols: +\[ /s//symbols:            [ _memchr, _memcmp, _memcpy, _memmove, _memset, _strchr, _strcmp, _strncmp,\n                          /' "$T" > "$T.new" 2>/dev/null || true
  if ! grep -q '_memcpy' "$T.new"; then
    perl -0pe 's/symbols: +\[ /symbols:            [ _memchr, _memcmp, _memcpy, _memmove, _memset, _strchr, _strcmp, _strncmp,\n                          /' "$T" > "$T.new"
  fi
  mv "$T.new" "$T"
fi
grep -q '_memcpy' "$T" && ! grep -rqE 'archs:.*i386' --include='*.tbd' "$DST" && echo "iOS SDK ready: $DST"

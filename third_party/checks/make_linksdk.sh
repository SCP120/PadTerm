#!/usr/bin/env bash
# The theos iPhoneOS9.3-armv7.sdk .tbd stubs do not export _memchr/_memcmp/_memcpy/_memmove/_memset/
# _strchr/_strcmp/_strncmp (real libSystem on iOS 6+ does), so any link using them fails.
# Make an APFS-clone of the SDK and add the names to libsystem_platform.tbd. Link-time only.
set -euo pipefail
SRC="${IOS_SDK:-$HOME/theos/sdks/iPhoneOS9.3-armv7.sdk}"
DST="$(cd "$(dirname "$0")" && pwd)/linksdk/iPhoneOS9.3-armv7.sdk"
rm -rf "$(dirname "$DST")"; mkdir -p "$(dirname "$DST")"
cp -cR "$SRC" "$DST"
T="$DST/usr/lib/system/libsystem_platform.tbd"
rm "$T"; cp "$SRC/usr/lib/system/libsystem_platform.tbd" "$T"
python3 - "$T" <<'P'
import sys
p=sys.argv[1]; t=open(p).read()
t=t.replace("symbols:            [ ","symbols:            [ _memchr, _memcmp, _memcpy, _memmove, _memset, _strchr, _strcmp, _strncmp,\n                          ",1)
open(p,"w").write(t)
P
echo "$DST"

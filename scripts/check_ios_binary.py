#!/usr/bin/env python3
"""Static checks of the built iOS app against iOS 6 / armv7 (NFR-1, NFR-3).

usage: check_ios_binary.py <deb> <sdk> <out.jsonl>
Each check is one JSON line (suite "ios"), the same shape as tests/host/pt_test_main.c writes.
A device run is still needed: these checks prove the binary has no feature that iOS 6 cannot load.
"""
import json
import pathlib
import re
import subprocess
import sys
import tempfile

DEB, SDK, OUT = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])

# Libraries and frameworks that exist on iOS 6.0 (Apple iOS 6.0 SDK); the app may link only these.
IOS6_DYLIBS = {
    "/usr/lib/libobjc.A.dylib", "/usr/lib/libSystem.B.dylib",
    "/System/Library/Frameworks/Foundation.framework/Foundation",
    "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation",
    "/System/Library/Frameworks/UIKit.framework/UIKit",
    "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
    "/System/Library/Frameworks/CoreText.framework/CoreText",
    "/System/Library/Frameworks/QuartzCore.framework/QuartzCore",
}
results = []


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout


def check(name, ids, ok, message=""):
    results.append({"suite": "ios", "name": name, "ids": ids, "status": "passed" if ok else "failed",
                    "duration_ms": 0, "message": "" if ok else message})
    print(("ok   " if ok else "FAIL ") + name + ("" if ok else "\n     " + message))


with tempfile.TemporaryDirectory() as tmp:
    run("dpkg-deb", "-x", str(DEB), tmp)
    app = pathlib.Path(tmp) / "Applications" / "PadTerm.app"
    exe = app / "PadTerm"
    check("deb_has_app_files", "NFR-1",
          all((app / f).exists() for f in ["PadTerm", "Info.plist", "DejaVuSansMono.ttf", "DejaVuSansMono-Bold.ttf", "Icon-72.png", "Icon-152.png", "Licenses/OpenSSL-LICENSE.txt", "Licenses/libssh2-COPYING.txt", "Licenses/libvterm-LICENSE.txt", "Licenses/PadTerm-LICENSE.txt",
                                                    "Default-Portrait~ipad.png", "Default-Landscape~ipad.png"]),
          "missing files in " + ", ".join(p.name for p in app.iterdir()))
    check("no_third_party_art", "NFR-7", not list(app.glob("mascot_*")), "mascot art in a public package")
    info = run("plutil", "-convert", "json", "-o", "-", str(app / "Info.plist"))
    plist = json.loads(info)
    check("plist_min_os_6", "NFR-1", plist.get("MinimumOSVersion") == "6.0" and plist.get("UIDeviceFamily") == [2],
          f"MinimumOSVersion={plist.get('MinimumOSVersion')} UIDeviceFamily={plist.get('UIDeviceFamily')}")

    archs = run("lipo", "-archs", str(exe)).split()
    check("arch_armv7_only", "NFR-1", archs == ["armv7"], f"archs={archs}")

    lc = run("otool", "-l", str(exe))
    cmds = re.findall(r"^\s+cmd (\S+)", lc, re.M)
    vmin = re.search(r"cmd LC_VERSION_MIN_IPHONEOS\n\s+cmdsize \d+\n\s+version (\S+)", lc)
    check("min_os_load_command_6_0", "NFR-3", bool(vmin) and vmin.group(1) == "6.0" and "LC_BUILD_VERSION" not in cmds,
          f"version_min={vmin.group(1) if vmin else None} build_version={'LC_BUILD_VERSION' in cmds}")
    check("no_chained_fixups", "NFR-3",
          "LC_DYLD_CHAINED_FIXUPS" not in cmds and "LC_DYLD_EXPORTS_TRIE" not in cmds and "LC_DYLD_INFO_ONLY" in cmds,
          f"load commands: {sorted(set(cmds))}")
    # ld-27037 writes code pointers without the Thumb bit, so every function must be ARM. On the iPad a Thumb
    # main crashed with SIGILL, and a Thumb ObjC method with SIGSYS (its first word decodes as ARM "svc").
    # An ARM function prologue has condition AL: 0xE in the top four bits of its first word.
    data = exe.read_bytes()
    fs = re.search(r"cmd LC_FUNCTION_STARTS\n\s+cmdsize \d+\n\s+dataoff (\d+)\n\s+datasize (\d+)", lc)
    text_vm = int(re.search(r"segname __TEXT\n\s+vmaddr 0x([0-9a-f]+)", lc).group(1), 16)
    off, end, addr, starts = int(fs.group(1)), int(fs.group(1)) + int(fs.group(2)), 0, []
    while off < end:
        delta, shift = 0, 0
        while True:
            b = data[off]
            off += 1
            delta |= (b & 0x7f) << shift
            shift += 7
            if b < 0x80:
                break
        if delta == 0:
            break
        addr += delta
        starts.append(addr)
    thumb = [hex(a) for a in starts if a & 1]
    not_arm = [hex(a) for a in starts if int.from_bytes(data[a & ~1:(a & ~1) + 4], "little") >> 28 != 0xE]
    check("all_functions_are_arm", "NFR-3", len(starts) > 100 and not thumb and len(not_arm) <= len(starts) // 100,
          f"{len(starts)} functions, {len(thumb)} marked Thumb, {len(not_arm)} without an ARM first word: {not_arm[:5]}")
    print(f"     functions: {len(starts)}, marked Thumb: {len(thumb)}, first word not ARM AL: {len(not_arm)}")
    sections = set(re.findall(r"sectname (\S+)", lc))
    tlv = sorted(s for s in sections if s.startswith("__thread_"))
    check("no_thread_local_variables", "NFR-3", not tlv, f"TLV sections: {tlv}")

    libs = [l.strip().split(" (")[0] for l in run("otool", "-L", str(exe)).splitlines()[1:] if l.strip()]
    extra = [l for l in libs if l not in IOS6_DYLIBS]
    check("links_only_ios6_libraries", "NFR-1", not extra, f"not in iOS 6: {extra}")

    imports = run("nm", "-u", str(exe)).split()
    bad = [s for s in imports if s in ("___atomic_is_lock_free", "__availability_version_check", "_getentropy",
                                       "_CCRandomGenerateBytes", "_SecRandomCopyBytes", "_clock_gettime",
                                       "_memset_s", "_explicit_bzero", "___isPlatformVersionAtLeast")]
    check("no_known_post_ios6_imports", "NFR-2", not bad, f"imports newer than iOS 6: {bad}")

    # C functions declared in usr/include with an availability newer than iOS 6 (heuristic header scan).
    syms = subprocess.run([sys.executable, "-I", str(pathlib.Path(__file__).parent.parent / "third_party/checks/ios6_syms.py"),
                           str(SDK), str(exe)], capture_output=True, text=True)
    lines = syms.stdout.splitlines()
    start = next((i for i, l in enumerate(lines) if l.startswith("FLAGGED")), None)
    flagged = ["(no FLAGGED section)"] if start is None else []
    for l in lines[start + 1:] if start is not None else []:
        if not l.startswith("  "):
            break
        if l.strip() != "none":
            flagged.append(l.strip())
    check("c_imports_available_in_ios6", "NFR-2", syms.returncode == 0 and not flagged,
          (syms.stdout + syms.stderr)[-400:])

    check("no_test_code_in_release", "NFR-1", b"PTSELFTEST" not in exe.read_bytes(), "SELFTEST build in a release package")

    signed = subprocess.run(["ldid", "-h", str(exe)], capture_output=True, text=True).stdout
    check("signed_with_ldid", "NFR-1", "CDHash" in signed, "no code signature")

with OUT.open("a") as f:
    for r in results:
        f.write(json.dumps(r) + "\n")
sys.exit(1 if any(r["status"] == "failed" for r in results) else 0)

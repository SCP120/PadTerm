#!/usr/bin/env python3
"""List nm -u imports of a Mach-O and flag symbols whose SDK header availability is > iOS 6.0.

usage: ios6_syms.py <sdk> <macho>
Also flags symbols not declared in any SDK header (cannot be judged from headers).
"""
import re, subprocess, sys, pathlib

sdk, exe = pathlib.Path(sys.argv[1]), sys.argv[2]
out = subprocess.run(["nm", "-u", exe], capture_output=True, text=True, check=True).stdout
syms = sorted({l.strip() for l in out.splitlines() if l.strip()})
inc = sdk / "usr/include"
files = [p for p in inc.rglob("*.h")]
text = {p: re.sub(r"/\*.*?\*/", " ", p.read_text(errors="ignore"), flags=re.S) for p in files}
ver = lambda m: tuple(int(x) for x in m.replace("_", ".").split(".")[:2])

def avail_after_6(decl):
    # __IPHONE_7_0 style, __IOS_AVAILABLE/__OSX_AVAILABLE_STARTING(.., __IPHONE_x_y), API_AVAILABLE(ios(x.y))
    vs = []
    for m in re.finditer(r"__IPHONE_(\d+)_(\d+)", decl): vs.append((int(m[1]), int(m[2])))
    for m in re.finditer(r"ios\((\d+)\.(\d+)", decl): vs.append((int(m[1]), int(m[2])))
    for m in re.finditer(r"__IOS_(\d+)_(\d+)", decl): vs.append((int(m[1]), int(m[2])))
    return [v for v in vs if v > (6, 0) and v < (99, 0)]

flagged, undeclared = [], []
for s in syms:
    name = s[1:] if s.startswith("_") else s
    if name.startswith(("OBJC_", "dyld_stub", "__tlv")): continue
    pat = re.compile(r"(?<![A-Za-z0-9_])" + re.escape(name) + r"\s*\(")
    decls = []  # (file, newest-introduced-version-or-None)
    for p, t in text.items():
        for m in pat.finditer(t):
            # declaration statement: from previous ';' or '}' up to the next ';'
            a = max(t.rfind(";", 0, m.start()), t.rfind("}", 0, m.start())) + 1
            b = t.find(";", m.end())
            decl = t[a:b if b > 0 else m.end() + 300]
            if len(decl) > 1500 or decl.lstrip().startswith(("*", "/")): continue
            v = avail_after_6(decl)
            decls.append((p.relative_to(inc), max(v) if v else None))
    if not decls: undeclared.append(name)
    elif all(v for _, v in decls):  # every declaration of the symbol says newer than iOS 6
        flagged.append((name, decls[0][0], decls[0][1]))
print(f"imports: {len(syms)}")
print("FLAGGED (availability > iOS 6.0):")
for n, p, v in flagged: print(f"  {n}  {p}  introduced {v[0]}.{v[1]}")
if not flagged: print("  none")
print("not found as a function declaration in SDK headers (data symbols / libSystem internals / compiler-rt):")
print("  " + " ".join(undeclared))

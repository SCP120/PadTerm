#!/usr/bin/env python3
"""Fail if a release would carry a secret, a session record, a test capture or a local path.

usage: check_release.py [--allow-mascots]
Scans what git would publish (tracked + untracked, minus .gitignore) and every package in dist/.
Extra words of your own (host names, user names, addresses), one per line, in the git-ignored build/release_denylist.txt.
"""
import io, pathlib, re, subprocess, sys, tarfile, tempfile, zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SECRET = {
    "private key": rb"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----\s+[A-Za-z0-9+/=]{40,}",
    "openssh key body": b"b3BlbnNzaC1" + b"rZXktdjE",
    "Anthropic key": rb"sk-ant-[A-Za-z0-9_-]{8,}",
    "OpenAI key": rb"\bsk-(?!ecdsa|ssh)(proj-)?[A-Za-z0-9_-]{24,}",  # libssh2 has names like sk-ecdsa-sha2-...
    "GitHub token": rb"(ghp_|gho_|ghs_|ghu_|github_pat_)[A-Za-z0-9_]{16,}",
    "GitLab token": rb"glpat-[A-Za-z0-9_-]{12,}",
    "AWS key": rb"AKIA[0-9A-Z]{16}",
    "JWT": rb"eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}",
    "URL with password": rb"[a-z]+://[^:/\s\"']+:[^@/\s\"']+@[^/\s\"']+",
}
# A Claude or Codex transcript line, not the code that reads them.
SESSION = {"transcript line": rb'"(parentUuid|sessionId|cwd|gitBranch)"\s*:\s*"', "rollout record": rb'"type"\s*:\s*"session_meta"'}
LOCAL = {"home path": rb"/(Users|home)/[a-z][a-z0-9_-]+/", "LAN address": rb"\b(?!192\.168\.1\.10\b)(192\.168|10\.\d{1,3}|172\.(1[6-9]|2\d|3[01])|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7]))\.\d{1,3}\.\d{1,3}\b", "machine name": rb"\b[a-z0-9-]+\.local\b"}
# Text that documents the format is fine: the example address of the form, and the fixtures that test the parser.
# 192.168.1.10 is the example in the form's hint and is not reported at all.
ALLOW = {"home path": {"tests/host/test_session.c", "tests/e2e/test_e2e.c"}, "machine name": {"tests/host/test_session.c", "docs/install/README.md", "scripts/check_release.py"}}
BAD_NAME = re.compile(r"(^|/)(id_(rsa|ed25519|ecdsa)[^/]*|[^/]*\.(key|pem|p12|mobileprovision|jsonl|ips)|\.env[^/]*|[^/]*credentials[^/]*|\.claude(/.*)?)$")
TEXT_ONLY = {".png", ".ttf"}

problems = []
dl = ROOT / "build/release_denylist.txt"
if not dl.exists():
    problems.append("no build/release_denylist.txt: add your own host names, user names and addresses, one per line")
deny = [re.escape(w.strip().encode()) for w in dl.read_text().splitlines() if w.strip()] if dl.exists() else []


def scan(name, data, tree):
    for group, table in (("secret", SECRET), ("session", SESSION), ("local", LOCAL)):
        for label, rx in table.items():
            if tree and name in ALLOW.get(label, ()):
                continue
            n = len(re.findall(rx, data))
            if n:
                problems.append(f"{group}: {label} x{n} in {name}")  # never the value
    for w in deny:
        if re.search(w, data, re.I):
            problems.append(f"denylist word in {name}")


files = subprocess.run(["git", "ls-files", "--others", "--cached", "--exclude-standard", "-z"], cwd=ROOT, capture_output=True, check=True).stdout.split(b"\0")
files = [f.decode() for f in files if f]
for f in files:
    p = ROOT / f
    if not p.is_file():
        continue
    if any(re.search(w, f.encode(), re.I) for w in deny):
        problems.append(f"denylist word in a file name: {f}")
    if BAD_NAME.search(f) or f.startswith("tests/artifacts/") or "__pycache__" in f:
        problems.append(f"file must not be published: {f}")
    if p.suffix.lower() not in TEXT_ONLY:
        scan(f, p.read_bytes(), True)
    if p.stat().st_size > 2_000_000:  # a source file of this project is under 200 KB; a font is 340 KB
        problems.append(f"large file: {f} {p.stat().st_size} bytes")

allow_mascots = "--allow-mascots" in sys.argv
newest = max((ROOT / f).stat().st_mtime for f in files if (ROOT / f).is_file() and f.split("/")[0] in ("core", "render", "ios", "scripts", "LICENSE"))
for pkg in (ROOT / "dist").glob("*"):
    if pkg.stat().st_mtime < newest:
        problems.append(f"stale package, built before the newest source: {pkg.name}")
with tempfile.TemporaryDirectory() as tmp:
    for pkg in sorted((ROOT / "dist").glob("*")):
        d = pathlib.Path(tmp) / pkg.name
        d.mkdir()
        if pkg.suffix == ".ipa":
            zipfile.ZipFile(pkg).extractall(d)
        elif pkg.suffix == ".deb":
            subprocess.run(["dpkg-deb", "-x", str(pkg), str(d)], check=True)
            scan(f"{pkg.name}:control", subprocess.run(["dpkg-deb", "-f", str(pkg)], capture_output=True, check=True).stdout, False)
            # A tar entry records the login name of whoever built the package.
            tar = subprocess.run(["dpkg-deb", "--fsys-tarfile", str(pkg)], capture_output=True, check=True).stdout
            with tarfile.open(fileobj=io.BytesIO(tar)) as t:
                owners = {(m.uname, m.gname) for m in t.getmembers()}
            if owners != {("root", "root")}:
                problems.append(f"tar owner in {pkg.name} is not root ({len(owners)} owners)")
        else:
            continue
        for p in d.rglob("*"):
            if not p.is_file():
                continue
            rel = f"{pkg.name}:{p.relative_to(d)}"
            if p.name.startswith("mascot_") and not allow_mascots:
                problems.append(f"mascot art in a package: {rel}")
            if p.suffix.lower() not in TEXT_ONLY:
                data = p.read_bytes()
                scan(rel, data, False)
                if b"PTSELFTEST" in data:
                    problems.append(f"test code in a package: {rel}")

mail = subprocess.run(["git", "config", "user.email"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
if not mail.endswith("@users.noreply.github.com"):
    problems.append("commit identity: git user.email is not a GitHub noreply address, and each commit publishes it")

print(f"checked {len(files)} files and {len(list((ROOT / 'dist').glob('*')))} packages")
for x in problems:
    print("FAIL", x)
print("ok: nothing found" if not problems else f"{len(problems)} problems")
sys.exit(1 if problems else 0)

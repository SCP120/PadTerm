#!/usr/bin/env python3
"""A private key must not stay behind in File Sharing or on screen. Runs against the Catalyst bench, whose home is a test folder.
The pasteboard branch is not run here: on a Mac it would touch the real clipboard."""
import os
import pathlib
import subprocess
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).parents[1] / "device"))
import device_test as d  # noqa: E402

HOME = d.ROOT / "build/catalyst/home"
DOCS = HOME / "Documents"
APP = d.ROOT / "build/catalyst/PadTerm.app"
KEY = (d.SSHD / "client_ed25519").read_bytes()
failed = []


def check(name, ok, info=""):
    print(("ok   " if ok else "FAIL ") + name + (f"  {info}" if info and not ok else ""), flush=True)
    if not ok:
        failed.append(name)


def launch():
    subprocess.run(["pkill", "-f", "catalyst/PadTerm.app"])
    time.sleep(1)
    subprocess.run(["open", "-n", "--env", f"CFFIXED_USER_HOME={HOME}", str(APP)], check=True)
    time.sleep(4)
    return d.Control()


subprocess.run(["rm", "-rf", str(HOME)])
DOCS.mkdir(parents=True)
(DOCS / "left.key").write_bytes(KEY)
ctl = launch()
shown = ctl("alertshown")
check("leftover_key_file_warns_at_launch", "left.key" in shown and "Private key file found" in shown, shown)
check("warning_does_not_show_the_key", "PRIVATE" not in shown and "OPENSSH" not in shown, shown)
ctl("alertok")
time.sleep(0.5)

(DOCS / "cancelme.key").write_bytes(KEY)
ctl("screen new"); time.sleep(1)
ctl("setfield 0 cancelme")
ctl("tap Import file"); time.sleep(0.4)
r = ctl("tap Import <name>"); time.sleep(0.5)
check("import_row_accepts_the_file", r.strip() == "ok" and not ctl("alertshown").strip(), ctl("alertshown"))
check("file_stays_until_save_or_cancel", (DOCS / "cancelme.key").exists())
ctl("tap Cancel"); time.sleep(1)
check("cancel_removes_the_imported_copy", not (DOCS / "cancelme.key").exists())
check("cancel_leaves_other_files", (DOCS / "left.key").exists())

(DOCS / "savedone.key").write_bytes(KEY)
ctl("screen new"); time.sleep(1)
for i, v in enumerate(["savedone", "127.0.0.1", "22", "me", "~"]):
    ctl(f"setfield {i} {v}")
ctl("tap Import file"); time.sleep(0.4)
ctl("tap Import <name>"); time.sleep(0.5)
ctl("tap Save"); time.sleep(1)
check("save_removes_the_imported_copy", not (DOCS / "savedone.key").exists())
stored = list(HOME.rglob("keys/*.key"))
check("save_stores_the_key_in_library", len(stored) == 1 and "Library" in str(stored[0]), str(stored))
check("stored_key_mode_0600", stored and oct(os.stat(stored[0]).st_mode & 0o777) == "0o600")
excl = subprocess.run(["xattr", "-l", str(stored[0])], capture_output=True, text=True).stdout if stored else ""
check("stored_key_excluded_from_backup", "com.apple.metadata:com_apple_backup_excludeItem" in excl, excl[:120])

ctl("resetprofiles")
subprocess.run(["pkill", "-f", "catalyst/PadTerm.app"])
print(f"key handling: {len(failed)} failed")
sys.exit(1 if failed else 0)

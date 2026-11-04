#!/usr/bin/env python3
"""WARNING: at the end this removes ~/.padterm on the server: use a test server.

UC-SESSION on the iPad over real Wi-Fi to your server, with real Claude: name, rename, resume.
usage: wifi_sessions_test.py <label>   The mini runs a live service: only tmux -L padterm and one project folder are touched."""
import json
import os
import pathlib
import subprocess
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import device_test as d  # noqa: E402
from sessions_test import rows, wait_rows  # noqa: E402

ROOT = d.ROOT
KEY = ROOT / "build/ipad/id_ed25519_mini"
KNOWN = ROOT / "build/ipad/known_hosts_mini"
HOST, USER = os.environ["PT_WIFI_HOST"], os.environ["PT_WIFI_USER"]
DIR = "~/padterm-test/sessions"
d.ART = ROOT / f"tests/artifacts/wifi/{sys.argv[1]}"
d.ART.mkdir(parents=True, exist_ok=True)


def mini(cmd, timeout=30):
    r = subprocess.run(["ssh", "-i", str(KEY), "-o", "IdentitiesOnly=yes", "-o", f"UserKnownHostsFile={KNOWN}", "-o", "BatchMode=yes",
                        "-o", "ConnectTimeout=8", f"{USER}@{HOST}", 'export PATH="$PATH:/opt/homebrew/bin"; ' + cmd],
                       capture_output=True, text=True, timeout=timeout)
    return r.stdout + r.stderr


def wait_ready(ctl, timeout=90):
    """Answer the trust question if it shows; return when Claude's input box is on screen."""
    end = time.time() + timeout
    while time.time() < end:
        s = ctl("dump")
        if "trust this folder" in s:
            ctl("tapkey \u2193")  # the first choice is "No, exit"
            time.sleep(0.8)
            ctl("tapkey \u23ce")
            time.sleep(3)
        elif "for shortcuts" in s or "auto mode" in s:
            return s
        time.sleep(0.5)
    raise AssertionError("no input box: " + ctl("dump")[-600:])


def main():
    fp = next(l for l in subprocess.run(["ssh-keygen", "-lf", str(KNOWN)], capture_output=True, text=True).stdout.splitlines()
              if "ED25519" in l).split()[1]
    key = KEY.read_bytes().hex()
    ctl = d.Control()
    assert ctl("ping").strip() == "pong"
    mini(f"mkdir -p {DIR.replace('~', '$HOME')}")
    assert ctl(f"profile {USER} {DIR} {fp} {key} {HOST} 22").strip() == "ok"
    ctl("screen launch")
    time.sleep(2)
    t0 = time.time()
    r0 = rows(ctl)
    state = {}

    @d.test("wifi_new_claude_gets_its_name", "AC-SESSION-1 AC-SESSION-3 AC-SESSION-4")
    def _():
        assert ctl("launch claude").strip() == "ok"
        wait_ready(ctl)
        d.shot("claude_new")
        assert "New session" in ctl("title"), ctl("title")
        ctl("type Reply with one word: pong. Do not use any tool.\\n")
        end = time.time() + 120
        while time.time() < end and "New session" in ctl("title"):
            time.sleep(1)
        name = ctl("title").strip()
        assert "New session" not in name, "the bar has no name"
        state["bar"] = name
        d.shot("claude_named")
        ctl("back")
        ctl("screen launch")
        row = wait_rows(ctl, lambda r: r and r[0][5] != "New session", 60, "name in the list")[0]
        state["key"] = row[0]
        d.shot("list_with_name")
        return f"bar: {name}; list: {row}"

    @d.test("wifi_rename_updates_list_and_bar", "AC-SESSION-3 AC-SESSION-4")
    def _():
        k = state["key"]
        i = [x[0] for x in wait_rows(ctl, lambda r: k in [y[0] for y in r], 30, "row")].index(k)
        assert ctl(f"session {i}").strip() == "ok"
        wait_ready(ctl, 40)
        ctl("type /rename padterm renamed\\n")
        end = time.time() + 40
        while time.time() < end and "padterm renamed" not in ctl("title"):
            time.sleep(1)
        bar = ctl("title").strip()
        assert "padterm renamed" in bar, f"bar: {bar}"
        ctl("back")
        ctl("screen launch")
        row = wait_rows(ctl, lambda r: r and [x for x in r if x[0] == k] and [x for x in r if x[0] == k][0][5] == "padterm renamed", 60, "new name in list")
        d.shot("list_renamed")
        return f"bar: {bar}"

    @d.test("wifi_stopped_session_resumes_with_history", "AC-SESSION-5")
    def _():
        k = state["key"]
        mini(f"tmux -L padterm kill-session -t '=pc-{k}'")
        wait_rows(ctl, lambda r: [x for x in r if x[0] == k] and [x for x in r if x[0] == k][0][2] == "0", 40, "not running")
        d.shot("list_stopped")
        i = [x[0] for x in rows(ctl)].index(k)
        assert ctl(f"session {i}").strip() == "ok"
        s = wait_ready(ctl, 90)
        assert "pong" in ctl("dump").lower(), "no history on screen: " + ctl("dump")[-500:]
        d.shot("resumed")
        cmd = mini(f"tmux -L padterm list-panes -t '=pc-{k}' -F '#{{pane_title}}|#{{pane_current_command}}'; "
                   f"ps -axo command | grep -oF -- 'claude --resume {k}' | head -1")
        assert f"--resume {k}" in cmd, cmd
        ctl("back")
        return cmd.strip().replace("\n", " ; ")

    @d.test("wifi_clean_exit_then_resume", "AC-SESSION-5")
    def _():
        k = state["key"]
        rows_now = wait_rows(ctl, lambda r: k in [y[0] for y in r], 30, "row")
        assert ctl(f"session {[x[0] for x in rows_now].index(k)}").strip() == "ok"
        wait_ready(ctl, 60)
        ctl("type /exit")
        time.sleep(1.5)
        ctl("tapkey \u23ce")
        end = time.time() + 30
        while time.time() < end and f"pc-{k}" in mini("tmux -L padterm list-sessions -F '#{session_name}' 2>/dev/null"):
            time.sleep(1)
        assert f"pc-{k}" not in mini("tmux -L padterm list-sessions -F '#{session_name}' 2>/dev/null"), "tmux session still there after /exit"
        time.sleep(2)
        status = ctl("status").strip()
        # A wake must not start the agent again: the user ended it.
        assert "ended" in status.lower(), status
        ok = ctl("foreground").strip()
        time.sleep(5)
        assert f"pc-{k}" not in mini("tmux -L padterm list-sessions -F '#{session_name}' 2>/dev/null"), f"a wake started it again ({ok})"
        ctl("back")
        ctl("screen launch")
        r = wait_rows(ctl, lambda r: [x for x in r if x[0] == k and x[2] == "0"], 40, "not running after /exit")
        assert ctl(f"session {[x[0] for x in r].index(k)}").strip() == "ok"
        wait_ready(ctl, 90)
        assert "pong" in ctl("dump").lower(), "no history after /exit: " + ctl("dump")[-400:]
        ctl("back")
        return status

    @d.test("wifi_second_session_changes_through_popover", "AC-SESSION-6")
    def _():
        ctl("screen launch")
        assert ctl("launch claude").strip() == "ok"
        wait_ready(ctl)
        first = ctl("title").strip()
        assert first == "New session", first
        ctl("sessionspopover")
        time.sleep(6)
        d.shot("sessions_popover")
        # Row 1 is the renamed session: this new one is row 0.
        assert ctl("popoverselect 1").strip() == "ok"
        time.sleep(4)
        assert ctl("title").strip() == "padterm renamed", ctl("title")
        d.shot("changed_by_popover")
        # A closed terminal with the popover open once crashed the app: UIPopoverController released while visible.
        ctl("sessionspopover")
        time.sleep(1)
        ctl("back")
        time.sleep(2)
        assert ctl("ping").strip() == "pong", "the app stopped"

    ctl("resetprofiles")
    print("mini cleanup:", mini("tmux -L padterm kill-server 2>/dev/null; rm -rf ~/.padterm ~/padterm-test/sessions; echo done").strip())
    (d.ART / "sessions_results.json").write_text(json.dumps(d.results, indent=1, ensure_ascii=False))
    failed = [r["name"] for r in d.results if r["status"] == "failed"]
    print(f"wifi sessions: {len(d.results)} run, {len(failed)} failed; {time.time() - t0:.0f} s")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())

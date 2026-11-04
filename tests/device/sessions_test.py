#!/usr/bin/env python3
"""UC-SESSION on the real iPad, over the USB relay, with real Claude and Codex on this Mac. No prompt is sent here;
tests/device/wifi_claude_test.py covers real names on the mini."""
import json
import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import device_test as d  # noqa: E402


def rows(ctl):
    return [l.split("|") for l in ctl("sessions").splitlines() if "|" in l]


def wait_rows(ctl, pred, timeout=40, what="rows"):
    end = time.time() + timeout
    last = None
    while time.time() < end:
        last = rows(ctl)
        if pred(last):
            return last
        time.sleep(1)
    raise AssertionError(f"timeout: {what}; rows: {last}; raw: {ctl('sessions')}")


def main():
    fp = (d.SSHD / "expected_fingerprint").read_text().strip()
    key = (d.SSHD / "client_ed25519").read_bytes().hex()
    user = d.getpass.getuser()
    work = d.ROOT / "build/e2e-work/dev-a"
    work.mkdir(parents=True, exist_ok=True)
    d.tmux("kill-server")
    d.Bridge().start()
    ctl = d.Control()
    assert ctl("ping").strip() == "pong"
    assert ctl(f"profile {user} {work} {fp} {key}").strip() == "ok"
    ctl("screen launch")
    test = d.test

    before = len(wait_rows(ctl, lambda r: True, 3))

    @test("session_new_plate_adds_a_row", "AC-SESSION-1 AC-SESSION-2")
    def _():
        assert ctl("launch claude").strip() == "ok"
        d.wait(ctl, lambda t: any(k in t for k in ("trust this folder", "Claude Code", "Welcome")), 60, "claude")
        d.shot("session_new_claude")
        ctl("back")
        ctl("screen launch")
        r = wait_rows(ctl, lambda r: len(r) == before + 1, 30, "one more row")
        assert r[0][1] == "Claude" and r[0][2] == "1" and r[0][5] == "New session", r[0]
        d.shot("session_list_one")
        return str(r[0])

    @test("session_second_plate_keeps_the_first", "AC-SESSION-1")
    def _():
        assert ctl("launch claude").strip() == "ok"
        d.wait(ctl, lambda t: any(k in t for k in ("trust this folder", "Claude Code", "Welcome")), 60, "claude")
        ctl("back")
        ctl("screen launch")
        r = wait_rows(ctl, lambda r: len(r) == before + 2, 30, "two rows")
        names = d.tmux("list-sessions", "-F", "#{session_name}").stdout.split()
        assert len([n for n in names if n.startswith("pc-")]) >= 2, names
        return f"tmux: {len(names)} sessions"

    @test("session_row_attaches_to_the_running_one", "AC-SESSION-5")
    def _():
        k = wait_rows(ctl, lambda r: len(r) >= 2, 30, "rows")[1][0]
        assert ctl("session 1").strip() == "ok"
        d.wait(ctl, lambda t: any(x in t for x in ("trust this folder", "Claude Code", "Welcome")), 30, "attached screen")
        out = d.tmux("list-clients", "-F", "#{client_session}").stdout
        assert f"pc-{k}" in out, out
        # Attach counts as activity: this row comes first now.
        ctl("back")
        ctl("screen launch")
        wait_rows(ctl, lambda r: r and r[0][0] == k, 30, "attached row first")
        return k

    @test("session_stopped_one_starts_again", "AC-SESSION-5")
    def _():
        k = wait_rows(ctl, lambda r: len(r) >= 1, 30, "rows")[0][0]
        d.tmux("kill-session", "-t", f"=pc-{k}")
        wait_rows(ctl, lambda r: [x for x in r if x[0] == k][0][2] == "0", 30, "row not running")
        d.shot("session_list_stopped")
        i = [x[0] for x in wait_rows(ctl, lambda r: k in [y[0] for y in r], 30, "row")].index(k)
        assert ctl(f"session {i}").strip() == "ok"
        d.wait(ctl, lambda t: any(x in t for x in ("trust this folder", "Claude Code", "Welcome")), 60, "agent again")
        names = d.tmux("list-sessions", "-F", "#{session_name}").stdout.split()
        assert f"pc-{k}" in names, names
        ctl("back")
        return k

    @test("session_codex_row", "AC-SESSION-1 AC-SESSION-2")
    def _():
        ctl("screen launch")
        assert ctl("launch codex").strip() == "ok"
        d.wait(ctl, lambda t: "Codex" in t or "Update available" in t, 60, "codex")
        d.shot("session_new_codex")
        ctl("back")
        ctl("screen launch")
        r = wait_rows(ctl, lambda r: r and r[0][1] == "Codex", 30, "codex first")
        return str(r[0])

    @test("session_codex_real_name_and_resume", "AC-SESSION-3 AC-SESSION-4 AC-SESSION-5")
    def _():
        k = wait_rows(ctl, lambda r: r and r[0][1] == "Codex", 30, "codex row")[0][0]
        assert ctl("session 0").strip() == "ok"
        end = time.time() + 40
        while time.time() < end:
            t = ctl("dump")
            if "Skip until next version" in t:
                ctl("tapkey Esc")  # never "Update now": this test does not change the Mac's Codex
                time.sleep(3)
            elif "Ask Codex" in t:
                break
            elif "trust" in t.lower() and "1." in t:
                ctl("tapkey \u23ce")
                time.sleep(3)
            time.sleep(0.5)
        ctl("type Reply with the two words: padterm probe")
        time.sleep(1.5)  # text and Enter in one burst count as a paste in Codex
        ctl("tapkey \u23ce")
        end = time.time() + 90
        while time.time() < end and ctl("title").strip() == "New session":
            time.sleep(1)
        bar = ctl("title").strip()
        assert bar != "New session", "no name in the bar: " + ctl("dump")[-500:]
        d.shot("codex_named")
        ctl("back")
        ctl("screen launch")
        row = wait_rows(ctl, lambda r: [x for x in r if x[0] == k and x[5] != "New session"], 60, "codex name in the list")
        name = [x for x in row if x[0] == k][0][5]
        rec = (d.pathlib.Path.home() / f".padterm/sessions/{k}").read_text().splitlines()
        assert len(rec) == 3 and "rollout-" in rec[2], rec
        d.tmux("kill-session", "-t", f"=pc-{k}")
        row = wait_rows(ctl, lambda r: [x for x in r if x[0] == k and x[2] == "0"], 40, "stopped")
        assert ctl(f"session {[x[0] for x in row].index(k)}").strip() == "ok"
        def resumed(t):
            if "Skip until next version" in t:
                ctl("tapkey Esc")  # the same prompt at each start
            return "padterm probe" in t
        d.wait(ctl, resumed, 60, "history after resume")
        d.shot("codex_resumed")
        cmd = d.subprocess.run(["ps", "-axo", "command"], capture_output=True, text=True).stdout
        cid = rec[2].rsplit("/", 1)[1].split("T", 1)[1][9:-6]
        assert f"codex resume {cid}" in cmd, cid
        ctl("back")
        return f"bar: {bar}; list: {name}; resumed {cid}"

    @test("session_delete_removes_row_and_tmux", "AC-SESSION-7")
    def _():
        k = wait_rows(ctl, lambda r: len(r) >= 1, 30, "rows")[0][0]
        assert ctl("sessionrm 0").strip() == "ok"
        end = time.time() + 20
        while f"pc-{k}" in d.tmux("list-sessions", "-F", "#{session_name}").stdout:
            assert time.time() < end, "tmux session still there"
            time.sleep(0.5)
        ctl("screen launch")  # a new read from the server: the row must not come back
        time.sleep(3)
        assert k not in [y[0] for y in rows(ctl)], rows(ctl)
        assert not list(d.pathlib.Path.home().glob(f".padterm/sessions/{k}")), "record still there"
        return k

    d.tmux("kill-server")
    failed = [r["name"] for r in d.results if r["status"] == "failed"]
    print(f"sessions: {len(d.results)} run, {len(failed)} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())

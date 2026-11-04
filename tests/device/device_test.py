#!/usr/bin/env python3
"""Drive a SELFTEST build of PadTerm on the USB-connected iPad, against the private test sshd on this Mac.

Path: pt_conn on the iPad -> relay in the app -> usbmux -> bridge here -> sshd 127.0.0.1:2222.
No prompt is sent to an agent. Writes tests/artifacts/device_results.json and screenshots in tests/artifacts/device/.
"""
import getpass
import json
import os
import pathlib
import socket
import subprocess
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
ART = ROOT / "tests/artifacts/device"
ART.mkdir(parents=True, exist_ok=True)
SSHD = ROOT / "build/e2e-sshd"
results = []


class Bridge(threading.Thread):
    """Connects through iproxy to the app's relay; opens sshd when the iPad sends its first byte."""
    daemon = True

    def __init__(self):
        super().__init__()
        self.cut_now = threading.Event()
        self.sessions = 0

    def run(self):
        while True:
            try:
                a = socket.create_connection(("127.0.0.1", 5022), timeout=3)
                a.settimeout(1)
                first = None
                while first is None:
                    try:
                        first = a.recv(65536)
                    except socket.timeout:
                        continue
                if not first:
                    a.close()
                    time.sleep(0.2)
                    continue
                b = socket.create_connection(("127.0.0.1", 2222))
                b.sendall(first)
                self.sessions += 1
                # The list and the terminal each hold a connection at the same time.
                threading.Thread(target=self.pump, args=(a, b), daemon=True).start()
            except OSError:
                time.sleep(0.3)

    def pump(self, a, b):
        import select
        a.setblocking(True)
        while not self.cut_now.is_set():
            try:
                r, _, _ = select.select([a, b], [], [], 0.2)
                for s in r:
                    d = s.recv(65536)
                    if not d:
                        a.close(); b.close()
                        return
                    (b if s is a else a).sendall(d)
            except OSError:  # the other pair's cut, or a USB drop
                a.close(); b.close()
                return
        self.cut_now.clear()
        a.close(); b.close()


class Control:
    def __init__(self):
        self.s = socket.create_connection(("127.0.0.1", 5024), timeout=30)
        self.f = self.s.makefile("rwb")

    def __call__(self, line):
        self.f.write(line.encode() + b"\n")
        self.f.flush()
        out = []
        while True:
            l = self.f.readline()
            if not l:
                raise RuntimeError("control channel closed: the app stopped?")
            if l.startswith(b"\x01END"):
                return b"".join(out).decode("utf-8", "replace")
            out.append(l)


def shot(name):
    t = ART / f"{name}.tiff"
    subprocess.run(["idevicescreenshot", str(t)], capture_output=True)
    subprocess.run(["sips", "-s", "format", "png", str(t), "--out", str(ART / f"{name}.png")], capture_output=True)
    t.unlink(missing_ok=True)


def test(name, ids):
    def deco(fn):
        t0 = time.time()
        try:
            note = fn() or ""
            status, msg = "passed", str(note)
        except Exception as e:  # one failure must not stop the remaining device checks
            status, msg = "failed", f"{type(e).__name__}: {e}"
        results.append({"suite": "device", "name": name, "ids": ids, "status": status,
                        "duration_ms": round((time.time() - t0) * 1000), "message": msg})
        print(("ok   " if status == "passed" else "FAIL ") + name + (f"\n     {msg}" if msg else ""), flush=True)
        return fn
    return deco


def wait(ctl, pred, timeout=30, what="screen"):
    end = time.time() + timeout
    last = ""
    while time.time() < end:
        last = ctl("dump")
        if pred(last):
            return last
        time.sleep(0.3)
    raise AssertionError(f"timeout waiting for {what}; screen:\n" + "\n".join(l for l in last.splitlines() if l.strip())[-900:])


def marker_row(text, marker):
    return next((l for l in text.splitlines() if marker in l), None)


def tmux(*args):
    env = dict(os.environ, TMUX_TMPDIR=str(SSHD / "tmux"))
    return subprocess.run(["tmux", "-L", "padterm", *args], env=env, capture_output=True, text=True)


def main():
    fp = (SSHD / "expected_fingerprint").read_text().strip()
    key = (SSHD / "client_ed25519").read_bytes().hex()
    user = getpass.getuser()
    work = ROOT / "build/e2e-work"
    (work / "dev-a").mkdir(parents=True, exist_ok=True)
    (work / "dev-b").mkdir(parents=True, exist_ok=True)
    tmux("kill-server")
    bridge = Bridge()
    bridge.start()
    ctl = Control()
    assert ctl("ping").strip() == "pong"

    def profile(pin, directory):
        r = ctl(f"profile {user} {directory} {pin} {key}").strip()
        assert r == "ok", r

    @test("device_wrong_pin_refused", "BR-CONNECT-2")
    def _():
        profile("SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "~")
        ctl("open shell")
        end = time.time() + 20
        while time.time() < end:
            st = ctl("status")
            if "host key does not match" in st:
                shot("wrong_pin")
                return st.strip()
            time.sleep(0.3)
        raise AssertionError(ctl("status"))

    @test("device_host_key_first_use", "BR-CONNECT-1 AC-CONNECT-1")
    def _():
        profile("-", "~")
        ctl("open shell")
        time.sleep(4)
        shot("host_key_alert")
        assert ctl("alert trust").strip() == "ok", "no alert appeared"
        end = time.time() + 30
        while "connected=1" not in ctl("status"):
            assert time.time() < end, ctl("status")
            time.sleep(0.3)
        got = ctl("pin").strip()
        assert got == fp, f"pin {got} != ssh-keygen {fp}"
        return f"pin = ssh-keygen fingerprint: {got}"

    @test("device_shell_session_over_ssh", "AC-CONNECT-1 AC-CONNECT-2 AC-LAUNCH-1 AC-INPUT-3")
    def _():
        profile(fp, "~")
        ctl("open shell")
        wait(ctl, lambda s: "%" in s or "$" in s, 30, "shell prompt")
        ctl("type export PTMARK=7; echo PT-$((40+2)); printf 'T=%s\\n' $TERM\\n")
        wait(ctl, lambda s: "PT-42" in s, 15, "PT-42")
        shot("shell")
        return "rows cols " + ctl("size").strip()

    @test("device_colours_and_characters", "AC-SCREEN-1 AC-SCREEN-4 AC-SCREEN-5")
    def _():
        script = ROOT / "build/e2e-work/colors.sh"
        script.write_text(
            r"""printf '\033[2J\033[H'
printf '\033[38;2;215;119;87m\xe2\x97\x8f\033[0m Read(\033[1msrc/app.ts\033[0m)\n'
printf '  \xe2\x8e\xbf  Read \033[1m42\033[0m lines \033[2m(ctrl+o to expand)\033[0m\n'
printf '\033[32m+ added\033[0m \033[31m- removed\033[0m \033[3mitalic\033[0m \033[4munder\033[0m \033[7mreverse\033[0m\n'
printf '\xe2\x95\xad\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x95\xae\n\xe2\x94\x82 \xe2\x9d\xaf hi \xe2\x94\x82 \xe2\x8f\xb5\xe2\x8f\xb5 accept  \xe2\x9c\xbb Thinking\xe2\x80\xa6\n\xe2\x95\xb0\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x95\xaf\n'
printf '\xe2\x80\xba 1. Update  \xe2\x80\xa2 codex  \xe2\x8f\xba \xe2\x8f\xb8 \xe2\x8f\xb9 \xe2\xa7\x89 \xe2\x8e\xaf\xe2\x8e\xaf\n'
printf '\033[48;5;236m 256 bg \033[0m \033[38;5;208morange\033[0m \xe4\xb8\xad\xe6\x96\x87 \xc3\xa9 \xe2\x96\x80\xe2\x96\x84\xe2\x96\x88\xe2\x96\x91\xe2\x96\x92\xe2\x96\x93\n'
echo COLORS-$((1+1))
""")
        ctl(f"type sh {script}\\n")
        wait(ctl, lambda s: "COLORS-2" in s, 10, "colour page")
        time.sleep(0.5)
        shot("colours")

    @test("device_font_and_theme", "AC-SCREEN-7")
    def _():
        before = ctl("size").strip()
        ctl("font +"); ctl("font +"); time.sleep(0.8)
        bigger = ctl("size").strip()
        assert before != bigger, f"size did not change: {before}"
        ctl("type stty size\\n")
        r, c = bigger.split()
        wait(ctl, lambda s: f"{r} {c}" in s, 10, "stty size on the server")
        shot("font_bigger")
        ctl("font -"); ctl("font -"); ctl("theme"); time.sleep(0.8)
        shot("theme_light")
        ctl("theme"); time.sleep(0.5)
        return f"{before} -> {bigger}; server stty agrees"

    @test("device_render_speed", "NFR-1")
    def _():
        ctl("type for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do echo line $i The quick brown fox jumps over the lazy dog 0123456789 abcdefghijklmnopqrstuvwxyz ABCDEFG; done\\n")
        time.sleep(3)
        ms = float(ctl("perf 10").strip())
        return f"full redraw on A5: {ms} ms per frame at {ctl('size').strip()} (rows cols)"

    @test("device_output_speed", "NFR-1")
    def _():
        ctl("type clear\\n")
        t0 = time.time()
        ctl("type head -c 500000 /dev/zero | tr '\\\\0' x; echo; echo DONE-$((2+2))\\n")
        wait(ctl, lambda s: "DONE-4" in s, 120, "500 kB output")
        dt = time.time() - t0
        return f"500 kB through SSH + tmux + terminal: {dt:.1f} s ({500 / dt:.0f} kB/s)"

    @test("device_reconnect_after_lost_link", "AC-RECONNECT-2")
    def _():
        ctl("type export PTR=9; clear\\n")
        time.sleep(1)
        before = bridge.sessions
        bridge.cut_now.set()
        end = time.time() + 15
        seen = ""
        while time.time() < end:
            seen = ctl("status")
            if "reconnecting" in seen:
                break
            time.sleep(0.1)
        assert "reconnecting" in seen, seen
        shot("reconnecting")
        end = time.time() + 40
        while "connected=1" not in ctl("status"):
            assert time.time() < end, ctl("status")
            time.sleep(0.3)
        assert bridge.sessions > before
        time.sleep(1.5)
        ctl("type echo R$PTR-Y\\n")
        wait(ctl, lambda s: "R9-Y" in s, 15, "same shell after reconnect")
        return seen.strip()

    @test("device_attach_keeps_session", "AC-LAUNCH-3 BR-RECONNECT-1")
    def _():
        ctl("back")
        time.sleep(1)
        ctl("open shell")
        wait(ctl, lambda s: "%" in s or "$" in s, 30, "prompt")
        time.sleep(1)
        ctl("type echo M$PTMARK-X\\n")
        wait(ctl, lambda s: "M7-X" in s, 15, "same shell after attach")
        ctl("back")

    @test("device_profile_screens_open", "AC-PROFILE-1 AC-LAUNCH-1")
    def _():
        for name in ("list", "new", "edit", "launch"):
            assert ctl(f"screen {name}").strip() == "ok"
            time.sleep(1)
            shot(f"screen_{name}")
        ctl("back")
        assert ctl("ping").strip() == "pong"

    @test("device_key_import_from_documents", "AC-PROFILE-2")
    def _():
        ctl("back")
        # --container, not --documents: on iOS 6 that mode opens the container root, not Documents.
        p = subprocess.run(["afcclient", "--container", "dev.padterm.app"], capture_output=True, text=True,
                           input=f"put {SSHD / 'client_ed25519'} Documents/mac-usb.key\nls Documents\nquit\n")
        assert "mac-usb.key" in p.stdout, p.stdout + p.stderr
        r = ctl("import mac-usb").strip()
        assert r == "ok", r
        p = subprocess.run(["afcclient", "--container", "dev.padterm.app"], capture_output=True, text=True, input="ls Documents\nquit\n")
        assert "mac-usb.key" not in p.stdout, "key copy left in Documents"
        ctl("open shell")
        wait(ctl, lambda s: "%" in s or "$" in s, 30, "prompt with the imported key")
        ctl("back")

    @test("device_claude_screen_and_keys", "AC-LAUNCH-2 AC-INPUT-2 AC-SCREEN-2 AC-SCREEN-4")
    def _():
        profile(fp, str(work / "dev-a"))
        ctl("open claude")
        s = wait(ctl, lambda t: any(k in t for k in ("trust this folder", "Claude Code", "Welcome to Claude")), 90, "claude")
        time.sleep(1.5)
        s = ctl("dump")
        shot("claude")
        before = marker_row(s, "❯")
        assert before, "no marker row"
        ctl("key down")
        end = time.time() + 15
        while time.time() < end:
            after = marker_row(ctl("dump"), "❯")
            if after and after != before:
                shot("claude_after_down")
                ctl("back")
                tmux("kill-server")
                return f"[{before.strip()}] -> [{after.strip()}]"
            time.sleep(0.3)
        raise AssertionError(f"marker did not move: {before}")

    @test("device_codex_screen_and_keys", "AC-LAUNCH-2 AC-INPUT-2 AC-SCREEN-2 AC-SCREEN-4")
    def _():
        profile(fp, str(work / "dev-b"))
        ctl("open codex")
        wait(ctl, lambda t: any(k in t for k in ("OpenAI Codex", "Update available", "trust the", "Codex")), 90, "codex")
        time.sleep(2)
        s = ctl("dump")
        shot("codex")
        before = marker_row(s, "›")
        assert before, "no marker row"
        ctl("key down")
        end = time.time() + 15
        while time.time() < end:
            after = marker_row(ctl("dump"), "›")
            if after and after != before:
                shot("codex_after_down")
                ctl("back")
                tmux("kill-server")
                return f"[{before.strip()}] -> [{after.strip()}]"
            time.sleep(0.3)
        raise AssertionError(f"marker did not move: {before}")

    tmux("kill-server")
    (ROOT / "tests/artifacts/device_results.json").write_text(json.dumps(results, indent=1, ensure_ascii=False))
    failed = [r["name"] for r in results if r["status"] == "failed"]
    print(f"device: {len(results)} run, {len(failed)} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())

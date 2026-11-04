#!/usr/bin/env python3
"""The real test: PadTerm on the iPad, over Wi-Fi, drives real Claude Code on your server to build a note app.

USB carries only the control port and monitoring; SSH goes iPad Wi-Fi -> PT_WIFI_HOST:22. usage: wifi_claude_test.py <label>
Writes tests/artifacts/wifi/<label>/: stats.jsonl, summary.json, progress.log, screenshots, the app Claude made.
"""
import json
import os
import pathlib
import re
import socket
import statistics
import subprocess
import sys
import threading
import time

LABEL = sys.argv[1]  # also used by wifi_soak_test.py
ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "tests/artifacts/wifi" / LABEL
OUT.mkdir(parents=True, exist_ok=True)
KEY = ROOT / "build/ipad/id_ed25519_mini"
# Your own lab: PT_WIFI_HOST (server), PT_WIFI_USER (login there), PT_WIFI_IPAD (the iPad's address).
MINI, USER, IPAD = os.environ["PT_WIFI_HOST"], os.environ["PT_WIFI_USER"], os.environ["PT_WIFI_IPAD"]
WORK = f"padterm-test/notes-{LABEL}"
UP, DOWN, ENTER = "\u2191", "\u2193", "\u23ce"
PROMPTS = [
    "Create a small note-taking web app in this folder: one file index.html with inline CSS and JS, notes saved in localStorage, with add, edit and delete. Keep it under 150 lines. Do not start a server.",
    "Add a search box that filters notes as I type.",
    "Add tags: a note can have comma-separated tags, and clicking a tag filters by that tag.",
    "Add a dark mode toggle that is remembered across reloads.",
    "Add export to a JSON file and import from a JSON file.",
    "Write test.js that runs the note logic in node with no dependencies and checks add, edit, delete and search. Run it and fix any failures.",
    "Print the whole of index.html here in this chat as a code block, every line.",
    "In 25 short bullet points, explain how the code works.",
    "List the files in this folder with their sizes using ls -l.",
    "Add a note count at the top of the page and make sure test.js still passes. Run it.",
]
CUT_ON = 7  # cut the link while Claude answers this prompt (0-based)
phase = "setup"
log_f = (OUT / "progress.log").open("a", buffering=1)
stats_f = (OUT / "stats.jsonl").open("a", buffering=1)
stop = threading.Event()
t_start = time.time()
events = []
results = {}


def log(msg):
    line = f"{time.strftime('%H:%M:%S')} [{phase}] {msg}"
    print(line, flush=True)
    log_f.write(line + "\n")


def mini(cmd, timeout=30):
    r = subprocess.run(["ssh", "-i", str(KEY), "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8",
                        "-o", f"UserKnownHostsFile={ROOT}/build/ipad/known_hosts_mini", "-o", "LogLevel=ERROR", f"{USER}@{MINI}", cmd],
                       capture_output=True, text=True, timeout=timeout)
    return r.stdout


class Control:
    """The control port over USB. A USB drop must not end a Wi-Fi test: it reconnects and repeats the command."""
    def __init__(self):
        self.lock = threading.Lock()
        self.connect()

    def connect(self):
        self.s = socket.create_connection(("127.0.0.1", 5024), timeout=60)
        self.f = self.s.makefile("rwb")

    def __call__(self, line):
        with self.lock:
            for attempt in range(40):  # 40 x 3 s: longer than any USB re-enumeration seen
                try:
                    self.f.write(line.encode() + b"\n")
                    self.f.flush()
                    out = []
                    while True:
                        l = self.f.readline()
                        if not l:
                            raise OSError("control channel closed")
                        if l.startswith(b"\x01END"):
                            return b"".join(out).decode("utf-8", "replace")
                        out.append(l)
                except OSError as e:
                    events.append(f"control channel lost at {time.time() - t_start:.0f}s: {e}")
                    log(f"control channel lost ({e}); retry {attempt + 1}")
                    time.sleep(3)
                    try:
                        self.connect()
                    except OSError:
                        pass
            raise RuntimeError("control channel did not come back in 2 minutes")


def shot(name):
    t = OUT / f"{name}.tiff"
    subprocess.run(["idevicescreenshot", str(t)], capture_output=True)
    subprocess.run(["sips", "-s", "format", "png", str(t), "--out", str(OUT / f"{name}.png")], capture_output=True)
    t.unlink(missing_ok=True)


def monitor(ctl):
    n = 0
    while not stop.wait(10):
        try:
            d = json.loads(ctl("stats"))
            d["t"] = round(time.time() - t_start)
            d["phase"] = phase
            stats_f.write(json.dumps(d) + "\n")
            n += 1
            if n % 6 == 0:
                shot(f"auto_{n // 6:03d}")
                log(f"cpu {d['cpu_pct']}% rss {d['rss_mb']}MB free {d['free_mb']}MB echo p95 {d['echo_p95']}ms "
                    f"draw p95 {d['draw_p95']}ms stall max {d['stall_max']}ms battery {d['battery']}")
        except Exception as e:
            log(f"monitor error: {e}")
            events.append(f"monitor error {e}")
            return


def typed(ctl, text, delay=0.04):
    for ch in text:
        r = ctl(f"type {ch}" if ch != " " else "type  ")
        time.sleep(delay)


def wait_idle(ctl, timeout, on_tick=None):
    """Until Claude is idle: no 'esc to interrupt' for 8 s. Answers permission menus with number keys."""
    end, quiet_since, answered = time.time() + timeout, None, 0
    while time.time() < end:
        s = ctl("dump")
        if on_tick:
            on_tick(s)
        if re.search(r"Do you want|Would you like to proceed", s) and re.search(r"1\. Yes", s):
            choice = "2" if re.search(r"2\. Yes.*(don.t ask|allow)", s) else "1"
            shot(f"permission_{phase}_{answered}")
            ctl(f"type {choice}")
            answered += 1
            log(f"answered permission menu with {choice}")
            time.sleep(1.5)
            quiet_since = None
            continue
        working = re.search(r"esc to interrupt|\u2026 \(", s)
        if working:
            quiet_since = None
        else:
            quiet_since = quiet_since or time.time()
            if time.time() - quiet_since > 8:
                return answered
        time.sleep(1)
    raise TimeoutError("Claude did not become idle; screen:\n" + "\n".join(l for l in s.splitlines() if l.strip())[-1500:])


def peer_is_ipad():
    out = mini(f"netstat -an -p tcp | grep -F '{MINI}.22' | grep -F '{IPAD}.' | grep ESTABLISHED")
    return out.strip()


def cut_link():
    """A real lost link: end the iPad's sshd process on the mini (only that one; tmux and Claude stay)."""
    out = mini(f"lsof -nP -iTCP -sTCP:ESTABLISHED 2>/dev/null | grep -F '{IPAD}:' | grep sshd | awk '{{print $2}}' | sort -u")
    pids = out.split()
    if not pids:
        log("cut: no iPad sshd process visible for this user")
        return False
    mini("kill " + " ".join(pids))
    log(f"cut link: killed sshd {pids}")
    return True


def main():
    global phase
    resume_at = int(os.environ.get("RESUME_AT_MSG", "0"))  # continue a running session from this message (1-based)
    key = KEY.read_bytes().hex()
    fp = mini("ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub").split()[1]
    if resume_at:
        ctl = Control()
        assert ctl("ping").strip() == "pong"
        threading.Thread(target=monitor, args=(ctl,), daemon=True).start()
        assert peer_is_ipad(), "the mini shows no SSH connection from the iPad"
        log(f"resumed at message {resume_at}; status {ctl('status').strip()}")
        run_messages(ctl, resume_at - 1)
        return finish(ctl)
    mini(f"PATH=\"$PATH:/opt/homebrew/bin\"; tmux -L padterm kill-server 2>/dev/null; mkdir -p ~/{WORK}")
    ctl = Control()
    assert ctl("ping").strip() == "pong"
    r = ctl(f"profile {USER} ~/{WORK} - {key} {MINI} 22").strip()
    assert r == "ok", r
    ctl("screen launch")
    time.sleep(1)
    shot("launch_screen")
    threading.Thread(target=monitor, args=(ctl,), daemon=True).start()

    phase = "connect"
    t0 = time.time()
    assert ctl("launch claude").strip() == "ok"
    while time.time() - t0 < 40:  # the alert appears after the SSH handshake
        if "hasalert=1" in ctl("alertstate"):
            break
        time.sleep(0.2)
    handshake = time.time() - t0
    shot("host_key_alert")
    assert ctl("alert trust").strip() == "ok", "no host-key alert"
    pin = ctl("pin").strip()
    assert pin == fp, f"pin {pin} != mini fingerprint {fp}"
    log(f"Wi-Fi TCP + SSH handshake to the alert: {handshake:.2f} s; pin matches the mini: {pin}")
    while "connected=1" not in ctl("status"):
        assert time.time() - t0 < 90, ctl("status")
        time.sleep(0.2)
    log(f"connected in {time.time() - t0:.2f} s")
    peer = peer_is_ipad()
    assert peer, "mini shows no SSH connection from the iPad address"
    log("SSH peer on the mini: " + " ".join(peer.split()[3:5]))

    phase = "startup"
    t0 = time.time()
    s = ""
    while time.time() - t0 < 120:
        s = ctl("dump")
        if "trust this folder" in s:
            shot("claude_trust")
            ctl(f"tapkey {DOWN}")
            time.sleep(0.8)
            ctl(f"tapkey {ENTER}")
            log("trust dialog: key bar down + enter")
            time.sleep(3)
        elif re.search(r"\u276f|>\s*$", s) and "trust" not in s and ("? for shortcuts" in s or "for shortcuts" in s or "Claude Code" in s):
            break
        time.sleep(0.5)
    log(f"Claude ready in {time.time() - t0:.1f} s")
    time.sleep(2)
    shot("claude_ready")
    mode = next((l.strip() for l in ctl("dump").splitlines() if "mode" in l.lower() and "on" in l.lower()), "(no mode line)")
    log("mode line: " + mode)
    assert "auto mode" in mode, f"Claude must start in auto mode: {mode}"

    phase = "echo_probe"  # a clean echo measure: one key, a quiet screen, 500 ms apart
    ctl("stats")
    for ch in "abcdefghijklmnopqrstuvwxyz0123":
        ctl(f"type {ch}")
        time.sleep(0.5)
    d = json.loads(ctl("stats"))
    results["echo_probe"] = {k: d[k] for k in ("echo_n", "echo_p50", "echo_p95", "echo_max")}
    log(f"key echo over Wi-Fi: {results['echo_probe']}")
    for _ in range(30):
        ctl("backspace")
        time.sleep(0.05)

    run_messages(ctl)
    return finish(ctl)


def run_messages(ctl, start=0):
    global phase
    for i, prompt in list(enumerate(PROMPTS))[start:]:
        phase = f"msg{i + 1}"
        log(f"typing: {prompt[:60]}")
        t0 = time.time()
        typed(ctl, prompt)
        t_typed = time.time() - t0
        shot(f"{phase}_typed")
        ctl(f"tapkey {ENTER}")
        t1 = time.time()
        cut_done = {"v": False}

        def tick(screen):
            if i == CUT_ON and not cut_done["v"] and time.time() - t1 > 6 and "esc to interrupt" in screen:
                cut_done["v"] = True
                shot("before_cut")
                events.append(f"cut at {time.time() - t_start:.0f}s: {cut_link()}")
        n = 0
        try:
            n = wait_idle(ctl, 600, tick)
        except TimeoutError as e:
            events.append(f"{phase} timeout")
            log(str(e)[:600])
            shot(f"{phase}_timeout")
        log(f"typed in {t_typed:.1f} s; reply took {time.time() - t1:.1f} s; {n} permission menus; status {ctl('status').strip()}")
        shot(f"{phase}_done")
        if i == CUT_ON:
            log("after cut: " + ctl("status").strip())
            assert peer_is_ipad(), "no iPad connection after the cut"
            ctl("wheel 12")  # finger scroll into tmux history, then back
            time.sleep(1.5)
            shot("scrolled_up")
            ctl("tapkey Esc")
            time.sleep(1)



def finish(ctl):
    global phase
    phase = "quiet"  # true idle: nothing changes on the screen for a minute
    ctl("stats")
    time.sleep(60)
    d = json.loads(ctl("stats"))
    results["idle"] = {k: d[k] for k in ("cpu_pct", "draw_n", "bytes", "stall_max")}
    log(f"idle for 60 s: {results['idle']}")

    phase = "end"
    time.sleep(3)
    shot("final")
    ls = mini(f"cd ~/{WORK} && ls -l && wc -l index.html test.js; PATH=\"$PATH:/opt/homebrew/bin\"; node test.js 2>&1 | tail -8")
    log("mini folder:\n" + ls)
    (OUT / "mini_result.txt").write_text(ls)
    subprocess.run(["scp", "-q", "-i", str(KEY), "-o", "IdentitiesOnly=yes", "-o", f"UserKnownHostsFile={ROOT}/build/ipad/known_hosts_mini",
                    f"{USER}@{MINI}:{WORK}/index.html", str(OUT / "index.html")])
    stop.set()
    time.sleep(1)
    rows = [json.loads(l) for l in (OUT / "stats.jsonl").read_text().splitlines()]
    active = [r for r in rows if r["wall_ms"] > 0]
    def agg(k, f=statistics.median):
        v = [r[k] for r in active if r.get(k) is not None]
        return round(f(v), 1) if v else None
    summary = {
        "label": LABEL, **results, "minutes": round((time.time() - t_start) / 60, 1), "samples": len(active), "events": events,
        "cpu_median": agg("cpu_pct"), "cpu_max": agg("cpu_pct", max), "cpu_idle_min": agg("cpu_pct", min),
        "rss_first": active[0]["rss_mb"] if active else None, "rss_last": active[-1]["rss_mb"] if active else None, "rss_max": agg("rss_mb", max),
        "free_min": agg("free_mb", min), "echo_p50_median": agg("echo_p50"), "echo_p95_max": agg("echo_p95", max), "echo_max": agg("echo_max", max),
        "draw_p50_median": agg("draw_p50"), "draw_p95_max": agg("draw_p95", max), "draw_max": agg("draw_max", max),
        "stall_max": agg("stall_max", max), "stall_p95_median": agg("stall_p95"), "bytes_total": sum(r["bytes"] for r in active),
        "feed_max": agg("feed_max", max), "connects": active[-1]["connects"] if active else None,
        "battery_first": active[0]["battery"] if active else None, "battery_last": active[-1]["battery"] if active else None,
    }
    (OUT / "summary.json").write_text(json.dumps(summary, indent=1))
    print(json.dumps(summary, indent=1))
    log("done")
    return 0



if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as e:
        log(f"FAILED: {type(e).__name__}: {e}")
        try:
            shot("failed")
        except Exception:
            pass
        stop.set()
        raise SystemExit(1)

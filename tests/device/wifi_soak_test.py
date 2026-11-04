#!/usr/bin/env python3
"""Soak over real Wi-Fi to your server without model calls: PadTerm Shell session + agent-shaped output, bursts, scrolling,
font changes, repeated lost links, and idle. usage: wifi_soak_test.py <label>"""
import json, pathlib, statistics, subprocess, sys, threading, time
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import wifi_claude_test as W

def window(ctl, name, secs=None, fn=None):
    W.phase = name
    ctl("stats")
    if fn: fn()
    if secs: time.sleep(secs)
    d = json.loads(ctl("stats"))
    d["phase"] = name
    W.results[name] = {k: d[k] for k in ("wall_ms", "cpu_pct", "rss_mb", "free_mb", "echo_n", "echo_p50", "echo_p95", "draw_n", "draw_p50", "draw_p95", "draw_max", "draw_total_ms", "stall_p95", "stall_max", "bytes", "feed_total_ms", "feed_max", "battery")}
    W.log(f"{name}: {W.results[name]}")

def wait_text(ctl, text, timeout):
    end = time.time() + timeout
    while time.time() < end:
        if text in ctl("dump"): return True
        time.sleep(0.5)
    raise TimeoutError(f"{text} not seen; screen: " + ctl("dump")[-500:])

def main():
    key = W.KEY.read_bytes().hex()
    fp = W.mini("ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub").split()[1]
    W.mini("mkdir -p ~/padterm-test; PATH=\"$PATH:/opt/homebrew/bin\"; tmux -L padterm kill-server 2>/dev/null; true")
    subprocess.run(["scp", "-q", "-i", str(W.KEY), "-o", "IdentitiesOnly=yes", "-o", f"UserKnownHostsFile={W.ROOT}/build/ipad/known_hosts_mini",
                    str(W.ROOT / "tests/device/workload_agent.py"), f"{W.USER}@{W.MINI}:padterm-test/workload_agent.py"], check=True)
    ctl = W.Control()
    assert ctl("ping").strip() == "pong"
    assert ctl(f"profile {W.USER} ~/padterm-test {fp} {key} {W.MINI} 22").strip() == "ok"
    ctl("screen launch"); time.sleep(1); W.shot("launch_screen")
    threading.Thread(target=W.monitor, args=(ctl,), daemon=True).start()
    W.phase = "connect"
    t0 = time.time()
    assert ctl("launch shell").strip() == "ok"
    while "connected=1" not in ctl("status"):
        assert time.time() - t0 < 60, ctl("status")
        time.sleep(0.1)
    W.results["connect_s"] = round(time.time() - t0, 2)
    assert W.peer_is_ipad(), "not the iPad's address on the mini"
    W.log(f"connected over Wi-Fi in {W.results['connect_s']} s; peer {W.peer_is_ipad().split()[4]}")
    wait_text(ctl, "%", 20)
    ctl("type clear\\n"); time.sleep(1)
    def probe():
        for ch in "abcdefghijklmnopqrstuvwxyz0123456789":
            ctl(f"type {ch}"); time.sleep(0.5)
    window(ctl, "echo_probe", fn=probe)
    ctl("ctrl u"); time.sleep(0.5)
    window(ctl, "idle_60s", 60)
    ctl("type python3 workload_agent.py 180\\n")
    window(ctl, "agent_load_180s", 182)
    wait_text(ctl, "WORKLOAD-DONE", 20); W.shot("after_load")
    def burst():
        ctl("type clear; seq 1 40000 | sed 's/$/ line of output from a build tool/'; echo BURST-$((1+1))\\n")
        wait_text(ctl, "BURST-2", 120)
    t0 = time.time(); window(ctl, "burst_1_7MB", fn=burst); W.results["burst_s"] = round(time.time() - t0, 1); W.log(f"burst took {W.results['burst_s']} s")
    def scroll():
        for n in range(20):
            ctl("wheel 5"); time.sleep(0.25)
        W.shot("scrolled")
        ctl("tapkey Esc"); time.sleep(0.5)  # the key-bar Esc alone must leave tmux scrollback
        mode = W.mini("PATH=\"$PATH:/opt/homebrew/bin\"; tmux -L padterm display -p -t '=shell:' '#{pane_in_mode}'").strip()
        assert mode == "0", f"still in tmux scrollback after Esc: pane_in_mode={mode}"
    window(ctl, "scroll_tmux_history", fn=scroll)
    def fonts():
        for f in ("font +", "font +", "font -", "font -", "font -", "font +", "theme", "theme"):
            ctl(f); time.sleep(0.8)
    window(ctl, "font_theme_changes", fn=fonts)
    cuts = []
    W.phase = "link_cuts"
    for n in range(5):
        ctl("type clear\\n"); time.sleep(1)
        before = time.time()
        assert W.cut_link(), "no iPad connection to cut"
        while "connected=1" in ctl("status") and time.time() - before < 15: time.sleep(0.05)
        while "connected=1" not in ctl("status"):
            assert time.time() - before < 60, ctl("status")
            time.sleep(0.1)
        cuts.append(round(time.time() - before, 2))
        ctl(f"type echo BACK-$(({n}+100))\\n")
        wait_text(ctl, f"BACK-{n + 100}", 15)
        time.sleep(3)
    W.results["reconnect_s"] = cuts
    W.log(f"reconnects: {cuts}")
    window(ctl, "idle_after", 30)
    W.stop.set(); time.sleep(1)
    rows = [json.loads(l) for l in (W.OUT / "stats.jsonl").read_text().splitlines()]
    W.results["rss_series_mb"] = [rows[0]["rss_mb"], rows[len(rows) // 2]["rss_mb"], rows[-1]["rss_mb"]]
    W.results["connects"] = rows[-1]["connects"]
    W.results["events"] = W.events
    (W.OUT / "summary.json").write_text(json.dumps(W.results, indent=1))
    print(json.dumps(W.results, indent=1))
    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as e:
        W.log(f"FAILED: {type(e).__name__}: {e}")
        W.shot("failed"); W.stop.set()
        raise SystemExit(1)

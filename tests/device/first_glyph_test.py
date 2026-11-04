#!/usr/bin/env python3
"""Measure the draw time of the first character that needs a system fallback font, in a new app process.

usage: first_glyph_test.py <char> [<char> ...]   Needs the relay test setup of run_device_tests.sh.
Prints one JSON line per character: draw_max and stall_max in ms for the window that shows the character.
"""
import json
import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import device_test as d  # noqa: E402


def main():
    fp = (d.SSHD / "expected_fingerprint").read_text().strip()
    key = (d.SSHD / "client_ed25519").read_bytes().hex()
    d.tmux("kill-server")
    d.Bridge().start()
    ctl = d.Control()
    assert ctl("ping").strip() == "pong"
    assert ctl(f"profile {d.getpass.getuser()} ~ {fp} {key}").strip() == "ok"
    ctl("open shell")
    d.wait(ctl, lambda s: "%" in s or "$" in s, 30, "shell prompt")
    time.sleep(2)
    script = d.ROOT / "build/e2e-work/glyph.sh"
    # ASCII first: it is the control for the character rows.
    for i, ch in enumerate(["plain"] + sys.argv[1:]):
        script.write_text(f"clear\nprintf '%s\\n' '{ch} {ch} {ch}'\necho GLYPH-$(({i}+1000))\n")
        ctl("stats")
        t0 = time.time()
        ctl(f"type sh {script}\\n")
        d.wait(ctl, lambda s: f"GLYPH-{i + 1000}" in s, 30, ch)
        time.sleep(1.5)
        s = json.loads(ctl("stats"))
        print(json.dumps({"char": ch, "seen_s": round(time.time() - t0 - 1.5, 2), "draw_max": s["draw_max"],
                          "stall_max": s["stall_max"], "rss_mb": s["rss_mb"]}, ensure_ascii=False), flush=True)
    d.shot("first_glyph")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Runs on the server: output shaped like an agent TUI (spinner at 12 Hz, coloured lines, box lines, periodic full
repaints), then bursts. usage: workload_agent.py <seconds>. Rates are from watching Claude Code on the iPad: its spinner
redraws about 10 times a second; replies arrive as bursts of lines. Light on CPU: the server may run other work."""
import random, sys, time
secs = float(sys.argv[1])
w = sys.stdout.write
SP = "✶✳✢✻"
LINE = "The quick brown fox jumps over the lazy dog 0123456789 abcdefghijklmnopqrstuvwxyz"
end = time.time() + secs
i = 0
while time.time() < end:
    i += 1
    w(f"\r\033[38;2;215;119;87m{SP[i % 4]}\033[0m Thinking… ({i // 12}s · esc to interrupt)\033[K")
    if i % 3 == 0:
        c = random.choice((32, 31, 36, 33))
        w(f"\r\033[K\033[{c}m+ {i:6d}\033[0m \033[2m│\033[0m {LINE[:random.randint(30, 80)]}\n")
    if i % 60 == 0:  # a full repaint, as a TUI does after a resize or a dialog
        w("\033[2J\033[H\033[1m╭" + "─" * 60 + "╮\033[0m\n")
        for n in range(30):
            w(f"│ \033[38;5;{16 + n * 6}m{LINE[:58]}\033[0m │\n")
        w("╰" + "─" * 60 + "╯\n")
    sys.stdout.flush()
    time.sleep(1 / 12)
print("\nWORKLOAD-DONE")

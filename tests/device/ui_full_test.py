#!/usr/bin/env python3
"""The whole UI on the real iPad, in light and dark, with repeated actions. The Mac drives the controls by what they show,
through the same action paths as a finger, with no hit test: a real finger still has to try the app.

Each step ends with a layout audit: no control may leave the area its ancestors show (the owner saw one grow out of the
form after many taps). Screens go to tests/artifacts/ui/<mode>/. usage: ui_full_test.py [light|dark ...]"""
import json
import os
import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import device_test as d  # noqa: E402

MODES = sys.argv[1:] or ["light", "dark"]
TINY_KEY = None


def audit(ctl, where):
    bad = ctl("audit").strip()
    assert not bad, f"{where}: layout audit:\n{bad[:1500]}"


def ui(ctl):
    return [l.split("|") for l in ctl("ui").splitlines() if l.count("|") == 2]


def box(rows, kind, text):
    """The frame of a control: x y w h."""
    for r in rows:
        if r[0] == kind and text in r[1]:
            return [int(x) for x in r[2].split()]
    raise AssertionError(f"no {kind} '{text}' in {rows}")


def ok(reply, what=""):
    assert reply.strip() == "ok", f"{what}: {reply.strip()}"


def clear_alerts(ctl):
    """A failed step must not leave its alert over the next step's screens."""
    while ctl("alertshown").strip():
        ctl("alertok")
        time.sleep(0.3)


def main():
    fp = (d.SSHD / "expected_fingerprint").read_text().strip()
    key_bytes = (d.SSHD / "client_ed25519").read_bytes()
    key = key_bytes.hex()
    user = d.getpass.getuser()
    work = d.ROOT / "build/e2e-work/dev-a"
    work.mkdir(parents=True, exist_ok=True)
    d.tmux("kill-server")
    d.Bridge().start()
    ctl = d.Control()
    assert ctl("ping").strip() == "pong"
    root = d.ROOT / os.environ.get("PT_UI_OUT", "tests/artifacts/ui")

    def shot(name):
        """The app's own windows: a SpringBoard alert over the device screen does not hide them."""
        (d.ART / f"{name}.png").write_bytes(bytes.fromhex(ctl("snapshot").strip()))

    d.shot = shot
    ok(ctl("resetprofiles"), "reset")

    for mode in MODES:
        d.ART = root / mode
        d.ART.mkdir(parents=True, exist_ok=True)
        ok(ctl(f"appearance {mode}"), "appearance")
        time.sleep(1)

        def step(name, ids="UI"):
            clear_alerts(ctl)
            return d.test(f"{mode}_{name}", ids)

        @step("empty_state")
        def _():
            ctl("screen empty"); time.sleep(1)
            d.shot("empty")
            audit(ctl, "empty")

        @step("form_key_mode_many_taps_keeps_its_size", "AC-PROFILE-1")
        def _():
            ctl("screen new"); time.sleep(1)
            d.shot("form_new")
            audit(ctl, "new form")
            rows = ui(ctl)
            fields = [r for r in rows if r[0] == "field"]
            assert len(fields) == 5, fields
            assert [r[1] for r in fields][2:] == ["22", "", "~"] or fields[2][1] == "22", fields  # the defaults show
            for r in fields:
                assert int(r[2].split()[2]) > 200, f"a field is too narrow to type in: {r}"
            first = box(ui(ctl), "segments", "Import")
            for i in range(20):
                ok(ctl("tap Import file"), f"import {i}")
                time.sleep(0.05)
                ok(ctl("tap Paste"), f"paste {i}")
                time.sleep(0.05)
            time.sleep(0.5)
            now = box(ui(ctl), "segments", "Import")
            assert now == first, f"segments grew: {first} -> {now}"
            audit(ctl, "after 40 mode changes")
            d.shot("form_after_40_taps")
            return f"segments {now} after 40 changes"

        @step("form_import_row_many_taps", "EF-CONNECT-3")
        def _():
            first = box(ui(ctl), "segments", "Import")
            ok(ctl("tap Import file"))
            time.sleep(0.3)
            for i in range(8):
                ok(ctl("tap Import <name>"), f"row {i}")
                time.sleep(0.3)
                assert "No key file" in ctl("alertshown"), ctl("alertshown")
                if i == 0:
                    d.shot("form_import_alert")
                ok(ctl("alertok"))
                time.sleep(0.2)
            assert box(ui(ctl), "segments", "Import") == first
            audit(ctl, "after import taps")
            ok(ctl("tap Paste"))

        @step("form_key_box_many_edits_and_keyboard", "AC-PROFILE-1")
        def _():
            time.sleep(0.3)
            before = box(ui(ctl), "textview", "")
            for i in range(6):
                ok(ctl(f"settext {'x' * 30}\\n{'y' * 200}"), "settext")
                time.sleep(0.5)
                audit(ctl, f"key box, keyboard up, round {i}")
                ctl("endedit")
                time.sleep(0.5)
                ok(ctl("tap Import file")); ok(ctl("tap Paste"))
                time.sleep(0.2)
            time.sleep(0.6)  # the row change animates; its old cell leaves after the reload
            d.shot("form_key_text")
            after = box(ui(ctl), "textview", "")
            assert after[2:] == before[2:], f"key box changed: {before} -> {after}"
            audit(ctl, "after key edits")
            ok(ctl("settext "))
            ctl("endedit")

        @step("form_rotates_with_keyboard", "UI")
        def _():
            ok(ctl("settext abc"))
            for o in ("landscape", "portrait", "landscape"):
                ok(ctl(f"rotate {o}"))
                time.sleep(1.2)
                audit(ctl, f"form {o}")
            d.shot("form_landscape")
            ctl("endedit")
            ok(ctl("rotate portrait"))
            time.sleep(1)
            ok(ctl("settext "))
            ctl("endedit")

        @step("form_save_refuses_bad_input", "AC-PROFILE-1 EF-CONNECT-3")
        def _():
            ctl("endedit")
            time.sleep(0.5)
            ok(ctl("scrolltop"))
            time.sleep(0.3)
            ok(ctl("tap Save"))
            time.sleep(0.4)
            shown = ctl("alertshown")
            assert shown, "no message for an empty form"
            ok(ctl("alertok"))
            ok(ctl("setfield 0 ui-test")); ok(ctl("setfield 1 127.0.0.1")); ok(ctl("setfield 2 notaport"))
            ok(ctl("setfield 3 me")); ok(ctl("setfield 4 ~"))
            ok(ctl("tap Save"))
            time.sleep(0.4)
            assert ctl("alertshown"), "no message for a bad port"
            ok(ctl("alertok"))
            ok(ctl("setfield 2 22"))
            ok(ctl("settext not a key"))
            ctl("endedit")
            ok(ctl("tap Save"))
            time.sleep(0.4)
            assert "key" in ctl("alertshown").lower(), ctl("alertshown")
            ok(ctl("alertok"))
            ok(ctl("tap Cancel"))
            time.sleep(0.6)
            return shown.strip()

        @step("server_page_portrait_landscape", "AC-LAUNCH-1 AC-SESSION-2")
        def _():
            ok(ctl(f"profile {user} {work} {fp} {key}"), "profile")
            ctl("screen launch"); time.sleep(4)
            d.shot("home")
            audit(ctl, "home")
            ok(ctl("rotate landscape")); time.sleep(1.5)
            d.shot("home_landscape")
            audit(ctl, "home landscape")
            ok(ctl("rotate portrait")); time.sleep(1.5)

        @step("edit_form_of_a_saved_server", "AC-PROFILE-1")
        def _():
            ctl("screen edit"); time.sleep(1)
            d.shot("form_edit")
            audit(ctl, "edit form")
            ok(ctl("tap Forget"))
            time.sleep(0.5)
            audit(ctl, "after forget")
            ok(ctl("tap Cancel"))
            time.sleep(0.6)

        @step("terminal_keys_and_bar", "AC-INPUT-1 AC-INPUT-2")
        def _():
            ok(ctl("launch shell"))
            d.wait(ctl, lambda s: "%" in s or "$" in s, 30, "prompt")
            time.sleep(1)
            d.shot("terminal_shell")
            raw = d.ART / "device_terminal.tiff"  # the real screen: the keyboard is not drawn by the app's windows alone
            d.subprocess.run(["idevicescreenshot", str(raw)], capture_output=True)
            d.subprocess.run(["sips", "-s", "format", "png", str(raw), "--out", str(d.ART / "device_terminal.png")], capture_output=True)
            raw.unlink(missing_ok=True)
            audit(ctl, "terminal")
            ok(ctl("type echo UI-$((40+2))\\n"))
            d.wait(ctl, lambda s: "UI-42" in s, 15, "echo")
            for k in ["Esc", "Tab", "↑", "↓", "←", "→", "PgUp", "PgDn"]:
                ok(ctl(f"tapkey {k}"), k)
                time.sleep(0.1)
            ok(ctl("tapkey Ctrl"))
            time.sleep(0.2)
            d.shot("terminal_ctrl_armed")
            ok(ctl("tapkey ^C"))
            time.sleep(0.3)
            ok(ctl("rotate landscape")); time.sleep(1.5)
            d.shot("terminal_landscape")
            audit(ctl, "terminal landscape")
            ok(ctl("rotate portrait")); time.sleep(1.5)
            audit(ctl, "terminal portrait again")

        @step("settings_all_controls_many_taps", "AC-SCREEN-3")
        def _():
            ok(ctl("settings")); time.sleep(1)
            d.shot("settings")
            audit(ctl, "settings")
            for _i in range(20):
                ctl("font +")
            time.sleep(0.5)
            d.shot("font_largest")
            audit(ctl, "largest font")
            for _i in range(30):
                ctl("font -")
            time.sleep(0.5)
            d.shot("font_smallest")
            audit(ctl, "smallest font")
            for _i in range(7):
                ctl("font +")
            for t in ("light", "amber", "green", "classic"):
                ctl(f"theme {t}"); time.sleep(0.4)
                d.shot(f"term_theme_{t}")
                audit(ctl, f"theme {t}")
            ok(ctl("settings")); time.sleep(0.5)

        @step("sessions_popover_rows", "AC-SESSION-6")
        def _():
            ok(ctl("sessionspopover")); time.sleep(4)
            d.shot("sessions_popover")
            audit(ctl, "sessions popover")
            ok(ctl("sessionspopover")); time.sleep(0.5)
            ctl("back"); time.sleep(0.6)

        @step("open_close_terminal_20_times", "UI")
        def _():
            rss0 = json.loads(ctl("stats"))["rss_mb"]
            for i in range(20):
                ok(ctl("launch shell"), f"open {i}")
                time.sleep(0.8)
                ctl("back")
                time.sleep(0.5)
            assert ctl("ping").strip() == "pong"
            time.sleep(1)
            rss1 = json.loads(ctl("stats"))["rss_mb"]
            audit(ctl, "after 20 opens")
            assert rss1 - rss0 < 15, f"memory {rss0} -> {rss1} MB"  # a terminal's buffers are near 5 MB: a leak of each shows
            return f"memory {rss0} -> {rss1} MB"

        @step("appearance_change_keeps_the_terminal_connected", "UI")
        def _():
            ok(ctl("launch shell"))
            d.wait(ctl, lambda s: "%" in s or "$" in s, 30, "prompt")
            ok(ctl("type export PTKEEP=$((1+1))\\n")); time.sleep(0.5)
            other = "dark" if mode == "light" else "light"
            ok(ctl(f"appearance {other}")); time.sleep(1.5)
            d.shot("switched_live")
            audit(ctl, "after a live change")
            assert "connected=1" in ctl("status"), ctl("status")
            ok(ctl("type echo KEEP-$PTKEEP\\n"))
            d.wait(ctl, lambda s: "KEEP-2" in s, 15, "same shell after the change")
            ok(ctl(f"appearance {mode}")); time.sleep(1)
            ctl("back"); time.sleep(0.6)

    d.tmux("kill-server")
    ok(ctl("resetprofiles"), "reset")
    (root / "ui_results.json").write_text(json.dumps(d.results, indent=1, ensure_ascii=False))
    failed = [r["name"] for r in d.results if r["status"] == "failed"]
    print(f"ui: {len(d.results)} run, {len(failed)} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())

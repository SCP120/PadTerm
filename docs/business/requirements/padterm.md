---
id: BREQ-PADTERM
name: "PadTerm: Claude Code and Codex from an iPad mini 1 (iOS 6)"
version: "1.0"
date: 2026-11-03
status: drafted
---

# BREQ-PADTERM

## Problem

A jailbroken iPad mini 1 (A5, armv7, 512 MB RAM, iOS 6) cannot run Claude Code or Codex CLI. No terminal app for
iOS 6 has the colours, characters and keys that these agents need, and the iOS 6 trust store and Safari are too old
for web terminals. [ClaudeBerry](https://github.com/0xProbabillity/claudeberry) solves the same problem for
BlackBerry OS 7 with an SSH client that attaches to `tmux` on the user's own server.

## Goal

A native iOS 6 app that opens an SSH session to the user's own server (Linux or macOS), attaches to a `tmux`
session, and shows the real `claude` or `codex` terminal UI in a form that is comfortable on a 7.9" touch screen.

## Stakeholders

| Who | Need |
|-----|------|
| Owner of the iPad (only user) | Drive Claude Code and Codex on own servers; nothing in a third-party cloud |
| Server (Linux or macOS) | Stock OpenSSH ≥ 6.5 and `tmux`; nothing else installed by the app |

## Scope

| In | Out (this version) |
|----|--------------------|
| SSH with Ed25519 key, host key pin | Password auth, SFTP, port forwards, WebSocket bridge, mosh |
| Claude / Codex / Shell launcher over `tmux` | Voice input (user decision 2026-11-03) |
| xterm-256color terminal, true colour, UTF-8 | Native chat UI (architecture B, rejected 2026-11-03) |
| Key bar for agent keys, touch as mouse | App-side scrollback (tmux has it, mouse wheel scrolls) |
| Profiles, reconnect after a lost link | Several terminals on screen at the same time |
| Many sessions per server, continued from a list (UC-SESSION) | Sessions started outside this app in the list |
| Light and dark appearance, changed live | Following a system dark mode |

## Use cases

One terminal connection is active at a time. A change of session closes it; `tmux` keeps the old agent alive. While a session list is on screen, the app holds one more connection to read the list.

### UC-CONNECT — Connect to a server

| ID | Statement |
|----|-----------|
| AC-CONNECT-1 | The app connects with an Ed25519 private key (OpenSSH format, no passphrase) to OpenSSH ≥ 6.5 with `curve25519-sha256` and `ssh-ed25519`. |
| AC-CONNECT-2 | The app asks for a PTY with `TERM=xterm-256color` and the screen size in cells. |
| BR-CONNECT-1 | The server host key is pinned as `SHA256:<base64>` (OpenSSH fingerprint format). On the first connection the app shows the fingerprint and the user accepts it. |
| BR-CONNECT-2 | A host key that is different from the pin stops the connection before authentication. |
| BR-CONNECT-3 | The app never shows or logs the private key. |
| EF-CONNECT-1 | A key that the server does not accept gives "authentication failed". |
| EF-CONNECT-2 | A host that does not answer gives "connection timed out" after the connect timeout. |
| EF-CONNECT-3 | A key file that is not a valid OpenSSH Ed25519 key gives "invalid key". |

### UC-LAUNCH — Start or attach an agent session

| ID | Statement |
|----|-----------|
| AC-LAUNCH-1 | The server page has **Claude**, **Codex** and **Shell**. Claude and Codex start a new session (UC-SESSION). Shell attaches to the one `tmux` session `shell`. All are on the private socket `tmux -L padterm`. |
| AC-LAUNCH-2 | If the session does not exist, the app creates it in the profile directory and starts the agent from an interactive login shell in its auto mode (`claude --permission-mode auto`; `codex --approve-for-me`). Shell has no agent. For an agent's exit, see EF-SESSION-4. |
| AC-LAUNCH-3 | If the tmux session exists, the app attaches only. The agent does not restart. A row of the session list does the same (AC-SESSION-5). |
| BR-LAUNCH-1 | The private socket keeps the app's `tmux` options away from the user's own `tmux`. Options: `status off`, `escape-time 10`, `mouse on`, `mode-keys emacs` (Esc leaves scrollback), `default-terminal` = `tmux-256color` (fallback `xterm-256color`, never `screen-*`, because tmux then shows italics as reverse), `COLORTERM=truecolor`, and `terminal-overrides` `Tc` for 24-bit colour on older tmux. |
| BR-LAUNCH-2 | The directory goes to the server shell single-quoted. A leading `~/` becomes `"$HOME"/`. |
| BR-LAUNCH-3 | The remote command adds `/opt/homebrew/bin`, `/usr/local/bin` and `$HOME/.local/bin` to `PATH`, because a non-interactive SSH command on macOS does not read the user's shell profile. |
| EF-LAUNCH-1 | If `tmux` is not on the server, the app shows "tmux not found" and opens a login shell. |
| EF-LAUNCH-2 | A directory with a control character (newline, NUL, etc.) is refused before connection. |

### UC-SESSION — Continue a session

The user starts many Claude and Codex sessions on one server and returns to any of them later, also after the agent stopped or the server restarted.

| ID | Rule |
|----|------|
| AC-SESSION-1 | The Claude or Codex row starts a **new** session. The server records each session that this app starts. |
| AC-SESSION-2 | The server page lists the recorded sessions, newest activity first, with agent, name, directory, time and a running mark. |
| AC-SESSION-3 | The row shows the name that the agent gave: Claude `custom-title`, else `ai-title`; Codex `thread_name`. A session with no name yet shows "New session". |
| AC-SESSION-4 | A changed name shows without user action: in the list within one refresh (15 s), and in the terminal bar when the agent changes its terminal title. |
| AC-SESSION-5 | A tap continues the session: it attaches if tmux still runs it, else it starts the agent with its resume command in the session's directory. |
| AC-SESSION-6 | While a terminal is open, a Sessions button lists the same rows; a tap changes to that session. |
| AC-SESSION-7 | Swipe and Delete removes the row and ends its tmux session. The agent's own transcript stays on the server. |
| BR-SESSION-1 | The list comes from the server (`~/.padterm`), so a new install of the app still shows the sessions. The app does not store titles. |
| BR-SESSION-2 | The list refresh must stay light on a server that runs other work: an unchanged session starts no `grep`. A `find` runs only for a session with no transcript link: once per read while tmux runs it, and once after it stops. |
| BR-SESSION-3 | Titles are data from the server. The app only shows them. Session keys that are not UUIDs are dropped. |
| EF-SESSION-1 | Server not reachable, or host key not pinned yet: the rows that start a session still work, and the list shows the reason in its footer. |
| EF-SESSION-2 | A Codex session is linked to its file while tmux runs it, by time and directory. Another Codex started in that directory while this session has not sent a message can take the link. A transcript of a removed session is never linked again. A stopped record that was searched takes no later rollout. |
| EF-SESSION-3 | The directory does not exist: no agent starts anywhere else. The terminal shows the reason and a shell. |
| EF-SESSION-4 | A clean exit of the agent ends the tmux session, and the row can resume it. A failed start keeps a shell with the error on screen. |

### UC-SCREEN — Show the terminal

| ID | Statement |
|----|-----------|
| AC-SCREEN-1 | 16, 256 (xterm values) and 24-bit colours; bold, italic, underline, reverse, dim. Server output never hangs the app or writes outside the screen (for example `CSI b` repeat with no previous character). |
| AC-SCREEN-2 | UTF-8 text is correct also when one character arrives in two packets. |
| AC-SCREEN-3 | Wide (East Asian) characters use two cells. |
| AC-SCREEN-4 | The Claude Code and Codex characters show: from DejaVu Sans Mono, or drawn as shapes for `⎿ ⏵ ⏺ ⎯ ⏸ ⏹ ⧉`, which the font does not have. |
| AC-SCREEN-5 | Box lines (U+2500–U+257F subset) and blocks (U+2580–U+259F) are drawn as shapes, so lines connect from cell to cell. |
| AC-SCREEN-6 | The terminal answers device queries (DA, DSR cursor position) to the server. |
| AC-SCREEN-7 | A rotation or a font-size change sends the new size to the server (window-change). |

### UC-INPUT — Send keys

| ID | Statement |
|----|-----------|
| AC-INPUT-1 | Key bar: Esc, Tab, Shift+Tab, Ctrl (one-shot modifier), ↑ ↓ ← →, Enter, PgUp, PgDn, Ctrl+C. |
| AC-INPUT-2 | Arrow keys follow the cursor-key mode of the program (`ESC [ A` or `ESC O A`). |
| AC-INPUT-3 | Text from the keyboard goes as UTF-8. |
| AC-INPUT-4 | Paste uses bracketed paste when the program turns it on. Line ends (LF, CRLF) go as one CR. ESC characters in pasted text are dropped, so pasted text cannot end the bracketed paste and act as keys. |
| AC-INPUT-5 | When the program turns on mouse mode, a tap is a mouse click and a vertical swipe is the mouse wheel. |

### UC-RECONNECT — Keep the session after a lost link

| ID | Statement |
|----|-----------|
| AC-RECONNECT-1 | SSH keep-alive every 30 s (the value ClaudeBerry uses on mobile links). |
| AC-RECONNECT-2 | After a lost link the app connects again (delay 1 s, doubled to a maximum of 30 s), attaches the same session, and the screen content comes back. |
| BR-RECONNECT-1 | A disconnect by the user, or a clean end of the session on the server (`exit`, tmux detach), does not start a reconnect. A lost link, a timeout or a refused TCP connection does. |

### UC-PROFILE — Keep profiles

| ID | Statement |
|----|-----------|
| AC-PROFILE-1 | Add, change and delete a profile: name, host, port, user, directory, private key, pinned host key. |
| AC-PROFILE-2 | The app imports a key from paste, or from `<name>.key` in its Documents folder (iTunes File Sharing; no root needed). After the import the app deletes that file. |
| BR-PROFILE-1 | Profiles are in the app Library folder with file mode 0600. They also use `NSFileProtectionComplete` when the device allows it; a device that refuses protection classes (seen on a jailbroken iPad mini, iOS 6.1.3) keeps mode 0600 only, and the app logs that. |

## Non-functional

| ID | Requirement |
|----|-------------|
| NFR-1 | iOS 6.0 to 12 on iPad, all orientations; iOS 13 and later are out (owner, 2026-11-04). The jailbreak `.deb` is signed with `ldid` and refuses iOS 13; the `.ipa` is signed by a sideload tool. |
| NFR-2 | The binary uses no API newer than iOS 6.0 (compile check `-Werror=unguarded-availability`). |
| NFR-3 | The binary has `LC_VERSION_MIN_IPHONEOS 6.0`, no `LC_BUILD_VERSION`, no chained fixups, no thread-local variables, and only ARM functions (this linker cannot write Thumb code pointers). |
| NFR-4 | Core, renderer and E2E tests run on macOS against a local `sshd`, with the real `claude` and `codex`. |
| NFR-5 | The app runs on the real iPad mini 1 (iOS 6.1.3): `tests/device/run_device_tests.sh`. A release package has no test code. |
| NFR-6 | The same sources run on modern UIKit: the app launches when linked with the newest SDK (scene lifecycle), and `tests/modern/run_bench.sh` passes in light and dark. A run on a real modern iPad is still open. |
| NFR-7 | A release carries no key, session record, test capture, local path or third-party art: `scripts/check_release.py`. |

## Priority (MoSCoW)

| Must | Should | Could |
|------|--------|-------|
| UC-CONNECT, UC-LAUNCH, UC-SCREEN, UC-INPUT | UC-RECONNECT, UC-PROFILE | Themes beyond dark + light |

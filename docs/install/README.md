# Install guide

PadTerm is a terminal client. Claude Code and Codex run on **your own server**, and the iPad shows them over SSH. The app has no account, no relay and no telemetry. Each agent logs in on your server with your own account.

**What has been tested**

| Part | State |
|------|-------|
| iPad mini 1, iOS 6.1.3, jailbroken | ✅ Ran on the real device: UI, sessions, a real Claude session over Wi-Fi |
| Modern UIKit (iOS 15 API level) on a Mac test bench | ✅ Full UI test passes. It is not an iPad: no touch, no on-screen keyboard |
| A real iPad on iOS 7 or later | ⚠️ **Experimental: never run.** If you try it, please send a [device report](../../../../issues/new?template=device-report.yml) |
| Sideload tools below | ❌ Not run by us. Follow the tool's own page if it differs from this guide |

## 1. Pick your route

Open Settings, General, About on the iPad and read the version.

| Your iPad | Route | File |
|-----------|-------|------|
| iOS 15 to 26, not jailbroken | [Sideload](#3-sideload-no-jailbreak) | `.ipa` |
| iOS 9 to 14, not jailbroken | [Sideload](#3-sideload-no-jailbreak) (older tools may be needed) | `.ipa` |
| iOS 14 to 16.6.1, 16.7 RC or 17.0, on a supported device | [TrollStore](#4-trollstore): permanent, no 7-day limit | `.ipa` |
| iOS 15 or later, rootless jailbreak | [Jailbreak](#5-jailbroken-ipad) | `iphoneos-arm64.deb` |
| iOS 6 to about 14, rootful jailbreak | [Jailbreak](#5-jailbroken-ipad) | `iphoneos-arm.deb` |
| iOS 6, not jailbroken | **No known route.** Update the iPad (iPad 2, 3, mini 1 stop at 9.3.5, iPad 4 at 10.3.4) and sideload, or jailbreak it | |

The `.ipa` holds 32-bit and 64-bit code. iOS 11 and later use only the 64-bit part. The 64-bit part needs iOS 10 or later: update a 64-bit iPad that is still on iOS 7 to 9. iPhones are not supported: the layout is for iPad only.

## 2. Prepare the server (Linux or macOS)

Do this first on every route.

```sh
# Linux (Debian/Ubuntu)               # macOS
sudo apt install tmux openssh-server  brew install tmux   # and turn on Remote Login
```

Install the agents as the user the iPad logs in as, then log in from a computer:

```sh
curl -fsSL https://claude.ai/install.sh | bash   # then run: claude
npm install -g @openai/codex                     # then run: codex login
```

Make a key for the iPad, on your computer:

```sh
ssh-keygen -t ed25519 -N "" -C ipad -f ~/.ssh/id_ed25519_ipad
ssh-copy-id -i ~/.ssh/id_ed25519_ipad.pub you@your-server
ssh you@your-server ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub   # note the fingerprint
```

Use this key for the iPad only. Then you can remove its line from `~/.ssh/authorized_keys` if you lose the iPad.

**macOS server:** macOS keeps the login keychain from SSH sessions, so log Claude in once from an SSH session: `claude auth login`.

## 3. Sideload (no jailbreak)

Apple runs an app only if it has a signature from Apple. A sideload tool signs the `.ipa` with your Apple Account.

| Limit with a free Apple Account | Value |
|---------------------------------|-------|
| Signature life | 7 days. Sign again after that. Your servers stay |
| Sideloaded apps at one time | 3 |
| New App IDs | 10 per week |

A paid Apple Developer account removes the 7-day limit: signatures last one year.

### Choose a tool

| Tool | Needs | Refresh | Page |
|------|-------|---------|------|
| **SideStore** | A computer once, then the iPad alone with the LocalDevVPN app | On the iPad | https://docs.sidestore.io/docs/faq |
| **AltStore Classic** | AltServer on a Mac or PC on the same Wi-Fi. On Windows, iTunes and iCloud from Apple's site, not from the Microsoft Store | In the background when the computer is on | https://faq.altstore.io/ |
| **Sideloadly** | A Mac or PC and a cable | By hand, or its auto-refresh | https://sideloadly.io/ |

Download tools from these pages only. Sign in only on a computer that you own.

### Steps with Sideloadly

1. Connect the iPad with a data cable. On the iPad tap **Trust** and enter the passcode.
2. Open Sideloadly. Drag the PadTerm `.ipa` into it.
3. Enter your Apple Account email. Press **Start**, then enter the password when asked.
4. On the iPad open Settings, General, VPN & Device Management. Tap your email, then tap **Trust**.
5. iOS 16 or later: if the app asks for it, turn on Settings, Privacy & Security, Developer Mode. The iPad restarts.
6. Open PadTerm.

## 4. TrollStore

TrollStore installs an `.ipa` for good, with no 7-day limit. It works only on the iOS versions in the table in section 1: iOS 14.0 beta 2 to 16.6.1, 16.7 RC and 17.0. It does not work on 16.7.x or 17.0.1 and later. Install it with the steps at https://ios.cfw.guide/installing-trollstore/ , then open the `.ipa` with TrollStore.

## 5. Jailbroken iPad

This guide gives no jailbreak steps. For your device see https://ios.cfw.guide/ and https://theapplewiki.com/ . palera1n covers A8 to A11 devices on iOS 15 and later. Dopamine covers some A12 and later devices; see its page for the exact range.

| Jailbreak type | File | Installs to |
|----------------|------|-------------|
| Rootful | `dev.padterm.app_<version>_iphoneos-arm.deb` | `/Applications` |
| Rootless | `dev.padterm.app_<version>_iphoneos-arm64.deb` | `/var/jb/Applications` |

Install the file with your package manager (Sileo, Zebra, Cydia), or with `dpkg -i`. An iPad that accepts unsigned apps through the normal install service can also use `ideviceinstaller` over USB, as the iOS 6 test iPad does: `scripts/ipad_deploy.sh <file>`.

## 6. Add your key and server

Copy the private key to the iPad. Do not send it by mail or chat.

1. Rename a copy of the key to `<server name>.key`, for example `home.key`.
2. Connect the iPad. On a Mac open Finder, select the iPad, open **Files**. On Windows use the Apple Devices app or iTunes, File Sharing. Drag the file into PadTerm.
3. In PadTerm tap **+**. Enter the same name, then host, port, user and directory.
4. In the key section choose **Import file** and tap the row. Tap **Save**. The app deletes the copy from its Documents folder.
5. Tap **Claude**, compare the fingerprint with the one from section 2, and tap **Trust**.

On iOS 14 or later iOS asks for permission to use the local network. Allow it if your server is on your LAN. If you refuse, change it in Settings, Privacy & Security, Local Network.

## 7. Auto mode: read this

New Claude and Codex sessions start in auto mode: `claude --permission-mode auto` and `codex --approve-for-me`. The agent can edit files and run commands on your server without asking at each step. An automatic reviewer checks risky actions, but this is not a sandbox. Use a user and a directory that you accept this for. In Claude, tap **⇧Tab** to change the mode.

## 8. Common errors

| What you see | Likely reason | What to do |
|--------------|---------------|------------|
| "Untrusted Developer" | The profile is not trusted yet | Settings, General, VPN & Device Management, tap your email, **Trust** |
| The app opens, then closes after about a week | The 7-day signature ended | Sign and install again. Your servers stay |
| "Maximum App ID limit" | 10 App IDs per week | Wait, or use another Apple Account |
| The tool does not see the iPad | Cable, trust prompt, or missing iTunes on Windows | Try another cable, tap **Trust**, install iTunes from Apple's site |
| The connection times out on a LAN address | Local network permission is off | Settings, Privacy & Security, Local Network, turn on PadTerm |
| "Host key changed" | The server key changed, or someone is in the middle | Compare the fingerprint on the server. Forget the pin only if you know why it changed |
| `Login expired` on a macOS server | The login was made in the Mac's own Terminal | `claude auth login` from an SSH session |
| Black bars around the app | Compatibility mode on your iPad | Open an issue with your iPad model and iOS version |

## 9. Routes that do not work

| Route | Why |
|-------|-----|
| App Store, TestFlight | A public build needs an arm64-only Xcode build and App Review. None exists today |
| AltStore PAL | It installs notarized apps only |
| Enterprise certificates | They are for a company's own staff. Apple revokes certificates sold to the public |

## 10. Build it yourself

See [the README](../../README.md#3-build-macos-apple-silicon-command-line-tools-only). Technical limits per iOS version are in [ios-version-support.md](../design/ios-version-support.md).

# Use PadTerm on an iPad that is not jailbroken

This guide takes you from a normal iPad to a working Claude Code or Codex session. You do not need to jailbreak the iPad.

**Read this first**

- ⚠️ **We have not run these steps.** Our only test iPad is jailbroken. The steps come from the Sideloadly site. If they differ, follow [Sideloadly](https://sideloadly.io/), and please send a [device report](https://github.com/SCP120/PadTerm/issues/new?template=device-report.yml) with what happened.
- The app runs on your iPad, and Claude Code and Codex run on **your own computer or server**. You need one that stays on.
- Apple runs an app only if it has a signature from Apple. A tool on your computer signs PadTerm with your Apple Account. With a free account the signature lasts **7 days**, and you must then sign again. Your servers stay.

## 1. Can your iPad do this?

Open **Settings, General, About** and read the version.

| iPad | Newest iOS it can run | Can it use this guide? |
|------|-----------------------|------------------------|
| Any iPad on iOS 6 | | ❌ **No.** No tool that we know of signs for iOS 6. Update the iPad (see below), or see the [jailbreak route](README.md#3-jailbroken-ipad) |
| iPad 2, iPad 3, iPad mini 1 | iOS 9 | ✅ On iOS 7 to 9 |
| iPad 4 | iOS 10 | ✅ On iOS 7 to 10 |
| iPad Air 1, iPad mini 2, iPad mini 3 | iOS 12 | ✅ On iOS 10 to 12. On iOS 7 to 9, update first |
| Any iPad on iOS 13 or later | | ❌ PadTerm supports iOS 6 to 12 only |

The "newest iOS" column comes from Apple's public lists, and we did not check it again.

**To update an old iPad:** back it up first, then use Settings, General, Software Update. An update cannot be undone. Do not update past iOS 12.

## 2. What you need

| Item | Notes |
|------|-------|
| The file `PadTerm-<version>-iOS7-12-sideload.ipa` | From the [releases page](https://github.com/SCP120/PadTerm/releases) |
| A Mac (macOS 10.12 or later) or a PC (Windows 7 or later) | It signs the app, and it must be there again every 7 days |
| A USB cable that carries data | A charge-only cable does not work |
| An Apple Account | A free one is enough. A spare account keeps your main one separate |
| A server | A Mac or Linux computer that you own, with SSH. It can be the same Mac |

Sign in with your Apple Account only on a computer that you own.

## 3. Prepare the server

Do this once, on the computer that runs the agents.

**Install the tools.**

```sh
# Linux (Debian/Ubuntu)
sudo apt install tmux openssh-server

# macOS: also turn on System Settings, General, Sharing, Remote Login
brew install tmux
```

**Install the agents and log in to them.** The login needs a browser.

```sh
curl -fsSL https://claude.ai/install.sh | bash    # then run: claude
npm install -g @openai/codex                      # then run: codex login
```

On a macOS server, also run `claude auth login` once **from an SSH session**. macOS keeps a login made in its own Terminal away from SSH sessions.

**Make a key for this iPad.** Run this on your computer, and use your own user and server names.

```sh
ssh-keygen -t ed25519 -N "" -C ipad -f ~/.ssh/id_ed25519_ipad
ssh-copy-id -i ~/.ssh/id_ed25519_ipad.pub you@your-server
ssh you@your-server ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Write down the `SHA256:...` text that the last command prints. You compare it in step 6.

Use this key for this iPad only. If you lose the iPad, remove the `ipad` line from `~/.ssh/authorized_keys` on the server.

## 4. Install PadTerm with Sideloadly

Current versions of AltStore need iOS 17.4 or later, so they do not fit these iPads. Sideloadly lists iOS 7 and later.

1. Download Sideloadly from [sideloadly.io](https://sideloadly.io/) only.
2. **Windows only:** install iTunes and iCloud from Apple's website, not from the Microsoft Store. Remove the Microsoft Store versions first.
3. Connect the iPad with the cable. On the iPad, tap **Trust** and enter the passcode.
4. Open Sideloadly and drag the `.ipa` into it.
5. Type your Apple Account email and press **Start**. Enter the password when asked.
6. Wait until it says done.
7. On the iPad, open **Settings, General, Device Management**. On some versions this is called **Profiles** or **Profiles & Device Management**.
8. Tap your email, then tap **Trust**.

PadTerm is now on the Home Screen.

## 5. Copy the key to the iPad

The key is a private file. Do not send it by mail or chat, and do not put it in a cloud folder.

1. Make a copy of `~/.ssh/id_ed25519_ipad` named after your server, for example `home.key`.
2. Connect the iPad and open the file list:
   - **macOS 10.15 or later:** Finder, select the iPad, **Files** tab.
   - **Older macOS or Windows:** iTunes, select the iPad, **File Sharing**.
3. Drag `home.key` into **PadTerm**.
4. Delete your copy named `home.key` on the computer. Keep the original.

## 6. Add your server

1. Open PadTerm and tap **Add Server**.
2. Fill in the form:

| Field | Example |
|-------|---------|
| Name | `home` (the same name as the key file) |
| Host | `192.168.1.10`, or the server's name |
| Port | `22` |
| User | your login on the server |
| Directory | the project folder, or `~` |

3. In the key section choose **Import file**, then tap the row that says **Import**.
4. Tap **Save**. The app stores the key and deletes the copy from its Documents folder.
5. Tap **Claude** or **Codex**.
6. Compare the fingerprint with the `SHA256:...` text from step 3. If they match, tap **Trust**. **If they differ, tap the other button and find out why.**

You now see the real agent on your iPad.

## 7. Everyday use

| To do this | Do this |
|------------|---------|
| Start a new agent | Tap **Claude**, **Codex** or **Shell** on the server page |
| Continue an old session | Tap it in the **Sessions** list. It attaches, or resumes if the agent stopped |
| Change session from the terminal | Tap **Sessions** in the top bar |
| End a session | Swipe its row to the left and tap **Delete**. The agent's own history stays on the server |
| Send Esc, Tab, Ctrl, arrows | Use the key bar above the keyboard |
| Scroll back | Swipe on the terminal. Tap **Esc** to return |
| Paste | Long press on the terminal |
| Change light or dark, font size | Tap the gear |

**Auto mode:** Claude and Codex start and resume in auto mode. The agent can edit files and run commands in that directory without asking each time. An automatic reviewer checks risky actions, but this is not a sandbox. In Claude, tap **⇧Tab** to change the mode.

If the Wi-Fi drops, PadTerm reconnects by itself, and the agent keeps running on the server.

Away from home, the iPad must still reach the server by SSH. A VPN such as Tailscale can do this, if your iOS version has an app for it. We did not test this.

## 8. Every 7 days

With a free Apple Account the app stops opening after 7 days. It shows a short flash and closes. This is normal, and your servers stay.

1. Connect the iPad to the computer.
2. Open Sideloadly and drag in the same `.ipa`.
3. Press **Start**.

Sideloadly also has an automatic refresh when the computer is on. See its site. A paid Apple Developer account ($99 a year) gives one year instead of 7 days.

## 9. When something goes wrong

| What you see | Likely reason | What to do |
|--------------|---------------|------------|
| "Untrusted Developer" | The profile is not trusted | Do step 4, items 7 and 8 |
| The app flashes and closes | The 7 days ended | Do section 8 |
| Sideloadly does not see the iPad | Cable, trust prompt, or iTunes on Windows | Use another cable, tap **Trust**, install iTunes from Apple's site |
| Apple password refused | Your account uses two-factor login | Follow the Sideloadly page on app-specific passwords |
| "Maximum App ID limit" | A free account has 10 new App IDs in 7 days | Wait, or use another Apple Account |
| A limit of 3 apps | A free account has 3 sideloaded apps | Delete one |
| "No key file" | The key file name does not match the Name field | Rename one so that they match |
| "Key not accepted" | The key has a passphrase, or is not Ed25519 | Make the key as in step 3, with `-N ""` |
| "Host key changed" | The server key changed, or someone is in the middle | Check the fingerprint on the server. Do not continue until you know why |
| `Login expired` on a macOS server | The login was made in the Mac's own Terminal | Run `claude auth login` from an SSH session |
| Connection times out | Wrong address, or the server blocks SSH | Try `ssh you@your-server` from another computer |
| "Private key file found" at start | A `.key` file is still in the app's Documents | Import it, or delete it through File Sharing |

If you are stuck, open a [device report](https://github.com/SCP120/PadTerm/issues/new?template=device-report.yml). Do not paste keys, host names or session text.

## 10. Remove PadTerm

1. On the iPad, delete the app. The stored key goes with it.
2. On the server, remove the `ipad` line from `~/.ssh/authorized_keys`.
3. On the server, optional: delete `~/.padterm`. The agents' own history stays.

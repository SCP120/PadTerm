# Security

## Report a problem

Use GitHub's private report: the **Security** tab of this repository, then **Report a vulnerability**. Do not open a public issue for a security problem.

## What PadTerm does

- It connects by SSH to a server that you own. It has no account, no relay and no telemetry.
- It holds no Claude or Codex login. Each agent runs on your server and logs in there with your own account.
- A release contains no key and no credential. `scripts/check_release.py` and gitleaks check this before each release.

## Known limits

| Limit | Detail |
|-------|--------|
| Private key on the iPad | PadTerm needs an unencrypted Ed25519 key, because it reconnects with no prompt. The key is in the app's Library, mode 0600, with `NSFileProtectionComplete` where the device allows it, and is excluded from backups. A jailbroken iPad can refuse file protection: then mode 0600 is the only protection. Use a key for this iPad only, so that you can revoke it |
| Key in memory | The key stays in memory while a session or a session list is open, for reconnects |
| Host key | Trust on first use: compare the fingerprint at the first connection. A changed key stops the connection before login |
| Auto mode | New and resumed Claude and Codex sessions start in auto mode. The agent can edit files and run commands on your server without asking each time. Use a user and a directory that you accept this for |
| libssh2 | Pinned to a commit on its main branch (`scripts/dep_pins.sh`), because release 1.11.1 has CVE-2026-55200 and others, and no release held the fixes on 2026-11-04. This moves to the next release when it exists |
| Sideloaded builds | A sideload tool signs the app with your Apple Account. Get the tool from its own site |
| Device testing | v0.1.0 has not run on a real iPad. Earlier builds ran on an iPad mini 1 on iOS 6.1.3. No real iPad on iOS 7 or later has run the app |

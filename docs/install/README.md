# Install guide

PadTerm supports **iOS 6 to 12** on iPad. It is a terminal client: Claude Code and Codex run on your own server, and the iPad shows them over SSH. The app has no account, no relay and no telemetry. Each agent logs in on your server with your own account.

**What has been tested**

| Part | State |
|------|-------|
| iPad mini 1, iOS 6.1.3, jailbroken | ✅ Earlier builds ran on the real device: UI, sessions, a real Claude session over Wi-Fi. ⚠️ Releases since v0.1.0 have not run on a real iPad yet: they have a new SSH library build, a new name and new icons |
| A real iPad on iOS 7 to 12 | ⚠️ **Experimental: never run.** Please send a [device report](https://github.com/SCP120/PadTerm/issues/new?template=device-report.yml) |
| The sideload steps | ⚠️ Not run by us |
| iOS 13 and later | ❌ Not supported |

## 1. Pick your route

Open Settings, General, About on the iPad and read the version.

| Your iPad | Route | File |
|-----------|-------|------|
| iOS 7 to 12, **not jailbroken** | **[Step-by-step guide for a non-jailbroken iPad](non-jailbroken-ipad.md)** | `PadTerm-<version>-iOS7-12-sideload.ipa` |
| iOS 6 to 12, jailbroken | [Jailbreak route](#3-jailbroken-ipad) | `PadTerm-<version>-iOS6-12-jailbreak.deb` |
| iOS 6, not jailbroken | **No known route.** Update the iPad and sideload, or jailbreak it | |
| iOS 13 or later | **Not supported** | |

Get the files from the [releases page](https://github.com/SCP120/PadTerm/releases). One file serves its whole range: it holds 32-bit code for iPad 2, 3, 4 and mini 1, and 64-bit code for later iPads. The 64-bit code needs iOS 10 or later, so a 64-bit iPad on iOS 7 to 9 must update first. iPhones are not supported: the layout is for iPad only.

## 2. Prepare the server

Do this first on every route. The steps are in [section 3 of the non-jailbroken guide](non-jailbroken-ipad.md#3-prepare-the-server), and they are the same for a jailbroken iPad.

## 3. Jailbroken iPad

This guide gives no jailbreak steps. For your device see https://ios.cfw.guide/ and https://theapplewiki.com/ . The package is for a rootful jailbreak, and it installs to `/Applications`.

Install `PadTerm-<version>-iOS6-12-jailbreak.deb` with your package manager (Cydia, Sileo, Zebra), or with `dpkg -i`. The package refuses iOS 13 and later.

An iPad that accepts unsigned apps through the normal install service can also use `ideviceinstaller` over USB, as the iOS 6 test iPad does: `scripts/ipad_deploy.sh <file>`.

Then copy the key and add the server: [sections 5 and 6 of the non-jailbroken guide](non-jailbroken-ipad.md#5-copy-the-key-to-the-ipad).

## 4. Routes that do not work

| Route | Why |
|-------|-----|
| AltStore | Current versions need iOS 17.4 or later |
| App Store, TestFlight | They need a current Xcode build for iOS 15 or later, and App Review. None exists |
| Enterprise certificates | They are for a company's own staff. Apple revokes certificates sold to the public |

## 5. Build it yourself

See [the README](../../README.md#3-build-macos-apple-silicon-command-line-tools-only). Technical limits per iOS version are in [ios-version-support.md](../design/ios-version-support.md).

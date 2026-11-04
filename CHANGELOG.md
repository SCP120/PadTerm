# Changelog

## [Unreleased]

## [0.1.1] - 2026-11-04

### Changed
- PadTerm now supports **iOS 6 to 12** only. The rootless package and all iOS 13+ routes are gone, and the jailbreak package refuses iOS 13 and later.
- Release files are named by install method and iOS range: one `.deb` for a jailbroken iPad, one `.ipa` to sideload.

### Added
- A step-by-step [guide for a non-jailbroken iPad](docs/install/non-jailbroken-ipad.md).

Not run on a real iPad: it passes the Mac tests and the iOS 6 binary checks.

## [0.1.0] - 2026-11-04

First public release.

### Added
- SSH + tmux terminal for Claude Code and Codex CLI on your own Linux or macOS server, for iPads.
- Session list: sorted by activity, with the name each agent gives, and resume.
- Stock iOS 6 look with light and dark modes, changed live.
- Fat `.ipa`, rootful `.deb` and rootless `.deb`. Earlier builds ran on a real iPad mini 1 on iOS 6.1.3. This release itself has not run on a real iPad: it passes the Mac tests and the iOS 6 binary checks. iOS 7 and later are experimental.

# PadTerm iOS version support (iOS 6 to 12)

Status: 2026-11-04. **Only the armv7 slice has run on a real device** (iPad mini 1, iOS 6.1.3). The modern code path has run on modern UIKit through a Mac Catalyst test bench on macOS 27 (section 4.1). No modern iPad has run the app. Items marked *(unverified)* come from memory or from non-Apple sources.

**Supported range: iOS 6 to 12** (owner, 2026-11-04). The rootless package and the sideload routes for iOS 13 and later are gone. The sections below on later iOS are background: the code keeps its guards, and the Catalyst bench still uses them, but those versions are not supported.

## 1. Summary

| Question | Answer |
|---|---|
| Same binary for the App Store or TestFlight? | **No.** Xcode 14+ cannot build armv7 for iOS, and App Store Connect needs an Xcode 26 / iOS 26 SDK build with a deployment target of iOS 15 or later (see section 2). That is a separate arm64-only Xcode build. |
| One source tree? | Yes. Newer APIs sit behind `respondsToSelector`, `NSClassFromString` or `#if __IPHONE_OS_VERSION_MAX_ALLOWED`. `@available` does not link in the armv7 pass. |
| Biggest risk | Touch, the on-screen keyboard, split screen and Stage Manager on a real modern iPad. The bench cannot show them. |

## 2. Version matrix

CPU facts: armv7 devices cannot run arm64 code. arm64 started with the A7 (iPad Air 1 and iPad mini 2, which shipped with iOS 7). 32-bit apps stopped running in iOS 11, and 32-bit iPads cannot install iOS 11 at all. The last iOS per 32-bit iPad is from Apple's public lists and was not re-checked here *(unverified)*: iPad 2, 3 and mini 1 end at 9.3.5; iPad 4 ends at 10.3.4.

| iOS / iPadOS | Slice that runs | Build approach | SDK / toolchain | Limits and notes |
|---|---|---|---|---|
| 6 | armv7 only | existing build: theos, `-mno-thumb`, min 6.0 | iPhoneOS 9.3 SDK (patched copy), CLT clang + ld-27037 | Only iPad 2, 3, 4 and mini 1 run iOS 6. Works on the owner's iPad mini 1 (iOS 6.1.3, jailbroken, ldid fake signature). |
| 7 to 8 | armv7 (32-bit iPads). A 64-bit iPad must update to iOS 10 | fat | armv7: 9.3 SDK. arm64: min target 10.0 | Spike links arm64 with min 7.0. Linker writes `LC_VERSION_MIN_IPHONEOS` below iOS 12. UI changes to the iOS 7 look. |
| 9 to 10 | armv7 or arm64 | fat | same | Last iOS for 32-bit iPads. Clang demands `libarclite` for ARC at min target below 9.0, but only when `-fobjc-arc` is on the link line (see 5.3). |
| 13 and later | not supported | | | The package refuses them; the code still has guards |
| 11 to 12 | arm64 only | arm64 slice of the fat binary | same | iOS 11 refuses 32-bit-only apps. Fat binaries run the arm64 slice. |

### What a modern iOS needs from the binary

| Item | Requirement | Spike result |
|---|---|---|
| Architecture | arm64 (plain arm64, not arm64e) | `otool -hv`: ARM64, PIE, `LC_MAIN` |
| Version load command | `LC_VERSION_MIN_IPHONEOS` below min 12, `LC_BUILD_VERSION` from 12 | confirmed with real output below |
| Code signature | A real Apple signature (CMS blob) plus an embedded provisioning profile, entitlements matching the profile (`application-identifier`, usually `get-task-allow`) | ldid writes a **fake** signature only (no certificate). A jailbroken device accepts it. A stock device does not. |
| Page hashes | 4 KB pages, SHA-1 and SHA-256 code directory | ldid output: `hashes=1465+2`, `Hash choices=sha1,sha256` |
| App Store upload | Xcode 26+, iOS 26 SDK since 2026-04-28, iOS 13+ target since 2026-09-09 per Apple; Xcode 26 range iOS 15 to 26.5 ([Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/)) | Not attempted (needs Xcode and an Apple account) |
| Xcode 14+ | No building iOS projects for armv7, armv7s, i386 (quoted from the Xcode 14 release notes via a [libwebp commit](https://git.iohub.dev/dany/libwebp/src/commit/c00d83f6642e7838a12bb03bca94237f03cc2e00)) | n/a: we use CLT clang, which still emits armv7 |

## 3. Recommended build plan

1. **Keep the armv7 build as is** (9.3 SDK, `-mno-thumb`, min 6.0). Do not change it.
2. **Add an arm64 pass** with the iPhoneOS16.5 SDK (or newer from theos/sdks), `-miphoneos-version-min=10.0` for the jailbreak and sideload product. `scripts/build_deps_arm64.sh` and `scripts/package_all.sh` hold the commands. The arm64 minimum is 10.0, because libssh2 calls `clock_gettime`.
3. **Merge with `lipo -create`**, then sign: `ldid -S` for jailbreak; a real signer (Sideloadly) re-signs for stock devices. These tools replace the ldid signature.
4. **Ship three artefacts:**

| Artefact | Slices | Signed by | Reaches |
|---|---|---|---|
| `.deb` rootful (iphoneos-arm) | armv7 + arm64 | ldid | iOS 6 to about 14 jailbreaks with `/Applications` |
| `.ipa` | armv7 + arm64 | the user's sideload tool | stock iPads, iOS 7 to 12 ([guide](../install/non-jailbroken-ipad.md)) |
| App Store / TestFlight build | arm64 | Xcode, paid account | iOS 15+, after App Review (section 8) |

5. **Source rule:** one source tree. Any API newer than the 9.3 SDK sits under `#if __IPHONE_OS_VERSION_MAX_ALLOWED >= N`, plus a runtime check, because the armv7 pass cannot see the declaration.
6. **Check before a release:** `scripts/check_release.py` fails on a key, a session record, a test capture, a local path, or mascot art in a package.

## 4. Spike results (real output)

Host: macOS arm64, Command Line Tools only, Apple clang 21.0.0, `ld PROJECT:ld-27037.1`, ldid 2.1.5-procursus7. SDK: theos `iPhoneOS16.5.sdk` (its `SDKSettings` says "iOS 16.4"), the newest in theos/sdks.

| Step | Result |
|---|---|
| OpenSSL 3.5.9, target `ios64-xcrun`, CC override, **with** arm64 assembly | OK. Whole deps script took 19 s. `lipo -info`: `libcrypto.a`, `libssl.a`, `libssh2.a` are arm64. Object `LC_VERSION_MIN_IPHONEOS version 7.0 sdk 16.4`. |
| libssh2 (cmake, OpenSSL backend) | OK |
| libvterm 0.3.3 (patched), core/*.c, render/pt_render.c, `-Wall -Wextra` | OK, no warnings, `libpadcore.a` built |
| All 9 `ios/src/*.m` files, `-fobjc-arc -Werror=unguarded-availability`, min 7.0 | OK, **0 warnings, 0 errors**. Nothing in the app is newer than iOS 7.0. |
| Link the real app (UIKit, Foundation, CoreGraphics, CoreText, QuartzCore) | OK. 5.7 MB. |
| `otool -hv` | `MH_MAGIC_64 ARM64 ALL EXECUTE ncmds 23 flags NOUNDEFS DYLDLINK TWOLEVEL PIE` |
| `otool -l` | `cmd LC_VERSION_MIN_IPHONEOS version 7.0 sdk 16.4` |
| Same test at min 12.0 on a trivial program | `LC_BUILD_VERSION platform 2 minos 12.0` |
| Min 6.0 for arm64 | clang and ld accept it (`LC_VERSION_MIN_IPHONEOS version 6.0`), but no iOS 6 device runs arm64, so use 7.0 or later |
| `lipo -create` existing armv7 binary + new arm64 binary | OK: `Architectures in the fat file: armv7 arm64`, offsets 16384 and 4751360, align 2^14. armv7 slice `version 6.0`, arm64 slice `version 7.0`. |
| `ldid -S` on the arm64 and the fat file | exit 0, `LC_CODE_SIGNATURE` in both slices, `CodeDirectory v=20400`, sha1+sha256. `ldid -Sent.plist` plus `ldid -e` round-trips an entitlement. |
| `codesign -dvv` on the fat file | `no signature` / `Info.plist=not bound`: the signature is ldid's fake one, not a valid Apple signature |
| Bundle and IPA zip | `PadTerm-fat-unsigned-by-apple.ipa` (4.4 MB, `plutil -lint` OK). Not signed by Apple, not installable on a stock iPad. |

Undefined `objc_*` imports of the arm64 binary (static check): `objc_retain`, `objc_release`, `objc_storeStrong`, `objc_loadWeakRetained`, `objc_retainAutoreleasedReturnValue`, `objc_autoreleasePoolPush/Pop`, `objc_msgSend`, `objc_setAssociatedObject` and similar. All exist since iOS 5. No `objc_alloc` or `objc_opt_*`, which newer clang emits for newer targets. Imports that exist in arm64 but not in the armv7 build: `_Unwind_Resume`, `__darwin_check_fd_set_overflow`, `bzero`, `sysctlbyname`, `usleep`. Whether iOS 7 and 8 export all of them was not checked *(unverified)*.

### Failures and findings

| Finding | Exact output | Meaning |
|---|---|---|
| ARC link below iOS 9 | `clang: error: SDK does not contain 'libarclite' at the path '/Library/Developer/CommandLineTools/usr/lib/arc/libarclite_iphoneos.a'; try increasing the minimum deployment target` | Appears when `-fobjc-arc` is on the **link** command with min below 9.0 (tested at 6.0, 7.0, 8.0; min 9.0 and 10.0 link). Our scripts compile with ARC and link without that flag, so they pass. The app imports only iOS 5+ runtime symbols. The existing armv7 iOS 6.1.3 build is the evidence that this works. |
| `@available` in the armv7 pass | `Undefined symbols for architecture armv7: "__availability_version_check", referenced from: ___isPlatformVersionAtLeast in libclang_rt.ios.a[armv7][16](os_version_check.c.o)` | The 9.3 SDK stubs lack that iOS 12 symbol, so `@available` and `if (@available(...))` **do not link** in the armv7 pass. Use `respondsToSelector:`, `NSClassFromString` or `NSFoundationVersionNumber`, plus `#if` on the SDK macro. |
| Headers in the 9.3 SDK | `property 'hasStrings' not found on object of type 'UIPasteboard *'` | The armv7 pass cannot see iOS 10+ declarations. Gate with `#if`, or call through `performSelector`. |
| Min-16 deprecation run | see section 5 (real compiler text) | |

**Not done:** no run on a modern device, no simulator (none without Xcode), no App Store or TestFlight upload, no real Apple signing.

### 4.1 Modern UIKit bench (real runs, 2026-11-04)

`scripts/build_catalyst.sh` builds the same sources as a Mac Catalyst app with Command Line Tools only (`arm64-apple-ios15.0-macabi`, SDK 27). `tests/modern/run_bench.sh` runs `tests/device/ui_full_test.py` against it with real SSH and tmux, with `CFFIXED_USER_HOME` so the app cannot touch the real `~/Documents`.

| Result | Value |
|---|---|
| Launch | Crash before the scene fix, runs after it |
| Full UI test | 26 of 26, light and dark, with the layout audit after each step |
| Bugs it found that iOS 6 cannot show | Rows 1, 2 and 3 of the table in 5.2 |
| Limits | It is Mac UIKit: no touch, no on-screen keyboard, no rotation effect, sheets live in separate windows, memory numbers do not apply to an iPad |

Bench-only test driver changes: alerts through `UIAlertController`, bar buttons through the navigation item, sheet windows outside `-windows`, capture with `drawViewHierarchyInRect`. Green tests did not catch row 3: only a look at the capture did.

## 5. UIKit compatibility: what the code uses and what to change

Method: read all `ios/src/*.m`, then compiled them against the iOS 16.5 SDK at min target 16.0 so clang lists the real deprecations. Behaviour on iOS 7+ below is predicted from API documentation, **not observed on a device**.

### 5.1 Real compiler output (min target 16.0)

```
PTLaunchController.m:84   'titleEdgeInsets' is deprecated: first deprecated in iOS 15.0 ...
PTProfileEditController.m:110, PTTerminalController.m:373,383  'UIAlertView' is deprecated: first deprecated in iOS 9.0 - Use UIAlertController
PTTerminalController.m:116  'applicationFrame' is deprecated: first deprecated in iOS 9.0
PTTerminalController.m:142-144  'UIBarButtonItemStyleBordered' is deprecated: first deprecated in iOS 8.0
PTTerminalView.m:80,81  'UIMenuController' is deprecated: first deprecated in iOS 16.0 - Use UIEditMenuInteraction
PTTerminalView.m:80  'setTargetRect:inView:' ... deprecated in iOS 13.0
PTTerminalView.m:81  'setMenuVisible:animated:' ... deprecated in iOS 13.0
```

Not used (grep found none): `UIActionSheet`, `shouldAutorotateToInterfaceOrientation`, `presentModalViewController`, `sizeWithFont`, `statusBarStyle` setters, `UIAlertController`.

### 5.2 Changes for modern iOS

"Bench" = seen on modern UIKit through the Catalyst bench. "Code" = in the code, no modern run proves it.

| # | Where | Problem | State |
|---|---|---|---|
| 1 | `main.m`, `Info.plist` | An app linked with the newest SDK and no scene crashes at launch: `___UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption` (crash report on macOS 27, SDK 27). TN3187 says the same for the release after iOS 26 | ✅ Fixed, bench. `PTSceneDelegate` in the arm64 pass, `UIApplicationSceneManifest` in the plist. iOS 6 to 12 ignore both |
| 2 | `PTSplitController.openTerminal` | Since iOS 13 the default presentation is a sheet: the terminal opened as a small card that a swipe closes | ✅ Fixed, bench. `UIModalPresentationFullScreen`; no change on iOS 6 |
| 3 | `PTTheme.styleCell` | In light mode the selected server row lost its name: modern UIKit draws selected text in the blue of the selection | ✅ Fixed, bench. White highlighted text in both modes; iOS 6 already used white |
| 4 | `PTTerminalController` | Row 0 under a translucent bar (`edgesForExtendedLayout`) | ✅ Bench shows row 0 below the bar |
| 5 | `Info.plist` | Letterbox without a launch screen | Code: `UILaunchScreen`. Apple documents it for no storyboard; effect not seen on an iPad |
| 6 | `Info.plist` | Local network prompt for SSH to a LAN address (TN3179) | Code: `NSLocalNetworkUsageDescription`. The prompt shows at first use; not seen on an iPad |
| 7 | `PTTerminalView` | Hardware keyboard: arrows, Esc, Ctrl chords | Code: `keyCommands`. Not pressed by a real keyboard |
| 8 | `showHostKey:`, `showMessage:` | `UIAlertView` deprecated | ✅ Bench: `UIAlertController` from iOS 8 |
| 9 | `PTTerminalView canPerformAction:` | Paste banner on each menu check | Code: `hasStrings` from iOS 10 |
| 10 | `PTTerminalController` | Home indicator inset | Code: `safeAreaInsets` from iOS 11 |
| 11 | `PTTerminalController.keyboardChanged:` | Floating or split keyboard gives a wrong terminal height | Code: a keyboard that does not touch the bottom edge takes no rows |
| 12 | `PTTerminalView.longPress:` | `UIMenuController` deprecated in iOS 16 | Open: still compiles and runs on the bench; replace with `UIEditMenuInteraction` when a device can prove it |
| 13 | `Info.plist` | iPadOS 26 windowing | Code: `UIRequiresFullScreen`. Effect not seen |

Stock controls take the look of the iOS that runs them: from iOS 7 the bars, buttons and tables are flat, so the iOS 6 style shows fully only on iOS 6. The icons, key bar and dark rows are the app's own art and stay.

### 5.3 Info.plist keys

| Key | Current | Modern status |
|---|---|---|
| `UIDeviceFamily` `[2]` | iPad only | Fine. iPhones cannot install it. Adding `1` needs layout work (`PTLaunchController` uses fixed 40 pt insets). |
| `UIRequiresPersistentWiFi` | true | Apple still documents it: opens Wi-Fi at launch and keeps it while the app runs; otherwise iOS closes Wi-Fi after 30 minutes ([Apple](https://developer.apple.com/documentation/bundleresources/information-property-list/uirequirespersistentwifi)). I did not see a deprecation flag in the extract; effect on iOS 15+ not tested. |
| `UIFileSharingEnabled` | true | Still documented ([Apple](https://developer.apple.com/documentation/bundleresources/information-property-list/uifilesharingenabled)). Windows and macOS access (Finder or Apple Devices app) and the Files app. This is the key import path for non-jailbroken users. `LSSupportsOpeningDocumentsInPlace` is commonly set together *(unverified whether it is needed)*. |
| `UIRequiredDeviceCapabilities` `armv7` | armv7 | For a fat build keep or drop. For an arm64-only build use `arm64`. Whether a 64-bit iPad satisfies `armv7` was not verified *(unverified)*. |
| `MinimumOSVersion` 6.0 | | Fine for the fat build. Xcode builds need 15+. |
| `UISupportedInterfaceOrientations~ipad` | all four | Fine. `shouldAutorotate` and `supportedInterfaceOrientations` are the iOS 6+ API and are already used. |

## 6. Jailbroken paths

| Era | Package | Install location | What PadTerm needs |
|---|---|---|---|
| iOS 6 to about 14 (rootful) | `.deb`, `Architecture: iphoneos-arm`, `Depends: firmware (>= 6.0)` (current control file) | `/Applications/PadTerm.app`, root, no sandbox | Current package works on the iPad mini 1. A fat binary adds the arm64 slice; same deb. |
| `.ipa` on a jailbroken device | zip with `Payload/PadTerm.app` | installed by the user's tool | Needs a real or ldid signature; the app is sandboxed, so Documents lives in the sandbox container and File Sharing works. |

Rootful jailbreak by version (6, 7, 8-9, 10, 11-14 and so on) and the rootless or roothide tools change over time; this document holds no current list. See [iOS Guide](https://ios.cfw.guide/) and [The Apple Wiki](https://theapplewiki.com/) for the tool that matches a device and iOS version. This document gives no jailbreak steps.

Notes for the package work:
- `scripts/ipad_install_key.sh` and `ipad_deploy.sh` rely on the jailbreak (ssh or file access). A stock iPad has no such route, so the key import is File Sharing (app reads `<name>.key` from Documents).
- A rootless build runs inside the same app logic. The app writes only under `NSDocumentDirectory` and `Library` (checked in `PTProfileStore.m`), so no path change is needed for `/var/jb`.

## 7. Risks

| Risk | Likelihood / effect | Mitigation |
|---|---|---|
| iOS 7+ UI never seen on a device | High for layout bugs (rows 1, 4, 8) | One iPad on iOS 9.3.5 and one on iOS 15+ for a smoke test before release |
| Sideload tools and old iOS | Sideloadly says iOS 7 to 27+ on its own page; whether it installs a 32-bit slice on iOS 9 or 10 was not confirmed *(unverified)* | Test on an iOS 9.3.5 iPad before promising it |
| Fake ldid signature on stock iPad | Certain rejection | Only a real Apple signature works; use the install guide |
| UIScene requirement | Blocked launch with SDK 27 on the bench | Closed: `PTSceneDelegate`, seen launching on the bench |
| `UIAlertView`, `UIMenuController` removal | Unknown date | Do items 6 and 10 |
| Trademarks | App Store rejection, or a rename request | Name and icons are neutral; see section 8 |
| Spike used a 16.4 SDK, not the newest | arm64 against iOS 17 to 27 APIs not checked | Re-run the spike with a newer theos SDK when it exists |
| 3-app and 7-day limits | User friction | Install guide, paid account option |

## 8. App Store and TestFlight: honest position

- A public build needs an arm64-only Xcode 26 build, a paid Apple Developer Program account and review. TestFlight needs the same build, builds last 90 days, and the first external build goes to App Review ([TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview)).
- **Trademark:** the app's name and icons use no third-party brand. The text says that it runs Claude Code and Codex, in plain words. Guideline 4.1(c): "You cannot use another developer's icon, brand, or product name in your app's icon or name, without approval from the developer" ([Guidelines](https://developer.apple.com/app-store/review/guidelines/)).
- Apple's guidelines list no rule for SSH or terminal apps in the part read for this document, and no rule against them was found. Rule 4.2 (minimum functionality) and 5.1.2(i) (disclose sharing personal data with third-party AI) need a check against the final feature set. Apple Review's real decision cannot be predicted from here.
- The Apple Developer Enterprise Program is for internal distribution to an organisation's own staff. Do not use it for public distribution.

## 9. Sources

- Apple, Xcode support table: https://developer.apple.com/support/xcode/
- Apple, upcoming requirements (SDK dates): https://developer.apple.com/news/upcoming-requirements/
- Apple, TN3187 scene lifecycle (read through the documentation JSON endpoint): https://developer.apple.com/documentation/technotes/tn3187-migrating-to-the-uikit-scene-based-life-cycle
- Apple, Info.plist keys: UIRequiresFullScreen, UIRequiresPersistentWiFi, UIFileSharingEnabled, UIStatusBarStyle; UIPasteboard.hasStrings (same JSON endpoint)
- Apple, App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Apple, TestFlight overview: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview
- Apple, membership comparison (free limits): https://developer.apple.com/support/compare-memberships/
- Theos rootless: https://theos.dev/docs/rootless
- Sideloadly: https://sideloadly.io/
- AltStore FAQ: https://faq.altstore.io/altstore-pal-v.-altstore-classic and https://faq.altstore.io/altstore-classic/your-altstore
- 32-bit drop in iOS 11 (press): https://9to5mac.com/2017/06/04/32-bit-apps-ios-11/
- Xcode 14 armv7 removal (quoted in a commit): https://git.iohub.dev/dany/libwebp/src/commit/c00d83f6642e7838a12bb03bca94237f03cc2e00
- iPadOS 26 device list: https://www.iphoneincanada.ca/2025/06/09/which-ipads-support-ipados-26/
- Apple, TN3179 local network privacy: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- theos SDK list (newest 16.5): https://github.com/theos/sdks

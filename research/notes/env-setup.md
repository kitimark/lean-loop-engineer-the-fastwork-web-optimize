---
id: 2026-10-17-env-setup
kind: note
title: Local device environment setup (Android emulator, iOS simulator)
status: draft
created: 2026-10-17
topics: [environment, devices]
---

# Local device environment setup

Mac: Apple Silicon, 16 GB RAM. Disk free went from ~69 GB to ~59 GB over this setup.

| Tool | Version | Install | Disk | Verification |
|---|---|---|---|---|
| Temurin JDK (cask `temurin`) | 25.0.1 | `brew install --cask temurin` (already present as a dependency of android-commandlinetools) | ~131 MB | `java -version` reports OpenJDK 25.0.1 (the Homebrew openjdk on PATH; temurin cask also installed) |
| Android SDK licenses | n/a | `yes \| sdkmanager --licenses` | n/a | exit 0 |
| Android Emulator | from sdkmanager `emulator` | `sdkmanager "emulator"` | ~1.2 GB | boots |
| platform-tools (SDK copy) | r37.0.1 | `sdkmanager "platform-tools"` | ~37 MB | adb works |
| Platform android-36 | r02 | `sdkmanager "platforms;android-36"` | ~134 MB | installed |
| System image google_apis_playstore arm64-v8a, API 36 | r07 | `sdkmanager "system-images;android-36;google_apis_playstore;arm64-v8a"` | ~2.3 GB | boots |
| AVD `fw-pixel` (Pixel 8 profile) | n/a | `avdmanager create avd -n fw-pixel -k "system-images;android-36;google_apis_playstore;arm64-v8a" -d pixel_8` | ~1.6 GB in ~/.android/avd after boots | headless boot ok |
| xcodes | 2.1.0 (upgraded from 2.0.2) | `brew upgrade xcodes` | small | `xcodes runtimes` works after upgrade |

SDK root: `/opt/homebrew/share/android-commandlinetools`.

## Emulator test (CONFIRMED, measured)
- Command: `emulator -avd fw-pixel -no-window -no-audio -no-snapshot -gpu swiftshader_indirect` (background).
- `sys.boot_completed` = 1 after about 55 s (cold boot, headless).
- Chrome shipped in the image: 133.0.6943.137 (older than current stable; Play updates need a Google account).
- DevTools: after launching Chrome and dismissing first-run ("Use without an account", "No thanks"),
  `adb forward tcp:9222 localabstract:chrome_devtools_remote` then `curl http://localhost:9222/json/version`
  returned Browser Chrome/133.0.6943.137, protocol 1.3. Forward removed and emulator killed with `adb emu kill`.

## Problems
- `avdmanager` prints "Could not load devices from .../devices.xml" for this image; harmless, the AVD was still created.
- Chrome's DevTools socket does not exist until the first-run screen ("Make Chrome your own") is dismissed. The first
  attempt returned nothing for that reason. Run `pm clear` then tap through first-run, or set a command-line flag.
- Android Chrome 133 UA string reports `Android 10; K` (UA reduction), not the real OS version.
- `xcodes` 2.0.2 failed to list runtimes (`DecodingError ... authentication ... none`); fixed by `brew upgrade xcodes`.

## iOS 26.6 Simulator runtime: NOT AVAILABLE
- Xcode installed: 27.1 (build 27A9275). Installed runtime: iOS 26.5 (23F77).
- `xcodes runtimes` (and `--include-betas`) list iOS 26.0 through 26.5, then 27.0, 27.1, 27.2 betas. There is no
  iOS 26.6 entry, so nothing to install. The iPhone's 26.6 cannot be matched by the simulator; closest is 26.5.
- iOS 27.x runtimes exist and could be installed if wanted (not done; not requested).

## 2026-10-17: iOS 27.0 Simulator runtime (matches phone iOS 27.0.1)
- `xcodes runtimes` lists a release (non-beta) "iOS 27.0" (no beta flag needed). Installed with
  `xcodes runtimes install "iOS 27.0"`; no Apple ID prompt, no sudo.
- `xcrun simctl list runtimes`: iOS 26.5 (23F77) kept, iOS 27.0 (24A434) added. Xcode 27.1.
- Disk used: about 8 GB (free space 57 GiB -> 49 GiB).
- Device: `xcrun simctl create fw-iphone-27 "iPhone 15 Pro Max" com.apple.CoreSimulator.SimRuntime.iOS-27-0`.
- Verification: booted headless, shut down cleanly. `simctl openurl ... about:blank` fails with
  LSApplicationWorkspaceErrorDomain 115 (about: scheme not routable); `openurl https://example.com` succeeds and
  com.apple.mobilesafari is running. Use an https URL for Safari checks.

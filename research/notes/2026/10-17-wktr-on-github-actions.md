---
id: 2026-10-17-wktr-on-github-actions
kind: note
title: "WKTR without a cloud Mac: WebKit's own prebuilt iOS-simulator archives, GitHub Actions, and a GTK/WPE proxy"
status: draft
created: 2026-10-17
topics: [webkit, wktr, internals, github-actions, ci, measurement, calibration]
---

Question (work-graph task wktr-ci): can GitHub Actions on our public repo (free standard runners) replace the rented
cloud Mac for the WKTR spike (PLAN §4.2 Q10; `packages/measure-webkit/README.md` "Feasibility: WKTR and
`window.internals` on this Mac")?

Status tags: CONFIRMED (source/doc cited), MEASURED (read-only HTTP probes and queries run on 2026-10-17, listed with
each claim), INFERRED. WebKit source: pinned sparse clone `.cache/upstream/WebKit@862f17d` (sha
`862f17dcae0aace47ea0ec16e209d960abfd553c`, tag WebKit-7625.1.29.10.29), cited `path:line@862f17d`. Nothing was
pushed and nothing was built.

## 0. Answer first

- **No build is needed anywhere.** WebKit's CI publishes the full built products of every trunk revision to a public
  S3 bucket. The iOS-simulator archive contains `WebKitTestRunnerApp.app` and `libWebCoreTestSupport.dylib` (the
  `internals` object). WebKit's own testers use exactly this route: download, extract, run layout tests (MEASURED and
  CONFIRMED, §1.3).
- The archive is built with **Xcode 26.5 (17F42) against the iOS 26.5 simulator SDK, `MinimumOSVersion` 26.5**
  (MEASURED). GitHub's `macos-26` image ships Xcode 26.5 (17F42) and the iOS 26.5 simulator runtime, and this Mac
  already has the iOS 26.5 runtime (MEASURED). So the spike can run **on this Mac first, at no cost**, with
  GitHub `macos-26` as the free, reproducible CI copy.
- Building iOS WKTR from source on a standard GitHub macOS runner (3 vCPU, 7 GB RAM, 6 h job cap) is not realistic,
  and it is also unnecessary (§1.1).
- The Linux GTK/WPE proxy is also prebuilt (GTK 194 MB, WPE 261 MB zips per revision, MEASURED), but it runs only
  inside the 5.9 GB `wkdev-sdk` container. The style engine is shared code, but the proxy would need its own
  validation (§3). Keep it as an optional cross-check, not as the lane.
- Recommendation: **(d)**, a choice the brief did not list. Use the prebuilt iOS-simulator WKTR, locally now, then on
  GitHub `macos-26`. Drop the cloud-Mac rental (a). Do not build a GTK/WPE lane (b) unless the cross-check is wanted.
  Details in §4.

## 1. iOS-simulator WKTR on GitHub's macOS runner

### 1.1 Building from source: does not fit
- CONFIRMED runner: `macos-26` / `macos-15` arm64 = 3 vCPU (M1), 7 GB RAM, 14 GB SSD documented; 6 h job limit;
  cache 10 GB per repo, 7-day eviction; artifacts 500 MB on Free (`research/notes/2026/10-17-gha-public-runners.md`
  §1-2, doc URLs there). Larger runners are "always charged for, even when used by public repositories"
  (https://docs.github.com/en/billing/concepts/product-billing/github-actions). CONFIRMED.
- WebKit does not document build time, disk or RAM. Our earlier estimate (README "Feasibility" section) was 2-5 h and
  40-60 GB of products plus checkout, with peak RAM reported at 32 GB on a 20-core Mac Studio. INFERRED.
- MEASURED (zip central directory read over HTTP range requests, §1.3): the **products alone** of a release iOS-sim
  build are 4.06 GB uncompressed (2.93 GB of that is dSYMs). The intermediates come on top.
- INFERRED: with 3 cores and 7 GB RAM a clean build takes several times as long as on an 8-core Mac. It will very
  likely exceed the 6 h job cap and swap at link time (WebCore is 233 MB and WebKit 137 MB of release binary,
  MEASURED from the archive). The documented 14 GB of disk is not the real free space: Electron reports freeing
  about 134-157 GB on a "macOS-15" runner after cleanup (https://releases.electronjs.org/pr/49118). INFERRED: they
  may be on a larger runner, so this is unverified for the free label.
- Splitting the build across jobs: Xcode-side caching is LLVM's built-in compilation cache, which WebKit turns on by
  default (`COMPILATION_CACHE_ENABLE_CACHING = YES`, `Configurations/CommonBase.xcconfig:75-76@862f17d`). ccache is
  supported only for Xcode < 26 or with caching opted out (`Tools/ccache/README.md:1-9@862f17d`). INFERRED: chaining
  3+ jobs through a cache that must hold the compilation cache plus products (well over 4 GB) is possible inside the
  10 GB actions/cache limit, but fragile and slow. The 500 MB artifact quota rules out passing products as
  artifacts. Not worth doing given §1.3.

### 1.2 Downloadable prebuilt?
- CONFIRMED: `webkit.org/build-archives` offers macOS archives only (README "Feasibility"). Safari Technology Preview
  has no iOS build.
- **But the CI bucket is public.** The builder `Apple-iOS-26-Simulator-Release-Build` uploads an archive per revision
  (`Tools/CISupport/build-webkit-org/steps.py:476-492@862f17d`; bucket names at `:57-59`). Testers download it with
  a plain unauthenticated `curl --fail` (`Tools/CISupport/download-built-product:54@862f17d`, called from
  `steps.py:681-686`), then run layout tests (`Tools/CISupport/build-webkit-org/factories.py:90-103@862f17d`:
  `DownloadBuiltProduct`, `ExtractBuiltProduct`, `LayoutTestClass`). CONFIRMED.

### 1.3 Probe results (MEASURED, 2026-10-17, HEAD and range GETs only)
Revision 324039@main (`e1c510bc7fae8b20c296f2bcc3aeac3c5c8df578`), from build 14722 of builder id 1691 on
build.webkit.org (API `api/v2/builders/1691/builds/14722/steps`, step `compile-webkit` URLs).

| Archive (s3-us-west-2.amazonaws.com/...) | zip | unzipped | entries | WKTR + internals inside |
|---|---|---|---|---|
| `archives.webkit.org/ios-simulator-26-x86_64-arm64-release/324039@main.zip` | 1.18 GB | 4.06 GB | 21,805 | yes |
| `minified-archives.webkit.org/ios-simulator-26-x86_64-arm64-release/324039@main.zip` | 315 MB | 1.02 GB | 13,389 | yes: `WebKitTestRunnerApp.app` (3.3 MB), `libWebCoreTestSupport.dylib` (7.3 MB), `WebCore.framework`, `WebKit.framework`; host `Release/ImageDiff` |
| `archives.webkit.org/gtk-x86_64-release/324039@main.zip` | 194 MB | 838 MB | 108 | yes: `bin/WebKitTestRunner`, `lib/libTestRunnerInjectedBundle.so` |
| `archives.webkit.org/wpe-x86_64-release/324039@main.zip` | 261 MB | 1.05 GB | 123 | yes: `bin/WebKitTestRunner`, `lib/libTestRunnerInjectedBundle.so` |

- `WebKitTestRunnerApp.app/Info.plist` (extracted by range request): `DTXcode 2650`, `DTXcodeBuild 17F42`,
  `DTSDKName iphonesimulator26.5`, `MinimumOSVersion 26.5`. The public compile log confirms the iPhoneSimulator26.5
  SDK. MEASURED.
- Retention: the minified iOS archive still exists for 315361@main (2026-06-17), so at least 4 months. The full iOS
  and GTK archives exist for 322343@main (2026-10-01) but return 403 for 319464@main (2026-08-19). So the full
  archives are kept somewhere between 16 days and 2 months. MEASURED. INFERRED: pin a revision and keep our own
  copy; the minified zip (315 MB) fits actions/cache.
- Bucket listing is denied (403); objects are readable by exact key. MEASURED. Keys come from the build.webkit.org
  API (`archive_revision` property).
- Host match: the `macos-26` image has Xcode 26.5 (17F42) and the iOS 26.5 simulator runtime, with iPhone 17 / 17e /
  Air devices (`images/macos/macos-26-arm64-Readme.md:157-182,219-238`, runner-images main, image 20260907.0351.1;
  CONFIRMED). This Mac: iOS 26.5 runtime (23F77) installed, Xcode 27.1 only, 30 GiB free (MEASURED via
  `simctl list runtimes`, `df`).
- Run command, CONFIRMED options: `run-webkit-tests --ios-simulator --release --no-build --root <extracted>
  --version 26.5 --device-type "<type>"` (`Tools/Scripts/webkitpy/layout_tests/run_webkit_tests.py:160,265,347-348@862f17d`;
  `--version` sets the runtime, `webkitpy/port/embedded_device.py:92-94`). The default device is iPhone 12
  (`webkitpy/port/ios_simulator.py:68-69`). It needs a WebKit checkout of `Tools/Scripts` plus a small part of
  `LayoutTests` at the same revision. That is a sparse clone of `e1c510bc`, not the 13 GB repo.
- INFERRED risks, to settle in the first hour: webkitpy may also query the 27.1 SDK on this Mac (fix: use the GitHub
  runner, or install Xcode 26.5 next to 27.1); the archive is unsigned beyond ad-hoc (`README` in the zip), and
  Gatekeeper quarantine may need `xattr -dr com.apple.quarantine`.

## 2. Linux route: GTK or WPE WebKitTestRunner on `ubuntu-24.04`

- Runner: 4 vCPU, 16 GB RAM, 14 GB documented disk (CONFIRMED, gha note §1). Free space: about 18 GB at start and
  about 48 GB after removing .NET, Android, Haskell and CodeQL (https://github.com/stacks-network/runner-cleanup).
  The image is not stated, so INFERRED for 24.04. Docker images are not preinstalled on 24.04
  (rust-lang `free-disk-space-linux.sh`), so that part of the saving does not apply.
- Build environment: the bots build inside the WebKit Container SDK. The GTK release build log shows
  `WEBKIT_CONTAINER_SDK_ENABLE_AUTOENTER=1`, "Launching WebKit Container SDK wkdev-build 2.55-v3-a507ffd", `CXX=clang++`,
  and a private remote ccache (`CCACHE_REMOTE_STORAGE=http://wk-ccache-bazel.igalia.com...`) (MEASURED: build 49864
  steps `jhbuild` and `compile-webkit`, log via `api/v2/logs/<id>/raw`). The SDK tag is pinned in
  `.wkdev-sdk-version` (`2.55-v3-a507ffd` at `e1c510bc`; `2.53-v8-8a63f74` at 862f17d). The image is
  `ghcr.io/igalia/wkdev-sdk` (`Tools/Scripts/webkitpy/port/linux_container_sdk_utils.py:33-35@862f17d`), and
  auto-enter needs podman (`:59-85`). The Flatpak SDK is gone (`Tools/flatpak` is absent at 862f17d). CONFIRMED.
- Image size (MEASURED, registry manifest, anonymous pull token): `wkdev-sdk:2.55-v3-a507ffd` linux/amd64 = 33
  layers, **5.92 GB compressed**; INFERRED 15-20 GB unpacked, so freeing disk is required.
- Build from source: the GTK release build is about 12,015 ninja edges (MEASURED, last progress line of the bot log
  after `delete-WebKitBuild-directory`). With the bots' remote ccache it takes 3-9 min, and 40-60 min on a big
  change (MEASURED, 15 recent builds each of builders 41 and 6). Without that cache on 4 vCPU: INFERRED 2.5-4 h, and
  10-20 GB of build directory. ccache is picked up automatically by CMake
  (`Source/cmake/WebKitCCache.cmake:4-6@862f17d`), so `actions/cache` (10 GB) could chain jobs. All of this is moot,
  because the products are prebuilt (§1.3 table). They do not bundle their libraries (108 entries), so they must
  run inside the same `wkdev-sdk` tag. INFERRED.
- INFERRED workflow time for the prebuilt Linux route: pull the image (~6 GB, 3-6 min), fetch the zip (~1 min), run
  (~5 min).

## 3. Validity: are restyled-element counts port-independent?

- **The API.** `internals.lastStyleUpdateSize` (`Source/WebCore/testing/Internals.idl:971@862f17d`) returns
  `Document::lastStyleUpdateSizeForTesting()` (`Internals.cpp:4450-4455`). That value is set in
  `Document::resolveStyle` as `styleUpdate->size()` (`Source/WebCore/dom/Document.cpp:2914`).
  `Style::Update::size()` = `m_elements.size() + m_texts.size()` (`Source/WebCore/style/StyleUpdate.h:88`). An
  element enters the update when it gets a new style or has `display:none`
  (`Source/WebCore/style/StyleTreeResolver.cpp:1367-1368`). CONFIRMED. Caveats:
  - it counts **text nodes too**;
  - it keeps only the **last** resolver pass after interleaved layouts (`Document.cpp:2901-2914`);
  - it is overwritten on every recalc, so a frame with two recalcs loses the first. Read it together with
    `styleRecalcCount()` (`Internals.idl:970`, incremented at `Document.cpp:2936`): if the count moved by more than
    1 since the last read, the step is under-counted. INFERRED.
- Companions: `styleInvalidationTraversalCount` (`Internals.idl:972`); `layerFlushCount`, `compositingUpdateCount`,
  `renderingUpdateCount` (`:948,982,985`; implemented on `RenderLayerCompositor` and `Page`, `Internals.cpp:4422-4545`).
  CONFIRMED.
- **Correction to the README:** `UIHelper.renderingUpdate()` is `animationFrame()` followed by `delayFor(0)`
  (`LayoutTests/resources/ui-helper.js:187-191@862f17d`). It is not an exact one-update lock. Bracket each step
  with `renderingUpdateCount()`. CONFIRMED.
- **Shared engine.** `Style::TreeResolver`, the Adjuster and media-query evaluation are WebCore code shared by all
  ports. The port `#if` blocks in `Source/WebCore/style/*.cpp` are:
  - COCOA intrinsic margins on form controls (`StyleAdjuster.cpp:688-694`);
  - iOS site quirks for Google Maps, Netflix, Facebook, Claude and Amazon (`:1025-1043,1118-1125`);
  - iOS design-mode `text-size-adjust` (`StyleResolveForDocument.cpp:72-75`);
  - the WPE MatchedDeclarationsCache cap of 1,024 entries vs 16 K elsewhere (`MatchedDeclarationsCache.cpp:186-190`;
    a cache size, not a count). INFERRED: it does not change which elements restyle.
  - Text autosizing (iOS only) is turned off by WKTR on every port (`TextAutosizingEnabled false`,
    `Tools/WebKitTestRunner/TestOptions.cpp:145-146`), and so are `ContentChangeObserverEnabled` and async
    frame/overflow scrolling (`:87-88,93`). WKTR also sets mock scrollbars, an 800x600 view and Times/Helvetica font
    defaults on every port (`:127,232-234` and the font list).
  - CONFIRMED overall: under WKTR the style code path is the same across ports, apart from the listed quirks.
- **What differs by port, and its weight for the fastwork homepage scroll** (snapshot under `snapshot/site`):

| Difference | Source | fastwork impact |
|---|---|---|
| `hover`/`pointer` media: iOS reports coarse/none unless a mouse is the primary device. GTK reads GDK seat capabilities; WPE reads WPE display devices, and builds with touch events fall back to Touchscreen | `WebPageIOS.mm:4233-4255`, `WebPageGLib.cpp:228-257`, `UIProcess/glib/WebProcessPoolGLib.cpp:113-133`, `OptionsWPE.cmake:90`, `OptionsGTK.cmake:108` @862f17d | Low at phone width. Every JS and CSS use is OR-ed with `max-width` ≤ 860-1200 px (`2.DyWL8TcE.js`: `(max-width: 860px), (max-device-width: 500px), (hover: none) and (pointer: coarse) and (max-width: 1200px)`); one tooltip helper (`D313Dngs.js`) and one `@media (hover:hover)` in `DialogHeader.*.css` act only on hover or focus. MEASURED (grep) / INFERRED (impact) |
| `:hover` from a real pointer: GTK under Xvfb has a mouse seat; a fake mouse-move after scroll could restyle `:hover` rules (16 in `2.*.css`) | INFERRED | Must be checked: log `document.querySelectorAll(':hover').length` per step |
| `device-width` (screen size) differs: the sim screen vs the Xvfb/WPE headless screen | INFERRED | Low: OR-ed with width queries |
| Fonts and shaping (CoreText vs HarfBuzz/fontconfig): line breaks, heights, so which elements cross IntersectionObserver thresholds at a given `scrollTo` offset | INFERRED | Medium: shifts which step a reveal fires on; per-step counts can move by a whole section's worth of elements. Compare totals and anchor-aligned steps, not raw step indices |
| Viewport: iOS honours `<meta viewport>` only with `useFlexibleViewport` (`TestControllerIOS.mm:535`); GTK/WPE use the view size | CONFIRMED / INFERRED | Set `viewWidth`/`viewHeight` (`TestOptions.cpp:233-234,317-318`) identically on both |
| Compositing and flushing: RemoteLayerTree/CA vs coordinated graphics | ports differ | `layerFlushCount`, repaint rects and compositing counts are **port-specific**: never mix them |

- Net: the restyled-element count is engine-level and **INFERRED close to port-independent** for this page at 390 px
  with the WKTR defaults. Layer, flush and repaint counts are not. The iOS prebuilt avoids the question for the Q10
  term, which is why §4 does not lean on the proxy.

## 4. Recommendation

**(d) Prebuilt iOS-simulator WKTR, this Mac first, then GitHub `macos-26`. Drop the cloud-Mac rental.** Keep (b) only
as an optional cross-check.

| Option | Cost | Time to first count | Main risk |
|---|---|---|---|
| (a) cloud Mac, build from source | 1 day rental (24 h minimum common, INFERRED) | 1 day+ | build breaks on trunk/SDK |
| (b) GitHub Linux GTK/WPE prebuilt | 0 | ~0.5 day | proxy validity (§3), 6 GB image |
| **(d) iOS-sim prebuilt, local + `macos-26`** | **0** | **~2-4 h (INFERRED)** | webkitpy/SDK mismatch on this Mac (then use the runner) |

Next step (owner: measure-engineer, worktree; nothing pushed until the lead asks):
1. Pin `324039@main` / `e1c510bc` in `refs/upstream/sources.lock.yaml` as `webkit-trunk`. Sparse-clone `Tools/Scripts`,
   `LayoutTests/resources` and `.wkdev-sdk-version`. Download the **minified** iOS zip (315 MB) into a fresh dir under
   `.cache/` and verify its size against the `Content-Length` above. Unzip it to about 1 GB; ~3 GB total on disk
   (MEASURED free: 30 GiB).
2. Write one test page, `LayoutTests/fastwork-spike/scroll-counts.html`. It loads the fixture
   (http server from `run-webkit-tests` or 127.0.0.1) with header
   `<!-- webkit-test-runner [ viewWidth=390 viewHeight=844 useFlexibleViewport=true ] -->`. Per step it does
   `scrollTo`, then a rendering update, then reads `lastStyleUpdateSize`, `styleRecalcCount()`,
   `renderingUpdateCount()`, `layerFlushCount()`, `compositingUpdateCount()` and `:hover` count, and prints them as
   text.
3. Run `run-webkit-tests --ios-simulator --release --no-build --root <dir> --version 26.5 fastwork-spike` twice.
   Determinism means identical rows.
4. GitHub copy, only if the local run works or hits the SDK mismatch; branch `ci/wktr`, `workflow_dispatch` only:

```
jobs:
  wktr-ios:            # runs-on: macos-26 (free, 3 vCPU, 7 GB)
    steps: checkout (ours) -> sparse checkout WebKit@e1c510bc (Tools/Scripts, LayoutTests/resources)
           -> actions/cache key "wktr-ios-min-324039" path webkit-min.zip (315 MB; miss: curl from S3, ~1 min)
           -> unzip (~1 min) -> sudo xcode-select -s /Applications/Xcode_26.5.app
           -> run-webkit-tests ... --version 26.5 --device-type "iPhone 17"  (sim boot 1-3 min, test < 5 min)
           -> upload-artifact counts.json (KBs)          # total ~10-15 min, INFERRED
  wktr-wpe (optional cross-check): runs-on ubuntu-24.04, container ghcr.io/igalia/wkdev-sdk:2.55-v3-a507ffd
           after a disk-cleanup step; cache key "wktr-wpe-324039" for the 261 MB zip; same test page; ~15 min, INFERRED
```

5. Calibrate once: the same fixture through the Inspector lane (iOS 27.0 shipping) and WKTR (trunk). The README's
   "What it would not add" still holds, because counts come from trunk 324039, not shipping iOS 27.0.

## What this changes in the plan

- **§4.2 "WebKit element counts (decided now, Q10)", bullet 2:** replace "the 1-day WKTR spike runs on a rented cloud
  Mac at the start of M3: it needs about 120 GB free" with: the spike uses WebKit's public prebuilt iOS-simulator
  archive (minified, 315 MB, Xcode 26.5 / iOS 26.5 runtime). It runs on this Mac (iOS 26.5 runtime present), and on
  GitHub `macos-26` as the CI copy. No build, no rental, about 3 GB of disk. Since it no longer needs M3 hardware, it
  can move up to M1 (per the plan's own "if M1 ends early it moves up").
- **§12.2 Q10:** same change. Drop "needs about 120 GB free / 38 GB" as the blocker, and state that the counts come
  from a pinned trunk revision (324039@main), so a calibration run is needed.
- **Work graph:** `wktr-cloud` (owner user, rental) becomes `wktr-prebuilt` (owner measure-engineer, no user
  go-ahead needed, no deps), and `calibration` depends on it instead.
- **`packages/measure-webkit/README.md`, "Feasibility" section:** correct "There is no prebuilt"; it covers only
  `webkit.org/build-archives`. Also correct the `UIHelper.renderingUpdate()` "exactly one rendering update" claim
  (§3).

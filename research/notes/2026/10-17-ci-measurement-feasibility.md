---
id: 2026-10-17-ci-measurement-feasibility
kind: note
title: "Measurement on GitHub-hosted runners: Chromium counts lane yes (ubuntu-24.04-arm), WebKit Simulator lane possible on the xcode-27 preview image, timing and device stay local"
status: review
created: 2026-10-17
topics: [measurement, ci, github-actions, chromium, webkit, simulator, playwright, breakpoints]
---

Question: can the two counts lanes (PLAN §4.1) run on GitHub-hosted runners of a public repo, and what is gained?
Sources: `actions/runner-images` @ `ee1ff4569e381a9649b400338bdc8ceb7e18a80e` (sparse clone, 2026-10-16), Playwright
`v1.64.1` @ `cfe490d941f992655948eee8fd4fd94e1c4234bf`, Chromium @ `f842f52ef39f` (our pin), GitHub docs pages (URLs inline).
Local facts are from this repo at `aa7b729`.

## Answer in one table

| Lane | On GitHub runners? | Runner label | Status |
|---|---|---|---|
| Lean check + `fwcore` build | yes | `ubuntu-24.04-arm` (or x64) | INFERRED (plain build) |
| Chromium counts (container, BeginFrameControl) | **yes, as-is, on arm64 Linux only**; same binary, same base image | `ubuntu-24.04-arm` | CONFIRMED (inputs); determinism on the runner still to be MEASURED |
| Breakpoint gate, 124 loads per engine (Chromium + Playwright WebKit) | **yes, best fit for CI** (shard by load) | `ubuntu-24.04-arm` | INFERRED |
| WebKit counts, iOS Simulator 27.0 + `ios_webkit_debug_proxy` | **probably yes**, on the `xcode-27` preview image only (macOS 27.0.1, Xcode 27.0/27.1, iOS 27.0 runtime preinstalled) | `xcode-27` | CONFIRMED (image contents); runtime build and lane run to be MEASURED |
| Timing lane (headed Chrome ms, Simulator Timeline ms) | **no** (shared VMs, 3 vCPU M1, ms are not this host's or the phone's) | local | INFERRED |
| Device lane (iPhone) | **no** | local | CONFIRMED (needs the phone over USB) |

## 1. Chromium lane on Linux runners

- **Runners.** Public repos get `ubuntu-latest`/`ubuntu-24.04` (x64, 4 vCPU, 16 GB) and `ubuntu-24.04-arm` (arm64, 4 vCPU,
  16 GB) as standard (free) runners (CONFIRMED, https://docs.github.com/en/actions/reference/runners/github-hosted-runners;
  labels in `README.md` l.25-26 @ee1ff45). Docker Server 28.0.4 and Buildx are preinstalled on the arm64 image
  (`images/ubuntu/Ubuntu2404-Arm64-Readme.md` l.70-74 @ee1ff45, CONFIRMED).
- **Runs as-is on `ubuntu-24.04-arm`.** The Dockerfile pins a linux/arm64 base by digest and the `linux-arm64` headless-shell
  zip by sha256 (`packages/measure-chromium/Dockerfile` l.7-12, 28-29 @aa7b729, CONFIRMED). Our local Docker is also
  linux/arm64 (`docker version` → `linux/arm64`, kernel `6.10.14-linuxkit`, MEASURED). So the runner executes the **same
  browser bytes** and the same base image; only the kernel and the CPU (Neoverse vs Apple M) differ (INFERRED: neither
  enters counts, since BeginFrameControl and the clock shim make time virtual).
- **Not as-is on `ubuntu-latest` (x64).** The arm64 zip and the arm64 digest would need QEMU emulation (slow) or an x64
  variant (`chrome-headless-shell-linux64.zip`, a different binary with different Skia SIMD raster paths). Treat x64 as a
  separate `(engine, platform)` key, never pooled with arm64 (INFERRED). Recommendation: arm64 only.
- **BeginFrameControl.** Allowed on Linux headless; refused only on macOS (`target_handler.cc` l.62-65 @317846d579b2,
  CONFIRMED in PLAN §4.1). `--deterministic-mode` adds begin-frame control, run-all-compositor-stages-before-draw,
  disable-new-content-rendering-timeout, disable-image-animation-resync, disable-threaded-animation, disable-checker-imaging
  (`headless/lib/browser/command_line_handler.cc` l.36-54 @f842f52, CONFIRMED). No GPU is involved: the lane runs with
  `--disable-gpu`, software raster (`packages/measure-chromium/src/run.mjs` l.25-26, CONFIRMED). So no GPU dependence.
- **CPU dependence (one real one).** The renderer raster thread count is `NumberOfProcessors()/2`, clamped to [1, 4],
  unless `--num-raster-threads` is given (`content/browser/gpu/compositor_util.cc` l.405-437, `kMin/kMaxRasterThreads`
  l.49-50 @f842f52, CONFIRMED). Local Docker VM has 8 CPUs → 4 raster threads (MEASURED: `docker info` NCPU 8); the
  runner has 4 vCPU → 2. Our flags do not pin it (`run.mjs` l.25-29, CONFIRMED). Raster/decode counts are already only
  *stable* locally (handoff `meas-chromium.md`); a different thread count can change how `RasterTask`/`ImageDecodeTask`
  split across compositor windows (INFERRED). **Fix: add `--num-raster-threads=2` and `docker run --cpus=4` on both hosts.**
- **Wall-clock residue.** The 100 ms real-time network barrier per frame (`README.md` l.62-64 of the package) is the one
  place where host speed can still move counts: a slower runner could let an image decode cross a frame boundary
  (INFERRED). The class table (28 det / 14 stable / 8 quarantined) must be re-MEASURED on the runner; cross-machine
  agreement (local vs runner) is a stronger V-i result than three runs on one Mac.
- **Other risks.** Apt libraries are unpinned (package README l.42): the image id differs between hosts; build once in CI
  and push to GHCR by digest, or pin the apt snapshot (INFERRED). Runner image updates (the arm64 image is dated 20261004,
  readme l.11) do not touch our container contents (INFERRED). Each 503-frame run is about 85 s locally (MEASURED, handoff), so a job of
  a few runs fits easily in the 6 h job limit (CONFIRMED, https://docs.github.com/en/actions/reference/limits).

## 2. WebKit Simulator lane on macOS runners

- **Images and what they hold** (all arm64, 3 vCPU M1, 7 GB RAM, 14 GB SSD for public repos, CONFIRMED docs page above):

| Label | macOS | Xcode | iOS Simulator runtimes | Source @ee1ff45 |
|---|---|---|---|---|
| `macos-15` | 15.7.9 | 16.0-16.4 (default 16.4), 26.0.1-26.3 | 18.x, 26.0, 26.1, (26.2) | `macos-15-arm64-Readme.md` l.8, 157-165, 254-257 |
| `macos-26` = `macos-latest` | 26.6.2 | 26.0.1-26.6 (default 26.6) | 26.2, 26.4, 26.5 | `macos-26-arm64-Readme.md` l.8, 157-163, 222-224 |
| `xcode-27` (**preview**) | **27.0.1** | **27.0 (27A266a, default), 27.1 (27A9275, RC), 27.2 beta** | **iOS 27.0** (only) | `xcode-27-arm64-Readme.md` l.8, 158-160, 191; label `README.md` l.30 |

  CONFIRMED. Xcode 27.1 on the runner is build 27A9275, the same build as ours (`xcodebuild -version`, MEASURED).
  Only Xcode 27.0 gets a runtime (`install_runtimes: "default"`; 27.1 and 27.2 `"none"`,
  `images/macos/toolsets/toolset-xcode-27.json` l.12, 20, 28 @ee1ff45, CONFIRMED). macOS 15/26 images have **no iOS 27
  runtime**.
- **Is it our runtime build?** Ours is iOS 27.0 **24A434** (`xcrun simctl list runtimes`, MEASURED). The image installs
  "the default iOS runtime for Xcode 27.0" with `xcodebuild -downloadPlatform iOS` (`images/macos/scripts/helpers/
  Xcode.Installer.psm1` l.204-206 @ee1ff45, CONFIRMED); the readme does not print the build. That it is 24A434 is INFERRED;
  the first workflow step must check it and fail on mismatch.
- **Installing a pinned runtime.** The same helper installs exact builds with `xcodebuild -downloadPlatform iOS
  -buildVersion <build>` (l.210-213, CONFIRMED), so `-buildVersion 24A434` is the pin path; `xcodes runtimes install`
  (Xcodes 2.1.0 is on the image, readme l.85) is the alternative. Size about 7.7 GB per iOS runtime (local: 2 runtimes =
  15.4 GB, MEASURED), against 14 GB of runner SSD: tight. Time: INFERRED 5-15 min per job; avoid by using the preinstalled one.
- **`ios_webkit_debug_proxy`.** In homebrew/core, 1.9.2, bottles for `arm64_golden_gate` (macOS 27), `arm64_tahoe`,
  `arm64_sequoia`, `arm64_linux` (https://formulae.brew.sh/api/formula/ios-webkit-debug-proxy.json, CONFIRMED). Not
  preinstalled (absent from the toolset brew list, `toolset-xcode-27.json`, CONFIRMED), so `brew install` (bottle, about
  a minute, INFERRED). No phone is attached on a runner, and our config already writes phones with port -1.
- **Headless Simulator.** Our lane already boots with `simctl boot` and no Simulator.app, then reads the inspector socket
  of `launchd_sim` (`packages/measure-webkit/README.md` l.17, 27, CONFIRMED). The Simulator is a set of host processes,
  not a VM, so the "nested virtualization is not supported" limit of arm64 macOS runners
  (docs page above, CONFIRMED) does not apply to it (INFERRED). It does block Docker on macOS runners: no Docker is listed
  in any macOS readme (CONFIRMED by grep), which does not matter because the Chromium lane runs on Linux.
- **Device type.** `fw-iphone-27` is an iPhone 15 Pro Max; the image only pre-creates iPhone 17/18-class devices
  (readme l.191). `simctl create fw-iphone-27 "iPhone 15 Pro Max" …iOS-27-0` works locally with Xcode 27.1 27A9275
  (`research/notes/env-setup.md` l.53, CONFIRMED), so it should on the runner with the same Xcode (INFERRED).
- **Risks.** (a) `xcode-27` is a preview image: no SLA, weekly updates (`README.md` l.30, 74-77, CONFIRMED); the runtime
  may be swapped. (b) The WebKit lane has no virtual time: per-zone and per-step counts are already *quarantined* locally
  because the scroll and the page's timers are wall-clock-driven (handoff `meas-webkit.md`); on 3 slower vCPUs in a
  shared VM they will move more (INFERRED). Only `Composite`, `EventDispatch`, whole-run totals and the y ≥ 3000 layer
  census are candidates for CI. (c) The VM's GPU is paravirtualized; Simulator compositing and paint could differ from the
  local Mac (INFERRED). (d) Free plan: 5 concurrent macOS jobs (CONFIRMED, limits page).

## 3. Alternative engines

- **Playwright WebKit** (what PLAN §6.6 already uses for the 124-load gate): Playwright 1.64.1 ships WebKit revision 2370,
  `browserVersion` "27.2" (`packages/playwright-core/browsers.json` l.26-33 @cfe490d, CONFIRMED), built from WebKit `main`
  at `56453fdfe0b0ca6258c23e6453b34f70b885d13f` (`browser_patches/webkit/UPSTREAM_CONFIG.sh` l.3 @cfe490d, CONFIRMED),
  a trunk revision, not the iOS 27.0 branch 8625.1.29.x (INFERRED from the version scheme). On Linux it is the **WPE**
  MiniBrowser when headless and **GTK** when headed (`browser_patches/webkit/pw_run.sh` l.29-35, CONFIRMED); downloads exist
  for `ubuntu24.04-arm64` (`server/registry/index.ts` l.245, CONFIRMED). On macOS it is the Mac port; macOS 27 maps to the
  `mac26` build (`packages/utils/hostPlatform.ts` l.62-65, CONFIRMED).
- **Valid stand-in for Safari counts? No.** Linux WebKit composites with TextureMapper/coordinated graphics, not Core
  Animation; no iOS async scrolling (UIScrollView), no RemoteLayerTree, no Safari toolbar (775/815 resizes), no iOS
  "conservative" compositing policy (research 04 §4.5, 02 §7; INFERRED from port structure, as recorded there). Layer,
  paint and composite counts must not be pooled with Simulator counts. **Valid for**: breakpoint and visual parity (PL0-PL3),
  style/layout *existence* checks, and as a cheap second engine in CI.
- **Safari on macOS (`safaridriver`)**: the `xcode-27` image has Safari and SafariDriver 27.0.1 (22625.1.29.11.28)
  (readme l.88-89, CONFIRMED): the same 625.1.29 branch as the Simulator's 8625.1.29.10.29, a later point build (INFERRED).
  Still the Mac port: desktop compositing, no touch, no toolbar, no iOS viewport. WebDriver gives no Timeline. Useful as a
  "Safari engine, same branch" functional check; not a counts stand-in. The Simulator stays the only iOS-path engine
  short of the phone.

## 4. What CI improves and what stays local

| Gains from CI | Why |
|---|---|
| **124-load breakpoint gate per engine**, sharded (e.g. 8 shards × ~16 loads) | independent loads, ≤ 256 matrix jobs and 20 concurrent jobs on Free (CONFIRMED limits page) |
| **Chromium V-i determinism across machines** (N runs on N fresh VMs, compare) | a fresh VM per run, and a second host proves counts are machine-independent |
| **A/A and original-vs-rewrite Chromium counts** in parallel | frees the Mac (16 GB RAM, Simulator + Docker + agents) for timing and device work |
| **Lean `lake build` + golden-vector checks** on every push | clean environment, no local state |
| Optional: WebKit Simulator **totals** and the y ≥ 3000 census | same runtime family, but only after a local-vs-CI V-b check per count type |

| Stays local | Why |
|---|---|
| Device lane (iPhone 27.0.1) | USB phone, booked sessions (PLAN §4.1) |
| Timing lane (headed Chrome `PipelineReporter`, Simulator Timeline ms) | ms on shared 3-4 vCPU VMs are noise and not the target host (INFERRED) |
| Reference WebKit Simulator lane until CI agrees with it | runtime build and GPU path may differ (above) |
| WDA finger-drag profiles | need a UI session and are wall-clock-driven (INFERRED) |

## 5. Workflow sketch (outline, not committed)

```yaml
name: measure
on: { workflow_dispatch: { inputs: { profile: {default: swipe-v1}, runs: {default: '3'} } }, push: { branches: [main] } }
permissions: { contents: read }          # public repo: no pull_request_target, no secrets in measurement jobs
jobs:
  lean:
    runs-on: ubuntu-24.04-arm
    steps:
      - uses: actions/checkout@<sha>
      - uses: leanprover/lean-action@<sha>   # or elan-init.sh; toolchain from lean/lean-toolchain (v4.35.0)
        with: { lake-package-directory: lean }
      - run: cd lean && lake build && lake exe fwtest   # name per lakefile
      - uses: actions/upload-artifact@<sha>
        with: { name: fwcore-linux-arm64, path: lean/.lake/build/bin/fwcore }
  chromium-image:
    runs-on: ubuntu-24.04-arm
    steps: [checkout, "docker build -t fw-measure-chromium:1 packages/measure-chromium", "docker save | zstd > image.tar.zst", upload-artifact]
  chromium-counts:
    needs: [lean, chromium-image]
    runs-on: ubuntu-24.04-arm
    strategy: { fail-fast: false, matrix: { run: [a, b, c] } }   # or: shard: [0..7] for the 124-load gate
    steps:
      - checkout; download fwcore + image; docker load
      - run: ./scripts/snapshot-fetch.sh       # snapshot by snapshot.lock.json id + sha256 check (see "plan changes")
      - run: FW_SNAPSHOT_DIR=$PWD/snapshot/site node packages/measure-chromium/src/host.mjs --profile ${{ inputs.profile }} --label ${{ matrix.run }}
      - uses: actions/upload-artifact@<sha>
        with: { name: "chromium-${{ matrix.run }}", path: packages/measure-chromium/out/, retention-days: 30 }
  chromium-classify:
    needs: chromium-counts
    runs-on: ubuntu-24.04-arm
    steps: [download all chromium-*, "node packages/measure-chromium/src/classify.mjs out/*/counts.json", upload classes]
  webkit-sim:
    if: inputs.webkit == 'true'
    runs-on: xcode-27
    steps:
      - run: sudo xcode-select -s /Applications/Xcode_27.1.app
      - run: xcrun simctl list runtimes | grep -q '24A434' || exit 1   # or: xcodebuild -downloadPlatform iOS -buildVersion 24A434
      - run: brew install ios-webkit-debug-proxy
      - run: xcrun simctl create fw-iphone-27 "iPhone 15 Pro Max" com.apple.CoreSimulator.SimRuntime.iOS-27-0
      - run: FW_SNAPSHOT_SITE=$PWD/snapshot/site pnpm --filter @fw/measure-webkit determinism -- --runs 2
      - upload-artifact (packages/measure-webkit/out/)
```

Pull back locally: `gh run list -w measure`, then `gh run download <run-id> -D results/ci/<run-id>/` (each artifact
lands in its own directory; CONFIRMED by `gh run download --help`). Artifacts of a public repo are readable by anyone
(INFERRED): counts JSON only, never the trace dumps if they embed page source.

## Caveats the lead must decide

- **Publishing.** CLAUDE.md says the repo is private, only the user pushes, and no Fastwork code or assets go in git.
  The user reports approval from Fastwork to publish the source and the compiled site. CI needs the snapshot (61 MB,
  MEASURED `du`) inside the runner; the options are commit it, attach it as a release asset, or fetch it in the job.
  This is the user's rule change, not an agent decision.
- Third-party actions pinned by sha; `actions/checkout` with `persist-credentials: false` (INFERRED good practice).

## What this changes in the plan

- **§4.1 counts lane (Chromium):** add "runs locally or on `ubuntu-24.04-arm` (same arm64 image and binary); x64 runners
  are a separate platform key". Add `--num-raster-threads=2` and `docker run --cpus=4` to the pinned flags (§4.2 step 1)
  so local (8 CPU) and CI (4 vCPU) use the same raster thread count.
- **§4.6 Version skew row:** add the CI WebKit option: `xcode-27` preview image, iOS 27.0 runtime (build to be MEASURED
  against 24A434), Xcode 27.1 27A9275 matches local; counts from it are a separate `platform` until a V-b local-vs-CI check
  per count type passes.
- **§6.6 breakpoint gate:** run the 124 loads per engine (Chromium + Playwright WebKit 2370 on WPE) as a sharded CI
  matrix; the closing Simulator check stays local until the CI Simulator passes V-b.
- **§10.1 workstreams:** new item "ci-measure" (inputs: SPK-i done, a publishing decision for the snapshot, `--num-raster-threads`
  pin); first exit = Chromium V-i class table MEASURED on 3 runner VMs and equal to the local table.
- **§12 decisions:** add Q "publish the repo and the snapshot for CI?" (needs the user to amend the CLAUDE.md private-repo
  and no-Fastwork-assets rules).

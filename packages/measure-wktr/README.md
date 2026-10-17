# measure-wktr: WebKitTestRunner restyle counts on GitHub CI

Counts only. Nothing here is phone time (CLAUDE.md "Measure on CI"). Workflow: `.github/workflows/wktr.yml`.

## What it measures

WebKit's own test runner (WKTR, `WebKitTestRunnerApp`) from WebKit CI's prebuilt iOS-simulator archive loads the
ORIGINAL page (`snapshot/site`, served read-only) in an iOS 26.5 Simulator on a `macos-26` runner. The page script
scrolls the page in steps and records, per step, WebKit's `internals` counters, which Safari and the Web Inspector do
not expose:

| count type (per scroll step) | meaning |
|---|---|
| `styleUpdateSizeSum` | sum over the step's frames of `internals.lastStyleUpdateSize`, taken only in frames where `styleRecalcCount` moved. Counts elements AND text nodes that got a new style (`Style::Update::size`). |
| `lastStyleUpdateSize` | the raw value read at the step's end (stale when the last frame had no recalc) |
| `styleRecalcs` | `styleRecalcCount()` delta |
| `undercountedRecalcs` | recalcs whose size was overwritten before it could be read (see Limits) |
| `renderingUpdates` | `renderingUpdateCount()` delta; brackets the step |
| `layerFlushes`, `layoutUpdates`, `compositingUpdates`, `styleInvalidations` | deltas of the matching trackers |

Classes come from fwcore (Lean `Fw.Measure.classify`, mode `frames`, kMax 4, tMax 24) via
`packages/measure-chromium/src/classify.mjs`. This package decides nothing.

## Method

- **Archive.** `src/archive.json` pins WebKit CI revision r324039 (commit e1c510bc, Xcode 26.5, iOS 26.5; 315 MB; size
  and sha256 checked). `scripts/fetch-archive.sh` downloads it into an empty directory and extracts it there. The
  archive is cached with `actions/cache` (key = revision + hash of `archive.json`) by the `archive` job. Nothing is
  committed.
- **No webkitpy.** `src/wktr.mjs` speaks WKTR's iOS socket protocol directly: launch with `xcrun simctl launch
  org.webkit.WebKitTestRunnerApp --no-timeout ... -`, environment through `SIMCTL_CHILD_*` (DYLD paths point at the
  archive), accept the app's 3 connections (stdin, stdout, stderr), write `url'--additional-header'useFlexibleViewport=true`,
  read to `#EOF\n#EOF\n`. Cited at WebKit@862f17d (the pinned clone; the archive is e1c510bc and the files were
  checked unchanged where it matters):
  `Tools/TestRunnerShared/IOSLayoutTestCommunication.cpp:51-78`, `Tools/Scripts/webkitpy/port/simulator_process.py:98-118`,
  `webkitpy/port/driver.py:615`, `webkitpy/xcode/simulated_device.py:716`, `Tools/WebKitTestRunner/TestFeatures.cpp:392`,
  `Tools/WebKitTestRunner/TestInvocation.cpp:258-269,333`, `Tools/WebKitTestRunner/ios/TestControllerIOS.mm:535`.
- **Harness injection.** The site's CSP allows only `'self'` scripts, so `src/server.mjs` serves a temp copy of
  `index.html` with `<script src="/__fw/harness.js">` as the first child of `<head>`. The snapshot is never written.
  The harness starts with the same pinned clock and seeded random as `measure-webkit` (`bootstrapSource`).
- **Scroll loop** (`src/harness.mjs`). After `load` plus a settle time, start the trackers, two idle frames, then for each
  step k: in a native `requestAnimationFrame` callback sample the counters, then `scrollTo(0, y_k)`; sample once per
  following frame (`frames`, default 2); the next step's first sample closes the window. `scrollY` is never read inside
  the loop (`LocalDOMWindow::scrollY` forces a layout update); the requested positions are recorded, the real one is read
  once at the end.
- **Internals relied on** (`Source/WebCore/testing/Internals.cpp` and `.idl` at e1c510bc, the archive's commit):
  `startTrackingStyleRecalcs` 4637, `styleRecalcCount` 4647, `lastStyleUpdateSize` 4656 (attribute, IDL 1006, returns
  `Document::lastStyleUpdateSizeForTesting`), `styleInvalidationTraversalCount` 4664, `startTrackingLayerFlushes` 4618 /
  `layerFlushCount` 4628, `startTrackingLayoutUpdates` 4678 / `layoutUpdateCount` 4688, `startTrackingCompositingUpdates`
  4752 / `compositingUpdateCount` 4762, `startTrackingRenderingUpdates` 4771 / `renderingUpdateCount` 4781.
  `lastStyleUpdateSize` is the size of the LAST `resolveStyle` only (`Document.cpp:2914@862f17d`), so it is read once
  per rendering update.
- **Passes.** Each job runs the original `passes` times (default 2), each in a fresh `WebKitTestRunnerApp` process on one
  simulator device, and the workflow runs 3 independent jobs (separate macOS VMs). Output per job: `counts-<p>.json`
  (schema `fw.wktr.scroll/1`: `meta` + `frames[{n, phase:'scroll', scrollY, counts}]`), `raw-<p>.txt`, `stderr-<p>.txt`,
  `runner.json`, `tools.txt`, `run.log`. The `classes` job writes `classes-all.*` (all passes of all jobs) and
  `classes-<job>.txt` (a job's passes alone).

## Run

CI: `git push origin ci/wktr-local` or run the workflow by hand (inputs: `jobs`, `passes`, `step`). Then
`gh run view <id>` and `gh run download <id>`.

Local debug only (one short run, under `sh scripts/sim-lock.sh acquire <you>`; a result from this Mac is never reported):

    sh packages/measure-wktr/scripts/fetch-archive.sh .cache/wktr-zip .cache/wktr-root
    node packages/measure-wktr/src/cli.mjs run --root .cache/wktr-root/Release-iphonesimulator \
      --site snapshot/site --out .cache/wktr-out --passes 1 --step 400 --settle 2000 --keep

The first `simctl launch` on a fresh device can take 100 s or more when the Mac is loaded; the driver waits 120 s for the
sockets.

## Limits

- **The viewport is the device screen, not the 390 x 844 phone profile.** `useFlexibleViewport=true` gives
  innerWidth 402 and dpr 2 on the iPhone 17 simulator (MEASURED locally); `viewWidth`/`viewHeight` in the header do not
  apply with a flexible viewport. Counts are comparable only inside this lane, not with the Chromium or Inspector lanes.
- **Recalcs per frame can exceed 1.** `lastStyleUpdateSize` keeps only the last recalc of an interval. Locally
  `styleRecalcCount` moved by far more than `renderingUpdateCount` (131 vs 28 in a coarse run), so `styleUpdateSizeSum`
  is a lower bound and `undercountedRecalcs` says by how many recalcs. A hooks mode that wraps the update to recover
  every recalc's size is the follow-up.
- `lastStyleUpdateSize` counts text nodes as well as elements.
- Wall time in the logs is the runner's, never phone time. Simulator launch time varies with runner load.
- macOS runner minutes are billed at a multiple (10x for macOS on private repos); the archive is cached so a job only
  extracts and runs.
- WebKit trunk revisions: archive e1c510bc vs the pinned source clone 862f17d. The Internals functions used exist in
  both; the run itself proves the archive has them (the harness reports missing trackers in `meta`).

## Results

See the section appended after the CI runs (stable vs quarantined per count type).

## TS stand-ins (CLAUDE.md "Lean first")

`src/reduce.mjs` (interval sums, deltas, output parsing) is pure counting arithmetic with no Lean spec and no golden
vectors yet; `test/wktr.test.mjs` pins its behaviour meanwhile. Classification is Lean's.

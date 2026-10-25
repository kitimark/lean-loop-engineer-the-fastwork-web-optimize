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

- **Archive (nothing is built).** WebKit's CI builder `Apple-iOS-26-Simulator-Release-Build` uploads a minified archive of
  every revision to the public bucket `minified-archives.webkit.org` (`Tools/CISupport/build-webkit-org/steps.py:58-59,485-491@862f17d`,
  builder at `config.json:425`; testers fetch the full archive with an unauthenticated `curl --fail`,
  `Tools/CISupport/download-built-product:54@862f17d`; CONFIRMED). `webkit.org/build-archives` lists macOS only, so a
  prebuilt iOS-Simulator WebKitTestRunner is easy to miss, but it exists. `src/archive.json` pins WebKit CI revision r324039
  (commit e1c510bc, Xcode 26.5, iOS 26.5; 315 MB; size and sha256 checked; url
  `https://s3-us-west-2.amazonaws.com/minified-archives.webkit.org/ios-simulator-26-x86_64-arm64-release/324039%40main.zip`). `scripts/fetch-archive.sh` downloads it into an empty directory and extracts it there. The
  archive is cached with `actions/cache` (key = revision + hash of `archive.json`) (the first job downloads it, later jobs restore it; the jobs run one at a time). Nothing is
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
  once at the end. The loop does not use WebKit's `UIHelper.renderingUpdate()`: that helper is one rAF callback followed by
  one `setTimeout(0)` (`LayoutTests/resources/ui-helper.js:182-191@862f17d`, CONFIRMED), not a single rendering update.
  How many rendering updates a step spans is read from `internals.renderingUpdateCount` (`renderingUpdates` above).
- **Internals relied on** (`Source/WebCore/testing/Internals.cpp` and `.idl` at e1c510bc, the archive's commit):
  `startTrackingStyleRecalcs` 4637, `styleRecalcCount` 4647, `lastStyleUpdateSize` 4656 (attribute, IDL 1006, returns
  `Document::lastStyleUpdateSizeForTesting`), `styleInvalidationTraversalCount` 4664, `startTrackingLayerFlushes` 4618 /
  `layerFlushCount` 4628, `startTrackingLayoutUpdates` 4678 / `layoutUpdateCount` 4688, `startTrackingCompositingUpdates`
  4752 / `compositingUpdateCount` 4762, `startTrackingRenderingUpdates` 4771 / `renderingUpdateCount` 4781.
  `lastStyleUpdateSize` is the size of the LAST `resolveStyle` only (`Document.cpp:2914@862f17d`), so it is read once
  per rendering update.
- **Variants** (`--variants`, workflow input `variants`; the name is the file prefix `counts-<variant>-<pass>.json`):
  `live` is the engine's own clock with Date pinned and Math.random seeded; `vt` replaces the page clock (`src/vtime.mjs`):
  `performance.now`, `Date`, `requestAnimationFrame` timestamps, `setTimeout`/`setInterval`/`requestIdleCallback` all run on
  one virtual clock that advances 1000/60 ms per native animation frame, so the page's own timers, springs and countdowns
  see the same time in every pass (the native rAF still drives the frames; nothing is seeked). Flags, in this order:
  `-warm` (scroll the page once first so lazy loads are done), `-still` (DIAGNOSTIC: `internals.suspendAnimations()`
  before the run, so CSS animations and transitions stop; the counts then exclude animation work), `-trace` (event
  counters `ev_*` for cause attribution, added to the count types).
- **Passes.** Each job runs every variant `passes` times (default 3), each in a fresh `WebKitTestRunnerApp` process on one
  simulator device, and the workflow runs `jobs` independent jobs (separate macOS VMs, one at a time). Output per job:
  `counts-<variant>-<p>.json` (schema `fw.wktr.scroll/1`: `meta` + `frames[{n, phase:'scroll', scrollY, counts}]`),
  `raw-*.txt`, `stderr-*.txt`, `runner.json`, `tools.txt`, `run.log`. The `classes` job writes
  `classes-<variant>-all.{txt,json}` (all passes of all jobs), `classes-<variant>-<job>.txt`, `run.txt`, `runners.jsonl`,
  `sha256.txt`.
- **Frozen classes** (`src/freeze.mjs`, `classes.frozen.json`). A type's signed class is its worst class over 3 workflow
  runs (separate CI runs, separate macOS VMs), decided by fwcore `measure.freeze` (Lean `Fw.Measure.Freeze`). The script
  only reads downloaded run directories, re-derives each run's classes with fwcore `measure.classify` and refuses a run
  whose own `classes-<variant>-all.json` differs. `--check` verifies the committed file.

## Run

CI: `git push origin ci/<task>` or run the workflow by hand (inputs: `jobs`, `passes`, `variants`, `step`). Then
`gh run view <id>` and `gh run download <id> --dir runs/<id>`. Freeze: `node src/freeze.mjs runs/<a> runs/<b> runs/<c>`
(`--check` to verify).

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

## Why the counts drift (answer first)

**Mostly a harness issue and fixable; a residue is inherent. WKTR gives a gateable class (deterministic) on rendering updates and layer flushes, and under `vt` a stable one on style invalidations; (MEASURED) quarantined classes for everything that reflects the page's style work.** So it is a findings lane, not a gate lane, in the 3-day plan (`classes.frozen.json` tags those three types `role: gate` and the other six `role: finding`; runs 39054209180, 39058900156, 39061993891).

Chain of evidence (all MEASURED on `macos-26`, exploratory run 39050685079 and 39051976631 and 39053133940, 3 passes each,
and the three signed runs below):

1. **Several style recalcs per rendering update are structural, not noise.** `Document::resolveStyle` counts one
   `styleRecalcCount` per run (`Document.cpp:3003@e1c510bc`), and `Page::updateRendering` (`Page.cpp:2476`) calls
   `layoutIfNeeded` at 2500, 2581 and 2647 and runs script steps in between (animation frame callbacks 2573, resize
   observations 2583, intersection observations 2609), each of which can dirty style again; script reads add more. About
   5-7 recalcs per step against 2 rendering updates is the shape, and it repeats.
2. **What changes the count is time-based work.** With the engine's own clock (`live`) styleRecalcs differ in about 70 of
   104 steps between passes. Putting the page clock on a virtual one (`vt`: rAF timestamps, `performance.now`, `Date`,
   timers all advance 1000/60 ms per native frame) cuts that to k 17 (k 25 in the trace variant), and the `-trace` counters show every
   page-clock source is then identical per frame between passes (rAF 843, timers 19, IntersectionObserver 42 callbacks,
   ResizeObserver, scroll events: zero differing frames).
3. **CSS animations and transitions run on the engine's real clock, not the page's.** In the trace run the events that
   still differ between passes are exactly `animationstart/iteration/end` (sums 50/49/49, 98/87/95, 41/39/39) and
   `transitionend` frame placement. Cited at WebKit@862f17d: `AnimationTimelinesController.cpp:118-130` caches the current
   time from the real rendering-update timestamp and `:330-333` `liveCurrentTime` is `window()->nowTimestamp()`. A
   JavaScript shim cannot move it. Diagnostic `-still` (`internals.suspendAnimations`, `Internals.idl:577@862f17d`) removes
   the events entirely (all `ev_animation*`/`ev_transition*` zero, `ev_animActive` identical) and styleRecalcs drops to
   about 8 to 15 differing steps (k 8 in the 3-pass run, 14 and 17 in the 6-pass signed runs).
4. **The residue is a +-1 phase shift, plus extra layouts.** With vt + still, styleRecalcs per pass sum to 498/501/503
   (about 1 %); steps differ by at most 1, as the same recalc lands one sampled frame earlier or later. layoutUpdates
   and compositingUpdates still differ by several per step (sums 353/366/374), with every observable event identical, so the
   cause is not visible to the page: INFERRED to be work that arrives from outside the page clock (UI-process messages,
   image decode and network arrival, display timing). Not attributed further. Warming (`-warm`) did not remove it (vt-warm-still-trace: layoutUpdates k 35, styleRecalcs k 21).
5. **One more structural drift.** One of 18 `vt-still` passes laid the page out 60 px shorter (docH 5903 vs 5963 in the
   other 53 passes), giving 103 steps; fwcore `measure.freeze` refuses mixed frame counts, so `vt-still` is not frozen.

What WKTR can still deliver: `renderingUpdates` and `layerFlushes` deterministic (they are driven by the harness),
`styleInvalidations` stable under `vt`, and everything else as quarantined findings with the per-step shape; totals per
pass are close (styleRecalcs within about 1 % under vt+still) but per-step values are not signed.

## Results

MEASURED on `macos-26`, original page, 104 scroll steps of 50 px, `jobs=2`, `passes=3`, variants `live,vt,vt-still`,
separate workflow runs 39054209180, 39058900156, 39061993891 (commit 82b0495 of branch `ci/wktr-ci-lane`, each run on its
own macOS VMs, one at a time). Classes are fwcore `frames` mode, kMax 4, tMax 24. Signed (frozen) classes are the worst
class over the 3 workflow runs (`classes.frozen.json`, fwcore `measure.freeze`); image id =
archive sha256 / iOS runtime build (23F77). Each workflow run's own table is over its 6 passes.

| count type | live (frozen) | vt (frozen) | vt-still per run (not frozen) |
|---|---|---|---|
| `renderingUpdates` | deterministic | deterministic | deterministic |
| `layerFlushes` | deterministic | deterministic | deterministic |
| `styleInvalidations` | quarantined (k 32) | **stable** (k 3, t 13) | quarantined (k 12) |
| `styleRecalcs` | quarantined (k 78, t 30) | quarantined (k 31, t 42) | quarantined (k 17 / 14 / 14) |
| `undercountedRecalcs` | quarantined (k 78) | quarantined (k 31) | quarantined |
| `styleUpdateSizeSum` | quarantined (k 85) | quarantined (k 30) | quarantined |
| `lastStyleUpdateSize` (raw) | quarantined (k 47) | quarantined (k 26) | quarantined |
| `layoutUpdates` | quarantined (k 86) | quarantined (k 80) | quarantined (k 57 / 56) |
| `compositingUpdates` | quarantined (k 69) | quarantined (k 60) | quarantined |

- `live` = 2 deterministic, 7 quarantined; `vt` = 2 deterministic, 1 stable, 6 quarantined (frozen, 3 workflow runs).
- `vt-still` is not frozen: `measure.freeze` refused it because one of its 18 passes had 103 frames (docH 5903).
  `freeze.mjs --variants live,vt` signs the other two. The still variant is a diagnostic (it removes animation work from
  the counts), not a result for the page as shipped.
- Under `vt`, per-step values are still not reproducible, but `vt` is a strict improvement on `live` in every type
  (styleRecalcs k 78 to 31, styleInvalidations quarantined to stable).
- The `attempts` field in each counts file's `meta` records launch retries (`#CRASHED - com.apple.WebKit.GPU.Development`
  at launch once on a runner in an earlier run; the driver retries up to twice).
- Wall time: the 1-job, 12-pass exploratory run took 13m54s; queueing for a macOS runner was the longer part when other jobs ran. Never phone time.

## Toolbar forced-inset gate (task toolbar-wktr-gate)

A gate, not a count lane. `[toolbar]` in the head commit (or the `toolbar` dispatch input) turns the `wktr` job's measuring step into:

1. `scripts/hook-check.sh`: do `beginInteractiveObscuredInsetsChange`, `endInteractiveObscuredInsetsChange` (`UIScriptControllerIOS.mm:1486-1494`) and
   `setObscuredInsets` (`UIScriptControllerCocoa.mm:683-692`, @862f17d) exist in the pinned binary (`hooks.json`).
2. `src/toolbar-cli.mjs`: per flag (`default`, `touch-first`, `open-once`, `unthrottle`) and pass one fresh WebKitTestRunnerApp process loads
   `src/toolbar-page.mjs`'s page, which calls `begin`, then `setObscuredInsets(inset,0,0,0)` for inset 10, 20, 30, 40, 30, 20, 10, 0 with a
   `scrollTo` before each, then `end`. It reports `typeof uiController.<hook>` (the hook is bound in the running WKTR), the viewport height,
   a fixed platform stand-in's rect and the time from each set's return to the first frame that sees the new height.
3. `src/gate.mjs`: the verdict against the Lean golden `packages/contracts/golden/parts/morph-mount-toolbar.gate.jsonl`
   (`Fw.Parts.MorphMountToolbar`, `gate*` rows): the arm sequence of each phase (production `armed`), the take sequence of each flag
   (production gesture `step`, looked up in the golden `gateRun` rows), and the unthrottle exemption (median wait of the sets after the first
   below `liftedBelowMs`, Lean `liftedBy`, exempt iff the flag is `unthrottle`).

Limits: `setObscuredInsets` is applied step-wise (each set returns after the UI process applied it), not once per frame; `lvh`/`svh` are not
overridden in WKTR, so viewport-unit values differ from Safari and the gate reads none; WKTR is not Safari and has no real toolbar; waits are in ms
of a free shared macOS runner, never phone time. TS stand-ins: `liftedBy` (one comparison, `test/toolbar.test.mjs` checks it against the golden
rows) and the page/driver glue.

## TS stand-ins (CLAUDE.md "Lean first")

- `src/reduce.mjs` (interval sums, deltas, the undercount arithmetic, output parsing, `ev_*` zero-filling) is pure
  counting arithmetic with no Lean spec and no golden vectors yet (the Lean ops of the write list are fwcore's, outside
  this package); `test/wktr.test.mjs` and `test/variants.test.mjs` pin it meanwhile. Every classification decision is
  fwcore's: `measure.classify` per run, `measure.freeze` for the signed table.
- `src/freeze.mjs` only reads files, groups counts by variant, hands them to fwcore and checks that the raw input facts
  agree (archive, runtime, harness parameters, viewport); it needs an fwcore with the `jobs` field of `measure.freeze`.
- `src/vtime.mjs` is page-side glue (a clock), with no decisions.

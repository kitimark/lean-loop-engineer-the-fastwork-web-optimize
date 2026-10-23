# @fw/measure-chromium

Counts lane, Chromium arm (PLAN 4.1-4.2). Raw per-frame work counts of the ORIGINAL page from Playwright's linux-arm64
`chromium-headless-shell` (Chrome Headless Shell 156.0.8078.4 = playwright-core 1.64.1, build v1248) in a Docker
container, with `HeadlessExperimental.beginFrame` stepping. Counts are work, not milliseconds; nothing here is phone
time. Chromium refuses BeginFrameControl on macOS (`headless/lib/browser/protocol/target_handler.cc` l.62-65
@317846d579b2), hence the container.

## Run it

Needs Docker Desktop (running) and the local snapshot (`snapshot/site` in the main checkout, found through
`git rev-parse --git-common-dir`; override with `FW_SNAPSHOT_DIR=/path/to/site`). The snapshot is mounted read-only and
never copied.

```
cd packages/measure-chromium            # or from the repo root, with pnpm:
pnpm --filter @fw/measure-chromium count -- --profile swipe-v1 --label a
node src/host.mjs --profile swipe-v1 --label a                 # same thing without pnpm
pnpm --filter @fw/measure-chromium determinism                 # two runs (det-a, det-b) and the comparison
node src/compare.mjs out/swipe-v1/a/counts.json out/swipe-v1/b/counts.json [--show type1,type2]
node src/classify.mjs out/swipe-v1/a/counts.json out/swipe-v1/b/counts.json [more] [--kMax 4] [--tMax 24]  # classes, from fwcore
node --test test/pure.test.mjs test/fwcore.test.mjs           # extraction unit tests + fwcore golden conformance (no Docker)
pnpm --filter @fw/measure-chromium build:image                 # or: docker build -t fw-measure-chromium:1 .
```

The first run builds the image `fw-measure-chromium:1` (about 2 min; downloads the browser zip, verified by sha256).
Output: `out/<profile>/<label>/counts.json` (gitignored), then the host writes `zones.json` next to it from `fwcore`
(`measure.zoneSums`; needs `cd lean && lake build`, exit code 3 if it is missing). `--dump-trace` also keeps the raw
trace (about 50 MB).
A run takes about 85 s of wall time (503 frames; 100 ms real-time grace per frame, see below). Wall time is printed to
stderr only and never enters `counts.json`.

## What is pinned

| Thing | Pin |
|---|---|
| Base image | `node:24-bookworm-slim@sha256:a5f4366e...daee5` (linux/arm64, Node 24.22) |
| Browser | `chrome-headless-shell-linux-arm64.zip` 156.0.8078.4, sha256 `81ab9d4d3c30...c476` |
| Driver library | `puppeteer-core@25.14.0` over CDP |
| Fonts | one system package, `fonts-liberation` 1:1.07.4-11, in one directory (`docker/fonts.conf`, Lean `Fw.Measure.Profile.fontsConf`); `run.mjs` refuses a container whose `fc-list` lacks its families and records them in `meta.systemFonts`. Webfonts come from the snapshot (Google Sans latin/thai, Fastwork, Playpen). Counts taken before this change (no `meta.systemFonts`) came from an image with no system font |
| Network | every host except 127.0.0.1 is unresolvable (`--host-resolver-rules`); the page is served by `src/server.mjs`, which records the sha256 of every file it sent (`meta.servedSha256`) |
| Apt libraries | all 212 packages pinned: dated snapshot.debian.org mirror (SNAP=20261016T000000Z) + `docker/apt-manifest.txt`; the build fails if dpkg differs from the manifest (`node src/pin-apt.mjs`). npm: `docker/driver/package-lock.json` (`npm ci`) |

## One virtual frame (src/run.mjs)

1. Chrome flags: `--enable-begin-frame-control --deterministic-mode --run-all-compositor-stages-before-draw
   --disable-gpu` (software raster), `--font-render-hinting=none`, `--force-color-profile=srgb`. Page created with
   `Target.createTarget({enableBeginFrameControl:true})`. Viewport 430x932, DPR 3, mobile, touch, Asia/Bangkok, en-US.
2. Clock shim (`src/clock-shim.js`, before any page script): virtual `Date` (pinned to 2026-10-01T00:00:00+07:00),
   `setTimeout/setInterval/requestIdleCallback`, `performance.now`, seeded `Math.random` (mulberry32).
   `requestAnimationFrame` stays native and fires inside the rendering steps. **One deliberate deviation:** the
   timestamp argument handed to rAF callbacks is the virtual frame time. The native value is ticks minus the document's
   time origin, which differs from run to run and, in a first run, was not on the same clock as the virtual
   `performance.now()` (pages that compute `ts - performance.now()` saw hours of elapsed time and ended their
   animations at once: 2040 rAF callbacks instead of the real 2459).
3. Load: no frame is sent until the navigation commits (the document's virtual clock starts at 0 on its first frame).
   Frames are then pumped until `readyState` is complete, fonts are loaded and the server has no request in flight
   for 30 frames. Then virtual time jumps to 20000 ms, so the profile starts at the same virtual time whatever the
   number of load frames, followed by 60 pre-roll frames. None of these are recorded.
4. Per recorded frame n: `console.timeStamp('F<n>')`, `__fw.advanceTo(t)` (due timers fire), `window.scrollTo` to the
   profile's position, `HeadlessExperimental.beginFrame({frameTimeTicks})`, then `Performance.getMetrics` deltas.
   After the frame, a **network barrier**: 100 ms of real time (`FW_BARRIER_MS`), then wait until the server has had no
   new request and none in flight for 40 ms. This makes lazy-image and decode completions land between frames, not in
   a racy one.
5. The trace (`Tracing`, categories in `src/trace.mjs`) is bucketed per frame: main-thread events by the `F<n>` marks,
   compositor events by `Scheduler::BeginImplFrame` (exactly one per BeginFrame), worker tasks by the compositor
   window they started in. Raster and decode tasks are also kept as run totals (`runLevel`).

Profile `profiles/swipe-v1.json`: 10 rest frames, then 10 CSS px per frame from the top to the page end (4626 px), 30
tail frames (503 frames at 60 Hz); zones of 500 px. This is v1's scripted swipe (scrollTo 10 px per rAF), not a touch
fling. A programmatic `scrollTo` also fires Chromium's hover recompute (see HitTest below).

## Output schema `fw.counts/1`

`counts.json`: `meta` (browser, image id, snapshot id, served-bytes hash, viewport, page height, start date), `frames`
(array of `{n, phase, scrollY, vt, counts:{type:number}}`), `runLevel` (run totals of worker-thread tasks). Plain JSON,
no wall-clock values, so equal runs are equal bytes. `zones.json` (`fw.zones/1`, written by the host from fwcore): per
500 px zone `id`, `frames`, `scrolledPx`, `firstFrame`, `lastFrame`, sums per type (Lean `Fw.Measure.zoneSums`; the same
values the former TS reducer stored under `zones`, checked on three 503-frame runs).

Count types: `hasDamage`; `metric.*` (Performance.getMetrics deltas: LayoutCount, RecalcStyleCount, Nodes,
LayoutObjects, JSEventListeners, Documents, Frames, Resources); `trace.*` (UpdateLayoutTree and `.elementCount`, Layout
and `.dirtyObjects/.totalObjects/.partial`, InvalidateLayout, ScheduleStyleRecalculation, PrePaint, Paint, PaintImage,
Layerize, Commit, UpdateLayer, Layer.created/deleted, ScrollLayer, CullRectUpdate, ResizeObserverNotify,
IntersectionObserverCompute, HitTest, FireAnimationFrame, RequestAnimationFrame, FunctionCall, EvaluateScript,
EventDispatch, TimerFire, ResourceSendRequest, ParseHTML, MinorGC, MajorGC, Animation.begin/instant/compositeFailedBits,
RasterTask, DisplayItemListRaster, ImageDecodeTask, DecodeImage, cc.Activate/Commit/Draw/SynchronizeTrees).
Not collected yet: raster-invalidation rects and the layer census (C8, C11 in research 03). Paint area is not
collected on purpose (the `Paint` clip is the cull rect, 03 section 5.3). With `--deterministic-mode` compositor
animations are disabled, so `compositeFailed` bits describe a main-thread run; compositor status needs the
free-running census.

## Determinism (3 runs, same machine, same image, same snapshot)

Method: runs a, b, c compared per count type and frame (`src/compare.mjs`). The files are NOT byte-identical (the
GC-dependent types below differ). Classes proposed here, for the lead to confirm:

| Class | Count types | Evidence |
|---|---|---|
| **deterministic** (0 differing frames in a-b and a-c) | hasDamage, metric.RecalcStyleCount, metric.JSEventListeners, trace.UpdateLayoutTree, ScheduleStyleRecalculation, Layerize, Commit, ScrollLayer, FireAnimationFrame, RequestAnimationFrame, FunctionCall, EvaluateScript, EventDispatch, IntersectionObserverCompute, ResizeObserverNotify, CullRectUpdate, PaintImage, ParseHTML, ResourceSendRequest, Layer.created, ImageDecodeTask, DecodeImage, Animation.begin/instant/compositeFailedBits, cc.Activate/Commit/Draw | identical in every frame |
| **stable** (a few frames differ by one frame of shift; run and zone totals equal or within a few) | metric.LayoutCount, trace.Layout and its three sums, InvalidateLayout, PrePaint, Paint, UpdateLayer, cc.SynchronizeTrees, RasterTask, DisplayItemListRaster, UpdateLayoutTree.elementCount | 1-4 frames of 503 differ (mostly 476/477, the end of the page; and 217, 262), by 1-4 units; totals within 1 except Paint (3) and elementCount (up to 24 of 48 300) |
| **quarantined** | trace.HitTest (98-119 frames differ by 1; totals 997-1001); GC-bound: metric.Nodes, LayoutObjects, Documents, Frames, Resources, trace.Layer.deleted, MinorGC, MajorGC | HitTest: the hover recompute after each scrolled frame plus one conditional extra hit test inside Commit; GC: collection timing, not page work |

"Deterministic" here means identical in every frame in a-b and a-c; "stable" means it was not, but differs only by shifts.

Two noise sources found and removed: (1) rAF timestamps on a different clock than `performance.now` plus a
per-run time origin; (2) timer phases shifted by the number of frames the browser spent before navigation commit.
Remaining sources: asynchronous image decode and iframe parsing finishing relative to frame boundaries (a 25 ms barrier
left clusters of 35 PaintImage / 19 RasterTask moving one frame; 100 ms removed them in these runs), hover and GC.

Classes are decided by fwcore (`measure.classify`, mode `frames`; Lean `Fw.Measure.Classes`): deterministic = no frame
differs in any pair of runs; stable(k, t) = at most k frames differ and totals differ by at most t, with k <= kMax and
t <= tMax; quarantined otherwise. On the three runs above with kMax 4, tMax 24 it gives 28 deterministic, 14 stable,
8 quarantined; it differs from the hand table in three places: `UpdateLayoutTree.elementCount` is quarantined (38
differing frames), `metric.Frames` and `metric.Resources` are stable (2 frames, equal totals). How each class may enter
the screen (deterministic frame by frame, stable by totals with margin 2t, quarantined never) is proved in
`Fw.Measure.Tolerance` (`measure.noMoreWork`).

## Pure modules

- Zone sums and classes: Lean (`lean/Fw/Measure`), called through `src/fwcore.mjs`. Golden vectors in
  `packages/contracts/golden/measure/`, conformance in `test/fwcore.test.mjs`. The TS `reduce.mjs` is deleted.
- `src/trace.mjs` `traceToFrameCounts(events, nFrames)`: trace events to per-frame counts (bucketing rules above).
  Extraction, not decision logic.
- `src/compare.mjs`: run-to-run equality report (a harness self-check, not a verdict). Per-100px normalisation,
  landing class, dominance screening and verdicts are Lean's (`fwcore`: `ticks`, `screen`, `verdict`, `cost`) and are
  not computed here.

## Known gaps

- Software raster in the container; headed Mac Chrome uses GPU raster with different tile geometry (V-a compares).
- Input: see "Touch input" below (swipe-v1 is still programmatic scrollTo).
- `Network.enable` makes BeginFrame hang at navigation commit (observed), so in-flight requests are counted by the
  server instead of through CDP.

## Update 2026-10-17 (flags, touch, census, rewrite, pins)

Commands: `--target original|rewrite|fixture` (rewrite: `apps/site/dist/aot`, `--site-dir`; `--search '?fw=part:variant'`),
`node src/classes.mjs a b c [--md]` (class table over N runs), `node src/fwcore-screen.mjs` (hands counts to fwcore `screen`/`ticks`
and records the replies), `host.json` next to every `counts.json` (attempts, host load1 and CPU idle before/after; never in counts.json).
Env knobs: `FW_BARRIER_MS`, `FW_BARRIER_MIN_MS` (conditional barrier), `FW_TOUCH_SETTLE_MS`, `FW_TOUCH_ACK_MS`, `FW_BF_TIMEOUT_MS`,
`FW_CHROME_EXTRA`, `FW_DROP_FLAGS`, `FW_NO_LAYERS`, `FW_DOCKER_CPUS` (host: `docker run --cpus`).

- **Chrome flags (CONFIRMED in run.mjs, recorded in meta.browserArgs):** `--deterministic-mode` is gone; kept
  `--enable-begin-frame-control --run-all-compositor-stages-before-draw --disable-new-content-rendering-timeout
  --disable-checker-imaging --disable-image-animation-resync`; `--disable-threaded-animation` is NOT passed; `--num-raster-threads=2`
  (CI portability). INFERRED: `AddSwitchesForVirtualTime` in headless_content_main_delegate.cc @156.0.8078.4 lists exactly those four
  switches plus threaded-animation; I did not find the code that maps `--deterministic-mode` to them. Fixture check (`fixtures/anim-*`,
  profile `fixture-rest`, 120 frames), MEASURED: compositor animation (transform/opacity): Paint 0, Layout 0, cc.Commit 0, cc.Activate 0,
  but UpdateLayoutTree 120 (2 elements per frame: a main-thread style update per BeginFrame remains); with `--disable-threaded-animation`:
  Paint 0, cc.Commit/Activate 120; main-thread animation (width, background-color): Paint 240, Layout 162, UpdateLayoutTree 162. So the
  V-n criterion "0 main-thread UpdateLayoutTree" does NOT hold; "0 Paint, 0 Layout, 0 commit/activate" does.
- **Touch (`swipe-touch-v1`, CDP `Input.dispatchTouchEvent`, virtual-time stamps, 10 px per frame, strokes 880 -> 100):** works, no fling,
  scroll 10 px per frame after a 5 px slop. MEASURED: (1) a touch ack arrives only after the next BeginFrame, sometimes one frame later;
  (SUPERSEDED for the cause and the fix of (2) and (3): see "touch wedge: cause and fix" at the end of this file.)
  (2) a frame without input while the finger is down in an active scroll, or a backlog of 2 unacknowledged events, wedges the renderer
  compositor (no deadline or draw after commit, BeginFrame never answers; the driver exits 75 and the host retries up to 5 times);
  (3) where it wedges depends on host speed: under load1 ~400 the original ran 3/3 to the end, at load1 ~8 it wedged at the same frame in
  5/5 attempts; (4) a touchmove is handled by the main thread in frame k or k+1 (a race inside the compositor), so EventDispatch,
  FunctionCall, HitTest, PrePaint move by one frame in ~150 of 409/531 frames and on the rewrite their run totals differ by up to 6%; about
  1 run in 6 the whole trajectory shifts by one frame (`meta.trajectorySha256`). HitTest is therefore NOT out of quarantine with touch:
  hover recompute was not the cause (touch has none), touch-event delivery is. With programmatic scrollTo the rewrite is fully
  deterministic (below). `swipe-wheel-v1` (native mouse wheel) was started as a diagnostic and not finished.
- **Class tables.** Original, touch, 3 runs (taken BEFORE the flag change and the pins; not repeated, see open items), under load1 360-450 (the earlier runs too: 15-minute load average 457 at 09:49Z):
  deterministic 24 types (hasDamage, LayoutCount, Layout and its sums, Commit, Layerize, ScrollLayer, FireAnimationFrame,
  RequestAnimationFrame, EvaluateScript, Layer.created, cc.Activate/Commit/Draw/SynchronizeTrees, ParseHTML, ResourceSendRequest,
  IntersectionObserverCompute, Animation.*), stable 13 (Paint, PaintImage, RasterTask, UpdateLayer, ...: 1-6 frames shift), shifting 5
  (EventDispatch, FunctionCall, HitTest, PrePaint, elementCount, ...), quarantined 8 (GC-bound). Rewrite, scrollTo (swipe-v1, barrier-min
  10 ms), 3 runs: all 43 count types deterministic (HitTest, census and raster invalidation included) except MinorGC; the files differ only in
  `meta.threads` (worker thread count). Run-to-run identity of the deterministic classes held under that load; whole-file byte identity never
  held (meta.threads, GC, async completions). `classes.mjs` thresholds are in its header comment.
- **Layer census and raster invalidation (done, `trace.mjs snapshotCounts`):** category `disabled-by-default-devtools.timeline.layers`
  gives one `LayerTreeHostImpl:snapshot` per BeginImplFrame (active-tree layers, tilings, active tiles) with each PictureLayerImpl's
  `invalidation` region (4 ints per rect: x y w h, cc/base/region.cc). New types: `census.{snapshots,layers,drawingLayers,drawingAreaPx,
  tilings,tiles,activeTiles,solidTiles,activeTileAreaPx}`, `raster.{invalidatedLayers,invalidationRects,invalidationAreaPx}`. Deterministic
  on the rewrite; on the CSS-animated layout fixture all but solidTiles and invalidationAreaPx (animation phase follows the per-run
  navigation start, INFERRED; not fixable without seeking animations). Not yet run on the original (trace size unchecked).
- **Apt/npm pins (done):** the build fails unless dpkg equals `docker/apt-manifest.txt`; a `--no-cache` rebuild passed (SNAP=20261016).
- **Conditional barrier (#18, partial):** `FW_BARRIER_MIN_MS=10`: a rewrite run takes 7 s instead of 45 s with identical classes (3 runs).
  Not validated on the original (lazy images keep the full barrier when a request starts); no sweep done.
- **Rewrite comparison (swipe-v1, scrollTo, one run per config; replies in `out/fwcore/swipe-v1-rewrite.json`, gitignored):** the rewrite
  has placeholder content only (24 cards, no images, document 4376 px vs the original's 4626+), so totals differ from the original by
  design and nothing is compared with the original; only variant vs default of the rewrite. Per-part attribution works through the config
  diff only (the trace has no per-part marks). fwcore `screen` (W = elementCount, dirtyObjects, Paint, UpdateLayer, RasterTask; S =
  FunctionCall, EventDispatch, FireAnimationFrame, HitTest; per 500 px zone and per frame): engine.scroll:batched W equal, S equal;
  nav.hitTest:hit-skip W dominates (Paint 556 vs 1152, UpdateLayoutTree 94 vs 784), S equal; hero.countdown:strip W equal, S mixed
  (FunctionCall 730 vs 911, FireAnimationFrame 385 vs 566). `ticks` with the nominal 16.67 ms frame (this lane has no durations): 385
  ticks, 0 above 34/50 ms. Not judged here.

## Update 2026-10-17 (touch wedge: cause and fix)

**Cause (CONFIRMED by source and by a scheduler trace; steps 4-5 are INFERRED).** The touch wedge is the compositor's
scroll-deadline mode waiting for a time that never comes. Source refs are @f842f52 (156.0.8078.4).

1. `features::kWaitForLateScrollEvents` is on by default with mode `DispatchScrollEventsUntilDeadline` (cc/base/features.cc:82, :120-123).
   `LayerTreeSettings::ToSchedulerSettings` turns it into `scroll_deadline_mode_enabled` (cc/trees/layer_tree_settings.cc:59-76).
2. At every `WillBeginImplFrame`, `LayerTreeHostImpl` tells the scheduler "waiting for scroll event" when a scroll is active and the
   compositor input queue is empty (cc/trees/layer_tree_host_impl.cc:3524-3528). The state machine then picks `WAIT_FOR_SCROLL`
   (cc/scheduler/scheduler_state_machine.cc:1337-1341, :1357-1372) and `ShouldSendBeginMainFrame` returns false (:616).
3. The wait ends at `frame_time + interval * 0.333` (cc/scheduler/scheduler.cc:861-864), a precise timer on the real clock. Here
   `frame_time` is virtual (`T0 + vt`, `T0` = 5,000,000 ms), about 4,900 s ahead of the container's monotonic clock (viz logs
   `Frame latency is negative: -4.93e6 ms` on every frame), so the timer never fires. Only an input event ends the wait
   (layer_tree_host_impl.cc:4645).
4. INFERRED: a touchmove with a main-thread handler is acknowledged by a main frame (rAF-aligned) and the scroll update follows the
   ack, so a frame that starts with a scroll active and an empty compositor queue (previous touchmove waiting for the main thread, or
   a frame without input) waits for a scroll event while the main frame that would deliver it is held back: a deadlock. This is the
   "backlog of 2 unacknowledged events" and "frame without input in an active touch scroll" of the older notes. Whether the input is
   already queued when the frame starts is a race with real time, hence the dependence on host speed.
5. MEASURED proof: `FW_DEBUG=1 FW_EXTRA_CATEGORIES=disabled-by-default-cc.debug.scheduler,cc` on a wedging run: the only
   `Scheduler::ScheduleBeginImplFrameDeadline` of mode `WAIT_FOR_SCROLL` has `new deadline = 5028738882` us while the trace clock is at
   ~115,400,000 us; the other 929 are `IMMEDIATE` (`new deadline = 0`). Ending the trace let the frame go on, so that run did not hang.

**Fix.** `--disable-features=WaitForLateScrollEvents` in `CHROME_ARGS` (so in `meta.browserArgs`). It removes only a real-time wait for
late scroll events, which means nothing on a virtual clock. A smaller `T0` is not a fix: frame times must stay monotonic and in the
past for the whole load and profile, and the container clock restarts at 0 for every container.

**Measured (original, `swipe-touch-v1`; host load1 from 165 down to 6 while other agents ran).**

| arm | runs | wedged runs | host attempts |
|---|---|---|---|
| flag off (control) | 1 (plus 1 debug) | 1 of 1 (all 5 attempts, always at vt 28733.33 = frame 556, 2 unacked) | 5 |
| flag on, touch settle 50 ms (default) | 11 | 0 | 1 each |
| flag on, touch settle 300 ms | 10 | 1 (vt 26516.67, 1 unacked; no trace taken; the next attempt passed) | 1 each, one 2 |

So the dominant wedge is gone (0/11 at the default settle, down from 5/5 attempts), and one wedge in 21 flag-on runs remains with a
cause I did not find (settle 300 only; a candidate is another deadline mode with a future deadline, `LATE`/`REGULAR` under
`IsDrawThrottled`, scheduler.cc:830-852, not checked). The host's 5-attempt retry makes it irrelevant for completion
(chance of 5 in a row is negligible), and `FW_DEBUG=1` hang traces will show it if it recurs.

**Determinism of the completed runs.** Completion: 21/21 flag-on runs reached the end. Trajectory (`meta.trajectorySha256`): runs g4-g8
(load1 165 -> 6, then 8) have the same trajectory, 521 frames, 470 touch events; g1-g3 at higher load have 531 frames with three
different trajectories (a one-stroke difference, the "1 in 6 shift" of the older notes). Within g4-g8 `meta` and phase/scrollY are equal
per frame; counts files are NOT byte-identical: `class table` over g4-g8 = 10 deterministic types (census.snapshots, hasDamage,
Commit, Layerize, ScrollLayer, cc.Draw, EvaluateScript, ParseHTML, ...), 20 stable, 21 shifting (PrePaint, FunctionCall, census/raster
types), 11 quarantined (EventDispatch, HitTest, GC, ...). The shifting/quarantined set is the same family as before: the main thread
takes a touchmove in frame k or k+1, and image/decode completions land by real time. That race is NOT fixed by this change. Byte-for-
byte identity of counts files is not reached on the original under touch; the deterministic and stable classes are the usable part.

**Fallback if the flag ever regresses:** `swipe-v1` (programmatic `scrollTo`) needs no input events and is fully deterministic on the
rewrite; it loses the browser's touch scroll path (gesture detector, touch-handler dispatch, scroll-update batching), so
`engine.scroll`-type variants would be measured without the input pipeline. Not needed now.

## Update 2026-10-17 (touch-ci-verify and class-freeze: CI runs, frozen class table)

All numbers MEASURED on GitHub Actions (ubuntu-24.04-arm), original target, harness commit 429e22a, one image for every run
(`sha256:ebefaf34...d491`, built by run 39038861283, reused by the other five through the `image_run` workflow input).

| profile | workflow runs (3 jobs each, separate VMs) | wedges / attempts | completion | classes (det / stable / quarantined) per run |
|---|---|---|---|---|
| swipe-v1 | 39038861283, 39038967198, 39038970307 | 0 / 1 attempt in 9 of 9 jobs | 9/9 | 28/25/9, 27/26/9, 30/25/7 |
| swipe-touch-v1 | 39038973297, 39038976656, 39038979125 | 0 / 1 attempt in 9 of 9 jobs | 9/9 | 17/31/14, 18/25/19, 18/33/11 |

- Touch fix confirmed on CI: `--disable-features=WaitForLateScrollEvents` gives 0 wedges in 9 touch jobs (the control wedged 5 of 5
  attempts locally). Attempts come from `attempts=N` in each job log (host.json is not uploaded).
- Touch is not trajectory-deterministic on CI: 531 frames and 480 touch events in all 9 jobs, but two `trajectorySha256` values
  (005bd6dc, 5278f464) that differ in one frame (469: scrollY 4337 vs 4327, the touchmove k/k+1 race). This is why touch has more
  quarantined types than swipe-v1 (EventDispatch, FunctionCall, HitTest, PrePaint, UpdateLayoutTree.elementCount, ...).
- Rewrite with touch: NOT run. The workflow has no site build step (apps/site/dist/aot is built by `pnpm --filter @fw/site build`, and
  host.mjs gets no `--target`), so the lane cannot reach the rewrite yet. A `target` input plus a build job is the missing piece.
- Frozen table: `classes.frozen.json` (swipe-v1 and swipe-touch-v1). Rule: worst class per type over the 3 workflow runs of a profile,
  policy kMax 4, tMax 24, pixel rule for `*AreaPx` types (tBound = max(tMax, floor(min|total| / 1000))). Result (signed class):
  swipe-v1 27 deterministic / 25 stable / 10 quarantined; swipe-touch-v1 16 / 27 / 19. The pooled class over all 9 files is stricter
  (swipe-v1 27/23/12, touch 16/25/21) and is stored as `pooledClass` for reference only.
- How it was made (no TS logic): per workflow run, `src/classify.mjs` (fwcore `measure.classify`, identical to the run's own
  `chromium-classes` artifact, checked for all 6); then fwcore `measure.summarize` over rows {family: profile, metric: type,
  level: "run <id>", cls} gives the worst. Only JSON was moved by a scratch script; a `src/freeze.mjs` that does this is an open item.
- Workflow: new dispatch input `image_run` (reuse the `chromium-image` artifact of an earlier run); the classes artifact now also holds
  `image-ids.txt`, `image-inputs.txt` (sha256 of Dockerfile, apt manifest, fonts.conf, npm lock) and `run.txt`. Dispatches on one ref cancel each
  other (concurrency), so the five dispatches ran from five `ci/chromium-ci-*` branches at the same commit.
- Reproduce: `gh workflow run chromium-counts.yml --ref ci/<branch> -f profile=swipe-touch-v1 -f runs=3 -f image_run=39038861283`
  (the image artifact lives 3 days; after that rebuild and re-freeze).

## Update 2026-10-17 (rewrite-ci-lane: the rewrite on CI next to the original)

`chromium-counts.yml` now measures the rewrite (`apps/site`, prerendered `dist/aot`) next to the original with the same profile, image,
flags and host. `host.mjs` already had `--target original|rewrite|fixture` and `--search`; the workflow now passes them.

- Dispatch inputs: `target` (both | original | rewrite, default both), `preset` (rewrite preset name, default `original`), `fw` (comma
  separated `part:variant`, default empty), plus the earlier `profile`, `runs`, `image_run`. `preset`/`fw` only shape the rewrite query
  (`?preset=<name>&fw=<flags>`); the original jobs ignore them; the plan job refuses them with `target=original`.
- Jobs: `plan` (matrix of target x run, one VM per job) -> `site` (setup-lean + setup-pnpm, `pnpm --filter @fw/site build`, which first checks
  `src/breakpoints.gen.json` against `lake exe breakgen`; a non-default query is added with `--config`) -> `counts (target, run)` ->
  `classify`. The rewrite jobs download the `site-dist` artifact to `apps/site/dist/aot`; the run refuses a page that did not hydrate.
- Artifacts: `chromium-counts-<target>-<run>` (counts.json, zones.json, host.json with the container attempts, runner.json, image-id.txt) and
  `chromium-classes` with one directory per target (`original/`, `rewrite/`: classes.txt/json, sha256, attempts, image ids) plus
  `a-vs-r.txt` (class(k,t) per type, A next to R), `image-inputs.txt`, `run.txt`. Both targets go through the same `classify.mjs` (fwcore).
- The paths filter gained `apps/site/**`, `package.json`, `pnpm-lock.yaml`, `pnpm-workspace.yaml` and the setup-pnpm action (`lean/**` was
  already there, so the breakpoint sources are covered).

## Update 2026-10-17 (hittest and spk-q: HitTest split, N0 census, N1 slices)

- **HitTest cause (CONFIRMED in source, MEASURED locally).** `trace.HitTest` was quarantined because one HitTest
  source follows real time: `OverlayInterstitialAdDetector::MaybeFireDetection` runs hit tests inside Commit and caps
  itself with a wall-clock check (`base::Time::Now()`, 1 s), so how many frames carry its hit tests depends on the CI
  machine, not on the virtual clock. The other sources (hover recompute in `BeginMainFrame`, page `elementFromPoint`
  in rAF) follow frames. `src/trace.mjs` now counts a HitTest slice that lies inside a detector slice as
  `trace.HitTest.overlayAdDetector`; `trace.HitTest` keeps the frame-driven rest. This is extraction, not a decision.
- **N0 (`src/n0-census.js`, `src/n0.mjs`).** Page-side census of CSSOM writes and sheet-node changes, stamped with
  virtual time and attributed to the frame after the fact. Keys `n0.events`, `n0.cssom`, `n0.sheetNode` per frame,
  zero-filled. `FW_NO_N0=1` turns it off (harness-neutrality control). Positive control:
  `--target fixture --site-dir fixtures/sheet-mutate --profile fixture-rest` reads 4 events in 4 frames.
- **N1 (`src/trace.mjs`).** Needs the trace categories `blink` and `blink_style`; keys `trace.N1.updateActiveStyleSheets`,
  `trace.N1.scheduleInvalidationsForRuleSets`, `trace.N1.fontUpdateInvalidation`, zero-filled.

## Update 2026-10-17 (refreeze: both arms, the split types, roles)

`classes.frozen.json` is regenerated (schema `fw.classes.frozen/2`) by `src/freeze.mjs` over 3 workflow runs per profile, each with
3 jobs per arm on separate VMs, one image (`sha256:8f0e17f5...`, built by run 39049264131, the other five reused it through
`image_run`). Harness commit `f87bf94` (main `c719d73`, which holds the HitTest/N1 splits of `f90c08f`/`33fdcfe` and the touchmove
fix of `c38088e`, plus the one-line workflow fix below). Every type the harness emits is in the table (checked against the union of
the counts files: A 70, R 52 in swipe-v1; A 70, R 51 in swipe-touch-v1). Touch cross-arm: 55 gates, 14 findings, 1 byDesign.

| profile | arm | workflow runs | before det/stable/quar (types) | after det/stable/quar (types) | roles gate/finding/byDesign |
|---|---|---|---|---|---|
| swipe-v1 | A | 39049264131, 39049466889, 39049469621 | 27/25/10 (62) | 32/28/10 (70) | 60/9/1 |
| swipe-v1 | R | same | none | 44/7/1 (52) | 51/1/0 |
| swipe-touch-v1 | A | 39049471997, 39049481754, 39050423094 | 16/27/19 (62) | 23/32/15 (70) | 55/14/1 |
| swipe-touch-v1 | R | same | none | 50/1/0 (51) | 51/0/0 |

- Eight types are new (the splits and the N0 census): `trace.HitTest.overlayAdDetector`, `trace.N1.updateActiveStyleSheets`,
  `trace.N1.svgImageDocument`, `trace.N1.fontUpdateInvalidation`, `trace.N1.scheduleInvalidationsForRuleSets`, `n0.cssom`, `n0.events`,
  `n0.sheetNode`. `trace.HitTest` went from quarantined to stable on A in both profiles (swipe-v1 on R too: deterministic).
- Roles are Lean's (`Fw.Measure.Arms`, in the `role`/`reason` fields of `measure.freeze` rows): `trace.HitTest.overlayAdDetector`
  is `byDesign` whatever its class (A: quarantined; the rewrite never records it). `crossArm` is `measure.arms` over the two frozen tables:
  an arm without the type reads as deterministic there, so the one-arm type is decided by the arm that has it (swipe-v1: 59 gates, 10
  findings, 1 byDesign; touch: 55 / 14 / 1).
- **A touch job with another trajectory stays out.** Run 39049478836 (touch) is not in the table: its rewrite job r2 sent 354 touch
  events and recorded 403 frames (the other 23 jobs of the four touch runs: 360 and 409 for R, 480 and 531 for A), which made 30 R types
  quarantined. Its log shows `attempts=1`, host wall 111.8 s (the others 113-115 s): no wedge retry, no early stop, no stall. The
  touch planner is closed loop (the stroke ends when scrollY reaches the page end), and in that job the scroll advanced 20 px in one
  frame at frame 172 (two touchmoves' worth, the touchmove-race residual of touch-race), so the page end came 6 moves early. A fourth
  touch run (39050423094) replaced it. This was a decision of the lead; since task freeze-refuse the freeze rule makes it (below).
- **Update 2026-10-18 (freeze-refuse): `measure.freeze` refuses jobs with different frame counts.** `src/freeze.mjs` sends each job's
  `{name, frames, trajectorySha256}`; Lean `Fw.Measure.Freeze.freeze` refuses a run without jobs and any two jobs (of any runs of one
  arm) whose frame counts differ, naming every job whose count is not the most frequent one (proved: accepted => one frame count,
  `freeze_frames`; every named job differs from another, `oddJobs_sound`). With 39049478836 instead of 39050423094 the freeze now
  stops with `swipe-touch-v1/rewrite: fwcore measure.freeze: frame counts differ between jobs: job chromium-counts-rewrite-r2 of
  workflow run 39049478836 has 403 frames; 8 of 9 jobs have 409 frames` (MEASURED 2026-10-18). Trajectory hashes are compared, not
  refused (touch A has two trajectories at one frame count); `allTrajectoriesEqual` now comes from Lean (`trajectoriesEqual`). The
  committed table regenerates identically with the six runs below. `measure.classify` is unchanged (it reads missing frames as 0).
- Schema change: `profiles.<profile>.arms.{original,rewrite}` hold what `profiles.<profile>` held (types with `class`, `k`, `t`, `perRun`,
  `role`, `reason?`, `tBound?`, `pooledClass`; `tally`, `roles`, `pooledTally`); `profiles.<profile>.crossArm` is new.
- Workflow fix (`.github/workflows/chromium-counts.yml`): `classify` now has an `if` that ignores the skipped `site` job, so a dispatch
  with `target=original` writes `chromium-classes` (before, the skip of `site` propagated to `classify`).
- Reproduce: `gh run download <id> --dir runs/<id> --pattern 'chromium-c*'` for the six runs, then
  `node src/freeze.mjs runs/<the six dirs above> --built-by 39049264131 --check` prints "identical".

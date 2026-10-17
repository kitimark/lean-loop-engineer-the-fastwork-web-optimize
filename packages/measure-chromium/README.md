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
| Fonts | none in the image (`src/image-check.sh`: `fc-list` is empty, no font files). Webfonts come from the snapshot only (Google Sans latin/thai, Fastwork, Playpen) |
| Network | every host except 127.0.0.1 is unresolvable (`--host-resolver-rules`); the page is served by `src/server.mjs`, which records the sha256 of every file it sent (`meta.servedSha256`) |
| Apt libraries | all 211 packages pinned: dated snapshot.debian.org mirror (SNAP=20261016T000000Z) + `docker/apt-manifest.txt`; the build fails if dpkg differs from the manifest (`node src/pin-apt.mjs`). npm: `docker/driver/package-lock.json` (`npm ci`) |

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

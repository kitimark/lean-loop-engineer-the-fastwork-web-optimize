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
node --test test/pure.test.mjs                                 # unit tests of the two pure modules (no Docker)
pnpm --filter @fw/measure-chromium build:image                 # or: docker build -t fw-measure-chromium:1 .
```

The first run builds the image `fw-measure-chromium:1` (about 2 min; downloads the browser zip, verified by sha256).
Output: `out/<profile>/<label>/counts.json` (gitignored). `--dump-trace` also keeps the raw trace (about 50 MB).
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
| Apt libraries | Debian bookworm at build time, NOT pinned (INFERRED to not change counts; the image id is in `meta.image`) |

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
(array of `{n, phase, scrollY, vt, counts:{type:number}}`), `zones` (per 500 px zone: `frames`, `scrolledPx`, sums per
type), `runLevel` (run totals of worker-thread tasks). Plain JSON, no wall-clock values, so equal runs are equal bytes.

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

## Pure modules (to get a Lean spec and golden vectors)

- `src/reduce.mjs` `zoneSums(frames, zoneHeightPx)`: per-zone sums. The ONLY reduction in the TS harness. Tests in
  `test/pure.test.mjs`.
- `src/trace.mjs` `traceToFrameCounts(events, nFrames)`: trace events to per-frame counts (bucketing rules above).
  Extraction, not decision logic.
- `src/compare.mjs`: run-to-run equality report (a harness self-check, not a verdict). Per-100px normalisation,
  landing class, dominance screening and verdicts are Lean's (`fwcore`: `ticks`, `screen`, `verdict`, `cost`) and are
  not computed here.

## Known gaps

- Software raster in the container; headed Mac Chrome uses GPU raster with different tile geometry (V-a compares).
- Programmatic scroll, not touch input: no touch events, hover recompute present.
- `Network.enable` makes BeginFrame hang at navigation commit (observed), so in-flight requests are counted by the
  server instead of through CDP.

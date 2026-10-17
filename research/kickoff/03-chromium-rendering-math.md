# 03 · Chromium rendering math: measuring animation cost from engine statistics

Kickoff research note for the v2 loop-engineering experiment, written 2026-10-17. It is research and design only: no
browser run, no device, no tooling changed.

**Question.** Can we measure scroll-animation performance from Chromium's engine statistics (deterministic work counts
plus a calibrated cost model) instead of a real device on every iteration? What does Chromium's source say about how a
frame is scheduled, what it costs, and how dropped frames are counted?

**Labels.**
- **CONFIRMED**: backed by a source line, doc or bug cited next to the claim.
- **INFERRED**: my reasoning or design, not verified by a run.
- **OBSERVED-v1**: measured in the v1 repo; cited by path.

**Pins.** Every source citation is pinned:

| Source | Pin |
|---|---|
| Chromium | GitHub mirror `chromium/chromium` at `fcacb60bd396ba6fb87a9d8183743784fe2af4a3` (main, 2026-10-16). Written below as `cr:` + path + line. |
| Perfetto | `google/perfetto` at `34ab25188c36` (2026-10-16). Written as `pf:`. |
| DevTools protocol | `ChromeDevTools/devtools-protocol` at `e908551762a5` (2026-10-16), `json/browser_protocol.json`. |
| Local Chrome | 155.0.8059.80. v1 measured on Chrome 154. |

`OLD/` means the v1 repo `../fastwork-com-web-optimize`, which is read-only. Nothing from Fastwork's
site was read for this note.

---

## 0. Answer first

1. **Yes, for Chromium, with one limit.** Chromium's per-frame work is driven by quantities that can be counted
   reproducibly. Those counts can be captured in headless, in parallel, with no timing noise, if frames are stepped
   deterministically. The steppable build is `chrome-headless-shell` with `HeadlessExperimental.beginFrame` (§7.1).
   The quantities are:
   - elements restyled;
   - layout objects dirtied;
   - paints and display items;
   - raster-invalidated pixels;
   - tiles rastered;
   - layers;
   - commits;
   - main-thread vs compositor animations.

   The limit: these counts measure **work, not the user's experience**. In v1 a pure work metric (the "cost card")
   was right about less work and wrong as a predictor of what the user felt (`OLD/research/architecture/stats-vs-finger.md`
   §1 row 8, §2 item 2). So counts must be turned into predicted missed frames by a calibrated cost model, and that
   model must be validated against device verdicts before it replaces the device.

2. **The frame budget is a set of inequalities, not one "16.7 ms".** From the cc scheduler and Viz source (§3):
   - the display compositor's own deadline is `vsync − interval/3`;
   - the renderer draws by `deadline − p90(draw) − 1 ms`;
   - the main thread is "on the critical path" only while `p90(BeginMainFrame→activation) < interval − p90(draw) − 1 ms`.

   At 120 Hz that leaves about 6.5 ms for a main frame to reach activation in low-latency mode, and about 15.7 ms at
   60 Hz (with draw p90 ≈ 0.8 ms; that value is INFERRED). Chromium's own estimators use the **90th percentile of the
   last 60 samples** per stage (`cr:cc/metrics/compositor_timing_history.cc` l.24-32). That is a direct template for
   our model.

3. **Compositor-only is decided by source rules we can check statically and in traces** (§4):
   - Compositable properties are `transform`/`translate`/`rotate`/`scale`, `opacity`, `filter` and `backdrop-filter`,
     plus `background-color` and `clip-path` with a native paint worklet (`cr:.../compositor_animations.cc` l.76-83).
   - A **filter animation that moves pixels (blur, drop-shadow) is not composited**: failure flag
     `kFilterRelatedPropertyMayMovePixels` (l.405-412).
   - A scroll-timeline animation composites only if its source has a user-scrollable composited scroll node (l.1145-1166).
   - Every failure is logged as a bitmask `compositeFailed` in the `Animation` trace event.

4. **Dropped-frame accounting changed after the docs were written** (§6). `DroppedFrameCounter`, the class behind the
   web.dev "sliding window Percent Dropped Frames", was **deleted on 2025-06-20** (Chromium commit `9e56a8798315`,
   crbug 409093076). What remains:
   - `FrameSequenceMetrics` V3/V4: `PercentDroppedFrames3 = ceil(100 · dropped / expected)`, reported only when at
     least 100 frames are expected;
   - `Jank3` (a frame whose presentation delta exceeds the previous delta by more than 0.5 × interval);
   - the `PipelineReporter` trace states;
   - Scroll Jank v4 (Perfetto table, Chrome 145+).

5. **Proposed cost model** (§9). The predicted time of each stage is
   `T_s(f) = κ_s + Σ_j c_{s,j}^{device} · x_{s,j}(f)`, where `x` are the deterministic counts. A frame misses
   `k_f − 1` vsyncs, with `k_f = max(1, ⌈T_crit(f) / I⌉)` (pipelined throughput form) or, with latency, against the
   thresholds in point 2.
   - **Calibration:** fit the coefficients per stage with non-negative and p90 quantile regression. Use a few device
     sessions over feature-flag factorial designs plus synthetic micro-fixtures.
   - **Validation:** check held-out configurations for stage error, prediction-interval coverage and **A/B decision
     agreement**, including the v1 blind-verdict ledger.

6. **Compared with v1's 6× CPU throttle** (§11): the throttle is one scalar on the main thread only.
   - It is super-linear for DOM work (6× nominal costs 7.8×).
   - It never touches the GPU.
   - It was fitted on the unfixed page, and it needs exclusive timing runs.

   The cost model has per-stage coefficients and runs in the parallel counts lane. It also says *which* stage is over
   budget. It cannot see WebKit-only costs: those need WebKit counts with their own coefficients (the WebKit kickoff note).

---

## 1. The pipeline, stage by stage

### 1.1 Stages and threads

RenderingNG names the stages as follows (CONFIRMED,
[RenderingNG architecture](https://developer.chrome.com/docs/chromium/renderingng-architecture)):

| # | Stage | Where | What it produces | Trace slice (Blink / cc / Viz) |
|---|---|---|---|---|
| 1 | Animate | main **or** compositor | updated computed style / property-tree values | `Animation` instant events; cc `AnimationHost` |
| 2 | Style | renderer main | ComputedStyle | `UpdateLayoutTree` (args `elementCount`) |
| 3 | Layout | renderer main | fragment tree | `Layout` (args `dirtyObjects`, `totalObjects`, `partialLayout`) |
| 4 | Pre-paint | renderer main | paint property trees; paint invalidation | `PrePaint` |
| 5 | Scroll | main **or** compositor | scroll offsets in property trees | compositor: `InputHandlerProxy` / scroll update; main: `ScrollLayer` |
| 6 | Paint | renderer main | display items → paint chunks; raster invalidation | `Paint` |
| 7 | Commit | main → compositor (blocking) | pending tree | `Commit` / PipelineReporter `kCommit` |
| 8 | Layerize | renderer (PaintArtifactCompositor) | `cc::Layer` list | `Layerize` |
| 9 | Raster, decode, paint worklets | GPU process (OOP raster) and compositor helpers | GPU tiles | `RasterTask` (cat `cc,disabled-by-default-devtools.timeline`) |
| 10 | Activate | compositor | active tree | PipelineReporter `kActivation` |
| 11 | Aggregate | Viz display compositor | one global CompositorFrame | Viz `Graphics.Pipeline` steps |
| 12 | Draw | Viz GPU main | pixels / swap | Viz breakdown `kStartDrawToSwapStart`, `kSwapStartToSwapEnd` |

The article: "Stages of the rendering pipeline can be skipped if they aren't needed … animations of visual effects,
and scroll, can skip layout, pre-paint and paint … they can be run entirely on the compositor thread and skip the
main thread" (CONFIRMED, same page).

### 1.2 The Blink document lifecycle

The states run `kVisualUpdatePending → kInStyleRecalc → kStyleClean → kInPerformLayout → kLayoutClean →
kInCompositingInputsUpdate → kInPrePaint → kPrePaintClean → kInPaint → kPaintClean` (CONFIRMED,
`cr:third_party/blink/renderer/core/dom/document_lifecycle.h` l.49-82).

`LocalFrameView::UpdateLifecyclePhasesInternal` loops (`while (true)`) over style+layout, post-layout snapshot steps,
pre-paint, intersection observers, and so on. Some steps **re-run the lifecycle** (`continue`) when they dirty it
(CONFIRMED, `cr:third_party/blink/renderer/core/frame/local_frame_view.cc` l.2547-2680). Container queries, resize
observers and IntersectionObserver callbacks can therefore multiply style and layout passes inside one frame. This is
a count we must record (style/layout passes per frame), not assume to be 1.

### 1.3 The cc / Viz frame reporter stages

`CompositorFrameReporter` splits one frame into stages (CONFIRMED,
`cr:cc/metrics/compositor_frame_reporter.h` l.91-158):
- **StageType:** `kBeginImplFrameToSendBeginMainFrame`, `kSendBeginMainFrameToCommit`, `kCommit`,
  `kEndCommitToActivation`, `kActivation`, `kEndActivateToSubmitCompositorFrame`,
  `kSubmitCompositorFrameToPresentationCompositorFrame`.
- **BlinkBreakdown** (inside BeginMainFrame→Commit): `kHandleInputEvents`, `kAnimate`, `kStyleUpdate`,
  `kLayoutUpdate`, `kAccessibility`, `kPrepaint`, `kCompositingInputs`, `kPaint`, `kCompositeCommit`,
  `kUpdateLayers`, `kBeginMainSentToStarted`.
- **VizBreakdown:** submit→receive, receive→start draw, start draw→swap start, swap start→end (with optional buffer
  sub-steps), swap end→presentation.

These are emitted as `PipelineReporter` slices in category `cc,benchmark,disabled-by-default-devtools.timeline.frame`
(CONFIRMED, `cr:cc/metrics/compositor_frame_reporter.cc` l.1498-1510). This is the per-frame, per-stage **timing**
ground truth for calibration on any Chromium device.

---

## 2. Life of a frame in one paragraph

This paragraph is INFERRED, assembled from §3 to §6.

1. A vsync tick makes Viz's `DelayBasedBeginFrameSource` issue `BeginFrameArgs{frame_time, deadline, interval}`.
2. The renderer compositor's `Scheduler` enters `INSIDE_BEGIN_FRAME`. It ticks compositor animations and scroll, and
   sends `BeginMainFrame` (BMF) to the main thread if something requested one: rAF, a main-thread animation, or a
   dirty lifecycle.
3. The main thread runs rAF callbacks, then the lifecycle (style → layout → pre-paint → paint → layerize), then
   **commits**. The main thread is blocked while the compositor copies the layer list and property trees into the
   pending tree.
4. The pending tree rasterizes the tiles that are *required for activation*, then **activates**.
5. At the impl-frame deadline the compositor **draws**: it builds quads and render passes and submits a
   CompositorFrame.
6. Viz aggregates the surfaces and draws on the GPU before its own deadline.
7. The frame is presented at a later vsync.

If the main thread is late, the compositor can still draw a *partial* frame: new scroll and compositor animations,
old main content.

---

## 3. BeginFrame, the cc Scheduler state machine, and deadlines

### 3.1 State

Source: `cr:cc/scheduler/scheduler_state_machine.h`.

- `BeginImplFrameState { IDLE, INSIDE_BEGIN_FRAME, INSIDE_DEADLINE }` (l.54-58).
- `BeginMainFrameState { IDLE, SENT, READY_TO_COMMIT }` (l.92-97).
- `BeginImplFrameDeadlineMode` (l.67-80):

  | Mode | Value | Meaning |
  |---|---|---|
  | `NONE` | 0 | — |
  | `IMMEDIATE` | 1 | — |
  | `WAIT_FOR_SCROLL` | 2 | "expecting input for a scroll" |
  | `REGULAR` | 3 | "at the deadline provided by in the BeginFrameArgs" |
  | `LATE` | 4 | "when the next frame is expected to arrive" |
  | `BLOCKED` | 5 | "until the next frame arrives" |

### 3.2 Action priority

`NextAction()` returns the first action whose condition holds, in this order (CONFIRMED,
`cr:cc/scheduler/scheduler_state_machine.cc` l.712-737):

```
SEND_BEGIN_MAIN_FRAME > POST_COMMIT > ACTIVATE_SYNC_TREE > COMMIT > DRAW_(ABORT|FORCED|IF_POSSIBLE)
  > PERFORM_IMPL_SIDE_INVALIDATION > PREPARE_TILES > INVALIDATE_LAYER_TREE_FRAME_SINK > BEGIN_LAYER_TREE_FRAME_SINK_CREATION
```

Facts that matter for the model (all CONFIRMED in the same file):
- **At most one BMF per BeginFrame**, unless an urgent one is pending (l.515-519).
- **No BMF while one is `SENT`** (l.525-529). The main thread's throughput is therefore bounded at one main frame
  per vsync.
- **Draw throttling:** `kMaxPendingSubmitFrames = 1` (l.34). `IsDrawThrottled()` holds while one submitted frame is
  un-acked, unless the `kNoCompositorFrameAcks` feature is on (l.1508-1514). The renderer is back-pressured by Viz
  one frame deep.

### 3.3 Which deadline mode is used

`CurrentBeginImplFrameDeadlineMode()` (CONFIRMED, l.1313-1342):
- `BLOCKED` applies only to `commit_to_active_tree` (browser UI) or headless full-pipeline mode.
- Otherwise, if the deadline should trigger immediately, the mode is `IMMEDIATE`, or `WAIT_FOR_SCROLL` when
  scrolling and no scroll event has arrived yet.
- Otherwise, `REGULAR` if the impl thread needs a redraw (a compositor animation or scroll).
- Otherwise `LATE` (only waiting for main).

`ShouldTriggerBeginImplFrameDeadlineImmediately()` (l.1361-1410) fires immediately when:
- the active tree needs its first draw; or
- a redraw is needed and no commit or pending tree is in flight; or
- impl latency takes priority.

### 3.4 Deadline arithmetic

All CONFIRMED in `cr:cc/scheduler/scheduler.cc` unless noted.

- **Viz client deadline.** A BeginFrame from `DelayBasedBeginFrameSource` has `deadline = next tick`
  (`cr:components/viz/common/frame_sinks/begin_frame_source.cc` l.390-400).
  - The display scheduler takes `interval / 3` as the estimated display draw time
    (`kDefaultEstimatedDisplayDrawTimeRatio = 1/3`, `cr:components/viz/common/frame_sinks/begin_frame_args.h` l.182-194).
  - It moves its own deadline to `deadline − interval/3` (`cr:components/viz/service/display/display_scheduler.cc`
    l.477-478).
  - The Viz unit test expects client args with `deadline = frame_time + interval − interval/3`
    (`cr:components/viz/service/frame_sinks/compositor_frame_sink_support_unittest.cc` l.2132-2134). That test covers
    the throttled path; that the same holds for unthrottled renderer clients is INFERRED.
- **Renderer adjustment** (l.666-668):
  `adjusted.deadline = args.deadline − DrawDurationEstimate − kDeadlineFudgeFactor`, with
  `kDeadlineFudgeFactor = 1 ms` (l.47).
- **Main-thread criticality** (l.676-684):
  `threshold = interval − DrawDurationEstimate − 1 ms`. If
  `p90(BMF queue → activation)` is below `threshold`, the main thread is treated as critical (low latency). Otherwise
  the scheduler prioritises impl latency: it draws without waiting for main, and main content lands one frame later.
  The flag `main_thread_missed_last_deadline` records "high latency mode" (l.645-650).
- **Late missed BeginFrames are dropped:** a `MISSED` BeginFrame whose deadline is already past is answered with
  `DidNotProduceFrame(kRecoverLatency)` (l.657-663).
- **Deadline per mode** (l.861-945):

  | Mode | Deadline |
  |---|---|
  | `LATE` | `frame_time + interval` (l.891-904); also sends an early `DidNotProduceFrame(kNoDamage)` if no new tree is likely |
  | `REGULAR` | `args.deadline` (l.905-907) |
  | `IMMEDIATE` | now (l.909-913) |
  | `WAIT_FOR_SCROLL` | `frame_time + interval × scroll_deadline_ratio` (l.915-919) |

- **Estimators.** `CompositorTimingHistory` keeps `kDurationHistorySize = 60` samples per stage and uses the **90th
  percentile** for every estimate: BMF queue, BMF start→ready-to-commit, commit, commit→ready-to-activate, activate and
  draw (CONFIRMED, `cr:cc/metrics/compositor_timing_history.cc` l.24-32, 185-231). The source comment says "Using the
  90th percentile will disable latency recovery" in some cases (l.20).

### 3.5 Budget inequalities

Let `I` be the interval (8.333 ms at 120 Hz, 16.667 ms at 60 Hz), `D̂` = p90(draw), and `F` = 1 ms. The source gives
three budgets (INFERRED as a model; each term CONFIRMED above):

| Budget | Inequality | 120 Hz (D̂ ≈ 0.8 ms, INFERRED) | 60 Hz |
|---|---|---|---|
| B1 main on the critical path (main content in *this* frame) | `Q_bmf + T_main + T_commit + T_commit→act + T_act ≤ I − D̂ − F` | ≤ 6.53 ms | ≤ 14.87 ms |
| B2 renderer impl draw by its deadline | `T_impl_anim + T_draw ≤ (I − I/3) − D̂ − F` measured from `frame_time` | ≤ 3.76 ms | ≤ 8.31 ms |
| B3 Viz aggregate + GPU draw by display deadline | `T_aggregate + T_gpu_draw ≤ I/3` (roughly, before swap) | ≤ 2.78 ms | ≤ 5.56 ms |
| B4 throughput (pipelined, high-latency mode) | `max(T_main + T_commit, T_raster_required, T_impl + T_draw) ≤ I` | ≤ 8.33 ms | ≤ 16.67 ms |

**How to read them.**
- B1 failing alone sends Chrome into high-latency mode: main content arrives one frame late but still once per vsync.
  The result is *partial* frames, felt as lag, while the frame rate is not lowered.
- B4 failing means main updates are skipped. These are *dropped* frames for main-thread-driven effects.
- B2 or B3 failing drops even compositor-driven scroll and animations.

v1's finding that the iPhone page "janks" exactly where scroll-linked main-thread effects stop following while the
native scroll continues (`OLD/research/architecture/stats-vs-finger.md` §2) is the WebKit analogue of B1/B4 failing
while B2/B3 hold.

---

## 4. What makes an animation compositor-only

### 4.1 Property eligibility

All CONFIRMED in `cr:third_party/blink/renderer/core/animation/compositor_animations.cc`.

- `kCompositableProperties = { backdrop-filter, filter, opacity, rotate, scale, transform, translate,
  background-color*, clip-path* }`, where * means only with a native paint worklet (l.76-83).
- **`filter` with a pixel-moving operation (blur, drop-shadow) sets `kFilterRelatedPropertyMayMovePixels`** and runs
  on main (l.405-412). `backdrop-filter` stays compositable, because "pixel moving filters do not change the layer
  bounds like regular filters do" (l.414-417).
- A custom property (`--x`) animates on the compositor only if a CSS Paint worklet uses it; otherwise it is
  `kUnsupportedCSSProperty` (l.418-440).
- **Failure reasons** are a 22-flag bitmask (`cr:.../compositor_animations.h` l.69-147). The ones we can act on:

  | Flag | What triggers it |
  |---|---|
  | `kEffectHasUnsupportedTimingParameters` | unsupported timing setup |
  | `kEffectHasNonReplaceCompositeMode` | composite mode other than replace |
  | `kTargetHasInvalidCompositingState` | target not in a valid compositing state |
  | `kTargetHasIncompatibleAnimations` | conflicting animations on the target |
  | `kTargetHasCSSOffset` | CSS `offset-*` (motion path) on the target |
  | `kTransformRelatedPropertyCannotBeAcceleratedOnTarget` | e.g. inline boxes |
  | `kFilterRelatedPropertyMayMovePixels` | pixel-moving filter |
  | `kUnsupportedCSSProperty` | property not compositable |
  | `kMixedKeyframeValueTypes` | mixed keyframe value types |
  | `kTimelineSourceHasInvalidCompositingState` | scroll timeline source not composited |
  | `kAnimationHasNoVisibleChange` | e.g. off-screen or constant values |
  | `kAffectsImportantProperty` | animated property is `!important` |
  | `kUnsupportedInheritance` | a descendant inherits the animated value |

- **Trace visibility.** Each decision is emitted as an `Animation` instant event with `data.compositeFailed` (bitmask)
  and `unsupportedProperties` or `additionalReasons`, in category `blink.animations,devtools.timeline,benchmark,rail`
  (CONFIRMED, `cr:.../animation/animation.cc` l.291, 2683-2687; `cr:.../inspector/inspector_trace_events.cc`
  l.1726-1760). This is the authoritative "is it on the compositor" signal per animation, with no guessing.

### 4.2 Scroll-driven animations

`CanStartScrollTimelineOnCompositor(target)` requires the timeline's source box to have a paint-property `Scroll()`
node that is `UserScrollable()` (CONFIRMED, l.1145-1166). Otherwise the result is
`kTimelineSourceHasInvalidCompositingState`. A ScrollTimeline or ViewTimeline animation of a compositable property on
a composited scroller therefore ticks on the compositor with the scroll. Anything else (JS `scroll` listeners writing
styles, rAF reading `scrollY`) is main-thread work on every scroll frame. That was v1's dominant cost
(`OLD/research/cpu-throttle-calibration/README.md`, "Same culprits at every rate").

### 4.3 Layers, `will-change`, and "squashing"

- **Compositing reasons** (CONFIRMED, `cr:third_party/blink/renderer/platform/graphics/compositing_reasons.h`
  l.20-103):
  - direct: `k3DTransform*`, `kActive{Transform,Scale,Rotate,Translate,Opacity,Filter,BackdropFilter}Animation`,
    `kFixedPosition`, `kStickyPosition`, `kBackdropFilter`, `kWillChange{Transform,Scale,Rotate,Translate,Opacity,
    Filter,BackdropFilter,ClipPath,MixBlendMode,Mask,Other}`, `kOverflowScrolling`, view-transition reasons;
  - post-paint, debugging only: `kOverlap`, `kBackfaceVisibilityHidden`, `kCanvas`, `kVideo`, and others.

  CDP `LayerTree.compositingReasons(layerId)` returns them as `compositingReasons` and `compositingReasonIds`
  (CONFIRMED, devtools-protocol).
- **"Squashing" no longer exists under that name.** Since CompositeAfterPaint, `PaintArtifactCompositor` creates one
  `PendingLayer` per paint chunk, then merges them. Merging is prevented by (CONFIRMED,
  `cr:third_party/blink/renderer/platform/graphics/paint/README.md` l.204-219):
  - a direct compositing reason;
  - overlap with interleaved composited content;
  - **sparsity**: a merge is allowed only if `merged_area − (home_area + guest_area) ≤ 10000 · dpr²` device px
    (`cr:.../compositing/pending_layer.cc` l.206-207, 303).

  One `will-change: transform` element over a large page can thus force neighbours into separate layers through
  overlap. Layer count is a count we must record.
- **Direct property updates.** With `kWillChangeTransform` already layerized, a transform or opacity change skips
  `PaintArtifactCompositor::Update` and only updates the property node (`DirectlyUpdateTransform`). Repaint-only
  changes use `UpdateRepaintedLayers` (CONFIRMED, paint README l.221-237). Pre-paint also has a fast path that updates
  transform and opacity property nodes without a tree-builder walk (CONFIRMED,
  `cr:third_party/blink/renderer/core/paint/README.md` l.448-470). **Implication (INFERRED):** a main-thread rAF
  writing only `transform`/`opacity` on a pre-promoted element costs style + pre-paint fast path + commit, with no
  layout, no paint and no raster. Writing `top`, `height` or a custom property feeding layout costs the full chain.
- **Engine difference** (OBSERVED-v1, CONFIRMED by v1 source reads,
  `OLD/research/architecture/claims-audit.md` §2.4 W1): crossing `opacity:1` and `transform:none` makes WebKit
  re-layout up to the nearest layout boundary. Blink pays only a stacking-context change. **A Chromium count model
  cannot predict this WebKit cost.**

---

## 5. Invalidation: from a DOM write to raster pixels

### 5.1 Style invalidation

Blink compiles selectors into **invalidation sets** (the RuleFeatureSet / `RuleInvalidationData`). A class, id or
attribute change schedules pending invalidations instead of restyling everything. They "err on the side of
correctness, so we invalidate elements that do not need recalculation" (CONFIRMED,
`cr:third_party/blink/renderer/core/css/style-invalidation.md` l.10-70; code in `core/css/invalidation/`).

The count that matters is **elements whose style was computed**, `elementCount` on the `UpdateLayoutTree` end event:
`StyleForElementCount()` delta (CONFIRMED, `cr:third_party/blink/renderer/core/dom/document.cc` l.2818-2870). With
category `disabled-by-default-devtools.timeline.invalidationTracking`, the
`StyleRecalcInvalidationTracking` / `StyleInvalidatorInvalidationTracking` events say which node was invalidated and
why (CONFIRMED that the emitters exist, `cr:.../inspector_trace_events.cc` l.380-394, 509-620; the category name is
INFERRED from DevTools usage).

Custom properties: v1 found WebKit's `style_recalc_var` 2.2× slower on the fastwork page than on a blank page
(OBSERVED-v1, `OLD/research/cpu-throttle-calibration/README.md`). In Blink, changing an *inherited* custom property on
an ancestor restyles its subtree. A registered `@property` with `inherits: false` limits that (INFERRED from the CSS
Properties & Values spec; not source-verified here).

### 5.2 Layout dirty bits

`Layout` begin args (CONFIRMED, `cr:.../inspector_trace_events.cc` l.632-646) give:
- `dirtyObjects`, the number of LayoutObjects needing layout;
- `totalObjects`;
- `partialLayout`, true when the layout started below the root, at a relayout boundary.

A forced (synchronous) layout appears as `Layout` with a JS stack (`SetCallStack`) inside a script slice.
`Performance.getMetrics` `LayoutCount` counts outermost `UpdateLayout` probes (nested ones excluded, depth counter)
(CONFIRMED, `cr:.../inspector/inspector_performance_agent.cc` l.344-356).

### 5.3 Paint invalidation and paint

- **Pre-paint** walks marked subtrees, calls `LayoutObject::InvalidatePaint()` and marks display-item clients
  (CONFIRMED, `cr:third_party/blink/renderer/core/paint/README.md` l.212-246).
- **Paint** then re-records only invalidated clients. The rest is cached through `UseCachedItemIfPossible` and
  subsequence caching (CONFIRMED, `cr:.../platform/graphics/paint/README.md` l.176-202).
- **Caution for metrics.** The `Paint` trace event's `clip` quad is the **contents cull rect**, not the invalidated
  area (CONFIRMED, `cr:.../inspector_trace_events.cc` l.1105-1115:
  `CreateQuad(dict.AddItem("clip"), ... contents_cull_rect)`). v1's plan to sum `Paint args.data.clip` area as "paint
  area" (`OLD/research/architecture/devtools-methodology.md` G3(a)) would measure the cull rect, which can be far
  larger than what is repainted. Use raster-invalidation rects (§5.4) for area.

### 5.4 Raster invalidation

`RasterInvalidator` compares the old and new paint artifacts (CONFIRMED,
`cr:.../platform/graphics/paint/README.md` l.239-292):
- **Chunk level:**
  - an appearing or disappearing chunk invalidates its full bounds;
  - a reordered chunk invalidates both old and new bounds;
  - a property change invalidates old and new bounds fully, except a clip-only change, which is incremental (the
    difference only).
- **Display-item level** (unchanged chunk): invalidated clients get a full (old ∪ new visual rect) or incremental
  invalidation by `PaintInvalidationReason`.

**Getting the rects.** Tracing `disabled-by-default-blink.invalidation` turns tracking on
(`cr:.../paint/raster_invalidation_tracking.cc` l.34-36). The rects are pushed into `cc::LayerDebugInfo` (l.128-137)
and serialized as `annotated_invalidation_rects` in the layer snapshot (`cr:cc/layers/layer_impl.cc` l.905-906).
Summing those rects × dpr² per frame gives **raster-invalidated device pixels**, the best upstream proxy for raster
cost. That the snapshot also needs `disabled-by-default-devtools.timeline.layers` or `cc.debug` is INFERRED; check it
with one trace.

### 5.5 Tiles and raster

- **GPU raster tile size** (CONFIRMED, `cr:cc/layers/tile_size_calculator.cc` l.40-85, 140-170):
  - the width is the viewport width, halved when the content is wider;
  - the height is ⌈viewport height / 4⌉ (divisor 4; 2 or 1 for narrow layers);
  - plus 2 border texels, rounded up to a multiple of 32.

  Software raster uses `default_tile_size` from settings. At 430×932 CSS px and DPR 3 (v1's iPhone emulation), one
  full-width tile is about 1312 × 704 device px (INFERRED arithmetic). Invalidating a 1 px line therefore re-rasters at
  least one whole tile, and **tiles rastered × tile area** over-counts the invalidated area in a predictable way.
- **Interest area and prepaint:** `skewport_target_time_in_seconds = 1.0` (0.2 for GPU raster) and
  `tiling_interest_area_padding` (CONFIRMED, `cr:cc/trees/layer_tree_settings.h` l.63-109). Scrolling rasters ahead
  of the viewport, so raster work during scroll is **not** zero for a static page. It is a function of scroll velocity
  and the distance to new content.
- **Checkerboarding:** a frame drawn with missing tiles sets `checkerboarded_needs_raster` / `_needs_record` in
  `FrameInfo` and in the PipelineReporter (CONFIRMED, `cr:cc/metrics/compositor_frame_reporter.cc` l.1536-1541).

---

## 6. Dropped-frame accounting today

### 6.1 Frame outcome per vsync

`FrameInfo::FrameFinalState` (CONFIRMED, `cr:cc/metrics/frame_info.h` l.18-42) is one of:
- `kNoUpdateDesired`;
- `kDropped`;
- `kPresentedAll`;
- `kPresentedPartialOldMain`;
- `kPresentedPartialNewMain`;
- `kPresentedPartialWithoutWaiting`.

Separate final states exist for V4, raster-property and raster-scroll. `SmoothThread` says which thread(s) were
expected to be smooth; `IsDroppedAffectingSmoothness()` is true when that thread's update was dropped (CONFIRMED,
`cr:cc/metrics/frame_info.cc` l.48-55).

### 6.2 Sequences

`FrameSequenceTrackerType` (CONFIRMED, `cr:cc/metrics/frame_sequence_metrics.h` l.29-48) is one of:
- `kCompositorAnimation`, `kMainThreadAnimation`, `kPinchZoom`, `kRAF`, `kTouchScroll`, `kVideo`, `kWheelScroll`,
  `kScrollbarScroll`, `kCustom`, `kCanvasAnimation`, `kJSAnimation`;
- `kSET{Main,Compositor}Animation`, `kCompositorRasterAnimation`, `kCompositorNativeAnimation`.

**This is Chromium's own main-vs-compositor animation classification**, per active sequence.

### 6.3 Formulas

All CONFIRMED in `cr:cc/metrics/frame_sequence_metrics.cc`.

- **Per sorted frame** (l.560-600):
  - compositor-effective sequence: `expected += 1`, and `dropped += 1` if the compositor update was dropped;
  - main-effective sequence: only when a main update was expected;
  - raster-effective sequence: drops counted in V4 only.
- **`PercentDroppedFrames3.<thread>.<type>` = `ceil(100 · dropped / expected)`**, reported only when
  `expected ≥ kMinFramesForThroughputMetric = 100` (l.81, 136-147, 314-326). V4 uses the raster-property-aware drop
  definition.
- **`Jank3`**: a presented frame is janky when
  `Δ_now > Δ_prev + 0.5 · interval`, where `Δ` = termination-time gap minus no-update time (l.614-690). The comment:
  "the 0.5 * frame_interval criterion is chosen so that the jank detection is robust to those fluctuations" (l.673-676).
  Sequences idle for at least `kMaxNoUpdateFrameCount = 100` frames ignore the next frame (l.64, 634-639).

### 6.4 `DroppedFrameCounter` is gone

It was deleted in commit `9e56a8798315` (2025-06-20, "Delete DroppedFrameCounter", Cr-Commit-Position 1476342,
crbug 409093076 and 422432528), after `6254131b59f9` "Move some DFC logic to FrameSorter" (CONFIRMED,
`gh api repos/chromium/chromium/commits?path=cc/metrics/dropped_frame_counter.cc`).
- The [web.dev smoothness article](https://web.dev/articles/smoothness) describes a "Worst Case of Percent Dropped
  Frames … over 1 second sliding windows". That sliding-window computation lived in DFC, so **the doc's
  sliding-window metrics should be treated as historical** (INFERRED: no replacement found in `cc/metrics/`).
- **We compute our own sliding windows** from per-frame states. That is a pure reducer: Lean-specifiable and
  testable (§9.6).

### 6.5 Trace-side signals

- **`PipelineReporter`** slices: state `PRESENTED_ALL`, `PRESENTED_PARTIAL`, `DROPPED` or `NO_UPDATE_DESIRED`, with
  `affects_smoothness`, `has_missing_content` and `scroll_state` (CONFIRMED, `cr:cc/metrics/compositor_frame_reporter.cc`
  l.1498-1560).
- **DevTools `DroppedFrame`** comes from `devtools_instrumentation::DidDropSmoothnessFrame(..., has_partial_update)`
  (l.1492-1496). It is what the DevTools Frames track reads (v1 G1, `OLD/research/architecture/devtools-methodology.md`).
- **Scroll Jank v4**: Perfetto `chrome_scroll_jank_v4_results` / `_reasons` with `vsyncs_since_previous_frame`.
  "Available since Chrome 145.0.7573.0" (CONFIRMED, `pf:src/trace_processor/perfetto_sql/stdlib/chrome/scroll_jank_v4.sql`
  l.95-130).
- **`chrome_graphics_pipeline_*`** Perfetto tables for the Viz steps (`pf:.../chrome/graphics_pipeline.sql` l.7-70).
- **Telemetry's rendering benchmark** collects:
  - `Graphics.Smoothness.{PercentDroppedFrames3,PercentDroppedFrames4,Jank3,Checkerboarding4}.{AllAnimations,AllInteractions,AllSequences}`;
  - `EventLatency.GestureScrollUpdate.*`;
  - `Event.ScrollJank.*`.

  It runs with `--enable-gpu-benchmarking` (CONFIRMED, `cr:tools/perf/benchmarks/rendering.py` l.20-46, 91, 108-127).

---

## 7. Deterministic work counts we can extract

### 7.1 How to make counts deterministic

INFERRED design; each mechanism is CONFIRMED where cited.

- **Frame stepping.** `HeadlessExperimental.beginFrame({frameTimeTicks, interval, noDisplayUpdates, screenshot}) →
  {hasDamage, screenshotData}`. It "Requires that the target was created with enabled BeginFrameControl. Designed for
  use with --run-all-compositor-stages-before-draw" (CONFIRMED, devtools-protocol `HeadlessExperimental`).
  - The switches `--enable-begin-frame-control` and `--deterministic-mode` are defined in Chromium's `headless/`
    shell (CONFIRMED, `cr:headless/public/switches.h`).
  - Since M132 that shell is only `chrome-headless-shell` (CONFIRMED, `cr:headless/README.md` l.8-16).
  - Playwright ships `chromium-headless-shell` for headless Chromium since 1.49 (CONFIRMED in substance by
    [playwright#33566](https://github.com/microsoft/playwright/issues/33566)).
  - With all compositor stages run before draw, **every frame contains the main frame**, so there are no
    partial/dropped outcomes. Counts are a pure function of (build, flags, scroll position, animation time).
- **Time.** Use Playwright `page.clock` and per-step animation seeking, as specified in kickoff note 02 §3.5. Scroll by
  a fixed amount of px per virtual frame.
- **Normalisation.** Report counts **per virtual frame and per 100 px scrolled**. In real-time runs the number of
  frames per scroll distance depends on the frame rate, so raw totals are not comparable (INFERRED).
- **Repeatability check.** Two identical runs must give byte-identical count vectors. Any difference is a harness bug
  (a Lean-checkable contract, §9.6).

### 7.2 Catalogue

| # | Count `x` | Unit | Interface | Source citation | Deterministic? |
|---|---|---|---|---|---|
| C1 | style passes | per frame | `Performance.getMetrics` `RecalcStyleCount` delta, or trace `UpdateLayoutTree` slices | `inspector_performance_agent.cc` l.202-206, 324-331 | yes with stepping |
| C2 | elements restyled | elements | trace `UpdateLayoutTree` end arg `elementCount` | `document.cc` l.2825, 2867-2870 | yes |
| C3 | layout passes, forced layouts | per frame | `LayoutCount`; trace `Layout` (forced = inside a script slice, with stack) | perf agent l.344-356; trace events l.632-646 | yes |
| C4 | layout objects dirtied / total, partial? | objects | `Layout` `beginData.dirtyObjects/totalObjects/partialLayout` | trace events l.632-646 | yes |
| C5 | pre-paint runs | per frame | trace `PrePaint` | `local_frame_view.cc` l.2629 | yes |
| C6 | paint runs; painted layout objects | per frame | trace `Paint` (count, `nodeId`); **not area** (cull rect) | trace events l.1105-1115 | yes |
| C7 | paint ops / display items recorded; record time | ops | `chrome.gpuBenchmarking.runMicroBenchmark("rasterize_and_record_benchmark")` → `paint_op_count`, `record_time_ms`, `pixels_recorded`, `raster_invalidation_and_convert_time_ms`, `paint_artifact_compositor_update_time_ms` (needs `--enable-gpu-benchmarking`) | `cr:cc/benchmarks/rasterize_and_record_benchmark.cc` l.30-31, 67-86; `content/renderer/gpu_benchmarking_extension.cc` l.697 | counts yes; times are repeat-averaged (100×) microbench timings |
| C8 | raster-invalidated area | device px² | trace `disabled-by-default-blink.invalidation` + layer snapshot `annotated_invalidation_rects` | §5.4 citations | yes |
| C9 | pixels rasterized, layers, picture layers, off-screen layers | px, layers | same microbenchmark → `pixels_rasterized`, `pixels_rasterized_with_non_solid_color`, `total_layers`, `total_picture_layers*` | `rasterize_and_record_benchmark_impl.cc` l.170-191 | yes (state snapshot, not per frame) |
| C10 | tiles rastered per frame | tiles (× tile area) | trace `RasterTask` (cat `cc,disabled-by-default-devtools.timeline`) with tile data | `cr:cc/tiles/frame_viewer_instrumentation.cc` l.17-53 | yes with stepping; depends on the skewport (§5.5) |
| C11 | composited layers; drawsContent; paintCount; reasons | layers | CDP `LayerTree.enable` → `layerTreeDidChange.layers[]` (`paintCount`, `drawsContent`, `backendNodeId`, …), `LayerTree.compositingReasons` | devtools-protocol `LayerTree`; **`layerPainted` dead since M148** (OBSERVED-v1 + Chromium `1bf9d9eb378c`, `OLD/research/architecture/claims-audit.md` §2.2) | yes; tool overhead large (v1: −17 fps in one A/A, claims-audit C2), so use the counts lane only |
| C12 | animations: total / compositor / main + failure reasons | animations | trace `Animation` events `compositeFailed`; CDP `Animation` domain for the list (`type`, `viewOrScrollTimeline`), not compositor status | §4.1 citations; devtools-protocol `Animation.Animation` | yes |
| C13 | rAF callbacks, script time | callbacks | trace `FireAnimationFrame`; `ScriptDuration` | trace events l.1024 | count yes; ms no |
| C14 | BMF per frame, commits per frame | per frame | `PipelineReporter` stages; `Commit` slices | `compositor_frame_reporter.h` l.91-105 | yes with stepping; ≤ 1 BMF per BeginFrame (§3.2) |
| C15 | DOM size, listeners | nodes | `Performance.getMetrics` `Nodes`, `JSEventListeners`, `LayoutObjects` (instance counters) | perf agent l.194-198 | yes |
| C16 | non-passive touch/wheel listeners on the scroll path | listeners | `DOMDebugger.getEventListeners` (v1 used it) | `OLD/research/architecture/devtools-methodology.md` M11 | yes |
| C17 | composited area / overdraw | px² | Σ over layers (`width × height × dpr²`, visible) from C11 + transforms | INFERRED derivation | yes |
| C18 | pixel-moving filters on screen | px² × radius | layer list + computed style of the filtered nodes | INFERRED | yes |

**Timing-only signals.** These are not counts. They are needed for calibration on a real Chromium device, not in the
counts lane:
- `PipelineReporter` stage durations and states;
- `Graphics.Smoothness.*` UMA;
- `EventLatency`;
- `chrome_scroll_jank_v4_results`;
- `DroppedFrame`.

### 7.3 Trace config

INFERRED; the category names are CONFIRMED where cited above.

```
devtools.timeline, disabled-by-default-devtools.timeline, disabled-by-default-devtools.timeline.frame,
blink.animations, cc, viz, gpu, benchmark,
disabled-by-default-blink.invalidation, disabled-by-default-devtools.timeline.layers,
disabled-by-default-devtools.timeline.invalidationTracking   (attribution runs only)
disabled-by-default-cc.debug.scheduler                       (scheduler-state runs only: deadline mode, MainThreadLatency counter, scheduler.cc l.647-652)
```

- Use `Tracing.start` with `traceConfig` or `perfettoConfig`, `transferMode: ReturnAsStream`, proto format.
- Query the trace with Perfetto `trace_processor` (Python or the `trace_processor_shell` binary). Do not write a
  custom JSON parser.

### 7.4 Perfetto SQL sketches

INFERRED; these are not run, and the argument key paths must be checked against the first trace.

```sql
-- per-frame main-thread stage counts and durations
INCLUDE PERFETTO MODULE slices.with_context;
SELECT name, COUNT(*) AS n, SUM(dur)/1e6 AS ms
FROM thread_slice
WHERE thread_name = 'CrRendererMain'
  AND name IN ('UpdateLayoutTree','Layout','PrePaint','Paint','Layerize','FireAnimationFrame')
GROUP BY name;

-- elements restyled (end-event arg; key path to verify: 'args.elementCount' vs 'debug.elementCount')
SELECT SUM(EXTRACT_ARG(arg_set_id, 'debug.elementCount')) FROM slice WHERE name = 'UpdateLayoutTree';

-- frame outcomes
SELECT EXTRACT_ARG(arg_set_id, 'chrome_frame_reporter.state') AS state, COUNT(*)
FROM slice WHERE name = 'PipelineReporter' GROUP BY state;
```

---

## 8. Which counts drive which stage

All INFERRED, from §3 to §5.

| Stage `s` | Drivers `x_{s,j}` | Fixed cost `κ_s` |
|---|---|---|
| Script | rAF callbacks, handler calls (C13); plus the app's own work, which is not counted. Treat it as measured ms × a device JS factor; v1 found the iPhone JS speed ≈ Mac Chrome 1× (`OLD/research/cpu-throttle-calibration/README.md`) | task overhead |
| Style | passes (C1), elements restyled (C2), custom-property fan-out (C2 restricted to `--*` writers) | per pass |
| Layout | passes (C3), dirty objects (C4), forced layouts (C3) | per pass |
| Pre-paint | dirty objects + objects needing paint invalidation (C4, C6), fast-path updates (≈ 0) | per pass |
| Paint | painted objects (C6), paint ops recorded (C7) | per pass |
| Layerize | `PaintArtifactCompositor::Update` full vs direct/repaint-only (§4.3); layers (C11) | per update |
| Commit | layers changed, property nodes changed (C11 deltas) | per commit (C14) |
| Raster | invalidated device px (C8), tiles (C10), paint ops in those tiles (C7), image px decoded | per tile task |
| Impl/draw | compositor animations (C12), layers drawn (C11), render passes (filters, C18) | per draw |
| GPU/Viz | composited area (C17), overdraw, filter px × radius (C18), backdrop-filter readbacks | per swap |

---

## 9. The cost model

### 9.1 Form

All INFERRED. For a device `d`, an engine `e` (Blink here) and a frame `f`:

```
T_s(f) = κ_{s,d} + Σ_j c_{s,j,d} · x_{s,j}(f) + ε_s(f),     c ≥ 0, κ ≥ 0
T_main(f) = T_script + T_style + T_layout + T_prepaint + T_paint + T_layerize      (serial, main thread)
T_crit(f) = Q_bmf + T_main(f) + T_commit(f) + T_raster_required(f) + T_activate    (budget B1)
T_impl(f) = T_impl_anim + T_draw(f);  T_viz(f) = T_aggregate + T_gpu(f)             (budgets B2, B3)
```

The frame inequality for an `N` Hz display, with `I = 1000/N` ms, is all of B1 to B4 from §3.5.

**Predicted outcomes per frame:**

```
k_main(f)  = max(1, ⌈(T_main(f) + T_commit(f)) / I⌉)    -- vsyncs consumed by main-thread update (B4, pipelined)
lag(f)     = [T_crit(f) > I − D̂ − 1 ms]                  -- one extra frame of latency (B1 fails, partial frame)
k_cc(f)    = max(1, ⌈max(T_impl(f), T_viz(f)·3) / I⌉)    -- compositor/display misses (B2/B3)
missed_main = Σ_f (k_main(f) − 1)                       -- comparable to v1 "k ≥ 2 vsync" counts
```

For an effect driven by `kMainThreadAnimation`/`kRAF`, the predicted `PercentDroppedFrames3.Main ≈ 100 · missed_main
/ (frames + missed_main)`. For compositor-driven effects, use `k_cc`. Report both per **part** (feature flag) and per
**scroll zone**. v1 showed that a whole-page average hides the zone the finger feels (stats-vs-finger §2 item 1).

**Why a deterministic per-frame `x` plus a stochastic `ε` is the right shape.** Chromium itself schedules using
p90 estimates over 60 samples (§3.4), so tail behaviour, not means, decides deadlines. We fit `c` for the mean and
also fit a p90 model (quantile regression, τ = 0.9). The **p90 prediction** is what goes into the budget
inequalities. This mirrors the scheduler's own decision rule.

### 9.2 Calibration (per device, per OS / browser version)

1. **Timing ground truth.**
   - On a Chromium device (Mac Chrome, optionally an Android phone): `PipelineReporter` and BlinkBreakdown stage
     durations per frame, plus main-thread slices (§1.3, §7.3). One traced run gives about 10³ frames × 10 stages.
   - On the iPhone (WebKit): per-frame `RenderingFrame` segments Script / Layout / Paint / Composite, as in v1
     (`OLD/research/architecture/measurement-protocol-v2.md` table at l.146). These are coarser stages, so fewer
     coefficients are identifiable. WebKit counts come from the WebKit note.
2. **Make counts vary independently.** Use the v2 feature flags (note 02 §3.3) to run a **fractional factorial
   design**: each part on/off, or variant A/B, in 16 to 32 configurations. The counts per stage then vary roughly
   orthogonally and each coefficient is identifiable. Avoid collinear designs, such as only "whole page" vs "nothing".
3. **Micro-fixtures** (synthetic pages, ours, no Fastwork code). Each fixture sweeps one count:
   - N elements restyled per frame;
   - N layout objects dirtied;
   - an A px² invalidated area;
   - L layers with `will-change`;
   - blur radius r over area A;
   - backdrop-filter area A.

   Each fixture gives the slope `c_{s,j}` directly. This is the Chromium `rasterize_and_record` idea applied to every
   stage. About 10 minutes per device session.
4. **Fit.** Per stage: non-negative least squares for `c, κ`, plus quantile regression at τ = 0.9. Use a Huber loss
   for outliers such as GC pauses. Add a per-run multiplicative factor `θ_run`, estimated from a fixed bench fixture
   before and after (v1's `cpu_bench.js` idea, `OLD/research/cpu-throttle-calibration/README.md`), to absorb thermal
   and DVFS drift. This makes it a mixed model: `T = θ_run · (κ + c·x) + ε`.
5. **Drift guard.** Re-run the micro-fixtures at the start of every device session. If any `c` moves outside its 90 %
   interval, the device coefficients are stale and the model is marked uncalibrated.

### 9.3 Validation

All INFERRED; the thresholds are proposals for the user.

| Check | How | Pass (proposal) |
|---|---|---|
| Stage fit | leave-one-configuration-out cross-validation; MAPE and R² per stage | stage MAPE ≤ 20 % at p50; p90 model coverage 85-95 % |
| Frame-miss prediction | predicted vs measured `missed_main` per scenario × zone on held-out configurations; Spearman ρ | ρ ≥ 0.8 |
| **Decision agreement** | for held-out A/B pairs, the sign of the predicted Δmissed vs the measured Δ, only where the prediction exceeds the A/A noise band | ≥ 90 % agreement, 0 sign errors among "large" predictions |
| Feel agreement | the v1 rule: N ≥ 5 blind verdicts incl. ≥ 1 "same"; predictions frozen before the verdict (`OLD/research/architecture/stats-vs-finger.md` §5) | 5/5, no sign disagreement |
| Interval calibration | bootstrap residuals → prediction intervals; check empirical coverage | within ±10 % of nominal |
| Spot-check | 1 device A/B per K = 5 landings (v1 §5) | demote on any sign disagreement |

**Pre-registration.** Each candidate optimisation carries a predicted Δ (by stage and zone) from counts alone. The
device run then validates the *model*, not just the change. That is how the device leaves the inner loop.

### 9.4 What the model buys

All INFERRED.
- **Inner loop with no device and no timing lock.** Counts run in the parallel counts lane (note 06 §2.4) on
  `chrome-headless-shell`, byte-reproducible. A tool change re-runs only the plugins whose `semantics` changed
  (note 06 §3).
- **Attribution.** A predicted miss names its stage and its count. "Style: 1,840 elements restyled per frame in zone
  1200-1800 px" is actionable; a 6×-throttled rAF gap is not.
- **Static checks.** The compositor-only property rules (§4.1) and the `compositeFailed` bits can gate each part's
  animations in CI: "part P animates only compositable properties, and no animation reports `compositeFailed ≠ 0`".

### 9.5 Known limits

| Limit | Why | Mitigation |
|---|---|---|
| **WebKit-only costs** (the iPhone is the target) | different invalidation rules: opacity/transform flip → layout (claims-audit W1); custom-property recalc 2.2× (cpu-throttle README); UI-process scrolling and the Core Animation render server, invisible to rAF (stats-vs-finger §2 item 4); 60 Hz rAF cap (claims-audit P9) | a separate WebKit count vector + coefficients (WebKit note); never predict iPhone feel from Blink counts alone |
| GPU raster / draw non-linearity | blur cost grows with radius × area; MSAA; backdrop-filter readback; tile-memory eviction → checkerboarding; GPU-process contention | C17/C18 features + fixtures; validate GPU claims on device (v1: large-area-blur flat in Chrome, real on phone, `OLD/research/architecture/measurement-review.md` §1) |
| Thermal / DVFS | coefficients shift with temperature and governor state; small work at low clock is non-linear | `θ_run` random effect; thermal gate (v1 `tools/thermal.mjs` idea) |
| JIT tiers, GC, image decode, fonts | stochastic or one-off costs | warm-up frames excluded; GC pauses as Huber outliers; decode counted separately |
| Pipelining and scheduler adaptivity | the scheduler switches latency modes on its own p90 estimates; frames interact | simulate the scheduler with our p90 predictions (a small state machine, §9.6) rather than treating frames independently |
| Input path | touch vs scripted scroll differ (non-passive `touchmove`, toolbar `resize`; v1 cpu-throttle README) | drive with `Input.synthesizeScrollGesture` touch / Playwright touch; keep the device for input-path claims |
| Headless ≠ display | no presentation in headless (v1 `OLD/research/architecture/headless-functional.md` C14) | headless only for counts; timing only headed or on a device |
| Unmodelled app script | JS cost is not a count | measure script ms per part at 1× on the Mac, scale by the device JS factor; React rewrite keeps per-frame JS small and explicit |

### 9.6 Where Lean fits

All INFERRED; the Lean note owns the details.

- **Spec the reducers.** These are pure functions over frame lists, and v1's bugs lived in exactly such reducers (the
  50.0 ms coin toss at 60 Hz, claims-audit §2.3):
  - `PercentDroppedFrames3 = ⌈100·d/e⌉` with the `e ≥ 100` gate;
  - the Jank3 rule;
  - our sliding-window metrics;
  - vsync-tick bucketing `k = ⌈T/I⌉` with midpoint cuts.

  Prove properties in Lean (monotonicity, bounds), then differential-test the TypeScript implementation against the
  Lean executable spec.
- **Prove model-level lemmas.**
  - With `c ≥ 0`, `x ≤ x'` componentwise implies `T(x) ≤ T(x')` and `missed(x) ≤ missed(x')`. So "every count went
    down" safely implies "predicted misses did not go up", and the loop can auto-land class-A changes.
  - B1 to B4 holding implies predicted `missed = 0`.
- **Specify the scheduler abstraction.** Model the §3 deadline-mode function and the "≤ 1 BMF per BeginFrame / no
  BMF while SENT" invariants as a small Lean state machine. It serves as the simulator in §9.5 row 5.
- **Not provable:** the coefficients and the engine's real behaviour. Those are empirical and stay under §9.3
  validation.

---

## 10. Plan for the first wave

All INFERRED. Each step is S to M sized.

1. **P1 counts plugin** (`chromium.trace-counts`): `chrome-headless-shell` + BeginFrameControl + virtual clock +
   scripted scroll profile. It outputs C1-C6, C8, C10-C14 per virtual frame per zone. Acceptance: two runs give
   byte-identical output (§7.1). First verify the arg key paths (§7.4) and the snapshot categories (§5.4).
2. **P2 microbench plugin** (`chromium.raster-record`): `--enable-gpu-benchmarking`, `rasterize_and_record_benchmark`
   at fixed scroll stops → C7, C9.
3. **P3 compositor gate**: per part, every animation's `compositeFailed` must be 0, and the layer count must equal the
   declared layer budget (C11, C12).
4. **P4 calibration fixtures**: about 8 synthetic pages (§9.2 step 3), stored in the repo and versioned.
5. **P5 Mac Chrome calibration**: headed, a traced timing lane, 16-32 flag configurations × 3 runs. Fit the model,
   then run the §9.3 cross-validation. This tests the method on Chromium before any phone time.
6. **P6 iPhone**: done jointly with the WebKit note. Calibrate WebKit coefficients from `RenderingFrame` segments on
   the same configurations. Re-measure the v1 blind-verdict pairs, where the builds can be rebuilt as flag
   configurations, for the feel-agreement check.

---

## 11. Comparison with v1

| Aspect | v1: CPU 6× throttle (`OLD/research/cpu-throttle-calibration/`) | v2: counts + cost model |
|---|---|---|
| What is calibrated | one scalar on renderer main-thread speed, chosen so long-frame counts match the iPhone on the unfixed page (distance 0.17 at 6×) | per-stage, per-count coefficients per device, from fixtures and factorial flag designs |
| Linearity | super-linear for DOM work: 4× → 5.0×, 6× → 7.8×, 20× → 30.9× (OBSERVED-v1, README "Other key facts") | linear in counts by construction; non-linearity handled by features (radius × area) and checked by fixtures |
| GPU / raster | not slowed by throttling ("GPU main-thread busy stays ~17-24 % at every rate", OBSERVED-v1) | modelled stages (C8-C10, C17, C18) with their own coefficients |
| Drift when the page changes | the mapping was fitted on the unfixed page; the mix changes with fixes (v1 `devtools-methodology.md` §2b) | coefficients are per unit of work, so they do not depend on the page mix; drift only with device or browser version (guarded) |
| Run cost | timing runs: exclusive lock, n ≥ 5 ABBA, host-load gate; parallel runs contaminate (v1 `headless-60-calibration/README.md` "Answer" 3) | counts: parallel, headless, deterministic, cacheable; timing only for calibration |
| What it explains | "there is jank" | which stage, which part, which zone, how much |
| WebKit costs | invisible (also invisible to the throttle) | invisible to Blink counts, but they get their own WebKit counts and coefficients |
| Validated against feel | partially: scripted S counts 0/2 on blind pairs (stats-vs-finger §1) | must pass §9.3 before replacing the device; the same ledger rule |

**Net (INFERRED).** v2 keeps v1's sound parts:
- device-anchored calibration;
- blind-verdict validation;
- zone metrics;
- vsync-tick classification.

It replaces the single throttle scalar with an engine-structured model whose inputs are reproducible counts.

---

## 12. Risks

All INFERRED.

1. **Over-trusting counts.** v1's cost card was right about the work and wrong about feel. The model must be judged
   on decision agreement and feel agreement, not on R².
2. **BeginFrameControl drift.** `HeadlessExperimental` is experimental, and headless shell is a separate binary. If it
   regresses or is removed, the fallback is Playwright clock + rAF stepping, with counts per rAF and no compositor
   stepping.
3. **Trace overhead.** Heavy categories (invalidation tracking, layers) perturb timing. Never mix counts-lane traces
   into timing data (v1 claims-audit C2).
4. **Collinearity.** If the flag designs are not varied enough, coefficients are unidentifiable. Fixtures mitigate
   this.
5. **Version churn.** Several metric surfaces changed recently: DFC was deleted in 2025, `layerPainted` died at M148,
   scroll jank v4 arrived at M145. Pin the Chrome version per calibration and re-check the trace schemas on upgrade.

---

## 13. Sources

**Chromium** (all at `fcacb60bd396`):

| Area | Files |
|---|---|
| scheduler and timing | `cc/scheduler/scheduler_state_machine.{h,cc}`, `cc/scheduler/scheduler.cc`, `cc/metrics/compositor_timing_history.cc` |
| Viz | `components/viz/common/frame_sinks/begin_frame_args.h`, `components/viz/common/frame_sinks/begin_frame_source.cc`, `components/viz/service/display/display_scheduler.cc`, `components/viz/service/frame_sinks/compositor_frame_sink_support_unittest.cc` |
| frame metrics | `cc/metrics/{frame_info.h,frame_info.cc,frame_sequence_metrics.h,frame_sequence_metrics.cc,compositor_frame_reporter.h,compositor_frame_reporter.cc}` |
| animation | `third_party/blink/renderer/core/animation/{compositor_animations.h,compositor_animations.cc,animation.cc}` |
| compositing and paint | `third_party/blink/renderer/platform/graphics/compositing_reasons.h`, `third_party/blink/renderer/platform/graphics/paint/{README.md,raster_invalidation_tracking.{h,cc}}`, `third_party/blink/renderer/platform/graphics/compositing/pending_layer.cc`, `third_party/blink/renderer/core/paint/README.md` |
| style, lifecycle, instrumentation | `third_party/blink/renderer/core/css/style-invalidation.md`, `third_party/blink/renderer/core/dom/{document_lifecycle.h,document.cc}`, `third_party/blink/renderer/core/frame/local_frame_view.cc`, `third_party/blink/renderer/core/inspector/{inspector_performance_agent.cc,inspector_trace_events.cc}` |
| cc layers and tiles | `cc/layers/{tile_size_calculator.cc,layer_impl.cc}`, `cc/trees/layer_tree_settings.h`, `cc/tiles/frame_viewer_instrumentation.cc` |
| benchmarks and headless | `cc/benchmarks/rasterize_and_record_benchmark{,_impl}.cc`, `content/renderer/gpu_benchmarking_extension.cc`, `tools/perf/benchmarks/rendering.py`, `headless/README.md`, `headless/public/switches.h` |

**Chromium history:**
- `9e56a8798315` "Delete DroppedFrameCounter" (2025-06-20, crbug 409093076, 422432528);
- `6254131b59f9`;
- `1bf9d9eb378c` (crbug 488803411, via v1 claims-audit).

**Perfetto** (`34ab25188c36`): `src/trace_processor/perfetto_sql/stdlib/chrome/{graphics_pipeline.sql,scroll_jank_v4.sql,vsync_intervals.sql,chrome_scrolls_v4.sql}`.

**DevTools protocol** (`e908551762a5`): domains `HeadlessExperimental`, `LayerTree`, `Animation`, `Performance`,
`Tracing`, `Input.synthesizeScrollGesture`, `Emulation.setCPUThrottlingRate`.

**Docs:**
- https://developer.chrome.com/docs/chromium/renderingng-architecture
- https://web.dev/articles/smoothness
- https://github.com/microsoft/playwright/issues/33566
- "Life of a Pixel" (Chromium design-doc slides; not re-read for this note)

**v1** (`OLD/`, read-only):
- `research/cpu-throttle-calibration/README.md`
- `research/headless-60-calibration/README.md`
- `research/architecture/{stats-vs-finger.md,devtools-methodology.md,claims-audit.md,measurement-protocol-v2.md,headless-functional.md,measurement-review.md}`
- `tools/costcard.mjs` (header only)

**Sibling kickoff notes:**
- `research/kickoff/02-site-anatomy-and-rewrite.md` §3.3, §3.5, §4.6
- `research/kickoff/06-architecture-and-tooling.md` §2.4, §3

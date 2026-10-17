---
id: 2026-10-18-engine-chromium-pipeline
kind: note
title: "Chromium rendering pipeline for scroll- and time-driven animations, as a model Lean can encode"
status: review
created: 2026-10-18
topics: [chromium, rendering, animation, scrolling, lean-model, counts-lane]
---

# Chromium pipeline for animations: a model Lean can encode

Source: the pinned sparse clone `.cache/upstream/chromium@f842f52` (Chrome Headless Shell 156.0.8078.4, the CI
counts lane). I added these paths to the clone with `node scripts/refs-fetch.mjs chromium --paths …`: `core/style`,
`core/dom/document*`, `core/page`, `core/scroll`, `core/inspector/inspector_trace_events.cc`,
`platform/graphics/{paint,compositing}`, `cc/{input,animation,base/devtools_instrumentation.*,layers/*.cc}`.
Three files came by curl at the same sha: `headless/lib/browser/command_line_handler.cc`, `blink/common/features.cc`
and `platform/runtime_enabled_features.json5`.
Abbreviations: `B/` = `third_party/blink/renderer/`. Every citation is `@f842f52`.
This note builds on `research/kickoff/03-chromium-rendering-math.md`, which used an unpinned commit. Where the two
overlap, this note re-checks the claim at the pin.

## 0. Answer first

- **A frame is a fixed sequence of stages, and most frames skip most of them.** On the main thread, BeginMainFrame
  runs the script steps (scroll events, animations, rAF), then style, layout, pre-paint, paint and Layerize, then a
  blocking commit. On the compositor thread come activate, impl animation tick, draw, and tile raster on worker
  threads. Each stage runs only when something is dirty, and its work is proportional to a count we can name
  (section 1).
- **Invalidation is a join-semilattice.** `StyleDifference` merges by `max` on two ordered enums and by `or` on
  about 20 flags (CONFIRMED, `B/core/style/style_difference.h:20-44,112-116`). `PaintPropertyChangeType` is a
  5-level ordered enum (CONFIRMED, `B/platform/graphics/paint/paint_property_node.h:30-58`). Lean can encode both
  as `Fin n` with `max`, which makes "the optimized change invalidates no more than the original" a pointwise `≤`.
- **Property classes** (section 2). Each property's invalidation groups are generated from
  `css_properties.json5 invalidate:`.
  - transform, translate, scale, rotate and opacity: paint-property only, with a direct-update fast path that
    skips repaint and raster.
  - filter: paint-property only.
  - top and left: positioned layout.
  - width, height and margin: full layout.
  - padding: layout plus paint.
  - clip-path and background-color: paint, unless a native paint worklet animates them.
  - background-position and color: paint.
  - will-change and backdrop-filter: compositing reasons.
  - contain: full layout when it changes, but `contain: layout size` turns a box into a relayout boundary.
- **Which thread runs an animation.** A CSS or Web Animation of transform, translate, scale, rotate, opacity,
  filter or backdrop-filter runs on the compositor unless one of the 22 failure bits is set (CONFIRMED,
  `B/core/animation/compositor_animations.h:69-148`, `compositor_animations.cc:78-83`). background-color and
  clip-path also run there through native paint worklets.
  - Once composited, the main thread is not ticked per frame. `Animation::TimeToEffectChange` returns 0 ("tick me
    every frame") only for a non-composited animation in its active phase (CONFIRMED,
    `B/core/animation/animation.cc:3390-3394`).
  - A ScrollTimeline animation is composited only if its source has a user-scrollable paint-property scroll node
    (CONFIRMED, `compositor_animations.cc:1136-1174`, `animation.cc:2561-2566`).
- **The CI lane keeps threaded animation (corrected by the lead, 2026-10-18).** Plain `--deterministic-mode` appends
  `--disable-threaded-animation` (CONFIRMED, `headless/lib/browser/command_line_handler.cc:52`@f842f52), which sets
  `kAcceleratedAnimationsDisabled` on every animation (CONFIRMED, `compositor_animations.cc:603-608`). But our lane does
  NOT pass `--deterministic-mode`: it passes the same switches minus `--disable-threaded-animation`, so compositor
  animations stay on the compositor as on real Chrome (CONFIRMED, `packages/measure-chromium/src/run.mjs:41`).
  - The lane therefore measures the threaded path. A "move it to the compositor" optimization can be read from the
    lane's own counts (no main-thread tick) as well as from its property class (transform: no Layout, Paint or Raster).
  - Threaded scrolling is not disabled, but the lane scrolls with `window.scrollTo`, which is a main-thread scroll.
- **Scroll costs.** A compositor scroll itself costs no main-thread work, but every scroll update requests a
  BeginMainFrame (`BeginMainFrameReason::kScroll`). That frame dispatches `scroll` events and runs the lifecycle,
  which is nearly empty when nothing is dirty (CONFIRMED, `cc/input/input_handler.cc:429,1705-1707`).
  - Scroll listeners never force main-thread scrolling. Only non-passive wheel or touch handler regions block, and
    `background-attachment: fixed` forces repaint (CONFIRMED, `cc/input/main_thread_scrolling_reason.h:25-70`).
  - A JS tween that calls `scrollTo` from rAF is a main-thread scroll every frame. It costs a rAF callback,
    ScrollLayer, PrePaint, Layerize and Commit, plus a repaint each time the scroll moves 512 px × DPR past the
    painted cull rect (section 4).

## 1. Pipeline stages per frame, and what each stage's work is proportional to

### 1.1 Main thread (renderer): `ProxyMain::BeginMainFrame` (`cc/trees/proxy_main.cc:174`)

| # | Stage | Code (CONFIRMED) | Runs when | Work ∝ (status) |
|---|---|---|---|---|
| M0 | Apply compositor deltas (scroll offsets, page scale) | `proxy_main.cc:346` `ApplyCompositorChanges` | every BMF that is not deferring commits | number of scrollers that scrolled (INFERRED) |
| M1 | Animate cc (main side) | `proxy_main.cc:362` `AnimateLayers` | every BMF | cc animations (INFERRED) |
| M2 | HTML "update the rendering" steps | `B/core/page/page_animator.cc:266` (step 9, scroll events), `:292` (step 11, update animations and events), `:335` (step 14, rAF) | BMF | listeners × events + rAF callbacks + **non-composited** animations sampled (`KeyframeEffect::ApplyEffects`, `B/core/animation/keyframe_effect.cc:698-743`, marks the target with `SetNeedsAnimationStyleRecalc` when the sample changed) |
| M3 | Style recalc | `B/core/dom/document.cc:2780` (skips if `!needs_layout_tree_update`), event at `:2815` | the style tree is dirty | elements recalculated = `UpdateLayoutTree.elementCount` (CONFIRMED that the event carries it; ∝ INFERRED) |
| M4 | Layout | `B/core/frame/local_frame_view.cc:3674-3678` (`if (NeedsLayout())`), event `:896` | some object needs layout | objects under the dirty layout roots (`Layout.dirtyObjects/totalObjects`); a root is a relayout boundary or the whole view (`:894-895`) |
| M5 | Compositing inputs + PrePaint | event `PrePaint` `local_frame_view.cc:2586` wraps both; `B/core/paint/pre_paint_tree_walk.cc:110` (deferred transform/opacity updates), `:419-423` (walk only objects flagged for paint-invalidation checks or subtree walk) | **every lifecycle update that reaches pre-paint** | objects on dirty paths + deferred updates; builds/updates the paint property trees (transform, clip, effect, scroll) |
| M6 | Paint | `local_frame_view.cc:3282-3285` (repaint only if the root layer `SelfOrDescendantNeedsRepaint`); event `Paint` `B/core/paint/paint_layer_painter.cc:62` | some PaintLayer needs repaint | display items of the repainted layers; clean layers reuse cached subsequences (`paint_layer_painter.cc:411-415`) |
| M7 | Layerize (PaintArtifactCompositor) | event `Layerize` `local_frame_view.cc:3386`, emitted **before** the fast path `TryFastPathUpdate` (`:3390`; `B/platform/graphics/compositing/paint_artifact_compositor.cc:1407-1450`: kNone, kRasterInducingScroll, kRepaint, kFull) | every paint phase | kNone ≈ 0; kRepaint ∝ pending layers; kFull ∝ paint chunks (layerization + cc property-tree rebuild) |
| M8 | UpdateLayers + commit | `proxy_main.cc:434` (`ScopedCommitTrace`, the devtools `Commit`), `:453` `UpdateLayers`; `cc/trees/layer_tree_host.cc:1118-1126` `FindLayersThatNeedUpdates` → `PaintContent` → `PictureLayer::Update` (event `UpdateLayer`, `cc/layers/picture_layer.cc:130-131`) | every BMF that reaches the commit stage | drawable layers (UpdateLayer per layer); raster invalidation rects are handed to the impl side |

The lifecycle loop can repeat inside one frame. `UpdateLifecyclePhasesInternal` runs `while (true)` and `continue`s
after ResizeObserver, IntersectionObserver, container-query and view-transition steps (CONFIRMED,
`local_frame_view.cc:2536`, continues at 2563, 2601, 2637, 2656, 2681). Style, layout and pre-paint counts per frame
are therefore ≥ 0 and not capped at 1.

An empty main frame is cheap. If UpdateLayers reports no update, `WillCommit` returns null and the frame ends as
`MainFrameAborted / NO_UPDATE` with no impl-side commit (CONFIRMED, `proxy_main.cc:470-505`). The devtools `Commit`
slice has already opened by then (`:434`). INFERRED consequence: `trace.Commit` counts main frames that reached
UpdateLayers, while `trace.cc.Commit` (`ProxyImpl::Commit`) counts real commits.

### 1.2 Compositor (impl) thread and workers

| # | Stage | Code (CONFIRMED) | Work ∝ |
|---|---|---|---|
| C0 | BeginImplFrame | `cc/scheduler/scheduler.cc:594,684` | 1 per BeginFrame |
| C1 | Scheduler action priority | `cc/scheduler/scheduler_state_machine.cc:728-755`: SEND_BEGIN_MAIN_FRAME > POST_COMMIT > ACTIVATE > COMMIT > DRAW > IMPL_SIDE_INVALIDATION > PREPARE_TILES | n/a |
| C2 | Impl animation tick | `cc/trees/layer_tree_host_impl.cc:839-852` (`Animate`), `:5065-5070` (`TickAnimations` with the scroll tree); writes go to `TransformTree::OnTransformAnimated` / `EffectTree::OnOpacityAnimated` (`cc/trees/layer_tree_impl.cc:1252-1268`) | running compositor animations; no main thread, no raster |
| C3 | Scroll-linked tick | `cc/animation/animation_host.cc:772-790`; time = scroll offset mapped to progress, `cc/animation/scroll_timeline.cc:85-130` | ScrollTimeline animations |
| C4 | Commit (impl side) | `cc/trees/proxy_impl.cc:875` `ProxyImpl::Commit`; `cc/trees/tree_synchronizer.cc:77,111` | layers pushed |
| C5 | Raster (workers) | `RasterTask`, `DisplayItemList::Raster` (from `src/trace.mjs` WORKER) | invalidated tiles ∩ interest rect (INFERRED; tile manager not read). Raster invalidation is decided per paint chunk: a chunk is invalidated when its accumulated **chunk-to-layer** transform, effect or clip changes (`B/platform/graphics/paint/raster_invalidator.cc:64-142`, transform case `:75-83`). A transform that is the layer's own state does not change chunk-to-layer, so moving a composited layer rasters nothing |
| C6 | Activate | `layer_tree_host_impl.cc:3803` | pending → active tree |
| C7 | Draw | `proxy_impl.cc:856` | quads; hasDamage |

`--run-all-compositor-stages-before-draw` (from deterministic mode, `command_line_handler.cc:42-43`) makes raster and
activation complete before each draw in the lane.

## 2. Per property change: which stages are invalidated, and the code that decides

### 2.1 The deciding chain (all CONFIRMED)

1. **Generated field diff.** `ComputedStyle::VisualInvalidationDiff` (`B/core/style/computed_style.cc:767-931`)
   starts from `FieldInvalidationDiff`, a bitmask generated from each property's `invalidate:` list
   (`B/core/css/css_properties.json5:340-401`, the schema).
2. **Mapping to the diff.**
   - `kLayout` → full layout (`:986-988`).
   - `kInset` on a non-static box → positioned layout (`:792-798`).
   - `kPaint` → normal paint (`:1104-1106`).
   - `kBackground` → normal paint unless the change is visually equal (`:1117-1120`).
   - `kOpacity` → `opacity_changed` (`:852-854`).
   - The transform group is resolved at `:881-891`:
     - `kTransformOther` (translate, scale, rotate, offset-*) → `transform_changed`;
     - a `HasTransform` flip → `transform_changed`;
     - `kTransformProperty` only (the `transform` property) → `only_transform_property_changed`.
   - `kFilterData` → `filter_changed` (`:849-851`).
   - `kClipPath` → `clip_path_changed` (`:832-834`).
   - `kBackgroundColor` → `background_color_changed` (deferred, `:814-819`).
   - `kColor` → `text_decoration_or_color_changed` (`:840-843`).
   - `kCompositing` → `compositing_reasons_changed` (`:1268-1292`).
   - Any change in stacking context → full layout + paint (`:779-784`).
3. **Layout-object adjustments.** `AdjustStyleDifference` (`B/core/layout/layout_object.cc:2921-2965`):
   - a transform on an SVG child → full layout;
   - color → simple paint only if something uses currentColor or the object is text;
   - a layer added or removed → full layout.

   `AdjustForCompositableAnimationPaint` (`:283-305`) drops the paint for background-color and clip-path when a
   native paint worklet runs them.
4. **`LayoutObject::SetStyle`** (`:3035-3231`) acts on the diff:
   - layout dirty bits (`:3166-3181`);
   - `SetShouldDoFullPaintInvalidation…` for normal paint (`:3196-3209`);
   - simple paint marks the painting layer for repaint (`:3154-3164`);
   - a clip-path paint change → paint-property update (`:3212-3216`);
   - a transform, opacity, z-index, filter, clip, blend, mask or compositing change on a layer-less object →
     `SetNeedsPaintPropertyUpdate` (`:3224-3230`).
5. **`PaintLayer::StyleDidChange`** (`B/core/paint/paint_layer.cc:2422`, `:2469-2497`).
   - `only_transform_property_changed` → `ScheduleDeferredTransformNodeUpdate`.
   - `opacity_changed` → `ScheduleDeferredOpacityNodeUpdate`.
   - Otherwise → `SetNeedsPaintPropertyUpdate`.
   - The deferred path is allowed only for a non-fragmented, non-SVG box that already has a Transform (or Effect)
     node and no pending property update (`B/core/paint/paint_property_tree_builder.cc:5085-5135`). It runs in
     PrePaint (`pre_paint_tree_walk.cc:110` → `local_frame_view.cc:5633-5652`) without walking the tree.
6. **Direct cc update.** If the change is `kChangedOnlySimpleValues` and the node has an active transform animation
   (or a directly composited effect), Blink writes the cc node itself and downgrades the change to
   `kChangedOnlyCompositedValues` (`paint_property_tree_builder.cc:1224-1262`). Then no repaint, no Layerize full
   update and no raster happen.
7. **Paint-property change → repaint?** A node added or removed causes a repaint of its chunks (comment at
   `layout_object.cc:3219-3223`). A change of value alone does not. Raster invalidation then follows the
   chunk-to-layer rule in C5.

### 2.2 Table (Chromium 156; "PP" = paint-property update in PrePaint; "Raster" = raster invalidation)

| Property change | Invalidate groups (`css_properties.json5` line) | Diff result | Stages hit per change (main thread) | Status |
|---|---|---|---|---|
| `transform` value, box already transformed | has-transform, transform-data, transform-property (6730) | `only_transform_property_changed` | Style → PP (deferred direct update) → Layerize kNone → Commit. **No Layout, no Paint.** Raster: 0 when the element is its own cc layer (will-change or animation); when it shares a layer, its chunks re-raster (old ∪ new rect) | CONFIRMED chain; raster split INFERRED from `raster_invalidator.cc:75-83` |
| `translate` / `scale` / `rotate` | has-transform, transform-data, transform-other (6788, 6824, 6807) | `transform_changed` (not only-property) | Style → PP full update for the object (no deferred path) → no Layout, no Paint | CONFIRMED |
| transform none ↔ some | `HasTransform` flip | `transform_changed`; a transform node is added or removed; may change the stacking context → full layout + paint (`:779-784`) | Style, (Layout), PP, Paint, Layerize full | CONFIRMED (the stacking-context branch applies when the stacking state flips) |
| `opacity` in [0,1) | opacity (4806) | `opacity_changed` | Style → PP deferred/direct (effect node) → no Layout, no Paint | CONFIRMED |
| `filter` | filter-data (3594) | `filter_changed` | Style → PP (effect node) → no Layout, no Paint (chunks re-raster if not its own layer) | CONFIRMED / INFERRED raster |
| `backdrop-filter` | compositing (2143) | `compositing_reasons_changed` | Style → PP (+ Layerize full likely) | CONFIRMED diff; Layerize INFERRED |
| `top` / `left` (positioned box) | inset, scroll-anchor (6686, 4212) | positioned layout (`:795-797`) | Style → Layout (simplified, OOF) → PP → Paint (geometry change) → Raster | CONFIRMED diff; Paint INFERRED |
| `width` / `height` / `margin-*` | layout, scroll-anchor (8286, 3981, 4447) | full layout | Style → Layout up to the relayout boundary → PP → Paint → Raster | CONFIRMED diff |
| `padding-*` | layout, paint, scroll-anchor (5208) | full layout + normal paint | same as above | CONFIRMED |
| `clip-path` | clip-path (3112) | `clip_path_changed` → normal paint unless the clip-path native worklet animates it (`layout_object.cc:298-302`); then PP + `SetNeedsCompositingInputsUpdate` (`:3212-3216`) | Style → PP → Paint → Raster (main); with `CompositeClipPathAnimation` (status stable, `runtime_enabled_features.json5:1342-1343`): compositor | CONFIRMED |
| `background-position` / `background-image` | `Background` FillLayer field: background, currentcolor (`computed_style_extra_fields.json5:362-369`) | normal paint if not `VisuallyEqual` (`computed_style.cc:1117-1120`) | Style → PP (paint invalidation) → Paint → Raster of the box | CONFIRMED |
| `background-color` | ax-style, background-color (2245) | `background_color_changed` → paint unless the native worklet animates it (`layout_object.cc:288-296`; `CompositeBGColorAnimation` status stable, `runtime_enabled_features.json5:1333-1335`) | Style → Paint → Raster (main) | CONFIRMED |
| `color` | accent-color, border-visual, color, currentcolor, outline (1404) | `text_decoration_or_color_changed` → simple paint for text or currentColor users (`layout_object.cc:2932-2948`) | Style → Paint (simple: client invalidation without a PrePaint walk) → Raster | CONFIRMED |
| `will-change` | compositing (8301) | `compositing_reasons_changed` → PP; direct reasons from `CompositingReasonsForWillChange` (`B/core/paint/compositing/compositing_reason_finder.cc:76-137`) | Style → PP → Layerize full (a new cc layer) → Commit; one-off, then later transform/opacity changes take the 0-raster path | CONFIRMED diff and reasons; Layerize INFERRED |
| `contain` | layout (3203) | full layout when it changes. Static benefit: `contain: layout size` (or `strict`) on a self-painting box makes it a relayout boundary (`layout_object.cc:1535-1537`; otherwise fixed width/height + overflow clip, `:1550-1559`), so later layouts inside stay inside; `contain: paint` changes compositing reasons (`computed_style.cc:1277-1279`) | Style → Layout (once) | CONFIRMED |
| `z-index` | z-index (8358) | `z_index_changed` → PP + stacking-context repaint (`paint_layer.cc:2491-2497`, `:2518-2524`) | Style → PP → Paint | CONFIRMED |
| `visibility` | paint, visibility (6976) | normal paint; collapse flip → layout | Style → Paint | CONFIRMED |
| `stroke-dashoffset` (SVG) | paint (6120) | normal paint (Blink); full layout only when stroke presence or dash-array presence flips (`computed_style.cc:996-1004`) | Style → Paint → Raster | CONFIRMED (Blink does not lay it out, unlike WebKit; see kickoff/01 row 6) |

A non-composited animation on the main thread runs the same chain once per frame. A `transform` or `opacity`
animation always gets `kActive*Animation` compositing reasons through `HasCurrent*Animation`
(`compositing_reason_finder.cc:563-600`), so it has its own cc layer and takes the direct-update path. INFERRED:
`HasCurrentTransformAnimation` is a style flag set whether or not the animation is composited, so the lane's
main-thread fallback still avoids Layout, Paint and Raster.

## 3. Compositor thread vs main thread for animations

- **Eligible properties.** `kCompositableProperties` = backdrop-filter, filter, opacity, rotate, scale, transform,
  translate, plus background-color and clip-path through a paint image generator (CONFIRMED,
  `compositor_animations.cc:78-83`). Anything else is `kUnsupportedCSSProperty` (`:173`).
- **Failure bits** (CONFIRMED, `compositor_animations.h:69-148`; the code that sets each bit is in
  `compositor_animations.cc` and `animation.cc` at the lines given):

  | Bit | Name | Set when | Code |
  |---|---|---|---|
  | 0 | `kAcceleratedAnimationsDisabled` | reduced motion forced, accelerated compositing off, or threaded animation off (NOT the CI lane, which keeps threaded animation: run.mjs:41) | `compositor_animations.cc:597-608`; `animation.cc:2505` |
  | 1 | `kEffectSuppressedByDevtools` | | |
  | 2 | `kInvalidAnimationOrEffect` | | |
  | 3 | `kEffectHasUnsupportedTimingParameters` | `ConvertTimingForCompositor` fails | `compositor_animations.cc:508` |
  | 4 | `kEffectHasNonReplaceCompositeMode` | | `compositor_animations.cc:393` |
  | 5 | `kTargetHasInvalidCompositingState` | no layout object, fragmented target, no direct compositing reasons, or `will-change: contents` | `compositor_animations.cc:282,624-646` |
  | 6 | `kTargetHasIncompatibleAnimations` | | `compositor_animations.cc:499` |
  | 7 | `kTargetHasCSSOffset` | | |
  | 10 | `kTransformRelatedPropertyCannotBeAcceleratedOnTarget` | e.g. an inline box | `compositor_animations.cc:316-320` |
  | 12 | `kFilterRelatedPropertyMayMovePixels` | blur or drop-shadow in `filter` (backdrop-filter is exempt) | `compositor_animations.cc:405-417` |
  | 13 | `kUnsupportedCSSProperty` | | |
  | 15 | `kMixedKeyframeValueTypes` | | `compositor_animations.cc:446` |
  | 16 | `kTimelineSourceHasInvalidCompositingState` | | `animation.cc:2561-2566` |
  | 17 | `kAnimationHasNoVisibleChange` | | `compositor_animations.cc:289,494` |
  | 18 | `kAffectsImportantProperty` | | |
  | 19 | `kSVGTargetHasIndependentTransformProperty` | | |
  | 20 | `kEffectHasNonReplaceIterationCompositeMode` | | |
  | 21 | `kUnsupportedInheritance` | | `compositor_animations.cc:310` |

  Each decision is traced as an `Animation` instant event with `compositeFailed` (`animation.cc:2653`), which the
  lane already sums into `trace.Animation.compositeFailedBits`.
- **Per-frame consequence.** `DocumentTimeline::ScheduleNextService` (`B/core/animation/document_timeline.cc:111-135`)
  asks each animation for `TimeToEffectChange`, which works like this:
  - A composited animation in its active phase returns the time to its end or next iteration. The main thread
    sleeps (`WakeAfter`) and does not tick it.
  - A main-thread animation returns 0, so it is serviced on the next frame, every frame (CONFIRMED,
    `animation.cc:3376-3400`).

  A CSS animation, transition or Web Animation on an eligible property therefore costs main-thread work only at
  start, at phase changes and at the end.
- **Caveat: composited animations ride along on main frames that run for other reasons** (scroll, rAF).
  `ApplyEffects` re-samples and marks the target for animation style recalc when the value changed
  (`keyframe_effect.cc:739-742`). That is style recalc of the target and PP with
  `kChangedOnlyCompositedValues`, but no layout and no paint. INFERRED: this is the "free-running" cost of a
  composited animation during a scroll.
- **Scroll-driven animations (ScrollTimeline / ViewTimeline).** They are composited if the source's paint
  properties have a `Scroll()` node that is `UserScrollable()` (CONFIRMED, `compositor_animations.cc:1136-1174`).
  - When composited, cc computes the timeline time from the scroll tree offset at each impl tick (CONFIRMED,
    `cc/animation/scroll_timeline.cc:85-130`, `animation_host.cc:772-790`). The animated value is in step with the
    compositor scroll in the same impl frame.
  - Native paint worklets (background-color, clip-path) need a monotonic timeline, so they cannot be
    scroll-driven on the compositor (CONFIRMED, `compositor_animations.cc:335-343`).
- **rAF + JS style writes**, and scroll listeners that write styles, are always main-thread. Each frame pays the
  rAF callback (`page_animator.cc:335`) plus the property class's chain from section 2.2 for every element written.

## 4. Scrolling

- **Threaded scroll.** `InputHandler::ScrollUpdate` (`cc/input/input_handler.cc:339`) moves the scroll node on the
  impl thread, calls `DidScrollContent`, then `SetNeedsCommit()` → `SetNeedsCommit(BeginMainFrameReason::kScroll)`
  (CONFIRMED, `:425-429`, `:1705-1707`). The main thread gets one BMF per scrolled frame, where the following
  happens:
  - `ApplyCompositorChanges` writes the offset (`proxy_main.cc:346`) → `PaintLayerScrollableArea::UpdateScrollOffset`
    (`B/core/paint/paint_layer_scrollable_area.cc:428`).
  - That runs `SetNeedsPaintPropertyUpdate` (scroll translation, `:450`), emits `ScrollLayer` (`:461-462`), enqueues
    the scroll event and runs `InvalidatePaintForScrollOffsetChange` (`:573-589`). The last one repaints only
    `background-attachment: fixed`/local-attachment backgrounds and sticky descendants.
- **Main-thread scroll reasons at this pin** (CONFIRMED, `main_thread_scrolling_reason.h:25-70`):
  - repaint reasons: `kHasBackgroundAttachmentFixedObjects`, `kNotOpaqueForTextAndLCDText`,
    `kPreferNonCompositedScrolling`, `kBackgroundNeedsRepaintOnScroll`;
  - hit-test reasons: `kScrollbarScrolling`, `kMainThreadScrollHitTestRegion`, `kFailedHitTest`;
  - other reasons: `kWheelEventHandlerRegion` and `kTouchEventHandlerRegion` for **non-passive** wheel or touch
    handlers.

  `scroll` listeners are not a reason. They run after the fact at step 9 of the next main frame.
- **Cull-rect repaint during scroll.** Composited scrolling contents are painted into a cull rect expanded by 4000 px
  on Linux and macOS (2000 on Android), scaled by the expansion ratio. The cull rect is re-computed and the layer
  repainted only when the visible rect has moved ≥ 512 px × ratio ("changed enough") (CONFIRMED,
  `B/platform/graphics/paint/cull_rect.cc:48-69,425-430`; defaults `third_party/blink/common/features.cc:627-652`).
  INFERRED: in the lane (10 px/frame) that is a Paint plus raster burst about every ⌈512·r/10⌉ frames, where r is
  the ratio (DPR coefficient 1, so r = 1 is assumed).
- **Cost of a scroll listener** (per scrolled frame, INFERRED from the steps above):
  - EventDispatch + FunctionCall for each listener;
  - plus the section 2.2 chain of whatever it writes;
  - a forced synchronous layout if it reads layout after a write (a second Layout inside the frame).

  With no writes the cost is BMF + PrePaint + Layerize(kNone) + Commit.
- **Cost of a scroll-jacked tween** (`scrollTo` inside rAF), per frame:
  - FireAnimationFrame + FunctionCall + a main-thread scroll (`ScrollLayer`, PP of the scroll translation, which
    can be updated directly through `DirectlyUpdateScrollOffsetTransform`, `paint_property_tree_builder.cc:3897-3914`);
  - scroll event dispatch on the following frame;
  - the cull-rect repaint bursts;
  - the hover hit-test that a programmatic scroll triggers (`trace.HitTest`, README of packages/measure-chromium).

  It also serializes scroll with main-thread latency, because the user's fling cannot run on the impl thread while
  JS owns the offset (INFERRED).

## 5. Trace events in our Chromium lane → stages

Mapping `packages/measure-chromium/src/trace.mjs:20-86` to the emitting code:

| Lane key | Emitted at (CONFIRMED) | Stage | What one count means |
|---|---|---|---|
| `trace.ScheduleStyleRecalculation` | `B/core/dom/document.cc:2563` | M3 (request) | a style invalidation was scheduled |
| `trace.UpdateLayoutTree` (+ `.elementCount`) | `document.cc:2815` (gated `:2780`) | M3 | one style recalc pass; elementCount = elements restyled |
| `trace.InvalidateLayout` | `local_frame_view.cc:1690` | M4 (request) | a layout was scheduled |
| `trace.Layout` (+ dirty/total/partial) | `local_frame_view.cc:896` (gated `:3674`) | M4 | one layout pass |
| `trace.PrePaint` | `local_frame_view.cc:2586` | M5 | one lifecycle update reached pre-paint (≈ main frames × lifecycle repeats); not proportional to work |
| `trace.CullRectUpdate` | `B/core/paint/cull_rect_updater.cc:221` | M6 (start) | cull rects re-checked |
| `trace.Paint` | `paint_layer_painter.cc:62` (`ShouldReport` `:82-110`) | M6 | 1 for the root when any repaint happens + 1 per nested PaintLayer that needs repaint under a non-repainting reporter; 0 when nothing repaints |
| `trace.PaintImage` | `image_painter.cc:246`, `box_painter_base.cc:1109,1264` | M6 | an image drawn during paint |
| `trace.Layerize` | `local_frame_view.cc:3386` | M7 | one paint phase; emitted even on the kNone fast path, so it counts frames, not layerization work |
| `trace.Commit` | `cc/base/devtools_instrumentation.h:50,134-142` via `proxy_main.cc:434` | M8 | a BMF reached UpdateLayers (also when the commit is then aborted for no updates; INFERRED) |
| `trace.UpdateLayer` | `cc/layers/picture_layer.cc:130-131` | M8 | one picture layer updated (∝ drawable layers per commit) |
| `trace.ScrollLayer` | `paint_layer_scrollable_area.cc:461-462` | M0/M2 | a scroll offset changed on main |
| `trace.FireAnimationFrame`, `FunctionCall`, `EventDispatch`, `TimerFire` | inspector events | M2 | script |
| `trace.Animation.begin` / `.instant` / `.compositeFailedBits` | `animation.cc:2653,3727,3741` | M2/C2 | compositing decisions; bit 0 is not forced in the lane (threaded), so the bits read eligibility directly |
| `trace.cc.Commit` | `cc/trees/proxy_impl.cc:875` | C4 | a real commit |
| `trace.cc.SynchronizeTrees` | `cc/trees/tree_synchronizer.cc:77,111` | C4 | layer tree sync |
| `trace.cc.Activate` | `layer_tree_host_impl.cc:3803` | C6 | activation |
| `trace.cc.Draw` | `proxy_impl.cc:856` | C7 | a draw |
| `trace.RasterTask`, `DisplayItemListRaster` | cc tile manager (workers) | C5 | tiles rastered |

Signatures the model predicts for one frame in the lane (INFERRED from sections 1-2; checkable against
`counts.json`):

| Frame kind | UpdateLayoutTree | Layout | PrePaint | Paint | Layerize | Commit | RasterTask |
|---|---|---|---|---|---|---|---|
| Idle (nothing dirty, BMF requested) | 0 | 0 | 1 | 0 | 1 | 1 | 0 |
| Main-thread transform/opacity animation, own layer | ≥1 | 0 | 1 | 0 | 1 | 1 | 0 |
| Same, transform on an element without its own layer | ≥1 | 0 | 1 | ≥1 | 1 | 1 | >0 |
| `top`/`width`/`margin` animation | ≥1 | ≥1 | 1 | ≥1 | 1 | 1 | >0 |
| `background-position` / `color` / dashoffset | ≥1 | 0 | 1 | ≥1 | 1 | 1 | >0 |
| `scrollTo` step, cull rect not changed enough | 0 | 0 | 1 | 0 | 1 | 1 | ≥0 (newly exposed tiles) |
| `scrollTo` step, cull rect changed enough | 0 | 0 | 1 | ≥1 | 1 | 1 | >0 |

## 6. Encoding for Lean (proposal)

A module `Fw.Engine.Chromium` next to `Fw.Spec.Cost` (which already has `Work`, `CompWork`, `Work.le`, `mainUs_mono`):

- `inductive Stage | style | layout | prePaint | paint | layerize | commit | raster | draw`. A change maps to a
  `Finset Stage`, and the stages are ordered: layout ⇒ prePaint, and paint ⇒ prePaint.
- `structure Diff` with `layout : Fin 3` (none < positioned < full), `paint : Fin 3` (none < simple < normal) and
  Bool flags; `Diff.merge` is the pointwise max/or. Prove that it is a join-semilattice and that
  `stages : Diff → Finset Stage` is monotone. The source is `style_difference.h:20-44,112-116`.
- `PropChange → Diff` as a table (section 2.2). `PaintPropertyChangeType` is `Fin 5`. The direct-update rule:
  `simple ∧ ownLayer → compositedOnly`, and `compositedOnly → ¬paint ∧ raster = 0`.
- A frame `F = (script, styled elements, layout objects, prePaint objects, repainted layers, layerize kind, layers
  updated, raster tiles)`. An optimization `o` is accepted when:
  1. **Same pixels.** The property-value trajectory over virtual time is equal: `∀ t, value_opt t = value_orig t`.
     Rendering is a function of property-tree values plus display lists, so equal values and equal display lists
     give equal frames. Model assumption; caveats below.
  2. **No more work.** `stages(o) ⊆ stages(orig)` per frame, and the counts are componentwise `≤`. Then
     `mainUs_mono` gives lower cost for every non-negative unit-cost vector.
- **Caveats the proof must state as hypotheses** (INFERRED, not read in source):
  - compositing can change text anti-aliasing (LCD text is disabled on non-opaque composited layers; see
    `kNotOpaqueForTextAndLCDText`);
  - raster scale for a composited scale animation can differ from main-thread raster;
  - a compositor animation starts one commit later than a main-thread one (start-time sync).

  Equal pixels therefore need either "no text inside the moved layer, no scale animation" or a pixel check in CI.

## What this changes in the plan

- **PLAN §4.2 (Step 1: deterministic work counts).** Add the section 5 mapping table and its consequences:
  - PrePaint, Layerize and Commit count lifecycle frames, not work, and Paint is 0 on frames with no repaint.
    Screen on Style/Layout/Paint/Raster plus `elementCount`/`dirtyObjects`.
  - State that the lane keeps threaded animation (run.mjs:41), so "compositor-only" is checked both by property class
    (no Layout, Paint or Raster per tick) and by the missing main-thread tick in the lane's own counts.
- **PLAN §5.1 (what is proved).** Add `Fw.Engine.Chromium`. It holds the Diff semilattice, the property → stages
  table with its source lines, and the theorem "optimized change ⊆ original stages ∧ counts ≤". The theorem has
  equal value trajectories and the three caveats as hypotheses. Golden vectors come from the section 5 signature
  table and are checked against CI counts.
- **PLAN §6.5 (runtime rules inside parts).** Add four rules, each with its source line from section 2:
  - animate only transform, translate, scale, rotate and opacity (no blur);
  - give moving elements their own layer (`will-change: transform`) so their chunks never re-raster;
  - prefer the `transform` property over the individual translate, scale and rotate properties when JS writes
    every frame, because only `transform` has the deferred direct-update path;
  - use ScrollTimeline on the root scroller instead of scroll listeners.

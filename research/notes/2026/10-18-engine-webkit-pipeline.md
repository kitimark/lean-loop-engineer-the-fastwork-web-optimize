---
id: 2026-10-18-engine-webkit-pipeline
kind: note
title: "WebKit (iOS Safari) rendering pipeline for scroll- and time-driven animation, as a model Lean can encode"
status: review
created: 2026-10-18
topics: [webkit, ios, rendering, compositing, scroll-driven-animations, scrolling, lean, cost-model, measure-webkit, measure-wktr]
---

# WebKit (iOS Safari) rendering pipeline: a model for Lean

**Source pin.** WebKit `862f17dcae0aace47ea0ec16e209d960abfd553c` (tag WebKit-7625.1.29.10.29, the iOS 27.0
build). It was read from the sparse clone `.cache/upstream/WebKit@862f17d`.

**Citation format.** Citations are `path:line@862f17d`. The path prefixes are:
- `WC/` = `Source/WebCore/`
- `WK/` = `Source/WebKit/`
- `WTF/` = `Source/WTF/`

**Statuses.**
- CONFIRMED: the cited source line says it.
- INFERRED: a reading across several sites, or behaviour of closed UIKit/Safari code.
- MEASURED: a cited repo result from a CI run.

## TL;DR (the model in seven lines)

1. One web-process rendering update runs these stages in order: rAF and other callbacks, then style, layout and the
   compositing update, then the layer-flush and transaction build, then backing-store paint, then the commit to the
   UI process. At most one commit is in flight at a time. (CONFIRMED, §1)
2. Each stage's cost scales with a different quantity:
   - style: restyled elements
   - layout: dirty renderers
   - compositing update: layers whose update root needs traversal
   - transaction build: **all layers**, every time
   - paint: **dirty area** of backing stores
   - commit: sent even when nothing changed (CONFIRMED, §1)
3. What a CSS change costs is `StyleDifference`, adjusted by whether the element already has a *composited* layer:
   - transform or opacity on a composited layer: `RecompositeLayer`, with no layout and no paint
   - transform on a layer that is not composited: an overflow layout plus a repaint
   - clip-path, background-position or color: Repaint
   - size or margin: Layout (CONFIRMED, §2)
4. Accelerated animations run in the UI process (Core Animation) with **zero web-process work per frame**:
   - properties: opacity, filter, backdrop-filter, transform, translate, scale, rotate; offset-* on the threaded path only
   - scroll-driven animations take the threaded path (preference stable, default on)
   - time-based animations take the legacy CAAnimation path (threaded preference default off)
   - clip-path, background-position, colors, insets and sizes never run in the UI process (CONFIRMED, §3)
5. iOS scrolling is always UIKit in the UI process, and there are no "synchronous scrolling reasons" on iOS. Still,
   **every scroll position that reaches the web process schedules a full rendering update plus a commit**, with or
   without scroll listeners. (CONFIRMED, §4)
6. A JS `scrollTo` inside rAF becomes a `RequestedScrollData` carried by the next commit. The UI process then calls
   `setContentOffset` on the UIScrollView while the user is panning: one round trip late, and it fights UIKit.
   (CONFIRMED path; INFERRED feel)
7. What the counters measure:
   - measure-wktr `internals` counters count the stages directly (renderingUpdate, style recalc, layout,
     compositing update, layer flush).
   - measure-webkit Timeline records map RecalculateStyles to style, Layout to layout, Paint to backing-store
     paint, and Composite to one `RemoteLayerTreeDrawingArea::updateRendering` (§5).

---

## 1. Stages of one rendering update, and what each is proportional to

### 1.1 Driver: `RemoteLayerTreeDrawingArea::updateRendering` (web process)

`WK/WebProcess/WebPage/RemoteLayerTree/RemoteLayerTreeDrawingArea.mm:319-443@862f17d` (CONFIRMED). In order:

| # | Step | Line | Notes |
|---|---|---|---|
| D0 | Bail out if `m_waitingForBackingStoreSwap` | 326-329 | Back-pressure: at most one commit in flight. The UI process's `displayDidRefresh` clears the wait and runs a deferred update (451-477). |
| D1 | `webPage->updateRendering()` → `Page::updateRendering` | 345 | Detailed in §1.2 |
| D2 | `finalizeRenderingUpdate` | 355 | LayerFlush and ScrollingTreeUpdate (§1.3) |
| D3 | `willStartRenderingUpdateDisplay` | 357 | Inspector **Composite** record starts (§5) |
| D4 | `flushCompositingStateForThisLayerOnly` per root, then `buildTransaction` | ~365-379 | Transaction build, plus backing-store paint (§1.4) |
| D5 | `m_waitingForBackingStoreSwap = true` | 383 | |
| D6 | Scrolling transaction `RemoteScrollingCoordinator::buildTransaction` | 388 | Carries scrolling-state changes, including requested scrolls |
| D7 | Commit dispatched on `m_commitQueue`, then `didCompleteRenderingUpdateDisplayFlush` | ~395-443 | A source comment reads "FIXME: Minimize these transactions if nothing changed". So a commit is sent **every** update, even an empty one. |

`scheduleRenderingUpdate` is at 562. All entry points (`Document::scheduleRenderingUpdate`, timelines, rAF) end
there. (CONFIRMED)

### 1.2 `Page::updateRendering`

`WC/page/Page.cpp:2231-2413@862f17d` (CONFIRMED). If the call is re-entrant, it only runs
`layoutIfNeeded(UpdateCompositingLayers)` and returns (2242-2245). Otherwise the step order is:

1. `layoutIfNeeded` (2254)
2. Resize (2290)
3. **Scroll**, i.e. `runScrollSteps`, which fires scroll events (2294)
4. MediaQueryEvaluation (2298)
5. AdjustVisibility
6. **Animations**: `updateAnimationsAndSendEvents` (2307). Main-thread animations resolve here, and stale
   ScrollTimelines are updated here.
7. Fullscreen
8. VideoFrameCallbacks
9. **AnimationFrameCallbacks** (rAF) (2329)
10. CaretAnimation
11. ResizeObservations (2340)
12. FocusFixup
13. UpdateContentRelevancy
14. ViewTransitions
15. IntersectionObservations (2366)
16. Images
17. SnapshottedScrollOffsets
18. `++m_renderingUpdateCount` (2397)
19. **`layoutIfNeeded(LayoutOptions::UpdateCompositingLayers)`**: style resolve, then layout, then the compositing
    update
20. `doAfterUpdateRendering` (2413). It covers cursor, paint timing, event timing, and
    `runPostRenderingUpdateAnimationTasks` (threaded animations), and finishes with **EventRegionUpdate**.

Style and layout can also run earlier, forced by JS reads such as `getBoundingClientRect` inside rAF or a scroll
handler. Those runs are synchronous and are counted by the same counters. (INFERRED from the `layoutIfNeeded` call
sites; the forced-layout API sites were not re-read for this note.)

### 1.3 `Page::finalizeRenderingUpdateForRootFrame`

`WC/page/Page.cpp:2542-2565@862f17d` (CONFIRMED):
- **LayerFlush**: `view->flushCompositingStateIncludingSubframes()`, which reaches
  `RenderLayerCompositor::flushPendingLayerChanges` (`WC/rendering/RenderLayerCompositor.cpp:814-860`).
- **ScrollingTreeUpdate**: `scrollingCoordinator->commitTreeStateIfNeeded()`.

### 1.4 Transaction build and paint

- **Transaction build is O(#layers).** `RemoteLayerTreeContext::buildTransaction`
  (`WK/WebProcess/WebPage/RemoteLayerTree/RemoteLayerTreeContext.mm:192-209`) calls `recursiveBuildTransaction`
  (`…/PlatformCALayerRemote.mm:211-260`). That walks every layer and encodes the properties of changed layers.
  It then calls `prepareBackingStoresForDisplay` and `paintReachableBackingStoreContents`. (CONFIRMED)
- **Paint is O(dirty area).**
  - `RemoteLayerBackingStoreCollection` loops only over `m_backingStoresNeedingDisplay`
    (`WK/Shared/RemoteLayerTree/RemoteLayerBackingStoreCollection.mm:69-96`).
  - `RemoteLayerBackingStore::paintContents` returns early when the dirty region is empty, and otherwise paints the
    `m_dirtyRegion` rects (`…/RemoteLayerBackingStore.mm:390-406`).
  - `setNeedsDisplay` unites rects into the dirty region (237, 242).

  (CONFIRMED)

### 1.5 Stage table

| Stage | Cost proportional to | Counter / record (§5) | Status |
|---|---|---|---|
| S0 callbacks: scroll events, rAF, observers | JS time | FireAnimationFrame, EventDispatch, ObserverCallback, TimerFire | CONFIRMED (order); cost INFERRED |
| S1 style | elements in the `Style::Update` (`lastStyleUpdateSize`) | `styleRecalcCount`, RecalculateStyles | CONFIRMED `WC/dom/Document.cpp:2897-2936` |
| S2 layout | renderers marked for layout (full, or simplified for Overflow) | `layoutUpdateCount`, Layout | CONFIRMED `WC/page/LocalFrameViewLayoutContext.cpp:205-383` |
| S3 compositing update | layers below the update root that need traversal; skipped when nothing is dirty | `compositingUpdateCount` | CONFIRMED `RenderLayerCompositor.cpp:1060-1106` |
| S4 layer flush and transaction build | **all** layers (walk), plus changed-layer properties (encode) | `layerFlushCount` | CONFIRMED |
| S5 paint | dirty area of backing stores | Paint | CONFIRMED |
| S6 commit (IPC), scrolling-tree commit | transaction size; a commit is always sent | Composite (whole D3-D7 span) | CONFIRMED |
| S7 event-region update (iOS touch regions) | layers whose regions were invalidated | — | CONFIRMED `WC/rendering/RenderLayer.cpp:6292-6295` |
| UI: CA commit, render server | layer tree diff | not visible to either harness | INFERRED (closed source) |

---

## 2. Which stages each CSS property change invalidates

### 2.1 Mechanism

**Raw style difference.** `Style::difference` returns a `DifferenceResult` (`WC/style/StyleDifference.h:28-55`,
CONFIRMED). The levels, in order:

```
Equal < RecompositeLayer < Repaint < RepaintIfText < RepaintLayer
      < LayoutOutOfFlowMovementOnly < Overflow < OverflowAndOutOfFlowMovement < Layout < NewStyle
```

It also returns a set of *context-sensitive* properties: Transform, Opacity, Filter, ClipRect, ClipPath, WillChange.

**Adjusted difference.** `RenderElement::adjustStyleDifference` (`WC/rendering/RenderElement.cpp:297-359`,
CONFIRMED) converts the context set using the element's layer state. The table uses three states:
- **noLayer**: the element has no RenderLayer
- **layer**: a RenderLayer that is not composited
- **comp**: a composited layer

**Applying the difference.** `RenderElement::setStyle` (592-643) works out the adjusted difference and then calls
`setNeedsLayoutForStyleDifference` (1355-1366):
- Overflow leads to `setNeedsLayoutForOverflowChange`, a simplified layout with a full repaint of the layer
  (1368-1385).
- Repaint-level differences call `repaint()`.

**Compositor side.** `RenderLayerCompositor::layerStyleChanged` (~2284-2318) handles RecompositeLayer:
- with a geometry change, it calls `setNeedsCompositingGeometryUpdate`;
- an opacity change to or from 0 calls `setNeedsCompositingConfigurationUpdate`.

(CONFIRMED)

**iOS extra.** A RecompositeLayer or a layout-level difference calls `invalidateRenderingDependentRegions`, which
recomputes touch and event regions (`WC/rendering/RenderLayer.cpp:6292-6295`, `ENABLE(IOS_TOUCH_EVENTS)`).
(CONFIRMED)

### 2.2 Property × layer state → stages

Each change also costs style (S1), the transaction walk (S4) and a commit (S6).

| Property change | Raw diff (StyleDifference.cpp) | noLayer | layer | comp |
|---|---|---|---|---|
| `transform`, `translate`, `scale`, `rotate`, `offset-*` value | ctx Transform (199-205, 246-252) | Layout + paint | **Overflow**: simplified layout + layer repaint | **RecompositeLayer**: S3 geometry only, no paint |
| transform appears or disappears (`hasTransform` toggles) | Layout (200-201) | Layout | Layout | Layout |
| `opacity` value | ctx Opacity (571-578) | — (an element with opacity < 1 has a layer) | **RepaintLayer** | **RecompositeLayer** |
| opacity crosses 1 (`isOpaque` toggles) | Layout (208-214) | Layout | Layout | Layout |
| `filter` value | ctx Filter (571-578) | — | RepaintLayer | RecompositeLayer, unless `shouldPaintWithFilters` (then RepaintLayer) |
| filter appears or disappears | Layout (217) | Layout | Layout | Layout |
| `clip-path` | ctx ClipPath (779-780) | Repaint | Repaint | RecompositeLayer only if `willCompositeClipPath`: composited, no mask, shape layer (`RenderLayer.cpp:779-791`); else Repaint |
| `clip` | ctx ClipRect (617-618) | Repaint/Layout | — | — |
| `will-change` | ctx WillChange (260-262) | RecompositeLayer if `canTriggerCompositing` | same | same |
| `background-position`, `background-*` | Repaint via `isEquivalentForPainting` (673, 856-858) | Repaint | Repaint | Repaint (the backing store is re-painted) |
| `color` | RepaintIfText (890-893); Repaint when currentColor is used (646, 700-707) | Repaint | Repaint | Repaint |
| `mask` | RepaintLayer | RepaintLayer | RepaintLayer | RepaintLayer |
| `top`/`left`/`inset` on positioned elements | Layout, or LayoutOutOfFlowMovementOnly for absolute (436-445, 557-564) | Layout (cheap movement-only layout for absolute) | same | same |
| `width`/`height`, `margin` | Layout (404-407, 423) | Layout | Layout | Layout |
| `requiresLayer` changes | Layout (`RenderElement.cpp`) | Layout | Layout | Layout |

The raw-diff column and the adjustment rules are CONFIRMED (`WC/style/StyleDifference.cpp@862f17d`, and
`RenderElement.cpp:297-359`). The cell for `clip` is INFERRED, because the ClipRect adjustment branch was not re-read
in detail.

**When does an element have a composited layer?**

`requiresCompositingLayer` (`RenderLayerCompositor.cpp:3289-3317`) is the OR of these reasons: transform, animation,
position, canvas, filters, will-change, backface, view transition, video, model, frame, plugin, overflow scrolling,
anchor positioning. (CONFIRMED) The individual rules:

- **Transform**: `requiresCompositingForTransform` (3878-3907) needs a **3D** transform op under the Normal policy,
  and a transform that is not 2D-representable under Conservative.
  **A static 2D `transform` does not composite.** (CONFIRMED)
- **Animation**: `requiresCompositingForAnimation` (3842-3870) is true for a running accelerated animation. It is
  also true for an effect stack that affects opacity (needs AnimatedOpacityTrigger), filter, backdrop-filter,
  translate, scale, rotate, transform or offset-*. (CONFIRMED)
- **Filters**: `requiresCompositingForFilters` (3981-3995) is always true for backdrop-filter. Otherwise it needs
  FilterTrigger. The WebKit2 client's triggers are ThreeDTransform, Video, Plugin, Canvas, ScrollableNonMainFrame,
  AnimatedOpacity (iOS) and Animation (`WK/WebProcess/WebCoreSupport/WebChromeClient.h:292-306`). That list has
  **no FilterTrigger**, so a static `filter` is painted, not composited. (CONFIRMED)
- **will-change**: `requiresCompositingForWillChange` (3997-4018) returns **false under the Conservative policy on
  non-Mac**. Conservative is chosen under memory pressure or a memory warning (`updateCompositingPolicy`, 691-719).
  The will-change properties that composite are opacity, filter and backdrop-filter on any box, and transform,
  translate, scale, rotate and offset-path on boxes only
  (`WC/style/values/will-change/StyleWillChange.cpp:83-125`). (CONFIRMED)

**Consequence (INFERRED from the rows above).** On iOS, `will-change: transform` is a hint that the system can
drop. A JS-driven 2D transform on an element that has no other compositing reason costs Overflow-layout plus a layer
repaint on every frame. A 3D transform (`translate3d`, `translateZ(0)`) composites under the Normal policy, and the
same JS-driven change then costs only RecompositeLayer. An accelerated CSS animation or a scroll-driven animation
composites the element through the animation reason, independent of will-change.

---

## 3. Accelerated (UI-process / Core Animation) vs main-thread animations

### 3.1 Eligible properties

`WC/css/CSSProperties.json`, key "animation-wrapper-acceleration", read by
`WC/css/scripts/process-css-properties.py:3823, 4093-4096` (CONFIRMED):
- **always**: opacity, filter, backdrop-filter, transform, translate, scale, rotate
- **threaded-only**: offset-path, offset-distance, offset-position, offset-anchor, offset-rotate
- **everything else, never accelerated**: clip-path, background-position, colors, width/height, inset, margin,
  custom properties, and so on

`KeyframeEffect::computeAcceleratedPropertiesState` (`WC/animation/KeyframeEffect.cpp:1737-1769`) classifies an
effect as None, Some or All. (CONFIRMED)

### 3.2 Two paths, chosen by preference

- `ENABLE_THREADED_ANIMATIONS` is 1 on Cocoa (`WTF/wtf/PlatformEnableCocoa.h:904-905`). (CONFIRMED)
- `canHaveAcceleratedRepresentation` (`KeyframeEffect.cpp:3253-3264`) allows the threaded representation in two
  cases (CONFIRMED):
  - a progress-based (scroll or view) timeline, when `threadedScrollDrivenAnimationsEnabled`;
  - a time-based timeline, when `threadedTimeBasedAnimationsEnabled`.
- `WTF/Scripts/Preferences/UnifiedWebPreferences.yaml` (CONFIRMED):
  - `ThreadedScrollDrivenAnimationsEnabled` has status **stable**, WebKit default **true** (8518-8531);
  - `ThreadedTimeBasedAnimationsEnabled` has status **preview**, default **false** (8557-8570).
- So on iOS 27 Safari, **scroll-driven animations use the threaded path** and **time-based CSS animations and
  transitions use the legacy `GraphicsLayerCA` CAAnimation path**. INFERRED: this assumes Safari ships the WebKit
  defaults, which is open item O2.

### 3.3 Disqualifiers

**`KeyframeEffect::canBeAccelerated`** (`KeyframeEffect.cpp:1970-2033`, CONFIRMED).

Disqualifiers on both paths:
- no timeline, or an animation in skipped content
- accelerated-properties state is None
- an accelerated property overridden by the cascade, for example `!important`
- a reference (`url()`) filter
- anchor-dependent geometry
- a size-dependent transform (percentages) while the size is also animated
- a discrete transform interval
- unresolved keyframe offsets
- a site quirk

Disqualifiers on the threaded path:
- the animation is pending
- `timeline->canBeAccelerated()` is false. For a ScrollTimeline, the source scrollable area must have a
  `scrollingNodeID` (`WC/animation/ScrollTimeline.cpp:417-427`), i.e. it must be an async-scrollable scroller or the
  root.

Disqualifiers on the legacy path:
- a progress-based timeline
- `steps()` easing
- `linear()` with points
- `composite` other than replace
- a per-keyframe composite on an accelerated property

**`GraphicsLayerCA::addAnimation`** (legacy only, `WC/platform/graphics/ca/GraphicsLayerCA.cpp:1169-1215`,
CONFIRMED) adds these:
- `playbackRate != 1`
- a direction that is not forwards
- zero duration
- fewer than 2 keyframes
- steps easing
- a cubic easing with y out of [0,1] over more than one interval
- filter animations when unsupported

### 3.4 What "accelerated" removes from the main thread

- `ticksContinuouslyWhileActive` (`KeyframeEffect.cpp:2724-2744`) is false for a completely accelerated running
  effect (threaded: unless it has disallowed properties). Then `DocumentTimeline` schedules no per-frame animation
  resolution (`WC/animation/DocumentTimeline.cpp:156-168`). Result: **no style, layout, paint or commit per frame**.
  (CONFIRMED)
- **Threaded scroll-driven, in the UI process.**
  - `RemoteScrollingTreeIOS::scrollingTreeNodeDidScroll`
    (`WK/UIProcess/RemoteLayerTree/ios/RemoteScrollingTreeIOS.cpp:56-64`) calls `updateProgressBasedTimelinesForNode`
    and then `progressBasedTimelinesWereUpdatedForNode`, which leads to `updateAnimationStacksDependentOnScrollingNode`
    (`…/RemoteScrollingCoordinatorProxyIOS.mm:789-792`).
  - `RemoteAnimationStack` writes values through `CAPresentationModifier`
    (`WK/UIProcess/RemoteLayerTree/RemoteAnimationStack.mm:117-197`).
  - Monotonic (time) timelines on this path are driven by display-refresh callbacks
    (`RemoteScrollingCoordinatorProxyIOS.mm:782-811`).

  (CONFIRMED)
- **Main-thread scroll-driven (fallback).**
  - `AnimationTimelinesController::hasProgressBasedScrollDrivenAnimation` (`…/AnimationTimelinesController.cpp:267-278`)
    is true when some progress-based animation is not completely accelerated.
  - That flag is sent as `hasMainThreadScrollDrivenAnimations` (`WK/WebProcess/WebPage/Cocoa/WebPageCocoa.mm:2357`).
    `WKWebViewIOS.mm:1197, 3259` use it to keep sending visible-rect updates during interactive obscured-inset
    changes.
  - Timelines go stale and are updated inside the rendering update (`ScrollTimeline::updateCurrentTimeIfStale`,
    `ScrollTimeline.cpp:300-322`; `updateStaleScrollTimelines`, `AnimationTimelinesController.cpp:259-265`).
  - `animationTimingDidChange` schedules `RenderingUpdateStep::Animations` (`ScrollTimeline.cpp:399-409`).
  - Result: each delivered scroll position costs S1 to S6, at the level from the §2 table.

  (CONFIRMED)

**Mixed effects.** If any animated property in the effect is not accelerated, the state is Some, the effect ticks
on the main thread, and the threaded representation does not cover it. Example: `transform` together with
`clip-path` in one `@keyframes`. INFERRED: from `computeAcceleratedPropertiesState` plus `ticksContinuouslyWhileActive`.
How a Some-state effect is split between paths was not traced line by line; this is open item O3.

---

## 4. iOS scrolling: UIScrollView, ScrollingTree, RemoteScrollingCoordinator

### 4.1 No synchronous scrolling on iOS

- `ENABLE_SCROLLING_THREAD` is **macOS-only** (`WTF/wtf/PlatformEnableCocoa.h:837-838`).
- `setSynchronousScrollingReasons` only has an effect under `ENABLE(SCROLLING_THREAD)`
  (`WC/page/scrolling/AsyncScrollingCoordinator.cpp:1250-1268`).
- The reasons enum (`WC/page/scrolling/ScrollingCoordinatorTypes.h:37-46`) has no "has scroll listener" entry.
  Slow-repaint objects come from fixed backgrounds (`RenderElement.cpp:1043-1055`).

So on iOS the main frame and overflow scrollers are **always** scrolled by UIKit in the UI process. Scroll
listeners never make scrolling itself synchronous. (CONFIRMED)

### 4.2 But every delivered scroll position costs a web-process rendering update

1. `-[WKWebView scrollViewDidScroll:]` (`WK/UIProcess/API/ios/WKWebViewIOS.mm:2384-2399`) calls
   `_scheduleVisibleContentRectUpdateAfterScrollInView` (3045-3070). Updates are coalesced: at most one pending,
   flushed from a CA pre-commit handler.
2. `_updateVisibleContentRects` (3219ff) sends the update to the web process.
3. `WebPage::updateVisibleContentRects` (`WK/WebProcess/WebPage/ios/WebPageIOS.mm:3573`; scroll application
   3749-3790) calls `AsyncScrollingCoordinator::applyScrollUpdate` (700). That calls `reconcileScrollingState` (865),
   which calls `frameView.notifyScrollPositionChanged`.
4. `LocalFrameView::scrollPositionChanged` (`WC/page/LocalFrameView.cpp:3778-3800`) calls `scheduleScrollEvent`
   (6537-6541). That calls `EventHandler::scheduleScrollEvent` (`WC/page/EventHandler.cpp:5367-5375`), then
   `Document::addPendingScrollEventTarget`, then `scheduleRenderingUpdate(RenderingUpdateStep::Scroll)`
   (`WC/dom/Document.cpp:5913-5937`).
5. Viewport-constrained objects (fixed or sticky) also get a scroll-time compositing update
   (`LocalFrameView::updateCompositingLayersAfterScrolling`, `LocalFrameView.cpp:3944-3955`). Overlap may then need a
   compositing-requirements traversal (`RenderLayerCompositor.cpp:1081-1093`).

So **every delivered scroll position triggers one rendering update (S0-S6) whether or not a listener exists**.
(CONFIRMED) A page with no work only pays the minimum: the S4 walk over all layers plus an empty commit.

The extra cost of a scroll listener is S0 (the handler's JS) plus whatever the handler dirties. A handler that
writes style moves the update up to the §2 level of what it writes. A handler that reads layout forces S1 and S2
synchronously. (INFERRED from the path above)

Delivery rate: at most one update in flight (D0) and coalesced visible-rect updates. INFERRED: so at most one per
display frame while the commit keeps up, and fewer when it does not. When web-process work is late, the scrolled
content in the UI process is still smooth (UIKit). Only main-thread-driven visuals lag behind the scroll position.

### 4.3 JS `scrollTo` inside rAF (scroll-jacking)

1. Web process: `AsyncScrollingCoordinator::requestScrollToPosition` (`AsyncScrollingCoordinator.cpp:381-440`)
   applies the position on the main thread immediately, so layout and `scrollY` see it in the same frame. It also
   writes `RequestedScrollData` into the scrolling state tree, which ships with the next commit (D6). (CONFIRMED)
2. UI process: `RemoteScrollingCoordinatorProxy::adjustMainFrameDelegatedScrollPosition`
   (`WK/UIProcess/RemoteLayerTree/RemoteScrollingCoordinatorProxy.cpp:171-191`) calls `requestScroll`
   (`WK/UIProcess/ios/PageClientImplIOS.mm:136-138`), then `-[WKWebView _scrollToContentScrollPosition:…]`
   (`WKWebViewIOS.mm:1515-1555`), which calls `setContentOffset:`. The interrupt mode is
   `InterruptScrollAnimation::No` for plain position updates and `Yes` for `CancelAnimatedScroll`. (CONFIRMED)
3. Cost per frame: one full rendering update for the rAF and one commit, then a UIKit content-offset set. That set
   in turn produces `scrollViewDidScroll`, a visible-rect update, and the next web-process rendering update (§4.2).
   INFERRED: the loop runs at least one round trip behind the finger or momentum position.
4. INFERRED (closed source, UIKit): a `setContentOffset:` during an active pan or deceleration competes with the
   UIScrollView's own offset, which shows up as jitter or as momentum being cancelled. This cannot be confirmed from
   WebKit source. It can only be MEASURED on device, which is open item O1.

### 4.4 Scroll-driven CSS vs JS scroll handler (the comparison Lean should state)

| Variant | Per-frame web-process work during scroll | Status |
|---|---|---|
| Threaded scroll-driven animation of transform, opacity or filter, async-scrollable source | the baseline update from §4.2 only; the animated values come from the UI process | CONFIRMED (§3.4, §4.2) |
| Main-thread scroll-driven animation of a non-accelerated property (e.g. clip-path) | baseline + S1 + the §2 level for that property | CONFIRMED |
| JS scroll or rAF handler writing transform on a composited layer | baseline + S0 + S1 + RecompositeLayer | CONFIRMED (§2), INFERRED (sum) |
| JS handler writing a 2D transform, not composited | baseline + S0 + S1 + Overflow layout + layer repaint | CONFIRMED (§2) |
| JS rAF `scrollTo` | the above + `RequestedScrollData` + UIKit `setContentOffset` + one extra round trip | CONFIRMED path, INFERRED cost |

---

## 5. How the measured counts map to stages

### 5.1 measure-wktr (`internals` counters, WebKitTestRunner)

Getters: `WC/testing/Internals.cpp:4412-4545@862f17d`. (CONFIRMED)

| Counter | Increment site | Stage |
|---|---|---|
| `renderingUpdateCount` | `Page.cpp:2397` (once per `Page::updateRendering`, while tracking) | one D1 = one rendering update |
| `styleRecalcCount` | `Document.cpp:2936` (end of a `resolveStyle` that ran) | S1 runs, forced ones included |
| `lastStyleUpdateSize` | `Document.cpp:2914` (`Style::Update` size, 2897-2912) | S1 size (elements) |
| `layoutUpdateCount` | `LocalFrameViewLayoutContext.cpp:383` (`didLayout`) | S2 runs, forced ones included |
| `compositingUpdateCount` | `RenderLayerCompositor.cpp:1106` (only when traversal is needed; bail-outs 1060-1103) | S3 non-trivial runs |
| `layerFlushCount` | `RenderLayerCompositor.cpp:859` (`flushPendingLayerChanges`) | S4 |

MEASURED, from `packages/measure-wktr/README.md:92-112`:
- `renderingUpdates` and `layerFlushes` are deterministic at 2 per step. That is the harness's own cadence, and
  it matches "one update per scheduled frame, one flush per update" (CONFIRMED by the sites above).
- Over a pass, styleRecalcs fall between 619 and 694 and layoutUpdates between 527 and 619 (CI runs 39036983052 and
  39042087508). These counts are quarantined as noisy.

INFERRED: the noise fits the source. These two counters also count *forced* style and layout (JS reads, timers),
which are not tied to the update cadence.

What is missing: there is no internals counter for paint area or commit size. Paint is visible only through the
Timeline (§5.2), or through `internals.repaintRectsAsText`-style APIs if we add them; that is open item O4.

### 5.2 measure-webkit (Web Inspector Timeline on the iOS Simulator)

The COUNT_TYPES in `packages/measure-webkit/reduce.mjs:17-21` and `lean/Fw/Measure/WebKit.lean` (`countTypes`) map
to stages as follows:

| Timeline record | Emitted at | Stage | Status |
|---|---|---|---|
| RecalculateStyles | `Document.cpp:2865/2940` | S1 | CONFIRMED |
| Layout | `LocalFrameViewLayoutContext.cpp:223/335` (in `performLayout`, 205) | S2 | CONFIRMED |
| Paint | `RenderLayerBacking::paintIntoLayer` (`RenderLayerBacking.cpp:4141`, will/did 4164/4198), `LocalFrameView.cpp:5760/5812` | S5, one per painted layer (dirty rect) | CONFIRMED |
| Composite | `Page::willStartRenderingUpdateDisplay` / `didCompleteRenderingUpdateDisplay` (`Page.cpp:2587-2609`); the source comment says that on Apple platforms this wraps the CA commit, mostly painting | D3-D7: **one per `RemoteLayerTreeDrawingArea::updateRendering`** | CONFIRMED |
| RenderingFrame | absent on iOS 27.0 (MEASURED, `packages/measure-webkit/README.md`) | Composite stands in for it, now justified by the row above | CONFIRMED + MEASURED |
| FireAnimationFrame | rAF callback | S0 | CONFIRMED (record type); site not re-cited |
| EventDispatch, TimerFire, ObserverCallback, FunctionCall | JS entry points | S0 | INFERRED |
| ScheduleStyleRecalculation, InvalidateLayout | invalidation (S1/S2 scheduled) | cause, not cost | INFERRED |

MEASURED (`packages/measure-webkit/README.md`): the original page runs a permanent rAF loop, about 105
FireAnimationFrame records per 3 s idle. Combined with §1.1 D7, every one of those frames is also a rendering update
plus a commit (≈ 105 Composite per 3 s), even with no visual change. INFERRED: the prediction to check is
Composite ≈ FireAnimationFrame while idle on the original page, and Composite ≈ 0 while idle on an optimized page
with no rAF loop and only accelerated animations.

### 5.3 Predictions to check on CI (each is an INFERRED consequence of the confirmed model)

| ID | Prediction | Engine counter |
|---|---|---|
| P1 | An optimized part whose animation is a threaded scroll-driven transform, opacity or filter adds 0 RecalculateStyles, Layout and Paint per scroll step beyond the page's baseline | measure-webkit per-step tally, A vs R |
| P2 | Replacing a rAF loop with a CSS time-based animation of an "always" property removes FireAnimationFrame and the matching Composite records while idle | measure-webkit idle window |
| P3 | Animating clip-path or background-position (either way) yields ≥ 1 Paint per frame on that element's layer | measure-webkit Paint |
| P4 | `renderingUpdateCount` per scroll step is the same for original and optimized (the baseline from §4.2); only S1, S2 and S5 differ | measure-wktr |
| P5 | A 2D-transform JS animation without a compositing reason shows Layout (Overflow) per frame; adding a 3D op removes it | measure-wktr `layoutUpdateCount` |

---

## 6. Proposed Lean encoding (spec first, then golden vectors)

The proposed module is `lean/Fw/Engine/WebKit.lean`. It is a pure model: every definition below is a restatement of
a CONFIRMED row above. Whether WebKit obeys it remains a measured claim, in line with the header of
`lean/Fw/Spec/Cost.lean`.

```lean
inductive Diff | equal | recomposite | repaint | repaintIfText | repaintLayer
  | layoutOOFMoveOnly | overflow | overflowOOF | layout | newStyle      -- StyleDifference.h:28-55 order
deriving DecidableEq, Ord

inductive LayerState | noLayer | layer | composited
inductive Prop' | transform | opacity | filter | clipPath | bgPosition | color | inset | size | ...

def rawDiff : Prop' → Diff × ContextSet           -- §2.2 column 2
def adjust  : Diff × ContextSet → LayerState → Diff   -- RenderElement.cpp:297-359
def stagesOf : Diff → Stages                    -- {style, layout, compUpdate, paint}; flush+commit always

def acceleratedProps : Path → List Prop'         -- §3.1 (always / threaded-only)
def canBeAccelerated (e : Effect) (p : Path) : Bool   -- §3.3 disqualifiers as a conjunction
def ticksMainThread (e : Effect) : Bool := !(allAccelerated e && canBeAccelerated e (pathOf e))

def frameWork (v : Variant) (ev : Event) : Work  -- Event = scrollStep | timeTick | idle
```

The theorems to prove, each with a LaTeX docstring:

1. **`diff_order`**: `Diff` is a total order with `recomposite` below `repaint` below `layout`, and `stagesOf` is
   monotone in it. $d_1 \le d_2 \Rightarrow \mathrm{stages}(d_1) \subseteq \mathrm{stages}(d_2)$.
2. **`composited_le`**: for transform, opacity and filter values,
   $\mathrm{adjust}(r, \mathrm{comp}) \le \mathrm{adjust}(r, \mathrm{layer}) \le \mathrm{adjust}(r, \mathrm{noLayer})$.
3. **`accelerated_zero_main`**: an accelerated, running effect contributes zero main-thread `Work` per time tick or
   scroll step, i.e. $\mathrm{ticksMainThread}(e) = \mathrm{false} \Rightarrow \mathrm{work}(e, \mathit{ev}) = 0$.
   This is the engine-specific instance of `compositorOnly_same_main`.
4. **`scroll_baseline`**: every variant pays the same baseline on a scroll step:
   $\forall v,\ \mathrm{renderingUpdates}(v, \mathit{scrollStep}) = 1$. The comparison therefore reduces to the
   S1/S2/S5 components.
5. **`dominance`** (per part): if for each animated property of the optimized part the adjusted `Diff` is ≤ the
   original's, and the optimized part never ticks where the original does not, then
   $\mathrm{frameWork}(\mathrm{opt}, \mathit{ev}) \preceq \mathrm{frameWork}(\mathrm{orig}, \mathit{ev})$, hence
   $\mathrm{mainUs}$ is ≤ by `mainUs_mono`.
6. **Visual-equivalence obligation** (not a pipeline fact; stated alongside): for each timeline progress
   $t \in [0,1]$, the computed value of each animated property agrees, i.e.
   $\mathrm{val}_{\mathrm{opt}}(p, t) = \mathrm{val}_{\mathrm{orig}}(p, t)$ (or lies within the tolerance in
   `Fw/Measure/Tolerance.lean`). Moving a property to the accelerated path changes *where* it is computed, not
   *what* is computed. The legacy CAAnimation path, however, rejects `steps()` and `linear()` points (§3.3); an
   optimized part that relies on them silently falls back to the main thread, which is a cost change, not a visual
   change.

**Golden vectors.** Lean emits `(property, layerState) → Diff → stages` and `effect → accelerated?` as JSON. The
measure reducers then check the P1-P5 predictions against them, rather than hard-coding expectations in TS.

---

## Open items

| ID | Item | How to close |
|---|---|---|
| O1 | UIKit `setContentOffset:` during pan or momentum (scroll-jacking feel) | MEASURED on the real phone in a booked session; not derivable from WebKit source |
| O2 | Safari's actual values of `ThreadedScrollDrivenAnimationsEnabled` and `ThreadedTimeBasedAnimationsEnabled` | read on the Simulator (`defaults`/Web Inspector "Experimental features"), or infer from a CI trace: P1 holds only if threaded scroll-driven animations are on |
| O3 | How a Some-state effect (accelerated plus non-accelerated properties) is split on the threaded path | read `KeyframeEffect.cpp` around 2724-2744 and `AcceleratedEffect` construction |
| O4 | There is no paint-area counter in WKTR | add `internals.startTrackingRepaints()`/`repaintRectsAsText()` to measure-wktr to give S5 a count |
| O5 | The `clip` (ClipRect) adjustment cell in §2.2 | re-read the ClipRect branch of `adjustStyleDifference` |

## What this changes in the plan

- **`docs/plan/PLAN.md`, Lean-first section (engine models).** Add a module `lean/Fw/Engine/WebKit.lean` holding
  `Diff`, `adjust`, `stagesOf`, `canBeAccelerated` and `frameWork`, with the theorems in §6. `dominance` per part
  replaces "measure on device to see if it is faster" as the primary argument. The measurements become the check of
  the model (P1-P5), not the proof.
- **Optimization rules (site build).** Prefer CSS scroll-driven animations of transform, opacity or filter
  (threaded, UI process) and CSS time-based animations of the "always" properties. Do not rely on `will-change` on
  iOS, because it is dropped under memory pressure. Give a JS-animated element a real compositing reason (3D op or
  an accelerated animation). Never animate clip-path or background-position per frame. Never `scrollTo` from rAF.
  Remove the permanent rAF loop, which costs one update and one commit per frame while idle.
- **Measurement section (measure-webkit / measure-wktr).** Report per scroll step `renderingUpdates` as the shared
  baseline, and compare only S1, S2 and S5 (RecalculateStyles, Layout, Paint). Use Composite as the
  rendering-update count on iOS 27. Add the P1-P5 checks as Lean golden vectors. Add a repaint counter to WKTR (O4).

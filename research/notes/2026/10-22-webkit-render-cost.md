---
id: 2026-10-22-webkit-render-cost
kind: note
title: "Where Safari pays for each frame of the hero exit and the end-of-page morph: main thread to glass, from WebKit source"
status: review
created: 2026-10-22
topics: [webkit, safari, ios, macos, remote-layer-tree, gpu-process, iosurface, raster, frame-scheduling, scrolling, touch-input, images, hero.exit, morph.tween, nav, coverage, lag]
---

# Where Safari pays for each lagging frame

This note extends [10-20-webkit-lag-source.md](10-20-webkit-lag-source.md) (Q1-Q8, terms 1-13, C1-C7) and does not
repeat it. It uses source only and ran no measurement. Every cite is WebKit @862f17d (tag WebKit-7625.1.29.10.29).
Prefixes: `WC/` = Source/WebCore/, `WK/` = Source/WebKit/, `WTF/` = Source/WTF/, `Prefs.yaml` =
WTF/Scripts/Preferences/UnifiedWebPreferences.yaml. "(raw)" marks a file fetched from raw.githubusercontent at the
same sha because the sparse clone lacks it. CoreAnimation, the render server, UIKit, IOSurface, CoreGraphics, ImageIO
and Metal are closed source: their costs are INFERRED and can only be measured.

## Answer

- On iOS the next page frame starts only after the GPU process has answered the flush of the previous one, or the flush
  wait has timed out (F1, CONFIRMED). Whether that answer waits for raster to finish is gap (e), INFERRED yes. So GPU
  raster likely shows up in the rAF interval as a gated gap with an idle main thread, and in Web Inspector inside
  "Composite", never inside "Paint" (F2).
- In the morph, each frame that changes a layer's size throws away its buffers. The GPU process allocates a new
  IOSurface and rasterizes the whole layer, and a pooled surface is reused only at the exact same size, so every morph
  frame allocates new surfaces (F3; path CONFIRMED, cost INFERRED). At the end state the nav or the panel is about
  13.5 MB per surface on an iPhone and 10.8 MB in the CI Simulator.
- The hero exit resizes no backed layer. Its per-frame cost is restyle, outset layout and a full re-raster of the
  `.cue` (and `.copy` on Mac) into same-size buffers, then a CA re-blur (prior note Q2b; INFERRED that no allocation
  happens there).
- Work that neither rAF nor Web Inspector attributes: UIView creation for new layers at morph start (F7), the pin's
  fight with UIScrollView (F12), the touch-start wait (F16) and the render-server blur and backdrop work. Instruments
  sees all of them.
- Highest-value same-look candidates: C1 (constant layer bounds) first, then C4 (scroll lock instead of the pin), then
  C8 (fixed-size nav with an animated composited `clip-path`).
- Negative result F8: giving the column `<img>` elements their own layers does not stop raster in Safari.

## Per-frame cost path, main thread to glass

A = hero exit (`hero.exit`, scroll-driven by JS). B = end-of-page morph (`morph.tween`, 680 ms rAF tween). "Insp" =
Web Inspector Timeline; "Instr" = Instruments on the named process.

| # | Step | A | B | Who pays | rAF interval | Insp | Instr |
|---|---|---|---|---|---|---|---|
| 1 | Touch start | none armed | non-passive window `touchmove` within the 200 % band makes pan start wait for one web main-thread turn (F16) | UI main thread waits on web main | no | touch dispatch only | yes (UI and web) |
| 2 | Script | `--exit-*` writes per scroll frame | `--morph` writes; `pin()` reads `scrollY` and calls `scrollTo`, which runs style, layout and compositing synchronously (F12) | web main | yes | Script; forced layout inside it | yes |
| 3 | Style | readers of `--exit-*` | nav subtree (`--morph`) and platform subtree (`--morph-fade`) | web main | yes | Recalculate Styles | yes |
| 4 | Layout | `.copy`/`.cue` blur outsets (Layout diff) | nav subtree plus the platform section's normal-flow path (F9) | web main | yes | Layout | yes |
| 5 | Compositing update | geometry and filter changes | requirements traversal of later layers on each new or resized backing (F11) | web main | yes | no record | `CompositingUpdate` signpost |
| 6 | Paint record | full `.cue` (and `.copy` on Mac) | full nav, panel, tracks, platform background (F3, F10) | web main | yes | Paint (nested inside Composite) | yes |
| 7 | Transaction build and send | small | large; Liquid Glass edge sampling at commit (F19) | web main | yes | Composite | `FixedContainerEdgeSampling` signpost |
| 8 | GPU raster | full repaint, same-size buffers | new IOSurface per resized layer, full raster, track tiles (F3, F4); filter-chain rebuild for painted blurs (F5) | GPU process, one serial queue per web connection | as a gated interval (F1; INFERRED until gap e is read) | inside Composite (F2) | GPU process time profile; allocations INFERRED visible |
| 9 | Flush wait | short | long | web commit thread | as a gated interval | inside Composite | yes |
| 10 | UI apply | CA filter values | import of new surfaces; about 80-160 new UIViews at morph start (F7); pin `setContentOffset` (F12) | UI main thread | only if it delays `DisplayDidRefresh` (INFERRED) | no | UI process; `slowFrame` signpost |
| 11 | Render server | re-blur up to 18 px | panel and platform blur, nav backdrop re-sample | render server (closed) | no (INFERRED) | no | yes (INFERRED) |

Steps 1-7 are the only steps a main-thread profile sees. Steps 8-9 reach rAF only through the commit gate. Steps
10-11 run beside the next page frame.

## Findings

| # | Finding | Evidence @862f17d | Status |
|---|---|---|---|
| F1 | Commit gate. The web process allows one commit in flight: `updateRendering` defers while `m_waitingForBackingStoreSwap`, which every commit sets and `displayDidRefresh` clears. The commit thread waits for each backing store's GPU flush (with a timeout; the commit is sent even if the flush timed out, `RemoteLayerTreeDrawingArea.mm:520`), then posts completion to main. The UI process sends `DisplayDidRefresh` only with no commit pending on iOS; Mac allows a second commit after 4 delayed ones. While rAF runs continuously, updates start on refresh ticks, so intervals cluster at multiples of 16.7 ms (INFERRED from the CONFIRMED gate); the first frame after idle starts off-tick, because `scheduleRenderingUpdate` triggers on the next main run-loop turn when no refresh is pending, and `displayDidRefresh` can take the idle path. WebCore's `RenderingUpdateScheduler` and `DisplayRefreshMonitor` are bypassed on this path. | `WK/WebProcess/WebPage/RemoteLayerTree/RemoteLayerTreeDrawingArea.mm:76, 319-333, 383, 431-442, 451-472, 508-526, 562-584`; `WK/WebProcess/GPU/graphics/RemoteImageBufferSetProxy.cpp:50-56, 98-107, 254` (raw); `WK/UIProcess/RemoteLayerTree/RemoteLayerTreeDrawingAreaProxy.mm:799-834`; `Prefs.yaml:296-308`; `WC/page/Page.cpp:2145-2148`; `WK/WebProcess/WebCoreSupport/WebChromeClient.cpp:1339-1347` | gate CONFIRMED; raster inside the gate INFERRED (gap e); clustering INFERRED |
| F2 | "Composite" has four parts: paint recording (the Paint records nest inside it), transaction build, the GPU-process flush wait, and the delay before main runs the posted completion. It starts at `willStartRenderingUpdateDisplay`, before the transaction build and recording, and ends when the completion posted from the commit queue runs on main. So "Composite much longer than summed Paint" does not isolate GPU raster; use Composite minus nested Paint minus main-thread busy time. The UI process's `slowFrame` signpost fires when update start to commit receipt exceeds 1/nominal fps: approximate on 60 Hz displays, over-counts on ProMotion (8.3 ms threshold); whether the signpost category is enabled is unverified (WTF SystemTracing is not in the clone). | `RemoteLayerTreeDrawingArea.mm:357, 434-438, 445-448`; `WK/WebProcess/WebPage/RemoteLayerTree/RemoteLayerTreeContext.mm:203-204`; `WC/page/Page.cpp:2587-2608`; `WC/rendering/RenderLayerBacking.cpp:4164, 4198`; `RemoteLayerTreeDrawingAreaProxy.mm:432-435` | CONFIRMED; `slowFrame` signpost gating unverified |
| F3 | A layer whose bounds change gets new buffers and a full raster every frame. `setBounds` changes the backing parameters, the GPU process clears front, back and secondary buffers, allocates a new front, and `prepareToDisplay` forces a full display with no front buffer. The UI process misses its buffer cache and imports the new IOSurface. A pooled surface must match size, format and colour space exactly. The iOS pool cap is 64 MB with 32 MB in use, so one 13.5 MB surface fits; the exact-size rule, not the cap, causes the allocation. With a steady size the buffers swap and only the dirty part is repainted. | `WK/WebProcess/WebPage/RemoteLayerTree/PlatformCALayerRemote.mm:333-355, 596-607`; `WK/Shared/RemoteLayerTree/RemoteLayerWithRemoteRenderingBackingStore.mm:83-84, 126-151`; `WK/WebProcess/GPU/graphics/RemoteImageBufferSetProxy.cpp:234-238, 274-291` (raw); `WK/GPUProcess/graphics/RemoteImageBufferSet.cpp:89-93, 127-150`; `WK/Shared/graphics/ImageBufferSet.cpp:42-73, 103-153` (raw); `WC/platform/graphics/cg/IOSurfacePool.cpp:81-91, 124-135`; `IOSurfacePool.h:86-94`; `WK/Shared/RemoteLayerTree/RemoteLayerBackingStore.mm:519-553, 644-695` | path CONFIRMED; cost INFERRED |
| F3b | Bytes per pixel. A real iPhone has an extended-colour screen, so WebKit picks `RGBA10` and the backing is RGB10A8, 5 B/px when not opaque. The Simulator and Mac lack `HAVE_IOSURFACE_RGB10`, so they use BGRA8, 4 B/px. End-state maxima per surface for the nav or the panel: iPhone 1098 × 2460 device px × 5 B = 13.5 MB; CI Simulator × 4 B = 10.8 MB; Mac 2x 2796 × 1640 × 4 B = 18.3 MB. Simulator byte counts understate the device by 20 %. | `WC/platform/ios/PlatformScreenIOS.mm:85-88`; `WC/platform/graphics/ca/PlatformCALayer.mm:197-198`; `WC/platform/graphics/ContentsFormat.h:58-59` (raw); `RemoteLayerBackingStore.mm:271-286`; `WTF/wtf/PlatformHave.h:902-904`; `WTF/wtf/PlatformEnableCocoa.h:769-771`; areas from the prior note's per-layer table | format CONFIRMED; sizes INFERRED |
| F4 | iPhone tracks are tiled at 512 px. A 372-device-px track is narrower than one tile, so every column is an edge tile, and a width change gives every tile `setBounds` and `setNeedsDisplay`. Tiles outside the primary coverage stay stale. | `WC/platform/graphics/ca/TileController.h:58, 267`; `TileController.cpp:500-548, 658-686`; `WC/platform/graphics/ca/TileGrid.cpp:125-136, 272-283, 625-645` | path CONFIRMED; reallocation of every tile INFERRED |
| F5 | A painted blur whose radius changes rebuilds the whole filter chain and repaints the full filter region. A changed `filter` value calls `clearLayerFilters`, which forces the rebuild (FIXME at `:214`). GraphicsContext (CGStyle) filters are on by default; CoreImage filters are off. GPU replay takes intermediate surfaces from the pool. Applies to the earn button while it is not composited. | `WC/rendering/RenderLayer.cpp:6418-6442`; `WC/rendering/RenderLayerFilters.cpp:207-236, 240-261`; `Prefs.yaml:3509-3523` (GraphicsContextFiltersEnabled), `:156-169` (AcceleratedFiltersEnabled, CoreImage); `WC/page/Page.cpp:4902-4929`; `WK/GPUProcess/graphics/RemoteGraphicsContext.cpp:358-408` | CONFIRMED |
| F6 | A composited `clip-path` with no mask is a CAShapeLayer mask. A change is RecompositeLayer, not Repaint (a FIXME notes some repaints remain). | `WC/rendering/RenderLayerBacking.cpp:1933-1957, 3035-3065`; `WC/rendering/RenderLayer.cpp:779-791`; `WC/rendering/RenderElement.cpp:321-326`; `WC/style/StyleDifference.cpp:779-781` | CONFIRMED; interaction with `backdrop-filter` unread (gap a) |
| F7 | On iOS each composited layer is a UIView, created during the commit on the UI main thread, the thread that also runs scroll callbacks. At morph start about 80 countdown faces plus their `.digit { overflow: hidden }` clipping layers composite in one commit: about 80-160 UIViews. Under the Conservative policy on non-Mac, `will-change` alone does not composite. | `WK/UIProcess/RemoteLayerTree/ios/RemoteLayerTreeHostIOS.mm:60-98`; `WK/UIProcess/RemoteLayerTree/RemoteLayerTreeHost.mm:147-225`; `WK/UIProcess/API/ios/WKWebViewIOS.mm:2384-2399`; `WC/rendering/RenderLayerCompositor.cpp:3584-3607, 3997-4018` | path CONFIRMED; count and UIKit cost INFERRED |
| F8 | Negative result: a composited `<img>` still rasterizes. `GraphicsLayerCARemote::shouldDirectlyCompositeImage` returns false, and `PlatformCALayerRemote::setContents` ignores non-null contents (null clears the backing store). The direct-image path in `RenderLayerBacking.cpp` is dead in Safari. | `WK/WebProcess/WebPage/RemoteLayerTree/GraphicsLayerCARemote.h:72`; `PlatformCALayerRemote.mm:817-821`; `RenderLayerBacking.cpp:3687-3736, 3850-3881` | CONFIRMED |
| F9 | The nav resize alone lays out only the view root's out-of-flow boxes: the RenderView is the layout boundary and takes `simplifiedLayout`, and inside the nav every in-flow child relayouts on a width change. In the same morph frames `--morph-fade` changes the platform's `filter: blur` radius (0 to 12 px), a Layout diff on in-flow content (prior note Q2b and S3 filters row). That sets `normalChildNeedsLayout`, so `canPerformSimplifiedLayout` is false, and the platform repaints its background. | `WC/rendering/RenderObject.cpp:516-519, 593-656`; `WC/rendering/RenderView.cpp:174-213`; `WC/rendering/RenderBlock.cpp:684-695, 736-748, 765-831`; `WC/rendering/RenderBlockFlow.cpp:555` | CONFIRMED |
| F10 | `repaintRectsAsText` reports web-side invalidation only. A resized backed layer is fully re-rasterized anyway (F3), whatever rects layout reports. `repaintAfterLayoutIfNeeded` has several full-repaint cases, among them `requiresFullRepaint` and fills that depend on size. | `WC/rendering/RenderLayer.cpp:1237-1432`; `WC/rendering/RenderElement.cpp:1482-1600, 1515-1520`; `RemoteLayerWithRemoteRenderingBackingStore.mm:83-84` | CONFIRMED |
| F11 | A geometry change sets a post-layout compositing update. A new or resized backing sets `fullPaintOrderTraversalRequired`, which re-evaluates every later layer (FIXME in place). Opacity reaching or leaving 0 adds a configuration update. | `WC/rendering/RenderLayerCompositor.cpp:1272-1420, 2196-2322, 2399-2518`; `RenderLayerBacking.cpp:1145-1163` | CONFIRMED |
| F12 | `pin()` forces synchronous style, layout and compositing in JS: `scrollY` (read first, `morph.tween/driver.ts:162`) forces layout, and `scrollTo` runs `updateLayoutIgnorePendingStylesheets(UpdateCompositingLayers)`. How much is dirty depends on the order of the scroll event and rAF (INFERRED). `updateCompositingLayers` bails while the RenderView needs layout. On iOS the main frame delegates scrolling: `requestScrollToPosition` applies a Programmatic update that reaches `notifyScrollPositionChanged`; the OnScroll update marks the root for a full requirements traversal (FIXME "avoid for page scrolling"); the link from `notifyScrollPositionChanged` to `scrollOffsetChangedViaPlatformWidgetImpl` is in a file outside the clone. The UI process applies the request after the commit as `setContentOffset` without interrupting a drag or deceleration, and may fire `scrollend`. | `WC/page/LocalDOMWindow.cpp:1480, 1844`; `RenderLayerCompositor.cpp:1065-1068, 1076-1089`; `WC/page/scrolling/AsyncScrollingCoordinator.cpp:381-419, 700-714, 829-884`; `WC/page/LocalFrameView.cpp:3759-3770, 3886-3899, 3913-3955`; `WK/UIProcess/RemoteLayerTree/RemoteScrollingCoordinatorProxy.cpp:172-212, 350-357`; `WKWebViewIOS.mm:1515-1555` | sync work CONFIRMED; last link and visible fight INFERRED |
| F13 | Page updates run at 60 Hz on a 120 Hz phone (`DisplayLinkFramesPerSecond = 60`; Near60 preference on). rAF-driven scroll-linked visuals update at half the scroll rate and trail it by at least 2 display frames. | `WK/UIProcess/RemoteLayerTree/ios/RemoteLayerTreeDrawingAreaProxyIOS.mm:47, 239-266, 354-368, 405-425`; `Prefs.yaml:6505-6520`; `WC/platform/graphics/AnimationFrameRate.cpp:35-45` (raw) | 60 Hz CONFIRMED; the 2-frame lag INFERRED |
| F14 | Thermal pressure alone does not halve rAF. Half-speed reasons are Low Power Mode, a non-interacted cross-origin frame, visually idle, and aggressive thermal mitigation (an internal setting, off). Thermal pressure only aligns DOM timers to 30 ms. Prior note term 11 is wrong on this. | `AnimationFrameRate.cpp:33` (raw); `WC/page/Page.cpp:2824-2840, 3065-3073`; `Prefs.yaml:6964-6974`; `WC/page/DOMTimer.h:53-56` | CONFIRMED |
| F15 | The sticky hero stays async in the UI process because the page root's `overflow-x` is `clip`, which `hasPotentiallyScrollableOverflow` excludes. The page root is a `<div>` (`apps/site/src/App.tsx:68`), so its overflow does not move to the viewport. `hidden` would turn `overflow-y` from `visible` into `auto` and make the div the sticky's scroll container, so the hero would stop sticking to the viewport: a visible change. | `RenderLayerCompositor.cpp:4226-4250`; `WC/rendering/RenderLayer.cpp:1826-1836`; `WC/rendering/RenderElementInlines.h:86-91`; `apps/site/src/styles/reset.css:98-104` | WebKit path CONFIRMED; `visible` computing to `auto` CONFIRMED by [CSS Overflow 3](https://www.w3.org/TR/css-overflow-3/#overflow-control); unsticking INFERRED |
| F16 | A window-level non-passive `touchmove` listener makes the pan start wait for the web main thread, with no timeout. Touchmoves coalesce while main is busy. | `WK/UIProcess/WebPageProxy.cpp:5049-5075, 5105-5125, 5174-5214, 5228-5300`; `WK/UIProcess/Cocoa/WKDeferringGestureRecognizer.swift:58-59`; `WK/WebProcess/WebPage/EventDispatcher.cpp:243-282`; `apps/site/src/parts/morph.mount/index.tsx:89-96` | CONFIRMED |
| F17 | An image drawn before decode draws blank, requests a decode, and repaints later. `decode()` decodes at natural size, so later draws at any size need no sync decode. | `WC/platform/graphics/BitmapImage.cpp:107-118`; `WC/rendering/RenderBoxModelObject.cpp:256-320`; `WC/platform/graphics/BitmapImageSource.cpp:349-353, 383-414, 563-580` | CONFIRMED |
| F18 | ImageQualityController drops to Low only after an object is drawn at two different sizes while its 500 ms timer runs, then repaints every tracked object. On the iPhone no column image qualifies: all 13 are height-dominated, so their drawn size stays constant (prior note, region B "First morph frames"). On the Mac 5 of 21 are width-dominated. | `WC/rendering/ImageQualityController.cpp:45-46, 83-101, 136-223` | path CONFIRMED; Mac-only |
| F19 | On Liquid Glass builds, a geometry update or repaint of a fixed composited layer queues edge-colour sampling (hit tests) for the next commit, on the web main thread. | `RenderLayerBacking.cpp:1634, 4083, 4138, 5303-5308`; `WK/WebProcess/WebPage/Cocoa/WebPageCocoa.mm:1697-1733, 2336-2338`; `WC/page/LocalFrameView.cpp:2272-2300` | path CONFIRMED; cost INFERRED small |
| F20 | Overlap testing at about 80 face layers is a rect list per layer with a bounding-rect early-out: microseconds. | `WC/rendering/LayerOverlapMap.cpp:40-60, 178-200, 312-330` | structure CONFIRMED; cost INFERRED |

## Coverage map

"Read" means cited above or in the prior note at this sha. Closed-source rows can only be measured.

| Subsystem | Directories | Read | Not read |
|---|---|---|---|
| Style | WC/style, WC/css | yes (prior notes) | |
| Layout | WC/rendering Render*, WC/layout | RenderObject, RenderBlock, RenderView, layout context, InlineContentConstrainer | RenderFlexibleBox, LayoutIntegration, positioned-child relayout rule (C14) |
| Paint recording | WC/rendering RenderLayer paint, WK/WebProcess/GPU/graphics | Paint record sites | RenderLayer::paintLayer*, display-list recorder (gap d) |
| Compositing | RenderLayerCompositor, RenderLayerBacking, LayerOverlapMap, GraphicsLayerCA, PlatformCALayerRemote | yes (F6-F11) | tile coverage (gap b), Conservative switch (gap c), backdrop with clip-path (gap a) |
| Update scheduling | RemoteLayerTreeDrawingArea(Proxy), RemoteLayerTreeDrawingAreaProxyIOS | yes, iOS (F1, F13) | Mac display link (gap f) |
| Commit and UI apply | WK/Shared/RemoteLayerTree, WK/UIProcess/RemoteLayerTree | RemoteLayerTreeHost node creation, backing-store import | transaction encoding, per-property apply cost |
| GPU raster | WK/GPUProcess/graphics, WC/platform/graphics/cg | RemoteImageBufferSet, RemoteRenderingBackend, IOSurfacePool, RemoteGraphicsContext | whether the flush reply waits for raster (gap e) |
| Scrolling and input | WC/page/scrolling, WK/UIProcess/ios, WebPageProxy touch | F12, F15, F16, prior Q7 | WKScrollView, iOS scrolling-tree apply |
| Images | BitmapImage*, ImageQualityController | yes (F17, F18, prior Q8) | |
| Animations | WC/animation, UI RemoteAnimation* | KeyframeEffect size rules | threaded RemoteAnimation stack |
| Closed | QuartzCore, render server, UIKit UIScrollView, IOSurface kernel, CoreGraphics, ImageIO, Metal | no source | measure only (Instruments, phone) |

Not read, ordered by effect on the two lag zones:

- (a) `backdrop-filter` and a `clip-path` mask on one layer: `WKBackdropView` (`RemoteLayerTreeHostIOS.mm`) and the
  backdrop rect updates in `WC/platform/graphics/ca/GraphicsLayerCA.cpp` on each morph frame. C8 and C1b depend on it.
- (b) Tile coverage of the iPhone tracks while their 16 s transform animation runs:
  `GraphicsLayerCA::computeVisibleAndCoverageRect` and the coverage adjustment in `TileController.cpp`. Newly
  revealed tiles may repaint every frame.
- (c) The memory-pressure switch to the Conservative policy (`RenderLayerCompositor.cpp:691-724` and its memory-usage
  source; prior note term 13). It matters more now that a resize allocates 10-13.5 MB surfaces, and it disables C9a.
- (d) Web-process cost of recording full-layer repaints: `RemoteDisplayListRecorderProxy` and
  `RemoteGraphicsContextProxy` in `WK/WebProcess/GPU/graphics/`.
- (e) Whether the `EndPrepareForDisplay` reply waits for raster to finish: the `ImageBufferIOSurfaceBackend` flush and
  `HAVE(CGIOSURFACECONTEXT_FLUSH_QUEUE)`.
- (f) The Mac display link and ProMotion path: `WK/UIProcess/RemoteLayerTree/mac/RemoteLayerTreeDrawingAreaProxyMac.mm`.
  F1 and F13 cover iOS only.

## Same-look candidates

C1-C7 are the prior note's. New numbers start at C8. Priority order is the table order.

| # | Change | Mechanism | Prediction to test |
|---|---|---|---|
| C1 | Constant layer bounds: lay the panel, backdrop and columns out once at the final size, clipped by the nav. | Removes F3 allocation and full raster for the panel and tracks, F4 tile reallocation and the panel-subtree relayout; the nav still resizes. | CI Simulator: IOSurface creations per morph frame fall to the nav's alone; Composite minus nested Paint minus main busy time falls; the share of 33 ms rAF deltas falls (count, not mean, because of F1). |
| C4 | Scroll lock during the morph instead of the per-frame `scrollTo` pin. | Removes F12: the synchronous layout and compositing inside script, the OnScroll traversal, the UI `setContentOffset` fight and extra `scrollend`s. | WKTR: no `compositingUpdateCount` increment from `pin()`; one `scrollend` per gesture; `scrollY` sampled in rAF constant while locked. |
| C8 | Nav at the fixed final size, pill shape drawn by an animated composited `clip-path: inset(... round r)` (C1b without the scale). | F6: RecompositeLayer and a CAShapeLayer mask; no bounds change, so no F3 allocation and no nav repaint. Cost: a full-panel backing (13.5 MB iPhone, 10.8 MB Simulator, 18.3 MB Mac) is held always, and the backdrop samples the full panel area on every scroll frame, not only during the morph. Depends on gap (a). | CI Simulator: zero IOSurface creations and zero nav Paint records during the morph; backdrop re-sample cost on plain scrolling measured against main (Instruments). |
| C9a | Pre-create the morph layers: composite the faces and tracks from mount or the arm band. | Moves F7 UIView creation out of the first morph frame. Fails under the Conservative policy (gap c). | `layerTreeAsText` layer count unchanged across the trigger; no UI main-thread spike at the first morph commit (Instruments). |
| C9b | Constant image drawn size during the morph (scale with a transform on a composited layer). | F18. Mac only; lower priority for the iPhone lag zone. | Mac Safari: no Paint burst about 500 ms after the morph ends. |
| C10 | One layer per digit strip instead of one per face. | Fewer UIViews (F7), traded against larger backings to raster (F3). | Layer count at morph start falls from about 80-160 to about 8-16; parity gate holds. |
| C11 | Arm the non-passive `touchmove` listener only near the take point, not across the 200 % band (a Lean arm rule). | F16: pans outside the narrow band no longer wait for the web main thread. | Phone, Simulator with synthesized touches: touchstart to first scroll movement outside the band equals the no-listener baseline. |
| C12 | `img.decode()` at idle for column images within 1-2 viewports, same `src`. | F17: no blank first draw and no second paint. | Blank-draw count 0 and one Paint per image tile. |
| C13 | Keep `overflow-x: clip` on the page root; add a gate predicate that no ancestor of a sticky part is `hidden`, `auto` or `scroll` unless it is the scroller. | F15. | A `hidden` branch fails the predicate and shows the hero unpinned in captures. |
| C14 | Fixed-size, absolutely positioned inner wrapper for the nav content. | Cuts F9 nav-subtree relayout. The positioned-child relayout rule is unread; overlaps C1 and C8. | WKTR layout counter covers fewer renderers per frame. |
| C15 | End mid-morph opacities at 0.001 and set `visibility` at the end, instead of reaching 0. | Avoids the F11 configuration update. Same look INFERRED. | One fewer configuration update per crossing; parity gate holds. |

## Applying the adversarial check



- Candidate labels: the check asked to mark the area-1 "fixed-size nav with `clip-path`" as C1b without the scale. The
  task fixes its canonical number as C8, so C8 carries that label in parentheses.
- Duplicates are cited once: area 1 F1 and area 2 F1 are F1-F2 here; area 1 F2 and area 3 F3 are F3; area 2 F8 and
  area 3 F7 are F7.
- Prior note term 11 (thermal throttles rAF to 30 fps) is wrong per F14. This task commits only this file, so the fix
  to `10-20-webkit-lag-source.md` is left to the lead.

The measured probe does not test F2. `10-21-webkit-lag-probe.md:63` reports region A Composite at 2.33 (1.91-2.62) of
the calm baseline for the original and 1.64 for faithful, and concludes "no difference shown (ranges overlap)".

## What this changes in the plan

| Section | Change |
|---|---|
| §4.2 Step 1, WebKit lane | Add per morph frame on the CI Simulator: IOSurface creations, Composite minus nested Paint minus main busy time, rAF delta histogram at 16.7, 33.3 and 50 ms, `compositingUpdateCount` per `pin()` call and per frame, layer count before and after the trigger, blank-draw count, touchstart-to-first-scroll inside and outside the band, `scrollend` per gesture. Report device bytes at 5 B/px, Simulator at 4 B/px. Record Low Power Mode per phone pass. |
| §5.1 `Fw.Engine.WebKit` | Replace the cadence term with the commit gate (iOS one in flight, page tick 16.7 ms at 120 Hz; Mac a second commit after 4 delays). Add: bounds change = new surface + full raster at 5 or 4 B/px; programmatic scroll = sync layout + compositing + full traversal; UIView per new layer on iOS; edge sampling per changed fixed layer. Throttle to 30 fps only for Low Power Mode, idle, cross-origin or the aggressive-thermal setting. Record F8 and F20 as negative results. |
| §6.1 parts | Rank C1 first, C4 above the pin, then C8 after gap (a) is read; add C9a-C15 as gate candidates; drop image promotion (F8). |
| Research backlog | Read gaps a, b, c first, then d, e, f. |

# 04. WebKit / Safari rendering math: measuring animation cost from engine statistics

Kickoff research note for the v2 plan architect, 2026-10-17. Topic: how WebKit (Safari on iOS and macOS) produces a
frame, which work counts are deterministic and can be pulled from the engine without the iPhone, through which
interfaces, how to turn them into a cost model (work counts × device coefficients), and how to validate that model with
the real iPhone used only for periodic calibration.

Labels: **CONFIRMED** = a cited WebKit source line, Apple/WebKit doc, bug or our own v1 data says so. **INFERRED** = my
reasoning from those, still to check. "v1:" = the old repo `../fastwork-com-web-optimize` (read only).
No Fastwork code or personal data is quoted here.

**Source pins (read 2026-10-17 through `gh api`, raw file contents):**
- WebKit `main` = commit `77db40e2fa70` (2026-10-16). Line numbers are for `main` unless the row names a branch.
- `safari-7625.1.29.18-branch`: the Safari 27 family. This host's Safari is 27.0.1, build 22625.1.29.11.28.
- `safari-7624.5.1.11-branch`: the Safari/iOS 26.x family. The v1 phone ran iOS 26.6.1.
- Playwright `main` and releases v1.61-v1.64.

---

## 0. Summary for the plan architect

1. **Count the work in the inner loop; time it on the phone only.** v1's Simulator study already shows the split
   (v1:`research/simulator/README.md` §6):
   - *Mechanism transfers.* Which layouts happen matched in 11/13 cells, with all absences agreeing.
   - *Timing does not transfer.* The morph ran about 4x slower per frame, an A/B comparison reversed with disjoint
     ranges, and count ratios ranged from 0.77 to 62.
   - So the v2 inner loop should measure **deterministic work counts**: restyled elements, layouts, paint area, layers,
     backing bytes, accelerated or not. It should measure them in a **frame-stepped** harness indexed by scroll position
     and animation time, not by wall clock. Device **coefficients** turn counts into ms, and only calibration runs fit them.
2. **WebKit already ships the counters, in its test build.** `window.internals` exists only in WebKitTestRunner (WKTR)
   and DumpRenderTree (CONFIRMED, `Source/WebCore/testing/Internals.idl`). It exposes:
   - `styleRecalcCount`, `lastStyleUpdateSize`, `styleInvalidationTraversalCount`;
   - `layoutUpdateCount`, `compositingUpdateCount`, `renderingUpdateCount`, `layerFlushCount`;
   - `startTrackingRepaints` / `repaintRectsAsText`, and `layerTreeAsText` with flags for repaint rects, tile caches and
     backing-store-attached;
   - `acceleratedAnimationsForElement`, which returns `isThreaded`;
   - `synchronousScrollingReasons`;
   - switches to force the memory-pressure compositing policy, Low Power Mode and thermal mitigation.

   WKTR runs on the **iOS Simulator** with the iOS code paths. The catch: it needs a local WebKit build.
3. **Stock Safari offers no internals, but it does speak the Web Inspector protocol.** On the iOS Simulator and on the
   device, through `ios_webkit_debug_proxy`, it provides:
   - `LayerTree`: layer count, `memory`, `paintCount`, 29 compositing-reason flags;
   - `Timeline`: Paint records with a clip quad, Layout records (Safari 27 adds the layout root element), RecalculateStyles,
     Composite and RenderingFrame records.

   This needs no WebKit build. v1 already drove the Simulator this way. New since v1: Playwright ≥ 1.61 has an
   experimental, undocumented backend that drives **stock Mobile Safari** in the Simulator through
   `webkit.connectOverCDP(<iwdp ws url>)` (CONFIRMED in source, §4.3).
4. **Three clocks, not one.** Each needs its own budget (CONFIRMED in source, §2.3):
   - Safari's page rendering (rAF, style, layout, paint) asks for **60 Hz** even on 120 Hz ProMotion.
   - Core Animation animations created by WebKit ask for **80-120 Hz** in the render server.
   - Threaded scroll-driven animations (Safari 26.4+) are resolved outside the WebContent main thread.

   Threaded **time-based** animations are `stable` and on in WebKit `main`, `preview` and off in Safari 27, and
   `unstable` and off in 26.x. That is a version axis the model must carry.
5. **Proposed model (§7).** Main-thread cost `W` is a linear sum of counts × coefficients. GPU-process raster `F` scales
   with dirty device pixels and new backing bytes. The UI apply `U` scales with changed layers. These set the rAF
   interval. Render-server cost `RS` (backdrops, filters, offscreen passes) is **not** on the rAF path, and only
   Instruments on the device sees it.
   - Coefficients come from a fixed calibration micro-suite run on the iPhone at each Safari/iOS version change, or when
     residuals drift.
   - Counts come from the Simulator or WKTR for every experiment.
6. **Lean fits the decision functions and the model algebra, not the engine** (§10). Candidates:
   - frame-rate selection (`preferredFramesPerSecond`, a ~30-line pure function);
   - acceleration eligibility (`KeyframeEffect::canBeAccelerated`, version-tagged);
   - the tiling threshold and the backing-store byte formula;
   - monotonicity of the cost model (removing work never raises predicted cost);
   - the metric definitions (dt > 50 ms).
7. **Biggest risks:**
   - **Host limits for a local WebKit build.** This Mac has 16 GB RAM and 69 GB free disk; that is tight, see §5.
   - **Render-server and GPU cost cannot be counted off-device.** Backdrop-filter blur was v1's largest blind spot.
   - **Version skew.** The iOS 26.5 Simulator runtime is installed, the phone is probably on 26.6.x or 27, and the host
     Safari is 27.0.1.
   - **Counts from a frame-stepped harness miss emergent timing effects:** back-pressure, catch-up frames, finger-only
     toolbar resizes. The device stays the outer loop.

---

## 1. Version map: pin every claim to a build

| Safari | WebKit family | public branch to read | notes | status |
|---|---|---|---|---|
| 26.0-26.1 | 622 | - | scroll-driven animations ship, main thread | CONFIRMED (v1:`research/architecture/claims-audit.md` §2 version map; WebKit blog 26.0) |
| 26.4 | 624.1 | `safari-7624-*` | **threaded scroll-driven** animations | CONFIRMED (https://webkit.org/blog/17862/webkit-features-for-safari-26-4/) |
| 26.5 / 26.6.x | 624.2.5 / 624.4.5-624.5.1 | `safari-7624.5.1.11-branch` | the v1 phone (26.6.1); the installed Simulator runtime is iOS 26.5 (23F77) | CONFIRMED (`xcrun simctl list runtimes` on this host; v1 simulator §1) |
| 27.0.x | 625.1.29.x | `safari-7625.1.29.18-branch` | host Safari 27.0.1 = 22625.1.29.11.28; scroll anchoring; Safari MCP; Timeline Layout events carry the layout root element | CONFIRMED (Info.plist on this host; https://webkit.org/blog/18325/webkit-features-for-safari-27-0/) |
| next | `main` | `main` @ 77db40e2fa70 | threaded time-based animations stable and on | CONFIRMED (UnifiedWebPreferences.yaml, §2.3) |

Rule for v2: every rule, count and coefficient is stored with `(engine, family/tag, platform)`. A claim read on `main`
is not a claim about the phone (v1 learned this the hard way: claims-audit §1.4).

---

## 2. The WebKit frame on iOS (and now macOS)

### 2.1 Processes and phases

One displayed frame crosses four processes (CONFIRMED in source: v1 traced it in
v1:`research/design-engineering/safari-render-signals.md` §1.1, and I re-checked the key lines on `main`):

1. **WebContent main thread: `Page::updateRendering()`** (`Source/WebCore/page/Page.cpp` l.2476).
   - It runs the HTML "update the rendering" steps, in the order of the `RenderingUpdateStep` enum
     (`Page.h` l.305-345): RestoreScrollPosition, Reveal, Resize, Scroll, MediaQueryEvaluation, AdjustVisibility,
     **Animations**, Fullscreen, VideoFrameCallbacks, **AnimationFrameCallbacks** (rAF), CaretAnimation,
     **layoutIfNeeded**, ResizeObservations, FocusFixup, UpdateContentRelevancy (content-visibility),
     ViewTransitions, **IntersectionObservations**, Images, …
   - It ends with `layoutIfNeeded(UpdateCompositingLayers)`, then the after-update steps: PaintTiming, EventTiming,
     **EventRegionUpdate**, AccessibilityRegionUpdate (`Page.cpp` l.2661+).
   - `++m_renderingUpdateCount` at l.2645 is the counter that `internals.renderingUpdateCount()` reads.
2. **Layer flush on the same thread.** `finalizeRenderingUpdateForRootFrame` (l.2802-2829) runs
   `flushCompositingStateIncludingSubframes()`, then commits the scrolling-tree state.
   - The transaction is built, and dirty backing stores **record display lists**. GPU-process DOM rendering is on by
     default on iOS **and macOS** (`Source/WTF/wtf/PlatformEnableCocoa.h` `main` l.416-420; 7625 l.400-404).
   - WebKit's own comment (`Page.cpp` `willStartRenderingUpdateDisplay`, l.2848-2859): "Inspector's use of 'composite' is rather innacurate. On Apple
     platforms, the 'composite' step happens in another process".
3. **GPU process.** It replays the display lists into IOSurfaces (CPU raster). The WebContent commit queue waits on the
   flush fence and then sends `CommitLayerTree` (v1 safari-render-signals §1.1, rows 8-9).
4. **UI process (Safari).** It applies the commit to CALayers, owns the **scrolling tree** (async scrolling, sticky and
   fixed positioning), and runs the **display link** that releases the next rendering update. Only one commit may be
   pending on iOS (v1 safari-render-signals §1.1, row 11).
5. **Render server (backboardd).** It composites on the GPU, including the offscreen passes for `backdrop-filter`,
   filtered groups, masks and group opacity. Apple calls a miss here a *render hitch*
   (https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app).

**macOS is now the same architecture.**
- `ENABLE_REMOTE_LAYER_TREE_ON_MAC_BY_DEFAULT` is set for `PLATFORM(MAC)` (`PlatformEnableCocoa.h` `main` l.851-853;
  7625 l.817-819; 7624 l.842-844 for macOS 14+). `WebViewImpl.mm` l.1366-1383 picks the `RemoteLayerTree` drawing area
  unless a user default overrides it.
- So macOS Safari 27 also uses UI-side compositing plus GPU-process painting. CONFIRMED in source. That Safari.app does
  not override the default is INFERRED; check it once.
- **Consequence:** macOS Safari is a much closer stand-in for the *pipeline shape* than it was in 2018-2022. It still
  differs in tiling, DPR, coverage, toolbar and display link (§6).

### 2.2 Time per frame and back-pressure

- **The rAF stamp is not a vsync.** `performance.now()` is frozen at the start of `updateRendering`, at 1 ms resolution.
  - CONFIRMED: v1 claims-audit P10, from `Document.cpp` and `Page.cpp`.
  - v1 re-binned 198,349 phone rAF gaps and found **no 16.7 ms grid above one vsync** (claims-audit §2.3, OBSERVED).
- **Back-pressure.** WebContent defers frame N+1 while a backing-store swap or commit is pending
  (`m_waitingForBackingStoreSwap`, `RemoteLayerTreeDrawingArea.mm`; v1 safari-inspector-probing §0.2). So
  `rAF gap ≈ W (main) + F (GPU-process raster wait) + U (UI apply) + wait for the next tick`.
- **Render-server time is not on that path.** It couples back only through extra buffer allocation, CPU and thermal
  contention, or a stalled UI commit. INFERRED from source by v1 (safari-render-signals §1.2).

### 2.3 Three clocks (CONFIRMED in source)

| clock | who | rate | source |
|---|---|---|---|
| Page rendering (rAF, style, layout, paint, commit) | WebContent | 60 Hz on a 120 Hz panel, because `PreferPageRenderingUpdatesNear60FPSEnabled` is stable and true on every platform except visionOS | `UnifiedWebPreferences.yaml` `main` l.4914, 7625 l.6505, 7624 l.6392; `AnimationFrameRate.cpp` l.35-45 (`framesPerSecondNearestFullSpeed`) |
| Throttled page rendering | WebContent | **30 Hz** when LowPowerMode, VisuallyIdle, NonInteractedCrossOriginFrame or **AggressiveThermalMitigation** is set | `AnimationFrameRate.cpp` l.33, 47-65; `AnimationFrameRate.h` l.50-56 (`FullSpeedAnimationInterval` 15 ms, half speed 30 ms) |
| Thermal | WebContent | plain `ThermalMitigation` (thermal state ≥ serious, `ThermalMitigationNotifier.mm`) does **not** halve rAF. The aggressive variant depends on `RespondToThermalPressureAggressively`, which defaults to false (`main` l.5250, 7625 l.6964). Thermal therefore shows up as **slower coefficients** (CPU/GPU clocks), not as a 30 Hz cap (INFERRED) | `Page.cpp` l.566-571 |
| CA animations made by WebKit (legacy accelerated path) | render server | each `CAAnimation` gets `preferredFrameRateRange = (80, 120, 120)` | `PlatformCAAnimationRemote.mm` 7625 l.611; `CAFrameRateRangeUtilities.h` `highFrameRateRange` |
| Threaded animations (`main`) | UI process (`RemoteAnimationStack`) | high frame rate only if `ThreadedTimeBasedAnimationsAtHighFrameRateEnabled` (unstable, false, iOS only) | `RemoteLayerTreeDrawingAreaProxyIOS.mm` l.488-503 |
| UI display link | UI process | `DisplayLinkFramesPerSecond = 60` unless high frame rate is wanted | `RemoteLayerTreeDrawingAreaProxyIOS.mm` l.48, `updateFrameRate` l.313-337 |

**Which animations run off the main thread, by version (CONFIRMED in source):**
- **Accelerated properties:** opacity, transform, translate, rotate, scale, offset-path/-distance/-position/-anchor/-rotate,
  filter, backdrop-filter (`AcceleratedEffect.cpp` l.111-150; `RenderLayerCompositor::requiresCompositingForAnimation`
  l.3863-3890).
- **`KeyframeEffect::canBeAccelerated`** (`main` l.1966-2023) refuses an effect that has:
  - a reference filter;
  - a size-dependent transform with an animated size;
  - a discrete transform interval;
  - a non-`replace` composite;
  - a property overridden by the cascade.
- **On the legacy CA path** (`USE(CA)`) it also refuses **`steps()` and `linear()` with points** (l.2009-2014; same in
  7625 l.2011-2014) and progress-based (scroll) timelines.
- **`canHaveAcceleratedRepresentation`** (l.3283-3294) routes scroll-driven animations to the threaded path when
  `ThreadedScrollDrivenAnimationsEnabled` is on (stable and true in 7624, 7625 and `main`). It routes time-based
  animations there when `ThreadedTimeBasedAnimationsEnabled` is on:
  - `main` l.6362: stable, true;
  - 7625 l.8557: **preview, false**;
  - 7624 l.8340: unstable, false.

So for **shipping Safari 26.x and 27**, a `linear()`-eased WAAPI animation runs on the main thread, and the same
animation on WebKit `main` (Safari 28 candidate, INFERRED) runs threaded. The cost model must branch on this.

---

## 3. Deterministic quantities: what the engine decides, and the formula behind it

These are the "mathematics" of WebKit that matter for animation cost. Each is a pure function of DOM, style, geometry
and settings, so it is deterministic given a frame-stepped harness (§8).

| quantity | decision / formula in source | notes |
|---|---|---|
| **Is this element a composited layer, and why** | `RenderLayerCompositor::reasonsForCompositing` (l.3447); the 31-bit `CompositingReason` enum (`RenderLayerCompositor.h` l.64-96). <br>Key rules: <br>• Normal policy composites a transform only if it is **3D** (`requiresCompositingForTransform` l.3899-3928). <br>• Any `filter` (incl. `blur(0)`) or `backdrop-filter` composites (`requiresCompositingForFilters` l.4006-4020). <br>• `will-change` composites unless the policy is Conservative on non-Mac (l.4022-4043). <br>• A running accelerated animation composites (l.3863). <br>• Overlap: an animated transform with uncertain extent stops overlap testing (`animationCausesExtentUncertainty` l.148, 1426, 2654) | CONFIRMED. Under memory pressure or a memory warning the policy becomes **Conservative** (`updateCompositingPolicy` l.696-729): on iOS, will-change layers vanish (v1 webkit.md §4). Force it in WKTR with `internals.compositingPolicyOverride = "conservative"` (`Internals.idl` l.74-77, l.1031) |
| **Tiled or single backing store** | iOS: tiled when width or height × **page scale** > **1280** (1024 when `systemMemoryLevel() < 35`); macOS: > 2048 (`GraphicsLayerCA.cpp` l.101-107, `requiresTiledLayer` l.4968-4984) | CONFIRMED. The comparison uses CSS px × page scale, not device px |
| **Backing-store bytes (one buffer)** | `bytesPerPixel × w × h × contentsScale²` for a non-tiled layer with an attached backing store; retained tile memory for tiled layers (`backingStoreMemoryEstimate` l.5418-5434) | CONFIRMED. This is the Inspector `LayerTree.memory`. Real IOSurface usage is about 2-3× (front, back, secondary buffers: INFERRED by v1 safari-render-signals §2.2). Worked example (derived): a full-viewport 430×932 CSS layer at DPR 3 is 1290×2796 px = 3.6 Mpx → **14.4 MB** per buffer |
| **Tile coverage** | tile size 512 (`TileController.h` `kDefaultTileSize`). iOS: visible rect extended by 512/contentsScale CSS px **in the scroll-velocity direction**; visible rect only under memory pressure (`TileController.mm` l.501-545). macOS: desktop page-scrolling coverage (l.446-499, chosen at l.562-583) | CONFIRMED. So tiles painted during a scroll depend on velocity on iOS: the harness must fix velocity per step (§8) |
| **Repaint on a layer resize** | a non-tiled layer whose size, scale, opaque flag or format changes discards its store and repaints **fully**; tiled layers revalidate tiles; layers ≤ 64×64 always repaint fully | CONFIRMED (v1 claims-audit P1: `RemoteLayerBackingStore.mm` l.139-152, `PlatformCALayerRemote.mm`) |
| **Repaint on a sub-pixel offset change** | a device-pixel-rounded offset change of a layer from its renderer → `setContentsNeedDisplay` (1/6 CSS px buckets at DPR 3) | CONFIRMED (v1 claims-audit P4, `RenderLayerBacking.cpp`) |
| **Layout on a presence flip** | `transform` none↔some, opacity 1↔<1, `filter` none↔some → `StyleDifference::Layout`, dirtying up to the first layout boundary | CONFIRMED on 26.6 (v1 claims-audit W1, `StyleDifference.cpp` `miscDataChangeRequiresLayout`). Blink does not do this |
| **Layout boundary** | `isLayoutBoundary`: `contain: layout size`, or overflow clip + fixed size + new formatting context, … A second disjoint dirty subtree turns into a full layout | CONFIRMED (v1 claims-audit W2, `RenderObject.cpp`, `LocalFrameViewLayoutContext.cpp`) |
| **Backdrop budget cliff** | each commit sums backdrop rect areas. Once the running total exceeds `1242×2208×10`, further backdrop layers are **dropped** (`cMaxTotalBackdropFilterArea` l.113, `updateBackdropFilters` l.2769-2790) | CONFIRMED in source. Visual, not perf: a variant with many glass layers can silently lose blur |
| **Max layer-tree depth** | 128 (`cMaxLayerTreeDepth` l.110) | CONFIRMED |
| **Synchronous scrolling** | `SynchronousScrollingReason`: ForcedOnMainThread, viewport-constrained objects without fixed layers, slow-repaint objects, … (`ScrollingCoordinatorTypes.h` l.37-46) | CONFIRMED enum. Mainly a macOS concern: on iOS the UI process scrolls a `UIScrollView` (INFERRED) |
| **rAF rate** | `preferredFramesPerSecond(reasons, nominal, prefer60)` (`AnimationFrameRate.cpp` l.47-65) | CONFIRMED. A pure function, a Lean target |

What source **cannot** give: milliseconds. "The source says which stage runs, not how long it takes"
(v1:`research/tooling-landscape/README.md` §5). Hence the coefficients in §7.

---

## 4. Interfaces: who exposes which count

### 4.1 Matrix

| count | WKTR `internals` (local build) | Web Inspector protocol: Simulator / iPhone (iwdp) | macOS Safari | stock-Safari JS |
|---|---|---|---|---|
| rendering updates | `renderingUpdateCount` | `RenderingFrame` records | manual Timeline | rAF count |
| style recalcs | `styleRecalcCount`, **`lastStyleUpdateSize`** (elements), `styleInvalidationTraversalCount` | `RecalculateStyles` records: count and duration only. Element count is **not** in the record: `TimelineRecordFactory.cpp` has no data factory for it | manual | none |
| layouts | `layoutUpdateCount`; `lastInlineLayoutInfo` | `Layout` records with a root quad; Safari 27 adds the layout root node | manual | none |
| repaint rects / area | `startTrackingRepaints` + `repaintRectsAsText`; `layerTreeAsText(doc, LAYER_TREE_INCLUDES_REPAINT_RECTS)` per layer | `Paint` records with `data.clip` (`TimelineRecordFactory.cpp` l.166-170); `LayerTree.paintCount` deltas | manual (paint flashing) | none |
| layers and backing bytes | `layerTreeAsText` with flags 2 (tile caches) and 128 (backing store attached), plus 4096 / 2048 | `LayerTree.layersForNode`: `memory`, `bounds`, `compositedBounds`, `paintCount` | manual Layers tab | none |
| compositing reasons | not printed by `layerTreeAsText` (INFERRED from the flag list) | `LayerTree.reasonsForCompositingLayer` (29 flags, incl. `backdropRoot`, `willChange`, `overlap`) | manual | none |
| compositing updates / layer flushes | `compositingUpdateCount`, `layerFlushCount` | "Other" segment (residual) / `Composite` records | - | none |
| accelerated / threaded? | **`acceleratedAnimationsForElement` → {property, speed, isThreaded, hasHighImpact}** (`Internals.idl` l.333-338, l.602; `Internals.cpp` l.1573) | indirect: the layer has reason `animation` **and** no per-frame `RecalculateStyles` from it. The `Animation` domain has no acceleration field (`Animation.json`) | indirect | `getAnimations()` lists animations, not acceleration |
| scrolling | `synchronousScrollingReasons`, `nonFastScrollableRects`, `scrollingStateTreeAsText` | - | - | - |
| rAF throttling | `requestAnimationFrameInterval`, `requestAnimationFrameThrottlingReasons`, `setLowPowerModeEnabled`, `setAggressiveThermalMitigationEnabled` | - | - | rAF dt |
| listeners | `wheelEventHandlerCount`, `touchEventHandlerCount` | `DOMDebugger` / `DOM.getEventListeners` (INFERRED name) | - | patched `addEventListener` |
| memory | `memoryInfo` | `Memory.startTracking`: a `layers` category every 500 ms (WebContent only; under-counts GPU-process buffers, INFERRED by v1) | - | - |

All `internals` rows: CONFIRMED in `Internals.idl` (`main` l.587-1031; same functions present in 7625 at l.585-985).
Protocol rows: CONFIRMED in `Source/JavaScriptCore/inspector/protocol/{LayerTree,Timeline,Animation}.json`.

### 4.2 WKTR and `window.internals`

- **What it is.** WebKit's layout-test runner. It injects `internals` and `testRunner` into every page. The tests under
  `LayoutTests/compositing/` and `LayoutTests/fast/repaint/` are exactly "layer tree / repaint rects as text"
  expectations.
- **Runs on the iOS Simulator** with the iOS code paths: `run-webkit-tests --ios-simulator`. `LayoutTests/fast/scrolling/ios/ui-side-compositing-check.html` asserts
  `internals.isUsingUISideCompositing()` there (CONFIRMED). On macOS, WKTR can run with or without the RemoteLayerTree
  drawing area (`Tools/WebKitTestRunner/mac/main.mm`, `PlatformWebViewMac.mm`).
- **Per-test options** go in a header comment (`<!-- webkit-test-runner [ ... ] -->`), including `deviceScaleFactor`,
  `viewWidth`, `viewHeight` and `useFlexibleViewport` (`Tools/WebKitTestRunner/TestOptions.cpp` l.212, 234-236:
  CONFIRMED). Preference keys can be set the same way, for example `ThreadedTimeBasedAnimationsEnabled=false`.
  The preference syntax is INFERRED from common LayoutTests usage; check it on the first build. This is how a `main`
  build can **emulate shipping Safari 27 defaults**.
- **Not available** in Safari, Safari Technology Preview, the Simulator's Mobile Safari, or Playwright's WebKit.
  Playwright exposes only its own protocol: INFERRED, since the Playwright webview notes list "upstream protocol only".
- **Gap vs Safari.** No Safari UI: no dynamic toolbar, no Safari-specific preference overrides, and a different default
  viewport (800×600) unless set. A WKTR count is an **engine** count. Toolbar-driven effects (v1 lesson 9) need Mobile Safari.

### 4.3 Web Inspector protocol over `ios_webkit_debug_proxy` (no WebKit build)

v1 built and used this stack: v1:`tools/lib/wip.mjs`, `tools/sim.mjs`; the simulator socket recipe is in
v1:`research/simulator/README.md` §3.2, §7. What v2 must keep:
- Send **`Page.enable` on the page target before `Timeline.start`**, or every timestamp is 0 (CONFIRMED by source,
  `InspectorPageAgent::enable` starts the stopwatch; v1 safari-inspector-probing §0.1; P16 OBSERVED working).
- `maxCallStackDepth: 1` keeps overhead low. **Never** use the `Screenshot` instrument, live `layersForNode`,
  `ShowRepaintCounter` or paint flashing in timed runs: they change what they measure (v1 safari-render-signals §2.5).
- `performance.mark()` comes back as a Timeline `TimeStamp` record on the same clock. Use it to join harness steps to
  records.
- `LayerTree.layersForNode(<document>)` at **held** states gives layer count, Σ `memory`, and `paintCount` per layer.
  ΔpaintCount between two states is repaints per layer, with no Timeline needed.
- **New: Playwright webview backend.** `packages/playwright-core/src/server/webkit/webview/` targets "unmodified Safari
  on real iOS/iPadOS or the iOS Simulator over the standard Web Inspector Protocol". The test fixture connects with
  `playwright.webkit.connectOverCDP(<iwdp endpoint>)`. `utils/run_webview_tests.sh` starts iwdp on
  `null:9221,:9222-9322`.
  - Status: CONFIRMED in source, first landed as "chore: wk_webview experiment (#41010)" on 2026-05-26 and included
    from v1.61.0 on.
  - **Not in the release notes, so it is experimental and undocumented.**
  - It would replace v1's hand-rolled `wip.mjs` for navigation, input and evaluation. Raw `Timeline` / `LayerTree`
    access through it is INFERRED: check whether its session can send arbitrary methods, or keep a thin raw WIP client
    next to it.
- **macOS Safari has no equivalent socket path.** iwdp handles iOS devices and the Simulator socket only. Whether
  macOS Safari's `webinspectord` can be scripted the same way is UNRESOLVED; I found no public interface.

### 4.4 macOS Safari and Safari Technology Preview

- `safaridriver` on this host has `--bidi` (WebDriver BiDi) and `--mcp` (Safari MCP, stdio) (CONFIRMED,
  `safaridriver --help`).
  - Safari MCP gives DOM, network, screenshots, console, JS evaluation and navigation timing.
  - It does **not** give timeline or layer tools (https://webkit.org/blog/18325/webkit-features-for-safari-27-0/;
    v1 safari-inspector-probing §0.5).
  - So scripted macOS Safari gives JS-observable signals only: rAF dt, Event Timing, LCP, MutationObserver, and
    `getAnimations()`.
- **Manual Web Inspector** gives Timelines (Rendering Frames) and the Layers tab, and exports recordings with ⌘S. A
  parser for exported recordings lets a human session feed the same pipeline. Use it as an occasional ground truth,
  not as the loop.
- **Feature Flags** (Develop menu) toggle `Threaded Time-based Animations` and `Prefer Page Rendering Updates near 60fps`.
  This allows a two-arm check of the version axis in §2.3 on real Safari. INFERRED: the flags are listed by
  `humanReadableName` in the YAML. Check that they appear in Safari 27's UI.

### 4.5 Playwright's own WebKit build is not Safari

- It is a patched WebKit build (Mac port on macOS, GTK/WPE on Linux). It is "not Safari, not iOS"
  (https://playwright.dev/docs/browsers; v1:`research/tooling-landscape/README.md` §2.3).
- Linux WebKit uses a different compositor (TextureMapper / coordinated graphics, not Core Animation; INFERRED from
  port structure), so its layer and paint counts **must not** be pooled with Cocoa ones.
- Use it for functional and visual regression only.

### 4.6 Instruments, `xctrace` and WebKit trace points

- Only Instruments (Animation Hitches, Metal System Trace, System Trace) sees render-server and GPU time (CONFIRMED by
  Apple docs; v1 safari-inspector-probing §3). On the device it needs Developer Mode.
- WebKit emits kdebug trace points in every process (`SystemTracing.h` l.81-201; `kdebug_trace` at l.225). Examples:
  `RenderingUpdateStart`, `CompositingUpdateStart`, `PaintLayerStart`, `ComputeEventRegionsStart`,
  `DisplayListReplayStart`, `BackingStoreFlushStart`, `CommitLayerTreeStart`, `DisplayLinkUpdate`,
  `RenderServerSnapshotStart`.
  - The name map is `Source/WebKit/Resources/Signposts/SystemTracePoints.plist`, mirrored at
    `Tools/Tracing/SystemTracePoints.plist`.
  - Whether Instruments decodes them by name for stock Safari is UNRESOLVED (a v1 open item, P9). On **macOS Safari**
    it can be tried locally with no device: `xctrace record --template 'System Trace' --attach Safari`. This is a cheap
    first spike.

---

## 5. Building WebKit locally: cost and feasibility on this Mac

| item | value | status |
|---|---|---|
| Host | MacBook Pro 18,3, M1 Pro, **16 GB RAM**, macOS 27.0.1, Xcode 27.1, **69 GB free** on `/` | CONFIRMED (`sysctl`, `sw_vers`, `df`, 2026-10-17) |
| Build commands | `Tools/Scripts/build-webkit --release` (macOS) or `--ios-simulator`; needs Xcode, the CLT and `xcodebuild -downloadComponent MetalToolchain` | CONFIRMED (WebKit `ReadMe.md`) |
| Prebuilt archives | https://webkit.org/build-archives/ lists **macOS-only release** zips per revision; nothing for WKTR or the iOS Simulator | CONFIRMED (page read 2026-10-17) |
| Peak RAM | 32 GB peak reported on a 20-core Mac Studio (bug 227128); parallelism can be capped | CONFIRMED that the bug report exists; the effect on 16 GB is INFERRED: cap jobs at about 4-6 and expect swapping |
| Time and disk | not documented. Estimate for one configuration (release, iOS Simulator, WebKit + WKTR): **2-5 h** first build on this M1 Pro at reduced parallelism, **40-60 GB** of build products plus a **3-8 GB** sparse or shallow checkout | INFERRED; measure in a spike |
| Version choice | Safari tags such as `WebKit-7625.1.29.x` may not build with the newer SDK. `main` builds with current Xcode but differs from shipping Safari (§2.3). Suggest building `main` and pinning the shipping defaults through test-header preferences | INFERRED |

**Recommendation (INFERRED).**
- **Phase A:** use only the stock Simulator plus iwdp/Playwright-webview and the Inspector protocol. No build is needed,
  and it covers layers, memory, paintCount, reasons, Paint area and Layout and style record counts.
- **Phase B:** do a time-boxed WKTR spike (one day) on this Mac or a rented, larger cloud Mac. Do it only when Phase A
  lacks a count v2 needs: restyled-element count, `isThreaded`, compositing update count, forced Conservative policy.
- Before the spike, free disk to **≥ 120 GB**, or build on an external SSD.

---

## 6. iPhone vs iOS Simulator vs macOS Safari vs WKTR

| factor | iPhone 15 Pro Max (Safari 26.6.x/27) | iOS Simulator Mobile Safari | macOS Safari 27 | WKTR (iOS Simulator) | status |
|---|---|---|---|---|---|
| WebKit code paths | IOS_FAMILY | IOS_FAMILY; a simulator build lacks some IOSurface features (`HAVE_IOSURFACE_ACCELERATOR` etc.) | MAC | IOS_FAMILY (sim) | CONFIRMED (v1 simulator D5) |
| Compositing (UI-side, GPU-process paint) | yes | yes | yes, since remote layer tree became the macOS default | yes | CONFIRMED (§2.1) |
| Tiling threshold | 1280 (1024 at low memory level) | 1280; the memory level comes from the host (INFERRED, v1 D11) | **2048** | 1280 | CONFIRMED |
| Tile coverage | velocity-based | velocity-based | desktop | velocity-based | CONFIRMED |
| will-change under pressure | dropped (Conservative) | rarely (host memory) | **kept** (`!PLATFORM(MAC)` guard) | forceable via `compositingPolicyOverride` | CONFIRMED |
| Touch event regions | `ENABLE_TOUCH_EVENT_REGIONS` iOS on `main` and 7625; **off through 7624** | same as the phone's version | none | same | CONFIRMED (`PlatformEnableCocoa.h` `main` l.946-948, 7625 l.916-918; v1 claims-audit W5) |
| DPR / viewport | 3, 430×~775 visible with the toolbar | 3, 430×775 (v1 OBSERVED) | 2 (Retina); responsive mode can emulate | settable (`deviceScaleFactor`, `viewWidth`/`viewHeight`) | CONFIRMED / INFERRED (macOS emulation) |
| Dynamic toolbar resizes | yes, finger scrolls | yes, if a touch gesture is injected | no | no | v1 OBSERVED |
| Page rendering rate | 60 Hz (30 in LPM); 80 Hz runs seen in finger scrolls (v1 F-071, WEAKENED "60 Hz") | 60 Hz OBSERVED; host panel 120 Hz | 60 Hz (prefer-60 pref) | 60 Hz nominal | CONFIRMED / OBSERVED |
| CA animation rate | 80-120 Hz (ProMotion; INFERRED lower in LPM) | host-dependent | 80-120 Hz on ProMotion Macs (INFERRED) | n/a | CONFIRMED request (source); delivered rate UNRESOLVED |
| CPU speed | A17 Pro | about **1.4x slower** in style, layout and DOM; faster in pure JS (v1 FP-1) | M1 Pro native | slower (test harness) | OBSERVED (v1) |
| GPU / render server | A17 Pro tile-based GPU | host GPU through the Simulator; "rendering performance … has no relation to" the device (Apple archived guide) | WindowServer, M1 Pro GPU | host | CONFIRMED |
| Thermal | throttles after ~10 min of scrolling; timer realignment when hot | host thermal | host thermal | host | OBSERVED (v1 P15) |
| JIT | entitlement-gated | on | on | on | CONFIRMED (v1 D6) |

**Implication (INFERRED).** For **counts**, the Simulator and WKTR-on-Simulator agree with the phone *by construction* on
the same WebKit family. The exceptions are memory level, toolbar and touch. macOS needs **platform terms**: the 2048
tiling threshold, desktop coverage, DPR 2 → scale bytes by (3/2)² and recompute tiling. Prefer the Simulator. For
**time**, nothing off-device transfers; only coefficients calibrated on the phone do.

---

## 7. A WebKit cost model analogous to Chromium's

### 7.1 Per-frame terms (frame f, at scroll position y_f and animation time t_f)

Counts (from §4; "s" is the device scale, 3 on the phone):

| symbol | meaning | source of the count |
|---|---|---|
| `J_f` | script ms in rAF, observers and events: measured, not modelled | page-side `performance.now()` wrappers |
| `E_f` | elements restyled | `lastStyleUpdateSize` (WKTR); proxy: `RecalculateStyles` count × invalidation scope from Timeline |
| `Lr_f` | layout runs, plus the **size of the dirty subtree** (renderers under the layout root) | `layoutUpdateCount` + layout root (Safari 27 Timeline) + DOM count of the root's subtree |
| `Ap_f` | Σ repaint area in CSS px², per layer (no union: nested layers overlap) | `repaintRectsAsText` / Paint `clip` |
| `Np_f` | layers repainted | ΔpaintCount / Paint records |
| `N_f`, `ΔN_f` | composited layers, created or destroyed | `layerTreeAsText` / `layersForNode` |
| `Bn_f` | new or resized backing bytes = Σ 4·w·h·s² over (re)allocated non-tiled stores + new tiles·512²·4 | §3 formulas over `layersForNode` before and after |
| `R_f` | layers whose event region recomputes | `ComputeEventRegions` trace point (Instruments) or INFERRED from layer changes |
| `Nc_f` | layers in the commit (changed properties) | INFERRED from layer diff |
| `Ab_f`, `r_b` | backdrop area (device px²) and radius per backdrop layer | layer reasons `backdropRoot`/filters + computed style |
| `Ao_f` | offscreen-pass area: filter groups, masks, group opacity with composited children | layer tree + reasons |

Model (coefficients `c_*` fitted per device, OS and thermal class):
```
W_f  = J_f + c_sty·E_f + c_sty0·[E_f>0] + c_lay·Σ subtree(Lr_f) + c_lay0·#Lr_f
     + c_cu·N_f + c_new·ΔN_f + c_er·R_f + c_rec·Ap_f + c_lp·Np_f + c_txn·Nc_f          (WebContent main)
F_f  = max(0, s²·Ap_f / R_cg + Bn_f / R_alloc − overlap)                                 (GPU-process raster wait)
U_f  = c_ui·Nc_f + c_ui0                                                                  (UI-process apply)
dt_f ≈ max(T_req, W_f + F_f + U_f + δ_f)   where T_req = 16.67 ms (60 Hz) or 33.3 ms (LPM)
RS_g = c_rs0·N_vis + Σ_o Ao_g·s²/R_fill + Σ_b k_b·Ab_g·h(r_b)   per **displayed** frame g, budget V_g = 8.33 ms at 120 Hz
```

What each piece means:
- `dt_f` is the predicted rAF interval. `δ_f` is wake and tick-alignment slack. It is not quantised: v1 found no vsync
  grid above one frame (claims-audit §2.3).
- `RS_g` is off the rAF path (§2.2). It predicts **render hitches**, not rAF gaps.
- `h(r)` is a radius term to fit: CA blurs through a downsampled pyramid, so it is likely sub-linear (INFERRED from v1
  apple-math §2.11, unverified). v1's P1b probe is the test.
- **Accelerated animations** add nothing to `W` while running. They add one compositing update plus commit at start and
  at end, and v1 observed that start/end cost on the phone (gpu-lessons C7). They add to `RS` at the CA rate (80-120 Hz).
- **Threaded scroll-driven** animations (26.4+) add `RS` and UI-process work. WebKit still restyles active targets
  (v1 seed number: about 0.72 ms per frame, ESTIMATE in v1 apple-math, cited in kickoff note 01 §A.4).

### 7.2 v1 seed values (ESTIMATES from v1, to be refitted)

Seeds, A17 Pro, from v1:`research/design-engineering/safari-render-signals.md` §1.2-1.3, apple-math, and kickoff
note 01 §A.4:
- `c_lp` ≈ 0.14 ms per repainted layer (derived from phone data);
- `R_cg` ≈ 0.6-0.9 Gpx/s, allocation included;
- a 60 Hz budget of ~8-12 ms variable main-thread work, ~120-300 restyled elements, ~1.5 Mpx painted, ~10 MB new backing.

These are priors for the fit, not truths. One v1 model over-predicted a gain 4-5x (30-45 ms predicted, 6-9 measured:
v1 measurement-protocol-v2 L1).

### 7.3 Analogy with Chromium (for the sibling Chromium note)

| Chromium (cc / Blink) | WebKit equivalent | difference that matters |
|---|---|---|
| BeginMainFrame: style, layout, prepaint, paint (record) | `updateRendering`, then flush and display-list record | WebKit's "Composite" in the Inspector = commit + record + raster wait |
| commit to the cc impl thread | `CommitLayerTree` to the UI process | iOS: one pending commit; WebContent waits for the backing-store swap |
| raster (GPU or OOP-R tiles) | GPU-process display-list replay into IOSurfaces (CPU raster) | WebKit discards a whole non-tiled store on resize |
| viz display compositor | Core Animation render server | not visible to rAF, Web Inspector or JS |
| compositor animations (cc) | CA animations (legacy) or `RemoteAnimationStack` (threaded) | `steps()`/`linear()` exclusion on WebKit's CA path; presence-flip layouts are WebKit-only |
| 120 Hz BeginFrame on ProMotion Macs (v1) | 60 Hz page rendering, 80-120 Hz CA | rAF counts don't compare across engines |

---

## 8. Making the counts deterministic: the frame-stepped harness (requirements for the React rewrite)

v1's class-4 miss was timing, not mechanism: the Simulator's slower scroll moved one Layout past a ±60 ms window edge
(v1 simulator §5.3). The fix is to index by **position and animation time**, not wall clock.

Harness contract (INFERRED design):
1. **Step schedule.** A list of `(y_k, t_k)` pairs, for example y in 4 px steps at a fixed velocity profile and
   t_k = k·16.667 ms.
2. **Per step:**
   - `scrollTo({top: y_k, behavior: 'instant'})`;
   - set every time-based animation to `t_k`: `document.getAnimations()`, pause, set `currentTime`;
   - advance the app's **MotionClock** to `t_k`;
   - wait for exactly one rendering update (two rAFs; in WKTR, `UIHelper.renderingUpdate()`);
   - read counter deltas (internals or Timeline records between `performance.mark('s'+k)` markers).
3. **Velocity.** iOS tile coverage depends on scroll velocity (§3). Real scrolling in the UI process sets velocity, and
   `scrollTo` may not. Record tile counts separately from a real gesture run, or treat tiles as a calibration-only term.
4. **Held-state censuses** (`layersForNode`) only at chosen steps, never inside a timed window.
5. **Determinism test.** Run the same build twice and require byte-identical count vectors. Any drift marks a
   non-deterministic count, to be quarantined. Lean can state this as a property: the harness is a function.

What this asks of the React + MUI rewrite (INFERRED, for the architecture note):
- Every JS-driven motion goes through one injectable **MotionClock** and one scroll source, so it can be stepped. No
  free-running `requestAnimationFrame` or `setInterval` in components.
- Every part has a feature flag (`part.variant`), so a run is `(flags, schedule) → count vectors`. This maps directly
  onto v1's ablation lessons; the flag names are in kickoff note 01 §A.1.
- No layout reads in scroll callbacks: v1's principles 1-4 (v1:`research/architecture/apple-smooth-scroll.md` §3).

---

## 9. Validation and calibration plan: the iPhone only for periodic calibration

**Tier 0: every experiment, no device.**
- Simulator Mobile Safari (or WKTR) with the frame-stepped harness gives count vectors per flag variant.
- The model then gives predicted `W`, `dt` and an `RS` proxy.
- Decisions allowed: "variant X removes layouts or repaints or layers" (mechanism), and a ranking of candidates.
- **No ms claims.**

**Tier 1: nightly or on demand, host-only.**
- Simulator Timeline attribution runs with real timestamps (`Page.enable`). They check that counts and segments line up.
- Optional macOS Safari System Trace spike for WebKit trace points (§4.6).

**Tier 2: calibration on the iPhone, a scheduled block.** Triggers:
- a Safari or iOS version change;
- 14 days elapsed;
- two consecutive experiments whose phone spot-check residual exceeds the band below.

Calibration micro-suite. Each page isolates one term at 3-5 sizes. Ours to write; nothing exists:

| page | varies | term fitted |
|---|---|---|
| K1 restyle | toggle a class on N ∈ {50, 200, 800, 2000} leaf elements per frame | `c_sty`, `c_sty0` |
| K2 layout | resize a box with N descendants, with and without `contain: layout size` | `c_lay`, `c_lay0` |
| K3 paint | repaint area A ∈ {0.1, 0.5, 1.5, 4} Mpx (solid, gradient, text, image) | `c_rec`, `R_cg` |
| K4 layer churn | create or destroy M layers of size S per frame | `c_new`, `R_alloc` |
| K5 store resize | animate the width of a non-tiled composited layer | resize → full repaint |
| K6 many layers | static N layers, one property change | `c_cu`, `c_txn`, `c_ui` |
| K7 backdrop | a fixed `backdrop-filter` of area A_b and radius r over scrolling content | `k_b`, `h(r)` (**Instruments**) |
| K8 CA animations | M infinite transform animations | `c_rs0`, delivered CA rate (**Instruments**, rAF histogram) |
| K9 presence flip | opacity 1↔0.99, transform none↔scale(1) | the flip-layout term |

Fit and holdout:
- **Fit:** non-negative least squares of per-frame Timeline segments (Layout, Paint, Composite, Other) on the count
  vectors, joined by `performance.mark`. A thermal class (nominal, fair, serious) is recorded per run, and run order is
  ABBA.
- **Holdout:** 3-5 real page scenarios from the rewrite, with flags.

Acceptance bands (pre-registered, INFERRED values to agree with the user):
- **Count transfer:** a phone count equals the Simulator count at the same step in ≥ 95 % of steps, per count type. A
  count that fails is "not transferable".
- **Ranking:** Spearman ρ ≥ 0.8 between predicted and measured per-variant cost on the holdout.
- **A/B sign:** for every phone A/B whose effect exceeds the phone's own noise (v1's A/A ceiling method), the predicted
  sign matches in ≥ 90 % of pairs.
- **Magnitude:** median |log(pred/meas)| ≤ 0.3. Otherwise the model ranks but does not size.
- **Validity table:** keep it per output, as v1's `stats-vs-finger.md` did, and retire any output that disagrees with the
  device twice.

**Always on the device** (no off-device substitute, v1 lessons):
- render-server and backdrop cost (Instruments);
- finger-only effects (toolbar resize, 80 Hz runs);
- first-interaction layer builds, which count-based predictions missed five times in v1 (kickoff note 01 §A.4);
- heat.

---

## 10. Where Lean 4 helps in this topic (INFERRED proposals)

1. **Frame-rate function.** Port `preferredFramesPerSecond` (`AnimationFrameRate.cpp` l.47-65) to Lean and prove:
   - the result is in {30, 60} when nominal = 60, prefer-60 is on and OutsideViewport is absent;
   - plain ThermalMitigation never changes it.

   The test oracle is WKTR's `requestAnimationFrameInterval` under `setLowPowerModeEnabled`.
2. **Acceleration eligibility per version.** Define `canBeAccelerated : Version → EffectDesc → Bool` from
   `KeyframeEffect.cpp` (`main` l.1966-2023, 7625, 7624), plus `canHaveAcceleratedRepresentation`. Prove the lemma
   "uses `linear()` with points ∧ legacy path → main thread". A lint can then cite a theorem, not a comment.
3. **Compositing-reason subset and tiling.** Model `requiresCompositingFor{Transform, Filters, WillChange, Animation}`
   and `requiresTiledLayer` and `backingStoreMemoryEstimate`. Prove:
   - byte monotonicity in w, h and s;
   - the iOS/Mac threshold split;
   - "Conservative ∧ iOS → no will-change layers".

   Overlap is excluded: it is too stateful and stays empirical.
4. **Cost-model algebra.** With non-negative coefficients, `W` is monotone in every count. So "the variant's count
   vector ≤ the baseline's component-wise" implies "predicted W ≤ baseline". This licenses Tier-0 screening without
   coefficients. A theorem worth having, since most v2 decisions are comparisons.
5. **Metric definitions.** dt > 50 ms counting, ±4 ms sensitivity bands, and pre-registered decision rules (v1
   simulator §4.3) written as Lean functions. The scorer is the proven function, with no re-implementations drifting.

Each Lean model must carry the WebKit tag it was read from. A version bump means re-reading the cited lines (§11).

---

## 11. Storing WebKit references in the new repo (INFERRED design)

```
refs/webkit/
  PINS.md                         # tag → commit → Safari/iOS version map (the §1 table)
  rules/<family>/*.yaml           # one rule per decision: {id, statement, file, lines, commit, status, lean_theorem?}
  excerpts/<family>/<path>.md     # short excerpts (≤ 40 lines) with attribution; WebKit is BSD/LGPL, so small excerpts are fine
  protocol/<family>/*.json        # copies of LayerTree/Timeline/Animation/Page protocol JSON (machine-readable, used by the client codegen)
refs/apple/                       # links and notes for Instruments, ProMotion, hitches docs
```

- A script re-reads each rule's `file:lines` at a new tag through `gh api` and flags changed hunks. This is how v1
  should have caught 7624 → 7625 drifts such as touch regions and steps/linear.
- For broader reading, use a **sparse, shallow** WebKit clone (`Source/WebCore/{page,rendering,animation,platform/graphics/ca,testing}`,
  `Source/WebKit/{UIProcess,WebProcess}/…/RemoteLayerTree`, `Source/JavaScriptCore/inspector/protocol`) searched with
  `rg`. Serena or clangd on WebKit C++ needs a compile database, which means a build, so prefer `gh api` plus `rg` until
  Phase B (INFERRED).

---

## 12. Risks

- **Off-device blindness for the render server.** It was the largest v1 blind spot: the nav backdrop and filter passes.
  Only Instruments on the phone covers it. The model's `RS` part is calibration-only.
- **Simulator runtime skew.** The host has only the iOS 26.5 runtime. If the phone is on iOS 26.6.x or 27, version-gated
  behaviour can differ; touch event regions and threaded flags are already known to differ across 7624/7625. Pin and
  record versions on every run.
- **Count transfer can still fail** through memory level (tiling at 1024), Conservative policy on the phone under memory
  pressure, velocity-dependent tiles, and toolbar resizes. The §9 count-transfer test catches these per count type.
- **A frame-stepped harness hides emergent dynamics:** back-pressure, catch-up frames, coalesced layouts from a second
  dirtier (v1 claims-audit W2). The device outer loop must still see them.
- **WKTR build cost on 16 GB / 69 GB.** It may be impractical locally; plan a cloud Mac or skip it.
- **The Playwright webview backend is experimental and undocumented.** It can break between releases; pin the version.
- **Coefficients drift with heat, battery and Low Power Mode.** Record the thermal state and LPM per run. LPM halves rAF.
- **Model overconfidence.** v1 had a 4-5x over-prediction and five same-direction misses on first-open layers. Keep the
  magnitude band, and say "ranks only" when it fails.

## 13. Open questions for the user

1. Which iOS and Safari version is the test iPhone on now (26.6.x or 27.x)? Should we download the matching Simulator
   runtime (several GB)?
2. May we spend a time-boxed day on a local WebKit build (WKTR on the iOS Simulator), and free ≥ 120 GB of disk for it?
   Or use a rented cloud Mac, or skip `internals` and stay with the Inspector protocol?
3. Is Developer Mode plus Xcode Instruments on the iPhone acceptable for the calibration blocks? It is the only way to
   price backdrop and filter passes.
4. Calibration cadence: on every Safari/iOS update plus every 14 days, or another schedule?
5. Are the acceptance bands in §9 acceptable: ≥ 95 % count transfer, ρ ≥ 0.8, ≥ 90 % sign agreement, and median
   |log ratio| ≤ 0.3?

## Sources

WebKit source (https://github.com/WebKit/WebKit, `main` @ 77db40e2fa70 unless noted):
- `Source/WebCore/page/Page.h` l.305-345; `Page.cpp` l.2313, 2380, 2476-2660, 2661, 2791-2862, 3019-3058, 566-571
- `Source/WebCore/rendering/RenderLayerCompositor.h` l.64-96; `RenderLayerCompositor.cpp` l.148, 696-729, 1282, 1426, 2654, 3293-3447, 3863-3928, 4006-4043
- `Source/WebCore/platform/graphics/ca/GraphicsLayerCA.cpp` l.101-117, 2769-2790, 4968-4984, 5418-5434
- `Source/WebCore/platform/graphics/ca/TileController.h` (`kDefaultTileSize` 512); `TileController.mm` l.446-583
- `Source/WebCore/animation/KeyframeEffect.cpp` l.1961-2056, 3283-3294 (7625: l.2002-2014)
- `Source/WebCore/platform/animation/AcceleratedEffect.cpp` l.111-150
- `Source/WebCore/platform/graphics/AnimationFrameRate.{h,cpp}` (h l.40-56; cpp l.33-95)
- `Source/WebCore/page/scrolling/ScrollingCoordinatorTypes.h` l.37-46
- `Source/WebCore/testing/Internals.idl` l.74-77, 333-338, 587-609, 834-878, 974-1031, 1588; `Internals.cpp` l.1573, 3935, 4598-4775
- `Source/WebCore/inspector/TimelineRecordFactory.cpp` l.46-187
- `Source/JavaScriptCore/inspector/protocol/{LayerTree,Timeline,Animation}.json`
- `Source/WebKit/UIProcess/RemoteLayerTree/ios/RemoteLayerTreeDrawingAreaProxyIOS.mm` l.48, 87-93, 266-337, 488-509
- `Source/WebKit/Platform/cocoa/CAFrameRateRangeUtilities.h`; `Source/WebKit/WebProcess/WebPage/RemoteLayerTree/PlatformCAAnimationRemote.mm` (7625 l.611)
- `Source/WebKit/UIProcess/mac/WebViewImpl.mm` l.1366-1383
- `Source/WTF/wtf/PlatformEnableCocoa.h` (`main` l.416-420, 851-853, 934-936, 946-948; 7625 l.400-404, 817-819, 904-906, 916-918; 7624 l.842-844)
- `Source/WTF/Scripts/Preferences/UnifiedWebPreferences.yaml` (`main` l.4914, 5250, 6336, 6362; 7625 l.6505, 6964, 8518, 8542, 8557; 7624 l.6392, 8316, 8340)
- `Source/WTF/wtf/SystemTracing.h` l.81-225, 341; `Tools/Tracing/SystemTracePoints.plist`
- `Tools/WebKitTestRunner/TestOptions.cpp` l.196-236; `Tools/WebKitTestRunner/mac/main.mm`; `LayoutTests/fast/scrolling/ios/ui-side-compositing-check.html`
- `ReadMe.md` ("Building WebKit")

Playwright (https://github.com/microsoft/playwright):
- `packages/playwright-core/src/server/webkit/webview/*`, `.claude/skills/playwright-dev/webview.md`
- `utils/run_webview_tests.sh`, `tests/webview/webviewTest.ts` l.162
- commit 25f22d2125 (2026-05-26); first included in release v1.61.0

Docs and bugs:
- https://webkit.org/blog/17862/webkit-features-for-safari-26-4/ ; https://webkit.org/blog/18325/webkit-features-for-safari-27-0/
- https://webkit.org/build-archives/ ; https://webkit.org/web-inspector/timelines-tab/ ; https://webkit.org/web-inspector/layers-tab/
- https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app
- https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays
- https://bugs.webkit.org/show_bug.cgi?id=227128 (build memory) ; https://bugs.webkit.org/show_bug.cgi?id=173434 (60 fps) ; https://bugs.webkit.org/show_bug.cgi?id=244988 (signposts / kdebug class)
- https://docs.webkit.org/Build%20&%20Debug/BuildOptions.html ; https://lists.webkit.org/pipermail/webkit-dev/2018-March/029919.html
- https://playwright.dev/docs/browsers

Old repo (v1, read only):
- `research/architecture/webkit.md`, `safari-inspector-probing.md`, `apple-smooth-scroll.md`, `apple-verify.md`, `claims-audit.md` (§1.1-1.2, §2.1, §2.3, §2.4, §2.7)
- `research/simulator/README.md` (§1-§7)
- `research/design-engineering/safari-render-signals.md` (§0-§3)
- `research/gpu-lessons/README.md`
- `research/tooling-landscape/README.md` §2.3, §5

New repo: `research/kickoff/01-prior-loop-lessons.md` §A.1, §A.3, §A.4.

Host facts (2026-10-17): `xcodebuild -version`, `xcrun simctl list runtimes`, Safari `Info.plist`, `safaridriver --help`,
`sysctl hw.memsize`, `df -h /`.

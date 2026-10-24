---
id: 2026-10-2x-webkit-throttles
kind: note
title: "WebKit iOS throttles and power heuristics beyond the toolbar scroll throttle, and which parts they hit"
status: review
created: 2026-10-24
topics: [lag, webkit, power, low-power-mode, engine.scroll, scroll-events, phone, end-of-page]
---

# WebKit iOS throttles and power heuristics beyond the toolbar scroll throttle

WebKit cites `@862f17d` unless a commit is named. The toolbar throttle and the phone numbers for
`?fw=engine.scroll:throttle-lift` and `?fw=engine.scroll:unthrottle` are in `10-2x-scroll-throttle-parts.md`; this note
does not repeat them. Per-part symptoms are INFERRED unless a row says MEASURED.

## Question

The user found that one invisible main-thread scroll-driven animation lifts the 100 ms visible-rect throttle
(`WKWebViewIOS.mm:3256-3268`) and made the hero exit and the end of the page smoother on the iPhone. Which other WebKit
throttles and power heuristics delay or skip work on iOS, which parts do they hit, and which parts can follow the
finding?

## Answer first

- **A second scroll throttle exists, and unthrottle does not lift it.** While the scroll is moving, WebKit delays the
  `scroll` event once its latency estimate passes 1/60 s (`WebPageIOS.mm:2240-2256`): the first position change starts
  a one-shot timer of min(2 x latency, 1 s), and later changes do not restart it. So `scroll` fires at most once per
  window (`LocalFrameView.cpp:3784-3790`). The estimate is an 0.8/0.2 moving average of the time from the oldest
  unflushed non-stable visible-rect update (`WebPageIOS.mm:3591-3595`) to the next layer-tree flush
  (`WebPageCocoa.mm:2384-2392`). CONFIRMED. `eventThrottlingDelay` checks no scroll timeline, so the 319523 exemption
  does not apply to it. CONFIRMED. `engine.scroll` requests its frames from `scroll` events (`engine/scroll.ts:94-101`),
  so every engine.scroll consumer inherits this delay. CONFIRMED. Whether the phone's estimate passes 1/60 s with lift
  on is not measured.
- **CI has never seen that throttle.** The test runner forces `EventThrottlingBehavior::Responsive`
  (`WebPageTesting.cpp:173-176`). WKTR can force it on with `internals.eventThrottlingBehaviorOverride` (`Internals.idl:967`).
  CONFIRMED.
- **Low Power Mode halves rAF and the rendering update to 30 fps and aligns maximally nested DOM timers (repeating
  ≥5, one-shot ≥10) to 30 ms** (`Document.cpp:4639-4655`; `DOMTimer.cpp:59-61,180,341-343`). No page opt-out exists.
  CONFIRMED (`AnimationFrameRate.cpp:33,72-85`, `Page.cpp:2809-2823`, bug 215745 closed INVALID). WKTR can force it
  with `internals.setLowPowerModeEnabled(true)` (`Internals.idl:960`, `Internals.cpp:2314-2325`). CONFIRMED.
- **Under Low Power Mode, three parts change their wall-time curve, because they chase per frame, not per ms:**
  commission (GAIN 0.22, `commission/logic.ts:6,51`), people.card (RATE 0.22, `people.card/logic.ts:8,49`) and
  people.deck (rate 0.2). Each settles about 2x slower at 30 fps. INFERRED from the code. A dt-based gain fixes it.
  On phones (people.card ≤860 px, commission ≤1000 px, or coarse pointer ≤1200 px) commission and people.card pin
  scale 1 and radius 0 (`people.card/card.module.css:127-131`; `commission/commission.module.css:436-440`; the `mq`
  variant skips the write, `people.card/driver.ts:51-61`; shrinking reads raw t, `people.card/logic.ts:106-110`), so
  their chase is invisible and Low Power Mode changes nothing visible there. The 2x slower settle shows only on wide
  viewports: Mac Safari in Low Power Mode, or an iPad wider than 1200 px. INFERRED.
- **Main-frame CSS, SMIL and rAF work is never throttled offscreen.** The OutsideViewport reason is set only for
  subframes (`LocalFrameView.cpp:3837-3862`), and the page has no iframes. CONFIRMED. Ungated offscreen animations
  (platform.sweep, platform.glint) keep the rendering update running every frame. INFERRED cost.
- **The 60 fps cap on 120 Hz, thermal, hidden-page and cross-origin throttles have no page lift.** Design around them.
  CONFIRMED (none documented, none in source).
- **The unthrottle lift rests on undocumented behaviour** (bug 319523, fix b07ce30ae0). A WebKit change could narrow it.
  INFERRED.

## Throttles table

| Heuristic | Trigger | Delay or skip | Lift | Page can lift? | Source | Status |
|---|---|---|---|---|---|---|
| Toolbar visible-rect throttle | Safari changes obscured insets interactively | Visible-rect update every 100 ms | Main-frame scroll timeline with a non-accelerated animation (bug 319523) | Yes: `engine.scroll:unthrottle` | `WKWebViewIOS.mm:3256-3268` | CONFIRMED |
| Latency scroll-event delay | Unstable scroll and latency estimate > 1/60 s | The first position change starts a one-shot timer of min(2 x latency, 1 s); later changes do not restart it, so `scroll` fires at most once per window; scrollY itself is current | Stable state or a fast main thread | Partly: read scrollY per rAF, keep commits cheap | `WebPageIOS.mm:2240-2256`; `WebPageCocoa.mm:2384-2392`; `LocalFrameView.cpp:3784-3790` | CONFIRMED |
| 60 fps cap on 120 Hz | Always on iOS (`PreferPageRenderingUpdatesNear60FPSEnabled`) | rAF, main-thread animations and scroll events at 60 Hz | Pref only | No | `RemoteLayerTreeDrawingAreaProxyIOS.mm:192-204,409-424`; `AnimationFrameRate.cpp:72-85` | CONFIRMED |
| Low Power Mode | System setting | Rendering and rAF 30 fps; maximally nested DOM timers (repeating ≥5, one-shot ≥10) aligned to 30 ms; preferred rendering fps forwarded to the drawing area; SMIL ticks every 1/30 s (also under aggressive thermal mitigation), which hits platform.glint | User turns it off | No | `AnimationFrameRate.cpp:33`; `Page.cpp:544-545,2809-2823`; `Document.cpp:4639-4655`; `DOMTimer.cpp:59-61,180,341-343`; `RemoteLayerTreeDrawingArea.mm:590-595`; `Source/WebCore/svg/animation/SMILTimeContainer.cpp:42-43,86-91` | CONFIRMED |
| Thermal mitigation | Thermal notifier | Timer alignment 0 to 30 ms; frame rate unchanged | Cooling | No | `Page.cpp:2825-2843,3068-3074` | CONFIRMED |
| Aggressive thermal mitigation | Thermal pressure and `RespondToThermalPressureAggressively` (default false) | 30 fps | Pref or cooling | No | `Page.cpp:548-549,2835-2840` | CONFIRMED |
| Hidden page | View not visible | Rendering at half speed (VisuallyIdle; on iOS visually idle means the view is not visible); rAF suspended; timers aligned to 1 s; CSS and SVG animations suspended | View visible | No | `Page.cpp:2798-2806,3018-3036`; `PageClientImplIOS.mm:238-241`; rAF suspension `Page.cpp:3488,3547`; webkit.org/blog/8970 | CONFIRMED |
| Subframe outside viewport | Iframe with empty visible rect | rAF every 10 s | Iframe in view | Yes (no iframes here) | `LocalFrameView.cpp:3837-3862` | CONFIRMED |
| Cross-origin frame | No gesture in that frame | rAF 30 fps | User gesture | No | `Document.cpp:9245-9246,9549-9556` | CONFIRMED |
| Timer nesting clamp | Repeating timers from nesting 5, one-shot from nesting 10 | Then a 4 ms floor and a 4 ms minimum alignment apply, plus the page alignment | Fresh tasks or rAF | Yes | `DOMTimer.cpp:416-430`; `DOMTimer.h:51`; `Document.cpp:4642-4652` | CONFIRMED |
| Non-observable 1 s timer throttle | Flagged repeating timer | 1 s minimum | n/a | n/a | `DOMTimer.cpp:86-98,284-293`; only `setScriptMadeUserObservableChanges` is called (`DOMTimer.cpp:302`) | CONFIRMED dead (`setScriptMadeNonUserObservableChanges` has no caller in WebCore) |
| Commit backpressure | One commit still in flight | Next update waits a whole vsync | Commit ends | Only by cheaper frames | `RemoteLayerTreeDrawingArea.mm:319-328,451-470` | CONFIRMED |
| Unstable-state geometry | Drag, deceleration, rubber band | Layout viewport set without layout; fixed and sticky layers approximate | Scroll at rest | No | `WKWebViewIOS.mm:2996-3025`; `WebPageIOS.mm:3729-3759` | CONFIRMED |
| Overflow-scroll pacing | UI-side overflow scrolling | Batches wait for the previous reply | Reply arrives | No | `RemoteScrollingCoordinatorProxy.cpp:282-347` | CONFIRMED |
| Observers and scroll events per update | Every rendering update | IntersectionObserver, ResizeObserver, `scroll`, `resize` once per update | n/a | No | `Page.cpp:2290-2296,2340,2366-2367` | CONFIRMED |
| Preventable touchmove gate | Non-passive touch listener under the finger | Native pan waits for the first touchmove answer | Answer arrives | Yes: passive listeners | `WKContentViewInteraction.mm:2290-2291,10568` | CONFIRMED (region INFERRED) |
| Async image decode | `decoding=async` or first paint offscreen | Image may paint blank for a frame | Decode ends | Yes | `RenderBoxModelObject.cpp:256-296` | CONFIRMED |
| Animated image pause | Offscreen, or image animation off | Animation stopped | Back in view | Per element | `RenderElement.cpp:1813-1851` | CONFIRMED |
| Tile coverage | Memory pressure, pinch, load not done | Coverage shrinks to the visible rect | Pressure ends, first scroll | No | `TileController.cpp:499-535` | CONFIRMED |
| Skipped content | `content-visibility` skips the subtree | Style animations not updated | Content relevant | Yes | `AnimationTimelinesController.cpp:150-151` | CONFIRMED |
| Tap hover hold | Tap with timers of 400 ms or less | One-shot timers held | Observation ends | No | `ContentChangeObserver.cpp:55,312` | CONFIRMED |

## Exposure per part

| Part | Machinery | Heuristic | Predicted symptom | file:line |
|---|---|---|---|---|
| every engine.scroll consumer (nav, people.card, commission, morph readers) | frames requested from `scroll` and `resize` events | Latency scroll-event delay | Frame requests late by 2 x latency (35-40 ms at an 18-20 ms estimate) while the main thread is busy | `engine/scroll.ts:94-101` |
| commission | per-frame chase, GAIN 0.22; `afterFrames(2)` | Low Power Mode | Wide viewports only: chase settles about 2x slower in ms; `afterFrames` waits 2x longer. ≤1000 px or coarse ≤1200 px pins scale 1, radius 0, so the chase is invisible | `commission/logic.ts:46-63`; `commission/driver.ts:68,137`; `commission/commission.module.css:436-440` |
| people.card | per-frame chase, RATE 0.22 | Low Power Mode | Wide viewports only: chase about 2x slower. ≤860 px or coarse ≤1200 px pins scale 1, radius 0 (the `mq` variant skips the write; shrinking reads raw t), so the chase is invisible on phones | `people.card/logic.ts:8,49,106-110`; `people.card/card.module.css:127-131`; `people.card/driver.ts:51-61` |
| people.deck | per-frame chase, rate 0.2; desktop only | 120 Hz Chromium, Low Power Mode | Chase 2x faster at 120 Hz, 2x slower at 30 fps | `people.deck/driver.ts:64` |
| hero.accent (faithful) | relative one-shot re-arms | Timer alignment 30 ms after 10 chained one-shot fires | JS state drifts against the CSS idle cycle | `hero.accent/driver.ts:37-70` |
| pain.notes (faithful) | free-running 3 s interval | Timer alignment 30 ms after 5 interval fires | Lateness carries over | `pain.notes/driver.ts:160-171` |
| platform.sweep | CSS `background-position` 4 s, main thread | No offscreen throttle | Rendering update and restyle every frame while offscreen | `platform/sweep.module.css:18-28` |
| platform.glint | SMIL x1 and x2, 5 s | No offscreen throttle; Low Power Mode SMIL tick 1/30 s | Same as sweep; under Low Power Mode the glint steps at 30 Hz | `platform/Visuals.tsx:269-292` |
| morph.mount | non-passive wheel and touchmove armed in a 200 % IO band | Preventable touchmove gate | First pan frames near the page end wait for a busy main thread | `morph.mount/index.tsx:78-126` |
| platform scene | `loading=lazy decoding=async` images, IO reveal | Async decode | Blank frame for an image revealed in the jump frame | `platform/Visuals.tsx:87,141,147` |
| hero.cue | CSS transform 2.2 s | Accelerated, runs in Core Animation | Little main-thread cost | `hero.cue/cue.module.css:37,71-78` |

## Candidates ranked

One variant per part. Brick names are `part:variant`.

| Rank | Brick | What to change | Kind | Same look | Lean proof | Measurement that decides |
|---|---|---|---|---|---|---|
| 1 | `engine.scroll:unthrottle-follow` | unthrottle plus a rAF loop that keeps requesting frames while scrollY moves, stopping after k still frames or `scrollend` | Robustness (position read per rendering update, not per event) | INFERRED same: outputs stay functions of scrollY, only fresher | Stop rule terminates; each frame's y is the latest scrollY at that update, never older than the event-driven y | CI WKTR with `eventThrottlingBehaviorOverride = 'unresponsive'`: still runs per 1000 moving frames, faithful vs unthrottle vs this. Phone: a recorder count of rAF frames where scrollY moved with no `scroll` event since the last frame |
| 2 | `commission:dt-chase` | gain per frame becomes 1 - (1 - 0.22)^(dt / 16.67 ms); matters only for desktop Low Power Mode (wide viewports), phones pin scale 1 and radius 0 | Robustness (time-based) | Same at 60 Hz; differs from faithful at 30 fps and at 120 Hz Chromium, so look-change class for the user's visual review | Step(a) after Step(b) equals Step(a + b) only for a fixed target and before the EPS snap and the `s.n < m ? m` jump (`commission/logic.ts:52-55`); Step(16.67) equals GAIN; EPS snap keeps the same end state | CI WKTR with `setLowPowerModeEnabled(true)` at a viewport wider than 1000 px: settle time in ms equals the 60 Hz run. Mac Safari Low Power Mode pass (user step) |
| 3 | `platform.sweep:offscreen-pause` | IO pauses the animation offscreen and seeks to the document timeline on resume (engine.scene pattern) | Less work | Same: phase on resume equals the uninterrupted phase | Seek phase equality, reused from the engine.scene and morph.columns proofs | CI Simulator: rendering updates and main-thread time while the platform scene is offscreen, both engines; breakpoint gate |
| 4 | `platform.glint:offscreen-pause` | `pauseAnimations()` offscreen, `setCurrentTime` from the document clock on resume | Less work | Same, by the same phase argument | as rank 3, for the SMIL clock | as rank 3 |
| 5 | `morph.mount:arm-late` | arm the non-passive listeners only in the band where the pin can call `preventDefault` | Less gating | Same if the band covers every pin position | The arm band contains every scroll position where the lock decision is true | Phone: touch-start to first scroll frame near the page end. CI cannot drive the touch gate (INFERRED) |
| 6 | `platform:predecode` | call `img.decode()` when the 100 % margin IO fires, before the reveal | Robustness | Same pixels; removes a possible blank frame | Reveal happens only after decode resolves or a deadline passes | CI Simulator: blank-image frames in the reveal window |

Existing variants that follow the Low Power Mode finding without a new brick: `hero.accent:steps` and `pain.notes:visible`
already aim at absolute time grids. They need only a WKTR run with `setLowPowerModeEnabled(true)` and a drift count.

## Not worth it

- Lifting Low Power Mode, thermal, the 60 fps cap, hidden-page or cross-origin throttles: no page lift. CONFIRMED.
- `hero.cue`: transform keyframes run in Core Animation, so the offscreen main-thread cost is small. INFERRED.
- `people.deck:dt-chase`: desktop only, not on the iPhone. Follow rank 2 if it passes.
- `people.card:dt-chase`: on phones (≤860 px, or coarse pointer ≤1200 px) the CSS pins scale 1 and radius 0, so the
  chase is invisible there; on wide viewports it follows rank 2 with the shared lemma if rank 2 passes. INFERRED.
- `content-visibility: auto` on far sections: it would stop style animations offscreen, but the placeholder size must
  match the real height exactly or scroll positions move. No cheap identity proof. INFERRED.
- Unstable-state geometry (fixed and sticky layers approximate during scroll): no page lift. CONFIRMED.
- The 1 s non-observable timer throttle: `setScriptMadeNonUserObservableChanges` has no caller in WebCore. CONFIRMED dead.
- Timer nesting clamp: our timers are 140 ms or longer, so the 4 ms floor never binds. INFERRED.

## Open questions

- Does the latency estimate pass 1/60 s on the phone with lift on? The rank-1 recorder count answers it. If it never
  does, rank 1 drops.
- Does WKTR on the iOS Simulator produce non-stable visible-rect updates under `UIScriptController` scrolls? The
  latency path needs them.
- Do Core Animation transform animations run at 120 Hz on a ProMotion iPhone? `ThreadedTimeBasedAnimationsAtHighFrameRate`
  defaults to false (`UnifiedWebPreferences.yaml:8542`). Not answered from source.
- Can Simulator Safari enter Low Power Mode? `simctl` has no switch that we know of (INFERRED), so WKTR is the CI route.
- A canary for the 319523 exemption at each WebKit pin bump: which test drives interactive inset changes? Candidate:
  `WKScrollViewTests.mm:1140-1446` in TestWebKitAPI.

## Sources

- WebKit `@862f17d`: `Source/WebKit/WebProcess/WebPage/ios/WebPageIOS.mm`, `WebPage/Cocoa/WebPageCocoa.mm`,
  `WebPage/WebPageTesting.cpp`, `UIProcess/API/ios/WKWebViewIOS.mm`, `UIProcess/ios/WKContentViewInteraction.mm`,
  `UIProcess/ios/PageClientImplIOS.mm`, `Source/WebCore/svg/animation/SMILTimeContainer.cpp`, `DOMTimer.h`,
  `RemoteLayerTreeDrawingArea.mm`, `RemoteLayerTreeDrawingAreaProxyIOS.mm`, `RemoteScrollingCoordinatorProxy.cpp`,
  `Source/WebCore/page/Page.cpp`, `LocalFrameView.cpp`, `DOMTimer.cpp`, `Document.cpp`,
  `platform/graphics/AnimationFrameRate.cpp`, `testing/Internals.idl`, `testing/Internals.cpp`, `TileController.cpp`,
  `RenderBoxModelObject.cpp`, `RenderElement.cpp`, `AnimationTimelinesController.cpp`, `ContentChangeObserver.cpp`.
- WebKit bugs 307463, 319523, 315320, 284586, 215745, 168837, 173434, 169213, 170534; commits 9583464b46, c8dd7e94f8,
  d844fca303, 886bdac053, 984773adbe, b07ce30ae0.
- webkit.org/blog/8970 (hidden pages), webkit.org/blog/17862 (Safari 26.4 threaded scroll-driven animations).
- Site: `apps/site/src/engine/scroll.ts`, `apps/site/src/parts/*/part.json`, paths in the exposure table.
- Toolbar throttle and phone data: `research/notes/2026/10-2x-scroll-throttle-parts.md`.

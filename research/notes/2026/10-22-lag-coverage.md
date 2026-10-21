---
id: 2026-10-22-lag-coverage
kind: note
title: "Which kinds of lag our measurements see, which they miss, and the lag definitions we adopt"
status: review
created: 2026-10-22
authors: [agent:researcher, agent:checker]
topics: [lag, measurement, webkit, chromium, phone, hitch, scroll-jank, raf, event-timing, felt-marks, promotion, thermal]
---

# Lag coverage: kinds, blind spots, definitions

Citations: repo paths at 16b8aac (the cited files are unchanged since 82e24c9f). WebKit at 862f17dcae0a (iOS 27.0
Simulator build; the phone runs 27.0.1): `WC/` = Source/WebCore, `WK/` = Source/WebKit, `WTF/` = Source/WTF, `Prefs` =
`WTF/Scripts/Preferences/UnifiedWebPreferences.yaml`. Chromium at f842f52ef39f. Phone figures are limited to the counts
in `results/phone/2026-10-21/summary.md` and `summary.json`. Other phone numbers are named by their source without the value.

## Answer

- **Our lag measurements see one thing: rAF callback times on the web-process main thread.** None reads presentation
  time, the UI process or the render server (CONFIRMED, harness table below). Of the 16 lag kinds below, rAF sees 4
  fully, 5 partly and 7 not at all.
- **Safari renders the page at 60 Hz on our 120 Hz phone.** `PreferPageRenderingUpdatesNear60FPSEnabled` defaults to
  true except on visionOS (`Prefs:6505-6520`), and 120 Hz maps to 60 fps (`WC/platform/graphics/AnimationFrameRate.cpp:35-45, 47-65`).
  CONFIRMED. The phone is an iPhone 15 Pro Max (`packages/measure-webkit/src/device.mjs:22`@16b8aac) with ProMotion up to
  120 Hz ([Apple tech specs](https://support.apple.com/en-us/111828), CONFIRMED). The look arm's first pass had 5,161
  frames in a 90 s pass, about 57 fps (MEASURED, summary.md frames; 90 s from summary.json `plan`).
- **One missed 60 Hz update is never counted.** It gives a 33.3 ms interval, and the slow line is > 34 ms
  (`lean/Fw/Device/Session.lean:13, 92`@16b8aac). Two missed updates (50 ms) are counted by `over34`, and only sometimes
  by `over50` (strict >, 1 ms rounding in `WC/page/Performance.cpp:73`). CONFIRMED.
- **"No frame over 50 ms near felt marks" says little about the lag.** The felt window ends at the third tap, counts
  only moving frames, and the first tap stops the fling. Many marks in every arm had zero counted frames (MEASURED,
  `results/phone/2026-10-21/summary.json`). INFERRED: the finding describes the window, not the lag.
- **We adopt three definitions:** Apple's hitch time ratio with its bands, Chromium's 1.5-interval missed-frame rule,
  and a skipped-slot count as the primary miss count, with a > 25 ms count beside it.
- **The phone needs two tools rAF cannot replace.** Instruments Animation Hitches (`xctrace`) sees commit and render
  hitches, and video sees trailing content, blank tiles and pop-in (INFERRED: no other counter compares them).

## Lag taxonomy

rAF = can a main-thread rAF interval recorder see it. CI = GitHub Actions lanes. Mac = Safari on this Mac.

| # | Kind | Mechanism (cite) | rAF | CI | Mac | Phone | Status |
|---|---|---|---|---|---|---|---|
| L1 | Long main-thread frame | The rendering update (rAF, style, layout, paint recording) runs past the next refresh; the next update waits for `DisplayDidRefresh` (`WK/WebProcess/WebPage/RemoteLayerTree/RemoteLayerTreeDrawingArea.mm:319-329, 451-470`) | yes | Chromium cadence lane; Simulator Timeline counts | rAF recorder in Safari | device recorder | CONFIRMED |
| L2 | One missed 60 Hz update, uneven cadence | 60 Hz page rate (row above the table); one miss = 33.3 ms, under the 34 ms line. The raw phone records also hold long-then-short pairs, a late update followed by a short one (MEASURED by the check on uncommitted raw records); cause, a deferred update fired from `DisplayDidRefresh` or a timer (`RemoteLayerTreeDrawingArea.mm:461-470`), INFERRED | yes, but our thresholds drop it | cadence lane with the slot rule | same | recorder with the slot rule | threshold CONFIRMED; pairs MEASURED; cause INFERRED |
| L3 | Commit back-pressure | One commit in flight on iOS: while it is pending, the refresh is only marked `Delayed` (`WK/UIProcess/RemoteLayerTree/RemoteLayerTreeDrawingAreaProxy.mm:799-806, 808-833`; `AllowMultipleCommitLayerTreePending` false on iOS, `Prefs:296-311`). A slow GPU-process flush costs one update with an idle main thread | partly: a 33 ms interval with little work in it | none today (Simulator `RenderingFrame` is 0, 10-21-lag-windows.md); kdebug `CommitLayerTreeStart/End` (`WTF/wtf/SystemTracing.h:169-170`) via `xctrace` is a probe | kdebug points in a System Trace | Animation Hitches, Commits track | mechanism CONFIRMED; frequency INFERRED |
| L4 | 60 Hz page under a 120 Hz scroll | The display link is raised only for threaded time-based animations (unstable, default false, `Prefs:8542-8555`) or with the 60 fps preference off (`WK/UIProcess/RemoteLayerTree/ios/RemoteLayerTreeDrawingAreaProxyIOS.mm:239-264, 409-425`). Sticky hero and fixed nav move every display frame; `--exit-*` and `--morph` change at most every other one | no: intervals look like a steady 16.7 ms | none (no ProMotion on the Simulator) | same mapping on a 120 Hz Mac (INFERRED) | Instruments Display track; 240 fps camera | 60 fps rule CONFIRMED; 120 Hz UIScrollView rate INFERRED |
| L5 | JS-placed content trailing the async scroll | iOS: the UI process moves fixed and sticky layers in its own transaction (`WK/UIProcess/ios/WKContentView.mm:677-680`, `WC/page/scrolling/ScrollingTreeScrollingNode.cpp:517-530`); the page reads the new offset one update later. Mac: the scrolling thread waits at most half a frame, capped at 32 ms, then desyncs (`WC/page/scrolling/ScrollingTree.cpp:1088-1092`; `WK/UIProcess/RemoteLayerTree/mac/RemoteLayerTreeEventDispatcher.mm:571-609`) | no | none on iOS | kdebug `ScrollingThreadRenderUpdateSyncStart/End`, End data 1 = desync (`SystemTracing.h:106-107`) | video of a sticky edge against a JS-placed edge | path CONFIRMED; visible size INFERRED |
| L6 | Render-server cost (blur, backdrop, big layers) | backboardd or WindowServer renders CA filters and `CABackdropLayer`; WebKit does not wait for it (`RemoteLayerTreeDrawingAreaProxy.mm:829-832`), so a frame is late on glass at an unchanged cadence | no | none (the Simulator uses the Mac render server, INFERRED) | Animation Hitches on a macOS target, unchecked (INFERRED) | Animation Hitches, Renders and GPU tracks, hitch type "render" | no back-pressure CONFIRMED; cost INFERRED (closed source) |
| L7 | UI-process commit stall | The display link and UIScrollView share the Safari UI thread (`RemoteLayerTreeDrawingAreaProxyIOS.mm:136-142`); applying a big commit stalls the scroll | partly: the next rAF is late too, unattributed | none | Time Profiler on Safari | Animation Hitches, Commits on the Safari process | path CONFIRMED; occurrence INFERRED |
| L8 | Input latency; `pin()` against momentum | `touchmove` is non-passive (`apps/site/src/parts/morph.tween/driver.ts:104-106`@16b8aac); the native gesture waits for the page (`WK/UIProcess/WebPageProxy.cpp:5228-5297`); after the pan starts, `preventDefault` is ignored (`WK/UIProcess/ios/WKContentViewInteraction.mm:4238-4246`) and `scrollTo` becomes `setContentOffset` on a decelerating view (`WK/UIProcess/API/ios/WKWebViewIOS.mm:1515-1556`) | no | synthesized touches: timing not real | wheel path only | raw touches (no reduction yet); Event Timing; kdebug `SyncTouchEventStart/End` (`SystemTracing.h:142-143`); video for the jump | path CONFIRMED; whether `scrollTo` stops the deceleration INFERRED |
| L9 | Checkerboarding | Tile coverage grows along the scroll velocity, sent only while dragging or decelerating (`WC/platform/graphics/ca/TileController.cpp:499-549`; `WKWebViewIOS.mm:2996-3003`); WebKit counts blank tile area behind `_setScrollPerformanceDataCollectionEnabled:` (`WK/UIProcess/RemoteLayerTree/RemoteLayerTreeScrollingPerformanceData.mm:54-69, 134-160`) | no | that SPI in a WKWebView host on the Simulator (INFERRED CI-able); Chromium `Checkerboarding4` | same SPI | video | CONFIRMED |
| L10 | Image decode pop-in | With no decoded frame, `BitmapImage::draw` draws nothing and asks for a decode (`WC/platform/graphics/BitmapImage.cpp:88-117`) | async: no; sync decode: yes | Chromium counts decodes, no timing | kdebug `AsyncImageDecodeStart/End` (`SystemTracing.h:81-82`) | video | CONFIRMED |
| L11 | Rate throttles | Low Power Mode, VisuallyIdle, non-interacted cross-origin frames and `AggressiveThermalMitigation` halve rAF to 30 fps (`AnimationFrameRate.cpp:33, 47-65`; `WC/page/Page.cpp:544-549, 2809-2835`). Plain `ThermalMitigation` does not change the rAF rate; it coarsens DOM timer alignment (`Page.cpp:3071-3072`) and gates HDR on Mac (`WC/platform/mac/PlatformScreenMac.mm:158`). `RespondToThermalPressureAggressively` is off by WebKit default and `defaultsOverridable` (`Prefs:6964-6976`) | yes: session median near 33 ms | n/a | macOS LPM, same path (INFERRED) | session median plus the device syslog line from `Page.cpp:2842` (syslog capture INFERRED; probe first) | WebKit rates CONFIRMED; Safari's value of the aggressive preference INFERRED |
| L12 | Heat lowering clocks | Lower CPU and GPU clocks lengthen main-thread and render work | yes, as longer frames | n/a | n/a | battery temperature readout (`device.mjs:48-60`), not stored per pass | INFERRED |
| L13 | Deferred layout-viewport relayout | `shouldPerformLayout = m_isInStableState && !isChangingObscuredInsetsInteractively` (`WK/WebProcess/WebPage/ios/WebPageIOS.mm:3729-3730`): skipped while the view is unstable (drag, deceleration) or the toolbar resizes, run when the scroll settles | partly: a layout spike at settle | none: stepped `scrollTo` never makes the view unstable (INFERRED) | n/a | video; Web Inspector Layout records | skip CONFIRMED; visible jump INFERRED |
| L14 | Layout shift, scroll-anchoring jump (font swap, late image size, hydration) | felt as a jump, not a slow frame; WebKit has no `layout-shift` entry type (`WC/page/PerformanceObserver.cpp:153-175`) | no | per-frame `getBoundingClientRect` delta of anchors (trajectory probe) | same | video | entry type absence CONFIRMED; occurrence INFERRED |
| L15 | ProMotion ramp-up at scroll start | the display idles at a low rate and ramps up when motion starts | no | none | n/a | Instruments Display track | INFERRED |
| L16 | Memory-pressure purge | tile, IOSurface or decoded-image eviction makes a re-decode or blank tiles on scroll-back | sync re-decode only | none | n/a | kdebug `AsyncImageDecodeStart/End`; Allocations and VM Tracker on Safari's WebContent process | INFERRED |

Tool notes:
- `xctrace record --template 'Animation Hitches' --device <id>` records Hitches, User Events, Commits, Renders, GPU,
  Frame Lifetimes and display vsync tracks ([tech talk 10857](https://developer.apple.com/videos/play/tech-talks/10857),
  CONFIRMED). Xcode 27.1 here lists the template (MEASURED, listing only). Whether it attributes Safari's hitches is
  unknown, so a debug run of 5 min or less comes first.
- Web Inspector Timeline builds its records from web-process run-loop observers
  (`WC/inspector/agents/page/PageTimelineAgent.cpp:119-159, 256-310`), so it sees the page's main thread only. CONFIRMED.
- The rAF timestamp is `performance.now()` frozen at the start of `Page::updateRendering` (`WC/page/Page.cpp:2272-2277`;
  `WC/page/LocalDOMWindow.cpp:828-841`), rounded to 1 ms (`Performance.cpp:73`). rAF intervals measure the page's
  cadence, never the time a frame reaches the glass. CONFIRMED.

## What our harness measures and misses

| Measurement | Where (@16b8aac) | Reads | Misses |
|---|---|---|---|
| Phone felt-lag recorder | `packages/measure-webkit/src/device-record.mjs:22-62`; Lean `lean/Fw/Device/Session.lean` | rAF time, scrollY, 3 custom properties, touches | L3-L10, L13-L16; single misses (L2) |
| Phone readout | `device.mjs:48-60` | battery %, battery temperatures; thermal state "not exposed" (:59) | not stored per pass |
| Chromium cadence lane | `packages/gate-breakpoints/src/smooth/cadence.mjs:29-45, 69-90`; `lean/Fw/Gate/Smooth.lean:408, 547` | rAF times, real vsync, bad > 34 ms, hitch > 60 ms | single misses; WebKit kinds |
| Chromium traced reps | `smooth/trace.mjs:10, 34-61` | BeginFrame, DrawFrame, DroppedFrame | outside the verdict (`cadence.mjs:10-11, 133-134`) |
| Chromium counts lane | `packages/measure-chromium/src/run.mjs:33, 67, 114` | work counts under BeginFrameControl | all timing |
| WebKit Simulator Timeline | `packages/measure-webkit/src/scrollrun.mjs:3-8, 30-38` | Timeline records per step | velocity (L9), gesture (L8, L13), render server |
| webkit-lag-probe morph pass | `packages/measure-webkit/src/lag/probe.mjs:67` | Timeline records | untrusted `WheelEvent` skips the scrolling tree |
| Trajectory probe | `packages/gate-breakpoints/src/trajectory/kit.mjs:1-6` | computed style and rects per frame | timing |

Gaps in the phone recorder and its Lean reduction:
- **Felt window.** It spans 1.5 s before the end of the third tap (`Session.lean:424-437, 500-505`), keeps only frames
  in which scrollY moved (`:79-80, 520-522`), and the first tap stops the fling (`device-record.mjs:10`). CONFIRMED.
- **Still-page lag excluded.** The morph tween under scroll lock and the people blur tail run while scrollY holds, so
  their frames never count (`Session.lean:79-80`). CONFIRMED.
- **Pinned clock.** `record` defaults to `clock: 'pinned'` (`device-cli.mjs:35`), which fixes `Date.now()`
  (`page.mjs:15-19`), and the record does not store the clock (`device-record.mjs:107`). CONFIRMED.
- **One frame behind.** The recorder's callback runs before the page's rAF work, so it reads the previous frame's
  values (`device-record.mjs:6-9`). CONFIRMED.
- **Cold load.** Recording starts after a reload and a 6 s countdown, and the first traversal is not split out
  (`device-record.mjs:79-93`). CONFIRMED.
- **Probe effect.** Web Inspector stays attached in every pass, so every A/A pair carries it. One pair with the
  inspector detached measures it (INFERRED).
- **Raw records.** The raw `fw.phone.record/1` files are in the session scratchpad (MEASURED), which is temporary and
  outside the repo. They are not in `.local/`.

Five gaps close by Lean reductions on those raw records: the felt window, still-page lag, misses and jitter, input
latency, and cold load. The rest need a recorder change or a phone tool (plan section below).

## Definitions we adopt

| Definition | Rule | Bands | Status |
|---|---|---|---|
| Hitch time ratio (Apple) | sum of ms late per s of animation; ours per zone is the sum of max(0, interval minus expected) over zone time, expected from the session median | Organizer: ≤ 10 good, ≤ 25 warning, ≤ 50 critical, > 50 urgent ms/s [A1]; WWDC20: < 5 good, 5-10 notice, > 10 critical [A2] | bands CONFIRMED; our rAF-based form INFERRED to undercount (start time, not presentation) |
| Missed frame (Chromium) | presentation delta over 1.5 vsync while input was available, per 64 frames (`cc/metrics/scroll_jank_dropped_frame_tracker.h:29-43`, `.cc:121-160`) | none | CONFIRMED |
| Miss at the 60 Hz page rate | interval > 25 ms (1.5 × 16.67 ms) | none | rule INFERRED from the two above |
| Skipped slot | slot k_i = round((t_i minus t_0) / 16.67 ms); a skip is k_i minus k_(i-1) > 1 | none | INFERRED; proposed by the check |

- The > 25 ms rule is the per-interval form of `Fw.Frames.tickAt` (`lean/Fw/Spec/Frames.lean:46`@16b8aac):
  `tickAt 60 dt` is 2 or more from exactly 25.0 ms, so the two differ only at 25 ms. The Lean spec picks one boundary.
- The skipped-slot count resists jitter that the per-interval rules do not, but neither catches a long-then-short pair
  whose two updates share one display slot; only presentation time (Instruments) shows that (INFERRED).
- Apple's MetricKit, Xcode Organizer and `XCTHitchMetric` measure the developer's own app, so they do not apply to
  Safari unless Safari runs as an `XCUIApplication` target, which is unprobed [A3][A4]. `MXAnimationMetric` is
  deprecated in iOS 27.2 and macOS 27.0 ("Use MetricResult instead") [A3]. CONFIRMED.
- Perception: Apple writes that "even a couple of milliseconds can be noticeable" in fluid motion [A1]. For discrete
  input it gives about 50 to 100 ms, and 50 ms for dragging direction changes [A5]. A hang starts at about 50-100 ms.
  CONFIRMED.
- Event Timing (Safari 26.2+ [D3]) gives input delay only at 16 ms or more (`durationThreshold` floor) and covers
  `touchstart` and `touchend`, not `touchmove`: `EventTimingEligible` on `touchstart` and `touchend` (`WC/dom/EventNames.json:270, 273`),
  absent on `touchmove` (:272), `pointermove` (:199), `scroll`/`scrollend` (:227-228) and `wheel` (:332), checked at `WC/dom/EventDispatcher.cpp:195-196`. CONFIRMED. Touch-to-first-moving-frame is a different
  metric and comes from the raw touch stream.
- A whole-session median near 33 ms suggests Low Power Mode, VisuallyIdle or aggressive thermal mitigation. A zone
  median near 33 ms is usually page cost (the original arm's hero zones, summary.json). Tag throttling only from the
  session median plus a syslog line, never from a zone (INFERRED).
- Chromium lane: `Event.ScrollJank.DelayedFramesPercentage4.*`, `Graphics.Smoothness.PercentDroppedFrames4.*` and
  `Checkerboarding4.*` (`cc/metrics/frame_sequence_metrics.cc:108-146, 560-605`; `scroll_jank_v4_histogram_emitter.h:18-37`)
  read through CDP `Browser.getHistograms` (method INFERRED, probe first). Descriptive only.

## Check findings: applied or not


- 4, 7, 8, 9: phone figures outside summary.md (zone medians, short-interval and pair counts, felt-window zero counts)
  are named by source without the value, per this note's scope. The figures themselves were MEASURED by the check.
- 7: the theorem "every interval over 25 ms is a skipped slot" is false under absolute slot rounding. Frames at 8.5 ms
  and 34 ms sit in slots 1 and 2, so a 25.5 ms interval is no skip. Provable instead: every interval over 2 slots
  (33.3 ms) is a skipped slot, since round(y) minus round(x) > y minus x minus 1. The converse fails, as the check says.
- 7 (miss rule): the > 25 ms raw-interval count is kept beside the skipped-slot count. It matches Chromium's 1.5-interval
  rule and `tickAt`, so the two counts can be compared. It undercounts long-then-short pairs (MEASURED by the check). The
  skipped-slot count is the primary miss count.

- The display rate class
  not stored per record".

## Sources

[A1] https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app ;
[A2] https://developer.apple.com/videos/play/wwdc2020/10077 (bands read via wwdcnotes.com) ;
[A3] https://developer.apple.com/documentation/metrickit/mxanimationmetric ;
[A4] https://developer.apple.com/documentation/xctest/xcthitchmetric ;
[A5] https://developer.apple.com/documentation/xcode/understanding-user-interface-responsiveness ;
[D3] https://web.dev/blog/lcp-and-inp-are-now-baseline-newly-available . Read 2026-10-22.

## What this changes in the plan

- **PLAN §4.6, "Render server / GPU" row.** Name the tool: `xctrace` Animation Hitches in the phone session, hitches
  split into commit and render. Add L7, the UI-process commit stall.
- **PLAN §4.6, new row "Scroll vs content sync" (L4, L5).** Only video sees it (240 fps camera, or a screen recording
  once its rate is known). Class X; the look-change candidate C1b (transform-based nav) is judged against it.
- **PLAN §4.6, "Heat and Low Power Mode" row.** Keep the thermal class per run. Add: thermal mitigation keeps WebKit's
  rAF rate but can lengthen frames through lower clocks; the throttle tag uses the session median plus the syslog line
  from `Page.cpp:2842`.
- **PLAN §4.6, primary device metric.** Beside the 34 and 50 ms counts add the > 25 ms count, the skipped-slot count,
  hitch ms/s with the Apple bands, p95 and the longest 30 fps run. Store the display rate class (120) per record.
- **Task `device-lag-recorder`.** Copy the raw 2026-10-21 records to `.local/phone/2026-10-21/` now. Then, in Lean
  `Fw.Device.Session` with golden vectors: a first-tap anchor with a 3 s lookback, all-frame and animating-frame stats,
  the counts above, touch-to-first-moving-frame, finger-to-scroll offset, and a per-traversal split. The miss theorems
  are `over50 ≤ over34 ≤ miss25` and "interval over 2 slots implies a skipped slot". Re-reduce before anyone cites the
  felt-mark finding again.
- **Next phone session.** `--clock live` with the clock in the record; the readout per pass; an Event Timing observer
  (`durationThreshold: 16`); the device syslog filtered to WebKit (probe first); a Low Power Mode step line; one A/A pair
  with Web Inspector detached; one pass with the 60 fps preference off.
- **New task `phone-hitches-xctrace`** (phone, user step). A debug run of 5 min or less, then one Animation Hitches pass
  per arm.
- **Tasks `smoothness-probe` and `smoothness-webkit-cadence`.** Add the > 25 ms and skipped-slot counts to
  `Fw.Gate.Smooth` beside `badTenths` 340. Push the WebKit morph through a real wheel, not the synthetic `WheelEvent`.
  Read the Chromium histograms above.
- **Task `webkit-lag-probe`.** Add the blank-tile count (L9) through a WKWebView host on the Simulator and the Mac
  desync kdebug count (L5). A lean-prover task states the counted predicates first.

---
id: 2026-10-2x-scroll-throttle-parts
kind: note
title: "Which parts hit Safari iOS's scroll-update throttle: every main-thread scrollY reader in every zone, the page end included; engine.scroll:unthrottle lifts it for all of them"
status: review
created: 2026-10-24
topics: [lag, webkit, ios-toolbar, scroll-driven, engine.scroll, morph, end-of-page, phone]
---

# Which parts hit Safari iOS's scroll-update throttle

WebKit cites `@862f17d` unless a commit is named. Phone numbers come from the real-iPhone session of 2026-10-24
(`results/phone/2026-10-24-throttle-lift/summary.md`), one person. "lift" means the rewrite plus
`?fw=engine.scroll:throttle-lift`. Counts other than the summary's come from uncommitted scratch scripts named in Open
questions; each count names its rule where it appears.

## Question

User: does the 100 ms scroll-event throttle explain lag the earlier measurements missed, which parts hit it, and does
the end of the page hit it too?

## Answer first

- **The throttle stalls the page's copy of scrollY, so every part that reads scroll position on the main thread hits it.**
  It is not a per-part cost. Without lift, scrollY stands still for about 104 ms at the median (per-pass p10 93-100,
  p90 117-124 ms), then jumps a median 119-180 px per pass (pooled p10-p90 52-287 px, six passes without lift).
  MEASURED, over band runs (rule below) inside the page. A part stair-steps only where its own scroll range overlaps
  those stalls.
- **The end of the page hits it.** In the last 600 px, scrollY has 75-263 band runs per 1000 moving frames without
  lift and 4-14 with lift. MEASURED. A band run is a scrollY value held for 5-6 extra frames between two moves, binned
  by the zone of the held value and divided by the frames in that zone where scrollY changed. Counting with
  `stillruns.mjs` over contiguous end-600 px segments instead gives 43-234 without lift.
- **Most flings hit it, not only the top of the page.** 57 of 120 flings without lift contain a stair chain, 0 of 55
  with lift; 58 % after a direction change against 35 % (38/65 vs 19/55). MEASURED. A fling is the stretch from
  finger lift to the next touch, starting 10 frames before lift, with at least 6 moving frames and 50 px net travel; a
  stair chain is 3 or more still runs of 4-7 extra frames, each starting on the frame the previous one moved. A looser
  rule (2 such runs, 8 moving frames) finds 90 of 100 without lift and 22 of 49 with lift.
- **WebKit has one 100 ms trigger: Safari changing the toolbar insets interactively** (`WKWebViewIOS.mm:3256-3268`).
  CONFIRMED. That Safari keeps this state on through deep mid-page flings is INFERRED from the phone data.
- **Lift removes the stall for every main-thread reader at once.** It brought end-of-page slow frames from 2.46-6.56 to
  0.00-1.17 per 100 and felt marks from 12-14 to 3-5. MEASURED.
- **The page-end restore fight is a second, separate cost.** scrollY reversals near maxY remain with lift (5-18 per
  pass against 9-31 without), and the morph reopens 8-41 times per pass without lift (9-35 with). MEASURED, rules in
  steps 5 and 7 below. So the stale pin predicted below is not the main cause of the reversals.

## When WebKit throttles

| Condition | 10 Hz? | Evidence |
|---|---|---|
| `_isChangingObscuredInsetsInteractively` set by SPI `_beginInteractiveObscuredInsetsChange` and not `hasMainThreadScrollDrivenAnimations` | Yes. Updates within 100 ms of the last one wait on a timer. | CONFIRMED `WKWebViewIOS.mm:143`, `:3256-3269`, `:2979-2989`, `:4697-4708`; `WKWebViewPrivate.h:771-772` |
| Who calls that SPI | Only tests in the tree. In Safari, the toolbar collapse and expand that follows the finger (closed source). | CONFIRMED `UIScriptControllerIOS.mm:1486-1494` and `WKScrollViewTests.mm:1140-1446` (raw fetch @862f17d); INFERRED for Safari |
| Plain pan or momentum with the toolbar still | No. One update per CATransaction pre-commit, so one per frame. | CONFIRMED `WKWebViewIOS.mm:2384-2399`, `:3030-3064` |
| Rubber band at the page end while the toolbar animates | Yes | CONFIRMED commit 13e748d819 (bug 315320) and test `FixedClippingViewTracksRubberBandDuringInteractiveObscuredInsetsChange` |
| Toolbar coming back at the page bottom | Probably yes | INFERRED |
| Keyboard, zoom bounce, live or animated resize, rotation (`:3246-3249`) | Not 10 Hz. The update waits until the view is stable. | CONFIRMED `WKWebViewIOS.mm:3246-3249`; `_shouldDeferGeometryUpdates` (`WKWebViewIOS.mm:3139-3142`) covers live and animated resize, rotation and fullscreen exit |
| Overflow (non-root) scrollers | Never. Their positions reach the web process through RemoteScrollingTree. | CONFIRMED `RemoteScrollingTreeIOS.cpp:66-72` |
| Web process slow (latency above 1/60 s) while scrolling is unstable | A second throttle: scroll events coalesce for min(2 × latency, 1 s), on any pan | CONFIRMED `WebPageIOS.mm:2240-2256`, `WebPageCocoa.mm:2384-2392`, `LocalFrameView.cpp:3784-3790` |

What lifts the 100 ms throttle: a main-frame progress-based timeline (`scroll()` or `view()`) with a relevant animation
whose properties are not all accelerated (`WebPageCocoa.mm:2357`, `AnimationTimelinesController.cpp:267-279`,
`KeyframeEffect.h:180`). Each layer-tree commit carries the flag (`WKWebViewIOS.mm:1197`), so it acts from the next
commit. CONFIRMED. WebKit added this exemption in b07ce30ae0 (bug 319523) after a jitter report; the throttle itself
(c45540108d, relanded de6e12d23e) was for "up to 2%" power. CONFIRMED from commit messages.

## What is stale

The main frame's scroll position reaches WebCore only through `WebPage::updateVisibleContentRects`, `applyScrollUpdate`
and `notifyScrollPositionChanged` (`WebPageIOS.mm:3573` for updateVisibleContentRects, `:3768-3779` for applyScrollUpdate; `AsyncScrollingCoordinator.cpp:865-884`).
CONFIRMED.

| Web-process API | Stale for up to 100 ms? | Evidence |
|---|---|---|
| `window.scrollY`, `getBoundingClientRect` | Yes | CONFIRMED (path above) |
| `scroll` events | Yes, fired only from `scrollPositionChanged` | CONFIRMED `LocalFrameView.cpp:3778-3790` |
| rAF that reads scroll position | Site engine: runs once per delayed update; a free rAF reads one value about 6 frames in a row | CONFIRMED `apps/site/src/engine/scroll.ts:94-101` for the site engine; INFERRED for a free rAF |
| IntersectionObserver | Yes, computed in the rendering update from the stale position | INFERRED (`Page.cpp:2367`) |
| visualViewport scroll and resize | Yes | CONFIRMED `WebPageIOS.mm:3719-3743` |
| `resize` event and layout | Suppressed during the inset change | CONFIRMED `WebPageIOS.mm:3729-3747` |
| Touch events | No, own channel; fresh finger delta against stale geometry | INFERRED |
| Threaded scroll-driven animations (opacity, transform, filter) | No, the UI process updates them every scroll | CONFIRMED `RemoteScrollingTreeIOS.cpp:60-64` |
| position: fixed and sticky layers | No, moved in the UI process every frame | CONFIRMED `WKWebViewIOS.mm:3264-3267`, `:3305-3315`, `WebPageProxy.cpp:18557-18562` |
| Script `window.scrollTo` | Sets the web process position; the next update carries the UI process's live offset | INFERRED |

## Per part

All per-frame JS readers share one passive `scroll` listener and one frame callback
(`apps/site/src/engine/scroll.ts:94-101`, `:131-137`), so under the throttle they see a new position at most 10 times a
second. Part paths are under `apps/site/src/parts/`. Phone columns: band runs per 1000 exit frames from `stillruns.mjs`, which only tracks hero exit
and coarse zone values; no per-part trace exists for most rows.

| Part | Zone | Driver | Hit? | Code evidence | Phone evidence | Predicted symptom | Measured symptom |
|---|---|---|---|---|---|---|---|
| hero.exit (faithful) | hero | JS reads track position per frame | Yes | `hero.exit/driver.ts:32` | 33-102 without lift, 0-4 with lift | 5-6 frame stills | Same; hero felt marks 12 to 0 |
| hero.exit:threaded | hero | CSS view timeline, compositor properties | No | `hero.exit/threaded.*` | pass rec-thr: hero not traced inline | None | Not measured per part |
| hero.accent, hero.countdown | hero | IntersectionObserver, ResizeObserver, timers | Yes, harmless | `hero.accent/index.tsx:84`, `hero.countdown/index.tsx:86` | none | Starts or stops up to 100 ms late | Not measured |
| hero.cue | hero | smooth `scrollTo` on tap | No | `hero.cue/index.tsx:10` | none | None | Not measured |
| nav | all | JS reads nav and sticky item positions per frame | Yes | `nav/index.tsx:41-42`, `:104` | none | Sticky and shadow class one update late | Not measured |
| nav.hitTest | all | `elementFromPoint` per frame sets the on-dark class | Yes | `nav.hitTest/index.tsx:33`, `probe.ts:66` | none | Nav colour wrong up to 100 ms at edges | Not measured |
| people.card | rest | JS writes `--future-shrink` per frame | Yes | `people.card/index.tsx:54-58`, `:74` | people zone 12-29 without lift, residual with lift | Stair-step shrink | People pooled 18 to 6.5 per 1000 (Lean 5x rule: not lifted; few frames) |
| people.deck | rest | snap row on the phone | No on the phone | `people.deck/driver.ts:82`, `:116` | none | None | Not measured |
| people.o, people shared | rest | IntersectionObserver (35 %, near viewport) | Yes, harmless | `people.o/index.tsx:45-47`, `people/shared.ts:31-33` | none | Ring opens or pauses up to 100 ms late | Not measured |
| pain dark | rest | CSS `animation-timeline` on opacity | No | `pain/darkScroll.ts:6`, `:47-58` | none | None | Not measured |
| pain.notes | rest | JS per frame under the card, plus IntersectionObserver at 12 % | Yes | `pain.notes/index.tsx:124`, `:141` | none | Notes move in steps | Not measured |
| commission | rest into finish | JS reads card top and section bottom, eases toward target | Yes | `commission/driver.ts:111-125`, `logic.ts:46-63` | none | 10 Hz pulses: target jumps, eased value chases it | Not measured |
| engine.scene, platform.entries, Visuals | rest, finish | IntersectionObserver thresholds | Yes | `engine.scene/observe.ts:18`, `platform.entries/driver.ts:10`, `Visuals.tsx:325` | none | Late reveal; one jump crosses several thresholds in one frame | Not measured |
| platform.shrink | finish | JS reads card bottom against `innerHeight` | Yes, likely idle at the end | `platform/index.tsx:98`, `:109`, `driver.ts:24-36` | none | Stair-step; INFERRED to stay 0 at the end (`logic.ts` `raw`) | Not measured |
| morph.mount, morph.tween | finish | IntersectionObserver at 200 % arms non-passive listeners; arm test reads platform bottom and viewport height; pin restores scrollY | Yes, in arm and pin | `morph.mount/index.tsx:46-60`, `:78-82`, `:107-110`; `morph.tween/driver.ts:113-136`, `:205-207` | end600 75-263 without lift, 4-14 with lift; reversals remain with lift | Late open, then a snap back | Reversals 9-31 per pass, 5-18 with lift |
| morph.panel, morph.countdown | finish | follow the tween value (time), timers | No | `morph.panel/driver.ts` | fade climbs every frame while scrollY is locked | None | Fade: 0 band runs in every pass |
| morph.columns | finish | CSS keyframes (16 s); an IntersectionObserver pauses the tracks while hidden | Up to 100 ms late, harmless (IO pause) | `morph.columns/index.tsx:20-25` | none | Pause or resume up to 100 ms late | Not measured |

Two more readings from the phone data. Parts freeze while scrollY moves in 0-17 runs per pass; this fits the second,
latency-based scroll-event throttle (INFERRED). The hero-threaded pass (rec-thr) has the highest rest-zone rate,
146 per 1000, because threaded animations are accelerated and do not set the exemption flag (INFERRED from
`AnimationTimelinesController.cpp:267-279`).

## End of page chain

1. **The toolbar changes near the bottom.** Phone passes show viewport heights 775 and 815, and the rubber band at the
   end runs with the toolbar animating, which commit 13e748d819 names as throttled. The throttle is on. INFERRED.
2. **scrollY stalls on the approach.** In pass rec-2b the rewrite held scrollY at 4731 for 7 frames, 5035 for 6 and
   5254 for 6, then 5296 for 5 in the rubber band; with lift (rec-3c) it held still twice (4640 for 7, 4855 for 6).
   MEASURED.
3. **Arming is late, not missed.** The 200 % IntersectionObserver has margin to spare. Each push then sees a fresh
   finger delta against the stale platform bottom and `visualViewport.height`, so `bottom <= vh + 8` can pass up to
   100 ms (about 6 touchmoves) late. A moving toolbar makes the stale height off by up to 40 px. INFERRED.
4. **The pin is taken from a stale scrollY.** The first accepted push stores `pin = window.scrollY`
   (`morph.mount/index.tsx:56`, `morph.tween/driver.ts:134`) while Safari has scrolled further. INFERRED.
5. **The restore fight.** On the next update both pins call `scrollTo({top: pin, behavior: 'instant'})`, as the
   original does (`snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js:13060-13079`). CONFIRMED in code. The phone
   shows reversals of 20 px or more within 100 px of maxY, 9-31 per pass (rec-thr 9, rec-4 12, rec-1 13, mpt 14, rec-2
   17, rec-2b 31; a reversal is a move of 20 px or more against the previous move's direction, either frame within
   100 px of maxY), 1-9 inside the morph-open window, in the
   pattern 5292, 5260, 5292, 5227. MEASURED. With lift they stay at 5-18 per pass, so the stale pin is not their main
   cause; the pin fighting the rubber band is (the CI Simulator showed the same alternation, `10-2x-touch-lock-page-end.md`).
6. **The tween itself is smooth.** It runs from time: fade climbs every frame while scrollY sits at 5227 or 5292.
   MEASURED.
7. **The morph reopens.** Fade onsets (frames where the fade value leaves 0) repeat 8-41 times (9-35 with lift) per pass during long stays at the bottom. MEASURED. Cause not
   traced.
8. **Burst frames.** Each update delivers 100 ms of scroll at once, so observer crossings, the commission step and new
   paint land in one frame. INFERRED. It fits the measured end-of-page gain from lift; the mechanism is not measured.

## Fixes ranked

| Rank | Fix | Covers | Same look | Needs to ship |
|---|---|---|---|---|
| 1 | `engine.scroll:unthrottle` (promoted throttle-lift) | Every main-thread reader in every zone, steps 2-4 and 8 above | Same look INFERRED: the element is 1x1, opacity 0, fixed, aria-hidden. User felt it the same (phone 2026-10-24). | Task `unthrottle-preset`: Lean decision for the WebKit condition chain, same-look proof from the visual model, cost bound (about one restyle per frame and 2 extra Chromium layers, MEASURED), a `(pointer: coarse)` or WebKit-only guard, breakpoint gate on both engines, trajectory probe. It gives back Apple's "up to 2%" power saving (INFERRED). |
| 2 | Stop script scroll restores at the page end: lock with `touch-action` or `overflow` on the root instead of `scrollTo(pin)` | Steps 4-5, the reversals that lift leaves | Look change: the lock removes the rubber band and native pan (`10-2x-touch-lock-page-end.md`). Goes to the user's visual review. | A candidate window on CI (the last run lost it to `pageLost`), the Lean fight verdict per arm, a phone pass |
| 3 | Move per-frame JS readers to threaded CSS scroll-driven animations (as hero.exit:threaded) | One part each: people.card, platform.shrink, pain.notes; nav.hitTest only as an opacity cross-fade of two colour layers | Same look only where the value is a pure function of scroll. commission's eased chase is time-based, so a threaded version changes the look. | Per part: Lean curve equality against the JS driver, breakpoint gate, phone pass. Does not help IntersectionObserver or morph readers. |
| 4 | IntersectionObserver thresholds in place of per-frame reads | Lowers main-thread work, so the latency-based throttle triggers less | Same look if thresholds match the old conditions | Lean threshold equivalence. Does not lift the 100 ms stall: observers read the same stale position (INFERRED). |
| 5 | Find why the morph reopens 8-41 times per pass | Step 7 | Same look if the open condition is unchanged on first open | A trace of arm and close events at the end; not yet a task |

Fix 3 conflicts with fix 1 in one way: with unthrottle on, threaded parts gain nothing extra; without it, they are the
only parts that stay smooth.

## Open questions

- Does Safari's interactive inset state really span whole mid-page flings? Needs innerHeight per frame (task
  `recorder-viewport-per-frame`).
- How much of the reversal amplitude does the throttle add, even if it does not cause the reversals? Needs reversal
  amplitudes compared with and without lift.
- Which part freezes in the 0-17 runs where scrollY moves, and is it the latency throttle?
- The per-zone tables, end-zone stall counts, fling stair chains, reversals and fade onsets come from uncommitted
  scratch scripts (`lib.mjs`, `yruns.mjs`, `jumps.mjs`, `phase.mjs`, `flings.mjs`, `flings2.mjs`, `rev.mjs`,
  `morph.mjs`); their rules are named where each number appears. Commit them with a regenerate command before this
  note leaves review.
- Port the counting rules (end-zone stalls, fling stair chains, reversals, fade onsets) to Lean; task
  `sim-finish-throttle`'s `Fw.Device.FinishRuns` covers end-zone stalls and reversals.

## Sources

- WebKit `@862f17d`: `Source/WebKit/UIProcess/API/ios/WKWebViewIOS.mm`, `WKWebViewPrivate.h`,
  `Source/WebKit/WebProcess/WebPage/ios/WebPageIOS.mm`, `WebPageCocoa.mm`, `RemoteScrollingTreeIOS.cpp`,
  `WebPageProxy.cpp`, `UIScriptControllerIOS.mm`, `Source/WebCore/page/LocalFrameView.cpp`, `Page.cpp`,
  `AsyncScrollingCoordinator.cpp`, `AnimationTimelinesController.cpp`, `KeyframeEffect.h`, test `WKScrollViewTests.mm:1140-1446`.
- WebKit commits c45540108d, cab43568d0, de6e12d23e, 13e748d819, b07ce30ae0, a71323b7d6.
- Site: `apps/site/src/engine/scroll.ts`, `apps/site/src/parts/` (paths in the per-part table),
  `apps/site/src/parts/engine.scroll/throttle.ts`.
- Original: `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js:13060-13079`.
- Phone: `results/phone/2026-10-24-throttle-lift/summary.md`; still-run rule Lean `Fw.Device.StillRuns`, twin
  `packages/measure-webkit/src/throttle/stillruns.mjs`.
- Notes: `10-2x-toolbar-throttle.md`, `10-2x-touch-lock-page-end.md`.

# End-of-page scroll: how it runs today and seven off-main-thread alternatives

Research run 2026-10-26 (three read-only agents: current mechanism, engine facts, designs). Repo at 9493a5ddb, WebKit
pinned 862f17d, Chromium f842f52. Every design below is a look change (class L) and needs the user's visual review.

## How the end of the page scrolls today (CONFIRMED from source at 9493a5ddb)
* It is a scroll-jack. While the platform section is within 2 viewports (IntersectionObserver, rootMargin 200%),
  morph.mount and morph.tween each attach a capture pair of non-passive `touchmove` and `wheel` listeners
  (morph.mount/index.tsx:107-115, morph.tween/driver.ts:156-170). A forward push that passes the armed test is
  `preventDefault`-ed and starts a 680 ms time-based JS tween (morph.tween/logic.ts:10, driver.ts:172-186).
* Each tween frame writes the inherited `--morph` and `data-fw-morph` on the fixed nav (morph.tween/index.tsx:46-51);
  three MutationObservers fire per frame (nav, morph.panel, nav.hitTest). `--morph` resizes the nav, the panel and the
  columns through layout properties (width, height, top, radius, gap, blur).
* The page is held at the end by `window.scrollTo({top: pin})` on every scroll frame whose scrollY differs from the pin
  (driver.ts:218-222, end.logic.ts:92-96), against UIKit's pan, deceleration and rubber band.
* Per scroll frame the scroll engine also runs nav.measure and nav.hitTest (an `elementFromPoint` after a
  pointer-events write, which forces style and layout; nav.hitTest/probe.ts:41-103).

## What the notes say causes the felt WebKit lag here
1. Safari's 100 ms toolbar throttle (CONFIRMED WKWebViewIOS.mm:3256-3268@862f17d). The only phone win so far is the
   lift: end slow frames 2.46-6.56 to 0-1.17 per 100 (MEASURED, results/phone/2026-10-24-throttle-lift).
2. The pin fight: 5-18 reversals of 20 px or more per pass remain with the lift, and 8-41 re-opens per pass, because
   a 1 px direction flip re-targets the tween (10-2x-morph-reopen.md, 10-2x-scroll-throttle-parts.md).
3. Each tween frame: a JS-written inherited custom property is never handed to Core Animation, so the morph is
   main-thread layout and paint on every frame.

## Engine facts that decide the designs (WebKit iOS unless named)
* The main-frame scroll is a UIScrollView in the UI process; composited `position: sticky`/`fixed` layers get a
  scrolling-tree node and move in the UI process every scroll (RenderLayerCompositor.cpp:5655-5661,
  ScrollingTreeStickyNodeCocoa.mm:64-89@862f17d).
* CSS scroll-driven animations ship with no flag; ThreadedScrollDrivenAnimationsEnabled is stable and on
  (UnifiedWebPreferences.yaml:8518-8531). An effect runs threaded only if its timeline source has a scrolling node and
  every effect on the element is accelerable: opacity, filter, backdrop-filter, transform, translate, scale, rotate
  (KeyframeEffect.cpp:1965-2021, KeyframeEffectStack.cpp:215-250, CSSProperties.json).
* A main-thread (non-accelerated) progress timeline is what skips the toolbar throttle (WKWebViewIOS.mm:1197,3259).
* Root `overscroll-behavior` maps onto UIScrollView bounce in the UI process (WKWebViewIOS.mm:1084-1087).
* Root scroll-snap replaces the momentum target in the UI process when the drag ends
  (RemoteScrollingCoordinatorProxyIOS.mm:643-672).
* A non-passive `touchmove` under the finger makes the native pan wait for the web process
  (WKContentViewInteraction.mm:2252-2260).
* Main-thread rendering is capped near 60 fps on iOS; time-based transform/opacity/filter animations become
  CAAnimations and are not (RemoteLayerTreeDrawingAreaProxyIOS.mm:192-204, GraphicsLayerCA.cpp:1183-1215).

## Designs, ranked (INFERRED effects; none measured yet)
| rank | design | replaces | why off the main thread | effort |
|---|---|---|---|---|
| 1 | Sticky end stage, scroll-linked morph (`morph.stage`): a track of T px after the platform, the scene `position: sticky` in it, `--morph` on `animation-timeline: scroll(root)` over [maxY-T, maxY] | the touch/wheel capture pairs, the scrollTo pin, the 680 ms rAF tween and its MutationObservers | the hold is a sticky scrolling-tree node; no scrollTo, no non-passive listener | L |
| 2 | Static root no-bounce (`morph.end.nobounce`): `html { overscroll-behavior-y: none }` from first paint, never toggled | the rubber-band side of the pin fight | UIScrollView bounce off in the UI process; differs from the tried overscroll-lock (n79), which toggled it mid-gesture | S |
| 3 | Compositor-only morph geometry: transform/opacity skins instead of `--morph` resizing layout | the layout consumers of `--morph` in nav/ and morph.panel | only accelerable properties, so rank 1 or rank 5 can run in the UI process | L |
| 4 | Root proximity scroll-snap at the two stage ends (with rank 1) | the tween's finishing role | snap target chosen in the UI process | S after 1 |
| 5 | Time-based CSS/WAAPI morph on compositor properties, keeping today's push trigger; `cubic-bezier(1/3,1,2/3,1)` equals the tween's ease-out cubic | the tween rAF and per-frame writes | CAAnimations in the UI process | M after 3 |
| 6 | Nav on-dark by a `view()` timeline crossfade of two skins | the per-frame `elementFromPoint` probe | threaded opacity with steps() | M |
| 7 | Whole page in a container scroller (toolbar never collapses) | window scroll listeners, the unthrottle element | async overflow scrolling | XL |

## Recommendation and caveats
* Build first, as separate look-change flags: rank 2 (one CSS rule; directly tests H2, that scroll fights drive the
  push-cycle rise, on the push-cycle and toolbar lanes) and rank 1 (removes the scroll-jack and the pin fight; its
  main-thread scroll timeline also lifts the toolbar throttle, so the unthrottle element becomes redundant).
* Then rank 3 plus rank 4 if the user accepts the interaction; rank 5 is the path that keeps today's push interaction.
* WebKit still runs one style pass per rendering update for scroll-timeline animations (MEASURED, ledger n10), so the
  expected gain is decoupling the morph from the main thread and ending the scroll fight, not zero main-thread work.
* Tried before and not repeated: batched reads (n1), scroll-lock (premise false on iPhone), touch lock (fights
  overlap), CM compositor-morph (trade), overscroll-lock toggled while armed (n79), end.clamp/flip/release (n67-n69).

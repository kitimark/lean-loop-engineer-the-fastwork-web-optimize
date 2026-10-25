---
id: 2026-10-25-toolbar-native
kind: note
title: "iOS toolbar resize: what WebKit does page-side, which claims of the first research stood the check, and the reproduction lanes"
status: review
created: 2026-10-25
topics: [webkit, ios, toolbar, obscured-insets, morph, throttle, reproduction, unthrottle]
---

# iOS toolbar resize: native handling and reproduction

Task `toolbar-proof-morph`. Inputs: a first research note and its independent check (both local, not committed).
Only what the check let stand is kept; its corrections replace the claims they refuted. All WebKit cites are
`file:line@862f17d` (pinned clone `.cache/upstream/WebKit@862f17d`). Tags: CONFIRMED (source cited), INFERRED, MEASURED.

## Answer

- iOS WebKit has no page-side per-frame toolbar handler (CONFIRMED). While Safari's toolbar moves the page is in an
  interactive obscured-insets change: every visible-rect update to the web process waits 100 ms
  (`WKWebViewIOS.mm:143`, `:3256-3268`). The scroll offset is part of that update, so `scrollY`,
  `getBoundingClientRect()`, `scroll` events and `visualViewport` are all stale up to 100 ms
  (`WKScrollViewTests.mm:1158-1166`).
- The UI process moves fixed and sticky layers every frame regardless (`WKWebViewIOS.mm:3305-3315`
  `_updateViewportRelativeLayersOutOfBand`).
- The throttle is lifted when the page runs a progress-based scroll-driven animation on the main thread
  (`hasProgressBasedScrollDrivenAnimation` with a not-fully-accelerated effect, `AnimationTimelinesController.cpp:267-279`).
  Our `engine.scroll:unthrottle` animates `@property --fw-ut`, so it qualifies (CONFIRMED; lifted in the Simulator,
  `10-2x-toolbar-throttle.md`, MEASURED).
- `resize` is skipped while the change is interactive (`WebPageIOS.mm:3743`); it fires after the end.

## Claims that stand (check, items 1-6)

1. The 100 ms throttle and its exemption for main-thread scroll-driven animations.
2. Fixed and sticky layers move out of band (`WKWebViewIOS.mm:3305-3315`).
3. `resize` is skipped during the interactive change (`WebPageIOS.mm:3743`).
4. Root `overscroll-behavior` maps to the main scroll view's `bounces` (`WKWebViewIOS.mm:1084-1087`).
5. `touch-action` accepts auto, none, manipulation, pan-x, pan-y; `pan-up`/`pan-down` are unimplemented. `minimal-ui` is
   ignored (`ViewportArguments.cpp:404-407`); `interactive-widget` is keyboard-only and off by default.
6. WKTR hooks exist: `LayoutTests/resources/ui-helper.js:2018-2050`, `UIScriptControllerIOS.mm:1486-1494`.

## Claims that fall, and the correction

| First research | Check | Consequence for the task |
|---|---|---|
| Rank 2: `dvh` forces layout, `vh` avoids it | Any layout-viewport height change forces layout (`LocalFrameView.cpp:1956-1957`); `didChangeViewportSize` invalidates every element with any viewport unit, `vh` included (`StyleScope.cpp:779-784`). `vh = lvh` (`WKWebViewIOS.mm:1249-1251`) holds only when the host overrides layout parameters; for Safari INFERRED | dropped; candidate (f) counts the cost |
| Rank 3: a probe element removes the staleness | The throttle covers every visible-rect update, scroll offset included; a probe fixes nothing; with unthrottle on nothing is stale | probe idea dropped; (b) only where geometry is toolbar-free by construction |
| Rank 4: decide at `touchstart` | `touchstart` has no direction; `preventDefault` there blocks scrolling up and kills taps. The first `touchmove` is still preventable: the native pan waits for it (`_touchMoveDeferringGestureRecognizer`, `WKContentViewInteraction.mm:1368`, `:2562`). After the pan began (`:4239-4245`) a `preventDefault` no longer stops it | candidate (e): decide on the first `touchmove`, never start pinning after the pan began |
| Rank 1: unthrottle is "same look", free | It brings layout and viewport-unit style work back every frame: a trade | candidate (f) |
| Lane (b) real-phone safaridriver swipes | Native-scroll swipes run away, end in `pointercancel`, wedge the session (`10-2x-device-replay.md:95-125`) | lane unusable |
| Lane (a) `vh` field | The recorder's `vh` is `visualViewport.height` (`recorder.mjs:24`), not CSS `vh` | count steps of `visualViewport.height` |
| Minor | `FixedLayerPositionDoesNotFreeze...` is at `WKScrollViewTests.mm:1351` | cite there |

## Corrected recommendation

1. Keep unthrottle; count its per-frame layout and style cost (f).
2. Decide the push on the first `touchmove` (e).
3. `overscroll-behavior-y: none` while armed: look-change class (g). Scrolling inside a container so the toolbar never
   collapses (d): look-change class.
4. No probe element.

## Reproduction recipe (corrected)

| Lane | Moves the toolbar | How |
|---|---|---|
| (a) Simulator XCUITest | yes | `.github/workflows/toolbar-throttle.yml`; count the 10 Hz steps in `visualViewport.height` (the page value steps, so count steps, not frames) |
| (c1) WKTR forced inset | the same WebKit state, no Safari chrome | `UIHelper.beginInteractiveObscuredInsetsChange`, `setObscuredInsets` in steps, `scrollTo` between, `endInteractiveObscuredInsetsChange`. Each `setObscuredInsets` waits for a presentation update: step-wise, not per frame. lvh/svh are not overridden there |
| (c2) host app | n/a | would add `_overrideLayoutParameters...` so the units match Safari; optional |
| real phone safaridriver | blocked by the wedge | not used |
| Playwright on Linux | no | dropped: the iOS UIProcess code is not compiled there |

Threaded scroll-driven animations move every frame but clamp to the last committed scroll range
(`RemoteProgressBasedTimeline.cpp:52-77`) and do not lift the throttle (only main-thread ones do); a stale range while the
toolbar moves is INFERRED.

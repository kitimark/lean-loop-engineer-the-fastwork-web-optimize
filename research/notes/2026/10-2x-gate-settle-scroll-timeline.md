---
id: 2026-10-22-gate-settle-scroll-timeline
kind: note
title: "A scroll-driven animation at a fixed scroll offset stays running forever in both engines, so the gate's settle probe must count document-timeline animations only"
status: draft
created: 2026-10-22
topics: [gate, settle, scroll-driven, hero.exit, web-animations]
---

# Why every sample of `hero.exit:threaded` ended unsettled

Task `gate-settle-scroll-timeline`. Run 39769627588 (breakpoint gate, `fw=hero.exit:threaded`, both engines) had 155 unsettled
samples, 0 fail readings and a red merge job. The settle probe (`packages/gate-breakpoints/src/page.mjs`, `settleInPage`) and the
idle waits (`waitReady`, `prepareInPage`) counted every finite-iteration animation whose `playState` is not `finished`/`idle`.
Status words: CONFIRMED (source or spec cited), MEASURED (run cited).

## 1. What a scroll-driven animation reports at a constant scroll offset

| claim | status | evidence |
|---|---|---|
| Progress of a scroll progress timeline is `scroll offset / (scrollable overflow - scroll container)`; it is a function of the offset only, updated once per frame in the event loop | CONFIRMED | Scroll-driven Animations 1, `#scroll-timeline-progress`, `#event-loop` (https://drafts.csswg.org/scroll-animations-1/) |
| The play state is `finished` only when current time reaches the effect end (rate > 0), else `running` once the animation has a start time | CONFIRMED | Web Animations 1 section 3.5.19 "Play states"; Chromium `third_party/blink/renderer/core/animation/animation.cc:1565-1594`@f842f52 (`CalculateAnimationPlayState`, `Limited` at `:467-476`); WebKit `Source/WebCore/animation/WebAnimation.cpp:791-821`@862f17d (`playState`) |
| Current time of the animation is `(timeline time - start time) * rate`, and the timeline time of a scroll timeline is the snapshot of the scroll offset | CONFIRMED | Chromium `animation.cc:1335-1344`@f842f52, `scroll_snapshot_timeline.cc:64-66` (`CurrentTimeInternal` returns the snapshotted `current_time`), `:221-233` (`UpdateSnapshotInternal` replaces it from the layout); WebKit `ScrollTimeline.cpp:255-271` (`computeCurrentTimeData`), `:383-397` (`currentTime`)@862f17d |
| A timeline with no scrollable overflow is inactive (current time null), then the animation has no current time | CONFIRMED | Scroll-driven Animations 1 `#scrolltimeline-interface`; Chromium `scroll_snapshot_timeline.cc:45-47`@f842f52 (`IsActive`), `animation.cc:1336` (`CalculateCurrentTime` is unresolved on an inactive timeline) |

Consequence (INFERRED from the rows above): while the scroll offset is inside the animation's range the current time is
strictly below the effect end, so `playState` is `running` on every frame and `finished` never arrives. The hero exit
animations of `hero.exit:threaded` (`animation-timeline: --hero-exit`, a view timeline; `apps/site/src/parts/hero.exit/`) are
finite (`iterations` 1) and are in range at the probe offset, so the old count was at least their number on every
observation, and `settled` (`running == 0`) never held: the wait ran to its frame budget and the sample was `unsettled`
(Lean `runCountAll_scroll_blocks`).

## 2. The rule

- `running` counts finite animations on the document timeline (`a.timeline instanceof DocumentTimeline`, the test
  `freezeAnimations` already uses to leave scroll-driven animations alone) that are not finished or idle.
- An animation on any other timeline contributes through the quiet signature: the probe samples the boxes, transform numbers
  and opacity of the probed elements, which already show the scroll-driven value. At a fixed offset two frames read the same
  value, so the frame is quiet and `stable` grows (Lean `scroll_fixed_quiet`, `scroll_fixed_nextStable`). If the offset
  moves, the signature moves and the sample is still unsettled, correctly.
- Document-timeline arms are unchanged: `runCount_document` shows the count equals the old one when every animation is on the
  document timeline; `signup_unsettled` still holds for a running document animation.

Lean: `lean/Fw/Gate/Settle.lean` (`runCount`, `runCountAll`, `runCount_document`, `runCount_cons_scroll`,
`runCount_cons_document`, `settled_cons_scroll`, `runCount_zero_of_scroll_or_done`, `scroll_cannot_block`,
`runCountAll_scroll_blocks`, `scrollSig`, `scroll_fixed_quiet`, `scroll_fixed_nextStable`). Golden: seven `runs` lines in
`packages/contracts/golden/gate/settle.jsonl`; the node twin `runCount` and the page predicate `counts` (markers in
`settleInPage`) replay them in `test/settle-golden.test.mjs`.

## 3. Limits

- A scroll-driven animation that is stuck for another reason (the offset keeps moving, e.g. a smooth scroll that never ends)
  still shows as a moving signature and stays unsettled. This is wanted.
- The `matchMedia` not-comparable excusals of the verdict are untouched.
- If this unblocks the cells and a real parity difference appears on `hero.exit:threaded`, that is a finding for
  `hero-exit-threaded`, not a defect here.

## 4. Result (MEASURED)

Run 39774976109, breakpoint-gate dispatched on `ci/gate-settle-scroll-timeline` (tip ff8c8cd1) with `fw=hero.exit:threaded`, engines both,
against run 39769627588 (same inputs, before the fix; both read from the merge job log).

| | run 39769627588 (before) | run 39774976109 (after) |
|---|---|---|
| Chromium: unsettled samples | 155 | 0 |
| Chromium verdict | unsettled (1476 pass, 0 fail, 431 cells not ok) | pass (504 cells, 7049 pass, 0 fail, 7 excused) |
| WebKit (Playwright, Linux): unsettled samples | 155 | 0 |
| WebKit verdict | unsettled (1476 pass, 0 fail, 360 cells not ok) | fail (6618 pass, 147 fail, 291 excused, 17 cells not ok) |
| Settle wait, arm samples waited in total (Chromium / WebKit) | 556704 ms / 610352 ms | 195104 ms / 166672 ms |

The unsettled samples are gone on both engines, and the merge verdict is no longer decided by them. The WebKit verdict now
shows what the unsettled samples were hiding: 147 failing readings, all of one item: `translate` of the `card` role of `hero.orbit`
(1060 probes, first `desk-601`) and `hero.deck` (164 probes, first `desk-319`); original `0px`, rewrite `-0.000022px -0.000015px`
(`-0.00001px -0.000008px` on the deck). This is a scroll-driven value that is not exactly zero at scroll offset 0 on WebKit with
the flag; it is a finding for `hero-exit-threaded` (accepted limit of this task), not a settle defect. Chromium has no such reading.

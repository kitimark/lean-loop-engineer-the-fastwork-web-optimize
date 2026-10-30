---
id: 2026-10-30-end-floor-dirty
kind: note
title: "end-floor-dirty: the end-of-page style recalc each frame comes from 7 elements that the main-thread scroll-driven animations (13 ViewTimeline animations of hero.exit:threaded, 1 ScrollTimeline animation of engine.scroll:unthrottle) re-dirty in every rendering update; hiding those 7 removes it"
status: draft
created: 2026-10-30
topics: [webkit, wktr, end-of-page, floor, style-recalc, scroll-driven-animations, lean]
---

# end-floor-dirty

Task `end-floor-dirty`, branch `ci/end-floor-dirty` (worktree branch `worktree-wf_d2113447-d6b-1`), follow-up of
`10-30-end-floor-probe.md`, which found one style recalc per rendering update at the end of the page and no harness cause. Question: which
element, style feature or document-level path makes `Document::needsStyleRecalc` true every frame? WKTR (Simulator
`internals`) with the threaded-animations pref OFF stands in for iOS Safari; every number is a class count, never phone time. The build
is the accel-lane build with `morph.geom:on, morph.tween:geom-timed, engine.scroll:unthrottle, hero.exit:threaded, platform:faded-pause`
(the temporary `wktr.yml` edit of pushes 2 and 3).

## Answer
- A named carrier set, not a document-level path (MEASURED, wktr run 41030064819, 3 of 3 jobs, `results/end-floor-dirty/r3/verdict.txt`).
  In the paused arm `flip-pbpd` every job reads 480 read frames at rate 100 with a dirty element in each of the 480 recalc frames and none
  without one (`of which no dirty name 0`); Lean verdict `carrier e:-|html.is-flip[0]>body[1]>div[4]` in 3 of 3 jobs (`end-floor-dirty overall
  flip-pbpd: carrier ...`). The same holds in 8 of 8 read arms of run 41022222810 (`results/end-floor-dirty/r2/verdict.txt:101-108`: dirty-read,
  timed, idle without a flip, forced flush at the rAF start and after the update, the hide and repeat arms). Push 1 (run 41016169778) had already read an empty style
  resolve (last style update size 0) in the idle arm.
- The carrier is 7 elements (MEASURED, `end-floor-dirty-anim`, r3, identical in 3 of 3 jobs): the 4 hero-deck cards, the hero copy header, the
  hero cue button, and `html.is-flip>body>div[4]`. They are dirty at the start of every rAF callback and clean after the rendering update
  (`dirty nodes per sample at rAF start` 196.62 with 7.62 elements, `after the update` 189 with 0 elements, j1). All 7 are targets of the page's
  non-document-timeline animations: `animations 49 (DocumentTimeline 35, ViewTimeline 13, ScrollTimeline 1), targets on a non-document
  timeline 7, steady dirty elements 7 of which targets 7`. The 13 ViewTimeline animations are the `hero.exit:threaded` keyframes
  (`exitCardFade`, `exitCardMove`, `exitFade`, `exitCopyUpNarrow`, `exitCueUpNarrow`, `exitBlur`, subject `hero-exit` track); the 1
  ScrollTimeline animation `fw-ut` (source `html`) is the `engine.scroll:unthrottle` animation on `div[4]`. All 14 read `finished` (names and play states read from the raw artifact of run:41030064819, wktr-jN/accel-probe-v2p-thr-off-1.json rows[rs-flip-pbpan].rs.an.els, not committed; r3/verdict.txt carries only the counts).
- Hide arm confirms the set (MEASURED, r3): hiding the 7 (`pbphides`, `elements hidden 7`) leaves 25, 30 and 26 recalcs per 576 frames, rate
  4, 5 and 4 per 100, below the band of 10: `end-floor-dirty-hide overall flip-pbphides: confirmed (jobs confirmed confirmed confirmed)`.
  Hiding only the top-named element (`pbphide`, 1 element) leaves 103, 102 and 102 per 100: `notConfirmed` in 3 of 3 jobs, as the other 6
  stay dirty. The part hide (`pbphidep`) had no part to hide (`hid -`), `unmatched`. A diagnostic hide changes the look; it is not a flag.
- The set arm records only the count of hidden elements and gives the top name to `hideVerdict` as the label of the set; that the 7 hidden elements are the 7 steady animation targets is INFERRED from the shared 90-percent rule (`mid-page.mjs:1021-1028`) and the equal counts (`steady dirty elements 7 of which targets 7`, r3/verdict.txt:64), not read.
- Not explained: 189 dirty non-element nodes persist after every update in every read arm, including the set-hide arm with no floor (r3/verdict.txt:65, `after the update 189 (elements 0, max 189)`).
- The flush arms (r2) say the recalc arises at the rendering update, not at a script flush: `flip-pbpft` and `flip-pbpfh` read 480 update
  recalcs and 0 flush recalcs per job, `arises` in 3 of 3 jobs.

## WebKit path (862f17d; INFERRED from the source, consistent with the measured order dirty-at-rAF-start, clean-after-update)
1. `Page::updateRendering` runs the Animations step before the rAF callbacks and the style update (`Page.cpp:2307-2309`).
2. `AnimationTimelinesController::updateAnimationsAndSendEvents` ticks every relevant animation of each timeline that answers `Yes`
   (`AnimationTimelinesController.cpp:128-181`). A `ScrollTimeline` or `ViewTimeline` answers `Yes` whenever its source or subject is connected
   (`ScrollTimeline.cpp:291-298`, `ViewTimeline.cpp:444-450`); a `DocumentTimeline` answers `Yes` only when a resolution was scheduled
   (`DocumentTimeline.cpp:190-197`), which is why it counts about 2 timeline invalidations per 100 frames in r3 while the scroll-driven ones tick every frame.
3. `WebAnimation::tick` calls `KeyframeEffect::animationDidTick` (`WebAnimation.cpp:1558-1582`, `KeyframeEffect.cpp:2129-2131`), which calls
   `invalidate()` (`KeyframeEffect.cpp:1731-1735`), which calls `Element::invalidateStyleForAnimation` on the target unless the document is
   inside a style recalc (`KeyframeEffect.cpp:127-135`); that is `Node::invalidateStyle(AnimationInvalid)` (`Element.cpp:2763-2767`, read from the
   pinned file, not in the sparse clone). The invalid element sets `childNeedsStyleRecalc` on its ancestors, so `Document::needsStyleRecalc`
   (`Document.cpp:3005-3023`) is true and the next style update runs `resolveStyle` once (`Document.cpp:2936`); the resolver handles the
   element as `ResolutionType::AnimationOnly` (`StyleTreeResolver.cpp:1173-1175`).
   A scroll-driven animation that is not idle stays relevant whatever its fill, because its timeline is not monotonic (`WebAnimation.cpp:1729`, `AnimationTimeline.h:56`), so a finished one is ticked every frame although its value never changes; only an idle (cancelled) one leaves the relevant set (`AnimationTimelinesController.cpp:180-181`). The about 2 timeline invalidations per 100 frames count only DocumentTimeline resolutions (`DocumentTimeline.cpp:199`, `Internals.cpp:1546-1549`), which is why push 1 read 0 while the scroll-driven ones ticked.

## One next step
A same-look fix task (name for the lead: `scrolldriven-park`): at the end-of-page state, where all 14 animations are finished, hold the
fill value as static style and park (cancel) those animations, restoring them when the scroll leaves the end range. The look is identical
if and only if the parked value equals the finished fill value; that equality is a Lean statement to prove for each of the 7 targets before the
flag exists. It is a candidate, not a result: the WKTR pref was OFF (main-thread scroll-driven animations); iOS Safari with threaded
scroll-driven animations ON may tick differently (OPEN). Restoring on scroll-out needs a main-thread scroll signal with its own cost, so the Lean statement covers both the fill equality and the restore trigger.

## Stand-ins and limits
- Lean decides carrier, documentLevel, spread, hide and flush verdicts (`lean/Fw/Device/EndFloorDirty.lean`, constants `carrierShare 90`,
  `documentShare 90`, `floorBand`); the animation facts line (`animOf`) and the page reads are TS stand-ins that count, they decide nothing.
- Document-level dirt was not read directly; the document-level verdict is carried by recalc frames with no dirty name, which is 0 in every read
  arm of r2 and r3.
- Three CI pushes used (runs 41016169778, 41022222810, 41030064819).

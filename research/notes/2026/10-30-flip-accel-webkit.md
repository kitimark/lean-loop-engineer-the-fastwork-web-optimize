---
id: 2026-10-30-flip-accel-webkit
kind: note
title: "flip-accel-webkit: the end-of-page flip already animates accelerated properties only; the accelerated-only variant is the identity, so no flag and no WKTR arm were built"
status: draft
created: 2026-10-30
topics: [webkit, end-of-page, accelerated-animation, style-recalc, lean, negative-result, premise-refuted]
---

# flip-accel-webkit

Task `flip-accel-webkit`, branch `worktree-wf_ec961771-f21-1`, no CI branch (no push was made). Premise of the task (from
`10-2x-end-floor-writes.md`): the WebKit end-of-page floor is the flip's own running tracks, so a flip that animates only
accelerated properties would cut it. Question: which animated properties of the flip can WebKit run accelerated, and is there
a same-look variant that removes the ones that cannot? Status words: CONFIRMED (source or Lean), MEASURED (earlier CI runs
cited), INFERRED.

## Answer
- The premise fails at the property level (CONFIRMED, Lean + source). The flip animates six CSS properties (`translate`,
  `scale`, `transform`, `opacity`, `filter`, `backdrop-filter`; `AnimProp`, `lean/Fw/Parts/MorphGeomAnim.lean:10-16`). WebKit
  862f17d lists all six as `animation-wrapper-acceleration: "always"` (below). No flip track animates a layout or paint
  property, so no track is forced onto the main thread by its property. Lean `FlipAccel.forcing_tracks_zero`: 0 forcing
  tracks of 43 (viewports at most 640 px wide), 51 (641 px) and 52 (from 768 px) at all 12 band viewports; golden
  `packages/contracts/golden/parts/flip-accel.jsonl` (`tracks` lines), replayed by
  `apps/site/src/parts/morph.geom/flip-accel.golden.test.ts`.
- The accelerated-only variant is the identity (CONFIRMED, Lean). `FlipAccel.accelOnly_id`: keeping only accelerated tracks
  returns the same list for every list of tracks; `same_look`: every per-frame reading of the variant equals the reading of the
  original. So same look holds for every frame, and the variant cannot change a recalc count. A flag for it would be a no-op,
  so none was added (CLAUDE.md: a refuted premise closes as a finding). The variant is not class L (no look change).
- The tracks also meet the static part of WebKit's eligibility test (CONFIRMED, Lean `static_eligible_bands`): accelerated
  property, composite `replace`, explicit keyframes at offset 0 and 1 (so no implicit keyframes). Timing functions are
  linear or cubic-bezier (the Lean `Easing` type has no steps or linear-points constructor).
- What decides a recalc per frame is runtime state, not the property list (CONFIRMED lines, INFERRED causality):
  `ticksContinuouslyWhileActive` is false only when the effect is completely accelerated and `isRunningAccelerated()`
  (`animation/KeyframeEffect.cpp:2724-2746@862f17d`), which needs a composited renderer when the Play action is recorded
  (`updateAcceleratedActions`, 2060-2071) and an effect stack that allows acceleration (`KeyframeEffectStack.cpp:215-280`).
  Until then each tick calls `invalidate()` (1731, 2129). Earlier CI runs (task `geom-pref-off-ticking`, MEASURED, notes
  `10-2x-geom-pref-off-ticking.md`): with the pref OFF the steady-state ticking set is empty (47 accelerated, 0 ticking from
  the second flip), and a transient set S1 of 21 tracks ticks until about p30 to p50 in some flips, correlated with a
  creation flush before the effects are active.
- Consequence for the floor (INFERRED, not measured here): the WKTR end-floor windows in j1 and j3 are 3 frames per rep
  (`10-2x-end-floor-writes.md`, rows.txt `wins 3 to 3`), each rep a fresh flip, so they sit inside the start-up transient, not
  the steady state. This is the reading to test next, with a window pinned by frame count (follow-up `end-floor-window` in
  the graph) plus a per-frame ticking probe from `acceleratedAnimationsForElement`; it is not a property change.

## Classification from WebKit source (CONFIRMED, WebKit@862f17d)
| property | `animation-wrapper-acceleration` (`css/CSSProperties.json`) | accelerated with the iOS pref default (threaded time-based OFF) |
|---|---|---|
| opacity | "always", line 7114 | yes |
| filter | "always", 10263 | yes |
| backdrop-filter | "always", 10639 | yes |
| transform | "always", 12112 | yes |
| translate | "always", 12260 | yes |
| scale | "always", 12281 | yes |
| rotate | "always", 12306 (not used by the flip) | yes |
| offset-path, -distance, -position, -anchor, -rotate | "threaded-only", 7004-7077 | no with the pref OFF |
| max-width, padding, width, left (layout) | no entry | no |
`CSSProperty::animationIsAccelerated` returns true for "always" and the two threaded settings for "threaded-only"
(`css/scripts/process-css-properties.py:4093-4096`); `Style::Interpolation::isAccelerated` calls it (`style/StyleInterpolation.cpp:256`);
`KeyframeEffect::computeAcceleratedPropertiesState` (`animation/KeyframeEffect.cpp:1737-1766`) turns the per-property answers into
None, Some or All. The Lean mirror is `FlipAccel.wkAlways`; the golden `css` lines pin it (layout names and `offset-path` are false).
The existing `MorphTrackAccel` module already proved the same per engine and mode (`webkit_timed_all`, golden `morph-track-accel.jsonl`);
`FlipAccel` adds the source list, the track-level static conditions and the variant.

## Same look: where it holds and where it could differ
Holds for every frame (Lean `same_look`), because the variant equals the original. The only variants that would differ are the ones
the task text named as alternatives (scale a box instead of animating its size, constant glass; graph rows `try-flip-st6`,
`try-constant-glass`): the flip no longer animates sizes, so there is nothing to convert, and those stay look-change candidates
for the user's review, unchanged by this task. No Lean model of text or border-radius under scaling was written (not needed).

## Not delivered, and why
- Flag, goldens for a flag, and the WKTR CI measurement of base against variant: not built. With the identity variant the two
  arms are the same page; a measurement would read process noise (floors move 135 to 154 by job in `end-floor-writes`). No CI push
  was made; no run id exists for this task.
- Phone: not touched (WKTR is not iOS Safari).

## Follow-ups (outside the unit)
1. `end-floor-window`: pin the frame window (already in the graph) and add a per-frame ticking probe to the end-floor harness, to
   split the transient (new tracks) from steady state. This is the test of the INFERRED reading above.
2. If the transient dominates: a start-up change (layers promoted before the push, or tracks created before the commit), not a
   property change. `geom-prewarm` tried a held tree and was parked because it moved layout; any new attempt needs its own
   same-look proof and is class L until proved.

## Lean and checks
`lean/Fw/Parts/FlipAccel.lean` (theorems `none_force`, `accelOnly_id`, `same_look`, `forcing_tracks_zero`, `static_eligible_bands`),
`FlipAccelGen.lean`, `lean/scripts/FlipAccelGolden.lean`, `check.sh` job "flip-accel golden check", trigger row in `Trigger.lean`
(lean.yml and breakpoint-gate.yml) and regenerated `triggers.jsonl`. TS: `flip-accel.golden.test.ts` checks `buildAnims` against the
golden (no TS decision logic added; no TS stand-in).

## Lesson (general)
Before building a variant, check the premise against the proved property table: a "make it accelerated" task needs a non-accelerated
track to start from. Whether an accelerated-capable effect stops ticking is decided at run time (composited renderer, effect stack),
so the next test is a per-frame ticking probe, not another property list.

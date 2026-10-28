# geom-track-style: which morph.geom WAAPI tracks run on the compositor, and which keep a style recalculation per frame

Status: finished investigation (graph r552), no site change. Claims: CONFIRMED (source or Lean), MEASURED (CI run), INFERRED.
Branch ci/geom-track-style. Lean `lean/Fw/Parts/MorphTrackAccel.lean`, golden `packages/contracts/golden/parts/morph-track-accel.jsonl`, probe
`packages/gate-breakpoints/src/track-accel{,-page}.mjs` (Chromium, `fw-track-accel`), `packages/measure-wktr/src/accel-{cli,page}.mjs` (WebKit).
Runs: push 1 (7a177f5f4) breakpoint-gate 40611977476, wktr 40611977559; push 2 (1b00b7447) lean 40616651280, breakpoint-gate 40616651357
(track-accel r1, r2, r3 on separate jobs, all success), wktr 40616651419 (j1, j2, j3 success). The flip-cell playwright-webkit morph.geom:on failure
in 40611977476 is the same flake geom-style-cut saw; it is not part of this unit.

## Question and unit
geom:on makes 55 WAAPI tracks (43 in the Lean sample at 390, 52 at 768 and 1440, plus image rows beyond it). `scrubbed` creates them paused and writes
`currentTime` per frame; `geom-timed` (morph.tween:geom-timed) creates them running with one `startTime` write, 680 ms. Unit: per track group and engine,
compositor or main thread, why, and who keeps a style recalculation per frame.

## The Lean predicate (CONFIRMED, proved)
`onCompositorTrack eng mode v a` has three gates, one theorem per branch:
- play state: only a Running animation is composited, both engines (`scrubbed_track_never`: scrubbed puts 0 tracks on the compositor);
- property (Chromium only): `filter` (blur) moves pixels, so it stays on main; the other five pass; WebKit accelerates all six (`webkit_timed_track_all`);
- constant (Chromium only, found in push 1): constant keyframes give `kAnimationHasNoVisibleChange`; exactly one such track per band, column:0 `translate`
  (`constant_bands`). `chromium_timed_track_iff`: on compositor iff prop is not blur and not constant. Main-thread tracks: 3 at <=720, 4 above (`chromium_timed_track_main_bands`), 0 on WebKit.
Not modelled: the unpainted-target check (below).

## Verdict per track, per engine (MEASURED against the Lean predicate)
| Group (tracks, 1440) | Chromium scrubbed | Chromium timed | WebKit scrubbed | WebKit timed |
|---|---|---|---|---|
| transform (26: images 21, K0, U, lang, panel, veil) | main (paused) | compositor | not accelerated (paused) | accelerated (18 of 26 in the one running readout) |
| translate (22) | main (paused) | compositor, except column:0 | idem | accelerated (20 of 20, 402 px) |
| opacity (4), scale (2), backdrop-filter (1) | main (paused) | compositor | idem | accelerated (all, 402 px) |
| filter (3: earn, panel, platform; 2 at 390) | main (paused) | MAIN: `filter-moves-pixels` | idem | accelerated (2 of 2, 402 px) |
| column:0 translate (1) | main (paused) | MAIN: `no-visible-change` | idem | idem |
| image transform, 8 of 12 beyond the sample at 390 | main (paused) | MAIN: `target-invalid-compositing-state+no-visible-change` | idem | idem |
Chromium, 3 reps x 3 bands (judge ok true in all 9 timed cells; scrubbed: 0 failures named, 0 cc starts added): the failure bits come from the trace
"Animation" `compositeFailed` events; a success writes none, so success is read from cc `KeyframeModel` BEGIN counts. Source: Chromium
compositor_animations.cc:491 (CompositorPropertyAnimationsHaveNoEffect, unpainted target), animation.cc:3376 (TimeToEffectChange), pinned chromium@f842f52.
The 8 hidden image tracks at 390 are not in the Lean sample (judged apart as `extra`).
WebKit (source: KeyframeEffect.cpp:1965-2035@862f17d `canBeAccelerated`, no property rule for these six; WebAnimation play state): accepted limit, there is no
per-animation readout on CI. WKTR `internals.acceleratedAnimationsForElement` is per element. Scrubbed (j1, j2, j3): 55 of 55 paused, accel false for all
(MEASURED, matches the play-state gate). Timed (j1, j2, j3; arms all and all-again; width 402): at creation 55 running, accel 0 (not styled yet); at the first frame
(294-524 ms later, the slow frame clock) 5 of 6 readouts see playState idle on all 55 (INFERRED: the driver's `settle` cancels the tracks, geom-timed.driver.ts:47-50 and 83-86) with
elements still reading accelerated in part (transform 3-13 of 26, translate 9-11 of 20, filter 1-2 of 2). One readout (j3 all-again, 294 ms) catches all 55 still running:
translate 20/20, opacity 4/4, filter 2/2, scale 2/2, backdrop-filter 1/1, transform 18/26; the 8 transforms not accelerated match the 8 hidden image tracks Chromium names at 390.
So WebKit accelerates the filter tracks Chromium cannot (MEASURED, one readout, element level; track level INFERRED). WebKit style recalcs per frame are 2.0 in every arm including idle (scrubbed j1 all 2.97): the count cannot attribute
a group; per-frame ms there is frame time, not style time. Phone not measured.

## Per-frame style work in Chromium (MEASURED, 3 reps, min-max over reps, CI Linux, not phone time)
Timed flip, elements per frame (ms per frame in brackets):
| arm | 390 | 768 | 1440 |
|---|---|---|---|
| all tracks | 42-48 (0.7-1.0) | 85-96 (1.8-2.1) | 84-92 (1.9-2.1) |
| translate paused | 35-36 (0.7) | 61 (1.1-1.2) | 53-54 (0.9-1.1) |
| transform paused | 36-37 (0.7-0.8) | 58-61 (1.1-1.4) | 45-50 (0.9-1.1) |
| scale, opacity, filter, backdrop paused | 43-56 | 92-131 | 78-102 (no cut) |
| none (all held) | 15-20 (0.4-0.5) | 45-53 (1.0-1.3) | 49-54 (1.2) |
| idle | 5 (0.1) | 12-13 (0.3) | 5 (0.1-0.2) |
Recalcs per frame are 0.95-1.2 in every arm: the count never moves, only elements and ms. Scrubbed sweep (390 / 768 / 1440): all 50 / 69-71 / 62, translate paused 33 / 55-63 / 43,
transform paused 34 / 45-46 / 38, none 10 / 19-38 / 12.
The tracks account for about 27 (390) to 40 (768, 1440) elements per frame, about 0.4 to 0.9 ms per frame; only the translate and transform groups matter, the
other four properties are inside the noise.
Reason (invalidationTracking, MEASURED): in the timed flip every extra recalc is `StyleRecalc:Animation`, on the track targets: per frame at 1440 IMG 20, plain DIV 8.6, column DIV 4.8,
track DIV 2 (all) against IMG 0, DIV 0, column 0 with all tracks held; paused-translate removes the column and half of the DIV, paused-transform removes every IMG. These nodes are tracks that cc started on the compositor,
so compositing does not stop the main-thread invalidation.
Mechanism (INFERRED from source, chromium@f842f52): `Animation::Update` returns `!inactive_ || TimeToEffectChange()` (animation.cc:3342), so a running animation stays in
`animations_needing_update_` while it is current; each frame `AnimationEffect::UpdateInheritedTime` sees a new time (animation_effect.cc:330) and `KeyframeEffect::ApplyEffects`
re-samples and calls `SetNeedsAnimationStyleRecalc` when the sample changed (keyframe_effect.cc:741). `TimeToEffectChange`'s compositor skip (animation.cc:3391) only decides the extra wake-up
request, not this update. Held (paused or scrubbed-ignored) tracks keep a constant time and cause none.

## Tracks that keep main-thread style per frame
- Scrubbed: all 55 (paused, driver writes `currentTime`): ~1.0 recalc and 50-62 elements per frame, 33-34 of them from the translate and transform groups.
- Timed on Chromium: every running track target still gets a per-frame `Animation` invalidation; the tracks off the compositor (filter, column:0 translate, hidden images at 390) additionally run their effect on the main thread.
- The biggest single group is the 21 image transforms (IMG 20 of ~42 `Animation` invalidations per frame at 1440).

## Proposed same-look fix task: geom-image-column-scale (INFERRED)
Replace the 21 per-image `transform` tracks with the scale already shared by each column: image i,j has `translateY((s-1)*y) scale(s)` (tracks.ts:170), which is exactly `scale(s)` of its column about the
column origin (a point at y maps to s*y). Animate the 3-5 column elements (already targets of their `translate` track) with an independent `scale` property track instead; the individual transform properties compose as translate, then scale, the same order the parent transform gave the images. Lean first: prove the image matrix equals the column composition per band; golden-check tracks.ts.
Effect, INFERRED: removes up to 21 animation targets and their `Animation` invalidations; bound = the paused-transform arm: elements per frame 390 -5 to -12, 768 -27 to -38, 1440 -34 to -47, ms per frame about -0.9 at 768 and 1440 on CI Linux, measured as the paused-transform drop which also holds 5 non-image transforms (upper bound). The compositor side gains nothing (images are already composited at 768 and 1440). Open: whether the layer count rises (GPU memory trade is accepted).
Engine file:line: keyframe_effect.cc:741, animation.cc:3342, animation_effect.cc:330@chromium f842f52. WebKit unknown: its recalc count cannot show it.

## Follow-ups, not in this unit
- Prune tracks with no visible change (column:0 translate) and unpainted images: INFERRED nil on style cost (no sampled effect), saves only creation work.
- A WebKit per-animation readout (needs `internals` per effect) would turn the WebKit column from element level to track level.
- Why the first-frame playState is idle on WebKit (the driver's settle cancel) and whether a mid-tween readout shows all six accelerated.

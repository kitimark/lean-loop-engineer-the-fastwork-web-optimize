# geom-track-style: which morph.geom WAAPI tracks run on the compositor, and which keep a style recalculation per frame

Status: finished investigation (graph r552), no site change. Claims: CONFIRMED (source or Lean), MEASURED (CI run), INFERRED.
Branch ci/geom-track-style. Lean `lean/Fw/Parts/MorphTrackAccel.lean`, golden `packages/contracts/golden/parts/morph-track-accel.jsonl`, probe
`packages/gate-breakpoints/src/track-accel{,-page}.mjs` (Chromium, `fw-track-accel`), `packages/measure-wktr/src/accel-{cli,page}.mjs` (WebKit).
Runs: push 1 (7a177f5f4) breakpoint-gate 40611977476, wktr 40611977559; push 2 (1b00b7447) lean 40616651280, breakpoint-gate 40616651357
(track-accel r1, r2, r3 on separate jobs, all success), wktr 40616651419 (j1, j2, j3 success). flip-cell playwright-webkit (morph.geom:on) failed on both pushes: 40611977476 at 360x640 and 640x1000 (7 of 48), 40616651357 at 640x1000 m=0..0.5 (3 of 48; columns 0 of 3, images 0 of 13). Cause unknown; it is not the geom-style-cut A4 failure; this branch changes no site or flip-cell code. Follow-up: rerun on main to tell a flake from a pattern.

## Question and unit
geom:on makes 55 WAAPI tracks at 390 and 58 at 768 and 1440 (Lean sample 43 and 52; the rest are image rows beyond it). `scrubbed` creates them paused and writes
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

## Style work per flip in Chromium (MEASURED, 3 reps on separate jobs, min-max over reps, CI Linux, not phone time)
Round 1 divided elements by main-thread frames. That is wrong as a comparison: the frames in the window differ about 4x between arms, so a per-frame figure
compares different numbers of frames. The decision figure is the total over the flip window. Rule (Lean `MorphTrackAccel`, `counted`, `flipTotal`): window =
the page marks `fwx:<arm>:flip:start|end` on the renderer main thread, both ends included; a record counts iff it is `UpdateLayoutTree` (or `RecalculateStyles`)
on that thread inside the window. `frames` = the page's rAF count in the window; `elements` and `ms` = sums over the counted records. Reduction `windowsOf`/`armSummary`
in `track-accel.mjs` (TS stand-in, no golden). Re-derived from the artifacts of run 40616651357 (track-accel r1..r3; r1/r2 at 1440:
all 7-8 frames, 641-702 elements, 14.6-15.6 ms; transform paused 31 frames, 1514-1546, 28.5-33.4 ms; translate paused 28-31 frames, 1515-1678, 24.9-33.9 ms; r3 adds 585 elements, 13.7 ms to `all` and 1353, 27.3 ms to transform paused).

390 px (flip window 560-650 ms):
| arm | frames | elements per flip | recalc ms per flip | elements per recalc (the round-1 "per frame" figure) |
|---|---|---|---|---|
| all tracks | 22-27 | 980-1252 | 18.9-25.0 | 44-50 |
| translate paused | 34-35 | 1212-1241 | 23.4-25.2 | 37 |
| scale paused | 22-26 | 1147-1312 | 22.7-24.0 | 48-55 |
| transform paused | 34-35 | 1247-1267 | 23.1-26.2 | 37-38 |
| opacity paused | 21-25 | 1069-1286 | 19.3-27.5 | 45-58 |
| filter paused | 23-26 | 1029-1404 | 19.8-28.3 | 47-59 |
| backdrop paused | 20-22 | 903-1198 | 17.2-25.9 | 48-57 |
| none (all held) | 27-30 | 428-558 | 11.1-14.5 | 16-21 |
| idle (no tracks) | 34 | 165 | 4.1-5.0 | 5 |
| all again | 23-26 | 1138-1196 | 20.4-23.5 | 46-52 |

768 px (flip window 560-650 ms):
| arm | frames | elements per flip | recalc ms per flip | elements per recalc (the round-1 "per frame" figure) |
|---|---|---|---|---|
| all tracks | 12-14 | 1022-1279 | 21.2-26.5 | 85-96 |
| translate paused | 31-32 | 1887-1936 | 34.3-39.4 | 61 |
| scale paused | 11-14 | 1216-1410 | 26.8-30.4 | 88-94 |
| transform paused | 32-33 | 1899-1967 | 34.8-45.6 | 58-61 |
| opacity paused | 12-14 | 1128-1349 | 22.4-26.4 | 92-96 |
| filter paused | 11-13 | 1136-1275 | 24.1-28.6 | 98-103 |
| backdrop paused | 11-13 | 1279-1577 | 33.5-43.6 | 98-105 |
| none (all held) | 16-18 | 777-855 | 16.9-20.5 | 47-53 |
| idle (no tracks) | 32-35 | 408-457 | 8.4-9.1 | 12-13 |
| all again | 12-13 | 1015-1108 | 20.8-21.1 | 85-92 |

1440 px (flip window 560-650 ms):
| arm | frames | elements per flip | recalc ms per flip | elements per recalc (the round-1 "per frame" figure) |
|---|---|---|---|---|
| all tracks | 7-8 | 585-702 | 13.7-15.6 | 88-98 |
| translate paused | 28-31 | 1515-1678 | 24.9-33.9 | 53-54 |
| scale paused | 8 | 695 | 15.0-18.3 | 87 |
| transform paused | 30-31 | 1353-1546 | 27.3-33.4 | 48-50 |
| opacity paused | 8-9 | 698-882 | 14.6-17.9 | 87-98 |
| filter paused | 8-9 | 700-818 | 14.4-18.2 | 88-102 |
| backdrop paused | 8 | 693-811 | 14.2-17.7 | 87-101 |
| none (all held) | 10-12 | 505-644 | 11.7-14.4 | 49-54 |
| idle (no tracks) | 27-34 | 130-165 | 3.6-4.7 | 5 |
| all again | 7-9 | 762-879 | 17.3-18.2 | 98-109 |

Reading (1440 and 768): with all 55 tracks running, Chromium ticks the main thread about 4x less often at 1440 (7-8 frames against 28-31) and about 2.5x less often at 768 (12-14 against 31-33), and the style work per flip is
below the transform-paused arm: 585-702 elements and 13.7-15.6 ms against 1353-1546 and 27.3-33.4 ms with the transform tracks paused (1440). At 390 the two overlap
(`all` 980-1252 elements, 18.9-25.0 ms; transform paused 1247-1267, 23.1-26.2 ms; frames 22-27 against 34-35). Pausing scale, opacity, filter or backdrop keeps the frame count low (8-14 frames); their totals are at or above `all` (at 768 backdrop paused 33.5-43.6 ms and scale paused 26.8-30.4 ms against 21.2-26.5). `all` is lowest or tied within the rep spread; Lean proves it against transform paused only; pausing translate or
transform lifts it to the idle cadence (26-34 frames) and the totals double. The tracks themselves add little per flip over `none` (all held): 1440 -3 to +120 elements and +0.5 to +2.1 ms; 768 +167 to +473 and +0.7 to +9.2 ms; 390 +552 to +694 and +7.8 to +10.5 ms (all minus none, same repetition). Lean proves the verdict (`no_fold_reason_any_band`: no band has a reason to fold; `all_lowest_wide`: at 768 and 1440 every `all` repetition is below every transform-paused one in elements and ms;
`all_not_lowest_390`, `frames_differ_wide`).
The old per-frame figures (84-92 against 45-54 elements, round 1) are real per recalculation, but a main frame is rarer when the tracks run, so they do not add up to more work per flip.

Mechanism for the lower frame count (re-checked): `Animation::TimeToEffectChange` returns `AnimationTimeDelta()` (wake on the next frame) only when `!HasActiveAnimationsOnCompositor() && !animation_has_no_effect_ && phase == Active`, otherwise the time to the effect's end
(animation.cc:3376-3399@f842f52; the compositor skip is :3389-3394), and `DocumentTimeline::ScheduleNextService` takes the minimum over `animations_needing_update_` (document_timeline.cc:111-132). So a composited track asks for no extra frame. That
explains why running tracks add no wake-ups; it does not explain why `all` has fewer frames than `none` or idle, for two reasons: (a) the probe's own rAF loop (`windowFrames`, track-accel-page.mjs:100-116) requests a frame every vsync in every arm, (b) the 3-4 main-thread tracks (filter, column:0)
sit in `all` and in the 7-frame arms alike, and removing them (`no-filter`: 8-9 frames) changes nothing. The main thread is idle between the frames (summed counted work in `all` at 1440: Paint 27 ms, Commit 4 ms, recalc 14.6 ms in a 600 ms window). INFERRED, not shown: the frame is delivered later,
because the compositor (software GL on CI Linux) is busy ticking the cc animations (69 cc starts counted in the arm at 1440) and producing frames; the exact gate is not isolated, trace events beyond the work slices were not kept. So the 4x is MEASURED, the TimeToEffectChange skip is a CONFIRMED cause of "no extra wake-ups", and the cadence cause is INFERRED. Whether a phone-class display, which runs a real 60 Hz vsync, sees the same
cadence is unknown; at a fixed 60 Hz cadence the per-recalculation figures would apply (tracks add about 35-45 elements and 0.4-0.9 ms per recalculation at 768 and 1440, round 1).

Reason (invalidationTracking, MEASURED, round 1): in the timed flip every extra recalc is `StyleRecalc:Animation`, on the track targets: per recalc at 1440 IMG 20, plain DIV 8.6, column DIV 4.8,
track DIV 2 (all) against IMG 0, DIV 0, column 0 with all tracks held. These nodes are tracks that cc started on the compositor, so compositing does not stop the main-thread invalidation
(`Animation::Update` returns `!inactive_ || TimeToEffectChange()`, animation.cc:3342; `AnimationEffect::UpdateInheritedTime` animation_effect.cc:330; `KeyframeEffect::ApplyEffects` keyframe_effect.cc:741, INFERRED).

## Tracks that keep main-thread style per frame
- Scrubbed: all 55 (paused, driver writes `currentTime`): ~1.0 recalc and 50-62 elements per frame, 33-34 of them from the translate and transform groups (here the window is a pinned number of frames, so per frame is comparable; 390 / 768 / 1440: all 50 / 69-71 / 62, translate paused 33 / 55-63 / 43, transform paused 34 / 45-46 / 38, none 10 / 19-38 / 12, round 1).
- Timed on Chromium: every running track target still gets a per-frame `Animation` invalidation; the tracks off the compositor (filter, column:0 translate, hidden images at 390) additionally run their effect on the main thread.
- The biggest single group is the 21 image transforms (IMG 20 of ~42 `Animation` invalidations per recalculation at 1440); per flip this does not make the transform arm costlier than the paused one (see above).

## Next step (derived from the per-flip totals)
Chromium: the data gives no style-work reason to fold the 21 image transforms into a column scale (`geom-image-column-scale`, round 1's proposal is withdrawn). At 768 and 1440 the arm with the transform tracks paused does more work per flip than `all`
(frames 4x more, totals 2x), and at 390 it is equal within the spread. Folding removes up to 21 targets per recalculation (40-ish elements) but cannot change the cadence that sets the total. No fix task for Chromium.

WebKit (the phone, `phone-flip-p95`: geom-timed 348 of 396 long frames carry RecalculateStyles on the iPhone): what the Chromium result implies. WebKit has the same two-part rule in source (862f17d): `WebAnimation::timeToNextTick` returns infinity unless Running (WebAnimation.cpp:1917-1929) and
`AnimationEffect::timeToNextTick` returns `endTime - localTime` in the active phase unless `ticksContinuouslyWhileActive()` (AnimationEffect.cpp:385-396); `KeyframeEffect::ticksContinuouslyWhileActive` is false when the effect is completely accelerated and running accelerated, or when its target has no renderer (KeyframeEffect.cpp:2724-2744);
`DocumentTimeline::scheduleNextTick` then schedules a one-shot at that delay instead of a resolution now (DocumentTimeline.cpp:382-398); and "when using accelerated effects, we may not update animations in WebCore" (KeyframeEffect.cpp:1820-1824). All six geom properties are accelerated (`AcceleratedProperties::All`, :1764-1768). So by source, a running accelerated geom track
asks WebKit for no per-frame tick and no per-frame style; unlike Chromium there is no `StyleRecalc:Animation` per frame for composited tracks to model. The 348 of 396 long frames therefore do not follow from the 55 tracks if they run accelerated, and the WebKit-specific question is: which of the tracks are rendered but not
running accelerated during the flip on the phone (a `Failed`/`Prevented` start, `KeyframeEffect.cpp:2057,2115`, or a mid-flip `UpdateProperties`/`transformRelatedPropertyDidChange` restart, KeyframeEffectStack.cpp:171), since each of those ticks every frame, and what else writes style each frame (the scripted tween, the sweep). CI cannot answer it: the WKTR readout is per element, and 5 of 6 readouts see the tracks idle after the driver's settle cancel.
Proposed next task `geom-webkit-midflip` (WKTR, no phone): read `acceleratedAnimationsForElement` and `playState` mid-flip with the settle cancel after the readout (all 55 running, 3 repetitions), per track group, next to a style-recalc time per frame, and compare the arms with the translate group and the transform group held, on the same page; a phone run (user-booked) only if WKTR shows all rendered tracks accelerated and the recalcs persist, which would point at the non-WAAPI per-frame writes and not at the tracks.

## Follow-ups, not in this unit
- Prune tracks with no visible change (column:0 translate) and unpainted images: INFERRED nil on style cost (no sampled effect), saves only creation work.
- A WebKit per-animation readout (needs `internals` per effect) would turn the WebKit column from element level to track level.
- Why the first-frame playState is idle on WebKit (the driver's settle cancel) and whether a mid-tween readout shows all six accelerated.
- Rerun flip-cell playwright-webkit (morph.geom:on) on main to tell a flake from a pattern (see Runs).
- The pooled per-property judge (per track key instead of pooled per property).

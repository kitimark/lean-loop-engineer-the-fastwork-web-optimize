---
id: 2026-10-30-end-floor-window
kind: note
title: "end-floor-window: with equal 48-frame windows every arm reads 102 recalcs per 100 frames in 3 of 3 jobs, and no tracked animation ticks or is accelerated in any frame"
status: draft
created: 2026-10-30
topics: [webkit, wktr, end-of-page, floor, style-recalc, animation-tick, lean, negative-result]
---

# end-floor-window

Task `end-floor-window`, branch `ci/end-floor-window` (worktree branch `worktree-wf_46680abc-c16-1`), follow-up of
`10-2x-end-floor-writes.md`. Unit of decision: every arm reads the same number of frames (a frame-count-pinned window), each frame
carries a tick probe, and Lean decides per arm whether the window holds a transient or a steady animation state. WKTR (Simulator
`internals.styleRecalcCount`) stands in for iOS Safari; the numbers are class counts per 100 frames, never phone time.

## Answer
- Pinned windows work (MEASURED, wktr run 40989068304, push 1 at 72f68bb66, 3 of 3 jobs): all 30 rows of
  `results/end-floor-window/r1/rows.txt` read `frames 576` (12 reps of 48), `wins 48 to 48`, `pin pinned (12 reps)`. Frames per arm are
  equal (the previous run's j2 windows ran 245 to 531 frames).
- Every arm reads the same rate (MEASURED): `rate 102 per 100 frames` in 30 of 30 rows, `r=0 0` and `r=1 564` in 30 of 30. `verdict.txt`:
  floor 102, arm 102, reference 102, cut 0 in 21 of 21 arm lines (3 jobs x 7 writer sets), each `verdict no writes`, finding
  `no writes` in j1, j2, j3 and overall. The earlier j2 spread (results/end-floor-writes/r3/verdict.txt: floor 154, cuts 7 to 27 over
  qstyle, qpanel, qdata and qpub, qwrite 40, with arm windows of 251 to 448 frames against a floor of 531) was a window effect, not a
  writer (INFERRED: the pinned run reads cut 0 for the same arms in all 3 jobs).
- The recalcs above 100 come from the 12 first frames (MEASURED, read from the result files): in every row the 12 frames not at `r=1` are
  the first frame of each rep. Each has 2 or 3 recalcs, and 1 or 2 of them land before the frame callback (`p`). 17 of 30 rows read 12
  frames at 2 (588 recalcs per 576 frames); 13 rows have 1 to 4 first frames at 3 (589 to 592). All round to 102 per 100 frames.
- No tracked animation ticks or is accelerated in any sampled frame (MEASURED): all 30 rows read `class empty`, `rep classes empty`,
  `frames ticking 0 quiet 0 idle 576`, `accelerated tracks at first frame 0 to 0`, `first-frame phase 9000 to 9000 per mille`. The Lean
  verdict per arm and per job is `empty` (`end-floor-window overall v2p <arm>: empty (jobs empty empty empty)` for nat, pall[0], pall[1],
  qstyle, qdata, qpub, qclass, qpanel, qplat, qwrite). The transient-vs-steady question has no answer in this window because the tracks
  are idle before the first sampled frame; it is not a "steady" verdict.
- Consequence (INFERRED, with the earlier engine-internal note `10-2x-geom-recalc-source.md`): the floor of one recalc per frame is not
  carried by the flip tracks in the sampled frames and no page writer carries it; no same-look lever exists in this lane. No flag was
  changed.

## What each probe signal reports (WebKit 862f17d)
- `m` (ticking now), `q` (ticks later), `d` (never ticks) come from `internals.timeToNextAnimationTick` (`Internals.cpp:1552-1555`), which
  returns `WebAnimation::timeToNextTick` (`WebAnimation.cpp:1917-1929`): 0 while pending, infinity when not running or at rate 0, else the
  effect's time to the next tick (`AnimationEffect.cpp:385-410`: before phase = time to the active phase; active = 0 for an effect that ticks
  continuously, else the time to the end; after phase = infinity). Page code: `tkRead`, `packages/measure-wktr/src/mid-page.mjs:588-603`.
  Class per frame: `m > 0` ticking, else `q > 0` quiet, else idle (`Fw.Device.EndFloorWindow.Tick.cls`).
- `a` (accelerated tracks) counts created tracks whose property is in `internals.acceleratedAnimationsForElement` for the track's element
  (`Internals.cpp:1534-1546`, the timelines controller's accelerated list). Every sampled frame reads `[m,q,d,a] = [0,0,55,0]`
  (all 17280 frames of the 30 rows, read from the result files): 55 created tracks, all `d`. Because `d` is infinity, `a` of 0 says nothing about whether
  a running track would be accelerated; those tracks were not running.
- `h` (phase per mille) is page-side, not WebKit: `rsWindow` (`mid-page.mjs:610-617`) returns 9 (`9000` per mille) when the reference
  track's `playState` is `idle`, otherwise the track's `currentTime` over the 680 ms duration. Reading 9000 in the first frame of all 360 reps
  means the reference track was idle (cancelled: an ended track reads `finished` and would report its currentTime, not 9000) before the window's first frame.
- `t` is the frame time from the window start; `window ms` in rows.txt is the last frame's `t`: 884 to 1300 over the 30 rows.

## The Lean parts
- Window rule `Fw.Device.EndFloorWindow` (`lean/Fw/Device/EndFloorWindow.lean`): `window_reads_pinN` (the page loop stops at exactly 48
  frames, :35), `pinned_equal` (two pinned arms read equal frame sums, :86), `legacy_windows_unpinned` (the old 3-frame windows are
  `unpinned`, :89). Per-rep class: one theorem per branch, `repClass_empty` (:151) to `repClass_transient` (:169), `armVerdict_alike`,
  `armVerdict_mixed`, `armVerdict_unread` (:213-222). Golden `packages/contracts/golden/device/end-floor-window.jsonl`, replayed by
  `packages/measure-wktr/test/end-floor-window.test.mjs`. The TS port `end-floor-window.mjs` is checked against that golden;
  `end-floor-rows.mjs` is an unproved formatting stand-in (frame counts from `end-floor.mjs`).
- The two `canBeAccelerated` conditions FlipAccel left unmodelled, over the keyframes the geom-timed driver plays
  (`lean/Fw/Parts/FlipAccelRun.lean`): the discrete transform interval needs a `matrix` or `matrix3d` function
  (`BlendingKeyframes.cpp:397-398`, `StyleTransformList.cpp:66-69`, `KeyframeEffect.cpp:1990`; `discrete_needs_matrix`, `no_played_matrix`: the
  played keyframes hold `translate` and `scale` only); the cascade override needs an author `!important` declaration on an accelerated
  property (`KeyframeEffect.cpp:1978`, `KeyframeEffectStack.cpp:306-320`; the flip's declarations are nav `backdrop-filter` and earn
  `transform`). `unmodelled_bands` proves that no played track at the band widths is hit by either, on both engines. Golden
  `packages/contracts/golden/parts/flip-accel-run.jsonl`, replayed by `apps/site/src/parts/morph.geom/flip-accel-run.golden.test.ts`.
  So neither condition explains `a = 0`; the tracks were idle (above).

## Limits and next candidate
- WKTR stands in for iOS Safari; the user's captured phone session is the device check. Only 1 of 3 allowed pushes was used.
- Not measured: why the reference track is idle at the first sampled frame (the first frame arrives late in WKTR, and the geom-timed driver
  cancels its tracks, `apps/site/src/parts/morph.tween/geom-timed.driver.ts:48-51`). The window therefore reads the settled floor, not the
  flip. Next candidate, a measurement and not a flag: read `tkRead` and each track's `playState` once right after the tracks exist, before
  the first window frame, and every few frames after, to see when the tracks leave the running state. Its Lean statement is the existing
  `repClass_transient` (a rep with ticking frames then only quiet frames and no later recalc), which this run never reaches. A lever would
  exist only if that read shows running tracks whose recalcs outlast the flip.
- `floor-fp-thr-off` is removed (its build config was never run); the SETS list is `v2p` only.

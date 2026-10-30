---
id: 2026-10-30-end-floor-writes
kind: note
title: "end-floor-writes: no page writer is dominant for the WebKit end-of-page floor in 3 of 3 jobs; every frame of the r3 windows holds at least one style recalc"
status: draft
created: 2026-10-30
topics: [webkit, wktr, end-of-page, floor, style-recalc, faded-pause, lean, negative-result]
---

# end-floor-writes

Task `end-floor-writes`, branch `ci/end-floor-writes` (worktree branch `worktree-wf_1aa4afc3-45b-1`). Question: after
`platform:faded-pause` the WKTR end-of-page flip sits near the all-paused floor (`10-2x-end-wktr-flip.md`,
`10-2x-faded-pause-entry.md`); which page writer (nav inline style, `data-fw-morph`, class toggles, panel, platform) carries
that floor? Unit of decision: one writer silenced in turn on top of the all-paused arm, judged per CI job by
`Fw.Device.EndFloor.judge`; a writer is dominant when its cut is over half the floor (`Entry.dominant`). WKTR (Simulator
`internals.styleRecalcCount`) stands in for iOS Safari; the numbers are class counts per 100 frames, never phone time.
Every number below is a `verdict.txt` value, a `rows.txt` cell, a named difference or "a of b" of cells, a range of named cells,
a code constant with file:line, or a run id, sha or count of jobs, rows and arms.

## Answer
- No page writer is dominant in 3 of 3 jobs. `results/end-floor-writes/r3/verdict.txt` finding lines: j1 `no writes`, j2 `spread over
  writers`, j3 `no writes`; the overall class is `mixed`. No same-look cut was built: the deliverable is conditional on one writer
  carrying most of the floor.
- `rs-flip-qwrite` silences the six listed writer sets at once (verdict lines, floor and arm per 100 frames):
  j1 floor 138, arm 133, `no writes`; j3 floor 135, arm 135, `no writes`; j2 floor 154, arm 114, cut 40, `carries`. The
  cut in j2 is spread over publish (cut 27), data (21), panel (20) and style (7), each judged `carries`; class is `no effect` and
  platform `raises`. The j2 verdict cuts are not comparable across arms (the window text below; its cause is INFERRED).
- Every row of the r3 run has no frame without a recalc: the `r=0` column of `results/end-floor-writes/r3/rows.txt` is 0 in all 30 rows
  (3 jobs, 10 rows each). The recalc needs no recorded write: in `rs-flip-qwrite` (the arm that records mutations) the `frames without
  mut: key` cell equals the `frames` cell in j1 (rows[8]) and j3 (rows[8]); in j2 rows[8] it is 432 of 448 frames, and the
  other frames carry `mut:platform#data-fw-scene`, which is in no silenced set. The natural and all-paused arms
  (`rs-flip-nat`, `rs-flip-pall`) do not record mutations (`rec`, `packages/measure-wktr/src/mid-page.mjs:589`), so their `mut:` cells say
  nothing about writes. The q arms do record: j2 rows[2] `rs-flip-qstyle` has 265 frames, 201 without a `mut:` key, and a
  `mut:nav#data-fw-morph` count of 64 (it silences only the nav inline style). Lean: `rate_one_per_frame`
  (`lean/Fw/Device/EndFloor.lean:204`, a window whose frames each hold a recalc reads at least 100 per 100 frames; arithmetic only).
- INFERRED, not measured per track: the recalcs in frames without a recorded mutation come from the running flip tracks.

## Numbers (per 100 frames, wktr run 40960310474, push 3 at 104183cb1)
Source: `results/end-floor-writes/r3/verdict.txt` (made by `node packages/measure-wktr/src/end-floor-cli.mjs
wktr-j1 wktr-j2 wktr-j3 --out verdict.txt`) and `results/end-floor-writes/r3/rows.txt`. Regenerate rows.txt (byte-equal, checked by
`packages/measure-wktr/test/end-floor-rows.test.mjs`) with
`node packages/measure-wktr/src/end-floor-rows.mjs results/end-floor-writes/r3 --out results/end-floor-writes/r3/rows.txt`
(same command with `r1` and `r2`; for the lane comparison `node packages/measure-wktr/src/end-floor-rows.mjs results/end-wktr-flip/r1 --out results/end-floor-writes/end-wktr-flip-r1-rows.txt`); `end-floor-rows.mjs` is an unproved TS stand-in (frame and key counts; `rate` is
imported from `end-floor.mjs`, which the Lean golden checks). Floor = pooled `rs-flip-pall` read before and after the writer arms (rows[1]
and rows[9]); reference = `rs-flip-qwrite`; mode `floor-v2p-thr-off` (v2-proved + morph.geom:on, morph.tween:geom-timed, WKTR pref off), reps per
arm `rsReps` (`packages/measure-wktr/src/end-floor.mjs:20`).

| arm | j1 | j2 | j3 |
|---|---|---|---|
| floor (pooled pall) | 138 | 154 | 135 |
| qstyle (nav inline style) | 135 | 147 | 133 |
| qdata (data-fw-morph) | 135 | 133 | 137 |
| qpub (style + data) | 135 | 127 | 135 |
| qclass (nav class, tabindex, aria) | 135 | 156 | 135 |
| qpanel (morph panel) | 137 | 134 | 133 |
| qplat (platform style) | 133 | 157 | 133 |
| qwrite (all six listed sets) | 133 | 114 | 135 |
| natural page | 135 | 160 | 133 |
| frames, floor (pall x2) | 96 | 531 | 96 |
| frames, qwrite (reference) | 48 | 448 | 48 |

Verdicts per job (verdict.txt): j1 and j3 `no writes` for all seven arms. j2 `carries` for qstyle, qdata, qpub, qpanel and
qwrite, `no effect` for qclass, `raises` for qplat.

- The per-frame recalc counts are in rows.txt (`frames`, `r=0`, `r=1` columns); no pattern across rows is restated here.
- j1 and j3: every row has `wins 3 to 3` (each rep window is 3 frames) and the same frame count (48). Frames minus `r=1`
  frames is 16 in rows[8] and rows[9] of both jobs, the same count as the reps; since `r=0` is 0, those frames hold more than one recalc.
  INFERRED reading: one extra recalc frame per rep, the frame a new track becomes ready (`animationBecameReady`, below).
- j2: the window is long and unequal across arms (rows.txt `frames`: pall rows[1] 267 and rows[9] 264, qwrite rows[8] 448, qdata
  rows[3] 425, qpub rows[4] 405, qpanel rows[6] 419, qstyle rows[2] 265, qclass rows[5] 251, qplat rows[7] 254, nat rows[0] 245;
  `wins`: pall rows[1] 15 to 18, qwrite rows[8] 26 to 29). INFERRED, not shown: muting data-fw-morph and class changes how long the
  flip lives, so the j2 arms cover different phases and the j2 rates follow the window as well as the writer. Within j2 the
  `r=1` over `frames` cells are rows[8] 407 of 448 and rows[1] 203 of 267, rows[9] 200 of 264 (pall).
- Per-writer verdict cut (floor - arm) in j2: qpub 27, qdata 21, qpanel 20, qstyle 7, against band 2. qpub is the style plus data
  sets and qdata is part of it. Lean `several_overlap` (`lean/Fw/Device/EndFloor.lean:193`): two cuts each over half the floor sum to more
  than the floor; frames shared by two cuts is INFERRED, not modelled.
- `platform#data-fw-scene` is in no silenced set (`KEYS.write`, `packages/measure-wktr/src/end-floor.mjs:5-13`, lists
  `nav#style`, `nav#data-fw-morph`, the nav class/aria/tabindex keys, the four morph-panel keys, `platform#style`). In
  `rs-flip-qwrite` rows[8] its cell is `mut:platform#data-fw-scene=16` in j2 and absent in j1 and j3. No claim is made that this
  writer is or is not part of the j2 floor.

## How the arms were built
Pushes r1, r2 and r3, kept under `results/end-floor-writes/r1`, `r2`, `r3` (each with rows.txt).
1. Run 40949084846 (r1, muting from before the wheel): in rows[3], rows[4], rows[5] and rows[8] (qdata, qpub, qclass, qwrite) the
   `frames` cell is 0 in all 3 jobs, so those arms made no flip track; the other rows hold frames.
   Cause (CONFIRMED in source): morph.geom timed tracks need `is-on-dark` (`apps/site/src/parts/morph.geom/index.tsx:53`),
   which nav.hitTest writes from a `data-fw-morph` observer; muting the attribute (qdata, qpub, qwrite) or the nav class (qclass, qwrite) removes the flip itself.
2. Run 40957179099 (r2, pin `is-on-dark` in every arm): the pin moved the window to the flip start and the arms were not comparable
   (`results/end-floor-writes/r2/rows.txt`: j1 `frames` from rows[0] 48 to rows[9] 416; qpin rows[2] rate 248, rows[10] rate 200, pall rows[1]
   rate 152). Cancelled after j1 (kept as `results/end-floor-writes/r2/wktr-j1`, not used).
3. Run 40960310474 (r3): writers silenced only while the frame window runs, the flip starts naturally.
   Verdict field `leaks A/R` is two counts (muted-arm leaks, reference leaks): `leaks 0/0` in every arm line of all 3 jobs; the `frames` cells
   are equal across arms in j1 and j3.

## Why (CONFIRMED, WebKit 862f17d, file:line)
- A running animation invalidates its target on each tick: `WebAnimation::needsTick` (animation/WebAnimation.cpp:1553)
  holds while the play state is running; `WebAnimation::tick` (1558) calls `KeyframeEffect::animationDidTick`
  (animation/KeyframeEffect.cpp:2129), which calls `invalidate()` (1731) -> `invalidateElement` (125-135) ->
  `Element::invalidateStyleForAnimation` (dom/Element.cpp:2763, `Validity::AnimationInvalid`). No write is needed. The
  all-paused arm pauses the page's animations, but the flip's own tracks are created after the pause and run (INFERRED: the extra
  recalc per rep in j1 and j3 is the frame a new track becomes ready, `animationBecameReady`, KeyframeEffect.cpp:2145).
- An inline-style write always marks the element: `StyledElement::inlineStyleChanged` (dom/StyledElement.cpp:214) ->
  `invalidateStyleAttribute` (190-212), `Validity::InlineStyleInvalid`, or `ElementInvalid` if a selector targets the
  style attribute. So the nav `--morph` write costs a recalc on the frames it lands in.
- An attribute write invalidates only when a rule depends on the attribute: `AttributeChangeInvalidation::invalidateStyle`
  (style/AttributeChangeInvalidation.cpp:44-77) returns on equal value and invalidates the element only if
  `attributesAffectingHost` or a substitution attribute names it, otherwise it goes through the rule sets of selectors
  using that attribute. INFERRED: the site's morph CSS reads the `--morph` property and no selector names `data-fw-morph`, so that
  attribute write alone invalidates little (selector use not grepped here).
- Lean (`lean/Fw/Device/EndFloor.lean`, golden `packages/contracts/golden/device/end-floor.jsonl`, replayed by
  `packages/measure-wktr/test/end-floor.test.mjs`): `rate_one_per_frame` (a window whose frames each hold a recalc reads at
  least 100 per 100 frames), `noWrites_gap` (a `no writes` cell has floor - reference at most twice the band, `end-floor.mjs:47`),
  `carries_cut`, `dominant_half`, `several_overlap` (above), `finding_noWrites`.

## Limits and follow-ups
- The 3 jobs do not give j2 a cause (INFERRED above). A pinned window (fixed frame count from the first track) would remove the
  long-window confound; it needs a harness arm that ends the window by frame count, not by the reference track. Follow-up, not run
  (the three CI pushes are used). `floor-fp-thr-off` (`packages/measure-wktr/src/accel-cli.mjs:36`) is defined and unrun.
- Lane comparison with `end-wktr-flip` (`results/end-wktr-flip/r1/verdict.txt`, `results/end-floor-writes/end-wktr-flip-r1-rows.txt`): this lane's pooled floor is 138, 154, 135
  (range 135 to 154, j1 to j3); the end-wktr-flip lane's all-paused floor is 83, 70, 81 (range 70 to 83; verdict `floor` of the
  `recalc` lines). The mode strings (`packages/measure-wktr/src/accel-cli.mjs:31-39`) differ: `end-base-thr-off` is
  `morph.geom:on,morph.tween:geom-timed`; `floor-v2p-thr-off` adds `engine.scroll:unthrottle`, `hero.exit:threaded` and
  `platform:faded-pause`. The two lanes also differ in harness options and arm list (`FLOOR_OPTS`, `FLOOR_ARMS`). The `rs-flip-pall`
  rows[2] of `accel-end-base` in end-wktr-flip r1 have `r=0` frames (32 in each of 3 jobs), against `r=0` of 0 in all r3 rows here. The cause of
  the higher floor is not measured. In end-wktr-flip r1 the `fp/recalc` verdict `variant` (geom plus `platform:faded-pause` only) is 87, 89,
  91 (j1 to j3), against this lane's natural page 135, 160, 133. Which added flag raises the rate is not measured.
- Attribution is per writer silenced in turn, not per call site. A cut of the floor itself would be a change to the flip
  tracks, a separate look-change question, not a writer cut; this is not measured here.
- `.github/workflows/wktr.yml` carried a temporary build config and `--modes floor-v2p-thr-off` for these runs; it is
  restored before the land.

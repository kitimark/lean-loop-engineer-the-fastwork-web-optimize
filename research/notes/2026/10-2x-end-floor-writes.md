---
id: 2026-10-30-end-floor-writes
kind: note
title: "end-floor-writes: no page writer carries the WebKit end-of-page floor; every frame holds a recalc with zero DOM writes, so there is no same-look cut"
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

## Answer
- No page writer carries the floor. Dominant writer: none in 3 of 3 jobs. In the 2 jobs with comparable windows (j1, j3,
  48 frames per arm) silencing the six listed writer sets at once leaves the floor unchanged: 138 -> 133 and 135 -> 135 per 100 frames,
  verdict `no writes`. In the job with long, unequal windows (j2) the six sets together cut 40 of 154, spread over
  publish (27), data (21), panel (20), style (7), class and platform (0); no single cut is over half the floor.
- The floor is the running animation tracks. Every frame of every arm in every job holds at least one style recalc (0
  frames with zero recalcs in 30 arm-windows). The recalc needs no write: with the six listed writer sets silenced
  (`rs-flip-qwrite`, the arm that records mutations) 0 of 48 frames in j1 and 0 of 48 in j3 carry a `mut:` key and all 48
  and 48 hold at least one recalc; in j2 432 of 448 frames carry no mutation and all 448 hold a recalc (the other 16
  carry `mut:platform#data-fw-scene`, see the table notes). The natural and all-paused arms (`rs-flip-nat`,
  `rs-flip-pall`) do not record mutations (`rsWindow` in `packages/measure-wktr/src/mid-page.mjs`, `rec` is on only for
  `obs`, `obsf`, `pallf` and the q arms), so nothing is claimed about writes in those windows. The q arms do show writes
  in the same kind of window: in j2 `rs-flip-qstyle` has 64 of 265 frames with `mut:nav#data-fw-morph` (it silences only the
  nav inline style). Source of all counts: `rows[arm].rs.frames`, `kt`, in `results/end-floor-writes/r3/wktr-jN/accel-floor-v2p-thr-off-1.json`.
  Lean: `rate_one_per_frame`.
- No same-look cut was built: the deliverable is conditional on one writer carrying most of the floor, and none does.
  Negative finding.
- Class decision over the 3 jobs by the Lean model (`overallW`, `overallF`): `mixed` (j1, j3: `no writes`; j2: `spread
  over writers`). The mix comes from the window length, not from the writers (next section).

## Numbers (per 100 frames, wktr run 40960310474, push 3 at 104183cb1)
Source: `results/end-floor-writes/r3/verdict.txt` (made by `node packages/measure-wktr/src/end-floor-cli.mjs
wktr-j1 wktr-j2 wktr-j3 --out verdict.txt`), rows of `results/end-floor-writes/r3/wktr-jN/accel-floor-v2p-thr-off-1.json`
(`rows[arm].rs.frames`, `.wins`). Floor = pooled `rs-flip-pall` read before and after the writer arms; reference =
`rs-flip-qwrite` (the six listed writer sets silenced at once: style, data, class, panel, plat, and pub, which is style plus data); mode `floor-v2p-thr-off` (v2-proved + morph.geom:on,
morph.tween:geom-timed, WKTR pref off), 16 reps per arm.

| arm | j1 | j2 | j3 |
|---|---|---|---|
| floor (2 x pall) | 138 | 154 | 135 |
| qstyle (nav inline style) | 135 | 147 | 133 |
| qdata (data-fw-morph) | 135 | 133 | 137 |
| qpub (style + data) | 135 | 127 | 135 |
| qclass (nav class, tabindex, aria) | 135 | 156 | 135 |
| qpanel (morph panel) | 137 | 134 | 133 |
| qplat (platform style) | 133 | 157 | 133 |
| qwrite (all six listed sets) | 133 | 114 | 135 |
| natural page | 135 | 160 | 133 |
| frames per arm (pall x2 / qwrite) | 96 / 48 | 531 / 448 | 96 / 48 |
| judge, each of the six sets | no writes | carries x5 (not qclass, qplat) | no writes |

- j1 and j3: each rep window is 3 frames and holds 4 recalcs (frame counts 1, 1, 2: 32 frames with one recalc, 16 with
  two, 0 with none, in `rs-flip-pall` and `rs-flip-qwrite` alike). The extra recalc per rep is also there with all
  writers silenced (qwrite 133 and 135).
- j2: the flip window is long (pall 267 frames, qwrite 448, nat 245, qpub 405, qdata 425, qpanel 419, qclass 251, qplat
  254, qstyle 265 over 16 reps), so the arms cover different phases of the flip and the rate differences follow the window,
  not only the writer. qwrite has 91% of its frames at exactly one recalc (407 of 448) against 76% for pall (203 of 267).
  INFERRED, not shown: muting data-fw-morph and class changes how long the flip lives, so the arms are not comparable
  in j2. The 3 jobs do not agree on a writer, so no writer is named.
- Per-writer cut (floor - arm), j2 only where it is above the band 2: qpub 27, qdata 21, qpanel 20, qstyle 7. qpub is the
  style plus data sum and qdata is part of it, so they overlap (`several_overlap`: two cuts over half the floor each
  must share frames); none is over half of 154.
- `platform#data-fw-scene` is in no silenced set (`KEYS.write`, `packages/measure-wktr/src/end-floor.mjs:5-13`, lists
  `nav#style`, `nav#data-fw-morph`, the nav class/aria/tabindex keys, the four morph-panel keys, `platform#style`). In
  `rs-flip-qwrite` it carries a mutation in 16 of 448 frames in j2 and in 0 of 48 frames in j1 and in j3 (same file, `kt` key
  `mut:platform#data-fw-scene`). Those 16 frames still hold a recalc, but no claim is made that this writer is or is not
  part of the j2 floor.

## How the arms were built
Three pushes, kept under `results/end-floor-writes/r1`, `r2`, `r3`.
1. Run 40949084846 (r1, muting from before the wheel): qdata, qpub, qclass and qwrite created no flip track in 3 of 3
   jobs (frames 0, verdict `unread`; qstyle, qpanel, qplat read, floors 138/141/143 against natural 133/150/137).
   Cause (CONFIRMED in source): morph.geom timed tracks need `is-on-dark` (`apps/site/src/parts/morph.geom/index.tsx:53`),
   which nav.hitTest writes from a `data-fw-morph` observer; muting the attribute removes the flip itself.
2. Run 40957179099 (r2, pin `is-on-dark` in every arm): the pin moved the window to the flip start, floors 200 to 344
   against 152 unpinned, so the arms were not comparable. Cancelled after j1 (kept as `results/end-floor-writes/r2/wktr-j1`, not used).
3. Run 40960310474 (r3): writers silenced only while the frame window runs, the flip starts naturally.
   Leaks (silenced keys seen in a muted arm): 0 of 0 in all 3 jobs; the frame counts are equal across arms in j1 and j3.

## Why (CONFIRMED, WebKit 862f17d, file:line)
- A running animation invalidates its target on each tick: `WebAnimation::needsTick` (animation/WebAnimation.cpp:1553)
  holds while the play state is running; `WebAnimation::tick` (1558) calls `KeyframeEffect::animationDidTick`
  (animation/KeyframeEffect.cpp:2129), which calls `invalidate()` (1731) -> `invalidateElement` (125-135) ->
  `Element::invalidateStyleForAnimation` (dom/Element.cpp:2763, `Validity::AnimationInvalid`). One recalc per frame,
  no write needed. The all-paused arm pauses the page's animations, but the flip's own tracks are created after the
  pause and run (INFERRED: the extra recalc per rep in j1 and j3 is the frame a new track becomes ready, `animationBecameReady`, KeyframeEffect.cpp:2145).
- An inline-style write always marks the element: `StyledElement::inlineStyleChanged` (dom/StyledElement.cpp:214) ->
  `invalidateStyleAttribute` (190-212), `Validity::InlineStyleInvalid`, or `ElementInvalid` if a selector targets the
  style attribute. So the nav `--morph` write costs a recalc on the frames it lands in, and `qstyle` removes them
  (j2 cut 7), but only on those frames.
- An attribute write invalidates only when a rule depends on the attribute: `AttributeChangeInvalidation::invalidateStyle`
  (style/AttributeChangeInvalidation.cpp:44-77) returns on equal value and invalidates the element only if
  `attributesAffectingHost` or a substitution attribute names it, otherwise it goes through the rule sets of selectors
  using that attribute. INFERRED: the site's morph CSS reads the `--morph` property and no selector names `data-fw-morph`, so that
  attribute write alone invalidates little (selector use not grepped here).
- Lean (`lean/Fw/Device/EndFloor.lean`, golden `packages/contracts/golden/device/end-floor.jsonl`, replayed by
  `packages/measure-wktr/test/end-floor.test.mjs`): `rate_one_per_frame` (a window whose frames each hold a recalc reads at
  least 100 per 100 frames), `noWrites_gap` (a `no writes` cell has floor - reference <= 2 band), `carries_cut`,
  `dominant_half`, `several_overlap`, `finding_noWrites`. The rule `dominant` was fixed before the run.

## Limits and follow-ups
- The 3 jobs are not enough to give j2 a cause (INFERRED above). A pinned window (fixed frame
  count from the first track) would remove the long-window confound; it needs a harness arm that ends the window by
  frame count, not by the reference track. Follow-up, not run (3 pushes used).
- The floor here (133 to 154) is higher than the all-paused floor of the end-wktr-flip lane (70 to 83; `results/end-wktr-flip/r1/wktr-jN/accel-end-base-thr-off-1.json`
  `rows[rs-flip-pall]`: 83, 71, 81 per 100 frames). What differs, from the mode strings (`packages/measure-wktr/src/accel-cli.mjs:31-39`):
  `end-base-thr-off` is `morph.geom:on,morph.tween:geom-timed`, so both lanes carry the flip geom tracks;
  `floor-v2p-thr-off` adds `engine.scroll:unthrottle`, `hero.exit:threaded` and `platform:faded-pause`. The rep window
  does not differ in j1 and j3: `rs.wins` is 3 frames in all 16 reps in both lanes (48 frames); in j2 this lane's windows are 6 to
  29 frames per rep over all arms (`rs-flip-pall` 15 to 18, `rs-flip-qwrite` 26 to 29). Measured contrast: the earlier `end-fp-thr-off` lane (geom plus `platform:faded-pause`
  only) reads its natural flip at 88, 90, 92 (j1 to j3, `rows[rs-flip-nat]`), against 135, 160, 133 here. Which added flag raises the rate per 100 frames is not measured
  (follow-up).
- Attribution is per writer silenced in turn, not per call site. A cut of the floor itself would be a change to the flip
  tracks (fewer concurrent tracks per frame), a separate look-change question, not a writer cut.
- `.github/workflows/wktr.yml` carried a temporary build config and `--modes floor-v2p-thr-off` for these runs; it is
  restored before the land.

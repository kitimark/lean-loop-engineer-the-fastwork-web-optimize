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
a code constant with file:line, or a run id, sha or count of jobs, rows and arms. Lines into `packages/measure-wktr/src` and
`.github/workflows/wktr.yml` are at the pushed commit of the run they explain (`git show 104183cb1:<path>` for run 40960310474,
`49a5c04f3` for end-wktr-flip run 40869911524); `end-floor.mjs` changed afterwards (task `end-floor-window`: platform keys, reps).
Job names are the artifact folders `wktr-j1` to `wktr-j3` of the run (`runner.json` `runId`).

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
  (`rs-flip-nat`, `rs-flip-pall`) do not record mutations (`rec`, `packages/measure-wktr/src/mid-page.mjs:594@104183cb1`), so their `mut:` cells say
  nothing about writes. The q arms do record: j2 rows[2] `rs-flip-qstyle` has 265 frames, 201 without a `mut:` key, and a
  `mut:nav#data-fw-morph` count of 64 (it silences only the nav inline style). Lean: `rate_one_per_frame`
  (`lean/Fw/Device/EndFloor.lean:204`): for a window `fs` with `hne : fs ≠ []` (non-empty) and `h : ∀ f ∈ fs, 1 ≤ f.r` (every frame
  holds at least one recalc), `100 ≤ rate fs`. Arithmetic only; `hne` limits the claim to existing windows: all 30
  r3 rows have `frames` above 0 (`frames 0` appears in no row of `results/end-floor-writes/r3/rows.txt`).
- INFERRED when written, refuted by later runs (MEASURED, runs 40989068304 and 41030064819): "the recalcs in frames without a recorded mutation come from the running flip tracks".
  Task `end-floor-window` (run 40989068304) found no running flip track in its windows (`research/notes/2026/10-2x-end-floor-window.md`),
  and task `end-floor-dirty` (run 41030064819) named the carrier: 7 elements that are targets of 13 `hero.exit:threaded` ViewTimeline
  animations and 1 `engine.scroll:unthrottle` ScrollTimeline animation, all finished (`research/notes/2026/10-30-end-floor-dirty.md:26-32`).
  The lane comparison below uses this.

## Numbers (per 100 frames, wktr run 40960310474, push 3 at 104183cb1)
Source: `results/end-floor-writes/r3/verdict.txt` (made by `node packages/measure-wktr/src/end-floor-cli.mjs
wktr-j1 wktr-j2 wktr-j3 --out verdict.txt`) and `results/end-floor-writes/r3/rows.txt`. Regenerate rows.txt (byte-equal, checked by
`packages/measure-wktr/test/end-floor-rows.test.mjs`) with
`node packages/measure-wktr/src/end-floor-rows.mjs results/end-floor-writes/r3 --out results/end-floor-writes/r3/rows.txt`
(same command with `r1` and `r2`; for the lane comparison `node packages/measure-wktr/src/end-floor-rows.mjs results/end-wktr-flip/r1 --out results/end-floor-writes/end-wktr-flip-r1-rows.txt`); `end-floor-rows.mjs` is an unproved TS stand-in (frame and key counts; `rate` is
imported from `end-floor.mjs`, which the Lean golden checks). Floor = pooled `rs-flip-pall` read before and after the writer arms (rows[1]
and rows[9]); reference = `rs-flip-qwrite`; mode `floor-v2p-thr-off` (v2-proved + morph.geom:on, morph.tween:geom-timed, WKTR pref off), reps per
arm `rsReps` 16 (`FLOOR_OPTS`, `packages/measure-wktr/src/end-floor.mjs:24@104183cb1`).

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
- `platform#data-fw-scene` is in no silenced set (`KEYS.write`, `packages/measure-wktr/src/end-floor.mjs:7-15@104183cb1`, lists
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
  all-paused arm pauses the page's running animations (`pausedN` 8, `stillRunning` 0 in rows[1] of `wktr-j1`), but the flip's own
  tracks are created after the pause and run (INFERRED, and not confirmed by `end-floor-window`, see the answer: the extra
  recalc per rep in j1 and j3 is the frame a new track becomes ready, `animationBecameReady`, KeyframeEffect.cpp:2145). The floor
  itself is carried by finished scroll-driven animations, see the lane comparison.
- An inline-style write always marks the element: `StyledElement::inlineStyleChanged` (dom/StyledElement.cpp:214) ->
  `invalidateStyleAttribute` (190-212), `Validity::InlineStyleInvalid`, or `ElementInvalid` if a selector targets the
  style attribute. So the nav `--morph` write costs a recalc on the frames it lands in.
- An attribute write invalidates only when a rule depends on the attribute: `AttributeChangeInvalidation::invalidateStyle`
  (style/AttributeChangeInvalidation.cpp:44-77) returns on equal value and invalidates the element only if
  `attributesAffectingHost` or a substitution attribute names it, otherwise it goes through the rule sets of selectors
  using that attribute.
- How `data-fw-morph` is used as a selector (CONFIRMED by grep over `apps/site` at this note's commit): no CSS, SCSS or HTML file
  names it (`grep -rn "data-fw-morph" apps/site --include="*.css" --include="*.scss" --include="*.html"` prints nothing, and no
  `.css` file under `apps/site/src` contains `fw-morph`), so no style rule depends on the attribute and its write invalidates no style by
  itself (the WebKit rule above; INFERRED for the engine, CONFIRMED for the site). The only selector string is a DOM query,
  `panel.closest('[data-fw-morph]')` (`apps/site/src/parts/morph.panel/index.tsx:32`), run in script, not a style rule. The attribute is
  read by three MutationObservers with `attributeFilter: ['data-fw-morph']` (`apps/site/src/parts/nav/index.tsx:113`,
  `nav.hitTest/index.tsx:32`, `morph.geom/index.tsx:89`), plus the debug observer at `apps/site/src/debug/nav-transition.ts:156`, active only with its debug param, and by the `dataset.fwMorph` reads next to them. So muting the attribute
  (arms qdata, qpub, qwrite) acts through those observers' writes (nav class, panel, geom tracks), not through a selector; this is why
  r1 lost the flip (How the arms were built, item 1).
- Lean (`lean/Fw/Device/EndFloor.lean`, golden `packages/contracts/golden/device/end-floor.jsonl`, replayed by
  `packages/measure-wktr/test/end-floor.test.mjs`): `rate_one_per_frame` (for `hne : fs ≠ []` and `h : ∀ f ∈ fs, 1 ≤ f.r`, the rate is at
  least 100 per 100 frames), `noWrites_gap` (a `no writes` cell has floor - reference at most twice the band, `end-floor.mjs:51@104183cb1`),
  `carries_cut`, `dominant_half`, `several_overlap` (above), `finding_noWrites`.

## Limits and follow-ups
- The 3 jobs do not give j2 a cause (INFERRED above). A pinned window (fixed frame count from the first track) would remove the
  long-window confound; it needs a harness arm that ends the window by frame count, not by the reference track. Follow-up, not run
  (the three CI pushes are used). `floor-fp-thr-off` (`packages/measure-wktr/src/accel-cli.mjs:36@104183cb1`) is defined and unrun.
- Lane comparison with `end-wktr-flip` (run 40869911524 at 49a5c04f3, `results/end-wktr-flip/r1/verdict.txt`,
  `results/end-floor-writes/end-wktr-flip-r1-rows.txt`; this lane is run 40960310474 at 104183cb1). Floors per 100 frames, each
  endpoint named by run and job: this lane's pooled floor is 138 (run 40960310474, job `wktr-j1`), 154 (`wktr-j2`) and 135 (`wktr-j3`),
  so its range 135 to 154 runs from `wktr-j3` (low) to `wktr-j2` (high); the end-wktr-flip all-paused floor (verdict `floor` of the
  `recalc` lines, `rs-flip-pall` rows[2]) is 83 (run 40869911524, job `wktr-j1`), 70 (`wktr-j2`) and 81 (`wktr-j3`), so its range 70 to
  83 runs from `wktr-j2` (low) to `wktr-j1` (high). The lowest floor here (135, `wktr-j3`) is above the highest there (83, `wktr-j1`) by 52.
- Why this lane's floor is above (flag differences, CONFIRMED by the two lanes' mode strings and build lines; the mechanism is MEASURED
  in other runs, the attribution to one flag INFERRED).
  1. Flags. The end-wktr-flip lane ran `end-base-thr-off` = `morph.geom:on,morph.tween:geom-timed`
     (`packages/measure-wktr/src/accel-cli.mjs:30@49a5c04f3`; built by the `--config` list at `.github/workflows/wktr.yml:160@49a5c04f3`,
     run by `--modes end-base-thr-off,...` at `:274@49a5c04f3`). This lane ran `floor-v2p-thr-off` = the same two plus
     `engine.scroll:unthrottle`, `hero.exit:threaded` and `platform:faded-pause` (`accel-cli.mjs:35@104183cb1`; built at
     `wktr.yml:160@104183cb1`, run by `--modes floor-v2p-thr-off` at `:274@104183cb1`). `platform:faded-pause` is not the difference:
     the end-wktr-flip `fp` variant (geom plus `platform:faded-pause` only) has recalc 87, 89, 91 (`wktr-j1` to `wktr-j3`), against its floors 83, 70 and 81 (results/end-wktr-flip/r1/verdict.txt fp/recalc lines: at floor true in wktr-j1, false in wktr-j2 and wktr-j3); all three are below this lane's lowest floor, 135 (wktr-j3).
     That leaves `engine.scroll:unthrottle` and `hero.exit:threaded`.
  2. Mechanism (MEASURED elsewhere). `engine.scroll:unthrottle` "costs one style recalc per frame, also while idle at the end of
     the page (WKTR run 41045232315: 576 of 576 frames with this flag alone, 0 without)" (`apps/site/src/parts/engine.scroll/part.json:11`).
     Task `end-floor-dirty` (run 41030064819, mode `probe-v2p-thr-off`, same flag set) found the dirty elements at every frame
     are targets of 13 finished ViewTimeline animations of `hero.exit:threaded` and 1 finished ScrollTimeline animation of
     `engine.scroll:unthrottle`; hiding them leaves 4 to 5 recalcs per 100 frames (`research/notes/2026/10-30-end-floor-dirty.md:26-35`,
     `results/end-floor-dirty/r3/verdict.txt:14`). So both flags add scroll-driven animations that tick every frame; neither exists in the
     end-wktr-flip build. The all-paused arm does not remove this: `pausedN` 8 and `stillRunning` 0 in both lanes (`accel-floor-v2p-thr-off-1.json`
     rows[1] and `accel-end-base-thr-off-1.json` rows[2] of `wktr-j1`), the pause covers the running time-based animations only.
  3. Cell evidence (MEASURED). `rs-flip-pall` has `r=0` 32 and `r=1` 0 of 48 frames in each of the 3 jobs of end-wktr-flip
     (`end-wktr-flip-r1-rows.txt`, rows[2]) and `r=0` 0 and `r=1` 32 of 48 frames in `wktr-j1` and `wktr-j3` here (rows[1] and rows[9];
     `r=0` is 0 in all 30 r3 rows): the 32 frames that were empty hold one recalc each. Adding 32 of 48 frames to 83 or 81 gives about 150,
     against 143 and 133 (`wktr-j1`) and 135 and 135 (`wktr-j3`): the size is consistent, not equal (INFERRED reading; the rest is not decomposed).
  4. Harness options. END_OPTS (`accel-cli.mjs:51@49a5c04f3`) is `{ rsIdleMs: 5000, rsReps: 16, gh: true, gk: true, lay: true }`;
     FLOOR_OPTS (`end-floor.mjs:24@104183cb1`) is the same with `lay: false`. Neither sets `tk`, and `rsWin` does not exist at either commit, so both windows end
     by the reference track or the cap (`mid-page.mjs:643-645@104183cb1`). The arm lists differ: `END_ARMS.base`
     (`accel-cli.mjs:46@49a5c04f3`) is nat, flip, pall, flip, nat; `FLOOR_ARMS` (`end-floor.mjs:21-23@104183cb1`) is nat, pall, six writer
     arms, qwrite, pall. `lay` only adds layout counter reads (`mid-page.mjs:613@104183cb1`, `layNow`); no run isolates it, so it is not
     excluded, but it only reads counters and no recalc counter read resolves style (INFERRED from the code, not from a run).
  Not measured in these two runs: each of the two flags alone on this lane. `floor-fp-thr-off` (`accel-cli.mjs:36@104183cb1`,
  geom plus `platform:faded-pause`, the end-wktr-flip flags on the floor harness) is defined and unrun, so the harness-option and
  the flag differences are not separated by a run here (the flag attribution rests on item 2).
- Attribution is per writer silenced in turn, not per call site. A cut of the floor itself would be a change to the flip
  tracks, a separate look-change question, not measured here.
- `.github/workflows/wktr.yml` carried a temporary build config and `--modes floor-v2p-thr-off` for these runs; it is
  restored before the land.

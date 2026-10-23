---
id: 2026-10-23-trajectory-aa-noise
kind: note
title: "Trajectory A/A noise: the carousel hold and the panel opacity kink"
status: final
created: 2026-10-23
authors: [agent:measure-engineer]
topics: [measurement, trajectory-probe, gate, chromium]
---

# Trajectory A/A noise (2026-10-23)

The hold-out run 39852684450 (same code both arms, Chromium 156.0.8078.4, recordings at rest) graded the carousel Q at
390 and 640 and the panel effect at 640 close L. An A/A must grade E. Both causes are in the recorded frames, not in the
engine, and both are fixed in the Lean grader (`lean/Fw/Gate/TrajectoryGpu.lean`).

## Carousel: whole-frame hold, not a sub-frame shift

- MEASURED (raw of 39852684450): the swap series starts at the container insertion row, where the children vector grows
  from 16 to 20 entries (the new avatar is about 10 by 11 px and invisible). The first motion row comes a whole number
  of frames later. Rows from insertion to first motion, per swap:

| Width | Arm | Swap 1 | Swap 2 | Swap 3 | Swap 4 |
|---|---|---|---|---|---|
| 390 | base | 4 | 4 | 2 | 2 |
| 390 | cand | 3 | 3 | 2 | 2 |
| 640 | base | 4 | 4 | 2 | 2 |
| 640 | cand | 3 | 3 | 2 | 2 |

- MEASURED: holdFrames (the `holds` field, frames dropped before the last rest frame) for 39852684450: base 2,2,0,0, cand 1,1,0,0.
- MEASURED: after onset the two arms agree within 0.02 px. Swaps 1 and 2 match only at a shift of exactly +1 frame,
  swaps 3 and 4 at 0; no quarter-frame shift matches. The earlier reading "two of four swaps match only at a sub-frame
  shift" is refuted.
- MEASURED (older runs 39823047557, 39823476824, 39824100493, before the settle rule): rows from insertion to first motion 4,4,2 in both arms, graded E.
- INFERRED: the longer holds of the first swaps are warm-up or scheduling after the start-selling avatar template swap
  mounts a fresh image. Not confirmed.
- Premise (stated in Lean, `holdTol`): the hold varies by 2 frames inside one recording, but between the arms of one
  recording it differs by at most one frame (holdFrames: 39852684450 2 vs 1, 39861846900 at 640 1 vs 2). The motion match
  anchors each swap series at the last rest frame before the first move (`dropHold`, `rebase`, `onset_hold_invariant`,
  `dropHold_first_moves`). The hold is graded apart: `holdGrade` is E iff the base and cand holds of a swap pair differ by
  at most 1 frame, else L, and the swap rep grade is `worse` of the motion grade and the hold grade (`repGrade`). The unit
  carries both arms' holds as `holds`.
- MEASURED: offline re-reduction of 39852684450 with the anchor grades E E E E at 390 and at 640; the three older runs stay E.
- MEASURED: offline re-reduction with `holdGrade` of the four A/A raws (artifact cells-gpu-chromium), 12 of 12 units E in each: 39852684450, 39860085568, 39861846900, 39863586490; carousel reps E,E,E,E at 390 and 640 in each.

## Panel effect 640 close: the opacity kink

- MEASURED: the close phase moves the morph clock m by about 0.1 per frame, and the opacity model
  `clamp01((m - 2/25) / (18/25))` has a kink at m = 4/5. The pooled base reference around it has the points
  (0.7776, 0.969) and (0.8782, 1). Linear interpolation of the reference at m = 0.7986 gives 0.9755 against the
  candidate's 0.998: 0.0225 off, tolerance 0.01.
- MEASURED: rep 1 (Q) had a worst ratio of 1.008 at k = 0.8455, rep 2 (L) 2.25. The lag was 0.006 to 0.008 frames, and
  the shifted grade fails too, so the rep grades L.
- Fix (Lean `residual`, `modelGrade`, `model_grade_e`): compare residuals against the declared effect for the reference
  and the candidate, including the lagged series. A sparse reference and a candidate on the effect grade E. A candidate
  that drops the blur or the scale, or is 3/100 off in opacity, still grades L (golden kind `kinkcell`).
- MEASURED: offline re-reduction: 640 close reps E,Q,L become E,E,E; every other unit stays E; the three older runs stay E.

## Small items

- `worst` ranks E < E1 < Q < L in Lean (`worse`); the JS RANK now has E1 and a golden case.
- Settle and tail stop rules of `carouselSample` (6 equal frames, caps 2.2 s and 1.5 s) are Lean `settleRun` and
  `tailRun` with theorems and golden kinds `settle` and `tail`. The page function lives in `cells-gpu-page.mjs`; a test
  drives it with a scripted clock against the golden vectors.
- `docs/team/tools/gate.md`: a pain-dark unit whose base never flips in one direction is not comparable.

## Fresh A/A runs

Three trajectory-probe runs of this branch (Chromium 156.0.8078.4, widths 390 and 640, same code both arms). MEASURED, artifact `cells-gpu-chromium` of each run:

| Run | Commit | Units graded E of 12 | Carousel holdFrames (base, cand) at 390 | at 640 |
|---|---|---|---|---|
| 39860085568 | 76f9a545d | 12 | 2,2,0,0 and 2,2,0,0 | 2,2,0,0 and 2,2,0,0 |
| 39861846900 | f3b07d2ee | 12 | 2,2,0,0 and 2,2,0,0 | 1,1,0,0 and 2,2,0,0 |
| 39863586490 | 3575e73aa | 12 | 2,2,0,0 and 2,2,0,0 | 2,2,0,0 and 2,2,0,0 |

- Every unit grades E in all three runs (panel-effect close at 640 included, carousel reps E,E,E,E).
- Between arms the hold differs by at most one frame in every run (39852684450 2 vs 1, 39861846900 at 640 1 vs 2), which `holdGrade` keeps E; a longer difference grades L (golden case "entering avatar held 2 rows
  against 4").
- Limit: Chromium only, three runs. WebKit A/A is not measured.

## Follow-ups

- WebKit A/A.
- Find why the first swaps hold 3 to 4 rows (INFERRED above).

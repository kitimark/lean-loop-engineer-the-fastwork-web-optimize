---
id: 2026-10-23-trajectory-aa-noise
kind: note
title: "Trajectory A/A noise: the carousel hold and the panel opacity kink"
status: draft
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
  of frames later. Hold from insertion to onset, per swap:

| Width | Arm | Swap 1 | Swap 2 | Swap 3 | Swap 4 |
|---|---|---|---|---|---|
| 390 | base | 4 | 4 | 2 | 2 |
| 390 | cand | 3 | 3 | 2 | 2 |
| 640 | base | 4 | 4 | 2 | 2 |
| 640 | cand | 3 | 3 | 2 | 2 |

- MEASURED: after onset the two arms agree within 0.02 px. Swaps 1 and 2 match only at a shift of exactly +1 frame,
  swaps 3 and 4 at 0; no quarter-frame shift matches. The earlier reading "two of four swaps match only at a sub-frame
  shift" is refuted.
- MEASURED (older runs 39823047557, 39823476824, 39824100493, before the settle rule): holds 4,4,2 in both arms, graded E.
- INFERRED: the longer holds of the first swaps are warm-up or scheduling after the start-selling avatar template swap
  mounts a fresh image. Not confirmed.
- Premise (stated in Lean): the hold is not graded. It varies by 2 frames inside one recording, more than the one-frame
  limit. `dropHold` and `rebase` anchor each swap series at the last rest frame before the first move
  (`onset_hold_invariant`, `dropHold_first_moves`); `holdFrames` reports the hold and the carousel unit carries it as `holds`.
- MEASURED: offline re-reduction of 39852684450 with the anchor grades E E E E at 390 and at 640; the three older runs stay E.

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

FILLED-AFTER-CI

## Follow-ups

- WebKit A/A (Chromium only here).
- A gate on the hold itself (`holds`), once the cause of the long early holds is known.
- Find why the first swaps hold 3 to 4 rows (INFERRED above).

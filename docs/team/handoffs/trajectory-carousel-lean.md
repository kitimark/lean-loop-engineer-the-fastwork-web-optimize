# trajectory-carousel-lean handoff

- Branch worktree-wf_6264ad43-ace-1, worktree .claude/worktrees/wf_6264ad43-ace-1, last commit: git log -1 (probe commit 42d931aab).
- CI: branch ci/trajectory-carousel-lean, trajectory-probe push run 39852684450 of 42d931aab (engines=chromium widths=390,640 diagnostic), complete, pass. One dispatch used.
- Verified: check.sh green (axiom check included), @fw/gate-breakpoints test 635/635, @fw/contracts test and typecheck, ci-paths 54/54, land-inputs 56/56.
- Hold-out (run 39852684450, artifact cells-gpu-chromium, Chromium 156.0.8078.4): every recording opens at rest (`atRest` true for both arms at 390 and 640; first change at rows 26-41) and every arm keeps 4 swaps (restedBefore drops none).
  Carousel: 390 Q (reps Q,Q,E,E, swaps 4/4), 640 Q (Q,Q,E,E, 4/4). nav-clip E at 390 and 640, open and close. pain-dark E at both widths.
  panel-effect: E except 640 close L (reps E,Q,L); the morph recording is unchanged, so that L is a new A/A finding (follow-up).
- Open: carousel A/A grades Q, not E (two of four swaps match only at a sub-frame shift); WebKit A/A; Lean is not run on the raws (gpu-cells-raw-fixture).
- Recorder glue (cells-gpu-run.mjs carouselSample): settle and tail stop conditions run in the page and are not checked against Lean.

## What changed
- lean/Fw/Gate/TrajectoryGpu.lean: worst (none on any null rep or no reps), restedBefore, Scan/settle/scanStep/swapSpans,
  swapSeries, swapsOf, swapGrade, carouselReps, carouselGrade, carouselCell, painDir, painCell. Theorems worst_none_mem,
  swapSpans_rested, swapSpans_from_pos, carouselGrade_mismatch, carouselCell_mismatch, carouselCell_zero_swaps,
  carouselCell_null_rep, painDir_no_flip, painDir_flips, painCell_no_flip_up/down. Golden kinds worst, rested, swaps,
  carousel, paincell.
- cells-gpu.mjs: twins restate them (swapSpans, swapSeries, carouselCellAt, carouselGrade, painDir); the carousel unit
  carries `atRest` (restedBefore of row 1 per arm).
- cells-gpu-run.mjs carouselSample: waits for a swap to end (motion, then 6 equal frames, cap 2.2 s) before recording, and
  after `ms` records on until 6 equal frames (cap 1.5 s).

Read first: TrajectoryGpu.lean section from `def worse` to `painCell_no_flip_down`.

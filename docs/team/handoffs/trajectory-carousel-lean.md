# trajectory-carousel-lean handoff

- Branch worktree-wf_6264ad43-ace-1, worktree .claude/worktrees/wf_6264ad43-ace-1, last commit: git log -1 (probe commit 42d931aab).
- CI: branch ci/trajectory-carousel-lean, trajectory-probe push run 39852684450 of 42d931aab (engines=chromium widths=390,640 diagnostic), state running.
- Verified: Lean module builds (guards pass), golden regenerated (174 lines), gate-breakpoints trajectory-gpu tests pass (31).
- Open: hold-out grades from the run; check.sh, package tests, ci-paths, land-inputs, dry land.

## What changed
- lean/Fw/Gate/TrajectoryGpu.lean: worst (none on any null rep or no reps), restedBefore, Scan/settle/scanStep/swapSpans,
  swapSeries, swapsOf, swapGrade, carouselReps, carouselGrade, carouselCell, painDir, painCell. Theorems worst_none_mem,
  swapSpans_rested, swapSpans_from_pos, carouselGrade_mismatch, carouselCell_mismatch, carouselCell_zero_swaps,
  carouselCell_null_rep, painDir_no_flip, painDir_flips, painCell_no_flip_up/down. Golden kinds worst, rested, swaps,
  carousel, paincell.
- cells-gpu.mjs: twins restate them (swapSpans, swapSeries, carouselCellAt, carouselGrade, painDir); the carousel unit
  carries `atRest` (restedBefore of row 1 per arm).
- cells-gpu-run.mjs carouselSample: waits for a swap to end (motion, then 6 equal frames, cap 2.2 s) before recording, and
  after `ms` records on until 6 equal frames (cap 1.5 s), so a recording opens and ends at rest.

Read first: TrajectoryGpu.lean section from `def worse` to `painCell_no_flip_down`.

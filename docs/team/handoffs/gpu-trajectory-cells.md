# gpu-trajectory-cells handoff

- Branch worktree-wf_9ab25dd7-9aa-1, worktree .claude/worktrees/wf_9ab25dd7-9aa-1; round 3 work on top of 21f4028f / main 45c952ee (sha of the final commit: git log -1). CI branch ci/gpu-trajectory-cells.
- CI runs (all complete/pass, chromium A/A at 6f4aea1c, widths 390 and 640, artifact cells-gpu-chromium): 39823047557, 39823476824, 39824100493. No new dispatch this round: the three raws were re-reduced.
  Under 6f4aea1c the CI artifacts graded carousel L at 640 in 39823047557 and at 390 in 39824100493. Every one of the 12 recordings in the three runs opens mid-swap (first swap 4-5 samples), so restedBefore drops the first swap of each; the rule has no hold-out.
- Round-2 blocker fixed: panelGrade (Lean TrajectoryGpu.lean, twin cells-gpu.mjs) grades a differing series at the lagged clock over opacity, blur and scale (laggedSeries, shiftedGrade, panelCell), Q only when it matches there within one frame of lag; theorems panelGrade_no_match_l, panelGrade_long_lag_l, panelGrade_short_lag_q, shiftedGrade_ne_e. Golden regenerated (132 lines, kinds panel with `shifted`, new panelcell).
- Re-reduction with the fixed reducer (per unit E/Q/L, reps in the artifact cells-chromium.md): all 12 units E in each of the 3 runs (nav-clip E4, panel-effect E4 lag max 0.020 / 0.013 / 0.022, pain-dark E2, carousel E2). Blur 0 or scale 1 on every candidate panel row of 39823476824: panel-effect L on all 4 units.
- Why the old panel Q cases (close, 3 of 8 units) are now E: the scale tolerance (half a device px over the panel, 0.00064 at 390) was under the reading step (thousandths); `readStep` 1/1000 added to the scale tolerance (Lean effectTols, JS READ_STEP). It was not the kinks.
- Verified: see the report (check.sh, tests, dry). Read raws: `gh run download <id> -n cells-gpu-chromium -D <empty dir>` (one id per call; in zsh `set -- $p` does not split), then `node src/trajectory/cells-gpu-cli.mjs summary --in <dir>/raw-chromium.json` in packages/gate-breakpoints.
- Open: WebKit A/A of all cells (follow-up); the 'probe chromium 1280' job status mismatch in run 39819890281 (follow-up for fw ci wait); the dry needs --allow for Trigger.lean and ci/triggers.jsonl (outside the graph writes: the lean.yml row lists the new golden).
- Open, TS stand-ins without a Lean twin yet: swapsOf, restedBefore, carouselCell pairing, worst, painCell's no-flip rule. Follow-up: port the carousel segmentation to Lean with swap-count mismatch graded L and null reps not comparable.
- seriesOf (sort and drop equal keys) is reading glue before the Lean series reducers; the golden panelcell cases have rising keys.

## What exists
- lean/Fw/Gate/TrajectoryGpu.lean: PixTol 1/2 device px, cell_eq_iff, clipRect_of_inset, matchedGrade (E/Q/L), edge/interior 1/100, panel effect, lag, laggedKey/laggedSeries/shiftedGrade/panelGrade/panelCell, painGrade; golden packages/contracts/golden/gate/trajectory-gpu.jsonl.
- packages/gate-breakpoints/src/trajectory/cells-gpu.mjs (twins, cellsOfRaw, tally), cells-gpu-cli.mjs (summary, run), cells-gpu-run.mjs (walker, CI only), registry.mjs GPU_NODES/GPU_CELLS.
- Wiring (outside the task's writes): lean/scripts/TrajectoryGpuGolden.lean, check.sh stage, Fw.lean import, trajectory-probe.yml step `Walk the GPU cells`, Trigger.lean row, ci/triggers.jsonl.

Read first: lean/Fw/Gate/TrajectoryGpu.lean (panelGrade section), then cells-gpu.mjs `panelCell` and `morphCells`.

# trajectory-aa-noise handoff

- Branch worktree-wf_7179b1a5-eff-1, worktree .claude/worktrees/wf_7179b1a5-eff-1, last commit f3b07d2ee (probe commit 2).
- CI runs (branch ci/trajectory-aa-noise, workflow trajectory-probe, engines=chromium widths=390,640 diagnostic):
  - 39860085568 of 76f9a545d: complete, success. All 12 units E (MEASURED, artifact cells-gpu-chromium): carousel E at 390 and 640 (reps E,E,E,E), panel-effect close E,E,E at both widths. Holds this run: 2,2,0,0 per arm at both widths (the earlier run had 4,4,2,2 / 3,3,2,2).
  - 39861846900 of f3b07d2ee: complete, success. All 12 units E. Holds 390 base 2,2,0,0 cand 2,2,0,0; 640 base 1,1,0,0 cand 2,2,0,0.
  - 39863586490 of 3575e73aa: complete, success. All 12 units E. Holds 2,2,0,0 in every arm at both widths.
  - Dispatches used: 3 of 3.
- Hold-out raw being fixed: run 39852684450 (A/A, Chromium 156.0.8078.4); older raws 39823047557, 39823476824, 39824100493.
- Verified (MEASURED on the raw files, offline re-reduction): carousel hold anchor gives E E E E at 390 and 640 on 39852684450 and all E on the three older runs; panel-effect 640 close reps Q,L become E with residual grading, all other units stay E.
- Lean: `lake build Fw.Gate.TrajectoryGpu` green, golden regenerated (198 lines) and `--check` ok; @fw/gate-breakpoints trajectory tests pass (22 + 14 + 3).
- Open: fresh A/A runs showed every unit E in all three; remaining: slot checks (check.sh, package tests, ci-paths, land-inputs); merge main; dry land; review ready.

## Causes
- Carousel (MEASURED): not sub-frame. The hold between container insertion and the first motion row is 4,4,2,2 rows in the base arm and 3,3,2,2 in the cand arm; the motion after onset matches within 0.02 px. Swaps 1 and 2 match only at a whole-frame shift. Why the early holds are longer is INFERRED (warm-up after the start-selling avatar template swap mounts a fresh image).
- Panel-effect 640 close (MEASURED): the opacity model has a kink at m = 4/5; interpolating the pooled base reference across it is 0.0225 off against a 0.01 tolerance. Fix compares residuals against the declared effect.

## Read first
`lean/Fw/Gate/TrajectoryGpu.lean`: residual, modelGrade, dropHold, rebase, holdFrames, settleRun, tailRun; `docs/team/tools/gate.md`.

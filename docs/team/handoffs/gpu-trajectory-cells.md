# gpu-trajectory-cells handoff

- Branch: worktree-wf_9ab25dd7-9aa-1 (CI branch ci/gpu-trajectory-cells, pushed tip 846e11a3 with `[ci:trajectory-probe]` `[trajectory engines=chromium]`)
- Worktree: .claude/worktrees/wf_9ab25dd7-9aa-1 (under the main checkout)
- CI runs: none created by GitHub for the pushes 6bcabccc and 846e11a3 after 20+ min (gh run list --branch shows []); first wait timed out (exit 3)
- Verified: check.sh green (rc 0), dry land `VERDICT dry gpu-trajectory-cells`, package tests (only the 8 files needing playwright-core fail locally),
  golden up to date (112 lines), node twins equal every golden kind, offline A/A on a real probe raw (see below).
- Open: CI A/A runs (>= 3); pain-dark and carousel cells have no CI hook; WebKit A/A follow-up; lead wiring (below).

## What exists
- lean/Fw/Gate/TrajectoryGpu.lean: PixTol 1/2 device px, cell_eq_iff, clipRect_of_inset (+ readers), matchedGrade (E/Q/L), panel lag
  (lagGrade Q up to 1 frame + 1/10 reading slack), painGrade; golden packages/contracts/golden/gate/trajectory-gpu.jsonl.
  `main` lives inside the namespace: a top-level `main` clashes with Fw.Obs.CiStatusGolden in the all-modules imports.
- packages/gate-breakpoints/src/trajectory/cells-gpu.mjs: exact-rational twins, `cellsOfRaw(raw)`, `tally`.
- cells-gpu-cli.mjs: `summary --in <raw-chromium.json or dir>` (nav-clip and panel-effect from the probe's own raw), `run` (standalone walker).
- cells-gpu-run.mjs: walker for all four cells (needs playwright and a site build; never run, CI only).
- registry.mjs: GPU_NODES (nav clip-path next to rect and radius) and GPU_CELLS; MORPH_NODES untouched.

## Offline A/A on a real raw (run 39781320030, pages split by rep: reps 0-2 as base, 3-4 as cand; not a CI result of this task)
nav-clip E 8 of 8; panel-effect E 4, Q 4, L 0, lag max 0.010 frames (the Q is the pooled reference's straight lines across the
opacity and blur kinks at m 0.08 and 0.8, not a lag).

## Lead wiring (outside the task's writes)
- lean/scripts/TrajectoryGpuGolden.lean: `import Fw.Gate.TrajectoryGpu` and `def main (args : List String) : IO UInt32 := Fw.Gate.TrajectoryGpu.main args`;
  check.sh line `job "trajectory-gpu golden check" lake env lean --run scripts/TrajectoryGpuGolden.lean --check ../packages/contracts/golden/gate/trajectory-gpu.jsonl`.
- trajectory-probe workflow step: `node src/trajectory/cells-gpu-cli.mjs run --engine chromium --out out/cells-gpu` (cwd packages/gate-breakpoints).

## Read first
lean/Fw/Gate/TrajectoryGpu.lean, then cells-gpu.mjs `cellsOfRaw`.

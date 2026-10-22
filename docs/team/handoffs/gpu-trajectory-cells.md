# gpu-trajectory-cells handoff

- Branch: worktree-wf_9ab25dd7-9aa-1 (CI branch ci/gpu-trajectory-cells, pushed tip 6bcabccc)
- Worktree: .claude/worktrees/wf_9ab25dd7-9aa-1 (under the main checkout)
- Last commit: 6bcabccc (probe commit, carries `[ci:trajectory-probe]` and `[trajectory engines=chromium]`)
- CI runs: trajectory-probe (A/A on faithful, chromium): pushed, run id pending (see `pnpm fw ci --branch ci/gpu-trajectory-cells`)
- Verified: Lean TrajectoryGpu compiles, golden up to date (112 lines); node twins match every golden kind (test/trajectory-gpu.test.mjs);
  synthetic raw tests (test/trajectory-gpu-cells.test.mjs) pass. Package tests: only the 8 files that need playwright-core fail locally.
- Open: CI A/A numbers; pain-dark and carousel cells need a CI hook (see below); WebKit A/A follow-up; check.sh golden line.

## What exists
- lean/Fw/Gate/TrajectoryGpu.lean: PixTol 1/2 device px, cell_eq_iff, clipRect_of_inset (+ readers), matchedGrade (E/Q/L), panel lag
  (lagGrade Q up to 1 frame + 1/10 reading slack), painGrade; golden packages/contracts/golden/gate/trajectory-gpu.jsonl.
- packages/gate-breakpoints/src/trajectory/cells-gpu.mjs: exact-rational twins, `cellsOfRaw(raw)`, `tally`.
- cells-gpu-cli.mjs: `summary --in <raw-chromium.json or dir>` (nav-clip and panel-effect from the probe's own raw), `run` (standalone walker).
- cells-gpu-run.mjs: walker for all four cells (needs playwright and a site build; never run yet, CI only).
- registry.mjs: GPU_NODES (nav clip-path next to rect and radius) and GPU_CELLS; MORPH_NODES untouched.

## Conventions
- Grades are Lean's: E is equal within half a device px at the same morph value, Q is a shift of at most one frame, L is any other.
- A nav reading without clip-path is graded only when the candidate's config hash equals the faithful one; else `not comparable`.

## Read first
lean/Fw/Gate/TrajectoryGpu.lean, then cells-gpu.mjs `cellsOfRaw`.

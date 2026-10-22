# gpu-trajectory-cells handoff

- Round 2 (this): branch worktree-wf_9ab25dd7-9aa-1, worktree .claude/worktrees/wf_9ab25dd7-9aa-1; wiring done (TrajectoryGpuGolden.lean, check.sh stage, Fw.lean, trajectory-probe.yml step `Walk the GPU cells`, artifact cells-gpu-chromium, Trigger.lean lean.yml row input + triggers.jsonl regenerated).
  One local debug run (390, rep 1) showed carousel A/A as L: swap keys were rAF timestamps (1.7 ms jitter) and the swap vector changes length (20 children inside, 16 at rest). Fixed in cells-gpu.mjs swapsOf (frame-count key, full-count vectors only); local debug showed E for pain and carousel (not a result).
  Round-2 dispatches (sha 6f4aea1c, chromium A/A, cells step in the probe job 390, artifact cells-gpu-chromium): 39823047557, 39823476824, 39824100493 (all queued at 17:36Z, GitHub degraded). Local check.sh green at 6f4aea1c.
  Read: `gh run download <id> -n cells-gpu-chromium -D <empty dir>`, then `node src/trajectory/cells-gpu-cli.mjs summary --in <dir>/raw-chromium.json` in packages/gate-breakpoints.
- Branch: worktree-wf_9ab25dd7-9aa-1, worktree .claude/worktrees/wf_9ab25dd7-9aa-1 (CI branch ci/gpu-trajectory-cells, pushed tip 846e11a3 with `[ci:trajectory-probe]` `[trajectory engines=chromium]`)
- CI runs: pushes 6bcabccc and 846e11a3 created NO run (GitHub, gh run list --branch []). Dispatched instead (`pnpm -s fw run --trajectory --engines chromium --ref ci/gpu-trajectory-cells`, sha 846e11a3, real A/A: base and cand are both the rewrite):
  39817825181, 39818033923, 39818039961 complete/pass (calibration); 39819884506, 39819890281 hold-out for the 1/100 edge (nav-clip E 8/8 each, panel L 0, lag max 0.019/0.020; in the latter `fw ci wait` named job probe chromium 1280 not success).
  Read: `gh run download <id> -n trajectory-chromium -D <empty dir>`, then `node src/trajectory/cells-gpu-cli.mjs summary --in <dir>/raw-chromium.json` in packages/gate-breakpoints.
- Verified: check.sh green, dry land ok, tests pass (8 playwright files fail locally only), golden 121 lines, twins equal every kind.
- Open: pain-dark and carousel cells have no CI hook; WebKit A/A follow-up; lead wiring (below).

## What exists
- lean/Fw/Gate/TrajectoryGpu.lean: PixTol 1/2 device px, cell_eq_iff, clipRect_of_inset (+ readers), matchedGrade (E/Q/L), panel lag
  (lagGrade Q up to 1 frame + 1/10 reading slack), painGrade; golden packages/contracts/golden/gate/trajectory-gpu.jsonl.
  `main` is inside the namespace (a second top-level `main` clashes in the all-modules imports).
- packages/gate-breakpoints/src/trajectory/cells-gpu.mjs: exact-rational twins, `cellsOfRaw(raw)`, `tally`.
- cells-gpu-cli.mjs: `summary --in <raw-chromium.json or dir>` (nav-clip and panel-effect from the probe's own raw), `run` (standalone walker).
- cells-gpu-run.mjs: walker for all four cells (needs playwright and a site build; never run, CI only).
- registry.mjs: GPU_NODES (nav clip-path next to rect and radius) and GPU_CELLS; MORPH_NODES untouched.

## A/A on CI (the 3 calibration runs, chromium, 8 units each: 4 widths x open/close)
First reading (all rows): nav-clip L at 1280 close in 2 of 3 runs. Cause: at 1280 the nav width keeps settling (987.4 to 984.1 px) while m sits
clamped at 0 to 3e-4, so rows there are not a function of m. Fix: Lean `edge` = 1/100 and `interior` (only 1/100 < m < 99/100 forms a series).
After it: nav-clip E 8/8 in all three; panel-effect E 5/3/4, Q 3/5/4, L 0; lag max 0.016, 0.016, 0.020 frames. The Q cases are the pooled
reference's straight lines across the opacity and blur kinks (m 0.08, 0.8), not a lag. The edge was fit on these 3; the 2 hold-out runs agree.

## Lead wiring (outside the task's writes)
- lean/scripts/TrajectoryGpuGolden.lean: `import Fw.Gate.TrajectoryGpu` and `def main (args : List String) : IO UInt32 := Fw.Gate.TrajectoryGpu.main args`;
  check.sh line `job "trajectory-gpu golden check" lake env lean --run scripts/TrajectoryGpuGolden.lean --check ../packages/contracts/golden/gate/trajectory-gpu.jsonl`.
- trajectory-probe workflow step: `node src/trajectory/cells-gpu-cli.mjs run --engine chromium --out out/cells-gpu` (cwd packages/gate-breakpoints).

Read first: lean/Fw/Gate/TrajectoryGpu.lean, then cells-gpu.mjs `cellsOfRaw`.

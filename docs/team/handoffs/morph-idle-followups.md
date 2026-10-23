Branch: worktree-wf_1a3f883b-68d-1 (CI branch ci/morph-idle-followups). Worktree: .claude/worktrees/wf_1a3f883b-68d-1
Last commit: see git log (final handoff commit on top of 2de2e8b82).
CI runs: webkit-sim 39915136431 base and 39915146774 flag (morph.columns:idle-none), both success; lag=true cost=only target=rewrite vms=3
(3 VMs x 2 passes = 6 passes per arm). Source runs: 39903977820 base, 39903974246 flag (2 passes each). 2 of 6 dispatches used.
Verdict (MEASURED, Lean-proved on the recorded sums): per-frame WebKit Paint/Composite on the morph zone is UNRESOLVED (overlap in all 8 cells,
both views); layers down 128 -> 112 stays. Theorems run_39903977820_overlap, run_39915136431_overlap/_outcome in lean/Fw/Measure/WkCost.lean.
Verified: lean/scripts/check.sh green; @fw/measure-webkit (407), @fw/site (6523 + typecheck), @fw/runner, scripts/ci-paths.test.mjs pass.
Delivered: reducer (Lean + packages/measure-webkit/src/lag/morphcost.mjs + CLI morph-verdict), goldens in wkcost.jsonl (morphNorm, morphCells,
morphOutcome, idleHold), IdleHold model lean/Fw/Measure/IdleHold.lean, site tests
morph.panel/scene.golden.test.ts, morph.columns/idle.golden.test.ts (writer -> attribute -> removal), idle.hold.golden.test.ts.
Outside the writes: apps/runner/src/land.ts (one declared read of wkcost.jsonl for apps/site, required by land-inputs.test.ts).
Open: item 4 Chromium base 28107 re-baseline on the font image waits for counts-font-fidelity (not landed). A phone arm would settle the sign.
TS stand-ins: MutationObserver wiring in morph.columns/index.tsx; IdleHold's element-keyed Map (model keys by id).
Read first: research/notes/2026/10-20-morph-idle-none.md (last sections), lean/Fw/Measure/WkCost.lean, lean/Fw/Measure/IdleHold.lean.

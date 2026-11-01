branch: worktree-wf_779ff154-e9a-1
worktree: .claude/worktrees/wf_779ff154-e9a-1
last commit: see `git log -1` (state below is at the commit that adds this file)
CI runs: none pushed

State: Lean Fw.Ops.LandDry has Kind, kindDep, edge, deps with lake_serial, core_after_builds, install_first,
kindDep_rank; golden packages/contracts/golden/ops/land-dry-deps.jsonl (guard in LandDryGolden.lean). land.ts: checkKind,
kindDeps, checkDeps (TS stand-in, golden-checked in apps/runner/test/land-parallel.test.ts). Log line now "lints not judged".
Measured (note research/notes/2026/11-01-dry-land-waves.md): warm 26.5/30.1 s before, 16.2/16.2 s after; cold 78.6 / 65.2 s
(built 28); the fwcore-build span starts after the lake-lint span in all six runs.
Verified: runner package test (120 files), Lean module builds. Open: see the final report.
Removed: scratch branches dlw-scratch-b/c and worktrees .claude/worktrees/dlw-before, dlw-scratchbr.
Read first: the note, then lean/Fw/Ops/LandDry.lean (deps).
Pitfall: the pre-commit hook builds committed lean edits into the shared Lake artifact cache, so a scratch lean edit shows
built 0 unless the branch base differs from main in a lean module the edit imports.

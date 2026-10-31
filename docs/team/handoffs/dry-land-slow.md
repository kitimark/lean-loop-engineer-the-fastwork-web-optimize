# dry-land-slow handoff

Branch: worktree-wf_779ff154-e9a-1. Worktree: .claude/worktrees/wf_779ff154-e9a-1. No CI runs (local tooling task, no CI push).
State: Lean rule + golden + TS stand-in + land.ts change committed; note written. Last commit: see `git log -1`.

Verified (MEASURED, my dry lands): same change set, load 5: 20.8 s before, 14.2 s after; same VERDICT dry.
Cause: no step grew; slow samples selected lake + workflow lint + overflow-widths and the three phases (reads, lints,
local tests) ran in series. Details: research/notes/2026/11-01-dry-land-slow.md.

Files: lean/Fw/Ops/LandDry.lean (+Golden, Fw.lean import), packages/contracts/golden/ops/land-dry.jsonl (generated:
`cd lean && lake env lean --run <script calling Fw.Ops.LandDry.jsonl>`; the #guard in LandDryGolden fails when stale),
apps/runner/src/land-dry.ts, land.ts (runChecksSplit, one wave), apps/runner/test/land-dry-waves.test.ts (outside the graph
writes: apps/runner/test/**).

Open: slow-sample extras (overflow-widths, workflow lint) could not be selected inside this task's writes, so the
after-number for them is INFERRED (about 21 s). Fwcore-build step after a lake lint is a no-op (follow-up). Pre-commit
on ledger.json takes about 3 minutes (preset check); I did not touch the ledger.
Read first: the note, then apps/runner/src/land.ts around `DRY_WAVES`.

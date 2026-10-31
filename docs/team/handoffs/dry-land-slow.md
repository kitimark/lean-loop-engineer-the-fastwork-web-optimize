# dry-land-slow handoff

Branch: worktree-wf_779ff154-e9a-1. Worktree: .claude/worktrees/wf_779ff154-e9a-1. No CI runs (local tooling task, no CI push).
State: Lean rule + golden + TS stand-in + land.ts change committed; note written. Last commit: see `git log -1`.

Verified (MEASURED, my dry lands; timings rows named in the note): small set 20.8 s -> 14.2 s (d8c021d 1793483732538, 4ed5e45 1793483702472); slow set (workflow + lean/Fw, lake cache off) 25.2/26.0 s before -> 15.8/15.8 s after (startMs 1793485115727, 1793485142154, 1793485078913, 1793485196559); all VERDICT dry. Round 2: refusal now from dryVerdict in land.ts.
Cause: no step grew; slow samples selected lake + workflow lint + overflow-widths and the three phases (reads, lints,
local tests) ran in series. Details: research/notes/2026/11-01-dry-land-slow.md.

Files: lean/Fw/Ops/LandDry.lean (+Golden, Fw.lean import), packages/contracts/golden/ops/land-dry.jsonl (generated:
`cd lean && lake env lean --run <script calling Fw.Ops.LandDry.jsonl>`; the #guard in LandDryGolden fails when stale),
apps/runner/src/land-dry.ts, land.ts (runChecksSplit, one wave), apps/runner/test/land-dry-waves.test.ts (outside the graph
writes: apps/runner/test/**).

Open: slow-sample extras (overflow-widths, workflow lint) could not be selected inside this task's writes, so the
after-number is now MEASURED (scratch/dls-slowset, round 2). No measured row for a set over budget before the fix; see note. If an inferred number remains: about 2.3 + 7.6 + 1.0 + 12.0 = 22.9 s at the same load (offsets of sample 001d247), before the slowdown of running the checks together (reads test 9.8 s before, 11.2 s after). Fwcore-build step after a lake lint is a no-op (follow-up). Pre-commit
on ledger.json takes about 3 minutes (preset check); I did not touch the ledger.
Read first: the note, then apps/runner/src/land.ts around `DRY_WAVES`.

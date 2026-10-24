branch: worktree-wf_1cff5c71-27c-1  worktree: .claude/worktrees/wf_1cff5c71-27c-1 (under the repo root)
last commit: see git log; CI runs: none (no CI dispatch in this task)

State: in progress. Lean theorems, goldens, emitters and tests written; check.sh, runner tests and dry land to run.
Verified so far: lake build Fw.Obs.Timing (theorems + #guards), TimingGolden --check, vitest timing-work/slow/alert (local debug run).
Read first: research/notes/2026/10-2x-lake-span-mods.md.
Conventions: lake member rule is Fw.Obs.Timing.lakeBuilt?; three twins (Lean, timing.ts lakeMember, awk lake_built_member in scripts/lake-slot-lib.sh) are tied by golden/obs/timing-lake.jsonl.

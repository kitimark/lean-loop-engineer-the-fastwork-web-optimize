branch: worktree-wf_a666a56e-9e7-1
worktree: .claude/worktrees/wf_a666a56e-9e7-1
no CI run pushed (reproduced from text; accepted limit)

Cause (INFERRED, mechanism CONFIRMED): the collector writes a process start as `now - ageMs` (next.ts child fact, watch-collect.ts
sessionProcs); ageMs is parsed from `ps etime`. procps computes etime as `boot_tics - start_time` (library/pids.c:287@v4.0.4),
two bases that can disagree in a container or restored VM, so the age may exceed the epoch (Linux text shape
`25000-03:04:05`). Then startedAt < 0 and fwcore's `nat` refused it: "field startedAt: expected a non-negative integer".
The error text says obs.health because coreCaller labels every op so (watch.ts:57); the failing op was obs.next.

Fix: TS `startFromAge` (watch-collect.ts) writes -1 for an age longer than the clock. Lean `startOf`/`unknownStart`
(Fw/Wire/Obs.lean) reads a negative integer start as unknown (2^64, age 0): theorems startOf_nat, startOf_neg,
unknownStart_age, oldB_unknown, overdueB_unknown, procLongB_unknown. Fractions are still refused. Goldens: health.jsonl (3
cases), next.jsonl (3 cases). Test: apps/runner/test/next.test.ts "an etime longer than the clock".

Flake rate from land history: 1 failure of this class (r316, ci-state-fast land, CircleCI job 408) in 457 lands; CircleCI
carries only overflow, so the per-CircleCI-run rate is unknown.
Open: none. Read first: lean/Fw/Wire/Obs.lean startOf.

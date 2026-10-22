Branch: worktree-wf_e3ff40d3-d74-1
Worktree: .claude/worktrees/wf_e3ff40d3-d74-1
CI runs: none (local Lean and runner code, no CI push)

State: the six follow-ups of slot-span-key, each with a Lean rule, a golden or test.
1. Wait spans: tool `fw wait` (`Timing.waitTool`, TS `WAIT_TOOL`), its own default budget `Params.waitBudgetMs` (30 min) inside
   `budgetOf`. Theorems `budgetOf_wait/_work`, `wait_within_budget_not_slow`, `wait_over_budget_slow`. Old wait samples (tool `fw`) keep the old key.
2. `cmdKey`: `fw` is a launcher, key `pnpm fw <sub>` (`fwLauncher`, `subOf`); goldens in slot-key.jsonl.
3. `stepKey`, `seenKeys` (suffix and seen-set rule), `kindCap` (land 8, sim 4, else 24); theorems `seenKeys_mem/_append`,
   `stepKey_prefix`, `capKey_bounded`. Golden slot-seen.jsonl. TS `seenInFile` reads the whole log in 4 MB chunks (63 ms for 27 MB).
4. slot.ts `run`: `endRun` in a finally with `EXIT_ERROR` (70); the wait span too; test with a spawn that throws.
5. slot-span.test.ts: `synthetic()` marks the made-up samples (`synthetic: true`).
6. `LandDry.dryTotalStep` / `runsLakeBuild` (+ theorems), golden dry-step.jsonl, TS `dryTotalStep` in land.ts; `land()` renames the
   total span to `dry total lake` when the lint plan has the axiom check or fwcore is built first.

Verified: lake build; runner package test (slot-span 44 tests); golden check; fwcore rebuilt through the slot.
Limits: past samples keep their old keys; the slot-run span `slot run land pnpm fw land dry` is still bimodal (the plan is known only
inside the child). Wait budget 30 min is a chosen value, not measured.
Writes: apps/runner/src/slot.ts and the new goldens dry-step.jsonl, slot-seen.jsonl under obs/*.jsonl.
Read first: SlotKey section of lean/Fw/Obs/Timing.lean, then apps/runner/src/slot-span.ts.

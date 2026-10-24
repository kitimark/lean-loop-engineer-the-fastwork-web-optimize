# Handoff: reap-exit-fold
Branch: worktree-wf_225504a4-348-1
Worktree: .claude/worktrees/wf_225504a4-348-1
Last commit: see `git log -1` on the branch (main merged after the TS commit).
CI runs: none (no CI needed).

## Verified
- `sh lean/scripts/check.sh` green (via slot, after merging main); goldens regenerate with `cd lean && lake env lean --run scripts/ReapGolden.lean --check`.
- apps/runner `test:run` (tsc + vitest): 107 files, 3425 tests pass; `node --test scripts/ci-paths.test.mjs` 56 pass.
- `plan lint`: 0 errors, no writesClosure row for this task.

## What changed
- Lean `Fw.Ops.Reap`: `InputD.promote`, `autoSet`; log fold (`Rec`, `foldSeen`, `outcomeOf`, `dedupe`); coverage (`slotSec` 1800, 7 days, `covered`, `verdictOf`); `newHeld`, `heldOf`, `wtOf`, `simNew`; ops `ops.reapFold`, `ops.reapLog`, `ops.reapSimNew`; `ops.reapPlan` returns `held`; `ops.reapHeld` entries carry `wt`.
- Lean `Fw.Obs.Next`: `Child.start`, `killChildB` (pid and start must match). Goldens: `reap-fold.jsonl`, `next.jsonl` (60 cases), reap*.jsonl.
- TS: `reap.ts` (`heldAll`, `heldPass`, `readLog` 4 MiB tail, `recordHeld` held+tick, `--exit`, `promotedKinds`, stopped `targets`), `watch-reap.ts` (one pass), `next.ts` (`ChildFact.start`, `reapHeldFacts(pass)`), `slot.ts` (`parseBooted`, `simBefore`, `simNew` at release), `slot-core.ts` (`simNew` twin).
- Docs: `docs/team/tools/reap.md`, `watch.md`, `watch-rules.md`.

## Decisions and open items
- 7-day coverage: verdict today is MEASURED "not yet 7 days of coverage"; E and F stay advice until the log covers 7 days.
- Explicit `fw reap --stop` of E/F counts as a true orphan stop (documented in reap.md).
- TS stand-ins: `simNew` in slot-core.ts (checked against the golden rows in `test/reap-fold.test.ts`); `readLog` is glue.
- Read first: `lean/Fw/Ops/Reap.lean` fold section, then `apps/runner/src/reap.ts` `recordHeld`/`foldLog`.

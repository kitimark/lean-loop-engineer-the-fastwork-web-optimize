Branch: worktree-wf_18899704-037-1. Worktree: .claude/worktrees/wf_18899704-037-1. No CI runs (none pushed).

State: Lean rule, golden, land glue, check change, doc written; lean check.sh green, runner (3463) and console-api (782) tests green, ci-paths green.
- Lean: lean/Fw/Console/LedgerAlloc.lean (`assign`, `assign_keeps`, `assign_unique`, `new_above`, `start_eq_of_top`); imported in lean/Fw.lean and lean/FwTestMain.lean (golden run + `--write-ledger-alloc-golden`).
- Golden: packages/contracts/golden/console/ledger-alloc.jsonl; replay: apps/runner/test/ledger-alloc.test.ts against `allocN` in apps/runner/src/land.ts.
- Land: `allocLedger(dir, mainRef)` in land.ts runs in the dry, the pre-lock and the fallback merge paths, right after the evidence write; it re-stages the ledger so the merge commit holds the numbers.
- Check: apps/console-api/src/ledger-unique.ts `candidateNs` skips rows without a numeric n.
- Doc: docs/team/tools/land.md, last section.

TS stand-in: `allocN` is checked against the golden (no Lean call at run time); `allocLedger` glue is tested in a scratch repo.
Open: writes outside the task list: lean/Fw.lean, lean/FwTestMain.lean, apps/console-api/src/ledger-unique.ts. No trigger row needed (the golden runs inside `lake test`, like ledger-unique).
Convention: new ledger rows carry no n; refer to rows by id. Existing rows are not renumbered.
Read first: lean/Fw/Console/LedgerAlloc.lean, land.ts `allocLedger`.

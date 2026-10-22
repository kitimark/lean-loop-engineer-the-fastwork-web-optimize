Branch: worktree-wf_c64abe11-ec7-1
Worktree: .claude/worktrees/wf_c64abe11-ec7-1
Last commit: 083b33ac (polish 3cc0eb94).
CI runs: none pushed (the unit is Lean + a TS unit test; no CI trigger needed)

State
- Lean: lean/Fw/Obs/Fold.lean section "Open tool calls": `stepEv`, `inflightOf`, theorems `assistant_clears`,
  `older_call_gone`, `assistant_nocalls`, `same_msg_keeps`, `inflight_resume`, `open_pass_eq_full`; cases feed the golden.
- Golden: packages/contracts/golden/obs/watch-inflight.jsonl, written by lean/Fw/Obs/Golden.lean (one writer/check line
  added there, outside the task's writes) via `cd lean && lake env lean --run scripts/ObsGolden.lean`.
- TS: apps/runner/src/watch-fold.ts keeps each open call with its message id; an assistant record (id, or a unique
  key when it has none) voids calls of other messages in both `sum.open` and `sig.open`. FOLD_SCHEMA goes from 1 to 2, which drops
  cache entries of the old shape. Tests: apps/runner/test/watch-fold.test.ts (golden, resume at every cut,
  synthetic missing-result transcript, parallel calls).
Verified: check.sh green, runner tests 2605/2605 pass.
Open: bgTasks end detection unchanged (accepted limit). Cause of the missing result record is INFERRED.

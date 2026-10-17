# lean-math-fix-r5 handoff

**State:** done on branch `worktree-agent-a5300835fce030fc7` (one commit after 28b18ee). All 62 `disagree` rows of
`research/notes/2026/10-17-math-review-r5-c4ca5ad.md` fixed in docstrings; `lean/scripts/check.sh` green
(mathview lint 0 failing, quantifier warnings 88 -> 84).

**Files:** lean/Fw/Sched/Admit.lean (12), lean/Fw/Sched/ParMetrics.lean (12), lean/Fw/Serve.lean (15),
lean/Fw/Ops/Meter.lean (4), PathCheck.lean (1), SpawnGuard.lean (14), Usage.lean (3), lean/Fw/Measure/WebKit.lean
(reduceSteps: full 4-tuple restored, last component kept as a list-filter length).

**Statement changes:** none. Only binder renames `r` -> `ρ` (Role) in SpawnGuard trap_worktree_role_as_teammate,
trap_exact, teammate_with_isolation_denied, accepted_nested_read_only, so the binder lint sees the `\forall i, \rho`
in the math (same types and hypotheses).

**Conventions followed:**
- Nodup of a mapped list: "[f(a) | a in l] has no repeats", never "f injective on l".
- List-filter lengths: `\big|[\, x \in L \mid P \,]\big|` (repeats counted), never set-builder.
- Nat inputs divided in Rat: `\in \mathbb{Q}` plus "(cast to Q; x/0 = 0)".
- First-match cases (capFail, roleCheck, check, writeAt/devAt scan order) written with the negated earlier guards.
- Edge cases stated: maxl([]) = 0 (cp), Array.modify out of range leaves rows (Tbl.modify, modify_eq), HashMap getD
  absent = 0 (runIdx, runIdx_get, fastRow), floor(now/0) = 0 (Meter).
- Every theorem binder from `variable` (Serve.Tbl: alpha, key, T, k, f) written in the leading forall.

**Open items:** the math view page was not regenerated (lead step); the 62 rows need a round-6 re-review. Remaining
lint warnings in these modules are pre-existing, not checked here (Usage join_* `a/b/c`, get_ins `r`, PathCheck `paths`, Meter once_per_window `p`, Serve refused_unchanged/accepted_changed `d`), not in the r5 list.

**Read first:** the r5 note's "Recurring problems", then `git show` of this branch's commit.

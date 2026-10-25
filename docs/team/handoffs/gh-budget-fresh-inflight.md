# Handoff: gh-budget-fresh-inflight
Branch: worktree-wf_b2422c29-dea-1. Worktree: .claude/worktrees/wf_b2422c29-dea-1. No CI push, no CI run ids (unit tests only).
State: Lean rules + golden + TS glue + tests written; final checks listed at the end once run.

What changed
- lean/Fw/Ci/Attempt.lean: `inflightS` (300 s), `trusted` (completed -> `fresh`, unfinished -> within `inflightS`), theorems
  trusted_completed / trusted_inflight_young / trusted_inflight_stale / trusted_old_never; `uncoveredMax` 2, `uncoveredCode` 6,
  `uncoveredExit`, theorems uncovered_once_waits / uncovered_repeated_exits / uncoveredCode_ne_timeout.
- lean/Fw/Ci/AttemptGolden.lean generates packages/contracts/golden/ci/attempt-inflight.jsonl; wired in lean/scripts/check.sh and
  lean/Fw/Ci/Trigger.lean (+ regenerated triggers.jsonl).
- packages/gh-budget/src/wait.ts: `trustedRow` (TS stand-in for the unfinished branch; the finished branch calls fwcore `ci.attempt`),
  used by createdOf cached()/listed(); `uncoveredSince` + exit 6 in the run-wait loop. Exit 6 chosen because 5 means gh unavailable in land-remote.
- packages/gh-budget/test/inflight.test.ts: golden replay, stale queued row of a completed run returns in 0 virtual seconds with 1 view,
  bound edge, one view per wait, gh failure not retried, uncovered exit.

TS stand-ins (Lean replacement later): trustedRow unfinished branch and the uncovered constants (golden-checked; no fwcore Wire op was added, to stay inside the task's writes).
Open: docs/team/tools mention of exit 6 not written (outside writes). The 47 moved rows stay moved.

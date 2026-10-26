# Handoff: gh-budget-fresh-inflight (round 2)
Branch: worktree-wf_b2422c29-dea-1. Worktree: .claude/worktrees/wf_b2422c29-dea-1. No CI push, no CI run ids (unit tests only).
Verified (round 2): lake build + lake test green; @fw/gh-budget test 101/101; check.sh, ci-paths, land-inputs, dry land: see the report.

Round 2 changes (review r1)
- B: Lean `uncoveredLookbackS` (1200) and `uncoveredExit regAt times` (>= 2 incidents with time >= regAt - lookback, one at or after regAt);
  theorems uncovered_none_waits / once_waits / two_slices_exit (567 s apart) / old_ignored / all_before_waits. Golden
  attempt-inflight.jsonl now carries regAt, times, lookback. TS: wait.ts `uncoveredExit(regAt, times)`, `uncoveredSince(env, id, regAt - UNCOVERED_LOOKBACK_S)`.
  Test: two consecutive 540 s waitFor calls, the poller logs one uncovered incident per wait, the second returns 6.
- F1: merged main, took main's triggers.jsonl, regenerated with `lake test -- --write-ci-trigger-golden`.
- F2/F3: AttemptGolden.lean module doc and Attempt.lean header text as the reviewer wrote.

TS stand-ins (Lean replacement later): trustedRow unfinished branch, uncoveredExit and the constants (golden-checked).
Open follow-ups: move `import Fw.Ci.AttemptGolden` out of Trigger.lean; fwcore Wire op for trusted/uncoveredExit; document exit 6 in
docs/team/tools and map it in land-remote.ts. The 47 moved rows stay moved.

branch: worktree-wf_85b6e7f2-42f-1
worktree: .claude/worktrees/wf_85b6e7f2-42f-1 (under the repo root)
last commit: see `git log -1` (53e104f07 plus the handoff commit)
CI runs: none (no CI push; the task needs none)

# polish-commit-failsafe

Cause of the two `polish-commit error` runs (journals wf_85b609fd-a1c, wf_cdc2f175-f40): the kept comment cuts left a
Lean file that does not build (Trajectory.lean parse error at 5772/5778; Timing.lean 1663/1666). The pre-commit hook
(checkmap `lakeBuild`) refused the commit, `git commit` threw, and `fw polish commit` stopped with the cuts staged and
unstaged. The `<file>-e` stray came from comment-sicko running BSD `sed -i -e`.

Done
- Lean `Fw.Plan.Polish.settle` (St, Act, run): settle_clean, settle_untracked_before, settle_keeps_before,
  settle_removes_created, settle_committed, settle_idempotent; wire op `plan.polishSettle`; goldens in polish.jsonl.
- `fw polish plan` saves the untracked files as a baseline (git dir `fw-polish-untracked`); `fw polish commit` ends every
  outcome (committed, nothing, refused, error) with `settleTree`: index reset, dirty paths restored, untracked files not in
  the baseline deleted, one `cleanup:` line. No baseline: nothing is deleted. fwcore down: all dirty restored (TS stand-in).
- build-review.js: failed or refused commit reports `reason` and `cleanup`; comment-sicko prompt says Edit tool only.
- comment-sicko.md: Edit tool only, no `sed -i`.

Verified: runner polish test 29/29, scripts/build-review.test.mjs 17/17, ci-paths 56/56, lake build.

Open / follow-ups
- The cut that breaks the build is still produced; it is now reverted instead of left. A pre-commit build check of the
  kept edits, or dropping Bash from comment-sicko's tools, is a follow-up.
- A refused commit (dirty main checkout) now also restores the edits; rerun the Polish stage after the main checkout is clean.
- docs/team/tools/polish.md is outside this task's writes and not updated (add the `plan.polishSettle` and cleanup line).

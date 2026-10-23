branch: worktree-wf_85b6e7f2-42f-1
worktree: .claude/worktrees/wf_85b6e7f2-42f-1
last commit: see `git log -1`
CI runs: none (no CI push; the task needs none)

# polish-commit-failsafe (round 2)

Real cause of the two `polish-commit error` runs (wf_85b609fd-a1c Trajectory.lean 5778:44, wf_cdc2f175-f40 Timing.lean):
comment-sicko's cut was clean. `fw polish commit` restored an out-of-hunk deletion with `git apply -R --unidiff-zero` on a
single zero-context hunk; git places it by the new-side line, which an earlier kept deletion had shifted, so a deleted
3-line docstring came back 7 lines too low inside a do-block. The build hook then refused the commit.

Done
- Restore: `walkHunks`/`keptText` (apps/runner/src/polish.ts) build the kept text from `git show HEAD:<path>`, walking the
  -U0 hunks in ascending order. Lean `Fw.Plan.Polish.walk` (+ `walk_restored`, `walk_keep`, `walk_restore`,
  `walk_skip_restored`), op `plan.polishWalk`, 5 golden rows replayed by TS (TS stand-in checked against goldens).
- Regression: real-git test "a kept deletion above and a restored 3-line deletion below ..." in apps/runner/test/polish.test.ts.
  The Trajectory file itself was not replayed (needs the journal's exact edit set).
- Settle backstop kept; now baseline-aware of dirty paths: `settle before dirtyBefore s`, theorems `settle_dirty_before`,
  `settle_keeps_dirty_before`, `settle_restores_clean_only`; `fw polish plan` saves `fw-polish-dirty`; dirty-at-plan paths
  are left (not committed, not restored). Test "a path the builder left dirty at plan time ...".
- docs/team/tools/polish.md documents walk, settle and the cleanup line.

Open
- comment-sicko's judgement unchanged; with fwcore down the TS stand-in restores all non-baseline dirty paths.
- Builder-dirty files the polish stage also edited are left alone (accepted limit).

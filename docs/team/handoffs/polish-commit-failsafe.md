branch: worktree-wf_85b6e7f2-42f-1
worktree: .claude/worktrees/wf_85b6e7f2-42f-1
last commit: see `git log -1` (round 3, final design round, items 1-6 of scratchpad/pcf/final-spec.md)
CI runs: none (no CI push; the task needs none)

# polish-commit-failsafe (round 3)

Live cause of round 3: morph-real-wheel polish ended `applied 2/3` and left probe.mjs with a deleted `/**` opener.

Done (round 3 commit)
- Invariant stated in docs/team/tools/polish.md: commit tree differs from HEAD only in keep; keep/restore/scopes disjoint
  from plan-time dirty; settle touches only non-baseline; no baseline = refused.
- apps/runner/src/polish.ts: `git commit -- <keep>`; no `git reset`; no-baseline refusal; settleTree restores nothing
  without a dirty baseline and deletes both baseline files; plan passes `dirtyBefore` to Lean, prints `skip`; commit prints
  `left` from Lean (TS `mine` filter deleted).
- Lean: `undirty`, theorem `dirty_never_scoped` (Plan/Polish.lean), `opPolishPlan` takes `dirtyBefore`, replies `left`;
  golden regenerated with FW_WRITE_POLISH_GOLDEN=1 (new row).
- Real-git tests in apps/runner/test/polish.test.ts: pathspec commit (staged q stays staged, HEAD lists only file),
  hook-refused with staged new file, no-baseline refusal and second-commit refusal, plan skip line.

Open: accepted limits of final-spec.md (plan-time snapshot, stagedChecks telemetry, Trajectory not replayed, build-review-worktree-path follow-up).
Read first: docs/team/tools/polish.md, apps/runner/src/polish.ts settleTree and the commit branch.

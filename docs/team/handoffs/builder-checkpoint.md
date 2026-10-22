# builder-checkpoint handoff

State: branch worktree-wf_acf9f8fb-3be-1; see `git log` for the commit.
Read first: .claude/workflows/build-review.js (CHECKPOINT constant, the no-result return after the builder agent call).

Done:
- The builder prompt carries a checkpoint rule: handoff docs/team/handoffs/<task>.md after the first CI push, updated after each CI run and before any wait over 10 min.
- A builder result that is null or lacks branch/commit returns [{task, worktree, branch, handoff, state: 'no-result'}] and skips gate, review and polish. With an isolated worktree the script does not know the path, so worktree/branch say where to look (the handoff's first lines).
- scripts/build-review.test.mjs runs the whole script with a stub agent (null result, result without branch/commit, named worktree, prompt text). 3 pass.
- Incident inc-builder-no-result in docs/team/incidents/ledger.json (`pnpm -s fw incidents lint`: 0 errors).

Open: no hard time limit on builders (follow-up). Running workflows keep the script they loaded; the change applies to workflows started after the land.
Writes outside the graph task: scripts/build-review.test.mjs.

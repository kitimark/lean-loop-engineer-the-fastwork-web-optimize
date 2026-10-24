branch: worktree-wf_84ab31ff-033-1
worktree: .claude/worktrees/wf_84ab31ff-033-1
last commit: see `git log -1` on the branch
CI runs: none (accepted limit: no CI run; local tests only)

State
- (1) Decision: run under the parent's lease, not refuse (`fw land` runs check.sh and package tests inside its land slot;
  refusing would break dry lands). `nestedSkips` in `lean/Fw/Sup/Nested.lean` no longer takes the request kind; theorems
  `nestedSkips_other_kind` (other kind under a live parent skips, never waits) and the reworked `_iff`/`_of_live`. Goldens:
  two `adapt.nested` rows flipped to skip (regenerated). TS twin and `nestedHeld(d)` follow; slot.test.ts case flipped.
- (2) `scripts/slot-self.mjs`: `plan(env, args, nested)`; main calls `nestedHeld(realDeps(cwd))` only when `FW_SLOT_TOKEN`
  is set. `FW_SLOT_HELD` alone (or a dead token) queues. Tests in `scripts/slot-self.test.mjs` (plan + live/dead integration).
- (3) Not done, documented follow-up: `Entry` has no pid/start, so the parent-token owner check needs a state-format change.
- Docs: `docs/team/tools/slot.md` nested-run and self-routing sections.

Open
- Footprint of a nested other-kind run is not counted (accepted).
- An `acquire` holder's shell must export FW_SLOT_OWNER/FW_SLOT_TOKEN to run self-routing scripts under it.
Read first: lean/Fw/Sup/Nested.lean.

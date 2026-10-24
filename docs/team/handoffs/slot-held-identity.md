branch: worktree-wf_0ad066e2-254-1
worktree: .claude/worktrees/wf_0ad066e2-254-1
last commit: see `git log -1` on the branch
CI runs: none (accepted limit: no CI run; fixtures only)

State
- Lean: `lean/Fw/Sup/Nested.lean` (`nestedSkips`, six theorems incl. `nestedSkips_iff`), imported by `AdaptGolden.lean`,
  which adds 11 `adapt.nested` rows to `packages/contracts/golden/sup/adapt.jsonl` (regenerated, not hand-edited).
  Named cases: `FW_SLOT_HELD` with no token -> acquire; held test slot + nested land request -> acquire.
- TS: `nestedSkips` in `apps/runner/src/slot-core.ts` (twin), `nestedHeld` in `slot.ts` reads `FW_SLOT_TOKEN` + state
  and `run()` uses it instead of the `FW_SLOT_HELD` presence test. Tests: golden replay case + four `fw slot run` tests.
- Docs: `docs/team/tools/slot.md` nested-run rule and the count.

Count (MEASURED, time match): 133 of 760 unlocked; 114 within 60 s of a lead `FW_SLOT_HELD=1 sh land-rNNN.sh` call, 122
within 10 min. INFERRED: the other 11-19 came from other callers (no caller field; long lead scripts may account for some). Spans carry no caller; the match is by the lead transcript's tool-call times.

Open
- The contention note (research/notes/2026/10-2x-land-dry-contention.md) is outside the task writes: the count is in slot.md only; a paragraph under its Serialization section is a lead follow-up.
- `scripts/slot-self.mjs` still runs directly on any `FW_SLOT_HELD` (outside the task writes); follow-up.
- The lead's land scripts now acquire a land slot per dry land (intended); `acquire` holders' shells have no token.

Read first: lean/Fw/Sup/Nested.lean, apps/runner/src/slot.ts `nestedHeld`.

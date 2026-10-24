branch: worktree-wf_84ab31ff-033-1
worktree: .claude/worktrees/wf_84ab31ff-033-1
last commit: see `git log -1` on the branch (round 2 findings 1-4 done, main merged)
CI runs: none (accepted limit: local tests only)

State (round 2)
- (1) `nestedSkips now kind named held` in lean/Fw/Sup/Nested.lean: skip iff live + owner + token match and (same kind or
  kind not sim/measure). Theorems: _iff, _none, _empty, _same_kind, _other_kind, _sim_admission, _measure_admission,
  sim_under_parent_not_blocked (single non-sim parent: verdict never waits/timeouts with simBusy or drain). Golden rows
  added (held land + nested sim: acquire; held sim + nested sim: skip; held land + nested measure: acquire), adapt.jsonl
  regenerated; TS twin `nestedSkips(now, kind, ...)`, `nestedHeld(d, kind)`; slot.test.ts replays goldens + a sim case.
- (2)+(3) lean/scripts/check.sh:21 guards on FW_SLOT_SELF_IN; scripts/slot-self.mjs direct spawn sets it. slot-self.test.mjs:
  no-token (inherited FW_SLOT_HELD queues) and no-recursion (owner+token only) tests run check.sh's guard line itself.
- (4) docstrings fixed; slot.md updated.
Verified: lean check.sh green, @fw/runner test 3433 pass, ci-paths test, slot-self test, dry land VERDICT dry slot-nested-kind.
Open: owner pid+start check on the parent token (follow-up); nested other-kind footprint not counted (accepted).
Note: node tests need the pinned node (`pnpm exec node --test`). Read first: lean/Fw/Sup/Nested.lean.

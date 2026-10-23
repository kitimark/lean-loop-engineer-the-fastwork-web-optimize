branch: worktree-wf_c10c080c-893-1
worktree: .claude/worktrees/wf_c10c080c-893-1
last commit: 459e7cbd7 (merge 068e5075d); CI runs: none (accepted limit: no CI run)

# Overflow widths scope data

State: done.
- `lean/Fw/Console/LandTier.lean`: `plannerFiles` has `packages/gate-breakpoints/src/scope.gen.json` (read by spec.mjs loadScope); `overflowWidths_scope` and `plannerFiles_select` (7 cases) re-proved; one `#guard`, one golden row.
- `packages/contracts/golden/console/land-tier-local.jsonl` regenerated from Lean (`--check` up to date).
- `apps/runner/test/land-overflow-widths.test.ts`: one test, a scope.gen.json-only change selects runner:overflow-widths.
Open: none in unit; other files gate-jobs.mjs --parts reads are not audited here.
Read first: `lean/Fw/Console/LandTier.lean` section "Local tests".

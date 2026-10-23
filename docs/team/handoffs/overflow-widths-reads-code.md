branch: worktree-wf_b291cc70-2f8-1
worktree: .claude/worktrees/wf_b291cc70-2f8-1
last commit: see `git log -1`; CI runs: none (accepted limit: no CI run)

# Overflow widths reads code

State: done.
- `lean/Fw/Console/LandTier.lean`: `plannerFiles` has `spec.mjs` and `serve.mjs`; `overflowWidthsReads` is built with `++ plannerFiles`;
  `overflowWidths_scope` and `plannerFiles_select` (6 cases) re-proved; 2 `#guard`s and 2 golden rows; golden regenerated.
- `apps/runner/src/land.ts`: `fileURLToPath`; the golden row is looked up by name (`LAND_TIER_LOCAL_ROW`).
- `apps/runner/test/workflow-widths.ts`: `widthTable` and `checkRow`, used by `land-overflow-widths.test.ts` and `land-widths-fixture.test.ts`.
- `land-widths-fixture.test.ts` removes its mkdtemp dirs in `afterAll`; `docs/team/tools/land.md` names `binMoved`.
Verified: runner test (103 files, 3238 tests), ci-paths 56 pass, lean/scripts/check.sh green.
Open: `apps/runner/test/workflow-widths.ts` is outside the graph writes (the graph names src/). `land-dry.test.ts` untouched.
Read first: `lean/Fw/Console/LandTier.lean` section "Local tests".

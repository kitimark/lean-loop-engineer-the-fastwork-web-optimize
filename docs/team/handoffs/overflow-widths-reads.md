branch: worktree-wf_5b492dd8-543-1
worktree: .claude/worktrees/wf_5b492dd8-543-1
last commit: see `git log -1`; CI runs: none (accepted limit: no CI run)

# overflow-widths-reads

State: done. The read set of `runner:overflow-widths` is one Lean list; TS reads it from the golden.

- `lean/Fw/Console/LandTier.lean`: `plannerFiles` (gate schedule/shards goldens, `breakpoints.gen.json`, `anchors.json`), inside
  `overflowWidthsReads`; theorems `overflowWidths_scope` (the parsed scope, was inline in `workflow_selects_overflowWidths`) and
  `plannerFiles_select` (each planner file alone selects the test); 4 new golden rows.
- `packages/contracts/golden/console/land-tier-local.jsonl` regenerated (`lake build Fw.Console.LandTier`, then `lake env lean --run scripts/LandTierGolden.lean --write`).
- `apps/runner/src/land.ts`: `OVERFLOW_WIDTHS_READS = overflowWidthsReadsFromGolden()`; the hand copy is gone.
- `apps/runner/test/land-widths-fixture.test.ts`: 6-job path-pix fixture parsed with `parseWorkflow`/`width` is 6, fails against a row of 4
  ("derived 6"); planner inputs select the test; the TS list equals the golden.
- `docs/team/tools/land.md`: Lean-change cost (~11 s, MEASURED 10.96 s vitest, 22.4 s wall) and the one-list rule.

Verified: `fw slot run` runner test (103 files, 3233 tests, incl. typecheck), ci-paths 56 pass, lean/scripts/check.sh green.
Open: a new planner input must be added to `plannerFiles` and the golden regenerated. The dry-land test in `land-dry.test.ts` still uses
a stand-in argv (not edited: timing-verdict-polish owns that file).
Read first: `lean/Fw/Console/LandTier.lean` section "Local tests".

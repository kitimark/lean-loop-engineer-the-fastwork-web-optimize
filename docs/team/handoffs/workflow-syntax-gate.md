branch: worktree-wf_f1b87bb1-9b8-1
worktree: .claude/worktrees/wf_f1b87bb1-9b8-1
last commit: 3883bdaf4 (pushed to ci/land-workflow-syntax-gate; land.yml triggers on ci/land-*, not ci/<task>)
CI runs: 39889327928 land (push 3883bdaf4) success: install prints 1.7.12, suites-a TIMING apps/runner 135s skipped=0
verified: main merged (check.sh = main + workflow-lint golden job); CircleCI land-actionlint leg (arm64, same sha); land.md; golden case regenerated
open: CircleCI legs shown by reading only; shellcheck warnings accepted

## State
- Lean `lean/Fw/Ci/WorkflowLint.lean`: selection (`select`, theorems `yml_selects`, `yaml_selects`, `script_selects`, `select_iff`) and verdict
  (`verdict`: `missing_refuses`, `error_fails`, `warnings_never_fail`, `clean_passes`, `dup_key_fails`, accepted finding theorems).
  Golden `packages/contracts/golden/ci/workflow-lint.jsonl` from `lean/scripts/WorkflowLintGolden.lean`; wired in `lean/Fw.lean` and `lean/scripts/check.sh`.
- TS stand-in `apps/runner/src/land-checks-workflow.ts` (verdict mirrors Lean, pinned by the golden); `WORKFLOW_LINT` / `LOCAL_GATES` in `land.ts`
  (candidate check and dry land); `scripts/check-workflows.sh` (refuses exit 3 when actionlint is missing; prints a TAP summary because the
  land lane fails a check without a summary as "unknown").
- Test `apps/runner/test/land-workflow.test.ts` (29 tests): golden replay, selection, script on dup key / expression / shellcheck / missing
  actionlint, and `runTier` refusing the land on a duplicated env key.
- webkit-sim.yml `''` option finding: accepted, file+message scoped (reason in Lean `accepted` and docs/team/tools/land.md).
- Tier: local (not in `remoteIds`); reason in land.md.

## Open
- Writes outside the task: `lean/Fw.lean`, `lean/scripts/check.sh`, `lean/scripts/WorkflowLintGolden.lean` (golden wiring).
- A future move to the remote tier needs an actionlint install step in land.yml and a `remoteIds` row in Lean LandTier.
- Read first: lean/Fw/Ci/WorkflowLint.lean, scripts/check-workflows.sh.

## Round 2 (land-lane fix)
- Decision: install, not seam. land.yml step "actionlint (pinned, sha256-checked)" puts rhysd/actionlint v1.7.12 linux_arm64 (sha256 325e971b...c0c6, checked
  against the release checksums file) on PATH in every land leg, so land-workflow.test.ts runs its real-binary cases with 0 skipped. skipIf commit reverted.
- Check reads now include apps/runner/src/land-checks-workflow.ts (Lean `reads`, `parse_reads`, `verdict_code_selects`; TS WORKFLOW_LINT_READS; golden regenerated).
- Open: land.yml is a new write; CircleCI overflow leg (.circleci) has no actionlint install; if it runs apps/runner the same skip fails there.

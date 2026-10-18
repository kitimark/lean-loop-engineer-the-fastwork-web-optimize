# workflow-salvage handoff

State: branch worktree-wf_df082d5f-ac9-6 (commit in the report). Pinned unit: one builder exit without a structured result.

Built
- `lean/Fw/Ops/Salvage.lean`: `decide` (Facts -> Out), five theorems (result_untouched, missing_commits_and_hands_back,
  empty_iff_clean, never_retries, state_from_facts), `#guard`s, `goldenText`.
- `packages/contracts/golden/ops/salvage.jsonl`: 8 cases, generated from `goldenText`.
- `apps/runner/src/workflow/salvage.ts`: TS stand-in `decide` plus `salvageStage(task, result, effects)`.
- `apps/runner/test/workflow-salvage.test.ts`: stand-in equals every golden line; effect order commit then handback.

Verified: lake build of the module, vitest for the test file (see report for check.sh and the dry verdict).

Open items
- TS stand-in, to replace: the op `ops.salvage` is not wired into `fwcore` (Fw/Wire.lean outside the write list).
- The golden is not in `lean/scripts/check.sh` (no generator script was in scope). Regenerate: a one-line `main` that prints
  `Fw.Ops.Salvage.goldenText`, run with `lake env lean --run` from `lean/`, stdout to the golden file.
- `docs/team/tools/prompt-rules.md` / `workflow-patterns.md` (work-graph rows) were not in this lane's write list: add the
  rule "a builder prompt ends with the structured result" and the salvage stage pattern there.
- Real glue (`Effects`: git status/commit in the worktree, `task.handback` command to console-api) is not written.

Read first: the header of `lean/Fw/Ops/Salvage.lean`.

# workflow-claim handoff

State: committed on the worktree branch (task `workflow-claim`). Incident `inc-workflow-unbound` in
`docs/team/incidents/ledger.json` (lint: 0 errors).

## What it does
- Signal (CONFIRMED on the live session dir): `<session>/workflows/scripts/<meta.name>-<runId>.js` appears at run
  start; `<session>/workflows/<runId>.json` appears at run end (completed | killed). Only file names are read.
  The journal dir and the hook events carry no name, so they are not used.
- Lean `lean/Fw/Plan/Workflow.lean`: `scriptRun`, `runFileId`, `Wf.cmds`, `wfEvents`; theorems `workflow_binds`,
  `workflow_ends`, `workflow_done_keeps`, `workflow_foreign_none`, `workflow_foreign_agentOf`,
  `workflow_foreign_bound`, `define_life_comm`, `define_workflow_comm`, `wfEvents_foreign`. No `Core.lean` change.
- Golden `packages/contracts/golden/plan/workflow.jsonl`, written by `lake test -- --write-plan-golden`
  (`Golden.lean` `wfCases`), checked byte for byte.
- TS glue (TEMPORARY stand-in for an fwcore op): `apps/console-api/src/spool/workflow.ts`; `Drain.workflowSweep`
  runs at the start of each drain, ids from the board, events `wf:<runId>` (spawn) and `wf-end:<runId>` (stop),
  actor hook. Test: `apps/console-api/test/workflow-claim.test.ts`.
- Dirs swept: `FW_WORKFLOWS_DIR` (colon separated) or `~/.claude/projects/<slug of root>/*/workflows`.

## Open items
- Glue sits in console-api, not the hook or `watch.ts` (off limits for this task). `work-graph.json` writes for
  this task do not list `apps/console-api/src/spool/**`; the lead may add it.
- A name in `meta.name` that differs from the file name slug would be missed (INFERRED same; the 39 local scripts
  all match). A run named like a task but started while a named agent of that task is alive: the stored claim wins.
- The math view (`lake exe mathview`) was not regenerated; run it if the lead wants the new theorems listed.

Read first: `lean/Fw/Plan/Workflow.lean` header, then `apps/console-api/src/spool/workflow.ts`.

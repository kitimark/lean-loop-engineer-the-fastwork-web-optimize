# workflow-multi-claim handoff

State: HEAD commit below (see `git log -1`). Branch worktree-wf_ebc4ff5b-4b6-2.

What changed
- Lean `Fw.Plan.Workflow`: `labelTask`, `JLine`, `WfAgent`, `wfAgents`, `WfAgent.cmds`, `agentEvents`, `wfAllEvents`.
  Theorems: `wfAllEvents_nil` (no journal = old events), `wfAllEvents_bound` (every bound id is in the plan and is a
  meta.name or a label task), `WfAgent.cmds_running/ended`, `WfAgent.cmds_life`, `define_agent_comm`.
- Signal (CONFIRMED): `<session>/subagents/workflows/<runId>/journal.jsonl`: `started` {agentId,label}, `result` {agentId}.
  Agent binds the task after the first `:` of its label until its result line or the run file. Event keys
  `wfa:<run>:<agent>` / `wfa-end:<run>:<agent>`.
- Golden `packages/contracts/golden/plan/workflow.jsonl`: old lines unchanged; new lines carry `journal`.
- TS stand-in `apps/console-api/src/spool/workflow.ts` (`wfAllEvents`, `parseJournal`), reads only type/agentId/label;
  tests in `apps/console-api/test/workflow-claim.test.ts`.

Lead after landing: restart console-api (drain sweep reads journals on the next pass); no backfill needed, the sweep
replays all journals and event keys dedup.
Open: a run whose agent labels have no `:` (e.g. "review") binds nothing; only meta.name then.

# con-plan handoff

State: console side of the work graph done on top of lean-plan (merged, commit 0de2fec). Branch worktree-wf_c2b8a932-977-5.

What exists
- packages/contracts: commands task.define/drop/claim/done, milestone.define; `Plan`, `PlanTask`, `PlanMilestone`; `LiveBoard`
  (= Board + plan; the stateless `console.board` golden has no plan, so `Board` stays plan-free). ObsRecord gained optional `agent_name`.
- console-api: core.board returns LiveBoard; GET /api/plan; agent door accepts `command` as an ARRAY (one capability per `fw`
  invocation covers a whole sync; per-command replies in `replies`); Drain: SpawnGuard record with agent_name == a task id
  -> task.claim (actor hook, key claim:<id>); Reconciler pass 3: landed card (or its branch agent) == undone task id -> task.done
  (actor git, evidence = card head, key taskdone:<id>).
- runner: `fw plan sync <file>` (src/plan.ts: topoSort, syncCommands, keys carry a content digest so edits re-apply and
  unchanged files are duplicates; titles clipped to 200), `fw plan show` (renderPlan). spawn-guard hook record carries agent_name.
- console-web: Plan tab (src/Plan.tsx): milestone bars, Ready by parallel-safe group / Running / Blocked / Done, SVG layered DAG
  of unfinished tasks with the critical path in red. No web tests (no vitest in that package).
- Tests: contracts (plan goldens parse), console-api test/plan.test.ts (golden replay through real fwcore, real work-graph.json
  invariants, batch door, claim from spool, done from a landing), runner test/plan.test.ts.

Open items
- Evidence has no link target: the repo has no public remote, so Done shows the short sha with `git show <sha>` as tooltip.
- A claim is dropped if the agent spawns before `fw plan sync` defined the task (drain skips unknown names, never blocks the spool).
- Task titles over 200 chars (gap-harness) are clipped on sync; shorten them in work-graph.json.
- The golden work-graph.jsonl is older than docs/team/work-graph.json (52 vs 67 tasks), so the test checks the Lean iff rules
  on the live file instead of equality; regenerate with `lake test -- --write-plan-golden` to refresh the golden.
- The PreToolUse cap hook grants one cap per Bash `fw ...` argv as before; sync needs no new hook.

Read first: apps/runner/src/plan.ts, apps/console-api/test/plan.test.ts, apps/console-web/src/Plan.tsx.

# task-state-truth (handoff)

State: branch `worktree-wf_82415a69-e43-1`, round 5 (lead's closed redesign, final round), commits 51d48c6d..HEAD on
round 4 (`worktree-wf_f085afd7-2cc-1`). check.sh green; vitest console-api 322, runner 1018, console-web 11; main merged (4fe8185e).
Root cause (MEASURED, round 1): strict zod `ObsRecord` refused every SubagentStop carrying `background_tasks`.

## Round 5 (lead decisions, done)
- **Quiet**: `TState.quiet`; a live key not sighted within q (`quietMs` = 120 min) shows quiet with `since` = its last
  sighting, derived at query time (`view q now`). No timeout stop exists: `plan.timeouts` and `timeoutSweep` are gone.
  Lean (Fw/Plan/Core.lean): `running_needs_recent_sighting`, `no_forever_running`, `ended_needs_identity_stops`,
  `timeout_never_ends`, `names_never_sight`, `claim_never_sights`.
- **Identity keys only**: agent id, `wf:<run>`, SpawnGuard obs key; `keysOf` drops the name, a claim never sights.
- **Workflow** (Fw/Plan/Workflow.lean, workflow.ts): every agent of a run whose name is a task id binds that task
  (`run_task_binds`), plus its label task; a journal `failed` line stops the id like `result`.
- **drain.ts**: `once()` body in one try; a throw is `caught("drain")` (spool.test "rejecting core").
- **Backfill**: the 23 name-keyed agent.stop lines are dropped (names never sight, so they ended nothing); 17 remain.
- **Replay**: `research/notes/2026/10-18-task-state-truth.md`: running 10 -> 2, quiet 0 -> 17, parked 0 -> 7 (27 rows).
- console-web Plan.tsx: Quiet group under Running with "last seen N min ago" (`quietLabel`, test/plan-quiet).

## Lead steps
1. Land; restart console-api; let one drain run.
2. Apply `docs/team/backfill/task-state-2026-10-18.jsonl` via `fw send`, one line at a time, actor lead, drop `cite`.

## Stated limits
Forged events; 10-min display lag after restart; a teammate between turns shows quiet or ended; quiet lasts until
someone acts (a stop, or a lead/user mark); a SpawnGuard key has no spool stop producer (SubagentStop carries no obs
key), so it ends as quiet; legacy name-keyed events stay in the log and do nothing; sweep-error counts reset on restart.
No checker subagent was available in this session (no spawn tool): the docstrings were self-checked only.

Read first: `lean/Fw/Plan/Core.lean` (search `running_needs_recent_sighting`), `lean/Fw/Plan/Workflow.lean`, drain.ts.

# task-state-truth (handoff)

State: branch `worktree-wf_f085afd7-2cc-1`, round 4 (conform to the round-3 final design), commits 3a5b058..HEAD.
Root cause (MEASURED, round 1): strict zod `ObsRecord` refused every SubagentStop carrying `background_tasks`.

## Round 4 (lead decisions, done)
- **Identity only**: every life event is keyed by an agent id, a run key `wf:<run>` or a spawn guard's obs key; a name
  is only a label (`agent.label`). Lean `wfAllEvents_identity`, `life_identity`, `byGuard`; `byName` is gone. TS:
  workflow.ts (`wfr`/`wfid` event keys), drain.ts (`lifeOf` has no name; label decisions submit `agent.label`).
- **Concurrency**: `concurrent_keep` (a stop of one key never ends a name another live key carries),
  `workflow_concurrent`; real-events golden "concurrent agents" (seq 1113/1114/1118) in Fw/Plan/Golden.lean.
- **No swallowed throw**: every caught fwcore throw in the sweep or drain (admit, workflow, label, timeout, fieldAlert,
  lifeOf, alertPlan) is counted per op in `.fw-console/sweep-errors.json` {pid, count, ops} plus spool issue
  `sweep:<op>`; the runner reads it for the live api pid; fwcore raises `svc.sweepError` (`sweep_error_alerts`).
- **Backfill**: the 23 agent.stop lines carry `at` = the journal time of their cited seq, keyed by id/name life key.

## Lead steps
1. Land; restart console-api; let one drain run (first drain on the real spool: 85 s, 6249 accepted, 24 timeouts).
2. Apply `docs/team/backfill/task-state-2026-10-18.jsonl` via `fw send`, one line at a time, actor lead, drop `cite`,
   keep `at`. Replay (read-only copy): all 40 accepted, running 25 -> 8, parked 4 -> 13, integrated 13, handedBack 1.

## Stated limits
Forged events; 10-min display lag after restart (epochs reset, heartbeats bucketed); a SpawnGuard bridge key ends
only at the 120-min quiet timeout (the Agent PostToolUse returns in p50 1.3 s, MEASURED, so it cannot end it);
legacy name-keyed events stay in the log and `keysOf` keeps the name; an id binds only once `fw watch` labels it;
sweep-error counts reset on restart.

Read first: `lean/Fw/Plan/Workflow.lean` (identity, concurrency), `lean/Fw/Ops/Obs.lean` life, drain.ts `caught`.

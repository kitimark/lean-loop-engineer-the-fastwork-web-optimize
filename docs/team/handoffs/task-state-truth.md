# task-state-truth (handoff)

State: branch `worktree-wf_dd322f5d-433-1`, round 3 (final design) at 0858abd..9d47aea plus this note; check.sh green,
vitest console-api 266, runner 874, console-web 7; `fw land --dry` (allow Console.lean, Ops/Obs.lean, Wire/Plan.lean).
Root cause (MEASURED, round 1): strict zod `ObsRecord` refused every SubagentStop carrying `background_tasks`.

## Round 3 (lead decisions, closed)
- **Liveness by agent id** (`Fw.Plan` keys): a life key is live when seen after its last stop; a name is live
  while any of `keysOf` = the name + ids labelled with it (`agent.label`, from the health index; label only).
  SubagentStart/Stop spawn/stop the id; any other event of an id is a heartbeat spawn. `revive_on_event`,
  `event_revives`, `stop_by_id`, `timeout_spares_recent`.
- **Claim TTL**: a claim is a sighting at its `at`; no later sighting -> quiet timeout -> parked (`expired`).
  `no_forever_running`. `since` = last sighting, claim included; board rows carry `keys` for `plan.timeouts`.
- **Integrate allowlist**: only refs/heads/{ci/,worktree-,integrate-}… (`integrate_allowlist`, `integrate_prefix`);
  runner `gitFullRef` = `git rev-parse --verify --quiet --symbolic-full-name`, else a given full ref, else refuse.
- **Admission**: only hook_event_name, agent_id (1..120), agent_name, ts reject; other fields soft (null + note).
  Rejections, notes, unknown fields and `lifeOf:error` are issues in one spool alert (`reject_alerts`,
  `issue_alerts`); title capped at 200 UTF-16 units (`alertTitle_le`). A lifeOf throw: not seen, retried.
- **Backfill**: integrate branches as full refs; fix-people-webkit, fix-nav-hittest parked no-op (handoff-only).

## Lead steps
1. Land; restart console-api; let one drain run (labels + stops of the 6173 unseen SubagentStops).
2. Apply `docs/team/backfill/task-state-2026-10-18.jsonl` via `fw send`, one line at a time, actor lead, drop `cite`.

## Stated limits
Forged events; 10-min display lag after restart (epochs reset, heartbeats bucketed by 10 min); an id binds to a task
only once `fw watch` names it; a legacy `live` define without a sighting binds nothing; rejected lines re-alert
after a restart (offsets reset).

Read first: `lean/Fw/Plan/Core.lean` "Agent binding" + "Quiet timeout", then `lean/Fw/Ops/Obs.lean` admission/life.

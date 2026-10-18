# console-stale handoff

State: branch worktree-wf_ebc4ff5b-4b6-1 (head = the commit that adds this file; see `git log -1`). check.sh green, runner+console-api+contracts tests green, `fw land --dry` ok.

Read first: docs/team/tools/console-stale.md, lean/Fw/Obs/Stale.lean.

Done
- Lean: Fw.Obs.Stale (Svc, stale_iff, mem_changed, restart_clears); Health: code `svc.stale` (rank 14, later ranks +1),
  `sStale`, theorems svcStale_iff, staleAlert_fields, sStale_restart; Wire/Obs.lean decodes `system.svcs` (round trip
  proved; maxHeartbeats raised for systemOf_systemJson); 3 golden rows, health.jsonl regenerated.
- TS: apps/runner/src/watch-svc.ts (measurement only), console-api writes commit+startedAt to api.json,
  GET /api/service and `service` inside GET /api/health.

Open
- fw land does not print "console-api is stale: restart" (optional).
- Running console-api must be restarted once to write startedAt; until then no svc.stale is possible (old api.json).
- lean/Fw/Wire/Obs.lean is outside the task's declared writes (land scope accepted it); add it to the work-graph writes.
- fwcore is judged to start with console-api; a lake rebuild without restart is not detected.

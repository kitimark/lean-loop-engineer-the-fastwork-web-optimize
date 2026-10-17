# plan-state-fix handoff

State: done on branch `worktree-agent-a1cd5e6036d1dcec2` (see `git log -1`); check-fast ok, runner/console-api/contracts/console-web tests pass.
- Late claims: `task.define` carries the fact `live` (live agent names). console-api `withLive` (store.ts) fills it from
  the latest health.jsonl line (`liveAgentNames`, health state not gone/done); Lean `Def.liveAgent` + `upsert` claim.
  Proof: `Fw.Plan.step_define_live` (and `upsert_live`).
- Cut: explicit `cut: true` on the 7 MX tasks in work-graph.json. `tstate` order: done > cut > running > ready > blocked.
  Cut rows are off the critical path (`criticalPath (kept ..)`) and out of milestone totals (`msView` over `kept`).
  Proofs: `cut_not_ready`, `tstate_cut_iff`, `readyRows_not_cut`, `view_criticalPath_not_cut`, `msView_kept`.
- `fw plan show` ends with one `CUT (n): ...` line; TaskState enum has "cut"; console-web greys cut tasks (under Done).
- Golden: `cd lean && lake test -- --write-plan-golden`; Golden.lean `clip` mirrors the sync title cap (200).
Open items:
- The live set needs `fw watch` writing health.jsonl; a live agent named like the task overrides an existing agent.
- Pre-existing: apps/console-api/test/plan.test.ts ~line 67 has a statement hidden inside a comment (left as is).
Read first: lean/Fw/Plan/Core.lean (section "Late definitions", tstate), apps/console-api/src/store.ts `withLive`.

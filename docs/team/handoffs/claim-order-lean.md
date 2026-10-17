# claim-order-lean (handoff)

State: done on branch worktree-agent-a49e0b41e2d64e0f4 (commit: see `git log -1` on that branch).

What changed
- Lean `Fw.Plan` (lean/Fw/Plan/Core.lean): new commands `spawn a` / `stop a` (wire `agent.spawn` / `agent.stop`,
  lean/Fw/Wire/Plan.lean). State keeps `spawns` / `stops` lists; the task's agent is DERIVED (`agentOf`, `bound`,
  `boundTo`): stored agent (explicit claim, or legacy `live`) first, then the task id if spawned; an agent is ended when
  0 < #stops and #spawns <= #stops. `view s = viewWith s (bound s)`.
- Theorems: `run_comm` / `define_spawn_comm` (spawn/stop commute with every command: full-state equality, so the
  exact "es++[define,spawn] vs es++[spawn,define]" form holds), `view_perm` (board depends on the non-life command order
  plus spawn/stop multisets; a full multiset statement over ALL commands is false: define/claim order matters),
  `boundTo_keep`, `boundTo_spawn` (monotone binding), `view_compat` / `run_compat` (no spawn/stop: old board),
  `step_define_idem`, `syncFrom` + `sync_only_main`, `sync_skip_same`, `sync_due`.
- Goldens: packages/contracts/golden/plan/serve.jsonl (+6 cases, old lines unchanged), new golden/plan/sync.jsonl.
- Contracts: `agent.spawn` / `agent.stop` commands; `live` marked legacy; src/plan-sync.ts (shared topoSort,
  syncCommands with injected digest, `syncFrom` TS stand-in of Lean, golden-checked in apps/console-api/test/plan-sync.test.ts).
- console-api: drain sends agent.spawn on every named SpawnGuard and agent.stop on SubagentStop (name from the latest
  health line, `agentNameOf`); `claimFor` and the console-added `live` are gone (`withoutLive` strips a client's).
  Reconciler step 0 syncs the work graph read with `git show <main head>:docs/team/work-graph.json` when main moves.
- Out of the task's writes (needed): lean/Fw/Console.lean (MAY rows), lean/Fw/Console/Self.lean (sources),
  lean/Fw/Wire/Console.lean (doc), golden/console/console.actor.jsonl, contracts schema/*.json (regenerated),
  contracts fixtures/commands.golden.json (+2 examples).

Open items
- Behaviour change: a stopped agent releases an undone task (back to ready), e.g. agent finished, land pending.
- A stop of an agent that never appeared in a health snapshot (< 1 watch period) is missed: the task stays running
  until its done fact. Fix needs the agent name at SubagentStop (hook payload or transcript meta).
- `syncFrom` is a TS stand-in (golden-checked), not run through fwcore.

Read first: Core.lean section "Agent binding" (line ~629), apps/console-api/test/plan.test.ts "automation".

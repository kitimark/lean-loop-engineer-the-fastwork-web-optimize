# cap-actor-fix (handoff)

**State:** done on branch `worktree-agent-a7fa85a50594312b0` (commit: see `git log -1 -- lean/Fw/Ops/Identity.lean`).
Implements SPK-c decision 1 (`research/notes/2026/10-17-spk-drafts/spk-c.md`): the lead is the record with no
`agent_id`; an `agent_id` with an empty or missing `agent_type` (forked internal agent) is unknown, never the lead.

**What changed**
- `lean/Fw/Ops/Identity.lean` (new): `who`, `isReviewRole`, `actorOf`, `capActor`; theorems `who_lead_iff`,
  `who_some_ne_lead`, `who_agent_iff`, `who_unknown_iff`, `who_forked`, `who_total`, `capActor_lead_iff`,
  `capActor_none_iff`, `capActor_range`; `#guard` edge cases.
- `lean/Fw/Ops/Wire.lean`: `ops.hook` replies carry `who`; new op `ops.actor` ({agent_id?, agent_type?} ->
  {who, role, actor}); goldens `packages/contracts/golden/ops/ops.actor.jsonl` (16 cases), `ops.hook.jsonl` regenerated.
- `apps/runner/hooks/cap.mjs`: `identity()` mirrors `ops.actor` (checked against the golden in `hooks.test.ts`); an
  unknown identity on a `pnpm fw` call mints nothing and exits 2 with a stderr reason (fail closed). Lead records are
  `{agent_id: null, agent_type: "main"}`.
- MAC now binds `agent_id` (`lib.mjs` and `cap.ts` `capMac(sec, agentId, agentType, toolUseId, cmdHash)`), because
  `agent_id` now decides the lead; without it, stripping `agent_id` from an agent's record would make it the lead.
  Old caps.jsonl lines stop verifying (TTL is 10 min anyway).
- `apps/console-api/src/cap/cap.ts`: `actorFor(agentId, agentType): Actor | null`, golden-checked; null = refuse.

**Conventions:** Lean first; JS/TS mirrors are 5-line functions pinned to Lean goldens (no fwcore call on the sync
hook path). Regenerate goldens: `cd lean && lake env lean --run scripts/OpsGolden.lean`.

**Open**
- Teammate role (SPK-c decision 2): a teammate's `agent_type` is its name; it currently acts as `owner` (or
  `reviewer` if its name contains "review"). Needs a console roster (name -> role, fed by spawn-guard from
  `tool_input.name` + `subagent_type`); not small, not done.
- SPK-c decision 3 (observers drop or label empty-type SubagentStop): not in scope; `ops.hook` now labels them
  `who: "unknown"`, which drain/summarize can use.
- `drain.ts` and `summarize` still default a missing `agent_type` to "main" for display keys (not an authority path).

**Read first:** `lean/Fw/Ops/Identity.lean` header, then `apps/runner/hooks/cap.mjs`.

---
id: 2026-10-17-spk-c
kind: note
title: "SPK-c: do hooks inside in-process teammates carry agent_type, or only agent_id?"
status: draft
created: 2026-10-17
topics: [spike, decision-record, hooks, capability, agent-teams]
---

# SPK-c (DRAFT decision record)

**Question (PLAN Appendix B).** Do hooks inside in-process teammates carry `agent_type`, or only `agent_id`?

**Status: PARTIAL.** The docs answer `agent_id`; `agent_type` for teammates is not observed.

**Answer so far.** `agent_id` is documented for in-process teammates. `agent_type` is documented as present "when the
session uses `--agent` or the hook fires inside a subagent", so for a teammate it is unconfirmed, and so is its value
(the role, the teammate name or empty).

## Evidence
| Claim | Evidence | Status |
|---|---|---|
| `agent_id`: "Unique identifier for the subagent or in-process teammate the hook fires in" | code.claude.com/docs/en/hooks, common input fields (fetched 2026-10-17) | CONFIRMED by docs |
| `agent_type`: "Present when the session uses `--agent` or the hook fires inside a subagent. For subagents, the subagent's type takes precedence" | same page | CONFIRMED by docs |
| In-process teammates pass their own `agentId` and `agentType` into hook input (`TeammateIdle` is built that way) | `research/notes/2026/10-17-agent-observability-sources.md` §2 @b65e983 (binary strings) | INFERRED |
| A teammate's transcript meta has `agentType` = the teammate name, plus `customAgentType` and `spawnedAgentType` = the role | `<session>/subagents/agent-<name>-<hash>.meta.json` (this teammate: `agentType: spk-records`, `customAgentType: researcher`) | MEASURED (meta file, not a hook payload) |
| No hooks block exists in `.claude/settings.json`, so no hook payload from a teammate has been recorded | `.claude/settings.json` @a0b9053 (no `hooks` key) | CONFIRMED |
| The capability hook reads `agent_type` and falls back to `"main"` when it is missing or empty | `apps/runner/hooks/cap.mjs:47` @97bd8a2 | CONFIRMED (code) |
| The console maps `main` to the lead (`actorFor`) | `apps/console-api/src/cap/cap.ts:71`, `con-hooks.md` "Open" @97bd8a2 | CONFIRMED (code) |

**Why it matters (INFERRED from the code above):** if a teammate hook has `agent_id` but no `agent_type`, `cap.mjs`
stamps `agent_type = "main"`, and the console would treat the teammate as the lead. Capability stays "anti-accident"
(`con-hooks.md`), but a builder teammate acting as lead would defeat the review rule.

**Evidence commit:** `97bd8a2` (hooks), `3fe1876` (merge), `b65e983` (note); HEAD `30e3264`.

## Missing
- A real hook payload from an in-process teammate (and from a named worktree subagent) with `agent_id`, `agent_type`.
- The hooks block in `.claude/settings.json` ("proposed in the report, not applied", `con-hooks.md`). Writing
  `.claude/**` prompts the user (an `ask` rule), so the lead batches it.

## Next step
1. Lead applies the proposed hooks block (SessionStart, PreToolUse capability, observer events) in a planned sitting.
2. console-builder (agent-ops): run one teammate and one named worktree subagent through `emit.mjs`; read the spooled
   record for `agent_id` and `agent_type`; record the result here.
3. If `agent_type` is missing for teammates: key the capability on `agent_id` joined to the transcript meta
   (`customAgentType`), and make `cap.mjs` refuse (not default to `main`) when both are missing.

## What this changes in the plan
- §8.3 (capability hook) and R27: change "binds each request to Claude Code's agent identity" to "binds to `agent_id`
  and, where present, `agent_type`; a missing `agent_type` is refused, never mapped to the lead". Appendix B: SPK-c
  "partial".

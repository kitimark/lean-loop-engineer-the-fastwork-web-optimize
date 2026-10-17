---
id: 2026-10-17-spk-c
kind: note
title: "SPK-c: do hooks inside in-process teammates carry agent_type, or only agent_id?"
status: review
created: 2026-10-17
topics: [spike, decision-record, hooks, capability, agent-teams, spawn-guard]
---

# SPK-c (decision record, for the lead to sign)

**Question (PLAN Appendix B).** Do hooks inside in-process teammates carry `agent_type`, or only `agent_id`?

**Status: ANSWERED** (MEASURED on real hook payloads, Claude Code 2.1.302; code read for the why).

**Answer.** Every hook that carries `agent_id` also carries `agent_type`, teammates included. What `agent_type`
holds depends on how the agent was started, and for a teammate it is the teammate's **name**, not its role:

| How the agent started | Agents seen | `agent_id` shape | `agent_type` value | Status |
|---|---|---|---|---|
| Lead (main session) | 1 | absent | absent | MEASURED (248 records) |
| `Agent` tool, subagent (named worktree or unnamed) | 11 | `a` + 16 hex | the role (`subagent_type`) | MEASURED |
| `Workflow` tool | 18 | `a` + 16 hex | the role | MEASURED |
| In-process teammate (`Agent` with `name`, no isolation) | 3 | `a<name>-` + 16 hex | the teammate **name**; the role is only in the transcript meta (`customAgentType`) | MEASURED |
| Forked internal agent (Claude Code's own side queries; no transcript) | 225 | `a` + 16 hex | `""` (empty string) | MEASURED; origin CONFIRMED by code |

The spool `agent_type` equals the transcript meta `agentType` for all 32 agents that have a transcript (32 of 32).

## Evidence
Snapshot of `.fw-console/spool/*.jsonl` at 19:25 (+0700): 2,328 records in 258 files, 17:24:13 to 19:25:09 (2 h 01 min),
two Claude Code restarts in between. Field names and counts only; no payload values are quoted.

| Claim | Evidence | Status |
|---|---|---|
| `agent_type` is non-null in exactly the records where `agent_id` is non-null: PostToolUse 1,669/1,669, PostToolUseFailure 135/135, SubagentStart 26/26, SubagentStop 249/249, TeammateIdle 1/1 | spool snapshot | MEASURED |
| No agent ever has two `agent_type` values (0 of 257 ids) | spool snapshot | MEASURED |
| Teammates: 3 of 3 have `agent_type` = name, `agent_id` = `a<agent_type>-<hex>`, meta `customAgentType` = a role, meta `taskKind` = in-process teammate | spool + `<session>/subagents/agent-*.meta.json` | MEASURED |
| TeammateIdle input is built from the teammate's context `agentId`/`agentType` and adds `teammate_name`, `team_name` | Claude Code 2.1.302 binary, grep anchor `hook_event_name:"TeammateIdle"` | CONFIRMED (code) |
| SubagentStop sets `agent_type` to the agent's type, else the session's, else `""`; it fires at turn end of any query loop that has an `agentId` | binary, anchor `hook_event_name:"SubagentStop"` | CONFIRMED (code) |
| Forked side agents (labels include `agent_summary`, `extract_memories`, `prompt_suggestion`, `compact`) get a fresh `agentId` and no `agentType`; `agent_summary` sets `skipTranscript`; SubagentStart is only called from the normal agent runner | binary, anchors `forkLabel:"agent_summary"`, `hook_event_name:"SubagentStart"` | CONFIRMED (code) |
| The 225 empty-type ids have only SubagentStop (no start, no tool record) and 0 of 225 have a transcript | spool + transcripts | MEASURED |
| `cap.mjs` stamps `"main"` when `agent_type` is missing or empty; 8 of 8 `caps.jsonl` records so far are the lead | `apps/runner/hooks/cap.mjs:47` @30fbbd8; `.fw-console/caps.jsonl` | CONFIRMED (code), MEASURED |

## Hook payload audit (all events, same snapshot)
`emit.mjs` keeps only 9 fields (`agent_id`, `agent_type`, `hook_event_name`, `tool_name`, `tool_use_id`, `duration_ms`,
`is_error`, `verb`, `ts`; `emit.mjs:23-33` @30fbbd8). Any other payload field (`source`, `trigger`, `background_tasks`,
`teammate_name`, `notification_type`, `error`) is dropped by design and cannot be measured from the spool.

| Event | Records | Non-null fields | Notes |
|---|---|---|---|
| PostToolUse (async) | 1,876 | `tool_name`, `tool_use_id`, `duration_ms` all; `agent_id`/`agent_type` 1,669 | lead 207. Bash 1,453, Edit 159, Write 122, Read 91 |
| PostToolUseFailure (async) | 137 | same | Bash 128, Read 9; duration p50 106 ms |
| SubagentStop | 249 | `agent_id`, `agent_type` | 225 forked agents with `""`, 24 real agents |
| SubagentStart | 26 | `agent_id`, `agent_type` | 3 teammates, 23 role agents |
| SessionStart | 12 | none (lead only) | 10 at compaction, 2 = the two restarts (see SPK-p) |
| PreCompact / PostCompact | 10 / 10 | none (lead only) | compaction took 30 to 100 s |
| SpawnGuard (spawn-guard log) | 5 | `tool_name`, `tool_use_id`, `verb` | see below |
| Notification | 2 | none | |
| TeammateIdle | 1 | `agent_id`, `agent_type` | |
| StopFailure | 0 | | none in 2 h |

- **Why SubagentStart (26) is so much rarer than SubagentStop (249):** 225 stops are forked internal agents, which never
  fire SubagentStart. The 24 real stops against 26 starts: 8 agents were still running at the snapshot; 5 agents started
  before the hooks went live, so they have a stop and no start. MEASURED.
- **Coverage:** of 1,819 tool calls in agent and lead transcripts in the window, 1,808 have exactly one spool record. The 11
  others did not complete: 9 rejected before execution (`tool_use_error`: 6 blocked Bash `sleep` chains, 2 Edit string
  mismatches, 1 unknown tool), 1 Bash call denied by the auto-mode classifier, 1 Bash call still in progress. All 2,013
  spooled tool records match a transcript `tool_use` (0 orphans, 0 duplicate `tool_use_id`). Rejected and denied calls
  leave no PostToolUse(Failure) record. MEASURED.
- **Ordering:** 1 timestamp inversion inside a spool file (async writes); in 1 of 24 agents a tool record lands after its
  SubagentStop. Every one of 26 starts precedes the agent's first tool record. Consumers must sort by `ts`. MEASURED.
- **Drain:** all 2,328 snapshot records are in `.fw-console/obs.jsonl`, 0 missing, 0 duplicate keys. MEASURED.
- **Latency added:** `duration_ms` is the tool's own duration (Bash p50 240 ms, p90 6.2 s), not hook cost. Hook cost,
  timed with synthetic payloads, 30 interleaved runs at load average 112: bare `node -e 0` p50 118 ms, `emit.mjs` 159 ms,
  `spawn-guard.mjs` 268 ms (p90 1.1 s), `fwcore` alone 107 ms. The plan's 47 ms (3fe1876) was on a quieter machine.
  Synchronous emits in the window: 310 (stops, starts, compaction, session, notification); PostToolUse is async. MEASURED.
- **Hot reload:** records start at 17:24:13, one second after the hooks commit, with no SessionStart before 17:36 (a
  compaction): the hooks block took effect in the running session. MEASURED (INFERRED that it was the settings watcher).

**Spawn-guard shadow log.** 5 records, one per `Agent` tool call after it was installed (5 of 5, joined on `tool_use_id`),
each 1 to 2 s before that call's PostToolUse. `verb` = decision[:reason], as specified (PLAN §8.3): 4 `allow`, 1
`deny:kindMismatch` (a `page-writer` spawned by name without worktree, which the Lean rule `trap_exact` refuses). The
denied agent still started 1 s later: shadow mode holds. Gaps against the spec:
1. **18 of 26 agent starts came from 5 `Workflow` tool calls** and never passed `PreToolUse(Agent)`: spawn-guard cannot
   see Workflow spawns. MEASURED.
2. The reason drops its arguments (want/got kind), so the log cannot tell `kindMismatch(worktree, teammate)` from the
   reverse. CONFIRMED (`spawn-guard.mjs:55`).
3. The console stores SpawnGuard records in `obs.jsonl`, but `/api/board` shows none (0 matches). MEASURED.

**Evidence commit:** HEAD `30fbbd8`; hooks `3e67d48`, spawn-guard `6756bb9`; Claude Code 2.1.302.

## Decision
1. The lead is the record with **no `agent_id`**, never "empty `agent_type`". `cap.mjs` and `actorFor` must refuse
   `agent_id` present with empty `agent_type` (a forked internal agent) instead of mapping it to `main`.
2. A teammate's `agent_type` is its name: the console resolves the role through its roster (name to role, filled by
   spawn-guard from `tool_input.name` and `subagent_type`), not from the payload.
3. Observers drop or label SubagentStop with empty `agent_type` (90 % of all stops) so they do not count as agents.

## Open
- A named worktree subagent's name is not in any payload (only the role). Joining `agent_id` to the name needs the
  `Agent` tool response (`agentId`) or the transcript meta `name`; `emit.mjs` keeps neither.
- Teammate or subagent compaction was not observed (all 10 compactions were the lead's).

## What this changes in the plan
- §8.3 (capability hook) and R27: "binds to `agent_id` and `agent_type`; lead = no `agent_id`; empty `agent_type` with an
  `agent_id` is refused; a teammate's role comes from the roster, because its `agent_type` is its name".
- §8.3 spawn-guard and Q31: add "Workflow spawns bypass `PreToolUse(Agent)` (18 of 26 starts); blocking needs a
  Workflow guard or a SubagentStart check, the log must keep want/got, and the board must show the decisions".
- §3.4 hooks row: emit keeps `source`, `trigger`, `notification_type` and a `background_tasks` count (enums and counts,
  no user text); hook cost under load ~40 ms over Node start (emit), ~150 ms (spawn-guard). Appendix B: SPK-c answered.

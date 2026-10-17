---
id: 2026-10-17-spk-p
kind: note
title: "SPK-p: lead SendMessage address, background-task wake, SessionStart source compact"
status: review
created: 2026-10-17
topics: [spike, decision-record, messaging, hooks, compaction]
---

# SPK-p (decision record, for the lead to sign)

**Question (PLAN Appendix B).** On the v2 Claude Code version: the lead's SendMessage address; does a finished
background task wake an idle teammate; does `SessionStart` fire with source `compact` so `session-brief` can
re-inject the roster?

**Status: PARTIAL, 2 of 3 answered.** Address and compaction answered; the wake test is still open. Claude Code 2.1.302.

| Part | Answer | Status |
|---|---|---|
| 1. Lead's address | In-process teammates reach the lead as **`team-lead`** (33 of 33 sends succeeded). Background subagents are told to use **`main`**. | MEASURED (teammates); CONFIRMED by tool description (`main`, not exercised) |
| 2. Finished background task wakes an idle teammate | Not measurable from the spool: `emit.mjs` drops `background_tasks`, and only 1 TeammateIdle was recorded. v1 said no (I-274). | OPEN |
| 3. `SessionStart` on compaction | **Yes, for the lead.** 10 of 10 compactions produced a SessionStart, 53 to 269 ms before PostCompact. Claude Code runs the session-start hooks with source `compact` during compaction. No subagent or teammate ever fired SessionStart. | MEASURED (firing); CONFIRMED by code (`source`); source value not in the spool |

## Evidence
Spool snapshot of 19:25 (+0700): 2,328 records, 17:24:13 to 19:25:09, two Claude Code restarts. Counts only.

| Claim | Evidence | Status |
|---|---|---|
| 12 SessionStart: 10 within 0.3 s of a PostCompact (always before it), 2 with no compaction (18:35, 18:41 = the two restarts) | `.fw-console/spool/main.jsonl` | MEASURED |
| 10 PreCompact, 10 PostCompact, 30 to 100 s apart; all 30 compaction and session records have no `agent_id` (lead only) | spool | MEASURED |
| Compaction emits a `session_start` hooks phase and calls the session-start hooks with source `"compact"`, then PostCompact (`trigger`, `compact_summary`) | Claude Code 2.1.302 binary, anchors `hookType:"session_start"`, `hook_event_name:"PostCompact"` | CONFIRMED (code) |
| SessionStart input carries `source`, `agent_type`, `model`, `session_title` | binary, anchor `hook_event_name:"SessionStart"` | CONFIRMED (code) |
| `emit.mjs` keeps 9 fields; `source`, `trigger`, `background_tasks` are dropped | `apps/runner/hooks/emit.mjs:23-33` @30fbbd8 | CONFIRMED (code) |
| 0 of 2,328 records have both `agent_id` and SessionStart: a teammate or subagent gets no SessionStart | spool | MEASURED |
| 33 teammate sends to `team-lead` succeeded, 0 errors; lead's messages arrive as `sender: team-lead` | teammate and lead transcripts (earlier draft) | MEASURED |
| SubagentStop carries `background_tasks` (the wake test's signal); the TeammateIdle builder adds only `teammate_name`, `team_name` | binary, anchor `hook_event_name:"SubagentStop"` (`background_tasks` built from the task registry) | CONFIRMED (code) |
| Only 1 TeammateIdle in the snapshot (1 of 3 teammates had finished a turn) | spool | MEASURED |

The full per-event audit (counts, gaps, ordering, latency, spawn-guard log) is in [spk-c.md](spk-c.md).

**Evidence commit:** HEAD `30fbbd8`; hooks `3e67d48`; Claude Code 2.1.302.

## Decision
1. Addresses: teammates send to `team-lead`, background subagents to `main`; `session-brief` prints both.
2. `session-brief.mjs` on `SessionStart` (matchers `startup|resume|compact`) re-injects the roster **for the lead only**.
   Agents need their brief from `SubagentStart` (its `additionalContext`), since they never fire SessionStart.
3. Until part 2 is answered, the stall watcher (§8.5) stays the only defence against a deaf teammate.

## Missing
- Part 2: let `emit.mjs` keep a `background_tasks` count on SubagentStop (a number, no user text),
  then run the controlled test: a teammate starts a background command, goes idle, the command ends, no message arrives.
- Part 1: one send to `main` from a background subagent.
- Keep `source` in the spool record, so the compaction answer is measured rather than read from code.

## What this changes in the plan
- §8.1: the two verified addresses replace "the lead's address was `main`".
- §3.4 hooks row: "`session-brief` on SessionStart (lead only; fires on compaction, MEASURED 10 of 10); agents get their
  brief on SubagentStart". Appendix B: SPK-p "partial: address answered, compaction answered, wake open". R18 unchanged.

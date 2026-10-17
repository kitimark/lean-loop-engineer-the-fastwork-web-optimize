---
id: 2026-10-17-spk-e
kind: note
title: "SPK-e: where do teammate transcripts live, for the usage meter?"
status: draft
created: 2026-10-17
topics: [spike, decision-record, transcripts, usage-meter, agent-teams]
---

# SPK-e (DRAFT decision record)

**Question (PLAN Appendix B).** Where do teammate transcripts live, for the usage meter?

**Status: ANSWERED.**

**Answer.** With the sub-agents, not in a separate team directory:
`<claude-home>/projects/<project>/<session>/subagents/agent-<agentId>.jsonl` with a sibling `.meta.json`. For an
in-process teammate the `agentId` is `a<name>-<16 hex>` (for example `a<teammate-name>-<hash>`). Workflow agents are
elsewhere: `<session>/workflows/` (`subagents/workflows/<runId>/` in the observability note).

## Evidence
| Claim | Evidence | Status |
|---|---|---|
| This teammate's own transcript and meta sit in `<session>/subagents/` next to the worktree subagents (45 agents, 13 of them `taskKind: in_process_teammate`, `spawnDepth: 0`) | directory listing and meta fields, this session | MEASURED |
| The docs path is `.../{sessionId}/subagents/agent-{agentId}.jsonl` | `research/notes/2026/10-17-token-usage-facts.md` §2 @61b6bb6 | CONFIRMED by docs (via note) |
| Teammate meta adds `taskKind`, `teamName`, `color`, `planModeRequired`, `customAgentType`, `spawnedAgentType`, `permissionMode`; there is no parent id field | same | MEASURED |
| Usage repeats across lines of one API message: keep the last line per `message.id` (2,841 messages, 468 with differing `usage`) | `research/notes/2026/10-17-agent-observability-sources.md` §1 @b65e983 | MEASURED |
| All cache writes are 5-minute (`ephemeral_1h_input_tokens` = 0 for every agent type) | same | MEASURED |
| The meter code expects this layout: `obsKey` is shaped for a transcript upsert by `message.id`; the transcript reconciler itself is not built | `docs/team/handoffs/con-hooks.md` "Open" @97bd8a2 | CONFIRMED (code state) |

**Evidence commit:** `61b6bb6`, `b65e983`, `97bd8a2`; HEAD `30e3264`.

## Missing
- Depth-2 attribution: a nested child's `toolUseId` is expected in its parent's transcript, but no depth-2 agent has
  existed yet (INFERRED, `token-usage-facts.md`).
- The transcript tailer / reconciler (usage upsert by `message.id`) is not built.

## Next step
- Build the tailer over `subagents/**/agent-*.jsonl` + `.meta.json`, keyed by `agentId`, with a Lean spec for the
  upsert and dedupe (the TS `standin.ts` in `apps/console-api/src/spool/` is temporary). Owner: lean-prover (spec) then
  console-builder (tailer).
- When the first depth-2 helper runs, check the `toolUseId` link. Owner: console-builder.

## What this changes in the plan
- §8.5 (usage meter): state the path above for teammates and sub-agents alike; teammates need no second source.
  Appendix B: SPK-e "answered".

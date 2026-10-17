---
id: 2026-10-17-spk-b
kind: note
title: "SPK-b: does name + isolation worktree give a named, messageable worktree subagent?"
status: draft
created: 2026-10-17
topics: [spike, decision-record, claude-code, agent-teams, worktree]
---

# SPK-b (DRAFT decision record)

**Question (PLAN Appendix B).** Does `name` + `isolation: "worktree"` on one Agent call give a named, messageable
worktree subagent?

**Status: ANSWERED.**

**Answer.** Yes. Such agents have a name, their own worktree and branch, and `SendMessage` to their name is accepted,
queued for the next tool round, or resumes them if they finished.

## Evidence
| Claim | Evidence | Status |
|---|---|---|
| 28 of 45 agent transcripts in this session carry `spawnedWithWorktree: true`, a `name`, a `worktreeBranch` of the form `worktree-agent-<id>`, `spawnDepth: 1` | `<session>/subagents/agent-*.meta.json` (read with a script; no paths copied) | MEASURED |
| The lead sent 50 `SendMessage` calls to 20 named agents; 0 returned an error | lead transcript, tool_use/tool_result pairs | MEASURED |
| Replies for worktree agents: "Message queued for delivery to `<name>` at its next tool round. If it finishes first, it is resumed with the message" (lean-core, site-aot, lean-site, part-hero, meas-chromium-2 and others); finished agents were resumed: `part-engine`, `site-breakpoints` ("Resuming agent ...", with `resumedAgentId`) | same | MEASURED |
| In-process teammates (13 files, `taskKind: in_process_teammate`, `spawnDepth: 0`) are a different path: their messages get "sent to `<name>`'s inbox" | same | MEASURED |
| Commits made in these worktrees reached `main` through merge commits (`3fe1876` con-hooks, `00c09bf` lean-doc-fix-r4) | `git log` | CONFIRMED |
| Without `isolation` on the call, a named spawn becomes a teammate in the main checkout, even if the role file sets isolation | PLAN §8.1 line ~930 | CONFIRMED by docs (via PLAN); not exercised here |

**Evidence commit:** `3fe1876`, `00c09bf`; checked at HEAD `30e3264`.

## Missing
- That the named worktree subagent really acts on a message (not only that delivery is accepted): shown indirectly by
  handoffs written after resumes (for example `docs/team/handoffs/part-hero.md`), not by a controlled test.
- The negative case (`name` without `isolation` becoming a teammate) is not exercised; spawn-guard does not exist yet.

## Next step
- Spawn-guard (denies a named code-editing spawn without `isolation`) with unit tests; owner: console-builder (agent-ops).

## What this changes in the plan
- Appendix B, SPK-b: status "answered (MEASURED, 28 agents)". §8.1: the delivery wording to keep is "queued at the next
  tool round; a finished agent is resumed".

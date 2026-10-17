---
id: 2026-10-17-spk-p
kind: note
title: "SPK-p: lead SendMessage address, background-task wake, SessionStart source compact"
status: draft
created: 2026-10-17
topics: [spike, decision-record, messaging, hooks, compaction]
---

# SPK-p (DRAFT decision record)

**Question (PLAN Appendix B).** On the v2 Claude Code version: the lead's SendMessage address; does a finished
background task wake an idle teammate; does `SessionStart` fire with source `compact` so `session-brief` can
re-inject the roster?

**Status: PARTIAL.** One of three parts answered, one by docs only, one open. Claude Code in use: 2.1.302.

| Part | Answer | Status |
|---|---|---|
| 1. Lead's address | In-process teammates reach the lead as **`team-lead`**: 33 of 33 sends succeeded. Background subagents are told to use **`main`** (SendMessage tool description). v1's address was also `main`. | MEASURED (teammates); CONFIRMED by tool description (`main`, not exercised) |
| 2. Finished background task wakes an idle teammate | **Not tested.** v1 observed it did not (I-274). | OPEN |
| 3. `SessionStart` source `compact` | Docs list `compact` as a matcher/source ("Auto or manual compaction"). No `SessionStart` hook is installed, so firing in this version is not observed. | CONFIRMED by docs; OPEN as behaviour |

## Evidence
| Claim | Evidence | Status |
|---|---|---|
| 33 `SendMessage` calls from 11 teammates to `team-lead` returned `"success":true`, "Message sent to team-lead's inbox"; 0 errors | scan of `<session>/subagents/agent-*.jsonl` (teammate transcripts) | MEASURED |
| The lead's own messages arrive with `sender: team-lead`; the lead's transcript shows 50 successful sends to 20 names, none failed | lead transcript | MEASURED |
| The SendMessage tool lists `"main"` as "the main conversation (background subagents only)" and teammates by name | this teammate's tool description | CONFIRMED |
| v1: lead address `main`; 20 sends failed on guessed names; a background notice did not wake an idle teammate (I-274) | PLAN §8.1 line ~938-941; `research/kickoff/08-chat-forensics/02-coordination-graph.md` | CONFIRMED (v1 digest) |
| `SessionStart` matcher values: `startup`, `resume`, `clear`, `compact`, `fork`; `source` includes `"compact"` | code.claude.com/docs/en/hooks (fetched 2026-10-17) | CONFIRMED by docs |
| No `hooks` key in `.claude/settings.json`; `session-brief.mjs` and spawn-guard do not exist | `.claude/settings.json` @a0b9053; repo search | CONFIRMED |
| Stall cost seen: idle teammates waiting for the lead pay a cold re-read (plan-rev5 5.9 min and 6.9 min, page-rev5 11.5 min) | `research/notes/2026/10-17-token-usage-profile.md` @61b6bb6 | MEASURED |

**Evidence commit:** `a0b9053` (settings), `61b6bb6` (profile); HEAD `30e3264`.

## Missing
- Part 2: a controlled test: a teammate starts a background command, goes idle, and the command finishes with no
  other message arriving. Does the teammate wake? How long? Note that `TeammateIdle` and `SubagentStop` hooks carry
  `background_tasks` (hooks docs, via the observability note).
- Part 3: install a `SessionStart` hook that logs `source`, trigger a compaction, read the log.
- Part 1: confirm `main` from a background subagent (a one-line send by a worktree agent).

## Next step
1. Lead applies the hooks block (same sitting as SPK-c); console-builder adds `session-brief.mjs` printing the verified
   addresses (`team-lead` for teammates, `main` for subagents). Owner: console-builder (agent-ops).
2. Wake test and `main` test as one script. Owner: console-builder; lead observes.
3. Until part 2 is answered, keep the stall watcher (§8.5) as the only defence.

## What this changes in the plan
- §8.1: replace "the lead's SendMessage address was `main`" by the two verified addresses. Appendix B: SPK-p "partial:
  address answered, compact documented, wake open". R18 unchanged.

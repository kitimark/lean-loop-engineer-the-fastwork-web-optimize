---
id: 2026-10-17-spk-a
kind: note
title: "SPK-a: does CLAUDE_CODE_ENABLE_TODO_TOOLS take effect from the project env?"
status: draft
created: 2026-10-17
topics: [spike, decision-record, claude-code, settings]
---

# SPK-a (DRAFT decision record)

**Question (PLAN Appendix B).** Does `CLAUDE_CODE_ENABLE_TODO_TOOLS` take effect from the project `env`?

**Status: ANSWERED** (one gap: no negative control).

**Answer.** Yes. The variable set in the project `env` reaches the running session and the task tools exist.

## Evidence
| Claim | Evidence | Status |
|---|---|---|
| `.claude/settings.json` sets `env.CLAUDE_CODE_ENABLE_TODO_TOOLS = "1"` (since `c0437de`) | `.claude/settings.json:4-12` @a0b9053 | CONFIRMED |
| The value is not in the user's global settings or `.claude/settings.local.json` (grep count 0 in both) | read-only grep, this session | MEASURED |
| In this session's process, `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` is in the environment of a teammate's Bash call, and `TaskCreate`, `TaskGet`, `TaskList`, `TaskUpdate` are available | environment listing, tool list of this teammate | MEASURED |
| Edits to project `env` reach an already running session: `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` is `10` in the process. `a0b9053` (17:04 local) changed it from 6, and the lead's transcript file was created at 02:04 local | `git show a0b9053`, `token-usage-facts.md` ("Repo sets 6") @61b6bb6, env listing | MEASURED (assumes the lead process was not restarted after `a0b9053`) |
| Docs say task tools are off by default on the 5.5 models and this variable turns them on, also for running sessions | PLAN §8.1 line ~934 | CONFIRMED by docs (via PLAN; not re-fetched) |

**Evidence commit:** `a0b9053` (settings), `c0437de` (variable first added). Checked at HEAD `30e3264`.

## Missing
- A negative control: the same session without the variable, to show the tools were absent. Not needed for the
  decision, but it is why this is "answered" and not "proved".

## Next step
- None required. Re-check once at the next planned restart of the lead (owner: lead), while batching other
  `.claude/**` edits.

## What this changes in the plan
- Appendix B, SPK-a: status "answered (MEASURED)". No section changes.

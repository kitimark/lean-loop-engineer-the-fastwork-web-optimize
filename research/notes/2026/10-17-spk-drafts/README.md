---
id: 2026-10-17-spk-drafts-index
kind: note
title: "SPK decision records for the M0 gate: draft index"
status: draft
created: 2026-10-17
topics: [spike, decision-record, m0-gate, index]
---

# SPK decision-record drafts (M0 gate)

Drafts for the lead to sign (move to `research/decisions/`, change `status` to `signed`). Source of the list: PLAN
§10.2 M0 row and Appendix B. Evidence read up to HEAD `30e3264`. Reading only: no measurements or builds were run.

**Count: 4 answered (a, b, e, k), 8 partial (c, d, i, j, l, o, p, t), 1 open (q).**

| Spike | Question (short) | Status | Key evidence | Missing | Owner role |
|---|---|---|---|---|---|
| [SPK-a](spk-a.md) | `ENABLE_TODO_TOOLS` from project env | **ANSWERED** (MEASURED) | env in process, tools present, `a0b9053` | negative control (optional) | lead |
| [SPK-b](spk-b.md) | named + worktree subagent, messageable | **ANSWERED** (MEASURED) | 28 agents, 50 sends, 0 errors | spawn-guard negative case | console-builder |
| [SPK-c](spk-c.md) | `agent_type` in teammate hooks | PARTIAL | docs: `agent_id` yes; no payload seen; `cap.mjs:47` defaults to `main` | real hook payload; hooks not installed | console-builder, lead |
| [SPK-d](spk-d.md) | `Agent(model:*fable*)` wildcard | PARTIAL | docs: `*` works, omitted model never matches | one observed firing; lint | lead, console-builder |
| [SPK-e](spk-e.md) | teammate transcript location | **ANSWERED** (MEASURED) | `<session>/subagents/agent-<id>.jsonl` + meta, 13 teammates | tailer; depth-2 link | lean-prover, console-builder |
| [SPK-i](spk-i.md) | BeginFrameControl, snapshot fonts, byte-identical vectors | PARTIAL | works, fonts only from snapshot; 28 det / 14 stable / 8 quarantined | byte-identity of whole vector fails; V-i re-scope | lead, measure-engineer |
| [SPK-j](spk-j.md) | harness neutrality | PARTIAL | WebKit seek: 122 style records, independent of N | Chromium shim vs free-running | measure-engineer |
| [SPK-k](spk-k.md) | Serena `lean4` `find_symbol` | **ANSWERED** (MEASURED, outside an agent) | works from the `lean/` project only | call from an agent after restart | lean-prover |
| [SPK-l](spk-l.md) | lean-lsp-mcp tools and disable flag | PARTIAL | `--disable-tools`, 5 local names in 0.31.0 | `lean_hammer_premise` is remote and not disabled | env-ops, lead |
| [SPK-o](spk-o.md) | worktree agent: gate, add, commit, zero refusals | PARTIAL | 138 of 1,652 Bash calls refused (8.4 %); plain add/commit work | `fw gate` missing; clean run | console-builder |
| [SPK-p](spk-p.md) | lead address, wake, `SessionStart` compact | PARTIAL | `team-lead` 33/33; `compact` documented | wake test; hook not installed | console-builder |
| [SPK-q](spk-q.md) | N0/N1 read 0 on arm A | **OPEN** | grep expectation only | lanes record no N0/N1; needs SPK-h | measure-engineer |
| [SPK-t](spk-t.md) | strict sandbox, socket, capability | PARTIAL: (f), (g) unit-tested; (a)-(e) not testable | `sandbox` block absent; cap tests, emit < 100 ms | whole sandbox run; separate-user fallback | lead, console-builder |

SPK-t is partial because only (f) and (g) have evidence; for the M0 gate it is unmet (neither passed nor on the
separate-user fallback).

## Also in this folder
- [class-policy.md](class-policy.md): frozen determinism-class policy per lane (Chromium kMax 4 / tMax 24, 28/14/8;
  WebKit tolerance table and classes), DRAFT.

## What blocks the M0 gate (PLAN §10.2, M0 row)
1. **SPK-t** neither passed nor on the separate-user fallback; needs the lead's one `.claude/settings.json` sitting
   (sandbox + hooks) and a console-builder checklist run.
2. **SPK-q** cannot be answered at M0 without lane changes; move it to M1 or accept the grep as the recorded answer.
3. **SPK-i**: the clause "two byte-identical vectors" is not met; the alternative clause ("failure recorded and V-i
   re-scoped") needs the lead to sign `spk-i.md` and `class-policy.md`.
4. **SPK-c, SPK-p, SPK-o** need hooks installed and `fw gate`; **SPK-l** needs a one-line `.mcp.json` fix.

## Findings that change something now
- SPK-l: `lean_hammer_premise` is a fourth remote tool (`http://leanpremise.net`), missing from `--disable-tools`.
- SPK-c / SPK-t: `cap.mjs` maps a missing `agent_type` to `main` (the lead); refuse instead.
- SPK-o: 8.4 % of worktree-agent Bash calls are refused, mostly `cd <worktree path>` and chained git.

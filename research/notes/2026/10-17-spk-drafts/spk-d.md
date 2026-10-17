---
id: 2026-10-17-spk-d
kind: note
title: "SPK-d: does Agent(model:*fable*) match (wildcards in parameter values)?"
status: draft
created: 2026-10-17
topics: [spike, decision-record, permissions, claude-code, cost]
---

# SPK-d (DRAFT decision record)

**Question (PLAN Appendix B).** Does `Agent(model:*fable*)` match (wildcards in parameter values)?

**Status: PARTIAL.** The docs answer yes; the rule has not been seen to fire.

**Answer.** Yes for an Agent call that passes `model` explicitly: `*` in a parameter value matches any sequence of
characters, so `Agent(model:*fable*)` matches `fable` and `claude-fable-5-1`. It never matches a call that omits
`model`, and it does not look at a role file's `model:`.

## Evidence
| Claim | Evidence | Status |
|---|---|---|
| Deny and ask rules can match a top-level input parameter with `Tool(param:value)`; "The value supports `*` as a wildcard that matches any sequence of characters" | code.claude.com/docs/en/permissions, "Match by input parameter" (fetched 2026-10-17) | CONFIRMED by docs |
| "A parameter the model omits is never matched, so `Agent(model:*)` doesn't match a call that leaves `model` unset" | same | CONFIRMED by docs |
| "The value is compared against the literal input Claude sends, before any normalization. `Agent(model:opus)` matches the alias `opus` but not a full model ID" (so a wildcard is needed for full ids) | same | CONFIRMED by docs |
| Parameter matching works for `ask` and `deny` rules (not `allow`) | same | CONFIRMED by docs |
| The rule is in place as an `ask` rule | `.claude/settings.json` `permissions.ask` @a0b9053 (added in `bdff9b3`) | CONFIRMED |
| No Agent call in this session passed a model containing "fable": the models seen are none or `sonnet` | scan of the lead transcript's Agent tool_use inputs (counts only) | MEASURED |
| Role files that pin a model are not caught (the PLAN adds a lint that forbids `fable` in `.claude/agents/*.md`) | PLAN §8.1 line ~935 | CONFIRMED by docs (via PLAN) |

**Evidence commit:** `bdff9b3` (rule added), `a0b9053` (current settings); HEAD `30e3264`.

## Missing
- One observed firing: an Agent call with `model: "fable"` showing the ask prompt. Not done because it would put a
  prompt in front of the user.
- The lint over `.claude/agents/*.md` (`fable` forbidden) is not built.

## Next step
- Owner: lead. At the first deliberate Fable spawn, record that the ask prompt appeared (or did not). Owner for the
  lint: console-builder (agent-ops), a unit-tested script in the spawn-guard family.

## What this changes in the plan
- Appendix B, SPK-d: "partial (docs: wildcard works, omitted `model` never matches)". §8.1 stays as written; add
  that `Agent(model:*fable*)` is an `ask`/`deny` rule only and does not cover a spawn that omits `model` or inherits it.

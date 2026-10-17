---
id: 2026-10-17-spk-k
kind: note
title: "SPK-k: does Serena's lean4 language server answer find_symbol on a Lean file?"
status: draft
created: 2026-10-17
topics: [spike, decision-record, serena, lean, tooling]
---

# SPK-k (DRAFT decision record)

**Question (PLAN Appendix B).** Does Serena's `lean4` language server answer `find_symbol` on a Lean file? If not:
Serena for TypeScript only, lean-lsp-mcp for Lean.

**Status: ANSWERED** (outside an agent session; see Missing).

**Answer.** Yes, but only when the Serena project root is the lake root (`lean/`). From the repo root the server gets
no `LEAN_PATH` for `Fw.*` and returns no symbols. So: the main Serena project covers TypeScript, a second project
`fwcore-lean` (path `lean/`) covers Lean, and both lean-lsp-mcp and `serena-lean` are kept.

## Evidence
| Claim | Evidence | Status |
|---|---|---|
| `lean4` is in Serena's language list | `.serena/project.yml` (PLAN Appendix B) | CONFIRMED |
| From `lean/`: symbols, `find_symbol`, references and hover work (on `Fw/Console.lean`); from the repo root no symbols | `docs/team/serena.md`, "Projects" and "What works" @22ee927 | MEASURED |
| Imports resolve only through `lake env` | same | MEASURED |
| `.mcp.json` registers `serena-lean` with `--project lean`; the build and research roles list the `mcp__serena-lean__*` tools | `.mcp.json` @4c9dd2a; `.claude/agents/lean-prover.md:6` | CONFIRMED |
| Serena 1.7.0 | `docs/team/serena.md` | CONFIRMED |

**Evidence commit:** `22ee927` (projects, doc), `4c9dd2a` (MCP server and role tools); HEAD `30e3264`.

## Missing
- No transcript in this session contains a call to a `mcp__serena-lean__*` or `mcp__lean-lsp__*` tool (scan of the lead
  and all 45 agent transcripts), so the MCP server was probably not loaded before `4c9dd2a`. The check "an agent calls
  `find_symbol` on `Fw/Console.lean` through `serena-lean`" is outstanding.

## Next step
- After the next lead restart (MCP servers are read at start), a lean-prover role runs `get_symbols_overview` and
  `find_symbol` on one `Fw/Spec` file via `serena-lean` and records the result here. Owner: lean-prover. The server
  entry is `serena` on PATH: env-ops confirms `serena` resolves for subagents.

## What this changes in the plan
- §8 / Appendix B: SPK-k "answered: yes, from the `lean/` project only". Keep the "Serena TypeScript only" fallback
  unused. Note the project-root rule in the Serena paragraph of §8.

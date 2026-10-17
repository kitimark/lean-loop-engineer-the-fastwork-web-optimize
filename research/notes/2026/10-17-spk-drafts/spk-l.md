---
id: 2026-10-17-spk-l
kind: note
title: "SPK-l: lean-lsp-mcp local tool names and a flag that disables its remote search tools"
status: draft
created: 2026-10-17
topics: [spike, decision-record, lean-lsp-mcp, tooling, privacy]
---

# SPK-l (DRAFT decision record)

**Question (PLAN Appendix B).** lean-lsp-mcp: exact local tool names, and a launch flag that disables its remote
search tools.

**Status: PARTIAL.** Names and flag are confirmed in the 0.31.0 source; the disable list misses one remote tool.

**Answer.**
- Flag: `--disable-tools <comma list>` (sets `LEAN_MCP_DISABLED_TOOLS`, removes the tools at start; an unknown name only logs a warning).
- Local tools used by the team: `lean_goal`, `lean_term_goal`, `lean_diagnostic_messages`, `lean_hover_info`,
  `lean_local_search`. Other local tools exist (`lean_file_outline`, `lean_declaration_file`, `lean_references`,
  `lean_completions`, `lean_code_actions`, `lean_multi_attempt`, `lean_verify`, `lean_profile_proof`, `lean_build`,
  `lean_minimal_hypotheses`, `lean_get_widgets`, `lean_get_widget_source`, `lean_run_code`).
- **Remote tools (open-world, network): `lean_leansearch`, `lean_loogle`, `lean_leanfinder` and `lean_hammer_premise`.**
  The project disables the first three and `lean_run_code`, but **not `lean_hammer_premise`**, which calls
  `http://leanpremise.net` by default (`DEFAULT_HAMMER_URL`).

## Evidence
| Claim | Evidence | Status |
|---|---|---|
| Pinned `lean-lsp-mcp==0.31.0` via `uvx`, with `--disable-tools lean_leansearch,lean_loogle,lean_leanfinder,lean_run_code` | `.mcp.json` @4c9dd2a | CONFIRMED |
| `--disable-tools` exists ("Comma-separated tool names to disable") and removes tools via `server.remove_tool` | package source 0.31.0 (local uv cache), `lean_lsp_mcp/__init__.py` l.94-96, 138-139; `server.py` `apply_tool_configuration` | CONFIRMED (source) |
| Tool names registered with `@tool("lean_...")` in `tools/*.py` | same package, `tools/goals.py` l.18-20 and the other modules | CONFIRMED (source) |
| `lean_leansearch` posts to `https://leansearch.net/search`; `lean_hammer_premise` has `open_world_hint=True` and `DEFAULT_HAMMER_URL = "http://leanpremise.net"` | `tools/search.py`, `config.py` l.41 | CONFIRMED (source) |
| Allowed tools in settings are exactly the five local ones | `.claude/settings.json` `permissions.allow` @a0b9053 | CONFIRMED |
| Role files list only those tools (a tool absent from `tools:` is not callable by the role) | `.claude/agents/lean-prover.md:6` | CONFIRMED |
| No call to any `mcp__lean-lsp__*` tool exists in this session's transcripts | scan of 46 transcripts | MEASURED |

**Evidence commit:** `4c9dd2a`; settings `a0b9053`; HEAD `30e3264`.

## Missing
- `lean_hammer_premise` is not disabled. Role `tools:` lists keep agents away from it, but any agent without a `tools:`
  list (general-purpose, a fork) would be offered it, and a call would send proof state to a third-party server (the
  repo rule on outward-facing traffic).
- A live check after restart that the server starts, lists exactly the five tools, and that `lean_local_search` works.

## Next step
1. Lead edits `.mcp.json`: add `lean_hammer_premise` to `--disable-tools`. Owner: env-ops drafts, lead applies
   (`.mcp.json` is outside `.claude/`, but user-approved config).
2. After the next restart: list the server's tools and record the names. Owner: env-ops.
3. Optional: also disable `lean_build` and `lean_multi_attempt` so builds go through `lake`/`fw` only (PROPOSAL).

## What this changes in the plan
- §8.3 line ~1077 ("flag that disables its remote search tools are checked at install"): name the flag and list four
  remote tools, not three. Appendix B: SPK-l "partial; add `lean_hammer_premise`".

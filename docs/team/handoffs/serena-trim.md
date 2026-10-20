# Handoff: serena-trim

State: committed on branch worktree-wf_2bbfa127-06f-2 (see `git log -1`).

Done
- `.mcp.json`: serena-lean server removed; serena and lean-lsp stay.
- `.claude/agents/lean-prover.md`, `math-reviewer.md`: mcp__serena-lean__* tools removed; both list the eight
  lean-lsp lookup tools (local_search, hover_info, goal, term_goal, diagnostic_messages, declaration_file,
  references, file_outline). No agent prose mentioned serena, so none changed; mcp__serena__* entries kept.
- `docs/team/serena.md`: serena on demand (`/mcp`), serena-lean gone, Lean lookups via lean-lsp; stale facts fixed
  (version 2.0.0, `--project .`, fwcore-lean project row dropped).

Verified: `.mcp.json` parses; `grep serena-lean` finds nothing in `.mcp.json` or `.claude/agents/`.

Open (lead)
- `.claude/settings.json:74-78` still allows five mcp__serena-lean__* tools: user command to delete them.
- settings.json has no allow rule for mcp__lean-lsp__lean_declaration_file, lean_references, lean_file_outline.
- Not edited (listed): docs/plan/PLAN.md:848 names serena-lean; lean/.serena/project.yml (fwcore-lean project)
  and its CheckMap.lean:341-342 rows may now be dead; history in research/notes/2026/10-17-plan-evidence.md,
  10-17-spk-drafts/spk-k.md, 10-18-chrome-agent-docs.md, 10-20-resource-audit.md, docs/team/improvements/2026-10-17.md.

Read first: docs/team/serena.md, then research/notes/2026/10-20-resource-audit.md section 2.

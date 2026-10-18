# context-slop handoff

State: round 2 on branch `worktree-wf_d6adc6c8-d0a-1` (round 1 `worktree-wf_fb7bd57e-030-3` merged onto main 0cc1dfa);
check.sh green at the final head; not landed.
Read first: `research/notes/2026/10-18-context-slop.md` (savings, rules applied and rejected, where each rule lives now).

Done
- Lean `Fw.Lint.Context` (kinds, budgets, slop markers, verdict; `verdict_cases`, `over_mono`, `overBudget_mono`,
  `rank_mono`), fwcore op `lint.context`, golden `packages/contracts/golden/lint/lint.context.jsonl` (`Fw.Ops.Golden`
  `extra`), glue `scripts/context-lint.mjs`, standalone and warn-only (its doc reads are outside `CHECK_SH_READS`).
- Skills `.claude/skills/no-slop`, `.claude/skills/no-comments`; helper `.claude/agents/slop-checker.md`; SpawnGuard
  roster + `every_role_spawnable`, `helpers_from_lead`, `helpers_nested`, `patcher_nested_refused`.
- Round 2: CLAUDE.md "Review loops (lead)" restored; lean-prover keeps the exact-strength rule and the 6-point checklist;
  the 5 spawning roles keep a short helper block; skill pointers are repo paths; `verdict_of_facts` deleted; budgets
  CLAUDE.md 5,600 B, agent 2,500 B; wait-guard shadow rounds 1-5 in `research/notes/2026/10-18-wait-guard-shadow-review.md`.
- Patcher at depth 0 = lead: CONFIRMED (hooks docs, `teammateMode: in-process`) and MEASURED (teammate spool records carry
  `agent_id`); evidence and the split-pane limit in `docs/team/tools/spawn-guard.md` class C.

Conventions
- Docstring math: no where/with clause after `$$` (mathview drops it); define helpers inside the `$$`.
- Agents have no Skill tool: point to `.claude/skills/<name>/SKILL.md`, never "skill X".
- The dry land needs `--allow` for the moved research notes (undeclared writes).

Open
- Lint: 48 over budget (46 handoffs, lean-first.md, wait-guard.md), 0 slop; `--strict` and a land check are lead calls.
- Budget raise (5,000 to 5,600 B, 2,000 to 2,500 B) is a lead decision; revert means trimming loaded rules.
- Work-graph titles, deny-message shadow suffix, workflow prelude, comment headers: the note's followups.
- Docstrings self-checked (no Agent tool in the workflow, so no checker).

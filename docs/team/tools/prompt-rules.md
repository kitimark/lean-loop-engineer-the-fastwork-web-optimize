# Prompt rules: one block instead of restating

Workflow scripts and spawn prompts repeated the same rules in 20-52 scripts each (MEASURED, see
`research/notes/2026/10-18-context-slop.md`). A role already loads CLAUDE.md and its body, so a prompt to a role names
only what differs. Cite this file and the rule ids below instead of pasting the text.

## For a role (loads CLAUDE.md)

Write only: goal, inputs (paths), write scope, checks, verify command, report shape, timebox. Do not restate CLAUDE.md
(personal data, Fastwork, statuses, 150-line output, commits, handoff) or the role body (wt-prep, docstrings, helpers).
Add a line from the list below only when the task changes it.

## Shared rules, by id

| Id | Rule |
|---|---|
| R1 | Write only the paths the task names; list anything else as a followup with its measured size. |
| R2 | Commit inside your worktree branch with `git add -- <paths>`; never land, never push except `ci/*`. |
| R3 | Lean first: decide and prove in Lean, then generate or golden-check the code; no `sorry`, `native_decide`, `implemented_by`, `unsafe`; `#print axioms` standard only. |
| R4 | Comments and docstrings per `.claude/agents/comment-sicko.md`; `#guard` for each decision function. |
| R5 | Hand back only after merging `main` and `pnpm fw land <branch> --task <id> --dry` ends with `VERDICT dry <id>` (`docs/team/tools/land.md`). |
| R5b | Report `items` [{id, status, evidence}], one per deliverable and per prior finding (status `done` `pending` `dispatch` `followUp` `undelivered`; evidence a `path:line` or `run:<id>`), the `dry` line, and the line of `pnpm -s fw review ready --report <json> --task <id>` (Lean `Fw.Plan.ReviewReady.reviewReady`). Answers: `review` (reviewed), `wait`, `dispatch`, `returnToBuilder` (the build goes back to the lead, no review). |
| R5c | A review grades each finding `blocker`, `fix-before-land` or `follow-up` and gets its verdict from `pnpm -s fw review verdict --findings <json>` (Lean `verdictOf`: accept iff no blocker; interim `strictVerdict` also refuses on `fix-before-land` until the medium-only refusals are audited). `fix-before-land` text the lead applies gets a checker re-check before land. |
| R6 | Write the handoff `docs/team/handoffs/<name>.md`, at most 30 lines (`.claude/skills/no-slop/SKILL.md`). |
| R7 | Report at most 300 characters plus paths. |

## For a helper (skips CLAUDE.md)

Helpers do not load CLAUDE.md, so their prompt carries the rules they need, at most 15 lines:

```
Question: <one question or checklist>. Paths: <absolute paths>.
Read-only: never edit, never run git writes; scratch only under <scratchpad path>.
Read with offset/limit; never print > 150 lines. No personal data, no Fastwork site code.
Return ≤ 1k tokens: line 1 the answer or pass/fail; then path:line - fact (CONFIRMED/INFERRED); then Not checked:.
```

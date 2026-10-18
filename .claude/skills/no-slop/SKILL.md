---
name: no-slop
description: Use when writing or trimming text agents read (docs, handoffs, research notes, tool docs, agent and skill files, workflow and spawn prompts, command output). Budgets, one fact once, no narration, plain words.
---

# No slop

Agents re-read these files on every spawn or task, so each line costs tokens many times. Rule ids (D, A, P, N, H) refer to
`research/notes/2026/10-18-context-slop.md`.

## Budgets

| File | Budget |
|---|---|
| `CLAUDE.md` | 5000 B |
| `.claude/agents/*.md` | 2000 B, description 300 B |
| `.claude/skills/*/SKILL.md` | 4000 B, description 300 B |
| `docs/team/tools/*.md`, `docs/team/token-policy.md` | 6000 B |
| `docs/team/handoffs/*.md` | 30 lines |
| research note | 200 lines |
| report to the lead | 300 characters plus paths |
| helper return | 1k tokens |

`node scripts/context-lint.mjs [paths]` checks the first five rows (Lean `Fw.Lint.Context`). Over budget: cut detail or move
rationale to a research note and leave a one-line pointer. Only the lead changes a budget.

## Cut

- Narration: how you got here, dates, "user decision on ...", incident stories. Git and notes hold history.
- Restatement: a rule lives in one file; everywhere else names that file (D30, A5, A9).
- Rationale in rule files: keep the rule, move the evidence to a research note.
- Filler phrases and inflated words: the lint lists them (`fillers`, `aiWords` in `lean/Fw/Lint/Context.lean`). No em dash;
  end the sentence or use a comma (D1, D2, D5, D11).
- Headings named after a task, like "Output (task x)": name the use instead.
- SHAs, dates and drifting paths in agent and skill bodies (A7). Notes keep `file:line@commit`.
- Stubs, pages with nothing new (D31), and lines no future agent would act on differently (A4).

## Write

- The real name of the symbol, file, flag or command, and one name per thing (D3, D4).
- The mechanism or number with its status (CONFIRMED, INFERRED, MEASURED) in the same sentence (D8, N6).
- Short sentences, active voice, the condition before the step it guards (D9, D20, D23).
- Tables for numbers, bullets for rules, one doc mode per file (D22).
- A count names the command that regenerates it (D28).

## By file type

- Handoff: state with commit, what is verified, open items, next step, files to read first, gotchas. Over 30 lines: cut
  detail before open threads. Point to logs, notes and run ids, never paste them (N1-N4).
- Research note: the answer first, then evidence with citations.
- Tool doc: sections Use, Output, Fails; Lean theorem names on one line; history goes to a note.
- Agent or skill body: rules that stay true when paths and versions change; name other skills, do not restate them (A7, A9).
- Workflow or spawn prompt: goal, write scope, checks, verify command, report shape. Pass file paths, not file contents.
  Do not restate CLAUDE.md or the role body; shared lines are in `docs/team/tools/prompt-rules.md`. Size the prompt to
  the job (P1-P3).
- Command and hook output: one summary line plus a file path; one line naming the step when it cannot run; no chat
  phrases (H1-H3).

## Prefer structure

A lesson written twice becomes a lint, hook, type or Lean check, and then the prose goes (A1, A2).

Review a diff against this skill: spawn `slop-checker`.

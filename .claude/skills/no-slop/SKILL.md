---
name: no-slop
description: Use when writing or trimming prose agents or the user read (reports, notes, handoffs, prompts, docs, agent and skill files, commit messages, command output). Cut AI tells, write plain sentences, keep reader load low.
---

# No slop

Write so a tired reader understands on the first read. Agents re-read these files on every spawn, so each line costs
tokens many times. Evidence: `research/notes/2026/10-18-context-slop.md`.

Adapted from cursor/plugins pstack (MIT, (c) 2026 Lauren Tan), commit d457567

## Budgets

- `node scripts/context-lint.mjs [paths]` checks: `CLAUDE.md` 5600 B, `.claude/agents/*.md` 2500 B,
  `.claude/skills/*/SKILL.md` 4000 B (descriptions 300 B), `docs/team/tools/*.md` and `docs/team/token-policy.md`
  6000 B, handoffs 30 lines.
- Unchecked: research note 200 lines, report to the lead 300 characters plus paths, helper return 1k tokens.
- Over budget: cut, or move the evidence to a note with a one-line pointer. Only the lead changes a budget.

## Cut

- Words that do no work: filler, hedging, adverbs that prop up a weak verb, inflated words (the lint lists them in
  `lean/Fw/Lint/Context.lean`), chat phrases, praise, generic conclusions.
- Tells: em dashes, "-ing" tails ("ensuring ..."), "serves as" for "is", "not just X but Y", forced groups of three,
  synonym cycling, vague attributions, colons as connectors, bold labels that restate the line, title case, emojis.
- Metaphor where a literal word exists: "base", "add", "a limit that only tightens", not substrate, wedge, ratchet.
- Narration and history: how you got here, dates, incident stories. Git and notes keep them.
- A rule restated: it lives in one file, and other files name that file. Rationale in a rule file moves to a note.
- Task names in headings. SHAs, dates and drifting paths in agent and skill bodies (the attribution line excepted).
- Lines no future reader would act on differently.

## Write

- Say what it does: the mechanism or number, with its status (CONFIRMED, INFERRED, MEASURED) in the same sentence. A
  sentence that could stand unchanged in another project's docs says nothing.
- The real name of the symbol, file, flag or command, and one name per thing everywhere.
- One thought per sentence, active voice, the condition before the step it guards, the common case first, commands.
- Whole sentences with their articles and verbs. No arrows, slashes or symbol-speak in prose; tables and code may use
  them. Every "it" and "this" points at one thing.
- Mix sentence lengths. A long sentence that carries one fact with its condition stays long.
- A pointer leads to the rule, never to another pointer. State an invariant once, where it is defined. Test: a new
  reader finds where X comes from and what changes it in 30 seconds.
- One doc mode per file (how-to, reference, explanation, tutorial). Tables for numbers, bullets for rules. A count
  names the command that regenerates it.

## By file type

- Handoff: state with commit, what is verified, open items, next step, files to read first. Point to logs and run ids.
- Research note: the answer first, then evidence with citations.
- Tool doc: Use, Output, Fails; Lean theorem names on one line.
- Agent or skill body: rules that stay true when paths and versions change. Name other skills, do not restate them.
- Spawn or workflow prompt: goal, write scope, checks, verify command, report shape. File paths, not contents. Shared
  lines: `docs/team/tools/prompt-rules.md`.
- Report or commit message: a briefing read in a minute. Link logs and tables.
- Command and hook output: one summary line plus a file path.

A lesson written twice becomes a lint, hook, type or Lean check, and the prose goes. Review prose: spawn
`slop-checker`. Code comments: `.claude/skills/no-comments/SKILL.md`.

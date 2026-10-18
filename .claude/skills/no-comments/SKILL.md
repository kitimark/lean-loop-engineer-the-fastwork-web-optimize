---
name: no-comments
description: Use when writing or reviewing code comments in TS, JS, shell, YAML or Lean. Keep a comment only for a why the code cannot show; Lean $$ math docstrings stay mandatory with minimal prose around them.
---

# No comments

Every agent that opens a file reads its comments. Keep a comment only when it changes what the reader does. Rule ids (C)
refer to `research/notes/2026/10-18-context-slop.md`.

## Keep

- A why the code cannot show: a constraint, a non-obvious choice, a trap (C1).
- Behavior forced by code we cannot change (WebKit, Chromium, Lean core, a vendor, a protocol), cited as
  `file:line@commit` (C2).
- A doc comment on an exported function: what it returns, units, edge cases, in one line where possible.
- The status (CONFIRMED, INFERRED, MEASURED) of a measured constant.

## Cut

- What the next line does, the function name restated, banners (C4).
- History: `(task x)` tags, "previously", "used to", "no longer", incident ids. Git holds history.
- Commented-out code; git has it (C4).
- Phase comments in tests and scripts (`// Phase 1`); the assertion or log line names the step (C5).
- Research in a file header. A header says in at most 3 lines what the file is for and where its spec lives; findings go
  to a research note.
- Comments that explain our own surprising code: rename, extract or retype instead (C3).
- An invariant stated in prose: move it into a type, a Lean proof, a test or a lint (C7).
- A paragraph that explains a workaround: fix the code (C6).
- `IMPORTANT` or `do not remove` with no evidence nearby: check it, then keep it with the reason or delete it (C8).
- A suppression (`eslint-disable`, `@ts-ignore`, `set_option linter.* false`) that hides a real finding: fix the code (C9).

## Lean

- Every `theorem` and key `def` keeps its docstring: the statement as LaTeX between `$$`, exactly as strong as the Lean
  statement, then one plain sentence. The user reviews the math, so this is never slop.
- Around the math: no proof narration, no restated Lean, no history. A helper lemma needs one sentence.
- A `/-! -/` module doc says what the module decides and who consumes it, in at most 5 lines.
- Inside a proof, comment only a step that is not obvious.

## Shell and YAML

- A `#` comment only for a flag or value whose reason is not obvious, with the doc or issue it comes from.
- Workflow YAML: the step `name:` names the step; no narration around it.

Review: spawn `slop-checker`, a reviewer that did not write the comments (C10).

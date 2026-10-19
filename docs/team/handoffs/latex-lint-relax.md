# latex-lint-relax (step B0 of lean-latex-removal)

State: branch worktree-wf_03cbf400-7bd-1, lint change in commit 5e4e2fb4 (plus this handoff commit).

Done:
- `MathView.lintEntry` refuses only on: export failed, depends on `sorryAx`, non-standard axiom. The rules
  "no $$ math in its docstring" and "no English sentence before the math" are gone.
- `MathView.english` is the whole docstring, trimmed; an entry without a docstring has `english = ""`.
- `#guard`s after `lintEntry` (helper `lintProbe`): no docstring passes, a plain docstring passes,
  `sorryAx` fails, a non-standard axiom fails, an export error fails once.

Verified: `sh lean/scripts/check.sh` green at 5e4e2fb4 (mathview lint 9334 entries, 0 failing);
`node --test scripts/ci-paths.test.mjs` 32/32; `apps/runner` `pnpm test` (see report for result).
No other file mentioned the removed messages (grep over .github, apps/runner, lean/scripts, packages, scripts).

Open (later steps of lean-latex-removal, not done here):
- fields `math`/`mathHash`/`binders`, quantifier lint (`warnEntry`), ShadowLint, WhereLint, generators, strip.
- WhereLint's module doc in `lean/MathViewMain.lean` still says the export keeps "the English before the first $$".

Read first: `lean/MathView.lean` around `english` (~line 256) and `lintEntry` (~line 405).

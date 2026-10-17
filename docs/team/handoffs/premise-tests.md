# premise-tests handoff

State: branch worktree-agent-ac5a2d77ab9f7910b, CI branch `ci/premise-tests` at 078a59a. CI run 39076735134: 14 of 15 premises hold on Chromium 156 + WebKit (Linux); only cv.auto-margin fails (both). Read first: `docs/team/tools/premises.md`.

- Lean: `lean/Fw/Ops/Premise.lean` (15 premises, `premiseLint_sound`, `flagged_*`, `registry_lint_clean`); golden
  `packages/contracts/golden/ops/premise.jsonl` from `lean/scripts/PremiseGolden.lean` (`--check` to compare).
- Browser: `packages/premise-tests` (`pages/<id>.html`, `src/tests.mjs`, `src/run.mjs`), tests `prem.<id>`, both engines.
- TS: `apps/runner/src/premises.ts` (`pnpm fw premises [--results dir]`), test `apps/runner/test/premises.test.ts`, one dispatch line in `fw.ts`.
- CI: `.github/workflows/premise-tests.yml` (jobs `engine` x2, `verdict`). Red verdict = a premise finding, not a harness bug.

Files outside the allowed list that I had to touch: `lean/scripts/PremiseGolden.lean` (golden writer, same pattern as other
scripts), `pnpm-lock.yaml` (new importer), `packages/premise-tests/.gitignore` (`out/`).

Finding: premise `cv.auto-margin` ("a node under a content-visibility-skipped subtree reports unresolved `auto` margins") is FALSE on
Chromium and WebKit: a style read forces the lock open and returns the used px; only `display:none` reports `auto`. It stays registered
as a negative result, so `fw premises` flags `planned:gate-settle` and `planned:fix-commission` for it. The corrected premise
`cv.read-forces-lock` holds. Gate-settle and fix-commission must not rely on `auto` margins to detect skipped subtrees.

Open items:
- When a `planned:<task>` theorem lands, rename the entry in `registry` to the real name and regenerate the golden.
- Decide whether to keep the false `cv.auto-margin` red in CI or move it to a `refuted` list (needs a Lean change: `Premise.expected`).
- Local runs on this Mac were debug only (Chrome 155, WebKit 27.2); results come from the CI run recorded in the lead's report.

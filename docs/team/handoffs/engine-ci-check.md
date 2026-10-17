# engine-ci-check (handoff)
**State:** done on branch `worktree-agent-a545afa4b06a14761` (commit in the report). `lake build` green, `lake test` green, mathview 0 failing
(38 binder-quantifier warnings in EngineCheck, same kind as the rest of the repo), `pnpm --filter ./apps/runner test` green (147 tests).
Axioms of the soundness theorems: propext, Classical.choice, Quot.sound only. No sorry, no partial.
**Files:** `lean/Fw/Measure/EngineCheck.lean` (core + wire op), one import/ops/handle/doc-row in `lean/Fw/Measure/Wire.lean`,
`apps/runner/src/engine-check.ts`, `apps/runner/test/engine-check.test.ts`, one import + dispatch + usage in `apps/runner/src/fw.ts`.
**Use:** `pnpm fw engine-check --rows <predictions.jsonl> --run <downloaded artifact dir> [--classes <classes.frozen.json>] [--json]`.
Exit 0 = no model-bug, 3 = at least one model-bug, 64 = usage. `--run` is searched recursively for `counts.json`; variant = `meta.target`
(also `target+search`, or `meta.variant`), scenario = `profile.id` (or `meta.scenario`). Default classes: `packages/measure-chromium/classes.frozen.json`.
**Rows:** `{engine, scenario, variant, stage, prediction (=0 | =o | <o | ≤o | any), countType, base?}`; `base` (default `original`) is the
variant `o` in `=o`, `<o`, `≤o`. Webkit rows are accepted and come back `unusable: no lane yet` (`laneRes_webkit`).
**Rules (all proved):** quarantined never used (`quarantined_unusable`); det exact; stable (k>=1) compared by totals with margin 2t
(`totals_gap`, `leO_pass_margin`); stable k=0 is frame exact; `=0` is every frame 0; `<o` only on frame-exact classes, else unusable
(`ltO_stable_unusable`). `pass_sound`: a pass certifies the claim for every unseen pair within the class; `bug_sound`: a bug refutes it for
every such pair; lifted to many runs by `rowRes_pass_sound` / `rowRes_bug_sound` (`combine`). Three verdicts: pass / model-bug / unusable
(reasons: quarantined, strictNeedsExact, inconclusive (inside the noise), noObs, noLane).
**Conventions:** TS reads files and calls `measure.engineCheck`; no decision in TS. Wire helpers are private in
`Fw.Wire.Measure.EngineCheck` (Wire.lean imports EngineCheck, so the op cannot live in Wire.lean).
**Open:**
- F1/F2 (packages/measure-chromium/README.md:146-149): the fixture counts.json are not in the repo and CI runs no fixture profile, so no real
  F1/F2 result; the test models the README numbers with synthetic counts. Run the fixture profiles on CI, then call the CLI on that artifact.
- Store refs for `--run` are not supported (directory only).
- `<o` on stable (k>=1) types is unusable by choice; stable noise gives unusable, never pass.
- Prediction rows come from engine-chromium-lean / engine-webkit-lean (`packages/contracts/golden/engine/*.jsonl`); I did not see their
  schema (not on this branch). The optional `base` field is mine: adapt the row reader if theirs differs.
- No wire golden was written (outside the allowed files); `#guard` cases cover every decision in Lean.
**Read first:** the module docstring of EngineCheck.lean, then `engine-check.ts`.

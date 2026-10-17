# Handoff: step-align (WebKit original vs rewrite by scroll position; merge by row key)

State: branch worktree-agent-a916f9841bd5d6301, CI branch ci/step-align. Results: `research/notes/2026/10-18-step-align.md`.

Cause of 74 vs 107 steps: page height only (docH 6042 vs 4378, same 50 px step). Not a harness bug; schedule unchanged.

Built
- `lean/Fw/Measure/StepAlign.lean`: steps keyed by (prev y, y, next y); `pairedSteps`; `align` zones (500 px) with A/B sums over
  paired steps, delta, `full` flag; proofs (partition, delta total, swap, self). Rows across sessions: `pairedRows`,
  `unpairedRows`, `mem_pairedRows`, `mem_unpairedRows`, `pair_cover`, `unpairedRows_count`, `pair_self`.
- Wire ops `measure.webkit.align` and `measure.webkit.pairRows` (Wire.lean), goldens in
  `packages/contracts/golden/measure/` (regenerate: `cd lean && lake env lean --run scripts/MeasureGolden.lean`).
- `packages/measure-webkit/src/align.mjs` (+ `cli.mjs align|align-classes`), `src/mergerows.mjs` (+ `cli.mjs merge`: paired rows
  with the worst class, then unpaired rows "k of n sessions" with Lean's reason; `--out` has `unpaired`). Glue only.
- `.github/workflows/webkit-sim.yml`: target original|rewrite|both (rewrite = jobs r1..rN, `--site`), experiment determinism|quiet
  (quiet needs target original), `align` job, `merge` job (needs the fwcore artifact; fwcore job runs when original is built).

Conventions: Lean first, JS prints; mathview lint 0 failing; tests `pnpm --filter ./packages/measure-webkit test`.

Open items
- Preset/fw on the rewrite arm are still refused by `plan` (default config only).
- When one VM is 1 px taller, the end-of-page census rows (y=5267 / y=5268) are unpaired and excluded, by design and reported.
- CI verdict of ci/step-align after the merge fix: in the lead's report / the note.

Read first: the note, StepAlign.lean doc header, `align.mjs`, `mergerows.mjs`.

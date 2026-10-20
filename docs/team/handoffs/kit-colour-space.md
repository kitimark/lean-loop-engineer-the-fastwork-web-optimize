# kit-colour-space handoff

Branch `worktree-wf_e1d953e4-5eb-2`. State: done (round 2), nothing pushed to `ci/*`, no CI dispatch.

## What changed
- `packages/gate-breakpoints/src/trajectory/kit.mjs`: `colour` reads rgb/rgba, hsl, color(srgb), oklab, oklch, lab, lch as
  sRGB x1000 plus alpha x255x1000 (unclamped). `colourFromV1` (offline only) reads the old oklab-shaped tuples back.
- `lean/Fw/Gate/Colour.lean`: engine citations, error budget (`chanErr` 500, `alphaErr` 1000), `budget_inside_tol`
  (channels 1000 of 2000, alpha 2000 of 2000), `judge_colour_same_truth`; generator `lean/scripts/ColourGolden.lean`.
  Lean proves the conditional; the kit staying in the budget is MEASURED by `test/kit-colour.test.mjs`.
- Golden `packages/contracts/golden/gate/trajectory-colour.jsonl` (27 lines).
- Writes outside the task list (lead-approved): `lean/Fw.lean`, `lean/scripts/check.sh`, `lean/Fw/Ci/Trigger.lean`,
  `lean/scripts/ColourGolden.lean`, regenerated `packages/contracts/golden/ci/triggers.jsonl`.

## Verified
- `sh lean/scripts/check.sh`, gate-breakpoints `pnpm test`, `scripts/ci-paths.test.mjs`, apps/runner `land-inputs.test.ts`.
- Re-reduction of every `raw-<engine>.json` of runs 39453181962, 39471466367, 39457063232 (apple, playwright-webkit,
  chromium): table per artifact and width in `docs/team/tools/trajectory-probe.md` Limits. MEASURED recovery error up to
  0.64 level (outside `chanErr`); tuple range L 0.234 to 1.0, a -0.004 to 0, b -0.019 to 0 (the task text said L 0.30 to
  1.0, within 0.016; one 39457063232 playwright-webkit tuple is `[234,-4,-19,212479]`, so the doc states the measured range).

## New against base after normalisation (`*`)
- 39471466367 chromium (waapi): nav close@0* at 390, 640, 641, 1280. 39453181962 apple: nav 640, 1280 close-hold@0*.
- 39457063232 chromium: nav 1280 close@0*. 39457063232 playwright-webkit: nav 390 close-hold@0*, nav 1280 close@0*, logo 390 close@0*.
- Other new units not at the start of the close: listed in the doc after the table.
## Open
- The close@0 / close-hold@0 units are a timing case (INFERRED): follow-up `trajectory-close-start`.
- `lab`, `lch` checked against the CSS Color 4 formula only. The re-reduction script is scratch, not committed.
Read first: `docs/team/tools/trajectory-probe.md` (Limits), `lean/Fw/Gate/Colour.lean` header.

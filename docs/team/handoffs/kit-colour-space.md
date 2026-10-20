# kit-colour-space handoff

Branch `worktree-wf_e1d953e4-5eb-2`. State: done (round 3, text only), nothing pushed to `ci/*`, no CI dispatch.
## What changed
- `packages/gate-breakpoints/src/trajectory/kit.mjs`: `colour` reads rgb/rgba, hsl, color(srgb), oklab, oklch, lab, lch as
  sRGB x1000 plus alpha x255x1000 (unclamped). `colourFromV1` (offline only) reads the old oklab-shaped tuples back.
- `lean/Fw/Gate/Colour.lean`: engine citations, error budget (`chanErr` 500, `alphaErr` 1000), `budget_inside_tol`
  (channels 1000 of 2000, alpha 2000 of 2000), `judge_colour_same_truth`; generator `lean/scripts/ColourGolden.lean`.
  Lean proves the conditional; the kit staying in the budget is MEASURED by `test/kit-colour.test.mjs`. Golden
  `packages/contracts/golden/gate/trajectory-colour.jsonl` (27 lines).
- Writes outside the task list (lead-approved): `lean/Fw.lean`, `lean/scripts/check.sh`, `lean/Fw/Ci/Trigger.lean`,
  `lean/scripts/ColourGolden.lean`, `golden/ci/triggers.jsonl`.

## Verified
- `sh lean/scripts/check.sh`, gate-breakpoints `pnpm test`, `scripts/ci-paths.test.mjs`, apps/runner `land-inputs.test.ts`.
- Limits table in `docs/team/tools/trajectory-probe.md`: 36 cells = 9 whole-run artifacts x 4 widths, re-reduced from each raw
  file: (a) not measured 12, (b) measured with no colour unit 3, (c) unit lists 21. Not measured (0 morph runs, 0 colour
  reads): 39453181962 playwright-webkit, 39471466367 playwright-webkit, 39457063232 apple. Leg artifacts: identity sentence.
- MEASURED recovery error up to 0.64 level (outside `chanErr`); tuple range L 0.234 to 1.0, a -0.004 to 0, b -0.019 to 0
  (not the round 1 review's proposed L 0.30 to 1.0, within 0.016; one 39457063232 playwright-webkit tuple is `[234,-4,-19,212479]`).

## New against base after normalisation (`*`, same as the table's after lists; nav and logo unless noted)
- 39453181962: apple 640 nav close-hold@0, 1280 open@3,5 and nav close-hold@0; playwright-webkit not measured; chromium 641 open@1.
- 39471466367: apple open@3 (390, 641), open@2 (1280), close@7 (640); playwright-webkit not measured; chromium nav close@0 at
  390, 640, 641, 1280 (waapi run) and open@2 at 641.
- 39457063232: apple not measured; playwright-webkit 390 logo open@10 and close@0, nav close-hold@0; 640 close@3; 1280 nav
  close@0; chromium 1280 nav close@0.
## Open
- The close@0 / close-hold@0 units are a timing case (INFERRED): follow-up `trajectory-close-start`.
- `lab`, `lch` checked against the CSS Color 4 formula only; the re-reduction script is scratch. Read first: `docs/team/tools/trajectory-probe.md` (Limits), `lean/Fw/Gate/Colour.lean` header.

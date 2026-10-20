# kit-colour-space handoff

Branch `worktree-wf_e1d953e4-5eb-2`. State: done, nothing pushed to `ci/*`, no CI dispatch.

## What changed
- `packages/gate-breakpoints/src/trajectory/kit.mjs`: `colour` reads rgb/rgba, hsl, color(srgb), oklab, oklch, lab, lch as
  sRGB x1000 plus alpha x255x1000 (unclamped); other strings stay strings. `colourFromV1` (offline only) reads the old
  oklab-shaped tuples of the stored raw files back.
- `lean/Fw/Gate/Colour.lean`: engine citations (WebKit ColorSerialization/ColorConversion, Chromium color.cc,
  color_conversions.cc), the error budget (`chanErr` 500, `alphaErr` 1000), `budget_inside_tol` (2 x budget <= `tol .colour`
  2000, so the judge is unchanged), `judge_colour_same_truth`, and the golden generator (`lean/scripts/ColourGolden.lean`).
- `packages/contracts/golden/gate/trajectory-colour.jsonl` (generated, 27 lines); test `test/kit-colour.test.mjs` (10 tests).
- Writes outside the task list: `lean/Fw.lean` (import), `lean/scripts/check.sh` (golden check job),
  `lean/Fw/Ci/Trigger.lean` (the golden is an input of the lean.yml and trajectory-probe.yml rows) and the regenerated
  `packages/contracts/golden/ci/triggers.jsonl`.

## Verified
- `sh lean/scripts/check.sh` green; gate-breakpoints `pnpm test` 385 pass; `node --test scripts/ci-paths.test.mjs` 49 pass;
  apps/runner `land-inputs.test.ts` 55 pass.
- Re-reduction of runs 39453181962, 39471466367, 39457063232 (stored raw has numeric tuples, not colour strings):
  table in `docs/team/tools/trajectory-probe.md` Limits.

## Open
- Remaining `close@0` / `close-hold@0` nav.background-color units are real 7 to 8 level channel differences at the start of
  the close (interrupted-transition start, INFERRED). New against base: mac 640 and 1280 close-hold@0, Chromium 1280 close@0.
- `lab`, `lch` conversion checked against the CSS Color 4 formula only, no device.
- The recovery of old tuples is a heuristic (limits in the `colourFromV1` comment). A new probe run stores sRGB tuples through the
  new kit, so no recovery is needed there.

Read first: `docs/team/tools/trajectory-probe.md` (Limits), `lean/Fw/Gate/Colour.lean` header.

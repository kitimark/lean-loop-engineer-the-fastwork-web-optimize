# layer-sweep-review: sweep strips for the look decision of platform.sweep:layer-sweep

Task layer-sweep-review (graph r620). The flag `platform.sweep:layer-sweep` is class L (look can change mid-animation). The user decides
Keep or Reject from a console Reviews card; this note records how the card gets its pictures and numbers.

## What was built
- CONFIRMED (code): `packages/premise-tests/src/sweep-strips.mjs` + `png.mjs` render faithful vs layer for four words (Document, Earn,
  Secure, Organized) at widths 390 and 1440, at loop progress 0, frames 1 and 2 (16667 us, 33333 us), 0.5 s and 2 s; each word is cropped,
  zoomed 4x, with a per-pixel heat map row (0 black, 1-2 blue, 3-8 green, 9-32 yellow, over 32 red). Output `strips/<engine>-<w>-sweep-<moment>.png` + `strips/index.json`.
- CONFIRMED (workflow): step in `.github/workflows/visual-diff.yml` shoot job, shard s0, push, tip message has `[strips:layer-sweep]`;
  artifacts `sweep-strips-chromium` and `sweep-strips-playwright-webkit`, retention 30 days. premise-tests is a seeder lane, so the
  push hook refuses it alone; the step lives in visual-diff.
- Lean: `Fw.Console.ReviewStrips` key generalised to `Moment` (nav push | sweep moment), 20 sweep rows, golden rows in console/review.jsonl;
  `Fw.Preset.Gen.lookDecisions` last row; `Fw.Console.Review.ask`; wire fields `moment`, `label`, `ask`.

## Numbers (MEASURED, CI run 41261936045, ci/layer-sweep-review, Chromium 156.0.8078.4 and Playwright WebKit 27.2)
Max colour difference (of 255) / differing pixels over four words, per width.

| moment | Chromium 390 | Chromium 1440 | WebKit 390 | WebKit 1440 |
|---|---|---|---|---|
| progress 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| frame 1 | 1 / 4 | 1 / 1 | 1 / 6 | 1 / 2 |
| frame 2 | 3 / 36 | 3 / 62 | 5 / 47 | 2 / 60 |
| 0.5 s | 5 / 1043 | 5 / 1591 | 3 / 619 | 8 / 1443 |
| 2 s | 4 / 2783 | 3 / 4204 | 1 / 302 | 1 / 651 |

The colour differs by at most 5 of 255 in Chromium and 8 of 255 in WebKit.

## Limits
- MEASURED: the strips come from a harness page built from the site's sweep CSS declarations and the snapshot font at dpr 1, not from the built site.
- MEASURED: this run found no difference at progress 0; the earlier run 40336086853 found nine differing pixels in one Chromium edge column, three of them by 33 of 255. Not reproduced.
- A local Chrome 155 debug run was used only to debug the harness; it is not a result.
- Expiry 2026-12-01 is INFERRED (30 days after the run); `gh api` is denied here, so it was not read.
- The flag-side cost numbers on the card (about 100 vs about 200 style recalcs per 100 frames) are from the iOS Simulator runs 41212638765,
  41215962130, 41219277317 (research/notes/2026/10-31-sim-layer-sweep.md).

## Open
- The user's Keep or Reject is pending. No preset or flag change is made here.
- `research/findings/ledger.json` got a `userDecision` on the layer-sweep row (needed by `ledgerDisagreements`).
- Card numbers are hard-coded in Lean (`sweepStat`) from index.json.

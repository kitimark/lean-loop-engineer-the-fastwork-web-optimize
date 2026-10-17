# visual-diff: pixel diff of the original against the rewrite

What the breakpoint gate cannot see (a fallback font drawing other glyphs, stacking order, paint) shows up here. For each
part, at each probe (a breakpoint environment of the gate's Lean matrix), the part's box is screenshotted in the original
snapshot and in the rewrite, compared with pixelmatch, and judged by a Lean rule.

## Pieces
| Piece | Path |
|---|---|
| Verdict rule, theorems, golden generator | `lean/Fw/Gate/Pixel.lean` |
| Golden vectors (22 cases) | `packages/contracts/golden/gate/pixel.jsonl` |
| TS verdict (checked against the golden) | `packages/visual-diff/src/verdict.mjs` |
| Pixel counts (pixelmatch 8, `threshold 0.1`, `includeAA false`) | `packages/visual-diff/src/diff.mjs` |
| Runner, CLI, report | `src/run.mjs`, `src/cli.mjs`, `src/report.mjs`, `src/shards.mjs` |
| Per-part tolerances | `packages/visual-diff/tolerances.json` (default `ppm 2000, delta 64, countAA false`) |
| Probe set | `packages/visual-diff/probes.default.json` (8 probes of the gate matrix) |
| CI | `.github/workflows/visual-diff.yml` |

## Verdict (Lean, `Fw.Gate.Pixel`)
Input: `Stats` (changed, antialias-only, total, max channel delta, max delta of the AA pixels, `settled`) and a `Tol`
(ppm, delta, countAA). Output: `pass | fail | unsettled`.
- `unsettled` when `settled = false` (never a pass); `fail` when the canvas is empty or outside the tolerance; else `pass`.
- Theorems: `pixel_verdict_total`, `unsettled_never_pass`, `tolerance_monotone`, `identical_pass` (statements as LaTeX in
  the docstrings).
- Size mismatch: the total is the larger canvas; the outside strip counts as changed with delta 255. One arm absent while the
  other is present is a full change. Both arms absent gives status `nc` (a small TS rule outside Lean; a TS stand-in).

## Settled
Each arm is screenshotted twice 200 ms apart; the arm is settled when the two are pixel-identical. Animations are never
seeked (native requestAnimationFrame): an endless animation gives `unsettled`, not a false fail or pass.

## Cropping and preparation
- Crop = the part's first role selector in the gate's `anchors.json` (`roles[0]`), scrolled to the viewport top and clipped
  to the visible box. Overlay and mount parts are prepared as the gate does (`prepareInPage`).
- Parts whose first role is the document (`engine.scroll`, `morph.tween`) are skipped unless named in `--parts`.
- The gate's `page.mjs`, `serve.mjs`, `spec.mjs`, `anchors.json` are imported read-only, with the same readiness wait.

## Run
- Locally (debug only, never a result): `node src/cli.mjs run --engine chromium --probes desk-1512 --parts nav --out DIR`
  with `FW_SNAPSHOT_SITE`, `FW_SITE_DIST` set; `node src/cli.mjs report --in DIR`.
- CI: `gh workflow run visual-diff --ref ci/<task>` or push a `ci/*` branch. Inputs: `engines`, `shards`, `probes`,
  `parts`, `fw` (flag set of the rewrite arm, becomes `?fw=...`). Free arm64 runners; browsers by the gate-engine action.
- Artifacts: `vd-<engine>-<shard>` (counts, verdicts and orig/rewrite/diff PNGs of every cell that is not a pass),
  `visual-diff-report` (merged table, md and json). Images are CI artifacts only; nothing is committed.
- Tolerance per part: add `{ "parts": { "<id>": { "ppm": ..., "delta": ... } } }` to `tolerances.json`.

## Caveats
- The Linux Playwright WebKit is a WebKitGTK/WPE port, not Mobile Safari; the numbers say nothing about iOS paint.
- Image-load timing and webfont swap can differ between arms; the settle check only guards against motion.

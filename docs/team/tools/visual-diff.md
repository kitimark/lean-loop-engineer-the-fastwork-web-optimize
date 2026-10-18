# visual-diff: pixel diff of the original against the rewrite

What the breakpoint gate cannot see (a fallback font drawing other glyphs, stacking order, paint) shows up here. For each
part, at each probe (a breakpoint environment of the gate's Lean matrix), the part's box is screenshotted in the original
snapshot and in the rewrite, compared with pixelmatch, and judged by a Lean rule.

## Pieces
| Piece | Path |
|---|---|
| Verdict rule, theorems, golden generator | `lean/Fw/Gate/Pixel.lean` |
| Golden vectors (34 verdict cases; 32 asset, image, font and settle cases) | `packages/contracts/golden/gate/pixel.jsonl`, `pixel-assets.jsonl` |
| TS verdict and asset twins (checked against the golden) | `src/verdict.mjs`, `src/assets.mjs` |
| Settle predicate adapter (gate-settle copy until it lands) | `src/settle-adapter.mjs` |
| In-page functions, asset server and font injection | `src/page.mjs`, `src/serve.mjs` |
| Pixel counts (pixelmatch 8, `threshold 0.1`, `includeAA false`) | `packages/visual-diff/src/diff.mjs` |
| Runner, CLI, report | `src/run.mjs`, `src/cli.mjs`, `src/report.mjs`, `src/shards.mjs` |
| Per-part tolerances | `packages/visual-diff/tolerances.json` (default `ppm 2000, delta 64, countAA false`) |
| Probe set | `packages/visual-diff/probes.default.json` (8 probes of the gate matrix) |
| CI | `.github/workflows/visual-diff.yml` |

## Verdict (Lean, `Fw.Gate.Pixel`)
Input: `Stats` (changed, antialias-only, total, max channel delta, max delta of the AA pixels, `settled`, `present`,
`fontsLoaded`, `imagesLoaded`) and a `Tol` (ppm, delta, countAA). Output: `pass | fail | unsettled | invalid | nc`, decided in
this order: nothing present in either arm is `nc`; fonts or images not loaded is `invalid`; not settled is `unsettled`;
else an empty canvas or a count outside the tolerance is `fail`; else `pass`.
- `invalid` is never `fail` and a pass or fail needs both premises: `no_verdict_without_assets`, `unloaded_is_invalid`,
  `unloaded_never_fail` (LaTeX statements in the docstrings). Other theorems: `pixel_verdict_total`, `unsettled_never_pass`,
  `tolerance_monotone`, `identical_pass`, `aa_mask_ignores_aa`.
- Asset premise: `imagesLoaded` is every `img` complete with a non-zero natural size; `fontsLoaded` is no face loading or
  in error and every used first-listed family that has a declared face has a loaded one (`document.fonts`). Computed in the
  page (`page.mjs`), decided by the Lean twins in `assets.mjs`.
- Size mismatch: the total is the larger canvas; the outside strip counts as changed with delta 255. One arm absent while the
  other is present is a full change. Both arms absent is `nc`, now a Lean outcome (the old TS rule is gone).

## Assets
Both arms must draw the snapshot's real fonts (Google Sans, Playpen Sans) and images, or the cell is `invalid`. The original
loads them itself. The rewrite arm is served by an overlay server (`serve.mjs`): its `dist`, and for a missing media file
(png, jpg, svg, woff2, ttf, mp4, ...) the snapshot file at the same URL, never HTML, JS or CSS. The `@font-face` rules are
read from the snapshot CSS and injected with a `font-family` override (the port has no font-face of its own; this
is a harness stand-in and is recorded in the report header, `assets`). `--assets none` turns it off. The page waits up to 10 s
for faces and images before the shot.

## Settled
An arm is settled when both hold: the gate's settled-sample predicate (`settled p o = running = 0 and minFrames <= frames
and minStable <= stable and not hoverInside`, from gate-settle, `Fw.Gate.Settle`), observed by an in-page copy over a 15 s
budget; and pixel calm, two shots 200 ms apart that are identical or differ only within the part's own tolerance. The
gate-settle branch has not landed on main, so `settle-adapter.mjs` carries verbatim twins of its predicate and wait; when it
lands, replace them by an import from `gate-breakpoints/src/settle.mjs` and replay its `settle.jsonl`. Animations are never
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
- The font override makes every rewrite glyph Google Sans, so regions set in Playpen Sans or Fastwork Bold can fail for a
  harness reason, not a port reason.

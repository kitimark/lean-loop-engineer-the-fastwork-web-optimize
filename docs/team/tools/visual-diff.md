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
| In-page functions; asset server and font injection (diagnostic `--assets inject` only) | `src/page.mjs`, `src/serve.mjs` |
| Port check 5 (fonts) in the browser | `src/fonts.mjs`; twin `scripts/port/fonts.mjs`; Lean `lean/Fw/Port/Fonts.lean` |
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
The default mode is `--assets none`: the rewrite arm is the port as built, served from its `dist` with its own fonts, images
and assets; a missing file is a 404 and shows as a broken asset. The cell is `invalid` when a face or image the arm needs has
not loaded. `--assets inject` (workflow input `assets`) is a named diagnostic only: an overlay server (`serve.mjs`) answers a
missing media file of the rewrite with the snapshot file at the same URL, and the original's `@font-face` rules are injected
with a forced `font-family`, which hides any font regression of the port; the report header (`assets`) records the mode. The
page waits up to 10 s for faces and images before the shot.

## Port check 5 (fonts)
`node src/cli.mjs fonts --engine <e> [--probes ids] --out DIR` (job `port-fonts`) loads both arms at each probe and reads, in
the page (`scripts/port/fonts.mjs` `fontsInPage`), every text leaf with the computed first font family, weight and style of its
element, owned by the innermost section row of `Fw.Port.Sections` that matches (else `page`), and every `FontFace` of
`document.fonts`. Lean `Fw.Port.Fonts` decides: the leaf units (section, normalised text, family, weight, style) must be equal
as multisets (text blanked in a section whose text is excluded, the countdowns) and the loaded (family, weight, style) faces
equal as sets, minus the excluded `Fastwork` family. Twin and golden: `scripts/port/fonts.mjs`,
`packages/contracts/golden/port/fonts.jsonl`, `apps/site/test/port-fonts.test.mjs` (with `FW_PORT_FONTS_ENGINE` it also loads a
port page whose `pain.notes` falls back to Google Sans and expects a fail). The built-page step is advisory
(`continue-on-error`), like checks 3 and 4. Output `<engine>.fonts.json` in artifact `port-fonts-<engine>`.

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
- With the port as built, a region the port draws in another font, or with a missing image, fails for a port reason; use
  `--assets inject` to separate the two when diagnosing.

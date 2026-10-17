# lean/Fw/Site: the breakpoint layer, Lean first

Source of truth: `research/kickoff/11-breakpoints/README.md` and `breakpoints.json` (schema `fw.breakpoints/1`).
Lean states every media condition, proves its edges, its overlaps and the gaps, builds the gate matrix, and generates
`breakpoints.gen.json`. The site and the breakpoint gate read only that generated file.

## Modules

| Module | Content |
|---|---|
| `Breakpoints` | `Px` (exact non-negative rational CSS px), `Env` (width, height, device width/height, DPR, hover, pointer, reduced motion, colour scheme, media type, forced colors), the media-query syntax `MQ` (an OR of ANDs), the evaluator, the CSS and legacy printers, the 30 conditions (`catalogue`, inventory ids and TS ids), and the edge-sufficiency theorems |
| `BreakpointFacts` | `*_iff`: each of the 30 conditions as plain mathematics; the byte-exact CSS table; the edge table; nested combos; the overlaps; the JS desktop-deck gate; the fractional gaps |
| `BreakpointMatrix` | the 124-load matrix (per engine), block counts, edge coverage, flip observation, and the MUI-internal neutral set |
| `BreakpointGen` | `genJson` (the document), `checkInventory` (field-by-field check against `breakpoints.json`), `run` (CLI driver), `opBreakpointsGen` (the same as an fwcore op body) |
| `breakpoints.gen.json` | generated; do not edit |

## Main results (all proved; `lake exe mathview --lint` passes; standard axioms only)

| Claim | Theorem |
|---|---|
| A condition changes value only across its own edges (rational widths, two cuts per edge) | `MQ.eval_congr` |
| At whole-pixel widths, testing `N` and `N+1` at each edge sees every change | `MQ.eval_ofNat_congr`, `MQ.eval_const_on_band` |
| Height, device height and DPR change no condition | `MQ.eval_indep_height_dpr` |
| The printed CSS equals the inventory's `condition`, byte for byte, for all 30 | `catalogue_css` (and `checkInventory` against the file) |
| The edges read off the syntax equal the inventory's `edges` | `catalogue_edges`, `catalogue_axis_edges` |
| C860 and `>=861` overlap exactly when the width is at least 861 and either the screen is at most 500 or the input is touch at up to 1200 | `overlap_c860_wGe861` (also `overlap_c1000_wGe1001`, `overlap_c1000_wGe1001Nopref`) |
| Pure 860 is not C860 | `c860_not_wLe860` |
| The JS desktop deck is off on touch tablets and small screens | `deskDeck_iff`, `touchTablet_overlap`, `smallScreen_overlap` |
| The four fractional gaps are real, and integer probes never land in them | `gap_iff`, `no_gap_ofNat`, `gap600`, `gap640`, `gap860`, `gap1000` |
| 124 loads, per-block counts as in `matrix.estimate` | `matrix_length`, `matrix_blocks` |
| Both sides of every edge in every required profile | `matrix_edge_pairs`, `matrix_pairs_agree` |
| For every condition and every edge it lists, the matrix contains a pair at `N` and `N+1` that flips it | `matrix_observes_every_edge` |
| `print` and `(forced-colors: active)` are false on every gate load | `matrix_neutral_inert` |
| `(hover: hover)` and `(hover: none)` are the inventory's hover conditions, and the cross block runs both sides | `matrix_neutral_hover_both_sides` |

## Findings against the inventory (proved here; corrected in the inventory README and JSON)

- **Phone landscape is not in the C1000 / `>=1001` overlap.** Its width is 932, which is below 1001, so C1000
  matches and `>=1001` does not (`matrix_landscape_overlaps`). `phone-landscape.why` claims both overlaps. The
  C1000 overlap is covered by `touch` at 1031 and 1200 and by `dw-arm-isolate`.
- **"No combo may match" in hover-pointer-cross holds at 1200 px but not at 1024 px.** At 1024, `c1030` matches by
  its width arm. No touch arm matches in that block (`matrix_cross_no_touch_arm`).
- **At viewport 1001, `dw-arm-isolate` does not flip `c1030`.** `c1030` already holds by width there. It does flip
  at 1031 and 1201 (`matrix_dw_arm`).

## Modelling choices (INFERRED where the inventory is silent)

- Device width equals viewport width in the `desk`, `touch` and `hover-pointer-cross` profiles. This follows the
  inventory's `deviceWidth: "= viewport width"`.
- `dark-1440x900` uses desktop inputs at DPR 1. `dark-430x932` uses touch inputs at DPR 3.
- The `height-probes` loads at 1440 use desktop inputs at DPR 1. The loads at 430 use touch inputs at DPR 3 on a
  430×932 screen.
- The fractional probes use desktop inputs at DPR 1.25 and height 900, with device width equal to the fractional width.
- The test matrix contains no `print` or forced-colors environment. Every load is `screen` with forced colors `none`.

## Generating `breakpoints.gen.json`

`lake exe breakgen` (root `lean/BreakgenMain.lean`, which calls `Fw.Site.BreakpointGen.run`) prints the document on
stdout:

```sh
cd lean
lake exe breakgen > Fw/Site/breakpoints.gen.json
lake exe breakgen --inventory ../research/kickoff/11-breakpoints/breakpoints.json --check Fw/Site/breakpoints.gen.json
```

- `--check <file>` exits 1 when the file's bytes differ from the generated text.
- `--inventory <path>` first checks the catalogue and the matrix against `breakpoints.json`, field by field, with CSS
  strings compared byte for byte. It exits 1 on any mismatch.

The same document is available as the fwcore op `breakpoints.gen`. The request is `{"op":"breakpoints.gen"}`, with
an optional `"inventory": <breakpoints.json object>`. The reply is `{gen, mismatches}`.

## `breakpoints.gen.json` layout

- `conditions[]`: `id`, `tsId`, `css` (range syntax, byte-equal to the inventory), `legacyCss` (`max-`/`min-` form,
  or `null` for `>N`), `kind`, `features`, `edges[{feature, pair}]`, `edgesPx`.
- `edgePairs`: `width` (15 pairs), `deviceWidth` (`[[500,501]]`), `touchRm` (5 pairs).
- `fractionalGaps[]`: `lower`, `upper`, `open`, `probe`.
- `neutral[]`: `tsId`, `css`, `reason`, `inventoryId`. These are the MUI-internal media of
  `apps/site/src/mui-internal-media.json`.
- `matrix`: `loadsPerEngine` (124), `engines`, `blocks[{id, loads}]`, and `probes[]`. Each probe has `id`, `block`,
  `width`, `height`, `deviceWidth`, `deviceHeight`, `dpr`, `hover`, `pointer`, `reducedMotion`, `colorScheme`,
  `mediaType` and `forcedColors`.
  - `expect` gives the value of each of the 30 conditions by `tsId`.
  - `expectNeutral` gives the value of each neutral query.
  - Together they are golden vectors for `matchMedia`.
- `backingTheorems`: the theorem names the file relies on.

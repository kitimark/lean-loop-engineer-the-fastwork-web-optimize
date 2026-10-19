# Wave-1 integration: gate on both engines, counts re-measured on the content-filled page

Status: MEASURED on GitHub CI at main 4283c5a1 (branch `ci/integrate-wave-1`, all dispatches from that one commit). Verdicts are Lean's
(gate `Fw.Gate.Exit`, faithful `Fw.Faithful` via fwcore). No Mac measurement. Educational study of the public fastwork.com homepage, not affiliated with Fastwork.

## Runs

| what | run | result |
|---|---|---|
| gate, default arm, both engines | 39184687325 | Chromium pass, WebKit incomplete (below) |
| gate, v2-proved arm | 39185920522 | not run: every job died at start (below) |
| counts swipe-v1, target both | 39184638066, 39186469962, 39186477379 | 3 workflow runs x (3 original + 3 rewrite shards), separate VMs |
| counts swipe-touch-v1, target both | 39184646781, 39186485136, 39187013275 | same |

All six counts runs reused the image of the frozen table (`image_run=39049264131`, `sha256:8f0e17f5...`). Counts wall 3.7 to 15.8 min (one waited for
runners behind the gate), gate 16 min. fixture-rest was not needed: the refreeze procedure (`packages/measure-chromium/README.md`, refreeze section) is 3 workflow runs per
profile for the class table plus one run's 3 shards per arm for the per-zone baselines.

## Gate, default arm (run 39184687325, 9 jobs, 124 loads and 4 sweeps per engine)

| engine | verdict | readings | pass | excused | bad | universe | unsettled |
|---|---|---|---|---|---|---|---|
| Chromium | pass | 7056 | 7049 | 7 | 0 | identical | 0 |
| WebKit (Playwright, Linux) | incomplete | 7056 | 6763 | 291 | 2 | identical | 0 |

- Main's last gate (39142015714): Chromium pass, 6992 pass, 64 excused, 0 bad; WebKit incomplete, 291 excused, 2 bad. No new failing cell on either engine.
- Chromium excused went 64 to 7. The 57 excused commission/commission.typing/pain live-resize readings (`Fw.Gate.Exit` `commissionResizeStops`) now all read
  pass (57 of 57 in each of commission, commission.typing, pain on the desktop-1512-320-1512 sweep; 5 of 5 on the other three sweeps). The remaining 7 are
  matchMedia =Lean not-comparable (4 fractional, 3 touch-1024). FINDING: the four `commissionResizeStops`/`resizeExemption` entries are now unused; their own
  note says to drop them when the port is faithful under live resize (lead, Lean change in `Fw.Gate.Exit`, not done here).
- WebKit bad cells: `matchMedia =Lean | sweep:phone-rotation | phone-rotation#1` and `#3`, not-comparable; the same two cells as main's gate (pre-existing). Excused 291:
  144 whole-width fractional, 144 primary-pair cross, 3 touch-1024.
- Part of every failing item: none (the failing-items list of both engines is empty).

## Gate, v2-proved arm (run 39185920522): blocked, no verdict

The workflow turns the `fw` input into `FW_SEARCH=?fw=<input>`. The site build prerenders `?preset=v2-proved` and one `?fw=` key per single flag, but no `?fw=` key for the
eight-flag set, and `?fw=preset:v2-proved` does not resolve (preset-v2-proved handoff). I passed the eight flags of `apps/site/src/registry/presets/v2-proved.json`
comma separated; all 7 gate jobs stopped in the smoke step with `FW_SEARCH "?fw=engine.scene:hidden-pause,..." is not prerendered` (`serve.mjs:47`), after 1 min, 0 readings.
Not retried: the input cannot name the preset. Fix is a workflow change (outside this task's writes and not main's commit): a `preset` input that sets `FW_SEARCH=?preset=<name>`
(one line in the two `FW_SEARCH` env entries), or a prerendered `?fw=` key of the eight flags. Until then the combined arm is gated only flag by flag (the single-flag keys exist).

## Counts, content-filled page

The rewrite R now shows real pictures; the original A is unchanged. Whole-run base (median of 3 shards), run 1 of each profile:

| profile | type | A (frozen) | A' (this run) | R before (faithful rerun, 39146329183 / 39146332555) | R now |
|---|---|---|---|---|---|
| swipe-v1 | trace.PaintImage | 687 | 687 | 388 | 757 |
| swipe-v1 | trace.DecodeImage | 27 | 27 | 2 | 30 |
| swipe-v1 | trace.ImageDecodeTask | 238 | 238 | 50 | 408 |
| swipe-v1 | trace.ParseHTML | 35 | 35 | not emitted | 17 |
| swipe-touch-v1 | trace.PaintImage | 1348 | 1347 | 610 | 1600 |
| swipe-touch-v1 | trace.DecodeImage | 39 | 39 | 2 | 40 |
| swipe-touch-v1 | trace.ImageDecodeTask | 638 | 641 | 52 | 827 |

- As expected PaintImage and DecodeImage rise (PaintImage x2.0 / x2.6, DecodeImage x15 / x20). R now decodes more image tasks than A (408 vs 238, 827 vs 638) at about the same
  PaintImage and DecodeImage: INFERRED to be decode tasks for pictures A defers or decodes once; not diagnosed.
- New R types: `trace.ParseHTML` (17, an SVG document parse), `trace.N1.svgImageDocument` (0 to 17); `trace.ResourceSendRequest` 29 to 45 (A 44).
- Layout shape: frames 503 and 531 (same as before and as A), zones 12 and 13. `metric.LayoutObjects` 82 to 506 (A 255), `metric.Nodes` 134 to 649 (A 635 to 659).
- Other whole-run moves above 10 %: `raster.invalidatedLayers` +50 % (swipe-v1), `raster.invalidationRects` +44 %, `census.drawingAreaPx` -16 %, `trace.EventDispatch` +16 %.
- The control A' equals A within the frozen bands on both profiles (class table of A: 32/28/10 and 23/32/15 det/stable/quarantined).
- The committed `results/baselines/chromium/*/rewrite.*` are the early rewrite (385 and 409 frames, 9 and 10 zones, no image types) and are untouched: the new R does not satisfy their test
  invariants (`fwcore.test.mjs`: detDrift empty, 0 unlisted) under the old class table (R tally det/stable/quar/unlisted 44/7/1/18 and 50/1/0/19, detDrift 44 and 72 cells).

### Class table refreeze (6 runs, `src/freeze.mjs`, accepted by Lean, built-by 39049264131)

| profile | arm | before det/stable/quar (types) | now det/stable/quar (types) |
|---|---|---|---|
| swipe-v1 | A | 32/28/10 (70) | 33/27/10 (70) |
| swipe-v1 | R | 44/7/1 (52) | 30/22/18 (70) |
| swipe-touch-v1 | A | 23/32/15 (70) | 24/35/11 (70) |
| swipe-touch-v1 | R | 50/1/0 (51) | 27/26/17 (70) |

- A moves by one to four types (one stable to deterministic; touch four quarantined to stable): noise of the class rule, not a page change.
- R: 14 (swipe-v1) and 17 (touch) types go deterministic to stable (the census family, `metric.LayoutCount`, `trace.HitTest`, `trace.PrePaint`, `trace.UpdateLayer`); 8 and 13 go deterministic to
  quarantined: `trace.RequestAnimationFrame`, `trace.FireAnimationFrame`, `trace.EventDispatch`, `trace.FunctionCall`, `trace.DisplayItemListRaster`, `trace.RasterTask`,
  `metric.Nodes`, `metric.LayoutObjects`, `metric.JSEventListeners`, `trace.UpdateLayoutTree.elementCount` (touch also `raster.invalidated*`). 18 and 19 types are new to the table
  (`trace.PaintImage` stable, `trace.ImageDecodeTask` stable, `trace.DecodeImage` deterministic, `trace.Layout*` quarantined or stable, `trace.ParseHTML` deterministic).
  This is the "rewrite less deterministic than A" of the faithful rerun, now with a class: the page animation and event work of R varies per VM (INFERRED, not diagnosed).
- Under the proposed table the new R baselines have detDrift 0 and 0 unlisted (in-sample: the baseline shards are 3 of the 9 the table was frozen from).
- The proposed table is `results/refreeze-wave-1/classes.proposed.json` (byte-for-byte `freeze.mjs` output, not yet `packages/measure-chromium/classes.frozen.json`, outside this task's writes).
  Per-zone baselines under it: `results/refreeze-wave-1/<profile>/rewrite.{zones,baseline}.json`. Adopting it makes the model-bug-fixes rows re-judge against the new R classes (wave 2).

## Faithful verdict on the new runs (Lean `faithful.verdict`, region zones y04000, y04500, tail)

A is the frozen original baseline, R and the control A' are run 1 of each profile (3 shards each, median). `faithful.comparable` accepted all pairs (430x932, scrollWidth 430).

| profile | zone | shape A / R (frames, px) | off-band cells now (before) | verdict |
|---|---|---|---|---|
| swipe-v1 | y04000 | 50, 500 / 50, 500 | 27 of 44 (26) | FAIL |
| swipe-v1 | y04500 | 14, 136 / 14, 136 | 14 of 43 (14) | FAIL |
| swipe-v1 | tail | 30, 0 / 30, 0 | 15 of 38 (14) | FAIL |
| swipe-touch-v1 | y04000 | 50, 500 / 50, 500 | 26 of 40 (26) | FAIL |
| swipe-touch-v1 | y04500 | 13, 129 / 13, 129 | 14 of 41 (15) | FAIL |
| swipe-touch-v1 | tail | 30, 0 / 30, 0 | 10 of 41 (15) | FAIL |

Control A'/A passes all zones on both profiles (0 failing cells). The refusal path (`NO DATA`, `not comparable`) did not trigger. No zone is a named refusal; all six are Lean FAIL.

- Unchanged causes (cells, A vs R, swipe-v1 y04000): layout work only R does (`metric.LayoutCount` 0 vs 24, `trace.Layout` 0 vs 24, `Layout.totalObjects` 0 vs 1340, `RecalcStyleCount` 152 vs 175),
  fewer animation-frame callbacks (`trace.RequestAnimationFrame` 204 vs 154; 175 vs 131 on touch), the census family, `raster.invalidationRects` 571 vs 197.
- Newly failing: `raster.invalidatedLayers` (swipe-v1 all three zones, touch y04000) and `raster.invalidationAreaPx` (swipe-v1 y04000, 1.13e6 vs 1.24e6): the added pictures change raster
  invalidation (INFERRED). New image cells: `trace.PaintImage` y04000 both profiles A 19 vs R 11 (fail).
- No longer failing: `trace.Layout.totalObjects` in swipe-v1 y04500 (50 vs 48 inside the band) and touch y04500; `trace.CullRectUpdate` in y04000.
- Touch tail improved most (15 to 10 off-band cells): the image cells now match, `PaintImage` 591 vs 583, `DecodeImage` 6 vs 6, `ImageDecodeTask` 367 vs 367 (last time R decoded none there).
  What remains there: `Layout.totalObjects` 21540 vs 46620 and `census.tilings`.
- Not gating: unbanded types (EventDispatch, FunctionCall, ResizeObserverNotify, HitTest on touch), and cells whose type the frozen A table has but R emits differently are scored by A's table only.
- Sensitivity not run: the verdict uses the frozen A table; the refreezed A table (above) would only tighten touch.

## New findings

| finding | part | evidence |
|---|---|---|
| R class table (52/51 types) was stale; R is quarantined on rAF/FireAnimationFrame/EventDispatch/FunctionCall and 8 to 13 more types | hero (rAF and countdown work), morph.* (INFERRED, not attributed: Chromium counts have no per-part dimension) | refreeze table above |
| v2-proved arm cannot be gated through `breakpoint-gate.yml` | gate workflow, preset registry | run 39185920522 |
| gate Exit entries for commission live resize are unused | commission, commission.typing, pain (port faithful now) | run 39184687325, 57 of 57 pass each |
| `raster.invalidatedLayers`/`invalidationAreaPx` newly off band after pictures | people / selling avatars and hero pictures (INFERRED from the content lanes) | verdict files |
| no new failing gate cell on either engine | none | run 39184687325 |

## Files

`results/faithful/runs/<profile>/*` and `results/faithful/<profile>.verdict.json` (regenerated from runs 39184638066 and 39184646781; the old run files stay in git history at c0d79175),
`results/refreeze-wave-1/**`. Stale after this: `lean/Fw/Faithful/Measured.lean` (`faithful.mjs lean --check` says DIFFERS: it still states the 39146329183/39146332555 numbers;
regenerate with `faithful.mjs lean`, outside this task's writes), and the faithful-rerun note's cell counts (that note is correct for its runs).

## Limits

Chromium counts only for the refreeze (WebKit counts lane not run); one gate per arm; gate has no per-part dimension for counts; R judged by the median of 3 shards; counts are work, not milliseconds.

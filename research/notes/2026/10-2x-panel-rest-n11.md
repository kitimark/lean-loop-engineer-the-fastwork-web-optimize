# panel-rest-n11: ledger row n 11 shipped as the flag `morph.panel:rest`

* The flag exists: the platform section drops `filter` (`blur(0px)` to `none`) while `--morph-fade` is 1 and keeps the same blur otherwise. CONFIRMED in code (`apps/site/src/parts/morph.panel/rest.logic.ts`, `morph.tween/driver.ts` `updateFade`, `platform.module.css` `.section[data-fw-rest]`).
* RG10 holds on the rewrite DOM. MEASURED (local debug run, Chromium, 10 widths 320 to 1440): 54 absolutely positioned descendants of the section and 0 fixed; every one has a positioned or transformed ancestor below the section, so none uses the section as its containing block. The section is `position: static`, `z-index: auto`.
* The scenes are not pixel-equal everywhere. MEASURED (Chromium, 70 viewport clips of the section at 9 widths, flag vs base; base vs base noise floor 0 to 77 px per clip): all clips are inside the noise except width 721, where three clips differ by 720 to 734 px, one full 721 px row at the section's fractional bottom edge (section top 4320.47, height 1482.16). INFERRED mechanism: the filter group is rastered into a snapped layer, so the edge row of a fractional box is covered differently. So `rest_visSame_E` needs a third premise (no fractional section edge), or the class is Q at that row. Follow-up, not a blocker: a Lean premise and a gate row for fractional edges.
* Verdict (MEASURED, four count runs, section "Per-engine verdict"): the flag stays a curated exclusion. Chromium is a trade, WebKit saves memory but its Paint rises in the finish zones, and the Lean rule cannot certify that type.

## Mechanism (CONFIRMED at the cited lines)
* Chromium@f842f52: `blur(0)` still appends a blur op (`third_party/blink/renderer/core/paint/filter_effect_builder.cc:465-470`); `NeedsFilter` is true for any layer with `HasFilter` (`core/paint/paint_property_tree_builder.cc:2629-2651`), so an effect node and a `SaveLayer` exist at rest.
* WebKit@862f17d: `hasFilter` is `!filter.isNone()` (`Source/WebCore/rendering/RenderElementStyleInlines.h:40`), so `blur(0)` keeps a group and a RenderLayer although nothing is painted.

## What was added in Lean (reuse of `Fw.Parts.MorphPanelOpt`)
`Fw.Parts.MorphPanelRest`: `kindOf` (the per-frame decision, `off` iff `filterV (fade r)` is empty), `kindOf_rest`, `kindOf_fade`, `kindOf_off_iff` (one theorem per branch), `toggles` (rest-fade flips of a run) with `toggles_cross`, `toggles_fade`, `toggles_rest`, `toggles_all_rest`, `toggles_all_fade`. Golden `packages/contracts/golden/parts/morph.panel.rest.jsonl` (17 rows) is replayed by `apps/site/src/parts/morph.panel/rest.golden.test.ts`; `morph.tween/rest.driver.test.ts` runs the real driver through rest, fade and back.

## Registration
`morph.panel:rest` is `optimized` in `part.json`; it conflicts with the WAAPI tween and the threaded fade (they own the fade write). `Fw.Preset.Gen` lists it as a curated exclusion (ledger n 11: Chromium trade) so v2-proved is unchanged; the decisions golden has the new row.

## Per-engine verdict (MEASURED)
Runs, all at `ab3b3248f` on `ci/panel-rest-n11`: WebKit Simulator base 40174475566 and flag 40174472900 (3 VMs, 2 passes each, so 6 passes per arm); Chromium swipe-touch-v1 base 40174480097 and flag 40174482844 (3 runs each, 771 frames). Gate 40179231272 passed on both engines (the earlier 40174477871 failed only on the intended `filter blur(0px) -> none`, which `Fw.Gate.FlagDelta` now excuses). Finish zones: Chromium frames 486-539 (y04500), 540-738 (y05000), 741-770 (tail), frames 486-770 (finish: y04500, y05000, tail and the two settle frames 739-740) and the whole run; WebKit 500 px zones z09 (4500-4999) and z10 (5000+). Method: the counts of each zone slice go to fwcore, `measure.classify` (kMax 4, tMax 24) per arm and zone gives the class, then `measure.engineCheck` judges `=o`, `<o` and `<=o` rows. A cell is WIN when `<o` passes (or `<=o` passes and `=o` is a model bug), COST when `<=o` is a model bug, equal when `=o` passes, otherwise unusable with the Lean reason.

### Chromium (Lean verdict per cell; counts are the sum of the zone's frames, flag vs base lower median of 3)
| type | y04500 | y05000 | tail | finish |
|---|---|---|---|---|
| trace.Paint | WIN 140 vs 186 (deterministic) | WIN(<=) 897 vs 911 | equal 60 | WIN(<=) 1101 vs 1161 |
| trace.PrePaint | unusable (inside noise) | COST 399 vs 373 | equal 30 | COST 629 vs 600 |
| trace.Layout.dirtyObjects | equal 135 | COST 624 vs 623 | unusable (quarantined) | COST 759 vs 758 |
| trace.Layout, metric.LayoutCount, trace.UpdateLayoutTree, trace.cc.Commit, trace.Layerize | equal | equal (UpdateLayoutTree unusable: inside noise) | equal | equal (same) |
| raster.invalidationAreaPx | equal | COST 140.2M vs 136.0M px | equal | COST 165.5M vs 161.3M |
| raster.invalidationRects | equal | COST 1934 vs 1888 | equal | COST 2981 vs 2935 |
| trace.RasterTask | COST 404 vs 278 | COST 1337 vs 1207 | unusable (quarantined) | COST 1741 vs 1485 |
| census.drawingLayers, drawingAreaPx | WIN (deterministic) 7586 vs 7972 layers, 613M vs 739M px | unusable (quarantined) | unusable | unusable |
| census.activeTiles | WIN 5740 vs 6538 | WIN(<=) 30546 vs 31885 | WIN 4740 vs 4920 | WIN(<=) 41342 vs 43671 |
| census.layers | COST 8358 vs 8329 | unusable (quarantined) | unusable | unusable |

* Toggle frame (INFERRED from the counts, no frame marker exists): frame 575, the only frame where PrePaint (+26, 32 vs 6) and Layout.dirtyObjects (+1) differ in all three flag runs against all three base runs, at y 5342 in phase swipe. In that frame the flag pays Paint 109 vs 88, invalidation rects 32 vs 13, invalidated area 4.15M vs 0.58M px and RasterTask 57 vs 11; UpdateLayoutTree and Layout do not change on any frame (0 frames differ), so the toggle is a style-only frame, not a layout frame.
* The Paint win is spread over frames before the toggle (279 frames differ in all runs, net -335 over the run); the cost sits on the toggle frame and in raster work (RasterTask +126 in y05000, +256 in finish).
* Reading: a trade, as `cr_toggle_not_le` says. The measured toggle pays PrePaint/Paint/raster but no layout, so the model's full-layout price for the toggle (`cr_toggle_not_le`, `CrLevel.layoutFull`) is refuted as a mechanism; only its conclusion (the toggle frame is not <=) holds (MEASURED, runs 40174480097 / 40174482844). PrePaint and invalidation `=o` / `<=o` fail with COST, which the Lean model's `=o` PrePaint row also predicted wrongly (model-bug on the finish zones). The table uses these runs' own zone classes, not the frozen table's quarantine of Paint, PrePaint, Layout and RasterTask.

### WebKit (Simulator; Lean has no WebKit lane in `measure.engineCheck`, it answers "no lane yet")
Classes from `measure.classify` (mode cells, zone tolerance absTol 2 / relTol 0.1, 11 zones, 6 passes per arm), steps up to y 5200 only (the passes end at 5231 or 5267; the last 1 to 2 steps differ by a harness read race and are left out). Raw per-pass sums, base | flag:
| type | class base / flag | z09 | z10 | finish (z09+z10) |
|---|---|---|---|---|
| Paint | quarantined / quarantined | 99-150 \| 233-277 | 50-63 \| 130-137 | 157-213 \| 370-412 |
| Layout | quarantined / quarantined | 33-57 \| 40-73 | 18-26 \| 21-32 | 51-83 \| 61-101 |
| RecalculateStyles | quarantined / quarantined | 45-58 \| 46-62 | 22-32 \| 23-32 | 67-90 \| 69-94 |
| Composite | deterministic / deterministic | 20 \| 20 | 10 \| 10 | 30 \| 30 (equal in all 6 passes) |

* The Lean rule can certify only Composite (equal). Paint, Layout and RecalculateStyles are quarantined in both arms, so no WIN or COST can be certified (unusable). Raw, not a Lean verdict: every one of the 6 flag Paint sums is above every one of the 6 base sums in z09, z10 and finish (about x2.3 to x2.5 in z10 and finish; the per-step rise starts near y 4200 when the section enters the viewport). Layout is higher by about 5 to 15 in z09/z10 with overlap; RecalculateStyles overlaps.
* This contradicts `wk_rest_claim` (rest frames dominate) and the Paint `=o` row; `wk_toggle_eqv` covers only the one or two toggle frames. The per-step rise is on rest frames: in all 6 flag passes Paint per 50 px step goes to 17-37 from y 4200 to 5200, against 7-26 in base, and those frames have fade >= 1 (filter none in the flag, `blur(0)` in the base). The Lean model said the toggle changes no WebKit count. A measured Paint rise means the section's content is painted into its parent layer once the filter group is gone (INFERRED, not isolated).
* Layer census (`measure.classify` cells per state, memory tolerance absTol 0 / relTol 0.02):
| state | layers base \| flag (lower median) | memoryBytes base \| flag | Lean cell verdict |
|---|---|---|---|
| 4500 (same y) | 141-150 \| 138-144 (145 vs 140) | 149.26-159.81 MB \| 125.49 MB in all 6 | memory: -28.15 MB, flag max below base min; base cell quarantined so unusable by the rule; layers unusable (quarantined) |
| finish | 124-128 \| 123-127 (124 vs 123) | 105.79 MB \| 84.60 MB, all 6 each | memory WIN, exactly -21.19 MB (both deterministic); layers inside noise (delta -1) |
  `section#platform` (reason `filterWithCompositedDescendants`) is a composited layer with 23.78 MB backing in the base at 4500 and absent in all flag passes; `reasonCounts.filterWithCompositedDescendants` goes 2 to 1. That is the `wk_rest_layers` claim (-1 layer) CONFIRMED, and memory goes down, not up. The finish census differs in requested y (5231 in all 6 base passes, 5267 in all 6 flag passes), so the -21.19 MB is tagged with that confound; the delta equals the base section backing 21192120 B exactly, so the y difference does not change the memory verdict (MEASURED).
* Machine confound (MEASURED, telemetry of the 6 Simulator VMs): the probe field `loadCenti` divided by 100, averaged over each VM's probes, is 510 to 523 on the three base VMs and 665 to 734 on the three flag VMs (CPU about 99% on all), so the flag VMs ran 30% to 40% higher on that field. EventDispatch and TimerFire rise in the flag arm and are load-sensitive, so the WebKit Layout, RecalculateStyles and EventDispatch differences cannot be attributed to the flag. Paint z10 is 130-137 in all six flag passes (three VMs) against 50-63 in the base, which does not track load, but one set of three VMs per arm cannot prove it.

### Decision
* `morph.panel:rest` stays a curated exclusion; `Fw.Preset.Gen` and the v2-proved set are unchanged. Reasons: (1) Chromium is a trade (Paint, tiles, drawing area down; PrePaint, invalidation, RasterTask up on the toggle frame and after it), the rule's own COST cells; (2) WebKit's memory win (-21.19 MB finish, WIN by the rule; -28.15 MB at 4500, not certifiable) comes with a Paint rise on a type the rule cannot certify, so "memory-only cost" does not hold: the cost is on the work side, not on memory.
* Mechanism: the flag removes the filter effect node (Chromium) or the filter group's RenderLayer (WebKit), which saves that layer's backing; the section is then painted into the parent, so the one frame where it flips pays PrePaint/Paint/raster and WebKit repaints more per step. Lean: `cr_toggle_not_le` (Chromium toggle frame is not `<=`), `wk_rest_layers` (-1 layer, confirmed); the measured WebKit Paint rise refutes `wk_rest_claim` on rest frames (raw, unclassified) and `wk_fade_trade`'s direction (paint -1) for the finish zones.

## Open (follow-ups, accepted limits)
* WebKit: repeat the counts with base and flag interleaved on the same VMs (the load confound), then the Paint rise can get a class; if it holds, correct `wk_rest_claim` and `wk_toggle_eqv` in `Fw.Parts.MorphPanelOpt` and the Chromium toggle price (`cr_toggle_not_le` mechanism, `CrLevel.layoutFull`) (model change, not done).
* The fractional-edge premise in Lean (the one edge row at 721 px), the Chromium run-level mixed theorem and the decision to toggle only in a frame that already pays layout (here the toggle frame pays PrePaint but no layout, so the second option does not apply as stated).
* Chromium `engineCheck` has no zone argument; the per-zone table is scratch glue over frame slices (TS stand-in, not committed).

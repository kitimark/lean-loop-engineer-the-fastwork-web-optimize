# Engine premises: which untested ones to measure first (task engine-premise-measure, 2026-10-18)

All 253 engine golden rows (12 files in `packages/contracts/golden/engine/`) cite at least one of the 17 untested
premises of `untestedPremises` (`lean/Fw/Ops/Premise.lean`, landed with engine-golden-premise-lint, 5acf680). Only 4 rows
also cite the measured WKTR premise p18. Status: MEASURED = row counts below, computed from the goldens with the citation
rules of `engineCites`; INFERRED = the part dependency column (a golden file stands for one part's theorems).

## Ranking

"Rows" = golden rows that cite the premise. "Files" = golden files that cite it; each file is the golden of one part (or
of the engine tables: `chromium`, `webkit`), so it is the number of part theorem sets that rest on the premise.

| Rank | Premise | Rows | Files | Observable (count type) | Measurable on CI |
|---|---|---|---|---|---|
| 1 | cr.layout | 38 | 10 | `trace.Layout` | yes, trace fixture |
| 2 | wk.style | 23 | 10 | `styleRecalcs` (WKTR internals) | yes, WKTR fixture |
| 2 | wk.layout | 23 | 10 | `layoutUpdates` | yes |
| 2 | wk.commit | 23 | 10 | `layerFlushes`, `renderingUpdates` | yes |
| 5 | cr.script | 20 | 10 | `trace.FunctionCall`, `FireAnimationFrame` | yes |
| 6 | cr.paint | 18 | 9 | `trace.Paint` | yes |
| 7 | cr.style | 17 | 10 | `trace.UpdateLayoutTree` | yes |
| 7 | cr.commit | 17 | 10 | `trace.cc.Commit` | yes |
| 7 | wk.paint | 17 | 9 | none (WKTR has no Paint counter) | no |
| 10 | cr.props | 13 | 7 | `trace.PrePaint` | yes |
| 10 | wk.script | 13 | 5 | none (no FireAnimationFrame counter; the harness's own rAF would be circular) | no |
| 12 | cr.signature | 8 | 1 | stage set of 69 (property, layer) members; all Chromium stage rows rest on it | yes, same fixture |
| 12 | cr.comp | 8 | 3 | `census.layers` is positive in every frame, so it cannot tell a frame with a compositor animation from one without | no (needs another observable) |
| 14 | cr.raster | 6 | 3 | `raster.invalidationRects` | yes |
| 15 | wk.props | 5 | 2 | `compositingUpdates` | yes |
| 16 | cr.mode | 2 | 1 | needs real Chrome next to the lane | no |
| 16 | cr.hits | 2 | 1 | `trace.HitTest` | yes |

Reading: the top seven by rows are the per-stage rules of the two engines; they are shared by every part, so one
fixture per engine covers 14 of the 17. Of the 17, 4 cannot be measured with the counters we have (wk.paint, wk.script,
cr.comp, cr.mode); they stay in `untestedPremises` and the reason is part of the statement.

## What a premise says, and what a test can say

Each stage rule says: the per-frame count of the stage's counters is ordered like the model's work of that stage "zero
iff zero, and <= / < against the base arm". For a frame without forced style or layout reads the model gives
`passes in {0, 1}` (Lean `frameWork`: one pass if the stage is touched, plus the forced passes), so for such frames every
`=0`, `any`, `>0` row and every ordering of passes reduces to presence. A test therefore compares presence of the stage's
counters in one frame with `s in touched E f`. The `units` component of `Work` (changes per stage) is not observed by a
presence test; that gap is stated in the registry statement of each moved premise.

## Method (CONFIRMED: `.github/workflows/engine-premises.yml`, `packages/measure-chromium/src/premise-*.mjs`, `lean/Fw/Ops/EnginePremise.lean`)

- One generated fixture page per engine; every step is one frame: a single style change on a probe element at a placement
  (none / own compositing layer / layer child), a bare rAF, or idle. Expected presence per stage comes from the Lean model
  (`touched`), written to `packages/contracts/golden/ops/engine-premises.jsonl` (251 rows); the TS verdict is a port of the
  Lean verdict (cell agree / mismatch / unstable / missing; a stage fails if any cell mismatches).
- Chromium: Docker trace lane with BeginFrameControl (65 cases, 130 steps); counters are trace events bucketed per frame
  (`FireAnimationFrame`, `FunctionCall`, `UpdateLayoutTree`, `Layout`, `PrePaint`, `Paint`, `RasterTask`, `cc.Commit`,
  `HitTest`). Six warm frames follow trace start and are dropped: Tracing.start forces one full repaint at the second
  commit after it starts (INFERRED from the trace). `raster.invalidationRects` is unusable (stale per-layer rects).
- WebKit: WKTR cases mode on the Simulator, `internals` counters sampled in rAF (30 cases, 60 steps).
- Excluded cases (6 Chromium, 27 WebKit) are property/placement pairs the engine cannot form.
- Gap: a presence test sees neither `units` nor forced passes nor the ordering against the base arm; each moved premise
  states this in its registry statement.

## Results (MEASURED: run 39088367495, commit 485b013; 3 independent Chromium jobs, 3 WebKit jobs x 2 passes; no unstable cell)

| Premise | Verdict | Cells (agree / mismatch) |
|---|---|---|
| cr.script, cr.style, cr.commit | holds | 130 / 0 |
| wk.style, wk.commit | holds | 60 / 0 |
| cr.layout | fails | 129 / 1 |
| cr.props | fails | 129 / 1 |
| cr.paint | fails | 126 / 4 |
| cr.raster | fails | 125 / 5 |
| cr.hits | fails | 112 / 18 |
| wk.layout | fails | 58 / 2 |
| wk.props | fails | 50 / 10 |
| wk.script, wk.paint, cr.comp, cr.signature, cr.mode | not measured | no counter / needs real Chrome |

Five hold and move into `registry` (lane `engine-premises.yml`). Seven fail and stay in `untestedPremises` with the
counterexamples recorded in `refutedPremises`. Five cannot be measured with our counters. Untested remaining: 12 (7
refuted, 5 unmeasurable); 100 of the 253 golden rows now rest only on measured premises, 153 still cite one of the 12.

### Findings (MEASURED counterexamples; the mechanisms are INFERRED and untested)

| Premise | Counterexample (all passes agree) | Likely mechanism | Rows citing it |
|---|---|---|---|
| cr.layout | transform none<->some at an own layer: model Layout, observed none | a transform change never needs layout; the model's `layoutFull` level over-counts at `@own` | 38 rows, 10 files (levels layoutFull) |
| cr.props | a bare rAF frame after `padding@own` runs PrePaint (one cell, step 126) | lagging property update of the previous layout change | 13 rows, 7 files |
| cr.paint | `top`, `left`, `margin`, transform none<->some at an own layer run no Paint (model runs) | the own layer is moved without repaint | 18 rows, 9 files |
| cr.raster | `scale@own`, `filter(blur)@own` run RasterTask (model none); `top`, `left`, `margin` at own run none (model runs) | scale and blur re-raster the layer; position at an own layer only moves it | 6 rows, 3 files |
| cr.hits | every layout-affecting set step (transform none<->some at none/layer, top/left at layer/own, width, height, margin, padding at all placements) also runs HitTest | hover/hit-test update after layout | 2 rows (nav-hittest) |
| wk.layout | `filter` at layer and own run layoutUpdates (model none) | filter changes visual overflow | 23 rows, 10 files |
| wk.props | compositingUpdates runs for transform, opacity, filter at layer and background, color, mask, insetAbs at own/layer (model none); `opacity@own` runs none (model runs) | WebKit re-evaluates compositing on more changes than the model's table | 5 rows, 2 files |

Row counts per file are from `lean/scripts/EngineCiteLint.lean` (a row cites a premise by file, engine and stage); a row
breaks only if its scenario's change is one of the counterexamples, which the golden rows do not record per property.

General lesson: the stage rules hold for the stages that every engine runs per frame regardless of layer (script, style,
commit) and fail at the compositor boundary (layout, paint, raster, props of an own layer), where the model's levels are
coarser than the engine. Parts whose theorems rest on those stages for promoted elements (hero-exit, morph-mount,
morph-panel, people-card, people-deck, pain-notes, nav-hittest) are sound only where their change avoids the counterexample
list. A model fix would split `layoutPos`, `layoutFull` and `paint` per placement (a follow-up for the model owner).

## Model fix (task engine-model-fix, 2026-10-18)

Every counterexample cell of run 39088367495 is now predicted: `Fw.Ops.EnginePremise.cr_recorded_holds` and
`wk_recorded_holds` rebuild all 190 step cells from the recorded presences (`crRecorded`, `wkRecorded`) and get
`holds` for every observer (PROVED). The records were checked against the run's `premise-verdict` artifact: old
expectation XOR offending cell gives the record for all 130 + 60 steps, and the regenerated golden predicts each one
(MEASURED, scratch script, 0 differences). The seven rules moved from `untestedPremises` into `registry` as lane
premises (p24-p30, `refuted_registered`); 5 untested remain (cr.comp, cr.signature, cr.mode, wk.script, wk.paint).

| Premise | Model change (Lean) |
|---|---|
| cr.layout, cr.paint, cr.raster | `keyLevel`: top/left/margin @own -> new level `layoutMove` (style, layout, props, commit); scale, blur filter, transform toggle @own -> `raster`; the level order is stage inclusion (`layoutMove_raster_incomparable`), `CrLevel.max` joins incomparable levels to `layoutFull` |
| cr.props | `chromiumAt.base = [props]`: every updating main frame runs PrePaint (`local_frame_view.cc:2586`@f842f52) |
| cr.hits | `crWorkH.hits` adds one hover hit test per frame that lays out (`crHover`, `crWorkH_hits`) |
| wk.layout | `filter` (outsets change) is Layout; `filterPainted` keeps the old Equal+Filter rule |
| wk.props | `props` comes from the compositing table `wkCompUpdate` (`wkStages`, `mem_wkStages`) |

### Sign changes (claims whose verdict changed)

| Claim | Engine | Old | New | Lean why |
|---|---|---|---|---|
| morph.panel own layer during the blur fade (ledger n=11) | Chromium | trade (raster -1) | no-win (equal work, +1 layer) | `cr_fade_stages`, `cr_fade_eq`, `cr_fade_noClaim` |
| morph.panel blur(0) -> filter:none at rest (n=11) | WebKit | trade (toggle +1 layout unit) | win (toggle frames equal) | `wk_toggle_layout_units`, `wk_toggle_eqv`, `wk_rest_claim` |
| WebKit table P5 js3d vs 2D transform | WebKit | compositingUpdates `>o` | `=o` | `webkit.jsonl` rows, `predOf` guards |
| WebKit union-check pair (transform@own + insetAbs vs background@layer + size) | WebKit | accepted | rejected | `unionLe` guards in `Fw.Engine.WebKit` |

Strength changes without a sign change: hero-exit Chromium raster `<o` -> `≤o` and WebKit compositingUpdates `≤o` ->
`<o` (still a trade on both); pain-notes and people-card Chromium PrePaint `=o` -> `≤o` (the gated variants also skip
the base PrePaint of a callback-only frame); morph.panel WebKit fade is still a trade, now paint -1 and props -1 per
frame and dominated frame by frame (`wk_fade_le`, `wk_fade_trade`). Ledger notes for the two ledger sign changes are
keyed (entry, engine-model-fix).

General lesson: a stage model calibrated per property and not per (property, placement) misprices exactly the
compositor-boundary cases that optimizations target (promotion, own layers, filter radius), so every claim that
promotes an element must cite the per-placement row, and a refuted premise must be followed by a sweep of the claims
that cite it.

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

Method and results are appended below once the CI runs have been read.

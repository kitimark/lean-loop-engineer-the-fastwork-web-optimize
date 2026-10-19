# F6 composition check on the measured runs

`engine-check --compose` asks, per (stage, count type, zone or whole run), whether a combined arm's delta equals the
sum of its single-flag deltas within the class margin. The verdict is Lean's `Fw.Measure.Compose.verdict`; the TS
loads runs and prints the table.

## Result: v2-proved against the faithful page, whole run, unit types

Coherent set on one commit (ci/f6-set at main 575e3087, `runner.json` sha of all 11 runs), workflow chromium-counts,
profile swipe-v1, arm rewrite, 2 runs per side, one image (sha256:8f0e17f5) and one trajectory (503 frames, 12 zones).
Base 39295469515 has every part faithful (`baseFlags` []). Combined 39295484486 adds the 9 v2-proved flags. Each single
run adds one flag on the same base. I read the flags of all 22 shards from `meta.rewrite.config.variants`.

| stage | type | class | combined Δ | single Δ above the margin | sum | residual | margin | verdict | evidence |
|---|---|---|---|---|---|---|---|---|---|
| script | trace.FireAnimationFrame | quarantined | -370 | scroll -463, mount +93, hitTest +1 | -369 | -1 | none | not comparable: quarantined | no verdict |
| script | trace.FunctionCall | quarantined | +38 | scroll -463, mount +499, scene, columns, countdown +2 each, hitTest +1 | 43 | -5 | none | not comparable: quarantined | no verdict |
| layout | trace.Layout.dirtyObjects | quarantined | -414 | mount -414, countdown +2, tween +2 | -410 | -4 | none | not comparable: quarantined | no verdict |
| paint | raster.invalidationAreaPx | stable(4,0) | -563778 | mount -563778 | -563778 | 0 | 0 | composes | informative |
| paint | raster.invalidationRects | stable(4,0) | 790 | mount 790 | 790 | 0 | 0 | composes | informative |
| raster | raster.invalidationAreaPx | stable(4,0) | -563778 | mount -563778 | -563778 | 0 | 0 | composes | informative |
| raster | raster.invalidationRects | stable(4,0) | 790 | mount 790 | 790 | 0 | 0 | composes | informative |
| comp | census.layers | stable(2,3) | 1056 | mount 1056 (the other 8: 0 to 3) | 1066 | -10 | 60 | composes | informative |

Short names: scroll `engine.scroll:batched`, mount `morph.mount:shift`, hitTest `nav.hitTest:elements-skip`, scene
`engine.scene:hidden-pause`, columns `morph.columns:hidden-pause`, countdown `morph.countdown:hidden-pause`, tween
`morph.tween:waapi`. `pain.notes:visible` and `people.card:mq` have whole-run single deltas of 0 or 1 on every unit type.
All values are MEASURED; `results/compose-check/table.md` lists every row with its run ids.

Pass types, reported only (whole run): `trace.UpdateLayoutTree` -1011 against a sum of -1012 (hitTest -926,
`people.card:mq` -61, scroll -25), `trace.Paint` -274 against -271, `trace.Layout` -4 against -2, `trace.PrePaint` -1
against -1, `trace.cc.Commit` 0 against 0.

Zone cells: none of the 96 unit zone cells is decided. 60 have a stable class with k at least 1, so they have no
per-zone margin (`verdict_noZoneMargin`); 36 are quarantined. 17 of the 96 have a nonzero residual, the largest
`trace.FunctionCall` zone y04000 (+14: combined -8 against a sum of -22).

## Answer

- **v2-proved composes on all 5 decided cells, and all 5 are informative, but only `morph.mount:shift` acts in
  them.** In the raster cells the other 8 flags change invalidation by exactly 0 alone, and adding them to
  `morph.mount:shift` changes it by exactly 0. `census.layers` reads the same within its margin of 60 (residual -10).
  No decided cell has two flags whose single deltas exceed the margin. MEASURED.
- **Coupled: none.** MEASURED.
- **The add-ups of several acting flags have no verdict.** `trace.FireAnimationFrame` (-370 against -463 + 93 + 1),
  `trace.FunctionCall` (+38 against 43) and `trace.Layout.dirtyObjects` (-414 against -410) are quarantined, so they
  have no margin. Their residuals (-1, -5, -4) are of the size of the base spread between its two runs (1, 2 and 2).
  MEASURED numbers, no F6 verdict.
- **The hidden-pause triple of round 1 composes only vacuously.** Its base 39130874266 sets `commission`, `pain` and
  `people` to `shell` (`baseFlags`), so it is not a comparison against the faithful page. Four of its 5 decided
  cells have a delta of 0 in every run, and the margin of `census.layers` (24) exceeds every delta (at most 2). The
  undecided `trace.FunctionCall` cell adds up exactly (12 = 9 + 1 + 2) but is quarantined. MEASURED.

## Rule (Lean, `lean/Fw/Measure/Compose.lean`)

- Delta: lower median of the arm runs minus lower median of the base runs (`Pair.delta`). Residual: combined delta
  minus the sum of the single deltas (`Cell.residual`). Margin: `2 · slack(class) · (n + 1)` for `n` flags
  (`Cell.margin`), 0 for frame-exact classes (`slack_exact`).
- Order (`pre`, then `verdict`): pass type, reported; a flag with no single arm, missing; quarantined or unlisted;
  zone cell of a class that is not frame exact, no-zone-margin; frame-exact cell whose runs disagree, drift; then
  composes if the absolute residual is at most the margin, else coupled, naming the flags with a nonzero single delta.
- Evidence: a cell is informative when its combined delta or a single delta exceeds the margin (`Cell.informative`,
  `informative_iff_beyond`), else vacuous (`vacuous_of_zero`). `beyond` names the single flags above the margin.
- Refusal (`refusal`): the op refuses a combined comparison that is not clean or adds fewer than 2 flags
  (`refusal_eq_none_iff`, `refusal_unclean`, `refusal_fewFlags`; golden cases in `measure.compose.jsonl`).
- Single arm (`armFor`, `armFor_spec`, `armFor_ne_self`): another run id, the same base run id and zone shape, both
  sides clean, and its arm adds exactly that flag. `loadRun` throws on a counts file without
  `meta.rewrite.config.variants`.
- Rows are keyed by (stage, count type, zone or whole run) of one combined comparison. A part enters a row as its
  single-flag delta in `parts`, and by name in `beyond` and in a `coupled` verdict, so the task's (part, stage, zone)
  unit is a row's part entry.
- Theorems: `verdict_composes_iff`, `verdict_coupled_iff`, `verdict_reported_iff`, `verdict_missing`,
  `missing_not_composes`, `missing_not_coupled`, `verdict_quarantined`, `verdict_noZoneMargin`, `verdict_drift`,
  `verdict_coupled_parts`, `composes_exact`, `coupled_cell_sound`, `cellAt_missing`, `informative_iff`,
  `informative_exact_iff`.

## Limits

- One profile (swipe-v1) and 2 runs per side.
- Flag independence is not checked. The verdict does not reference `Fw.Engine.Compose.lego_swap_units`, so a
  `coupled` verdict could not tell flags that are not independent from a model failure. No cell is coupled here.
- No unit type has a frame-exact class in `classes.frozen.json` swipe-v1 rewrite, so zone cells get no verdict.
- `trace.FireAnimationFrame` counts units: Chromium emits one event per uncancelled callback in the loop of
  `ExecuteFrameCallbacksImpl` (third_party/blink/renderer/core/dom/frame_request_callback_collection.cc:114@f842f52),
  CONFIRMED. That the callbacks of two parts are disjoint, and the split of the other types, is INFERRED from
  `Fw.Engine.Compose`.
- Runs pair by base run id and zone shape; counts files carry no site commit. The commit of the coherent set is
  CONFIRMED from `runner.json`. That the round 1 runs share build 698b7755 is INFERRED from the model-checks note,
  and applying the frozen class table to them is INFERRED.
- All 10 deltas share the base median B, so the residual is C − ΣSᵢ + 8B for 9 flags: a base offset of 1 moves the
  residual by 8. The quarantined residuals above (-1, -5, -4) are smaller than that.

## Files

`results/compose-check/plan.json` (run ids), `results/compose-check/<name>.json` (fwcore replies),
`results/compose-check/table.md` (every row). Regenerate: download with
`gh run download <id> -p 'chromium-counts-*' -D <dir>/<id>`, then
`node packages/engine-check/src/cli.mjs --compose results/compose-check/plan.json --runs <dir> --out results/compose-check`.

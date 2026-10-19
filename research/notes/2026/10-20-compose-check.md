# F6 composition check on the measured runs

`engine-check --compose` asks, per (stage, count type, zone), whether a combined arm's delta equals the sum of its
single-flag deltas within the class margin. The verdict is Lean's `Fw.Measure.Compose.verdict`; the TS only loads
runs and prints the table.

## Answer

- **Composes**: the hidden-pause triple (`engine.scene`, `morph.columns`, `morph.countdown`, all `hidden-pause`) on
  build 698b7755. 5 cells are judged and all 5 compose with residual 0: `raster.invalidationAreaPx` and
  `raster.invalidationRects` (stage paint and raster) and `census.layers`, whole run. MEASURED.
- **Coupled**: none. No judged cell has a residual beyond its margin. MEASURED.
- **Not comparable, v2-proved** (run 39253172750 on build c6912998): all 104 unit cells. None of the 10 flags has a
  single-flag arm on that run's base 39253166643. Six flags have one on build 698b7755 (base 39130874266). That base
  differs, and its trajectory is 614 frames against 503, so the identity rule refuses it. Four flags were never
  measured alone on the whole page: `engine.scroll:batched`, `hero.countdown:strip`, `pain.notes:visible`,
  `people.card:mq`. MEASURED (artifact listing).
- **Not comparable, triple**: 42 unit cells are quarantined: `trace.FireAnimationFrame`, `trace.FunctionCall` and
  `trace.Layout.dirtyObjects` in `classes.frozen.json`. 65 zone cells have a stable class with k at least 1, so they
  have no per-zone margin. No unit type is frame exact in the frozen table, so a per-zone F6 verdict is not
  available on swipe-v1 today. MEASURED (class table), CONFIRMED (`verdict_noZoneMargin`).
- **Reported, not judged**: pass types (`trace.UpdateLayoutTree`, `trace.Layout`, `trace.PrePaint`, `trace.Paint`,
  `trace.cc.Commit`), per `passes_not_compositional` in `Fw.Engine.Compose`.
- The triple is weak evidence. Its deltas are near zero on swipe-v1: 10 of 182 cells have a nonzero combined delta,
  the largest `trace.FunctionCall` +12. Every one of the 182 residuals is 0, judged or not. MEASURED.

## Rule (Lean, `lean/Fw/Measure/Compose.lean`)

- Delta of a pair: lower median of the arm runs minus lower median of the base runs (`Pair.delta`,
  `ZoneBaseline.base`).
- Residual: combined delta minus the sum of the single-flag deltas (`Cell.residual`).
- Margin: `2 · slack(class) · (n + 1)` for `n` flags (`Cell.margin`). It is 0 for frame-exact classes
  (`slack_exact`).
- Order of the decision (`pre`, then `verdict`): pass type, reported; a flag with no single arm, missing; quarantined
  or unlisted; zone cell of a class that is not frame exact, no-zone-margin; frame-exact cell whose runs disagree,
  drift; then composes if the absolute residual is at most the margin, else coupled, naming the flags whose single
  delta is nonzero.
- Identity of a single-flag arm (`armFor`, `armFor_spec`): its arm adds exactly that flag to its base, its base run
  id equals the combined base run id, its zone shape (id, frames, scrolled px, first and last frame per zone) equals
  the combined one, and both sides are clean (`Runs.clean`).
- Theorems: `verdict_composes_iff`, `verdict_coupled_iff`, `verdict_reported_iff`, `verdict_missing`,
  `missing_not_composes`, `missing_not_coupled`, `verdict_quarantined`, `verdict_noZoneMargin`, `verdict_drift`,
  `verdict_coupled_parts`, `composes_exact`, `coupled_cell_sound` (if every unseen delta stays within twice the
  slack, a coupled cell keeps a nonzero residual), `cellAt_missing`.

## Hidden-pause triple, whole run

Combined 39131249517, base 39130874266, singles 39131168588 (`engine.scene`), 39131207849 (`morph.columns`),
39131217951 (`morph.countdown`); 3 runs each side, profile swipe-v1, arm rewrite.

| stage | type | class | combined Δ | single Δ (scene, columns, countdown) | residual | margin | verdict |
|---|---|---|---|---|---|---|---|
| script | trace.FireAnimationFrame | quarantined | 0 | 0, 0, 0 | 0 | 0 | not comparable: quarantined |
| script | trace.FunctionCall | quarantined | 12 | 9, 1, 2 | 0 | 0 | not comparable: quarantined |
| style | trace.UpdateLayoutTree | deterministic | 1 | 1, 0, 0 | 0 | 0 | reported |
| layout | trace.Layout | quarantined | 0 | 0, 0, 0 | 0 | 0 | reported |
| layout | trace.Layout.dirtyObjects | quarantined | 0 | 0, 0, 0 | 0 | 0 | not comparable: quarantined |
| props | trace.PrePaint | stable(2,0) | 0 | 0, 0, 0 | 0 | 0 | reported |
| paint | trace.Paint | quarantined | 0 | 0, 0, 0 | 0 | 0 | reported |
| paint | raster.invalidationAreaPx | stable(4,0) | 0 | 0, 0, 0 | 0 | 0 | composes |
| paint | raster.invalidationRects | stable(4,0) | 0 | 0, 0, 0 | 0 | 0 | composes |
| raster | raster.invalidationAreaPx | stable(4,0) | 0 | 0, 0, 0 | 0 | 0 | composes |
| raster | raster.invalidationRects | stable(4,0) | 0 | 0, 0, 0 | 0 | 0 | composes |
| commit | trace.cc.Commit | deterministic | 0 | 0, 0, 0 | 0 | 0 | reported |
| comp | census.layers | stable(2,3) | -2 | -2, 0, 0 | 0 | 24 | composes |

Zone cells (13 zones, `rest` to `tail`): the nonzero ones are `trace.FunctionCall` y01000 +1 (countdown), y02000 +1
(countdown), y03000 +9 (scene), y04000 -8 (scene), y05000 +1 (columns); `trace.UpdateLayoutTree` y03000 +1 (scene);
`census.layers` y05000 -2 (scene). Each equals the sum of its singles. None is judged: they are quarantined, passes, or
have no zone margin.

## v2-proved, whole run

Combined 39253172750, base 39253166643. Flags: `engine.scene:hidden-pause`, `engine.scroll:batched`,
`hero.countdown:strip`, `morph.columns:hidden-pause`, `morph.countdown:hidden-pause`, `morph.mount:shift`,
`morph.tween:waapi`, `nav.hitTest:elements-skip`, `pain.notes:visible`, `people.card:mq`.

| stage | type | combined Δ | verdict |
|---|---|---|---|
| script | trace.FireAnimationFrame | -603 | not comparable: missing, all 10 flags |
| script | trace.FunctionCall | -195 | not comparable: missing, all 10 flags |
| style | trace.UpdateLayoutTree | -1011 | reported |
| layout | trace.Layout | -4 | reported |
| layout | trace.Layout.dirtyObjects | -414 | not comparable: missing, all 10 flags |
| props | trace.PrePaint | -1 | reported |
| paint | trace.Paint | -274 | reported |
| paint, raster | raster.invalidationAreaPx | -565155 | not comparable: missing, all 10 flags |
| paint, raster | raster.invalidationRects | 789 | not comparable: missing, all 10 flags |
| commit | trace.cc.Commit | 0 | reported |
| comp | census.layers | 1054 | not comparable: missing, all 10 flags |

Single-flag whole-page runs that exist (all on base 39130874266, build 698b7755, research/notes/2026/10-19-model-checks.md):
39131146372 `morph.tween:waapi`, 39131168588 `engine.scene:hidden-pause`, 39131207849 `morph.columns:hidden-pause`,
39131217951 `morph.countdown:hidden-pause`, 39131302530 `morph.mount:shift`, 39131395370
`nav.hitTest:elements-skip`, 39131343835 `nav.hitTest:hit-skip` (not in v2-proved). 39131314391 sets two flags, so it
is never a single.

## Limits

- Runs pair by base run id and zone shape, not by site commit. Counts files carry no site commit. That the
  model-checks runs share build 698b7755 is INFERRED from the model-checks note.
- The class table is `classes.frozen.json` swipe-v1 rewrite, frozen on one image. Applying it to build 698b7755 runs
  is INFERRED.
- The unit and pass split (`unitTypes`) is INFERRED from `Fw.Engine.Compose`: work units add over parts; pass counts
  do not.
- A part page (`?only=`) runs another trajectory (992 frames), so its zones never match a whole-page run.

## Next

One coherent set on one commit makes v2-proved comparable: a base, the v2-proved arm, and one whole-page arm per flag
(`fw` input of `chromium-counts.yml`, profile swipe-v1), each with the same base run. The v2-proved set on main now
has 9 flags (`hero.countdown:strip` left it, `lean/scripts/check.sh` "v2-proved"), so the set is 11 runs. Not dispatched:
GitHub Actions was degraded and the accepted limits allow listing the missing arms.

Files: `results/compose-check/plan.json` (run ids), `results/compose-check/<name>.json` (fwcore replies),
`results/compose-check/table.md` (every row). Regenerate:
`node packages/engine-check/src/cli.mjs --compose results/compose-check/plan.json --runs <download dir> --out results/compose-check`.

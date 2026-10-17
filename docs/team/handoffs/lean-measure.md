# Handoff: lean-measure (Lean spec of the measurement lanes)

State at the lean-measure branch commit. Lean first: every reduction and class decision of both counts lanes past raw
counts is in `lean/Fw/Measure/` and reached through `fwcore` ops `measure.*` (table in `lean/README.md`).

## Modules (111 theorems, 63 `#guard`s; mathview lint clean, standard axioms only)

| Module | Content |
|---|---|
| `Zones` | Chromium `zoneSums` (was `packages/measure-chromium/src/reduce.mjs`). Lookups are filter sums (`sumAt_spec`, `framesAt_spec`, `scrolledAt_spec`); additivity over concatenation (`sumAt_append`, `framesAt_append`, `scrolledAt_append`: scroll distance chains through `lastY`); monotone in the counts (`sumAt_mono`) and in appended non-negative frames (`sumAt_le_append`); partition: zone sums add to the run total, frames to the frame count, scroll distances to the final scrollY (`zones_sum_total`, `zones_frames_total`, `zones_scrolled_total`); each zone listed once, exactly the occupied ones (`zoneIds_nodup`, `mem_zoneIds`) |
| `Classes` | `Within`/`Holds` for deterministic, stable(k, t), quarantined; `classify` (policy kMax, tMax) is sound (`classify_sound`), the strictest admissible class (`classify_strictest`), monotone in the runs (`classify_mono`, `classify_snoc`); deterministic iff stable(0, 0) (`holds_det_iff_stable00`); exact characterisations of det and quarantined |
| `Tolerance` | Which classes enter the screen. Deterministic: frame by frame (`det_frames_sound`). Stable(k, t): by totals with margin `2t` (0 if k = 0): `margin_sound`, and `margin_exact` (a margin m is sound, even for non-negative counts, iff m >= margin(k, t)); frame by frame is unsound (`stable_frames_unsound`). Quarantined: no margin works (`quarantined_unsound`). `noMoreWork` with `noMoreWork_sound` and `noMoreWork_cost` (linear run cost under any non-negative coefficients) |
| `WebKit` | `packages/measure-webkit/src/reduce.mjs`: `quadArea`, `tally`, step join (`stepOf`, `reduceSteps`; `steps_partition`, `rows_conserved`), dense `zones` (`zones_partition`, `zones_steps_total`, `zoneSteps_append`), cell-spread `classifyCells` (`classifyCells_snoc`: monotone in the runs when relTol <= 1; `classifyCells_det_holds`: deterministic cells are deterministic runs; `classifyCells_stable`: frame-sense k, t always hold, so `Tolerance` applies to WebKit too), `symDiff`, `summarize` (`summarize_worst`) |
| `Wire`, `Golden` | ops and golden generator (namespace `Fw.Wire.*`, outside the math view) |

Key statement (the one to review first), `Fw.Measure.margin_exact`:
$$\operatorname{Sound}(k, t, m) \iff \operatorname{margin}(k, t) \le m,\qquad \operatorname{margin}(k, t) = \begin{cases} 0 & k = 0 \\ 2t & k \ge 1 \end{cases}$$

## Goldens and conformance (MEASURED)

- `packages/contracts/golden/measure/<op>.jsonl`, 8 files, 47 cases, `{name, request, response}`; regenerate with
  `cd lean && lake env lean --run scripts/MeasureGolden.lean` (`--check` fails on a stale file; `lake test` checks too).
- Chromium: the TS `zoneSums` equalled every non-error golden case and, through fwcore, the stored `zones` of three real
  503-frame runs (det-a/b/c); then `reduce.mjs` was deleted. `src/fwcore.mjs` is the host-side client; `host.mjs`
  writes `zones.json` from fwcore; `src/classify.mjs` prints classes from fwcore. `test/fwcore.test.mjs` replays the
  goldens through the binary.
- WebKit: `packages/measure-webkit/test/fwcore.test.mjs` checks every golden line against fwcore and against the TS
  functions (tally, reduceSteps, zones, classify, symDiff, summarize): all equal. The WebKit harness still calls its TS
  `reduce.mjs` (not rewired; I cannot run the Simulator lane here).
- Real Chromium runs, `measure.classify` kMax 4, tMax 24: 28 deterministic, 14 stable, 8 quarantined. Differences from
  the hand table: `UpdateLayoutTree.elementCount` quarantined (38 frames differ), `metric.Frames`, `metric.Resources`
  stable (2 frames, equal totals; the hand table called them GC-bound).

## Semantics chosen (review these)

- "Shifted by one" is not checked structurally: stable(k, t) bounds the number of differing frames (zero-padded, as
  `compare.mjs`) and the total gap, over all pairs of runs. A one-frame shift is a special case.
- Counts are `Int` (getMetrics deltas can be negative); the wire refuses non-integers and `zoneHeightPx = 0`, fewer
  than two runs, negative WebKit offsets, decreasing or empty marks (cases where JS throws or misbehaves).
- WebKit times, clips and tolerances are exact decimals (Rat). JS uses doubles: comparisons agree (JSON carries the
  shortest decimal); `relTol * big` agrees for 0.02/0.05/0.1 because those doubles lie above their decimals; paint area
  and `maxRelSpread` rounding could differ only on exact .5 ties after float error (INFERRED, none in the goldens).
- Edge cases where Lean is cleaner than JS (documented, not replicated): key order uses code points (JS sort: UTF-16);
  count names like `constructor`/`__proto__` break the JS object accumulators; `stepOf` counts marks <= s (equals the
  JS binary search for non-decreasing marks, which the wire enforces; not proved).

## Gaps

- `symDiff` symmetry is proved termwise over any key list, not for the sorted key lists of `A++B` vs `B++A`.
- `flattenRecords`, `markTimes`/`markTime`, `layerKey` (extraction) and Chromium `trace.mjs` have no Lean spec.
- The class premise (unseen runs stay within the observed class) is L3, not provable; `classify` needs >= 2 runs and a
  policy (kMax, tMax) the lead has to fix per lane.

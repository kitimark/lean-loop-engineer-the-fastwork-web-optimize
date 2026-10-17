# Handoff: zone-baseline-lean (lean-prover)

State: worktree branch of task zone-baseline-lean, one commit with trailer `Task: zone-baseline-lean` (see `git log --grep "Task: zone-baseline-lean"`).
Gates: `sh lean/scripts/check.sh` green; `cd packages/measure-chromium && pnpm test` 23/23.

Done
- `lean/Fw/Measure/ZoneBaseline.lean`: `zoneBaseline tb rs` = `refusal` (< 3 runs, repeated run id, repeated zone id,
  zone structure (id, frames, scrolledPx, firstFrame, lastFrame) differing from run 1) or `baseline`: per zone and type
  `row` = (type, frozen entry or none = unlisted, perRun, lo, hi, base = sorted index floor((n-1)/2)); whole-run `totals`;
  `detDrift` (zone, type) and `detDriftTotals` (det class and lo != hi).
- Theorems: `det_lo_eq_hi_or_drift`, `det_total_lo_eq_hi_or_drift`, `detDrift_nil_of_equal`, `totals_eq_sum_zones`,
  `total_zoneSums` (reuses `zones_sum_total`), `lo_le_base`, `base_le_hi`, `base_mem`, `lo_eq_hi_iff`, `baseline_perm`
  (order independence via `cellAt`/`totalAt` lookups: summaries equal, perRun permuted, drift membership equal),
  `refusal_none`, `zoneBaseline_ok`.
- Wire op `measure.zoneBaseline` in `lean/Fw/Measure/Wire.lean` (runs give `frames` + `zoneHeightPx`, or `zones`);
  cell JSON {class | unlisted, rule, perRun, lo, hi, base}; 11 goldens `packages/contracts/golden/measure/measure.zoneBaseline.jsonl`
  (generator cases in `Fw/Measure/Golden.lean`).
- `packages/measure-chromium/src/zone-baseline.mjs baseline --out results/baselines/chromium [--check]` writes
  `results/baselines/chromium/swipe-v1/original.baseline.json` from the committed `original.zones.json` + frozen table
  (sha256 recorded). Result: 3 runs, 12 zones, 70 types, detDrift 0, tally det 27 / stable 25 / quar 10 / unlisted 8.
- README in `results/baselines/chromium/` names the file and the re-run after refreeze (outside the task's write list,
  asked for by the task text).

Conventions: Lean binders `l`, `ty`, `rs` appear as `v`, `\tau`, `\mathcal{R}` in the math (mathview prints
"renamed binder" warnings only). Order independence is stated on lookups, not list order, since JSON objects are keyed.

Open
- refreeze: after it, re-run `zone-baseline.mjs baseline` (fwcore.test.mjs fails while the file is stale).
- Part dimension: none (counts have no part attribution).

Read first: `lean/Fw/Measure/ZoneBaseline.lean` header, then the `measure.zoneBaseline` row in `Wire.lean`.

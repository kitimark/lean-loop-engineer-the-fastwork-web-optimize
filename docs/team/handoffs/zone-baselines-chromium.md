# Handoff: zone-baselines-chromium (measure-engineer)

State: branch `ci/zone-baselines-chromium` (pushed for CI) and the worktree branch; commit with trailer `Task: zone-baselines-chromium`.
Done: CI run 39048702153 (3 original shards, image = frozen image), stored with `pnpm fw ci`, per-shard zone sums in
`results/baselines/chromium/swipe-v1/original.zones.json` (+ `original.classes.json`), README with run id, sha, image.
`packages/measure-chromium/src/zone-baseline.mjs` is glue only (store read, fwcore `measure.zoneSums`, `--check`).

Learned
- `pnpm fw ci` writes to the MAIN checkout's `.fw-console/store` even from a worktree (storeDir follows the git common dir).
- A `target=original` dispatch skips `site`, so `classify` is skipped (no `if: !cancelled()`), and `fw ci` then refuses
  (`missing chromium-classes/original`). Dispatch `target=both` until the workflow (not my file) is fixed.
- A push to a `ci/*` branch starts all workflows incl. macOS ones (wktr, gate-gaps, webkit-sim): cancel them.

LEAN REQUEST (open, blocks the cross-shard baseline): op `measure.zoneBaseline`.
- Request: `zoneHeightPx` (>= 1), `runs` (>= 3, distinct `id`) [{id, frames}], `classes` {type: {class, k, t, tBound?}} (the frozen table).
- Refuse: runs whose zone structure differs (id, frames, scrolledPx, firstFrame, lastFrame per zone).
- Reply per zone and per type seen in any run: `class` (from the table; a type absent from it is `unlisted`, rule = quarantined),
  `perRun` sums in run order, `lo`, `hi`, `base` (the observed run total at sorted index floor((n-1)/2), a real observation);
  plus whole-run `totals` per type with the same fields.
- Theorems: det class => lo = hi (or the cell is reported in `detDrift`, which must be empty for equal-trajectory runs); totals =
  sum over zones per run (reuse `zones_sum_total`); lo <= base <= hi; order independence of the runs.
- Then `zone-baseline.mjs` calls it and writes `original.baseline.json`; golden vectors under `packages/contracts/golden/measure/`.
- Decide with the lead: `refreeze` first (frozen table lacks 8 types incl. N1/N0; HitTest changed class), and whether a part dimension is wanted
  (counts have none).

Open: swipe-touch-v1 waits for touch-race; the rewrite target's zones were not produced (key 12670b98... is stored).
Read first: `results/baselines/chromium/README.md`, `zone-baseline.mjs` header.

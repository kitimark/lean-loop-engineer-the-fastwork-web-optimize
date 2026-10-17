# Zone baselines, Chromium: all four (profile, arm) baselines

Status: MEASURED on GitHub CI (chromium-counts, Linux, free runners); raw counts are work, not milliseconds, and nothing here is phone time.

Question: per-zone baselines of the original and the rewrite for swipe-v1 and swipe-touch-v1, from 3 separate-VM shards each, with
no deterministic type drifting between shards.

Method: store the CI runs (`pnpm fw ci`), recompute each shard's zone sums with fwcore `measure.zoneSums`, check them against the
shard's own `zones.json`, then fwcore `measure.zoneBaseline` (Lean `Fw.Measure.ZoneBaseline`) with the arm's table from
`packages/measure-chromium/classes.frozen.json` (schema 2, `profiles[p].arms[target]`). JS only reads and writes files
(`packages/measure-chromium/src/zone-baseline.mjs`, new `--profile` filter for picking among stored runs).

Result (MEASURED): files under `results/baselines/chromium/<profile>/{original,rewrite}.{zones,baseline,classes}.json`; table in
`results/baselines/chromium/README.md`. All four baselines have 0 unlisted types and an empty `detDrift` and `detDriftTotals`:
no deterministic cell or total differs between shards. Differences exist only in stable/quarantined types of the original (swipe-v1: 16 of 309
stable cells, 27 of 107 quarantined; touch: 13 of 401, 34 of 174), mostly pixel-area and invalidation types. Both rewrite arms differ in no cell.

Caveats
- The swipe-v1 pair comes from run 39048702153 (image ebefaf34, harness cba3040, an early rewrite); the touch pair from the refreeze
  run 39050423094 (image 8f0e17f5, sha f87bf94, the frozen table's image). A rewrite change needs a new `target=rewrite` run and re-pull.
- Zones are scroll bands, not parts; no per-part attribution exists in Chromium counts.
- One workflow run per baseline (3 shards). Three workflow runs per profile exist for the class table; they were not pooled here.
- Local fwcore came from the main checkout's build (this worktree had no lake build); the committed files are checked by `pnpm test`.

Open: re-run `zone-baseline.mjs baseline` for every pair after each refreeze; baselines for the new rewrite once ports land.

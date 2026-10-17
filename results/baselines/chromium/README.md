# Per-zone baselines of the original, Chromium (profile swipe-v1)

Raw counts are work, not milliseconds; nothing here is phone time. MEASURED on GitHub CI, not on this Mac.

| Thing | Value |
|---|---|
| CI run | 39048702153 (chromium-counts, branch `ci/zone-baselines-chromium`, `target=both`, `image_run=39038861283`), 3 shards `counts (original, r1..r3)` on separate VMs |
| Harness head sha | cba3040623312e35349dd23048295cd38779e79d (includes the HitTest/N1 splits and N0; not the touch-race changes) |
| Image | `sha256:ebefaf34b6c912a57b62fd023bbe81b4dc5fe7cef1ebcddca0bfda7a6a31d491` (the frozen table's image), Chrome Headless Shell 156.0.8078.4 |
| Store key (original) | `1a6f1c4aaab56b8d54a2051ceaad6d69d608d1ffa5acda5502bf539c5a82046a` (`pnpm fw ci 39048702153 --branch ci/zone-baselines-chromium`; the re-pull printed `unchanged`) |
| Zones | `rest` (10 frames), `y00000`..`y04500` (nine 500 px bands, 49/50x8/14 frames; scroll 490/500/136 px), `tail` (30) |

Files in `swipe-v1/`:
- `original.zones.json` (`fw.zonebaseline.chromium/1`): per shard, per zone: frames, scrolledPx, first/last frame and the sum of every count type (70 types). Zone assignment and sums are Lean `Fw.Measure.zoneSums` (fwcore `measure.zoneSums`).
- `original.classes.json`: the run's own classes over its 3 shards (fwcore `measure.classify`, kMax 4, tMax 24), copied byte for byte from the store.
- `original.baseline.json` (`fw.zonebaseline.chromium.baseline/1`): the cross-shard baseline, fwcore `measure.zoneBaseline` (Lean `Fw.Measure.ZoneBaseline`) over the 3 shards of `original.zones.json` and the `swipe-v1` profile of the frozen table `packages/measure-chromium/classes.frozen.json` (its sha256 is in `classTable`). Per zone and type, and per type for the whole run (`totals`): `class` (the frozen class, or `unlisted` = not in the table, rule quarantined), `perRun` (r1, r2, r3), `lo`, `hi`, `base` (the observed value at sorted index floor((n-1)/2), here the median of 3). `detDrift` lists deterministic cells with lo != hi: empty for this run (MEASURED). 8 types are `unlisted` until the refreeze.
  **Re-run after every refreeze of the frozen table:** `node packages/measure-chromium/src/zone-baseline.mjs baseline --out results/baselines/chromium` (`--check` compares; `pnpm test` in `packages/measure-chromium` fails while the file is stale).

Reproduce (needs the store entry and fwcore; the store is gitignored):
`pnpm fw ci 39048702153 --branch ci/zone-baselines-chromium` then
`node packages/measure-chromium/src/zone-baseline.mjs --store <store> --target original --run 39048702153 --out results/baselines/chromium --check`.
The script recomputes every shard's zone sums with fwcore from `counts.json` and refuses if they differ from the shard's own `zones.json` or from this file. Per-frame vectors are the `frames` of `r<n>/counts.json` in the store.

What the data shows (MEASURED, this run): zone ids, frame counts and scrolled px are identical in the 3 shards. Of 12 zones x 70 types, the cells that differ between shards are 18 of stable types and 25 of quarantined types by the run's own classes; none of a deterministic type.

NOT in this directory, with the reason:
- **Count vectors per part.** The Chromium counts have frame and zone dimensions only; the original snapshot has no part attribution (nothing in `counts.json` is keyed by part).
- **The frozen table `packages/measure-chromium/classes.frozen.json` does not cover 8 of the 70 types** (n0.*, trace.HitTest.overlayAdDetector, trace.N1.*; the run classifies them deterministic) and has trace.HitTest quarantined where the split harness gives stable (k 2). The `refreeze` task regenerates it; until then the frozen table is stale for these.

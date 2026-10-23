# Per-zone baselines, Chromium (profiles swipe-v1 and swipe-touch-v1; arms original and rewrite)

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
- Count vectors per part. The Chromium counts have frame and zone dimensions only; the original snapshot has no part attribution (nothing in `counts.json` is keyed by part).
- The frozen table `packages/measure-chromium/classes.frozen.json` does not cover 8 of the 70 types (n0.*, trace.HitTest.overlayAdDetector, trace.N1.*; the run classifies them deterministic) and has trace.HitTest quarantined where the split harness gives stable (k 2). The `refreeze` task regenerates it; until then the frozen table is stale for these.

## Part 2: all four (profile, arm) baselines

Each baseline is 3 shards (separate VMs) of ONE workflow run, same zone structure and frame counts in all 3 (Lean refuses otherwise).
All four files are `fwcore measure.zoneBaseline` over the profile's arm table in `classes.frozen.json` (schema 2). No new CI run was needed.

| profile | arm | CI run | harness sha | image | frames | zones | types | tally det/stable/quar/unlisted | detDrift |
|---|---|---|---|---|---|---|---|---|---|
| swipe-v1 | original | 39048702153 | cba3040 | ebefaf34... | 503 | 12 | 70 | 32/28/10/0 | 0 |
| swipe-v1 | rewrite | 39048702153 | cba3040 | ebefaf34... | 385 | 9 | 51 | 44/7/0/0 | 0 |
| swipe-touch-v1 | original | 39050423094 | f87bf94 | 8f0e17f5... | 531 | 13 | 70 | 23/32/15/0 | 0 |
| swipe-touch-v1 | rewrite | 39050423094 | f87bf94 | 8f0e17f5... | 409 | 10 | 51 | 50/1/0/0 | 0 |

- Pull: `pnpm fw ci <run> --branch <ci branch>` (swipe-v1 run on `ci/zone-baselines-chromium`, touch run on `ci/refreeze-b`), then
  `node packages/measure-chromium/src/zone-baseline.mjs --store <store> --profile <p> --target <original|rewrite> --run <run> --out results/baselines/chromium`
  and `... baseline --out results/baselines/chromium --profile <p> --target <t>` (`--check` compares; the test checks all four).
- The swipe-v1 rewrite is the rewrite at harness sha cba3040 (the first rewrite CI run), not the current apps/site; re-pull a new `target=rewrite` run to move it. The swipe-v1 pair was measured on image ebefaf34..., the frozen table on 8f0e17f5... (classes are per type, not per image; the image is recorded in each file).
- Zones are scroll bands (`rest`, `settle`, `yNNNNN`, `tail`), not parts. The rewrite page is shorter, so its last bands differ (touch rewrite stops at y03000; swipe-v1 rewrite at y03000 with 454 px); compare arms per zone id and per whole-run `totals`.
- `detDrift` and `detDriftTotals` are empty in all four (MEASURED). Cells that differ between shards (profile/arm: stable cells, quarantined cells): swipe-v1 original 16 of 309, 27 of 107; touch original 13 of 401, 34 of 174; both rewrite baselines 0 (rewrite is deterministic/stable-only: 365+55 and 464+1 cells with no difference). Largest whole-run spans are pixel-area types (census.drawingAreaPx ~2.0e6, raster.invalidationAreaPx ~2.9e6 of ~1.9e8 in touch original).

## Part 3: re-measured on the font image

Parts 1 and 2 above were measured on the font-less lane image (text not drawn, page 720 px short); the files in this directory now come from the
font image `sha256:47b1dcbe...` (fonts-liberation, page 6278 px at 430x932), so the Part 2 table and the 8-types-unlisted remarks are history.
MEASURED, 3 shards of ONE workflow run per profile (both arms in that run), image digest equal in all jobs, frozen table = the 6 runs below.

| profile | CI run (zones) | harness sha | frames (both arms) | zones | types | tally det/stable/quar/unlisted, original | rewrite | detDrift |
|---|---|---|---|---|---|---|---|---|
| swipe-v1 | 39916914389 | 3783b39 | 575 | 13 | 70 | 30/16/24/0 | 23/22/25/0 | 0 |
| swipe-touch-v1 | 39924634896 | c3c94a0 | 771 | 14 | 70 | 33/18/19/0 | 20/19/31/0 | 0 |

- Frozen over three runs per profile (`classes.frozen.json`, `--built-by 39914488176`): swipe-v1 39914488176, 39916914389, 39916917890; swipe-touch-v1 39924634896, 39924639452, 39924643106 (the note research/notes/2026/10-2x-counts-font-fidelity.md has the font-less counts next to these).
- Pull and rebuild: `pnpm fw ci <run> --branch ci/counts-font-fidelity`, then `zone-baseline.mjs --store <store> --profile <p> --target <t> --run <run> --out results/baselines/chromium` and `... baseline --out results/baselines/chromium --profile <p> --target <t>`. The store keeps one run per key, so the other two runs of a profile (same key) are not stored; the zones and baselines are of the run named here.

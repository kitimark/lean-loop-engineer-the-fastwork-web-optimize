# webkit-cost-counters: per-frame cost counters of the WebKit lag lane, original against rewrite

Date 2026-10-22. Task `webkit-cost-counters`, branch `worktree-wf_3d6e8140-325-1`. Lane: iPhone Simulator 430x775 at DPR 3 on a
GitHub macOS runner (one width only; "both widths" is not deliverable). Status words: CONFIRMED (source or Lean cited),
MEASURED (CI run cited), INFERRED. Source cites are `file:line@862f17d` (WebKit, tag WebKit-7625.1.29.10.29).

## 1. What exists

| Piece | Where | Status |
|---|---|---|
| Lean predicates and per-zone reductions | `lean/Fw/Measure/WkCost.lean` (core only, no `sorry`) | CONFIRMED (`sh lean/scripts/check.sh` green) |
| Golden (54 lines) | `packages/contracts/golden/measure/wkcost.jsonl`, written by `lean/scripts/WkCostGolden.lean`, `--check` in `check.sh` | CONFIRMED |
| TS twin of the reductions | `packages/measure-webkit/src/lag/cost.mjs`, replayed against the golden in `test/lag-cost.test.mjs` (9 tests) | CONFIRMED |
| Probe passes (I/O only) | `src/lag/costprobe.mjs`: `scrollCost`, `morphCost`, `scrollLayers`, `morphLayers`, run by `lagSession` (`--cost on|off|only`) | MEASURED |
| Per-zone table | `src/lag/costreport.mjs`, `cli.mjs cost-report --original a,b --rewrite c,d [--preset e]`, 4 tests | CONFIRMED on synthetic data, MEASURED on CI data |
| CI trigger | `.github/workflows/webkit-sim.yml`: commit tokens `[lag]` (both arms), `[lag:rewrite]`, `[lag:v2-proved]`, 3 VMs each | MEASURED |

Lean theorems (all in `Fw.Measure.WkCost`): `nOver_anti`, `over_chain` (over 50 ms <= over 34 ms <= over 25 ms),
`slot_gap_of_long` (an interval of 33.334 ms or more spans 2 display slots), `nOver_le_nSkip` (an interval over 33.333 ms is a
skipped slot; the converse is false, the golden has a 26 ms interval inside one slot), `nSkip_le_nSlots`, `histBin_0` to
`histBin_6`, `histBin_lt`, `hist_sum`; `compositeBound_true`, `compositeBound_false`, `bound_le_frames`, `sumsOf_append`;
`newLayers_self`, `newLayers_nil`, `resizedLayers_nil`, `isResized_of_isNew`, `new_add_resized_le`; `early_add_late`,
`nIn_nil`; `morphZone_idle`, `morphZone_open`, `morphZone_rest_between`, `morphZone_close`, `morphZone_rest_after`.
The skipped-slot formula (`slotOf d = (6 d + 50000) / 100000`, offsets anchored at the first frame of a pass) is the one the parallel
task `device-stats-v2` defines in `Fw.Device.Session`; the two are not yet unified.

## 2. CI runs (one workflow run per arm, 3 VMs each; a failed VM was repeated in a new run)

| Run | Branch, token | Arm | Jobs with cost data | Not usable |
|---|---|---|---|---|
| 39647881249 | `ci/webkit-cost-counters`, `[lag]` | original v1 v2 v3 | 3 of 3 (6 passes) | - |
| 39647881249 | same | rewrite r2 r3 | r3 (2 passes), r2 (pass 1 only) | r1: step hit the 35 min bound; r2: pass 2 morph lost the Safari tab |
| 39665776192 | `ci/webkit-cost-counters-rewrite`, `[lag:rewrite]` | rewrite r1 r2 | 2 of 3 (4 passes) | r3: cancelled after about 50 min |
| 39657539501 | `ci/webkit-cost-counters-preset`, `[lag:v2-proved]` | preset r1 r2 r3 | 3 of 3 (6 passes) | - |
| 39647907113 | same branch, first push | preset r1 r2 r3 | not in the table (r2, r3 agree in the same ranges) | r1: inspector died during the cost scroll |

The original arm is 3 jobs, the rewrite arm 4 jobs (7 of 8 passes with cost counters, two runs), the preset arm 3 jobs. Counts
are per pass; a cell is the range over passes (MEASURED, run ids above). Cost-pass failures of the rewrite and preset arms:
4 of 12 jobs did not finish (original: 0 of 3). The cause is not identified (no lag-only control in this task, the logs show a
`Runtime.evaluate` timeout of 120 s in a cost scroll once and a lost tab twice); whether the cost passes make the rewrite arm
less stable is OPEN. The Lean step bound for `determinism` (35 min) is close for the lag probe with cost passes: finished jobs took
16 to 30 min (MEASURED).

## 3. Which counter worked

| Counter | Result on CI | Separates original from rewrite? |
|---|---|---|
| rAF interval histogram (7 bins), skipped display slots, over 25 and 50 ms | Works in every zone and arm. The VM is slow: in the stepped scroll 44 to 100 of 100 frames skip a slot, so the counter nearly saturates. | Hero exit only: skipped slots 72-88 per 100 frames (rewrite) against 97 (original), and intervals over 100 ms 16-39 percent against 48-94 percent; the preset arm (same code as rewrite) gives 72-81 and 16-42, so the result replicates. The other zones overlap. |
| Paint against Composite per frame (Timeline) | Works. Composite is 16 to 655 ms per frame and Paint 0.7 to 30 ms; Composite exceeds Paint in 83 to 100 percent of frames in every zone. The Inspector files GPU raster and buffer waits under Composite (`RenderLayerBacking.cpp:4164,4198`, `RemoteLayerTreeDrawingArea.mm:357,445-448`@862f17d, CONFIRMED), so the Simulator frame is raster-bound (INFERRED, software raster). | No, all zones overlap. It attributes cost; it does not rank the arms here. |
| New layers per layer-tree read | Works. Hero exit: original 4.3 to 4.8 new layer ids per read, rewrite 1.0 to 1.5, preset 1.0 to 1.3. | Yes, hero exit (lower, replicated by the preset arm). Other zones overlap. What creates the layers is not identified here. |
| Layer bounds changes (resized) | Works. Hero exit 72 to 119 per 100 reads in all arms. | No. |
| Paint records after a morph ends | Works but weak: the morph zones hold only 1 to 4 frames or reads per pass (the tween is 680 ms and a frame takes 150 ms or more on the VM). One pass (rewrite, run 39665776192, r2, pass 1) has 523 paint records after the push and none in the 500 ms after either tween end. | No, all ranges overlap. Do not use alone. |

The A/A control matters: with the same code in the rewrite and preset arms, the calm-scroll skipped-slot verdict is "lower"
for the preset arm and "overlap" for the rewrite arm. A single-zone "lower" is therefore fragile; the hero-exit results
above are the ones that two arms reproduce. The preset `v2-proved` is EMPTY at this commit
(`apps/site/src/registry/presets/v2-proved.json` = `{"extends":"original","fw":{},"name":"v2-proved"}`), so the preset arm is an A/A
replicate of the default rewrite, not a measurement of a proved flag set.

## 4. Per-zone table (original against rewrite against preset)

Generated with `node packages/measure-webkit/src/lag/cli.mjs cost-report --original v1,v2,v3 --rewrite r2,r3 (run 39647881249),
r1,r2 (run 39665776192) --preset r1,r2,r3 (run 39657539501)`. "vs original" says lower or higher only when the per-pass ranges
do not overlap (`Fw.Measure.WebKitLag.verdict`). Morph-zone cells rest on 1 to 5 frames per pass.

Arms: original (6/6 passes with the cost counters), rewrite (7/8 passes with the cost counters), preset (6/6 passes with the cost counters). Cells are per-pass ranges.

#### Frame cadence (rAF intervals; slot = round((t - t0) / 16.67 ms), skipped when it jumps more than one)

| zone | arm | frames | skipped slots events / 100 frames | slots lost / 100 frames | > 25 ms / 100 frames | > 50 ms / 100 frames | skipped100 vs original |
|---|---|---:|---:|---:|---:|---:|---|
| hero exit (scroll A) | original | 32 | 96.9 | 613-1281 | 96.9 | 75.0-96.9 |  |
| hero exit (scroll A) | rewrite | 32 | 71.9-87.5 | 225-819 | 75.0-87.5 | 28.1-53.1 | lower |
| hero exit (scroll A) | preset | 32 | 71.9-81.3 | 234-594 | 62.5-87.5 | 28.1-50.0 | lower |
| end of page (scroll B) | original | 32-34 | 47.1-100 | 82.4-669 | 44.1-100 | 14.7-96.9 |  |
| end of page (scroll B) | rewrite | 32-34 | 76.5-100 | 159-909 | 79.4-100 | 32.4-96.9 | overlap |
| end of page (scroll B) | preset | 32-34 | 62.5-100 | 141-603 | 68.8-97.1 | 21.9-87.5 | overlap |
| calm scroll (baseline) | original | 86-88 | 70.5-87.2 | 252-590 | 69.3-87.2 | 48.9-74.4 |  |
| calm scroll (baseline) | rewrite | 86-88 | 44.3-80.2 | 87.5-366 | 38.6-77.9 | 11.4-48.9 | overlap |
| calm scroll (baseline) | preset | 86-88 | 44.2-68.2 | 90.7-222 | 38.4-67.0 | 8.1-36.4 | lower |
| morph idle (baseline) | original | 9-10 | 44.4-90.0 | 44.4-360 | 33.3-90.0 | 0.0-66.7 |  |
| morph idle (baseline) | rewrite | 9-10 | 33.3-88.9 | 33.3-244 | 22.2-90.0 | 0.0-77.8 | overlap |
| morph idle (baseline) | preset | 9-10 | 30.0-90.0 | 30.0-100 | 10.0-90.0 | 0.0 | overlap |
| morph open (push down) | original | 2-4 | 50.0-100 | 200-1400 | 50.0-100 | 33.3-100 |  |
| morph open (push down) | rewrite | 2-5 | 100 | 200-1333 | 80.0-100 | 33.3-100 | overlap |
| morph open (push down) | preset | 1-4 | 50.0-100 | 50.0-900 | 50.0-100 | 0.0-100 | overlap |
| morph close (push up) | original | 2-5 | 100 | 640-1200 | 100 | 50.0-100 |  |
| morph close (push up) | rewrite | 2-4 | 75.0-100 | 825-1600 | 100 | 50.0-100 | overlap |
| morph close (push up) | preset | 2-7 | 75.0-100 | 500-1150 | 80.0-100 | 50.0-80.0 | overlap |
| morph rest | original | 18-60 | 75.0-100 | 152-800 | 71.7-100 | 8.3-100 |  |
| morph rest | rewrite | 6-44 | 88.6-100 | 252-3467 | 97.7-100 | 18.2-100 | overlap |
| morph rest | preset | 14-66 | 60.6-100 | 124-1229 | 56.1-100 | 7.6-100 | overlap |

#### rAF interval histogram (% of intervals per bin; bin edges from Lean `histEdges`)

| zone | arm | <= 12 ms | 12-20 ms | 20-25 ms | 25-34 ms | 34-50 ms | 50-100 ms | > 100 ms | h6 vs original |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| hero exit (scroll A) | original | 0 | 0 | 0 | 0-6 | 0-19 | 6-32 | 48-94 |  |
| hero exit (scroll A) | rewrite | 0-3 | 0-16 | 0-16 | 6-35 | 16-23 | 13-35 | 16-39 | lower |
| hero exit (scroll A) | preset | 0-3 | 0-13 | 6-23 | 6-35 | 6-26 | 10-29 | 16-42 | lower |
| end of page (scroll B) | original | 0-6 | 0-26 | 0-24 | 0-26 | 3-32 | 15-41 | 0-56 |  |
| end of page (scroll B) | rewrite | 0-3 | 0-15 | 0-9 | 0-26 | 3-29 | 24-56 | 3-71 | overlap |
| end of page (scroll B) | preset | 0-6 | 0-22 | 3-9 | 0-16 | 3-35 | 19-56 | 3-50 | overlap |
| calm scroll (baseline) | original | 1-10 | 5-22 | 3-8 | 1-8 | 3-16 | 22-36 | 13-51 |  |
| calm scroll (baseline) | rewrite | 1-5 | 9-36 | 8-24 | 11-28 | 8-17 | 9-26 | 2-23 | overlap |
| calm scroll (baseline) | preset | 1-8 | 13-42 | 9-19 | 8-30 | 9-27 | 5-25 | 3-11 | lower |
| morph idle (baseline) | original | 0 | 0 | 0-63 | 0-38 | 0-88 | 0-75 | 0-33 |  |
| morph idle (baseline) | rewrite | 0 | 0 | 0-75 | 0-63 | 0-63 | 0-88 | 0 | overlap |
| morph idle (baseline) | preset | 0 | 0 | 0-89 | 11-78 | 0-78 | 0 | 0 | overlap |
| morph open (push down) | original | 0 | 0 | 0-50 | 0-33 | 0-50 | 0-67 | 0-50 |  |
| morph open (push down) | rewrite | 0 | 0 | 0-20 | 0 | 0-67 | 0-67 | 0-60 | overlap |
| morph open (push down) | preset | 0 | 0 | 0-50 | 0-50 | 0-50 | 0-50 | 0-100 | overlap |
| morph close (push up) | original | 0 | 0 | 0 | 0-25 | 0-25 | 0-67 | 33-60 |  |
| morph close (push up) | rewrite | 0 | 0 | 0 | 0-50 | 0-50 | 0-50 | 50-100 | overlap |
| morph close (push up) | preset | 0 | 0-20 | 0-20 | 0-50 | 0-50 | 0-43 | 29-80 | overlap |
| morph rest | original | 0 | 0 | 0-28 | 0-50 | 0-39 | 2-56 | 7-47 |  |
| morph rest | rewrite | 0 | 0 | 0-2 | 0-43 | 0-55 | 6-32 | 9-83 | overlap |
| morph rest | preset | 0 | 0-6 | 0-38 | 0-46 | 0-54 | 2-36 | 3-64 | overlap |

#### Paint against Composite per frame (Timeline durations, microseconds; the Inspector files raster under Composite)

| zone | arm | Paint us / frame | Composite us / frame | Composite > Paint, % of frames | compPF vs original |
|---|---|---:|---:|---:|---|
| hero exit (scroll A) | original | 1501-4654 | 41421-78534 | 100 |  |
| hero exit (scroll A) | rewrite | 2389-4345 | 35014-89423 | 100 | overlap |
| hero exit (scroll A) | preset | 2391-4635 | 36085-84125 | 100 | overlap |
| end of page (scroll B) | original | 946-4658 | 20642-109763 | 97 |  |
| end of page (scroll B) | rewrite | 1297-5537 | 28189-122742 | 97 | overlap |
| end of page (scroll B) | preset | 1095-3909 | 28459-92156 | 97 | overlap |
| calm scroll (baseline) | original | 843-1987 | 15943-50045 | 100 |  |
| calm scroll (baseline) | rewrite | 685-1875 | 16718-50818 | 100 | overlap |
| calm scroll (baseline) | preset | 794-1333 | 16665-33925 | 100 | overlap |
| morph idle (baseline) | original | 727-1346 | 21773-71279 | 100 |  |
| morph idle (baseline) | rewrite | 1005-1720 | 19153-54640 | 100 | overlap |
| morph idle (baseline) | preset | 760-1337 | 18663-40656 | 100 | overlap |
| morph open (push down) | original | 3177-9261 | 129222-323785 | 100 |  |
| morph open (push down) | rewrite | 3694-10733 | 110393-655473 | 100 | overlap |
| morph open (push down) | preset | 3787-30465 | 136273-368640 | 100 | overlap |
| morph close (push up) | original | 1983-5437 | 96710-256793 | 100 |  |
| morph close (push up) | rewrite | 2189-7279 | 158599-483161 | 100 | overlap |
| morph close (push up) | preset | 1940-4202 | 76484-267127 | 100 | overlap |
| morph rest | original | 1142-2599 | 30574-101447 | 94-98 |  |
| morph rest | rewrite | 806-8396 | 43395-216999 | 83-98 | overlap |
| morph rest | preset | 900-4671 | 25265-138803 | 93-98 | overlap |

#### Layers between layer-tree reads (new layer = id not in the previous read; resized = composited width or height changed)

| zone | arm | reads | new layers / 100 reads | resized layers / 100 reads | fresh100 vs original |
|---|---|---:|---:|---:|---|
| hero exit (scroll A) | original | 32 | 428-478 | 71.9-96.9 |  |
| hero exit (scroll A) | rewrite | 32 | 100-147 | 71.9-93.8 | lower |
| hero exit (scroll A) | preset | 32 | 103-131 | 75.0-119 | lower |
| end of page (scroll B) | original | 34 | 58.8-106 | 0.0-35.3 |  |
| end of page (scroll B) | rewrite | 32-34 | 56.3-79.4 | 0.0-5.9 | overlap |
| end of page (scroll B) | preset | 32-34 | 52.9-76.5 | 0.0 | overlap |
| calm scroll (baseline) | original | 88 | 62.5-78.4 | 9.1-15.9 |  |
| calm scroll (baseline) | rewrite | 86-88 | 61.4-68.2 | 10.2-22.7 | overlap |
| calm scroll (baseline) | preset | 86-88 | 52.3-71.6 | 13.6-19.3 | overlap |
| morph open (push down) | original | 2-4 | 2075-4150 | 550-1250 |  |
| morph open (push down) | rewrite | 1-3 | 2700-8100 | 833-1250 | overlap |
| morph open (push down) | preset | 1-4 | 2075-8100 | 975-1400 | overlap |
| morph close (push up) | original | 1-2 | 0.0 | 1100-1350 |  |
| morph close (push up) | rewrite | 1 | 0.0 | 1300-1400 | overlap |
| morph close (push up) | preset | 1-3 | 0.0 | 1050-1300 | overlap |
| morph rest | original | 1-14 | 0.0-25.0 | 157-800 |  |
| morph rest | rewrite | 1-18 | 0.0-100 | 256-1160 | overlap |
| morph rest | preset | 1-16 | 0.0-9.1 | 163-1400 | overlap |

#### Paint records after a morph ends (early: 0-500 ms after the tween end, late: 500-1000 ms)

| morph | arm | early | late | early vs original |
|---|---|---:|---:|---|
| morph open (push down) | original | 98-193 | 16-68 |  |
| morph open (push down) | rewrite | 0-100 | 3-100 | overlap |
| morph open (push down) | preset | 96-106 | 14-51 | overlap |
| morph close (push up) | original | 28-111 | 35-93 |  |
| morph close (push up) | rewrite | 0-57 | 28-88 | overlap |
| morph close (push up) | preset | 40-108 | 33-115 | overlap |


## 5. Accepted limits

- The Simulator has no real GPU. Pixels are BGRA8 (4 B/px), the device uses RGBA10 (5 B/px). Raster and Composite times here are
  not device times; they are CI-VM times and rank only within this lane.
- One width (430 CSS px, DPR 3). The breakpoint dimension of the pinned unit cannot be delivered by this lane.
- Preset `v2-proved` is empty at this commit, so the preset arm is an A/A control (section 3), not a flag measurement.
- rAF slot drift is anchored at the first frame of a pass. The Mac clock decides the zone of a layer read in `morphLayers`
  (reads are event-driven, so a zone edge can move by one read).
- The layer-tree reads and the Timeline passes run on separate fresh loads, so a frame's layer count and its Paint/Composite time
  are never from the same frame. Per-zone ranges are compared, not per-frame pairs.
- IOSurface creation and `slowFrame` need `xctrace`; they are the task `xctrace-ci-probe`, not attempted here. Without them the
  counters above show where frames are late and which layers are new, not what the GPU process allocated.

## 6. TS stand-ins (no Lean golden behind them)

- The in-page scripts of `costprobe.mjs` (`SCROLL_COST_JS`, `MORPH_COST_JS`) and the LayerTree reads (`readLayers`, `layerSession`).
- `frameCosts` (bucketing Timeline rows to frame marks): tested on synthetic rows only (`test/lag-costreport.test.mjs`).
- Retry handling (`costPasses`, the reconnect in `lagSession`), the markdown formatting and `rangeOf` in `costreport.mjs`.
- The Mac-clock zone assignment in `morphLayers`.
The per-zone verdict is the existing `Fw.Measure.WebKitLag.verdict` through `reduce.mjs`.

## 7. Open

- Why rewrite-arm jobs fail more often with the cost passes (4 of 12 against 0 of 3); a lag-only rewrite control would answer it.
- The lag probe uses the 35 min step bound of the Lean sim plan for `determinism`. With cost passes it is tight: finished jobs
  took 16 to 30 min, one job hit the bound and one was cancelled near 50 min. Options: a lag bound in Lean, or cost passes in pass 1 only.
- `device-stats-v2` and this task both define the skipped-slot formula; one Lean definition should serve both.
- Replication with a non-empty preset once `v2-proved` has flags.

# Zone baselines, WebKit Simulator: the original, per 500 px zone

Status: MEASURED on GitHub CI (webkit-sim, run 39061324429, `macos27` image 20261012.0260.1, 3 vCPU, 3 independent VMs v1-v3, 1 session
each, 2 fresh-load passes per session = 6 runs). Raw counts are work, not milliseconds; nothing here is phone time or a Mac run.

Question: per-zone baselines of the original page in the Simulator lane, for the types the WebKit class table lets us gate.

Method: the session files of the run (`determinism --out`) go through Lean twice: `measure.webkit.zones` (per pass: 500 px zone sums of the
per-step counts) and `measure.zoneBaseline` (`Fw.Measure.ZoneBaseline`: refuses runs with different zone structure, class lookup, perRun,
lo, hi, base = sorted index floor((n-1)/2), detDrift). The glue `packages/measure-webkit/src/zone-baseline.mjs` only reshapes zone rows into
zone records (frames = scroll steps; first/last frame by cumulative step count; scrolled px from ys) and writes files. The op takes one class
table per call, so it is called twice on the same 6 runs: zone-level classes (zones, `detDrift`) and whole-run classes (totals,
`detDriftTotals`), both from `packages/measure-webkit/classes/webkit-sim-v1.json` (49 D / 9 S / 46 Q of 104 rows, 3 sessions of earlier runs).
Files: `results/baselines/webkit/original.{zones,baseline}.json`; test `packages/measure-webkit/test/zone-baseline.test.mjs` (recomputes the
baseline from the committed zones file).

Structure (MEASURED): all 6 runs have the same 11 zones (z00-z09: 10 steps, 450 px; z10: 7 steps, 267 px), so Lean did not refuse them.

## Result: per type, class, drift, noise

`detDrift` and `detDriftTotals` are empty: no deterministic cell differs between the 6 runs. Zone class = worst of 3 earlier sessions at the zone level.

| count type | zone class | zones differing (of 11) | max zone spread (hi - lo) | whole-run class | whole-run lo..hi (6 runs) | gate? |
|---|---|---|---|---|---|---|
| RenderingFrame | deterministic | 0 | 0 | deterministic | 0..0 | yes (but constant 0) |
| Composite | stable | 0 | 0 | stable | 213..213 | yes |
| EventDispatch | stable | 0 | 0 | stable | 107..107 | yes |
| RecalculateStyles | quarantined | 11 | 17 | stable | 705..721 | no |
| Layout | quarantined | 11 | 20 | quarantined | 633..684 | no |
| Paint | quarantined | 11 | 50 | quarantined | 1326..1430 | no |
| FireAnimationFrame | quarantined | 5 | 16 | stable | 707..730 | no |
| TimerFire | quarantined | 11 | 17 | quarantined | 97..163 | no |
| ObserverCallback | quarantined | 6 | 7 | quarantined | 108..128 | no |
| FunctionCall | quarantined | 11 | 18 | quarantined | 1011..1063 | no |
| ScheduleStyleRecalculation | quarantined | 10 | 5 | stable | 644..661 | no |
| InvalidateLayout | quarantined | 11 | 20 | quarantined | 541..586 | no |
| paintArea | quarantined | 11 | 3408829 | quarantined | 83.4M..88.8M | no |

Gateable base values per zone (lo = hi = base in all 6 runs): Composite 19, 20 x 9, 14 (z00, z01-z09, z10); EventDispatch 10 x 10, 7; RenderingFrame 0 everywhere.
Zone values equal 2 Composite and 1 EventDispatch per scroll step: they track the scroll script's step count, not page content.

## What this means

- **Gateable per zone: RenderingFrame, Composite, EventDispatch only.** Their per-zone baseline is a single value. CONFIRMED by the Lean op (no drift).
- **Model-check-only (quarantined at the zone level): RecalculateStyles, Layout, Paint, FireAnimationFrame, TimerFire, ObserverCallback,
  FunctionCall, ScheduleStyleRecalculation, InvalidateLayout, paintArea.** The file keeps `perRun`, `lo`, `hi`, `base` for each as a noise band; a
  rewrite can be compared against the band, never gated on a cell. Whole-run totals of RecalculateStyles, FireAnimationFrame and
  ScheduleStyleRecalculation are stable (a whole-run gate on those is allowed by the table; per zone it is not).
- **Weak gate.** RenderingFrame is 0 in every zone and run (INFERRED: the Inspector timeline gives no RenderingFrame record in this setup), and
  Composite/EventDispatch are set by the scroll script. They catch a changed step structure or compositing schedule, not a style or layout regression.
  The real work types are noisy; the noise band (e.g. Layout +-10 per zone, Paint +-25) is as large as plausible part-level effects.

## Caveats

- 3 VMs x 2 passes in one workflow run; passes in one VM share a boot. The class table comes from earlier sessions (runs 39048376821,
  39050061299, 39055837084), not from this run; this run's own spreads (Composite, EventDispatch: 0) are smaller than the table's.
- Job v1's step "Determinism sessions" hit its 50 min timeout after writing `v1-session-1.json` (the log ends at the write; the session is
  complete), so the run is marked failed and the `merge` job was skipped. The v1 session file is complete and used. INFERRED: a slow end-of-session
  shutdown or md output; the same tail did not occur in v2 and v3.
- `scrolledPx` of a zone is first-to-last step distance (9 gaps of 50 px = 450), not 500; it only serves the structure check.
- The rewrite is not served by this lane (workflow input `target=original` only); no rewrite arm exists.
- Local fwcore came from the main checkout's build; the committed files are checked by `node --test test/zone-baseline.test.mjs`.

Open: re-run `zone-baseline.mjs` when the class table is regenerated; a quieter runner or the phone could widen the gateable set.
Reproduce: `gh workflow run webkit-sim.yml --ref <branch> -f vms=3`, download the artifacts, then
`node packages/measure-webkit/src/zone-baseline.mjs --sessions v1-session-1.json,v2-session-1.json,v3-session-1.json --out results/baselines/webkit --run-id <id>`.

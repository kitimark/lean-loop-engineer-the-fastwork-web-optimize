# Do the end-of-page column pictures cost anything on CI? Probe on Chromium counts and the WebKit Simulator push lane

Task cols-probe, P1 of `research/notes/2026/10-27-end-columns-probe.md`. CI lanes only: no phone, no Safari on the Mac. The phone half is
`research/notes/2026/10-2x-phone-cols-probe.md` (n = 4 per arm). The verdict rule was fixed in Lean before the data
(`lean/Fw/Device/ColsProbe.lean`, golden `packages/contracts/golden/device/cols-probe.jsonl`, 54 lines; TS twin
`packages/measure-chromium/src/cols-verdict.mjs` replays it).

## Answer (MEASURED, 2026-10-29)
| engine | contrast | Lean reading | what moved |
|---|---|---|---|
| Chromium | base vs base+off | pictures cost | RasterTask 2715-2718 to 2418-2420 (-11%), PaintImage 3302-3303 to 2856-2857 (-13%) |
| Chromium | timed-fixed vs timed-fixed+off | pictures cost | RasterTask 1861-1862 to 1843-1845 (-1%), PaintImage 2699-2700 to 2660-2661 (-1.5%) |
| WebKit Sim | base vs base+off | mixed | Paint per 1000 pushes is higher with the pictures hidden in 3 of 3 jobs; layerCount 128, 124, 128 against 128, 128, 141, 128 |
| WebKit Sim | timed-fixed vs timed-fixed+off | mixed | layerCount no cost; backing bytes and Paint overlap |
- Chromium is the same in two runs on separate CI jobs: 40802455145 and 40812007208 (12 jobs each, 3 per arm, profile swipe-touch-v1). The
  cost is small on the flip path and about a tenth on the base path. `cc.Draw` (771) does not move: the frame count is the same, the raster work per frame falls.
- WebKit Sim (3 push runs: 40792572994, 40802455303, 40812007170) never reads "pictures cost". Hiding the pictures does not lower layerCount,
  backing bytes or Paint beyond the reference arm's own job-to-job spread. This agrees with the phone (undecided, paint did not fall).
- Not delivered: Chromium RasterTask milliseconds and render-pass counts (the counts lane does not record them; follow-up: add both to
  `packages/measure-chromium/src/trace.mjs`). WebKit backing is bytes, not MB.

## Which of P2-P6 stay (Lean `fate`, decided by the rule)
| plan | fate | reason |
|---|---|---|
| P2 leaf opacity | independent of picture cost | removes the group offscreen pass, not picture paint |
| P3 column scaler | independent | track layers, not picture paint |
| P4 static backdrop wrappers | independent | structure |
| P5 hide always-clipped pictures | keep | a cost read in both Chromium contrasts |
| P6 crop reveal at <= 600 px | keep, by the rule | Chromium base contrast is "pictures cost" |
- INFERRED: the keep for P6 rests on Chromium alone. The engine where the lag is felt (WebKit, phone) shows no cost on any metric, so P6
  (look-class Q, user review) is the weakest keep: rank it last, and start it only after P2 to P4 are measured on the phone.
- The flip log, MEASURED: every timed push took (Chromium 3 of 3 per arm and run; Sim 12 of 12 per job) and `nav.is-on-dark` was false at every
  push (0 of 12 Sim, 0 of 3 Chromium). At the page end the nav is light, so the "flip" arms ran the geom-timed tween without a dark nav; the phone note's
  40 of 40 taken is the same count.

## Sim job loss (MEASURED)
Of 24 planned Sim arm passes in 9 jobs (3 runs of 3 VMs), 17 gave metrics: `push server: no ready file after 420 s` and `Timeline.stop timed out after 120000 ms` cost
the rest. With four arms per job (push 1) a job fits three passes in the 110 min limit, so pushes 2 and 3 used two arms per job (temporary workflow tokens
`cols-base`, `cols-timed`, patch in `results/cols-probe/toolbar-throttle-cols-token.patch`, reverted before the land). Jobs are pooled across the three runs
as files `f1..f9` (a file per job); base has 4 jobs, base+off 3, timed-fixed 5 (a sixth had one push window, no metrics), timed-fixed+off 5.
Census values are the last cycle at the page end. One base job (f5/vm2) had 141 layers and 154 MB, outside the others (128, 122.6 MB): why is not known.

## Chromium finding about the harness (MEASURED, INFERRED for the consequence)
Run 40792572637 used profile `push-cycle-d1000`: the page never reached its end (scrollY max 307 of 5189, `endGapPx` 4882, `input.start: 'end'` is
not read by `run.mjs`), so all four arms were identical and no push happened. Kept as `results/cols-probe/chromium-run-40792572637-push-cycle-d1000.json`.
INFERRED: the earlier Chromium push-cycle proxy (`research/notes/2026/10-2x-push-cycle-lag.md`) probably never reached the page end either; check before reusing it.

## Engine claims (CONFIRMED in source, from the phone note)
WebKit@862f17d `Source/WebCore/rendering/RenderReplaced.cpp:411` (no paint when used visibility is not visible), `RenderLayer.cpp:401`,
`RenderLayerBacking.cpp:1918` and `:2142`. Chromium@f842f52 `third_party/blink/renderer/core/paint/replaced_painter.cc:406-409`. The probe removes picture
paint and raster and not decode (not checked).

## Runs and files
- Chromium counts: 40792572637 (unusable), 40802455145, 40812007208. Reduced: `results/cols-probe/chromium-run-*.json`.
- Sim push lane: 40792572994, 40802455303, 40812007170. Reduced: `results/cols-probe/webkit-run-40792572994.json`, `results/cols-probe/webkit-pooled-40792572994-40802455303-40812007170.json`.
- Reducers: `packages/measure-chromium/src/cols-reduce.mjs`, `packages/measure-webkit/src/throttle/cols-report.mjs` (`push-cycle-cli.mjs cols --in a.json,b.json`).
- Limits: WebKit Sim is not iOS Safari; no phone and no Safari macOS in this task; the probe flag is in no preset; three pushes used.

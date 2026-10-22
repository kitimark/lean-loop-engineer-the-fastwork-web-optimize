---
id: 2026-10-22-hero-exit-threaded-measure
kind: note
title: "hero.exit:threaded on the WebKit Simulator lane: one script callback, one layout and one style pass fewer per step; Recalculate styles time relative to each arm's calm baseline is lower with the flag, absolute per-step times and frame cadence overlap"
status: draft
created: 2026-10-22
topics: [hero.exit, webkit, scroll-driven, threaded-animations, cost-counters, lag]
---

# hero.exit:threaded against the base, WebKit cost lane

Task `hero-exit-threaded-measure`, branch `ci/hero-exit-threaded-measure` (tip 34fcb69a, which has the landed variant).
Lane: `webkit-sim` dispatched with `lag=true cost=on target=rewrite vms=3`; the flag arm adds `fw=hero.exit:threaded`
(served as `?fw=hero.exit:threaded`). iPhone Simulator 430x775 at DPR 3 on a GitHub macOS runner, no real GPU. Each VM
records 2 passes; reduced with `lag/cli.mjs report` and `cost-report`. Zone "hero exit (scroll A)": 16 steps and 32 frames per
pass. Status words: MEASURED (run cited), INFERRED, CONFIRMED.

## 1. Runs

| arm | run | VMs with data | passes | note |
|---|---|---|---|---|
| base | 39739724461 | r1, r3 | 4 (cost ok in all) | r2 lost its page target, the Simulator was shut down (exit 4); rerun of the base arm after run 39731185714 |
| base (sensitivity) | 39731185714 | r3 | 2 | r2 same failure, r1 hit the job time limit without an artifact |
| flag `hero.exit:threaded` | 39731192687 | r1, r2, r3 | 6 (cost ok in all) | all three VMs succeeded |

3 of at most 4 dispatches used. The primary table is run 39739724461 against run 39731192687, so every cell has one run
id. Adding the 2 passes of run 39731185714 to the base (6 passes) changes no verdict (section 2, last column).

## 2. The hero-exit zone, per scroll step (mean of the per-pass values; range over passes)

"Separated" is the Lean verdict of the lag lane (`Fw.Measure.WebKitLag.verdict`: every pass of one arm on one side of every pass of the other), here on the per-step value.

| counter (per scroll step) | base | flag | verdict | with 6 base passes |
|---|---|---|---|---|
| requestAnimationFrame callbacks | 6.88 (6.88-6.88) | 5.88 (5.88-5.88) | flag lower | flag lower |
| Layout events | 7.80 (7.31-8.25) | 6.51 (6.25-6.75) | flag lower | flag lower |
| Recalculate styles events | 7.52 (7.06-7.94) | 6.46 (6.38-6.56) | flag lower | flag lower |
| Recalculate styles time (us) | 24064 (18308-31819) | 16469 (14274-19235) | overlap | overlap |
| Layout time (us) | 7718 (4579-10774) | 4662 (3632-5312) | overlap | overlap |
| FunctionCall events | 27.5 (21.7-33.8) | 21.9 (20.3-23.2) | overlap | overlap |
| Paint events | 17.9 (17.4-19.1) | 22.4 (19.1-26.9) | overlap | overlap |
| InvalidateLayout events | 7.95 | 5.95 | flag lower | not reduced |
| ScheduleStyleRecalculation events | 7.42 | 6.42 | flag lower | not reduced |
| FireAnimationFrame events | 6.69 | 5.75 | flag lower | not reduced |

Relative to each arm's own calm-scroll baseline (the same pass's calm steps; `lag/cli.mjs report`, Region A, ratio column; mean of the per-pass ratios, range over passes; "separated" is the Lean verdict on the ratio). The calm baselines are equal (Recalculate styles 12,735 us base, 12,935 us flag), so the lower ratio is a drop inside the zone (MEASURED, rerun on the artifacts of runs 39739724461 and 39731192687):

| counter | base ratio | flag ratio | verdict on the ratio |
|---|---|---|---|
| Recalculate styles time (us) | 1.89 (1.78-2.02) | 1.27 (1.15-1.54) | flag lower (separated) |
| FunctionCall time (us) | 1.55 (1.30-1.67) | 1.13 (0.99-1.28) | flag lower (separated) |
| Recalculate styles events | 1.16 (1.12-1.19) | 1.00 (0.99-1.02) | flag lower |
| ScheduleStyleRecalculation events | 1.18 (1.13-1.22) | 1.01 (1.00-1.03) | flag lower |
| Layout time (us) | 2.31 (1.76-2.65) | 1.81 (1.55-2.25) | overlap |
| InvalidateLayout events | 1.77 (1.41-1.97) | 1.42 (1.21-1.64) | overlap (the per-step value is lower, table above) |

The ratio of FireAnimationFrame is 0.99 against 1.00 (both arms' baselines fall with it); its per-step value is lower. Flag r3 alone, which ran on the same runner image as the base, gives the same separated verdicts (Recalculate styles us ratio 1.89 against 1.23, FunctionCall us 1.55 against 1.10, InvalidateLayout per step lower).

Page length: the scroll range maxY is 5231 px in the base and 5267 px in the flag arm, so the page is 36 px longer with the flag (possibly the IO sentinel; not explained here). The zone has 16 steps in both arms. Open item: check the length in the phone replay.

## 3. Cost counters of the same zone (cost passes, 32 frames per pass)

| counter | base | flag | verdict |
|---|---|---|---|
| skipped display slots per 100 frames | 78.9 (75.0-84.4) | 81.8 (68.8-87.5) | overlap |
| slots lost per 100 frames | 409 (228-566) | 251 (216-275) | overlap |
| frames over 50 ms per 100 frames | 43.8 (31.3-56.3) | 31.3 (25.0-37.5) | overlap |
| Paint per frame (us) | 2906 (2313-3391) | 2409 (2209-2556) | overlap |
| Composite per frame (us) | 56848 (34557-75519) | 37586 (32481-41750) | overlap |
| new layers per 100 layer-tree reads | 122.7 (112.5-128.1) | 116.2 (96.9-134.4) | overlap |
| resized layers per 100 reads | 88.3 (65.6-109.4) | 87.0 (78.1-106.3) | overlap |

Layer census (untimed, one value per session): compositing layers at scroll state 2 (y 388) base 118-122, flag 121-123 (overlap);
backing store base 51.6 MB, flag 54.5 MB in all three sessions (flag higher, +2.9 MB); state 1 (y 0) 52.2 against 53.5 MB.

## 4. Mechanism

- **Deterministic count drop (MEASURED, run 39739724461 against 39731192687).** The exit's `requestAnimationFrame`
  callback is one per step in the original path; the flag arm has exactly one fewer in all 6 passes (6.88 against 5.88 per
  step). With it the script's track-rect read goes: one Layout and one Recalculate styles event less per step (about 1.3
  and 1.1). These match the ledger mechanism: the variant removes the rAF script, the forced track-rect read and the inherited
  `--exit-opacity` restyle (INFERRED from the variant design in the ledger row; the counts are MEASURED here).
- **Why the absolute times overlap, the relative ones do not (INFERRED).** The remaining style events per step (6.46) equal the flag arm's own calm-scroll
  baseline (6.45 per step in the same runs), and the scroll-driven animations still restyle their targets once per rendering update on WebKit, also when
  accelerated (ledger note wktr-p1p4, MEASURED on WKTR). The saving is one event per step out of about 7, and the Simulator
  step times spread more than that (Recalculate styles 18-32 ms per step in the base against 14-19 ms with the flag), so the per-pass ranges of the absolute
  times overlap. Against each arm's own calm baseline the zone's Recalculate styles time is 1.89 against 1.27 and FunctionCall time 1.55 against 1.13, separated
  (section 2): the zone costs less over the calm scroll with the flag, and the absolute cells do not show it because the passes spread.
- **No new layers (MEASURED).** New and resized layers per read overlap; the layer count at scroll state 2 overlaps. The
  backing store is larger by about 3 MB, the resident cost of the animated layers.
- **Frame cadence (MEASURED, limit).** The Simulator has no real GPU and its frame cadence is host-bound (about 8 of 10
  frames follow a skipped display slot in both arms). The lane records interval histograms and slot counts, not frame percentiles of a phone.
  The cadence cells overlap, so this run does not say the exit is smoother or less smooth.
- **The breakpoint gate verdict on record:** trajectory probe run 39669915362, RED only on nodes whose rect is empty in
  every arm (note `10-2x-hero-exit-threaded.md`). The entrance window is covered by Lean `entrance_same` and the unit tests,
  not by this lane.

## 5. Result and lesson

- One script callback, one layout and one style pass fewer per step (counts MEASURED, deterministic; the attribution to the exit script is INFERRED).
  Recalculate styles time relative to each arm's calm baseline is lower with the flag (1.89 against 1.27, separated); absolute
  per-step times and frame cadence overlap. The layers do not grow, the backing store does (+2.9 MB). Recorded as a trade (ledger row 6 `hero.exit:threaded`, note
  `hero-exit-threaded-measure`).
- Lesson: read the zone against the same arm's calm baseline, not only as absolute cells: the baseline ratio separates where the spread of absolute Simulator
  step times hides one event out of seven. Frame cadence on a host-bound Simulator still says nothing about the feel. The check for
  "feels smoother" is the phone replay (follow-up, `docs/team/tools/device-replay.md`), with the pair that the variant needs: `scrollY`
  inside the exit range and a `getComputedStyle` sample of one consumer per frame.

## 6. Reproduce

    gh workflow run webkit-sim.yml --ref ci/hero-exit-threaded-measure -f lag=true -f target=rewrite -f vms=3 -f cost=on [-f fw=hero.exit:threaded] -f nonce=<n>
    node packages/measure-webkit/src/lag/cli.mjs cost-report --original <base r1,r3 json> --rewrite <flag r1,r2,r3 json>
    node packages/measure-webkit/src/lag/cli.mjs report --original <base json> --faithful <flag json>

Limits: no real GPU; one width (430); 4 base passes against 6 flag passes; base VM 2 failed twice (Simulator shut down after the inspector died), flag VM 2 ran;
runner images differ (base r1,r3 20261019.0289.1; flag r1,r2 20261012.0260.1, r3 20261019.0289.1); flag r3 alone against the base gives the same separated verdicts.
TS stand-ins: none added (the reduction is the existing lag code, `cost.mjs` replayed against the Lean golden).

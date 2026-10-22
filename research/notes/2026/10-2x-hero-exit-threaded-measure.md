---
id: 2026-10-22-hero-exit-threaded-measure
kind: note
title: "hero.exit:threaded on the WebKit Simulator lane: the exit script, its forced layout and a style pass are gone; frame cadence and times do not move"
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
- **Why the time does not follow (INFERRED).** The remaining style events per step (6.46) equal the flag arm's own calm-scroll
  baseline (6.45 per step in the same runs), and the scroll-driven animations still restyle their targets once per rendering update on WebKit, also when
  accelerated (ledger note wktr-p1p4, MEASURED on WKTR). The saving is one event per step out of about 7, and the Simulator
  step times spread more than that (Recalculate styles 18-32 ms per step in the base), so the per-pass ranges overlap.
- **No new layers (MEASURED).** New and resized layers per read overlap; the layer count at scroll state 2 overlaps. The
  backing store is larger by about 3 MB, the resident cost of the animated layers.
- **Frame cadence (MEASURED, limit).** The Simulator has no real GPU and its frame cadence is host-bound (about 8 of 10
  frames follow a skipped display slot in both arms). The lane records interval histograms and slot counts, not frame percentiles of a phone.
  The cadence cells overlap, so this run does not say the exit is smoother or less smooth.
- **The breakpoint gate verdict on record:** trajectory probe run 39669915362, RED only on nodes whose rect is empty in
  every arm (note `10-2x-hero-exit-threaded.md`). The entrance window is covered by Lean `entrance_same` and the unit tests,
  not by this lane.

## 5. Result and lesson

- A count win, no time win in this lane: the main-thread script and the events it forces are gone (deterministic), the layers
  do not grow, the backing store does. Frame cadence and times do not separate. Recorded as a trade (ledger row 6 `hero.exit:threaded`, note
  `hero-exit-threaded-measure`).
- Lesson: removing one event out of seven per step cannot show as time on a Simulator whose cadence is host-bound. The check for
  "feels smoother" is the phone replay (follow-up, `docs/team/tools/device-replay.md`), with the pair that the variant needs: `scrollY`
  inside the exit range and a `getComputedStyle` sample of one consumer per frame.

## 6. Reproduce

    gh workflow run webkit-sim.yml --ref ci/hero-exit-threaded-measure -f lag=true -f target=rewrite -f vms=3 -f cost=on [-f fw=hero.exit:threaded] -f nonce=<n>
    node packages/measure-webkit/src/lag/cli.mjs cost-report --original <base r1,r3 json> --rewrite <flag r1,r2,r3 json>
    node packages/measure-webkit/src/lag/cli.mjs report --original <base json> --faithful <flag json>

Limits: no real GPU; one width (430); 4 base passes against 6 flag passes; base VM 2 failed twice (Simulator shut down after the inspector died), flag VM 2 ran.
TS stand-ins: none added (the reduction is the existing lag code, `cost.mjs` replayed against the Lean golden).

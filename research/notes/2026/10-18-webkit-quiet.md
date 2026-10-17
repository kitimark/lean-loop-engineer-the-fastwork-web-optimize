---
id: 2026-10-18-webkit-quiet
kind: note
title: "WebKit Simulator count jitter on the free CI runner: host load or engine? (webkit-quiet, webkit-table-regen)"
status: draft
created: 2026-10-18
topics: [webkit, simulator, ci, determinism, measurement, host-load]
---

Question: the webkit-sim lane (free `xcode-27` runner, 3 vCPU) gave 57 deterministic / 11 stable / 36 quarantined rows at
host load ~970. Is the per-step jitter host load, or the engine/page? And which class table can `zone-baselines-webkit` use?

Status tags: MEASURED (CI run ids given; counts from the downloaded artifacts), CONFIRMED (code/proof), INFERRED (reading
of MEASURED data, not shown directly). Nothing here is phone time or a Mac run; the Simulator timings are runner-host time.

## Answer

- **Not CPU contention from other processes.** Adding 1, 3, 6 or 12 busy-loop processes on the runner did not lengthen the
  steps and did not raise any type's jitter (tables below). MEASURED, runs 39053364004 and 39055950094.
- **The runner is saturated by the Simulator itself** before any burner starts: `top` shows 0 % idle in every arm (57 % user,
  43 % sys), led by the Simulator's own services (SimMetalHost, WebKit GPU process, diagnosticd, backboardd). `loadavg`
  reads 400-950 and decays during a pass, so it is not a usable load stamp on this image. MEASURED (`v1-quiet.json`
  `host.top`, `v1-host.txt`). So "a quiet host" cannot be produced on this runner; the lowest load is the one we already have.
- **One type is wall-time driven: `TimerFire`.** Its pass total follows the pass wall time (r 0.93 in both quiet runs, 9 passes
  each) and dividing by wall time cuts its spread/mean from 0.22 to 0.10 (run 1) and 0.57 to 0.20 (run 2). Also repeated in
  both runs: `FunctionCall` (r 0.74, 0.77), `ObserverCallback` (0.86, 0.66), `FireAnimationFrame` (-0.69, -0.65); these rates
  do not help (per-second spread is larger than raw for all but TimerFire). MEASURED, n = 9 passes per run.
- **The rest (`RecalculateStyles`, `Layout`, `Paint`, `InvalidateLayout`) is not explained by load.** Their correlation with
  pass wall time flips between the two runs (Layout -0.15 then 0.70, Paint 0.59 then -0.15), the jitter is the same at 0 and
  12 burners, it stays in the fastest steps, it is not conserved between neighbouring steps (window sums grow at least like
  sqrt(w) times the step jitter, so a count does not just move to the next step), and the census at rest (y = 0, no scroll)
  is already quarantined for `layerCount` in all three sessions. INFERRED: page/engine asynchrony (lazy content,
  compositing decisions), not CPU starvation.
- **The quiet-step rule is proved but does not improve the table.** Keeping only steps below a duration limit L in every pass
  leaves per-step classes unchanged down to L = 160 ms (32 of 106 steps kept) and the whole-run totals get worse (relative
  spread grows as steps are dropped: Layout 0.08 at L = inf, 0.22 at L = 130). So the rule is not a fix; it stays as a
  diagnostic (below). MEASURED on run 39053364004.

## Dose-response (quiet command, one Simulator session each, arms rotated per round, 3 rounds)

Burners = `yes` processes started for the scroll only. Jitter = mean over steps of (max - min) over the passes of the same
arm. Median step = distance between consecutive step marks (nominal 2 rAF = 33 ms).

| run | burners | passes | median step ms | p90 step ms | top idle % | Layout | Paint | InvalidateLayout | TimerFire | FunctionCall |
|---|---|---|---|---|---|---|---|---|---|---|
| 39053364004 | 0 | 3 | 130 | 299 | 0 | 1.84 | 3.82 | 2.04 | 1.36 | 1.66 |
| | 1 | 3 | 153 | 309 | 0 | 1.89 | 3.18 | 1.88 | 1.22 | 1.61 |
| | 3 | 3 | 131 | 332 | 0 | 1.68 | 3.24 | 1.78 | 1.70 | 1.93 |
| 39055950094 | 0 | 3 | 161 | 365 | 0 | 2.11 | 4.08 | 2.41 | 1.85 | 2.27 |
| | 6 | 3 | 142 | 287 | 0 | 1.71 | 3.94 | 1.96 | 1.47 | 1.77 |
| | 12 | 3 | 135 | 271 | 0 | 1.95 | 3.89 | 1.99 | 1.34 | 1.83 |

No dose-response: more burners do not make steps slower (the later arms are slightly faster, an order/warm-up effect, not
load). The harness timer lag (Node event loop on the runner, 20 ms ticks) is uncorrelated with the counts (|r| <= 0.04), so
it only tells us the harness itself is not starved; it is kept in `scroll.lag`. Steps are 4-5 times the nominal 33 ms
at every load, so the step duration, not the load stamp, is the per-step proxy.

## WebKit class table (webkit-table-regen): 3 independent CI sessions

Sessions: 39048376821, 39050061299 and 39055837084, each one VM, 2 fresh-load passes after 1 discarded warm-up load
(`--warmup 1` is the default). Class = worst of sessions; letters in brackets are the per-session classes
(D deterministic, S stable, Q quarantined; policy of `reduce.mjs` TOL: step abs 1, zone abs 2 / 10 %, total abs 2 / 5 %).
Machine-readable: `packages/measure-webkit/classes/webkit-sim-v1.json` (`fw.webkit.classes/1`, with the worst spread per row).

| count type | whole run | per 500 px zone | per step |
|---|---|---|---|
| RecalculateStyles | S (SSS) | Q | Q |
| Layout | Q (SSQ) | Q | Q |
| Paint | Q (SSQ) | Q | Q |
| Composite | S (DSD) | S (DSD) | Q (DQD) |
| RenderingFrame | D | D | Q (DQD) |
| FireAnimationFrame | S | Q | Q |
| TimerFire | Q | Q | Q |
| ObserverCallback | Q (SSQ) | Q | Q |
| EventDispatch | S (DSD) | S (DSD) | Q (DQD) |
| FunctionCall | Q (SQS) | Q | Q |
| ScheduleStyleRecalculation | S | Q (SQS) | Q |
| InvalidateLayout | Q (QSQ) | Q | Q |
| paintArea | Q (SQQ) | Q | Q |

All 104 rows (census and seek included): 49 deterministic, 9 stable, 46 quarantined. The two sessions of the earlier read
(57 / 11 / 36) were the more favourable pair; a third session worsens the tally to 49 / 9 / 46, which is what the
worst-of-sessions rule is for. Usable for per-zone baselines today: `RenderingFrame` (D), `Composite` and `EventDispatch`
(S). Everything else is quarantined at the zone tolerance: a zone of ~10 steps sums ~10 independent
step jitters (window-sum growth above), so the 10 % zone tolerance is too tight for `Layout` (zone mean ~60, spread ~13 over 9 passes).

## What `zone-baselines-webkit` should do with this (INFERRED)

1. Treat `RenderingFrame`, `Composite`, `EventDispatch` as gateable; report the rest as findings with a measured noise band
   (`maxSpread`/`maxRelSpread` in the JSON), and compare A vs R only on drift beyond that band.
2. Compare `TimerFire` only through the existing timer-hold mode (`--mode hold`, README "holding timers"), or per second of
   pass wall time; never raw.
3. Run baselines on separate VMs (a session is 19-24 min; 2 passes per session) and keep the worst-of-sessions rule.

## The Lean rule and its wiring (CONFIRMED)

`lean/Fw/Measure/Quiet.lean`: a step is quiet when its duration is at most L in every pass (over the shortest pass);
`classifyQuiet` classes the series restricted to quiet steps; `verdict` is `none` below `minKept`. Proved (`lake build`, no
`sorry`): membership iff, monotone in L, `restrict` = reading cells at indices, `classifyCells_restrict` (cell classes of
restricted series are the cell classes at the indices), `classifyCells_restrict_mono` and `classifyQuiet_mono` (keeping
fewer steps never makes the class stricter; a bigger L never makes it laxer), `classifyQuiet_le` and `classifyQuiet_all`
(the class over quiet steps is at most the class over all steps; with L large enough it is the class over all steps).
Wire op `measure.quietSteps` (`Fw/Measure/Wire.lean`), goldens `packages/contracts/golden/measure/measure.quietSteps.jsonl`,
TS stand-in `packages/measure-webkit/src/quietsteps.mjs` checked against them in `test/fwcore.test.mjs`. The measured result
above says the rule gives no better table; it is kept so a quieter runner (or a phone) can use it without new Lean.

## Caveats

- n = 9 passes per quiet run, 2 passes per determinism session; correlations are indicative (INFERRED), the flat
  dose-response and the census-at-rest result are the strong evidence.
- The runner image, CPU and Simulator build are the ones recorded in `runner.json` of each run; another image can differ.
- Sessions 1 and 2 predate the host-monitor instrumentation (same counting code); only the third has load stamps.
- `sessions=2` per VM and a single-VM comparison with Safari kept running are not covered here.

## Reproduce

`gh workflow run webkit-sim.yml --ref <branch> -f experiment=quiet -f arms=0,6,12 -f reps=3` then
`node packages/measure-webkit/src/cli.mjs quiet-report <v1-quiet.json>`; classes:
`node packages/measure-webkit/src/cli.mjs merge <session.json>... --out classes.json`.

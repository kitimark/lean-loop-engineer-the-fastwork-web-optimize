# Smoothness on WebKit: what the engine computes in the two lag windows, original against the rewrite

Question (user, 2026-10-21): "the lag happens on WebKit; Chromium is optimized fine" and "we can use CI to analyze the computation
process (events)". `smoothness-probe` measured Chromium only. This task measures WebKit on CI, on two legs, and puts the
per-zone computation events first and the frame cadence second.

Every number below is MEASURED (the generated tables, filled from `results/smoothness-webkit/`) unless it says INFERRED. The
absolute times come from CI virtual machines under heavy host load (the sim host reported load averages above 600 on 3 CPUs in `host.txt`), not from the phone
GPU; they rank arms against each other and are not the phone's frame times (comparison with the phone is task `ci-device-accuracy`).

## Answer

- **Hero exit (hero -> people), original against faithful rewrite: the original does about 3.5 times the render work per frame
  and 20 times the layout time, in the same number of layouts.** macOS Playwright WebKit, three CI jobs, 18 windows per arm: render
  work per frame 815 ms (original) against 238 ms (rewrite) and 272 ms (A/A copy of the rewrite); `Layout` is 161 records for
  2457 ms (original) against 157 records for 115 ms (rewrite). Lean's per-job zone verdict says the rewrite does less work per
  frame in 3 of 3 jobs, and the rewrite against its own A/A copy says same. The cadence agrees: 48 frames over 60 ms
  per rep (original) against 7 (rewrite) and 7 (A/A).
- **On the iOS Simulator (Mobile Safari, iOS 27.0) the original barely renders the hero window.** It delivers 1 to 7 frames per
  window (median 2 to 3) against 10 to 33 for the rewrite, and one task of 2.3 s sits in the zone (`TimerFire` 5 records for 2349 ms).
  The per-job Lean verdict there is `insufficient` for original against rewrite: only 6 of 14 original windows put a frame in the hero zone,
  at most 3 in one job, below the 5 the rule asks per job. This is a gap, stated, not hidden (see Gaps).
- **End-of-page morph: original and rewrite are the same on both legs.** Zone `finish`, macOS: render work per frame 73 ms (original),
  126 ms (rewrite), 101 ms (A/A), 146 ms (look-change); all pairs `same` in 3 of 3 jobs; frames over 60 ms per window 16, 12, 12, 10.
  The window is paint-bound in every arm: 1745 to 1928 `Paint` records over 45 to 51 frames (about 40 per frame) against about 105 `Layout`.
  On iOS: 420 to 516 `Paint` records over 6 to 7 frames, render work per frame 235 to 294 ms, all pairs `same` or `insufficient`.
  So the rewrite does not remove the end-of-page morph work that the original has, on either engine configuration measured here (INFERRED
  cause: the morph repaints a large area per frame; the events show the paint count, not the area).
- **Look-change arm (`?fw=morph.tween:scroll-lock,nav:earn-no-transition`) is the same as the rewrite in both windows**: base against look is
  `same` in every zone and window on macOS (3 of 3 jobs) and on iOS.
- **`RenderingFrame` records are absent** in Playwright WebKit 27.2 and in iOS 27.0 (0 records in every table); the per-frame work comes from the
  `Layout`, `Paint`, `Composite` and `RecalculateStyles` records that no render record encloses (Lean `renderWork`).
- **CI cost.** macOS leg 10.4 min median, 11.2 longest (billed 33 min over 3 jobs); iOS Simulator leg 34.1 median, 34.2 longest (billed 100 min
  over 3 jobs). Both ran under `max-parallel 1`, cap rows `smoothness-webkit-mac` 26 min and `smoothness-webkit-sim` 65 min in `Fw.Ci.Pool.Caps`
  (thin: 3 successes each).

## Method

- Legs: (1) Playwright WebKit 27.2 on `macos-26` (macOS 26.6.2, Apple M1 virtual, width 390), one browser for all arms; (2) iOS Simulator
  `fw-iphone-27`, runtime iOS 27.0 (24A434), Xcode 27.0 on `xcode-27` (macOS 27.0.1, image 20261019.0289.1), Mobile Safari at width 430
  through the Web Inspector of the simulator. Both are glue around Lean `Fw.Measure.WebKitProfile` (records put on the page clock, binned into the
  device recorder's zones `hero`, `finish`, `rest` of `Fw.Device.Session`; golden `packages/contracts/golden/measure/webkit-profile.jsonl`).
- Zones: `hero` = the first two viewports (hero -> people), `finish` = the last viewport (end-of-page morph), `rest` = between. The hero window
  scrolls 60 wheel steps of 42 px every 16 ms plus a 600 ms tail; the end window pushes 120 px then holds 1 s.
- Arms by resolved flags, never by preset name: `orig` (the snapshot), `base` (the faithful rewrite), `aa` (a second server of the rewrite, the
  control), `look` (flags `morph.tween:scroll-lock` and `nav:earn-no-transition`). The v2 arm was dropped by Lean's dedup: its resolved flags are
  empty, equal to the rewrite's. Arms interleave per rep and rotate order. One job runs all arms. No CircleCI.
- Event reps run with the Timeline on, cadence reps without it (the Timeline slows the page); both are reported. The macOS leg has 6 event reps and 5
  cadence reps per arm per window per job; the iOS leg 5 event reps per job (cadence is read from the same windows, Timeline on).
- Runs (workflow `smoothness.yml`, branch `ci/smoothness-webkit-cadence`, jobs `webkit-mac` and `webkit-sim`, run only on `[webkit-cadence]`):
  39612238445 (03941815), 39617081415 (bda5a6a7, same leg code), 39624728525 (b7948d65, same leg code). Runs 39617051910 (2829754c) and
  39623909805 (ce2b60e6) produced no data (the first skipped every job; the second was refused by the line parser: the `diagnostic` word is not
  accepted by this lane). Raw leg files: `results/smoothness-webkit/runs/`; tables regenerate with
  `node packages/measure-webkit/src/profile/cli.mjs report --runs results/smoothness-webkit/runs --out results/smoothness-webkit --jobs results/smoothness-webkit/jobs --note research/notes/2026/10-2x-smoothness-webkit.md`.
- Verdict: Lean `zoneVerdict` per job on the render work per frame of the window, against the A/A pair, then Lean `across` over jobs (two thirds must
  agree, none may disagree, at least 3 jobs; a frame over 60 ms is a hitch). Counts per zone and arm (deterministic, stable, quarantined, Fw.Measure.Classes) are in the class tables.

## Jobs

<!-- gen:runs -->
| job | leg | engine | version / runtime | arms | dropped by flags | windows | kept | refused (reason) | wall s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39612238445:smoothness-webkit-mac | mac | playwright-webkit | 27.2 | orig, base, aa, look | v2 = rewrite | 48 | 48 | 0 | 523 |
| 39612238445:smoothness-webkit-sim | sim | mobile-safari | com.apple.CoreSimulator.SimRuntime.iOS-27-0 | orig, base, aa, look | v2 = rewrite | 40 | 40 | 0 | 1546 |
| 39617081415:smoothness-webkit-mac | mac | playwright-webkit | 27.2 | orig, base, aa, look | v2 = rewrite | 48 | 48 | 0 | 615 |
| 39617081415:smoothness-webkit-sim | sim | mobile-safari | com.apple.CoreSimulator.SimRuntime.iOS-27-0 | orig, base, aa, look | v2 = rewrite | 40 | 40 | 0 | 1343 |
| 39624728525:smoothness-webkit-mac | mac | playwright-webkit | 27.2 | orig, base, aa, look | v2 = rewrite | 48 | 48 | 0 | 577 |
| 39624728525:smoothness-webkit-sim | sim | mobile-safari | com.apple.CoreSimulator.SimRuntime.iOS-27-0 | orig, base, aa, look | v2 = rewrite | 29 | 29 | 0 | 1754 |
<!-- /gen:runs -->

## macOS Playwright WebKit (leg 1)

Render work per frame (microseconds, median over windows, range), and the number of records per kind per window:

<!-- gen:mac-headline -->
**hero**

| arm | jobs | windows | frames | render us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 3 | 18 | 76 | 814926 (586461-1107032) | 213 | 161 | 451 | 76 | 447 | 306 |
| base | 3 | 18 | 82 | 237815 (151881-448718) | 219 | 157 | 449 | 82 | 746 | 308 |
| aa | 3 | 18 | 80 | 271786 (120151-487064) | 217 | 161 | 468 | 80 | 752 | 308 |
| look | 3 | 18 | 76 | 255779 (69405-454162) | 208 | 153 | 434 | 76 | 723 | 299 |

**finish**

| arm | jobs | windows | frames | render us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 3 | 18 | 45 | 72621 (36333-148317) | 128 | 111 | 1745 | 45 | 92 | 80 |
| base | 3 | 18 | 48 | 125674 (32916-229473) | 122 | 102 | 1913 | 48 | 312 | 74 |
| aa | 3 | 18 | 50 | 100742 (36412-206491) | 125 | 107 | 1838 | 50 | 319 | 76 |
| look | 3 | 18 | 51 | 145799 (52744-170181) | 134 | 99 | 1928 | 51 | 253 | 79 |

**rest**

| arm | jobs | windows | frames | render us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 3 | 18 | 66 | 166742 (67295-306276) | 132 | 118 | 177 | 66 | 295 | 210 |
| base | 3 | 18 | 67 | 58579 (16231-113526) | 131 | 116 | 173 | 67 | 374 | 178 |
| aa | 3 | 18 | 71 | 71182 (15180-94198) | 124 | 107 | 144 | 71 | 387 | 183 |
| look | 3 | 18 | 70 | 75297 (18365-93935) | 135 | 117 | 184 | 70 | 378 | 183 |

<!-- /gen:mac-headline -->

Lean verdict per zone and pair (first = left arm of the pair; `second` means the second arm does less work per frame):

<!-- gen:mac-verdict -->
| zone | pair (first, second) | jobs | first | second | same | insufficient | verdict over jobs |
| --- | --- | --- | --- | --- | --- | --- | --- |
| hero | orig, base | 3 | 0 | 3 | 0 | 0 | second |
| hero | base, look | 3 | 0 | 0 | 3 | 0 | same |
| hero | orig, look | 3 | 0 | 3 | 0 | 0 | second |
| finish | orig, base | 3 | 0 | 0 | 3 | 0 | same |
| finish | base, look | 3 | 0 | 0 | 3 | 0 | same |
| finish | orig, look | 3 | 0 | 0 | 3 | 0 | same |
| rest | orig, base | 3 | 0 | 2 | 1 | 0 | second |
| rest | base, look | 3 | 0 | 0 | 3 | 0 | same |
| rest | orig, look | 3 | 0 | 2 | 1 | 0 | second |
<!-- /gen:mac-verdict -->

Count classes per zone and arm:

<!-- gen:mac-class -->
| zone | arm | jobs | deterministic | stable | quarantined |
| --- | --- | --- | --- | --- | --- |
| hero | orig | 3 | 2 | 8 | 1 |
| hero | base | 3 | 3 | 5 | 3 |
| hero | aa | 3 | 3 | 3 | 5 |
| hero | look | 3 | 4 | 4 | 3 |
| finish | orig | 3 | 4 | 6 | 1 |
| finish | base | 3 | 3 | 6 | 2 |
| finish | aa | 3 | 3 | 5 | 3 |
| finish | look | 3 | 3 | 4 | 4 |
| rest | orig | 3 | 2 | 9 | 0 |
| rest | base | 3 | 3 | 7 | 1 |
| rest | aa | 3 | 3 | 7 | 1 |
| rest | look | 3 | 3 | 6 | 2 |
<!-- /gen:mac-class -->

Records per kind, count and summed duration per window. `Composite` durations are a wait for the compositing flush as WebKit records it
(INFERRED); they are large on this host and are compared between arms only:

<!-- gen:mac-kinds -->
**hero** (median count / median summed ms per window)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| RecalculateStyles | 213 / 443.73 | 219 / 462.55 | 217 / 459.46 | 208 / 446.88 |
| Layout | 161 / 2456.59 | 157 / 114.80 | 161 / 114.90 | 153 / 107.82 |
| Paint | 451 / 105.03 | 449 / 128.73 | 468 / 144.89 | 434 / 125.70 |
| Composite | 76 / 55617.74 | 82 / 17008.08 | 80 / 22132.94 | 76 / 19915.16 |
| FunctionCall | 447 / 2218.16 | 746 / 543.80 | 752 / 493.69 | 723 / 495.65 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 35 / 18.74 | 8 / 3.69 | 10 / 3.50 | 8 / 3.38 |
| FireAnimationFrame | 306 / 2090.71 | 308 / 486.14 | 308 / 442.59 | 299 / 432.60 |
| EventDispatch | 76 / 7.04 | 509 / 59.90 | 532 / 53.06 | 501 / 53.17 |
| ObserverCallback | 33 / 113.32 | 12 / 8.10 | 12 / 8.01 | 12 / 7.60 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

**finish** (median count / median summed ms per window)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| RecalculateStyles | 128 / 419.86 | 122 / 397.27 | 125 / 382.89 | 134 / 402.94 |
| Layout | 111 / 764.48 | 102 / 67.39 | 107 / 67.10 | 99 / 65.77 |
| Paint | 1745 / 124.02 | 1913 / 125.45 | 1838 / 128.09 | 1928 / 127.96 |
| Composite | 45 / 1989.84 | 48 / 5532.99 | 50 / 4760.03 | 51 / 7281.32 |
| FunctionCall | 92 / 890.30 | 312 / 157.69 | 319 / 153.24 | 253 / 155.55 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 5 / 0.25 | 4 / 0.36 | 4 / 0.50 | 4 / 0.36 |
| FireAnimationFrame | 80 / 889.86 | 74 / 151.03 | 76 / 145.50 | 79 / 146.35 |
| EventDispatch | 4 / 0.77 | 188 / 8.31 | 190 / 8.03 | 124 / 6.48 |
| ObserverCallback | 6 / 0.12 | 48 / 2.55 | 48 / 2.96 | 50 / 3.07 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

**rest** (median count / median summed ms per window)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| RecalculateStyles | 132 / 297.96 | 131 / 219.27 | 124 / 243.89 | 135 / 239.83 |
| Layout | 118 / 1915.09 | 116 / 48.50 | 107 / 47.93 | 117 / 54.09 |
| Paint | 177 / 21.61 | 173 / 26.38 | 144 / 23.94 | 184 / 26.00 |
| Composite | 66 / 8708.18 | 67 / 3713.13 | 71 / 4534.42 | 70 / 4953.42 |
| FunctionCall | 295 / 1859.34 | 374 / 291.82 | 387 / 309.97 | 378 / 304.21 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 19 / 7.63 | 5 / 0.59 | 5 / 0.86 | 5 / 0.85 |
| FireAnimationFrame | 210 / 1846.59 | 178 / 277.25 | 183 / 291.32 | 183 / 289.41 |
| EventDispatch | 73 / 5.10 | 247 / 16.78 | 256 / 17.49 | 244 / 16.83 |
| ObserverCallback | 14 / 1.52 | 6 / 1.15 | 6 / 1.28 | 6 / 1.16 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

<!-- /gen:mac-kinds -->

Cadence (secondary), `timeline on` = the event reps, `off` = the cadence reps:

<!-- gen:mac-cadence -->
| window | timeline | arm | jobs | reps | hitches per rep (median) | p50 ms | p95 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hero | on | orig | 3 | 18 | 48 | 26.0 | 141.0 | 575.0 |
| hero | on | base | 3 | 18 | 7 | 17.0 | 55.0 | 205.0 |
| hero | on | aa | 3 | 18 | 7 | 17.0 | 61.0 | 198.0 |
| hero | on | look | 3 | 18 | 6 | 17.0 | 56.0 | 180.0 |
| hero | off | orig | 3 | 15 | 34 | 34.0 | 128.0 | 286.0 |
| hero | off | base | 3 | 15 | 6 | 17.0 | 60.0 | 186.0 |
| hero | off | aa | 3 | 15 | 7 | 17.0 | 64.0 | 226.0 |
| hero | off | look | 3 | 15 | 7 | 17.0 | 65.0 | 189.0 |
| end | on | orig | 3 | 18 | 16 | 49.0 | 106.0 | 222.0 |
| end | on | base | 3 | 18 | 12 | 33.0 | 116.0 | 290.0 |
| end | on | aa | 3 | 18 | 12 | 32.0 | 104.0 | 193.0 |
| end | on | look | 3 | 18 | 10 | 32.0 | 112.0 | 197.0 |
| end | off | orig | 3 | 15 | 10 | 33.0 | 99.0 | 260.0 |
| end | off | base | 3 | 15 | 7 | 25.0 | 88.0 | 220.0 |
| end | off | aa | 3 | 15 | 9 | 25.0 | 79.0 | 451.0 |
| end | off | look | 3 | 15 | 8 | 24.0 | 92.0 | 345.0 |
<!-- /gen:mac-cadence -->

<!-- gen:mac-cadence-verdict -->
| window | timeline | pair (first, second) | jobs | first | second | same | insufficient | verdict over jobs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hero | on | orig, base | 3 | 0 | 3 | 0 | 0 | second |
| hero | on | base, look | 3 | 0 | 0 | 3 | 0 | same |
| hero | on | orig, look | 3 | 0 | 3 | 0 | 0 | second |
| hero | off | orig, base | 3 | 0 | 3 | 0 | 0 | second |
| hero | off | base, look | 3 | 0 | 0 | 3 | 0 | same |
| hero | off | orig, look | 3 | 0 | 3 | 0 | 0 | second |
| end | on | orig, base | 3 | 0 | 0 | 3 | 0 | same |
| end | on | base, look | 3 | 0 | 0 | 3 | 0 | same |
| end | on | orig, look | 3 | 0 | 0 | 3 | 0 | same |
| end | off | orig, base | 3 | 0 | 0 | 3 | 0 | same |
| end | off | base, look | 3 | 0 | 0 | 3 | 0 | same |
| end | off | orig, look | 3 | 0 | 0 | 3 | 0 | same |
<!-- /gen:mac-cadence-verdict -->

## iOS Simulator (leg 2)

<!-- gen:sim-headline -->
**hero**

| arm | jobs | windows | frames | render us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 3 | 6 | 2 | 2602515 (989380-2846850) | 9 | 67 | 45 | 2 | 16 | 7 |
| base | 3 | 14 | 8 | 120551 (42012-203945) | 38 | 84 | 111 | 8 | 185 | 46 |
| aa | 3 | 13 | 8 | 108092 (54495-521063) | 33 | 81 | 110 | 8 | 160 | 37 |
| look | 3 | 14 | 8 | 131484 (39006-277816) | 34 | 84 | 106 | 8 | 174 | 37 |

**finish**

| arm | jobs | windows | frames | render us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 3 | 14 | 6 | 293618 (113906-489115) | 25 | 28 | 420 | 6 | 26 | 18 |
| base | 3 | 13 | 6 | 273250 (156115-540520) | 23 | 24 | 421 | 6 | 96 | 14 |
| aa | 3 | 13 | 7 | 237862 (112781-309601) | 23 | 25 | 500 | 7 | 140 | 17 |
| look | 3 | 14 | 7 | 235245 (95642-439767) | 25 | 25 | 516 | 7 | 110 | 15 |

**rest**

| arm | jobs | windows | frames | render us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 3 | 13 | 2 | 1338760 (162885-3490060) | 21 | 79 | 49 | 2 | 36 | 16 |
| base | 3 | 14 | 4 | 121980 (29940-369590) | 33 | 42 | 94 | 4 | 116 | 29 |
| aa | 3 | 12 | 7 | 136850 (23920-294026) | 35 | 49 | 113 | 7 | 171 | 34 |
| look | 3 | 14 | 8 | 125412 (29574-774450) | 38 | 39 | 99 | 8 | 139 | 39 |

<!-- /gen:sim-headline -->

<!-- gen:sim-verdict -->
| zone | pair (first, second) | jobs | first | second | same | insufficient | verdict over jobs |
| --- | --- | --- | --- | --- | --- | --- | --- |
| hero | orig, base | 3 | 0 | 0 | 0 | 3 | same |
| hero | base, look | 3 | 0 | 0 | 2 | 1 | same |
| hero | orig, look | 3 | 0 | 0 | 0 | 3 | same |
| finish | orig, base | 3 | 0 | 0 | 2 | 1 | same |
| finish | base, look | 3 | 0 | 0 | 2 | 1 | same |
| finish | orig, look | 3 | 0 | 1 | 1 | 1 | same |
| rest | orig, base | 3 | 0 | 1 | 0 | 2 | same |
| rest | base, look | 3 | 0 | 0 | 1 | 2 | same |
| rest | orig, look | 3 | 0 | 1 | 0 | 2 | same |
<!-- /gen:sim-verdict -->

<!-- gen:sim-class -->
| zone | arm | jobs | deterministic | stable | quarantined |
| --- | --- | --- | --- | --- | --- |
| hero | orig | 3 | 2 | 9 | 0 |
| hero | base | 3 | 2 | 9 | 0 |
| hero | aa | 3 | 4 | 7 | 0 |
| hero | look | 3 | 2 | 8 | 1 |
| finish | orig | 3 | 5 | 5 | 1 |
| finish | base | 3 | 3 | 5 | 3 |
| finish | aa | 3 | 3 | 6 | 2 |
| finish | look | 3 | 3 | 5 | 3 |
| rest | orig | 3 | 6 | 4 | 1 |
| rest | base | 3 | 2 | 6 | 3 |
| rest | aa | 3 | 2 | 8 | 1 |
| rest | look | 3 | 2 | 4 | 5 |
<!-- /gen:sim-class -->

<!-- gen:sim-kinds -->
**hero** (median count / median summed ms per window)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| RecalculateStyles | 9 / 21.08 | 38 / 81.95 | 33 / 75.50 | 34 / 83.54 |
| Layout | 67 / 2534.81 | 84 / 55.36 | 81 / 44.37 | 84 / 58.45 |
| Paint | 45 / 2.98 | 111 / 70.15 | 110 / 56.86 | 106 / 49.55 |
| Composite | 2 / 2595.92 | 8 / 709.34 | 8 / 653.00 | 8 / 724.97 |
| FunctionCall | 16 / 2373.82 | 185 / 250.36 | 160 / 215.86 | 174 / 247.50 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 5 / 2349.21 | 52 / 137.01 | 49 / 115.93 | 53 / 142.39 |
| FireAnimationFrame | 7 / 40.27 | 46 / 102.02 | 37 / 91.24 | 37 / 95.56 |
| EventDispatch | 2 / 0.24 | 117 / 8.49 | 92 / 6.06 | 99 / 7.40 |
| ObserverCallback | 2 / 0.72 | 7 / 3.45 | 7 / 1.98 | 7 / 3.98 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

**finish** (median count / median summed ms per window)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| RecalculateStyles | 25 / 129.12 | 23 / 135.95 | 23 / 138.22 | 25 / 112.80 |
| Layout | 28 / 499.51 | 24 / 33.40 | 25 / 23.53 | 25 / 20.45 |
| Paint | 420 / 38.27 | 421 / 37.44 | 500 / 38.35 | 516 / 38.07 |
| Composite | 6 / 1214.02 | 6 / 1471.03 | 7 / 1526.07 | 7 / 1452.50 |
| FunctionCall | 26 / 539.41 | 96 / 40.10 | 140 / 45.58 | 110 / 42.16 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 6 / 3.02 | 6 / 2.99 | 6 / 3.28 | 6 / 3.03 |
| FireAnimationFrame | 18 / 535.75 | 14 / 24.80 | 17 / 30.52 | 15 / 32.10 |
| EventDispatch | 4 / 1.71 | 86 / 6.30 | 115 / 6.43 | 80 / 5.32 |
| ObserverCallback | 0 / 0.00 | 10 / 1.82 | 12 / 1.51 | 12 / 1.73 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

**rest** (median count / median summed ms per window)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| RecalculateStyles | 21 / 134.71 | 33 / 118.57 | 35 / 96.99 | 38 / 139.39 |
| Layout | 79 / 2219.83 | 42 / 45.84 | 49 / 43.04 | 39 / 57.41 |
| Paint | 49 / 13.40 | 94 / 21.72 | 113 / 30.20 | 99 / 22.62 |
| Composite | 2 / 261.88 | 4 / 458.30 | 7 / 460.11 | 8 / 429.40 |
| FunctionCall | 36 / 2255.01 | 116 / 105.76 | 171 / 99.18 | 139 / 116.57 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 3 / 1930.84 | 7 / 6.02 | 11 / 19.64 | 5 / 16.20 |
| FireAnimationFrame | 16 / 175.57 | 29 / 60.65 | 34 / 48.79 | 39 / 60.50 |
| EventDispatch | 1 / 0.13 | 89 / 26.13 | 139 / 21.56 | 116 / 27.55 |
| ObserverCallback | 12 / 87.41 | 8 / 6.08 | 9 / 5.48 | 8 / 5.76 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

<!-- /gen:sim-kinds -->

<!-- gen:sim-cadence -->
| window | timeline | arm | jobs | reps | hitches per rep (median) | p50 ms | p95 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hero | on | orig | 3 | 14 | 1 | 335.0 | 2447.0 | 2700.0 |
| hero | on | base | 3 | 14 | 7 | 29.0 | 332.0 | 628.0 |
| hero | on | aa | 3 | 13 | 7 | 34.0 | 324.0 | 430.0 |
| hero | on | look | 3 | 14 | 7 | 38.0 | 291.0 | 687.0 |
| end | on | orig | 3 | 14 | 5 | 354.0 | 575.0 | 664.0 |
| end | on | base | 3 | 13 | 5 | 316.0 | 605.0 | 763.0 |
| end | on | aa | 3 | 13 | 6 | 328.0 | 502.0 | 598.0 |
| end | on | look | 3 | 14 | 7 | 244.0 | 499.0 | 535.0 |
<!-- /gen:sim-cadence -->

<!-- gen:sim-cadence-verdict -->
| window | timeline | pair (first, second) | jobs | first | second | same | insufficient | verdict over jobs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hero | on | orig, base | 3 | 1 | 0 | 1 | 1 | same |
| hero | on | base, look | 3 | 0 | 0 | 2 | 1 | same |
| hero | on | orig, look | 3 | 1 | 0 | 1 | 1 | same |
| end | on | orig, base | 3 | 0 | 0 | 2 | 1 | same |
| end | on | base, look | 3 | 0 | 0 | 2 | 1 | same |
| end | on | orig, look | 3 | 1 | 0 | 1 | 1 | same |
<!-- /gen:sim-cadence-verdict -->

## Job minutes

<!-- gen:minutes -->
| run | leg | job | result | wall min | billed min |
| --- | --- | --- | --- | --- | --- |
| 39612238445 | mac | webkit mac (playwright-webkit, macos-26) | success | 9.4 | 10 |
| 39612238445 | sim | webkit sim (mobile safari, xcode-27) | success | 34.1 | 35 |
| 39617081415 | mac | webkit mac (playwright-webkit, macos-26) | success | 11.2 | 12 |
| 39617081415 | sim | webkit sim (mobile safari, xcode-27) | success | 29.1 | 30 |
| 39624728525 | mac | webkit mac (playwright-webkit, macos-26) | success | 10.4 | 11 |
| 39624728525 | sim | webkit sim (mobile safari, xcode-27) | success | 34.2 | 35 |
| median of successes | mac |  | n=3 | 10.4 |  |
| longest success | mac |  |  | 11.2 |  |
| all jobs billed | mac |  | n=3 |  | 33 |
| median of successes | sim |  | n=3 | 34.1 |  |
| longest success | sim |  |  | 34.2 |  |
| all jobs billed | sim |  | n=3 |  | 100 |
<!-- /gen:minutes -->

## What the events say about the two lag windows

Hero exit (zone `hero`, window `hero`):

- The counts of style recalculation and layout are the same in the original and the rewrite (macOS: 213 against 219 style records, 161 against 157 layouts).
  The cost per record is not: 15 ms per layout in the original, 0.7 ms in the rewrite. So the original's lag in this window is expensive layouts
  (INFERRED: forced reflow of a large tree each frame; the Timeline gives no call stack), not more of them.
- The original runs fewer script calls but each is longer: `FunctionCall` 447 records for 2218 ms against 746 for 544 ms; `FireAnimationFrame` 2091 ms against 486 ms.
  The rewrite dispatches many more events (`EventDispatch` 509 against 76) at 0.1 ms each.
- On iOS the original's hero zone holds 2 frames and about 2.5 s of layout and one 2.3 s timer task per window; the rewrite holds 8 frames and
  55 ms of layout.
- The cadence hitch count undercounts the original on iOS (1 per rep against 7 for the rewrite): a window of 2 frames has no room to hitch.
  The p50 (335 ms against 29 ms) and p95 (2447 ms against 332 ms) of the frame intervals show it.
- Look-change flags: no difference from the rewrite in any table of this window.

End-of-page morph (zone `finish`, window `end`):

- Layout is cheap in every arm after the first frames (macOS 65 to 764 ms per window) and the window is paint-bound: about 40 `Paint` records per frame on macOS, about 70 on iOS, in the original and in all other arms.
- The original has the lowest render work per frame on macOS (73 ms against 126 ms), and the two Composite sums are larger in the rewrite and look arms; A/A
  differs by as much, so the pair verdict is `same` (3 of 3 jobs). On iOS the orders are 294 ms (original), 273 ms (rewrite), 238 ms (A/A), 235 ms (look): within the A/A spread.
- Cadence at the end window: 16, 12, 12, 10 frames over 60 ms per rep (original, rewrite, A/A, look); `same` for every pair.

## Gaps and accepted limits

- iOS leg, hero zone, original: 6 windows with a frame in the zone out of 14 kept, at most 3 per job, so its per-job verdict is `insufficient`. The frame
  count itself (1 to 7 frames per window) is the finding; a verdict needs a run that puts 5 frames per job in the zone, or a window that starts earlier.
- The iOS leg of run 39624728525 stopped in rep 3: the inspector died and relaunching Safari failed with a simulator in state Shutdown (29 of 40 windows kept; the
  windows read are kept, the leg exits 0). Two of three iOS jobs are complete.
- `RenderingFrame` is absent on both legs (Playwright WebKit 27.2, iOS 27.0), so frame start and end come from the animation-frame records.
- The runs do not rank against the phone: `ci-device-accuracy` compares them with the device recorder.
- Chrome-side numbers are in `10-2x-smoothness-probe.md`; the CircleCI legs are out of scope.

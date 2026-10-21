# Smoothness on WebKit: what the engine computes in the two lag windows, original against the rewrite

Question (user, 2026-10-21): "the lag happens on WebKit; Chromium is optimized fine" and "we can use CI to analyze the computation
process (events)". `smoothness-probe` measured Chromium only. This task measures WebKit on CI, on two legs, and puts the
per-zone computation events first and the frame cadence second.

Every number below is MEASURED (the generated tables, filled from `results/smoothness-webkit/`) unless it says INFERRED. The
absolute times come from CI virtual machines under heavy host load (the sim host of job 2 reported load averages of 804, 782 and 700 on 3 CPUs in the job artifact `host.txt`, not committed because it lists local device ids), not from the phone
GPU; they rank arms against each other and are not the phone's frame times (comparison with the phone is task `ci-device-accuracy`).

## Answer

Every number below is a cell of the generated tables. A per-window value (render work, span, share, frames, record counts, covered times, work per frame) is the Lean `medianNat`
(index n/2, the upper middle on an even count) over all kept windows of all loaded jobs of the leg and arm; an interval quantile (p50, p95) is Lean `quantile` over all intervals
of all those repeats; the hitch count is the median over all repeats. Each cell's n is the pooled count with the split per job (`12 (6+6)`), and a cell under 5 (Lean `minReps`)
prints `insufficient (n=k)` instead of a number. Ratios are computed by the report (blocks `*-ratios`), not rounded by hand. Every time is bounded by its window (Lean
`renderWork_le_span`: render work is the union of the top-level `Layout`, `Paint` and `RecalculateStyles` intervals clipped to the window). `Composite` is a count. Round 1 of this
note summed overlapping `Composite` records into the render work (about 95 % of it); those times and the claims built on them (3.5 times, 20 times, "end morph is the same") are withdrawn.

**Status: measurement, not a verdict.** The run (39634194664) was meant to give three jobs per leg. macOS has 2 complete jobs (job 3 hit the 15 minute
cap, no data); iOS has 1 complete job, 1 partial (9 of 40 windows) and 1 refused (17 windows), and its cells pool the complete and the partial job (INFERRED sound: arm, zone and
image are identical; the host load differs, and the n split is shown). Lean `across` needs at least 3 jobs, so every zone verdict below is `insufficient` and the class counts are
empty. The ratios stand as observations over the pooled windows of 2 jobs.

- **Hero exit (hero -> people), macOS Playwright WebKit, original against rewrite: the original spends 42.6 % of the window computing render work, the rewrite
  18.6 %; the layout count is about the same (147 against 138 records), the layout time is 29.0 times.** n = 12 (6+6) windows per arm. Render work 2998.32 ms per window against 529.99 ms
  (window span 6829 ms against 2752 ms), 42229 us per frame against 7098 us (5.9 times). `Layout`: 147 records for 2491.18 ms against 138 records for 85.99 ms.
  `FunctionCall` 2194.21 ms against 420.82 ms (5.2 times), `FireAnimationFrame` 2055.29 ms against 367.87 ms (5.6 times). The rewrite against its A/A copy is 1.0 to 1.2 in these
  ratios (render work per window 1.2, per frame 1.0, share 1.1). The original's windows are longer, so the work per window ratio (5.7) mixes work and span; the share of the span (2.3 times)
  and the work per frame (5.9 times) do not.
- **Cadence agrees on macOS.** Frames over 60 ms per rep (hero, timeline on, 12 (6+6) reps per arm): 43 (original), 4 (rewrite), 5 (A/A), 5 (look); frame interval p50 34.0 ms against 17.0 ms,
  p95 136.0 ms against 52.0 ms (quantiles over all intervals of all 12 reps). The original's longer window gives it more frames to hitch, so the count is read next to the intervals.
- **iOS Simulator (Mobile Safari, iOS 27.0), hero zone: the original has no window with a frame in the zone** (n = 0 windows for `orig`, the table prints `insufficient (n=0)`), so
  there is no hero profile for it on iOS. The rewrite's hero zone holds 7 frames per window (median) at 216.95 ms render work (13.8 % of the span), n = 7 (5+2).
  The `rest` zone shows what the original does there: 2823.18 ms of render work in a 3051 ms window (91.2 %), 81 `Layout` records for 2746.00 ms, a median of 5 `TimerFire` records covering 2352.11 ms
  (n = 6 (5+1)); the rewrite: 114.80 ms in a 1570 ms window (7.2 %), 26 `Layout` records for 40.96 ms (n = 6 (5+1)). Every iOS cell is a pool of 5 to 7 windows from one complete and one partial job
  (the partial job gives 1 or 2 windows per cell) and holds 2 to 4 frames per window in `rest`, so read them as large and unreliable in size.
- **End-of-page morph (zone `finish`): the original does more work, in layout.** macOS: render work 992.92 ms against 600.67 ms (1.7 times; 43.8 % against 28.7 % of
  the span), `Layout` 452.90 ms against 72.92 ms (6.2 times) in 141 against 124 records; `Paint` is 2708 against 2263 records. iOS: 668.06 ms against 225.84 ms (3.0 times; 32.2 % against 11.1 %), `Layout` 502.31 ms against 35.61 ms (14.1 times).
  The cadence does not separate them: end window hitches per rep 7 (original), 10 (rewrite), 9 (A/A), 9 (look) with the timeline on.
- **Look-change arm (`?fw=morph.tween:scroll-lock,nav:earn-no-transition`) is close to the rewrite**: render work 511.68 ms against 529.99 ms (hero), 551.87 ms against 600.67 ms (finish) on macOS;
  the Lean pair verdict is `same` in 2 of 2 macOS jobs in every zone (insufficient only through the job count).
- **`RenderingFrame` records are absent** in Playwright WebKit 27.2 and in iOS 27.0 (0 records in every table); frames come from the animation-frame records.
- **CI cost.** macOS: jobs 2 and 1 took 9.1 and 10.7 min (median 9.9), job 3 cancelled at the 15 min timeout (15.0 min, 901 s, billed 16); iOS: job 2 37.7 min, job 3 31.8 min (exit 0, incomplete), job 1 failed after 23.2 min.
  Billed (each job rounded up from its seconds) 37 min (mac, 3 jobs) and 94 min (iOS, 3 jobs). Cap rows `smoothness-webkit-mac` 15 min and `smoothness-webkit-sim` 45 min in `Fw.Ci.Pool.Caps`
  are built from the first three runs (n=3: 9.43, 10.40, 11.22 min and 29.12, 34.05, 34.15 min); this run put one mac job at the cap, so n=3 is thin.

## Method

- Legs: (1) Playwright WebKit 27.2 on `macos-26` (macOS 26.6.2, Apple M1 virtual, width 390), one browser for all arms; (2) iOS Simulator
  `fw-iphone-27`, runtime iOS 27.0 (24A434), Xcode 27.0 on `xcode-27` (macOS 27.0.1, image 20261012.0260.1), Mobile Safari at width 430
  through the Web Inspector of the simulator. Both are glue around Lean `Fw.Measure.WebKitProfile` (records put on the page clock, binned into the
  device recorder's zones `hero`, `finish`, `rest` of `Fw.Device.Session`; golden `packages/contracts/golden/measure/webkit-profile.jsonl`).
- Zones: `hero` = the first two viewports (hero -> people), `finish` = the last viewport (end-of-page morph), `rest` = between. The hero window
  scrolls 60 wheel steps of 42 px every 16 ms plus a 600 ms tail; the end window pushes 120 px then holds 1 s.
- Metrics: render work = the union (not the sum) of the top-level `Layout`, `Paint` and `RecalculateStyles` intervals of the window clipped to it, so a time never exceeds the window span (Lean `renderWork_le_span`, `Fw.Measure.WebKitProfile`; the TS reducer `reduce.mjs` is checked against the golden). `Composite` is a count. Per kind, the covered time is the union of that kind's intervals.
- Arms by resolved flags, never by preset name: `orig` (the snapshot), `base` (the faithful rewrite), `aa` (a second server of the rewrite, the
  control), `look` (flags `morph.tween:scroll-lock` and `nav:earn-no-transition`). The v2 arm was dropped by Lean's dedup: its resolved flags are
  empty, equal to the rewrite's. Arms interleave per rep and rotate order. One job runs all arms. No CircleCI.
- Event reps run with the Timeline on, cadence reps without it (the Timeline slows the page); both are reported. The macOS leg has 6 event reps and 5
  cadence reps per arm per window per job; the iOS leg 5 event reps per job (cadence is read from the same windows, Timeline on).
- Runs (workflow `smoothness.yml`, branch `ci/smoothness-webkit-cadence`, jobs `webkit-mac` and `webkit-sim`, each a matrix of 3 jobs with `max-parallel 1`, run only on `[webkit-cadence]`):
  run 39634194664 (commit 8850e24d), the only run in `results/smoothness-webkit/runs/`. It is the re-run of round 2: the earlier runs 39612238445, 39617081415 and 39624728525 kept
  profiles reduced with the summed render work and no raw records, so their time metrics are withdrawn and their rows were removed (they stay in git history; the cap rows in
  `Fw.Ci.Pool.Caps` still use their minutes). Each job uploads its raw Timeline records (`mac.raw.json.gz`, `sim.raw.json.gz`: kind, start, duration, nesting of the counted kinds per window); the report
  re-reduces the rows from them with the Lean-mirrored reducer. Job results: mac 1 and 2 complete, mac 3 cancelled at the 15 min timeout (no artifact, cause unknown, the log is not available);
  sim 1 refused (the inspector probe failed, 17 windows, not used), sim 2 complete (40 windows), sim 3 incomplete (9 windows; relaunching Safari failed with ETIMEDOUT). Raw leg files: `results/smoothness-webkit/runs/`; tables regenerate with
  `node packages/measure-webkit/src/profile/cli.mjs report --runs results/smoothness-webkit/runs --out results/smoothness-webkit --jobs results/smoothness-webkit/jobs --note research/notes/2026/10-2x-smoothness-webkit.md`.
- Units of the headline, kinds, ratio and cadence tables: per window is Lean `medianNat` (index n/2, upper middle on even n) over all kept windows of all loaded jobs of the leg, arm and zone; interval quantiles (p50, p95) are Lean `quantile` over all intervals of all loaded jobs; the cell's n is shown with the split per job; a cell under Lean `minReps` (5) prints `insufficient (n=k)`. Billed minutes round up from the unrounded seconds. Only the verdict and class tables stay per job.
- Verdict: Lean `zoneVerdict` per job on the render work per frame of the window, against the A/A pair, then Lean `across` over jobs (two thirds must
  agree, none may disagree, at least 3 jobs; a frame over 60 ms is a hitch). Counts per zone and arm (deterministic, stable, quarantined, Fw.Measure.Classes) are in the class tables.

## Jobs

<!-- gen:runs -->
| job | leg | engine | version / runtime | arms | dropped by flags | windows | kept | refused (reason) | wall s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39634194664:smoothness-webkit-mac-1 | mac | playwright-webkit | 27.2 | orig, base, aa, look | v2 = rewrite | 48 | 48 | 0 | 594 |
| 39634194664:smoothness-webkit-mac-2 | mac | playwright-webkit | 27.2 | orig, base, aa, look | v2 = rewrite | 48 | 48 | 0 | 507 |
| 39634194664:smoothness-webkit-sim-2 | sim | mobile-safari | com.apple.CoreSimulator.SimRuntime.iOS-27-0 | orig, base, aa, look | v2 = rewrite | 40 | 40 | 0 | 1642 |
| 39634194664:smoothness-webkit-sim-3 | sim | mobile-safari | com.apple.CoreSimulator.SimRuntime.iOS-27-0 | orig, base, aa, look | v2 = rewrite | 9 | 9 | 0 | 1216 |
<!-- /gen:runs -->

## macOS Playwright WebKit (leg 1)

Render work per frame (microseconds, Lean `medianNat` over all kept windows of all jobs, range over those windows), and the number of records per kind per window (median over the same windows); n per cell with the split per job:

<!-- gen:mac-headline -->
**hero**

| arm | n windows (per job) | frames | render work ms / window (median) | render work us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 12 (6+6) | 72 | 2998.32 | 42229 (26012-73989) | 202 | 147 | 433 | 72 | 409 | 297 |
| base | 12 (6+6) | 69 | 529.99 | 7098 (5749-8834) | 200 | 138 | 391 | 69 | 686 | 291 |
| aa | 12 (6+6) | 70 | 439.32 | 6764 (5574-8822) | 202 | 143 | 406 | 70 | 679 | 293 |
| look | 12 (6+6) | 68 | 511.68 | 7524 (5913-8899) | 204 | 148 | 402 | 68 | 686 | 290 |

**finish**

| arm | n windows (per job) | frames | render work ms / window (median) | render work us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 12 (6+6) | 64 | 992.92 | 17730 (8649-29494) | 164 | 141 | 2708 | 64 | 110 | 100 |
| base | 12 (6+6) | 57 | 600.67 | 10470 (7945-15921) | 146 | 124 | 2263 | 57 | 376 | 88 |
| aa | 12 (6+6) | 59 | 564.92 | 10201 (7756-14874) | 145 | 125 | 2215 | 59 | 373 | 89 |
| look | 12 (6+6) | 60 | 551.87 | 9133 (7233-11420) | 149 | 115 | 2287 | 60 | 279 | 89 |

**rest**

| arm | n windows (per job) | frames | render work ms / window (median) | render work us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 12 (6+6) | 66 | 1926.87 | 25240 (19373-43896) | 123 | 111 | 173 | 66 | 283 | 209 |
| base | 12 (6+6) | 68 | 239.22 | 3797 (3025-5052) | 129 | 114 | 235 | 68 | 374 | 180 |
| aa | 12 (6+6) | 63 | 253.85 | 3830 (3086-5208) | 132 | 114 | 234 | 63 | 375 | 170 |
| look | 12 (6+6) | 65 | 245.52 | 3816 (3238-4851) | 129 | 116 | 253 | 65 | 373 | 172 |

<!-- /gen:mac-headline -->

Ratios, computed from the same values (original / rewrite, rewrite / A/A; `-` where an arm has no window with a frame in the zone). Render work is the union of the top-level `Layout`, `Paint` and `RecalculateStyles` intervals clipped to the window, so it is never above the window span:

<!-- gen:mac-ratios -->
**hero**

| metric | orig | base | aa | look | orig / base | base / aa |
| --- | --- | --- | --- | --- | --- | --- |
| n windows (per job) | 12 (6+6) | 12 (6+6) | 12 (6+6) | 12 (6+6) |  |  |
| frames in zone | 72 | 69 | 70 | 68 | 1.0 | 1.0 |
| window span ms | 6829.00 | 2752.00 | 2880.00 | 2796.00 | 2.5 | 1.0 |
| render work ms / window | 2998.32 | 529.99 | 439.32 | 511.68 | 5.7 | 1.2 |
| render work share of the window span % | 42.6 | 18.6 | 16.7 | 18.4 | 2.3 | 1.1 |
| render work us / frame | 42229 | 7098 | 6764 | 7524 | 5.9 | 1.0 |
| RecalculateStyles n | 202 | 200 | 202 | 204 | 1.0 | 1.0 |
| RecalculateStyles ms | 421.61 | 344.26 | 294.22 | 320.14 | 1.2 | 1.2 |
| Layout n | 147 | 138 | 143 | 148 | 1.1 | 1.0 |
| Layout ms | 2491.18 | 85.99 | 77.65 | 92.12 | 29.0 | 1.1 |
| Paint n | 433 | 391 | 406 | 402 | 1.1 | 1.0 |
| Paint ms | 96.01 | 107.30 | 99.90 | 106.07 | 0.9 | 1.1 |
| Composite n | 72 | 69 | 70 | 68 | 1.0 | 1.0 |
| FunctionCall n | 409 | 686 | 679 | 686 | 0.6 | 1.0 |
| FunctionCall ms | 2194.21 | 420.82 | 349.30 | 375.87 | 5.2 | 1.2 |
| FireAnimationFrame n | 297 | 291 | 293 | 290 | 1.0 | 1.0 |
| FireAnimationFrame ms | 2055.29 | 367.87 | 303.74 | 321.77 | 5.6 | 1.2 |

**finish**

| metric | orig | base | aa | look | orig / base | base / aa |
| --- | --- | --- | --- | --- | --- | --- |
| n windows (per job) | 12 (6+6) | 12 (6+6) | 12 (6+6) | 12 (6+6) |  |  |
| frames in zone | 64 | 57 | 59 | 60 | 1.1 | 1.0 |
| window span ms | 2233.00 | 2054.00 | 2048.00 | 2051.00 | 1.1 | 1.0 |
| render work ms / window | 992.92 | 600.67 | 564.92 | 551.87 | 1.7 | 1.1 |
| render work share of the window span % | 43.8 | 28.7 | 27.5 | 26.2 | 1.5 | 1.0 |
| render work us / frame | 17730 | 10470 | 10201 | 9133 | 1.7 | 1.0 |
| RecalculateStyles n | 164 | 146 | 145 | 149 | 1.1 | 1.0 |
| RecalculateStyles ms | 430.88 | 422.76 | 408.41 | 369.68 | 1.0 | 1.0 |
| Layout n | 141 | 124 | 125 | 115 | 1.1 | 1.0 |
| Layout ms | 452.90 | 72.92 | 66.70 | 59.68 | 6.2 | 1.1 |
| Paint n | 2708 | 2263 | 2215 | 2287 | 1.2 | 1.0 |
| Paint ms | 143.21 | 132.45 | 125.97 | 128.54 | 1.1 | 1.1 |
| Composite n | 64 | 57 | 59 | 60 | 1.1 | 1.0 |
| FunctionCall n | 110 | 376 | 373 | 279 | 0.3 | 1.0 |
| FunctionCall ms | 543.90 | 166.53 | 153.40 | 138.95 | 3.3 | 1.1 |
| FireAnimationFrame n | 100 | 88 | 89 | 89 | 1.1 | 1.0 |
| FireAnimationFrame ms | 543.96 | 159.85 | 149.05 | 134.64 | 3.4 | 1.1 |

**rest**

| metric | orig | base | aa | look | orig / base | base / aa |
| --- | --- | --- | --- | --- | --- | --- |
| n windows (per job) | 12 (6+6) | 12 (6+6) | 12 (6+6) | 12 (6+6) |  |  |
| frames in zone | 66 | 68 | 63 | 65 | 1.0 | 1.1 |
| window span ms | 6829.00 | 2752.00 | 2880.00 | 2796.00 | 2.5 | 1.0 |
| render work ms / window | 1926.87 | 239.22 | 253.85 | 245.52 | 8.1 | 0.9 |
| render work share of the window span % | 33.3 | 8.9 | 8.8 | 9.0 | 3.7 | 1.0 |
| render work us / frame | 25240 | 3797 | 3830 | 3816 | 6.6 | 1.0 |
| RecalculateStyles n | 123 | 129 | 132 | 129 | 1.0 | 1.0 |
| RecalculateStyles ms | 267.15 | 168.03 | 167.97 | 187.21 | 1.6 | 1.0 |
| Layout n | 111 | 114 | 114 | 116 | 1.0 | 1.0 |
| Layout ms | 1667.93 | 45.60 | 46.27 | 45.40 | 36.6 | 1.0 |
| Paint n | 173 | 235 | 234 | 253 | 0.7 | 1.0 |
| Paint ms | 20.58 | 21.66 | 21.09 | 19.98 | 1.0 | 1.0 |
| Composite n | 66 | 68 | 63 | 65 | 1.0 | 1.1 |
| FunctionCall n | 283 | 374 | 375 | 373 | 0.8 | 1.0 |
| FunctionCall ms | 1721.08 | 245.33 | 231.74 | 254.88 | 7.0 | 1.1 |
| FireAnimationFrame n | 209 | 180 | 170 | 172 | 1.2 | 1.1 |
| FireAnimationFrame ms | 1711.33 | 231.28 | 217.75 | 240.32 | 7.4 | 1.1 |

<!-- /gen:mac-ratios -->

Lean verdict per zone and pair (first = left arm of the pair; `second` means the second arm does less work per frame):

<!-- gen:mac-verdict -->
| zone | pair (first, second) | jobs | first | second | same | insufficient | verdict over jobs |
| --- | --- | --- | --- | --- | --- | --- | --- |
| hero | orig, base | 2 | 0 | 2 | 0 | 0 | insufficient |
| hero | base, look | 2 | 0 | 0 | 2 | 0 | insufficient |
| hero | orig, look | 2 | 0 | 2 | 0 | 0 | insufficient |
| finish | orig, base | 2 | 0 | 1 | 1 | 0 | insufficient |
| finish | base, look | 2 | 0 | 0 | 2 | 0 | insufficient |
| finish | orig, look | 2 | 0 | 1 | 1 | 0 | insufficient |
| rest | orig, base | 2 | 0 | 2 | 0 | 0 | insufficient |
| rest | base, look | 2 | 0 | 0 | 2 | 0 | insufficient |
| rest | orig, look | 2 | 0 | 2 | 0 | 0 | insufficient |
<!-- /gen:mac-verdict -->

Count classes per zone and arm:

<!-- gen:mac-class -->
| zone | arm | jobs | deterministic | stable | quarantined |
| --- | --- | --- | --- | --- | --- |
| hero | orig | 2 | - | - | - |
| hero | base | 2 | - | - | - |
| hero | aa | 2 | - | - | - |
| hero | look | 2 | - | - | - |
| finish | orig | 2 | - | - | - |
| finish | base | 2 | - | - | - |
| finish | aa | 2 | - | - | - |
| finish | look | 2 | - | - | - |
| rest | orig | 2 | - | - | - |
| rest | base | 2 | - | - | - |
| rest | aa | 2 | - | - | - |
| rest | look | 2 | - | - | - |
<!-- /gen:mac-class -->

Records per kind, count and covered time per window (the union of the kind's intervals in the window). `Composite` is a count only: WebKit records it as an asynchronous wait for the compositing flush, so its durations overlap and are not work.

<!-- gen:mac-kinds -->
**hero** (median count / median covered ms per window over all kept windows of all jobs; covered = union of the kind's intervals in the window, never above the window span; Composite is a count)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| n windows (per job) | 12 (6+6) | 12 (6+6) | 12 (6+6) | 12 (6+6) |
| RecalculateStyles | 202 / 421.61 | 200 / 344.26 | 202 / 294.22 | 204 / 320.14 |
| Layout | 147 / 2491.18 | 138 / 85.99 | 143 / 77.65 | 148 / 92.12 |
| Paint | 433 / 96.01 | 391 / 107.30 | 406 / 99.90 | 402 / 106.07 |
| Composite | 72 / count only | 69 / count only | 70 / count only | 68 / count only |
| FunctionCall | 409 / 2194.21 | 686 / 420.82 | 679 / 349.30 | 686 / 375.87 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 25 / 15.34 | 8 / 2.62 | 8 / 2.59 | 8 / 2.85 |
| FireAnimationFrame | 297 / 2055.29 | 291 / 367.87 | 293 / 303.74 | 290 / 321.77 |
| EventDispatch | 59 / 5.68 | 475 / 40.22 | 465 / 44.17 | 477 / 51.05 |
| ObserverCallback | 31 / 82.24 | 12 / 5.44 | 12 / 6.90 | 12 / 5.26 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

**finish** (median count / median covered ms per window over all kept windows of all jobs; covered = union of the kind's intervals in the window, never above the window span; Composite is a count)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| n windows (per job) | 12 (6+6) | 12 (6+6) | 12 (6+6) | 12 (6+6) |
| RecalculateStyles | 164 / 430.88 | 146 / 422.76 | 145 / 408.41 | 149 / 369.68 |
| Layout | 141 / 452.90 | 124 / 72.92 | 125 / 66.70 | 115 / 59.68 |
| Paint | 2708 / 143.21 | 2263 / 132.45 | 2215 / 125.97 | 2287 / 128.54 |
| Composite | 64 / count only | 57 / count only | 59 / count only | 60 / count only |
| FunctionCall | 110 / 543.90 | 376 / 166.53 | 373 / 153.40 | 279 / 138.95 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 5 / 0.24 | 4 / 0.36 | 4 / 0.32 | 4 / 0.39 |
| FireAnimationFrame | 100 / 543.96 | 88 / 159.85 | 89 / 149.05 | 89 / 134.64 |
| EventDispatch | 4 / 0.78 | 228 / 8.31 | 206 / 6.51 | 132 / 4.76 |
| ObserverCallback | 5 / 0.13 | 58 / 3.14 | 56 / 2.90 | 54 / 2.93 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

**rest** (median count / median covered ms per window over all kept windows of all jobs; covered = union of the kind's intervals in the window, never above the window span; Composite is a count)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| n windows (per job) | 12 (6+6) | 12 (6+6) | 12 (6+6) | 12 (6+6) |
| RecalculateStyles | 123 / 267.15 | 129 / 168.03 | 132 / 167.97 | 129 / 187.21 |
| Layout | 111 / 1667.93 | 114 / 45.60 | 114 / 46.27 | 116 / 45.40 |
| Paint | 173 / 20.58 | 235 / 21.66 | 234 / 21.09 | 253 / 19.98 |
| Composite | 66 / count only | 68 / count only | 63 / count only | 65 / count only |
| FunctionCall | 283 / 1721.08 | 374 / 245.33 | 375 / 231.74 | 373 / 254.88 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 16 / 6.26 | 4 / 0.70 | 5 / 0.96 | 4 / 0.99 |
| FireAnimationFrame | 209 / 1711.33 | 180 / 231.28 | 170 / 217.75 | 172 / 240.32 |
| EventDispatch | 69 / 4.64 | 241 / 16.64 | 243 / 15.07 | 245 / 15.38 |
| ObserverCallback | 12 / 1.29 | 6 / 0.83 | 6 / 0.84 | 6 / 0.98 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

<!-- /gen:mac-kinds -->

Cadence (secondary), `timeline on` = the event reps, `off` = the cadence reps:

<!-- gen:mac-cadence -->
| window | timeline | arm | reps n (per job) | hitches per rep (median) | p50 ms | p95 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- |
| hero | on | orig | 12 (6+6) | 43 | 34.0 | 136.0 | 484.0 |
| hero | on | base | 12 (6+6) | 4 | 17.0 | 52.0 | 167.0 |
| hero | on | aa | 12 (6+6) | 5 | 17.0 | 50.0 | 242.0 |
| hero | on | look | 12 (6+6) | 5 | 17.0 | 50.0 | 227.0 |
| hero | off | orig | 10 (5+5) | 24 | 34.0 | 122.0 | 422.0 |
| hero | off | base | 10 (5+5) | 7 | 17.0 | 64.0 | 313.0 |
| hero | off | aa | 10 (5+5) | 6 | 17.0 | 63.0 | 125.0 |
| hero | off | look | 10 (5+5) | 11 | 17.0 | 70.0 | 210.0 |
| end | on | orig | 12 (6+6) | 7 | 32.0 | 93.0 | 194.0 |
| end | on | base | 12 (6+6) | 10 | 27.0 | 92.0 | 153.0 |
| end | on | aa | 12 (6+6) | 9 | 27.0 | 93.0 | 220.0 |
| end | on | look | 12 (6+6) | 9 | 25.0 | 86.0 | 193.0 |
| end | off | orig | 10 (5+5) | 11 | 32.0 | 92.0 | 162.0 |
| end | off | base | 10 (5+5) | 8 | 25.0 | 84.0 | 279.0 |
| end | off | aa | 10 (5+5) | 8 | 24.0 | 84.0 | 145.0 |
| end | off | look | 10 (5+5) | 9 | 23.0 | 81.0 | 157.0 |
<!-- /gen:mac-cadence -->

<!-- gen:mac-cadence-verdict -->
| window | timeline | pair (first, second) | jobs | first | second | same | insufficient | verdict over jobs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hero | on | orig, base | 2 | 0 | 2 | 0 | 0 | insufficient |
| hero | on | base, look | 2 | 0 | 0 | 2 | 0 | insufficient |
| hero | on | orig, look | 2 | 0 | 2 | 0 | 0 | insufficient |
| hero | off | orig, base | 2 | 0 | 1 | 1 | 0 | insufficient |
| hero | off | base, look | 2 | 0 | 0 | 2 | 0 | insufficient |
| hero | off | orig, look | 2 | 0 | 2 | 0 | 0 | insufficient |
| end | on | orig, base | 2 | 0 | 0 | 2 | 0 | insufficient |
| end | on | base, look | 2 | 0 | 0 | 2 | 0 | insufficient |
| end | on | orig, look | 2 | 0 | 0 | 2 | 0 | insufficient |
| end | off | orig, base | 2 | 0 | 0 | 2 | 0 | insufficient |
| end | off | base, look | 2 | 0 | 0 | 2 | 0 | insufficient |
| end | off | orig, look | 2 | 0 | 0 | 2 | 0 | insufficient |
<!-- /gen:mac-cadence-verdict -->

## iOS Simulator (leg 2)

<!-- gen:sim-headline -->
**hero**

| arm | n windows (per job) | frames | render work ms / window (median) | render work us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 0 (0+0) | insufficient (n=0) | insufficient (n=0) | insufficient (n=0) | insufficient (n=0) | insufficient (n=0) | insufficient (n=0) | insufficient (n=0) | insufficient (n=0) | insufficient (n=0) |
| base | 7 (5+2) | 7 | 216.95 | 30992 (20402-42961) | 33 | 84 | 116 | 7 | 178 | 32 |
| aa | 6 (5+1) | 6 | 227.19 | 40500 (22772-45438) | 30 | 83 | 105 | 6 | 173 | 27 |
| look | 6 (5+1) | 7 | 183.69 | 30558 (20878-39292) | 32 | 81 | 102 | 7 | 159 | 36 |

**finish**

| arm | n windows (per job) | frames | render work ms / window (median) | render work us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 6 (5+1) | 5 | 668.06 | 116323 (102832-137864) | 21 | 24 | 400 | 5 | 23 | 15 |
| base | 6 (5+1) | 6 | 225.84 | 43341 (22421-56460) | 26 | 28 | 425 | 6 | 142 | 16 |
| aa | 6 (5+1) | 5 | 234.78 | 46956 (33248-92177) | 18 | 18 | 406 | 5 | 107 | 15 |
| look | 6 (5+1) | 6 | 168.84 | 28078 (22507-76970) | 18 | 18 | 409 | 6 | 91 | 13 |

**rest**

| arm | n windows (per job) | frames | render work ms / window (median) | render work us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 6 (5+1) | 2 | 2823.18 | 1432690 (624023-2823180) | 22 | 81 | 49 | 2 | 37 | 16 |
| base | 6 (5+1) | 4 | 114.80 | 40250 (27070-114800) | 25 | 26 | 57 | 4 | 105 | 24 |
| aa | 5 (4+1) | 2 | 114.02 | 44756 (31830-111270) | 14 | 13 | 44 | 2 | 77 | 11 |
| look | 6 (5+1) | 3 | 118.67 | 44365 (29667-109620) | 23 | 28 | 64 | 3 | 104 | 21 |

<!-- /gen:sim-headline -->

Ratios, computed from the same values (original / rewrite, rewrite / A/A; `-` where an arm has no window with a frame in the zone). Render work is the union of the top-level `Layout`, `Paint` and `RecalculateStyles` intervals clipped to the window, so it is never above the window span:

<!-- gen:sim-ratios -->
**hero**

| metric | orig | base | aa | look | orig / base | base / aa |
| --- | --- | --- | --- | --- | --- | --- |
| n windows (per job) | 0 (0+0) | 7 (5+2) | 6 (5+1) | 6 (5+1) |  |  |
| frames in zone | insufficient (n=0) | 7 | 6 | 7 | - | 1.2 |
| window span ms | insufficient (n=0) | 1569.00 | 1571.00 | 1569.00 | - | 1.0 |
| render work ms / window | insufficient (n=0) | 216.95 | 227.19 | 183.69 | - | 1.0 |
| render work share of the window span % | insufficient (n=0) | 13.8 | 14.4 | 11.7 | - | 1.0 |
| render work us / frame | insufficient (n=0) | 30992 | 40500 | 30558 | - | 0.8 |
| RecalculateStyles n | insufficient (n=0) | 33 | 30 | 32 | - | 1.1 |
| RecalculateStyles ms | insufficient (n=0) | 89.43 | 83.39 | 76.17 | - | 1.1 |
| Layout n | insufficient (n=0) | 84 | 83 | 81 | - | 1.0 |
| Layout ms | insufficient (n=0) | 59.01 | 69.53 | 52.25 | - | 0.8 |
| Paint n | insufficient (n=0) | 116 | 105 | 102 | - | 1.1 |
| Paint ms | insufficient (n=0) | 67.78 | 96.43 | 65.35 | - | 0.7 |
| Composite n | insufficient (n=0) | 7 | 6 | 7 | - | 1.2 |
| FunctionCall n | insufficient (n=0) | 178 | 173 | 159 | - | 1.0 |
| FunctionCall ms | insufficient (n=0) | 250.60 | 280.52 | 243.77 | - | 0.9 |
| FireAnimationFrame n | insufficient (n=0) | 32 | 27 | 36 | - | 1.2 |
| FireAnimationFrame ms | insufficient (n=0) | 99.97 | 96.74 | 89.70 | - | 1.0 |

**finish**

| metric | orig | base | aa | look | orig / base | base / aa |
| --- | --- | --- | --- | --- | --- | --- |
| n windows (per job) | 6 (5+1) | 6 (5+1) | 6 (5+1) | 6 (5+1) |  |  |
| frames in zone | 5 | 6 | 5 | 6 | 0.8 | 1.2 |
| window span ms | 2088.00 | 2024.00 | 2023.00 | 2005.00 | 1.0 | 1.0 |
| render work ms / window | 668.06 | 225.84 | 234.78 | 168.84 | 3.0 | 1.0 |
| render work share of the window span % | 32.2 | 11.1 | 11.2 | 8.4 | 2.9 | 1.0 |
| render work us / frame | 116323 | 43341 | 46956 | 28078 | 2.7 | 0.9 |
| RecalculateStyles n | 21 | 26 | 18 | 18 | 0.8 | 1.4 |
| RecalculateStyles ms | 124.18 | 177.14 | 157.23 | 127.55 | 0.7 | 1.1 |
| Layout n | 24 | 28 | 18 | 18 | 0.9 | 1.6 |
| Layout ms | 502.31 | 35.61 | 27.59 | 25.63 | 14.1 | 1.3 |
| Paint n | 400 | 425 | 406 | 409 | 0.9 | 1.0 |
| Paint ms | 37.75 | 44.77 | 71.33 | 44.92 | 0.8 | 0.6 |
| Composite n | 5 | 6 | 5 | 6 | 0.8 | 1.2 |
| FunctionCall n | 23 | 142 | 107 | 91 | 0.2 | 1.3 |
| FunctionCall ms | 529.93 | 39.82 | 45.36 | 35.96 | 13.3 | 0.9 |
| FireAnimationFrame n | 15 | 16 | 15 | 13 | 0.9 | 1.1 |
| FireAnimationFrame ms | 528.02 | 33.44 | 39.07 | 29.94 | 15.8 | 0.9 |

**rest**

| metric | orig | base | aa | look | orig / base | base / aa |
| --- | --- | --- | --- | --- | --- | --- |
| n windows (per job) | 6 (5+1) | 6 (5+1) | 5 (4+1) | 6 (5+1) |  |  |
| frames in zone | 2 | 4 | 2 | 3 | 0.5 | 2.0 |
| window span ms | 3051.00 | 1570.00 | 1570.00 | 1569.00 | 1.9 | 1.0 |
| render work ms / window | 2823.18 | 114.80 | 114.02 | 118.67 | 24.6 | 1.0 |
| render work share of the window span % | 91.2 | 7.2 | 7.2 | 7.5 | 12.7 | 1.0 |
| render work us / frame | 1432690 | 40250 | 44756 | 44365 | 35.6 | 0.9 |
| RecalculateStyles n | 22 | 25 | 14 | 23 | 0.9 | 1.8 |
| RecalculateStyles ms | 164.00 | 85.97 | 83.84 | 85.88 | 1.9 | 1.0 |
| Layout n | 81 | 26 | 13 | 28 | 3.1 | 2.0 |
| Layout ms | 2746.00 | 40.96 | 40.73 | 39.02 | 67.0 | 1.0 |
| Paint n | 49 | 57 | 44 | 64 | 0.9 | 1.3 |
| Paint ms | 14.40 | 18.31 | 18.81 | 28.34 | 0.8 | 1.0 |
| Composite n | 2 | 4 | 2 | 3 | 0.5 | 2.0 |
| FunctionCall n | 37 | 105 | 77 | 104 | 0.4 | 1.4 |
| FunctionCall ms | 2579.21 | 68.36 | 76.62 | 73.25 | 37.7 | 0.9 |
| FireAnimationFrame n | 16 | 24 | 11 | 21 | 0.7 | 2.2 |
| FireAnimationFrame ms | 133.47 | 44.57 | 47.65 | 50.70 | 3.0 | 0.9 |

<!-- /gen:sim-ratios -->

<!-- gen:sim-verdict -->
| zone | pair (first, second) | jobs | first | second | same | insufficient | verdict over jobs |
| --- | --- | --- | --- | --- | --- | --- | --- |
| hero | orig, base | 2 | 0 | 0 | 0 | 2 | insufficient |
| hero | base, look | 2 | 0 | 0 | 1 | 1 | insufficient |
| hero | orig, look | 2 | 0 | 0 | 0 | 2 | insufficient |
| finish | orig, base | 2 | 0 | 1 | 0 | 1 | insufficient |
| finish | base, look | 2 | 0 | 0 | 1 | 1 | insufficient |
| finish | orig, look | 2 | 0 | 1 | 0 | 1 | insufficient |
| rest | orig, base | 2 | 0 | 0 | 0 | 2 | insufficient |
| rest | base, look | 2 | 0 | 0 | 0 | 2 | insufficient |
| rest | orig, look | 2 | 0 | 0 | 0 | 2 | insufficient |
<!-- /gen:sim-verdict -->

<!-- gen:sim-class -->
| zone | arm | jobs | deterministic | stable | quarantined |
| --- | --- | --- | --- | --- | --- |
| hero | orig | 0 | - | - | - |
| hero | base | 2 | - | - | - |
| hero | aa | 2 | - | - | - |
| hero | look | 2 | - | - | - |
| finish | orig | 2 | - | - | - |
| finish | base | 2 | - | - | - |
| finish | aa | 2 | - | - | - |
| finish | look | 2 | - | - | - |
| rest | orig | 2 | - | - | - |
| rest | base | 2 | - | - | - |
| rest | aa | 2 | - | - | - |
| rest | look | 2 | - | - | - |
<!-- /gen:sim-class -->

<!-- gen:sim-kinds -->
**hero** (median count / median covered ms per window over all kept windows of all jobs; covered = union of the kind's intervals in the window, never above the window span; Composite is a count)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| n windows (per job) | 0 (0+0) | 7 (5+2) | 6 (5+1) | 6 (5+1) |
| RecalculateStyles | insufficient (n=0) | 33 / 89.43 | 30 / 83.39 | 32 / 76.17 |
| Layout | insufficient (n=0) | 84 / 59.01 | 83 / 69.53 | 81 / 52.25 |
| Paint | insufficient (n=0) | 116 / 67.78 | 105 / 96.43 | 102 / 65.35 |
| Composite | insufficient (n=0) | 7 / count only | 6 / count only | 7 / count only |
| FunctionCall | insufficient (n=0) | 178 / 250.60 | 173 / 280.52 | 159 / 243.77 |
| EvaluateScript | insufficient (n=0) | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | insufficient (n=0) | 52 / 156.04 | 54 / 161.81 | 54 / 148.93 |
| FireAnimationFrame | insufficient (n=0) | 32 / 99.97 | 27 / 96.74 | 36 / 89.70 |
| EventDispatch | insufficient (n=0) | 113 / 8.82 | 101 / 14.52 | 92 / 8.68 |
| ObserverCallback | insufficient (n=0) | 7 / 2.83 | 6 / 3.62 | 8 / 2.90 |
| RenderingFrame | insufficient (n=0) | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

**finish** (median count / median covered ms per window over all kept windows of all jobs; covered = union of the kind's intervals in the window, never above the window span; Composite is a count)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| n windows (per job) | 6 (5+1) | 6 (5+1) | 6 (5+1) | 6 (5+1) |
| RecalculateStyles | 21 / 124.18 | 26 / 177.14 | 18 / 157.23 | 18 / 127.55 |
| Layout | 24 / 502.31 | 28 / 35.61 | 18 / 27.59 | 18 / 25.63 |
| Paint | 400 / 37.75 | 425 / 44.77 | 406 / 71.33 | 409 / 44.92 |
| Composite | 5 / count only | 6 / count only | 5 / count only | 6 / count only |
| FunctionCall | 23 / 529.93 | 142 / 39.82 | 107 / 45.36 | 91 / 35.96 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 6 / 1.52 | 6 / 1.68 | 6 / 4.85 | 6 / 2.32 |
| FireAnimationFrame | 15 / 528.02 | 16 / 33.44 | 15 / 39.07 | 13 / 29.94 |
| EventDispatch | 4 / 2.87 | 137 / 6.94 | 78 / 11.45 | 69 / 5.56 |
| ObserverCallback | 0 / 0.00 | 12 / 1.97 | 10 / 2.77 | 10 / 2.34 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

**rest** (median count / median covered ms per window over all kept windows of all jobs; covered = union of the kind's intervals in the window, never above the window span; Composite is a count)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| n windows (per job) | 6 (5+1) | 6 (5+1) | 5 (4+1) | 6 (5+1) |
| RecalculateStyles | 22 / 164.00 | 25 / 85.97 | 14 / 83.84 | 23 / 85.88 |
| Layout | 81 / 2746.00 | 26 / 40.96 | 13 / 40.73 | 28 / 39.02 |
| Paint | 49 / 14.40 | 57 / 18.31 | 44 / 18.81 | 64 / 28.34 |
| Composite | 2 / count only | 4 / count only | 2 / count only | 3 / count only |
| FunctionCall | 37 / 2579.21 | 105 / 68.36 | 77 / 76.62 | 104 / 73.25 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 5 / 2352.11 | 1 / 0.52 | 2 / 0.93 | 2 / 2.62 |
| FireAnimationFrame | 16 / 133.47 | 24 / 44.57 | 11 / 47.65 | 21 / 50.70 |
| EventDispatch | 1 / 0.13 | 83 / 32.82 | 59 / 27.67 | 100 / 23.45 |
| ObserverCallback | 12 / 107.62 | 7 / 4.62 | 8 / 2.90 | 8 / 4.71 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

<!-- /gen:sim-kinds -->

<!-- gen:sim-cadence -->
| window | timeline | arm | reps n (per job) | hitches per rep (median) | p50 ms | p95 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- |
| hero | on | orig | 6 (5+1) | 1 | 375.0 | 474.0 | 474.0 |
| hero | on | base | 7 (5+2) | 4 | 136.0 | 531.0 | 791.0 |
| hero | on | aa | 6 (5+1) | 5 | 165.0 | 529.0 | 759.0 |
| hero | on | look | 6 (5+1) | 6 | 156.0 | 573.0 | 638.0 |
| end | on | orig | 6 (5+1) | 4 | 437.0 | 627.0 | 805.0 |
| end | on | base | 6 (5+1) | 5 | 360.0 | 576.0 | 780.0 |
| end | on | aa | 6 (5+1) | 4 | 440.0 | 713.0 | 781.0 |
| end | on | look | 6 (5+1) | 5 | 388.0 | 520.0 | 1023.0 |
<!-- /gen:sim-cadence -->

<!-- gen:sim-cadence-verdict -->
| window | timeline | pair (first, second) | jobs | first | second | same | insufficient | verdict over jobs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hero | on | orig, base | 2 | 1 | 0 | 0 | 1 | insufficient |
| hero | on | base, look | 2 | 0 | 0 | 1 | 1 | insufficient |
| hero | on | orig, look | 2 | 1 | 0 | 0 | 1 | insufficient |
| end | on | orig, base | 2 | 0 | 0 | 1 | 1 | insufficient |
| end | on | base, look | 2 | 0 | 0 | 1 | 1 | insufficient |
| end | on | orig, look | 2 | 0 | 0 | 1 | 1 | insufficient |
<!-- /gen:sim-cadence-verdict -->

## Job minutes

<!-- gen:minutes -->
| run | leg | job | result | wall min | billed min |
| --- | --- | --- | --- | --- | --- |
| 39634194664 | mac | webkit mac (playwright-webkit, macos-26) job 1 | success | 10.7 | 11 |
| 39634194664 | sim | webkit sim (mobile safari, xcode-27) job 1 | failure | 23.2 | 24 |
| 39634194664 | mac | webkit mac (playwright-webkit, macos-26) job 2 | success | 9.1 | 10 |
| 39634194664 | mac | webkit mac (playwright-webkit, macos-26) job 3 | cancelled | 15 | 16 |
| 39634194664 | sim | webkit sim (mobile safari, xcode-27) job 2 | success | 37.7 | 38 |
| 39634194664 | sim | webkit sim (mobile safari, xcode-27) job 3 | success | 31.8 | 32 |
| median of successes | mac |  | n=2 | 9.9 |  |
| longest success | mac |  |  | 10.7 |  |
| all jobs billed | mac |  | n=3 |  | 37 |
| median of successes | sim |  | n=2 | 34.8 |  |
| longest success | sim |  |  | 37.7 |  |
| all jobs billed | sim |  | n=3 |  | 94 |
<!-- /gen:minutes -->

## What the events say about the two lag windows

Units: "per window" is the Lean `medianNat` (index n/2, upper middle on an even count) over all kept windows of all loaded jobs of the leg and arm, of the whole window (the window span is in the ratio tables); "frames in zone" is the same median of the number of frames inside the zone per window; interval quantiles are over all intervals of all loaded jobs; n per cell with the split per job is in the tables, and a cell under 5 windows prints `insufficient (n=k)`.

Hero exit (zone `hero`, window `hero`):

- The counts of style recalculation and layout are about the same in the original and the rewrite on macOS (202 against 200 style records, 147 against 138 layouts).
  The covered time is not: `Layout` 2491.18 ms in the original, 85.99 ms in the rewrite. So the original's lag in this window is expensive layouts
  (INFERRED: forced reflow of a large tree each frame; the Timeline gives no call stack), not more of them.
- The original runs fewer script calls but they cover more time: `FunctionCall` 409 records for 2194.21 ms against 686 for 420.82 ms; `FireAnimationFrame` 2055.29 ms against 367.87 ms.
  The rewrite dispatches many more events (`EventDispatch` 475 against 59 records).
- On iOS the original has no window with a frame in the hero zone; in the `rest` zone it has 81 layouts for 2746.00 ms and a median of 5 timer records covering 2352.11 ms per window; the rewrite 26 layouts for 40.96 ms.
- The cadence hitch count undercounts the original on iOS (1 per rep against 4 for the rewrite, n = 6 (5+1) and 7 (5+2) reps): a window with no frames in the zone has no room to hitch.
  The p50 (375.0 ms against 136.0 ms) of the frame intervals shows it.
- Look-change flags: no difference from the rewrite beyond the A/A spread in any table of this window.

End-of-page morph (zone `finish`, window `end`):

- Layout is the difference: the original 452.90 ms against 72.92 ms on macOS (6.2 times) and 502.31 ms against 35.61 ms on iOS (14.1 times); `Paint` is about the same (2708 against 2263 records on macOS).
- Cadence at the end window does not separate the arms (7, 10, 9, 9 frames over 60 ms per rep on macOS: original, rewrite, A/A, look).

## Gaps and accepted limits

- Jobs: macOS has 2 complete jobs of 3 (job 3 was cancelled at its 15 min cap, cause unknown, no log); iOS has 1 complete job (job 2), 1 incomplete (job 3: the inspector died and relaunching Safari failed with ETIMEDOUT, 9 windows) and 1 refused (job 1: probe failed, not used).
  Lean `across` needs 3 jobs, so no zone verdict and no class count is available. One re-run was the limit of this task; a third complete job per leg is the next step.
- iOS leg, hero zone, original: no window put a frame in the zone, so the zone has no profile and stays `insufficient`. A verdict needs a window that starts earlier or a run that puts 5 frames per job in the zone.
- iOS cells pool one complete and one partial job under different host load (INFERRED sound: arm, zone and image are identical) and hold 5 to 7 windows each, the partial job giving 1 or 2 (the split is in every cell); iOS zones hold 2 to 7 frames per window; per-frame values there (up to 1432690 us for the original `rest` zone) are dominated by one or two long tasks and are read next to the span share.
- macOS original windows are longer than the rewrite's (6829 ms against 2752 ms in the hero zone) because the same wheel input takes longer to settle; per-window sums mix span and work, so the span share and the per-frame values carry the comparison.
- `RenderingFrame` is absent on both legs (Playwright WebKit 27.2, iOS 27.0), so frame start and end come from the animation-frame records.
- CI virtual machines are not the phone GPU. The runs do not rank against the phone: `ci-device-accuracy` compares them with the device recorder.
- The cap rows (15 and 45 min) rest on n=3 successes per leg; mac job 3 of this run reached the 15 min cap.
- Chrome-side numbers are in `10-2x-smoothness-probe.md`; the CircleCI legs are out of scope.

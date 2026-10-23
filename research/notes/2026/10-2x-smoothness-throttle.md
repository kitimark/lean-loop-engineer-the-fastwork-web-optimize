# Smoothness under a 6x CPU throttle in Chromium: a PROXY of the WebKit lag, not WebKit evidence

Question (user, 2026-10-21): "the lag happens on WebKit; Chromium is optimized fine, except on 6x throttling we will find lag on Chromium too." Task `smoothness-cpu-throttle` runs the
Chromium cadence arms of `smoothness.yml` with CDP `Emulation.setCPUThrottlingRate` 6 and 1 (control) in the two lag windows, and asks whether the arm ranking matches the WebKit cadence
and the phone. **PROXY**: a Linux Chrome Headless Shell on a shared CI runner, software rendering, main thread slowed; nothing here is a WebKit or iPhone time.

## Answer

- **6x makes every window lag in Chromium, and it lags every arm alike.** MEASURED. Bad-frame rate (gap above 34 ms between rAF callbacks), median over 3 job samples, round b:
  390 hero 0.6 % to 26 %, 390 end 0.7 % to 29 % (orig, base), 1280 hero 4 to 5 % to 22 to 25 %, 1280 end 16 to 19 % to 41 to 48 %. Hitches (frames over 60 ms) per repeat go from 0 or 1 to 8 to 15.
  At 1x only 1280 end lags already (16 to 19 %, 3 to 4 hitches per repeat): the same software-rendering floor the probe found.
- **The arms are not told apart at 6x.** MEASURED. Every Lean pair verdict (rate rule and hitch rule, over the 3 samples) is "not told apart" in all four windows. The A/A spread (base against aa, in points) grows
  from 0.0 to 7.8 at 1x (7.8 only at 1280 end; 0.0 to 1.7 at 390) to 6.6 to 14.8 at 6x, larger than any gap between arms (largest pair difference 7.9 points, 390 end base against cand, spread 14.8; at 1280 end 6.4 points, orig against base, spread 10.0). One 390 hero sample ranged from 11.7 % to 41.6 %
  between jobs for the same arm, so job noise at 6x is large. A hitch-rule sample said "second smoother" once (390 end, orig against cand) and the rule over three samples stayed "not told apart".
- **The ranking does not match WebKit in the hero window.** MEASURED against the WebKit cadence (run 39634194664, width 390). macOS WebKit hero: 43 hitches per repeat for the original against 4 to 5 for the rewrite and the
  look arm (timeline on; timeline off: hero 24 against 6 to 11, end 11/8/8/9); the phone session 2026-10-21 hero: 372 hitch ms per second (original) against 47 (rewrite) and 55 (look). Chromium 6x hero: 26.4 % (orig), 25.7 % (base), 27.6 % (aa), 26.3 % (cand), 9 hitches per repeat in each.
  Chromium 1x hero even has the original slightly smoother (0 against 1 hitch per repeat; the rewrite's one 83 ms frame at scroll 672 px, probe finding). So the throttle does not recreate the WebKit original-versus-rewrite gap.
- **End of page: direction agrees with the phone only weakly.** 390 end at 6x: orig 28.9 %, base 32.0 %, aa 26.5 %, cand (look) 24.1 %; look lowest, as on the phone finish zone (look 96 hitch ms per second against 213 rewrite and 219 original),
  but the 7.9 points between base and cand are inside the 14.8 point A/A spread. macOS WebKit end hitches per repeat 7 / 10 / 9 / 9 (orig / base / aa / look) do not separate the arms either.
- **Reading (INFERRED).** The throttle slows the page's whole main thread, the rAF recorder and the input dispatch alike, so it adds a common floor (30 fps frames, p50 33.3 ms at 390 hero) to every arm. The WebKit gap comes from the
  original's layout work (Layout 2491 ms against 86 ms per hero window on macOS, note `10-2x-smoothness-webkit.md`), which Chromium does not pay at 1x and which a uniform slowdown does not reproduce. 6x is a cheap way to find
  windows that lag at all, not a way to rank arms.

## Runs

Workflow `smoothness.yml`, Chrome Headless Shell 156, ubuntu-24.04-arm, 7 repeats per arm per window per job, 3 jobs per width (independent runners), widths 390 and 1280, arms `orig`, `base`, `aa`, `cand`.
Arms by resolved flags: `cand` is `?fw=morph.tween:scroll-lock,nav:earn-no-transition` (config hash `205fc308455f455f`, the base rewrite is `ede2c7641aacf2d2`), the same `look` flags as the WebKit legs.
The throttle covers the scripted scroll only (the page loads and settles at full speed); no traced repeats under 6x.

| round | run | branch | throttle | candidate | state |
| --- | --- | --- | --- | --- | --- |
| a | 39924675073 | ci/smoothness-cpu-throttle-1x | 1x | none: a copy of base (hash `ede2c7641aacf2d2`) | complete, supplement |
| a | 39924693045 | ci/smoothness-cpu-throttle-6x | 6x | none: a copy of base | complete, supplement |
| b | 39927164863 | ci/smoothness-cpu-throttle-1x | 1x | look flags | complete, main result |
| b | 39927184622 | ci/smoothness-cpu-throttle-6x | 6x | look flags | complete, main result |

Round a's commit carried the `[trajectory ...]` text on its title line instead of its own line, so the parser read no flags (the run's cells say candidate `default`). It is kept as a second sample of `orig`, `base` and `aa`
(`results/smoothness-throttle/a-empty-cand/`) and is never used for `cand`. Job time: 1x 9 to 15 min, 6x 6 to 9 min (under the 45 min cap).

## Per window and arm, 1x against 6x (round b, runs 39927164863 and 39927184622)

Rate = bad frames per frame, percent, median over 3 samples (range). Hitches/rep = frames over 60 ms per repeat, median over all 21 repeats.

| width | window | arm | rate % 1x | rate % 6x | hitches/rep 1x | hitches/rep 6x | p95 ms 1x / 6x |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | hero | orig | 0.0 (0.0-0.0) | 26.4 (11.7-41.6) | 0 | 9 | 16.8 / 66.6 |
| 390 | hero | base | 0.6 (0.6-0.6) | 25.7 (11.3-42.4) | 1 | 9 | 16.8 / 66.7 |
| 390 | hero | aa | 0.6 (0.6-0.7) | 27.6 (12.5-42.3) | 1 | 9 | 16.8 / 66.6 |
| 390 | hero | cand | 0.6 (0.6-0.7) | 26.3 (12.2-43.3) | 1 | 9 | 16.8 / 66.6 |
| 390 | end | orig | 0.7 (0.7-1.0) | 28.9 (23.4-34.3) | 0 | 11 | 16.8 / 83.3 |
| 390 | end | base | 0.7 (0.5-0.9) | 32.0 (22.3-37.8) | 0 | 10 | 16.8 / 66.7 |
| 390 | end | aa | 0.7 (0.6-0.9) | 26.5 (20.4-39.3) | 0 | 11 | 16.8 / 66.7 |
| 390 | end | cand | 0.7 (0.6-0.8) | 24.1 (19.0-31.6) | 0 | 10 | 16.8 / 66.7 |
| 1280 | hero | orig | 4.4 (4.0-5.3) | 22.1 (19.9-25.5) | 0 | 10 | 33.4 / 66.7 |
| 1280 | hero | base | 4.8 (4.6-5.4) | 24.7 (19.3-27.1) | 0 | 9 | 33.4 / 66.7 |
| 1280 | hero | aa | 5.1 (4.9-5.7) | 25.0 (18.6-25.8) | 0 | 8 | 49.9 / 66.6 |
| 1280 | hero | cand | 5.0 (4.5-5.3) | 25.3 (17.3-25.9) | 0 | 9 | 33.5 / 66.6 |
| 1280 | end | orig | 17.6 (17.6-19.7) | 41.1 (30.9-42.6) | 4 | 14 | 50.1 / 100.0 |
| 1280 | end | base | 18.6 (17.8-18.6) | 47.5 (37.9-47.9) | 4 | 15 | 66.6 / 100.0 |
| 1280 | end | aa | 19.4 (17.8-20.8) | 46.1 (35.8-51.3) | 3 | 15 | 50.1 / 100.0 |
| 1280 | end | cand | 16.5 (16.2-20.1) | 43.4 (34.3-46.8) | 3 | 13 | 66.6 / 100.0 |

The full table with p50 and the round a table: `results/smoothness-throttle/compare.md` and `results/smoothness-throttle/a-empty-cand/compare.md`. Round a (orig, base, aa) at 390: hero 6x 37.5 / 38.8 / 38.4 %
(1x 0.0 / 0.6 / 0.6 %), end 6x 32.6 / 33.8 / 34.9 % (1x 0.5 / 1.0 / 0.9 %): the level of the 6x rates moves by up to 12 points between the two runs (runner load), the order orig at or below base does not.

## Lean verdicts (existing rules, no new rule), pair over the 3 job samples

Rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`, over samples `acrossDecisive` (two thirds agree, none disagree); counts are samples saying first / second / same / insufficient.

| width | window | pair | 1x | 6x | A/A spread 1x / 6x (points) |
| --- | --- | --- | --- | --- | --- |
| 390 | hero | orig vs base | first smoother (rate 2/0/1/0, hitch 3/0/0/0) | not told apart (0/0/3/0, 0/0/3/0) | 0.0 / 11.5 |
| 390 | hero | base vs cand | not told apart | not told apart | 0.0 / 11.5 |
| 390 | hero | orig vs cand | first smoother (rate 2/0/1/0, hitch 3/0/0/0) | not told apart | 0.0 / 11.5 |
| 390 | end | all three pairs | not told apart | not told apart (orig vs cand hitch 0/1/2/0) | 1.7 / 14.8 |
| 1280 | hero | all three pairs | not told apart (orig vs cand rate 1/0/2/0) | not told apart | 1.3 / 6.6 |
| 1280 | end | all three pairs | not told apart | not told apart | 7.8 / 10.0 |

"First smoother" at 390 hero 1x is the probe's known finding (the rewrite's single 83 ms frame, original smoother by 1 hitch per repeat), the opposite sign to WebKit. Under 6x it disappears into the spread.

## Ranking against WebKit and the phone (width 390, hero and end windows)

| source | run or session | hero | end of page |
| --- | --- | --- | --- |
| Chromium 6x (PROXY) | 39927184622 | all four arms tied (26 to 28 %, 9 hitches/rep) | cand 24.1 < aa 26.5 < orig 28.9 < base 32.0 %, inside the spread |
| Chromium 1x (PROXY) | 39927164863 | orig 0 < rewrite 1 hitch/rep (rewrite's 83 ms frame) | all tied (0.7 %) |
| macOS WebKit cadence | 39634194664 | orig 43 hitches/rep against 4 to 5 (timeline on; timeline off: hero 24 against 6 to 11, end 11/8/8/9) | 7 / 10 / 9 / 9 (orig / base / aa / look), not separated |
| iOS Simulator cadence | 39634194664 | orig 1 (no frames in the zone) against 4 / 5 / 6 | 4 / 5 / 4 / 5, not separated |
| iPhone session, 2026-10-21 | `results/phone/2026-10-21/summary-v2.md` | hitch ms/s orig 372 and 281 against rewrite 47, look 55 | hitch ms/s orig 219 and 195, rewrite 213, look 96 |

There is no iPhone screen recording in the repository; the phone rows are the device recorder session. Hero: the proxy does not match (WebKit and the phone put the original worst by several times, Chromium 1x and 6x do not).
End: the proxy has the look arm best, as the phone does, but only inside its noise; WebKit macOS does not separate the arms.

## What this changes

- A uniform CPU slowdown in Chromium is not a stand-in for WebKit's layout cost. Do not rank candidate flags with it; use it, if at all, to see whether a window lags at all on slow hardware.
- The 6x run is cheap (6 to 9 min per job) but noisy (A/A spread 6.6 to 14.8 points, job-to-job range up to 30 points in one cell). A decision at 6x needs more samples than 3 jobs, or a spread rule tuned to it (open for the lead: no new Lean rule this round).
- A real candidate flag arm needs the trajectory text on its own commit-message line and a site build that prerenders the query; both are now in the workflow (`[cpu-throttle=N]` or `cpu_throttle` also builds the `?fw=` page).

## Method and stand-ins

- Throttle: `launch.mjs` `setCpuThrottle` sends `Emulation.setCPUThrottlingRate { rate }` right before the recorder starts (after load and settle); allowlist 1 and 6 in `throttle.mjs`; the workflow reads the dispatch input `cpu_throttle`
  or the commit's `[cpu-throttle=N]` (shell allowlist 1 or 6). Local sanity, not a result: a busy loop took 32 ms at 1x, 181 ms at 6x.
- Tables: `cli.mjs cadence` per throttle directory (it refuses to mix throttles), `cli.mjs throttle --a <1x dir> --b <6x dir>`. Verdicts are the Lean twin `reduce.mjs`; medians over samples are TS.
- TS stand-ins (no Lean golden): `throttle.mjs` (allowlist), `throttle-table.mjs` (alignment, medians), the shell allowlist in the workflow.
- Limits: a proxy, three job samples per width, shared-runner noise, rAF recorder and input dispatch slowed with the page, no trace under 6x.

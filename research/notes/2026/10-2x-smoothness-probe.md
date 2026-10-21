# Smoothness probe: are the transitions of the original and the rewrite equally smooth?

Question (user): "lag may not be only the animation computation, it may include how smooth the transition is; did you measure
how smooth the transitions are, original and optimization?" Before this task: no. Only phone session 1b had measured the
original's rAF jank in the first 2500 px; nothing compared the arms, and the trajectory probes read values at stepped
(virtual) time, which cannot show a frame arriving late.

Every number below is MEASURED (CI runs named in Method) unless it says INFERRED. The text says what the tables show and no more.

## Answer

The verdict is main-thread rAF cadence (an in-page rAF loop; Lean `verdict` on the bad-frame rate, Lean `hitchVerdict` on
per-repeat counts of frames over 60 ms, Lean `across` over 10 CI job samples per width, 7 of 10 must agree and none may
disagree). Compositor drops from the Chromium trace are reported beside it, below, and never enter it.
The third arm, labelled "empty preset", is `?preset=v2-proved`; that preset was empty (`fw {}`) at every cadence SHA, so the
arm runs the rewrite's config (hash equal to the rewrite's in all 40 cells). It is a second copy of the rewrite, not a flag arm.
"First" means the first named arm is smoother. n = 10 job samples per width (runs 39580977630, 39583122954, 39585007706,
39589237987; one job is one sample, each on its own runner).

| window | width | pair | rate rule (first / second / same of 10) | hitch rule (first / second / same of 10) | how sure |
| --- | --- | --- | --- | --- | --- |
| hero scroll | 390 | original vs rewrite | 6 / 0 / 4 | 10 / 0 / 0 | hitch: original smoother (10 of 10, every rep of the rewrite has one hitch, original none); rate: not told apart (6 of 10 say original, 7 are needed) |
| hero scroll | 390 | rewrite vs empty preset | 2 / 0 / 8 | 0 / 0 / 10 | not told apart |
| hero scroll | 390 | original vs empty preset | 7 / 0 / 3 | 10 / 0 / 0 | original smoother on both rules (rate: 7 of 10, the bar) |
| hero scroll | 1280 | original vs rewrite | 0 / 0 / 10 | 0 / 0 / 10 | not told apart (median rate difference 0.65 points, A/A spread 1.29) |
| hero scroll | 1280 | rewrite vs empty preset | 0 / 0 / 10 | 0 / 0 / 10 | not told apart |
| hero scroll | 1280 | original vs empty preset | 1 / 0 / 9 | 0 / 0 / 10 | not told apart (difference 0.56, spread 1.29) |
| end-of-page morph | 390 | all three pairs (the third arm is the empty preset) | 0 / 0 / 10 | 0 / 0 / 10 | not told apart (differences 0.11, -0.11, 0.12 points; spread 0.89) |
| end-of-page morph | 1280 | all three pairs (the third arm is the empty preset) | 0 / 0 / 10 | 0 / 0 / 10 | not told apart (differences 0.60, -0.42, 0.18 points; spread 6.64) |

Bad-frame rate per arm (percent, median over the 10 samples, min-max in brackets):

| window | width | original | rewrite | empty preset (= rewrite config) |
| --- | --- | --- | --- | --- |
| hero | 390 | 0.00 (0.00-0.00) | 0.58 (0.57-0.82) | 0.66 (0.57-0.75) |
| hero | 1280 | 4.88 (2.11-5.99) | 5.34 (2.85-7.09) | 5.52 (2.67-6.63) |
| end | 390 | 0.98 (0.47-1.60) | 0.97 (0.72-1.47) | 1.20 (0.84-1.59) |
| end | 1280 | 20.12 (11.75-25.85) | 20.84 (12.02-24.44) | 21.20 (11.40-23.82) |

Presented and dropped compositor frames, from the trace of the page's own frame sink, run 39589237987 only (3 jobs x 5 traced
repeats per arm, so 15 repeats per arm and window; traced reps never enter a verdict). A frame is one `frame_sequence`;
"dropped" = any of its reporters dropped, "dropped (all)" = every reporter dropped:

| window | width | arm | frames | presented | dropped (%) | dropped (all) (%) |
| --- | --- | --- | --- | --- | --- | --- |
| hero | 390 | original | 2614 | 2359 | 255 (9.8) | 49 (1.9) |
| hero | 390 | rewrite | 2678 | 2343 | 335 (12.5) | 115 (4.3) |
| hero | 390 | A/A copy | 2674 | 2337 | 337 (12.6) | 118 (4.4) |
| hero | 390 | empty preset | 2664 | 2346 | 318 (11.9) | 114 (4.3) |
| hero | 1280 | original | 3019 | 2279 | 740 (24.5) | 713 (23.6) |
| hero | 1280 | rewrite | 3036 | 2292 | 744 (24.5) | 716 (23.6) |
| hero | 1280 | empty preset | 3031 | 2295 | 736 (24.3) | 708 (23.4) |
| end | 390 | original / rewrite / empty preset | 1897 / 1893 / 1891 | 1809 / 1806 / 1806 | 88 / 87 / 85 (4.6 / 4.6 / 4.5) | same as dropped |
| end | 1280 | original / rewrite / empty preset | 1955 / 1965 / 1964 | 982 / 992 / 998 | 973 / 973 / 966 (49.8 / 49.5 / 49.2) | 971 / 973 / 966 |

What the two views show together: at 390 hero the rewrite arms drop about 2.3-2.4 times as many frames outright as the original
(115-118 against 49 of about 2650); the A/A pair differs by 3 (115 vs 118), so the A/A noise is small against that gap. In
the other three cells the arms are within 1 percentage point of each other (software rendering drops
half of the 1280 end frames in every arm). No test decides these counts; they are reported, not judged.

- The morph at the end of the page is as smooth in the rewrite as in the original on this runner at both widths. At 1280 the numbers cannot rank any arm: the A/A pair differs by more than any arm does.
- The one cadence difference: at 390 px the rewrite loses about 5 frames (83 ms between rAF callbacks) when the hero scroll
  passes 672 px, once in every rep of every rewrite arm (rewrite, A/A copy, empty preset) in all 10 job samples; the original has
  a 33 ms gap at the same place and no more.
- Limit of the rate rule (why two rules): in this cell one hitch per rep is about 0.58 points, which is the whole effect and,
  in 7 of 10 samples, also the A/A spread (0.58-0.60; 0.01-0.02 in the other 3, which all say "original"). The 4 of 10 "same"
  samples in the rate column are samples where the original-minus-rewrite difference (0.57-0.58) is 0.01 under the spread
  (0.58-0.59) in each of the 4, so the rule's rate-plus-spread test cannot separate them; this is the rule's coarseness,
  not noise in the effect. The hitch rule compares per-repeat hitch counts (original 0 in every rep, rewrite 1 in
  every rep) and says "original" 10 of 10 times.
- Cause, INFERRED and not proved. The browser's long-animation-frame entry for that frame (in all 7 reps of every rewrite arm in 9 of the 10 samples,
  hitch table of `cadence.table.md`; the first sample recorded none) lasts 76-78 ms in 18 of the 21 rewrite-arm reps of the raw
  data of run 39589237987 job `smoothness-390-1` and 61 ms in the other 3, with no script and no blocking time in any, so it is
  render work, not JS (the durations and empty script lists are in that job's artifact, not in the tables). Two candidates in the traced reps of the page renderer (table in
  `cadence.table.md`, "Fixed slow-event names"), 390 hero, 15 reps per arm:

  | arm | decode tasks of 15 ms or more | longest decode (ms) | summed decode time (ms) | `ProxyMain::BeginMainFrame` of 15 ms or more | longest (ms) |
  | --- | --- | --- | --- | --- | --- |
  | original | 30 | 54.9 | 2297 | 6 | 16.3 |
  | rewrite | 60 | 57.0 | 3198 | 11 | 18.1 |
  | A/A copy | 60 | 54.7 | 3226 | 11 | 17.8 |
  | empty preset | 60 | 54.6 | 3231 | 6 | 17.3 |

  (a) Image decodes: the rewrite arms do twice as many decodes of 15 ms or more as the original, each about as long. (b) The
  main thread's BeginMainFrame: the longest is 1-2 ms longer in the rewrite arms (17.3-18.1 against 16.3 ms), and the count of
  15 ms or more is 11 in the rewrite and the A/A copy and 6 in the empty preset and the original; the three rewrite-config arms
  (rewrite, A/A copy, empty preset) have the same config, so their counts of 11, 11 and 6 are run noise and the count does not
  point to a cause; the summed BeginMainFrame time is the same in all four (10.6-10.8 s). Both (a) and (b) are INFERRED;
  neither is shown to be the cause of the 83 ms frame. Which images, and why twice, is open (follow-up).
- Part A (existing trajectory data, no new run) per window, property and arm: `results/smoothness-probe/continuity.table.md`
  (property = node of the registry, its part named; run ids per row). Cells where the faithful rewrite differs from the original
  beyond the original's own run-to-run range, restated from the first table of that file (Chromium; median over runs, range
  in brackets; the rewrite ranges and run counts are those of its "Window totals per arm"):

  | window | ideal | cell | runs per arm | original | rewrite |
  | --- | --- | --- | --- | --- | --- |
  | 390 hero | line | nodes moving in the window | 33 | 7 | 9 |
  | 390 hero | line | nodes flagged | 33 | 6 | 8 (6-16) |
  | 390 hero | line | `hero.stage`, `hero.deck`: moved | 33 | not moving | moving in 16 of 33 runs |
  | 1280 hero | line | defects per push | 29 | 0 | 12 (0-24) |
  | 390 end-open | ref | defects per push | 33 | 0 (0-9) | 16 (5-40) |
  | 390 end-open | ref | `logo` defects, `panel` defects | 33 | 0 (0-4), 0 (0-1) | 5, 5 |
  | 390 end-close | ref | defects per push | 33 | 20 (17-25) | 29 (19-60) |

  No other Chromium cell differs, and no macOS WebKit cell differs (end window only, see Limits). The rewrite's own run-to-run
  range is wider than the original's in these cells (the original is 0 in several), so these are differences in the middle of a
  wide rewrite range. Per flag, every cell that differs from the faithful rewrite in either direction (2-5 runs per flag, so
  thin) is the second table of `continuity.table.md` (column arm); this note does not summarise it.

## Method (two parts, decided in Lean)

- A, continuity: Lean `Fw.Gate.Smooth` metrics (stall, jump, reversal, late tail against a straight-line ideal and against
  the original's own response) over the raw readings of 45 existing trajectory runs, Chromium and macOS WebKit, widths 390 and
  1280, 1564 records. Per window, property (node) and arm: `results/smoothness-probe/continuity.table.{md,json}`. The
  "differs" rule that picks the cells above (an arm's median outside the other arm's min-max over runs) is a TS stand-in that
  picks cells to read; it decides nothing.
- B, cadence: a scripted wheel scroll (hero: 60 x 42 px every 16 ms; end: approach, rest, push open, hold 1 s, push close,
  hold 1 s) in Chrome Headless Shell on the free arm runner, real compositor timing. An in-page rAF loop gives the intervals.
  Four arms interleaved per repeat with rotating order: `orig`, `base` (faithful rewrite), `aa` (same rewrite, second server),
  `cand` (`?preset=v2-proved`; at every cadence SHA (29bcad69, 9159fc9b, f26fad3f, 26e7dd04) that preset was empty,
  `{"extends":"original","fw":{}}`, and its config hash equals `base`'s in all 40 cells, so `cand` is a second copy of the
  rewrite, called "empty preset" in this note ("cand" in the tables), and the B legs measured no flag arm). 7 verdict repeats plus traced repeats (5 per job in run 39589237987, 3 per job before; reported
  apart). A bad frame is a gap over 34 ms (rate rule: an arm wins only when its rate plus the A/A spread is under the other's,
  Lean `judge`); a hitch is a gap over 60 ms (hitch rule: Lean `hitchVerdict`, an arm wins only when every repeat of the other has
  more hitches than every repeat of it and the A/A pair is itself not told apart). Across the 10 samples Lean `across` asks 7
  to agree and none to disagree; the golden `packages/contracts/golden/gate/smooth.jsonl` drives the TS twin.
- Trace counts come from the page's compositor sink only: the renderer process with the most `BeginMainThreadFrame` events and its
  layer tree with the most `DrawFrame` events (the browser process draws its own UI frames and has its own reporters; the test
  replays a two-process fixture). The slow-event table has a fixed row set (BeginMainFrame, Paint, UpdateLayoutTree, Layout,
  image decode task) with no cap. Traces from before the filter (336 windows, runs 39580977630, 39583122954, 39585007706) hold counts
  over every process and are not shown.
- Runs: 39580977630 (1 sample per width), 39583122954 and 39585007706 and 39589237987 (3 sets per width, each its own runner).
  Verdict tables use all four; the trace tables use run 39589237987.

## Limits

- Linux runner with software rendering at 60 Hz: ranks the arms, gives no phone time. The phone hitch may differ (image decode is on
  the GPU path there). CI software-rendering noise is bounded by the A/A pair, not removed.
- Cadence has no flag arm. The v2-proved preset was empty (`fw {}`) at every cadence SHA, so its config hash equals the
  rewrite's in all 40 cells and the empty-preset column is a second copy of the rewrite; the note makes no claim that any flag
  or preset changes the cadence. The preset rows of the continuity table (runs R4 and R7) ran at SHA 718c619d, a commit that
  restored the eight-flag preset for that dispatch; at the cadence SHAs it was empty. The note states no per-flag continuity effect.
- Chromium only for cadence. The WebKit cadence leg (Web Inspector or a macOS lane) is owned by the task
  smoothness-webkit-cadence and is not delivered here. Linux WebKit renders about 150 ms frames in software, and a macOS leg needs a measured-p90 row in
  `Fw.Ci.Pool.Caps`. WebKit coverage of original against rewrite is the continuity data of the end window only: macOS WebKit
  hero has no original rows in the trajectory runs, and Linux WebKit was skipped. So WebKit hero smoothness of the original is
  unknown.
- The verdict uses main-thread rAF cadence. The compositor's dropped frames are a different clock (they count frames the
  compositor did not present) and are reported beside it; at 1280 about half the end frames are dropped in every arm because of software
  rendering, with no effect on the verdict.
- Tracing slows the page; traced reps never enter a verdict. The rAF loop runs in every arm alike.
- The 1280 end window is noisy (11-26 % bad frames for every arm, A/A spread up to 10 points): it only shows that no arm is worse
  by more than that spread.
- Part A spans different commits and cannot judge real-time smoothness; its absolute defect counts include easing. The node
  registry has no "people reveal" node in the hero window and no nav-morph node there (the nav morph nodes exist only in the end
  window), so those two transitions are not in the hero rows.
- The 390 hitch cause stays INFERRED.

## Follow-ups (not in this task)

- A cadence arm with real flags: the v2-proved preset was empty at every measured SHA, so the cadence lane has not yet measured
  any flag (lead re-plan).
- Original hero rows for macOS WebKit (and a WebKit cadence leg, which needs a pool cap row).
- A cause trace with image URLs for the 390 hitch near 672 px scroll: which images decode twice, and why.
- Registry nodes for the people reveal and the nav morph inside the hero window.

# Smoothness probe: are the transitions of the original and the rewrite equally smooth?

Question (user): "lag may not be only the animation computation, it may include how smooth the transition is; did you measure
how smooth the transitions are, original and optimization?" Before this task: no. Only phone session 1b had measured the
original's rAF jank in the first 2500 px; nothing compared the arms, and the trajectory probes read values at stepped
(virtual) time, which cannot show a frame arriving late.

## Answer

| window | width | smoother arm | by how much | how sure |
| --- | --- | --- | --- | --- |
| hero scroll (first 2500 px) | 390 | original | rewrite has one extra 83 ms frame at scroll 672 px in every rep; bad-frame rate 0.00 % vs 0.57-0.82 % (median +0.58 points) | MEASURED, 7 job samples, 5 of 7 beat the A/A spread |
| hero scroll | 1280 | none | original 2.1-5.4 %, rewrite 2.9-6.1 % (median +0.56 points, spread 1.3) | MEASURED, 7 of 7 inside the spread (same sign every time, so a small lean to the original, not proved) |
| end-of-page morph (open and close) | 390 | none | 0.6-1.6 % both | MEASURED, 7 of 7 same |
| end-of-page morph | 1280 | none | 11.8-23.6 % for every arm (CI software rendering); median difference 0.77 points against a spread of 6.6 | MEASURED, 7 of 7 same |
| `?preset=v2-proved` against the faithful rewrite | both | none | median difference under 0.4 points everywhere | MEASURED, 7 of 7 same in three cells; 390 hero 6 of 7 same, 1 of 7 says the faithful rewrite is smoother than the preset |

- The morph at the end of the page is as smooth in the rewrite as in the original, and the preset does not change that. On this
  runner the numbers cannot rank them: the A/A pair (the same rewrite on a second server) differs by more than any arm does.
- The one real difference: at 390 px the rewrite loses 5 frames (about 83 ms between rAF callbacks) when the hero scroll passes
  672 px (16 wheel events in), in all 7 reps of each of the three rewrite arms (faithful, A/A copy, preset) in all 7 job
  samples. The original has a 33 ms gap at the same place and no more. The preset does not fix it.
- Cause, INFERRED and not proved: the browser's long-animation-frame entry for that frame is 76 ms with no script and no
  blocking time, so it is render work, not JS. The traced reps show image decodes of 15 ms or more on the raster workers: the
  in each of the three jobs of run 39585007706 the 3 traced reps hold 12 such decodes per rewrite arm (longest 54-55 ms) against 6
  for the original (longest 54-56 ms). The decode cost is the same, the rewrite does it twice as often in this window. Which images, and why twice, is open (follow-up in the handoff).
- Part A (existing trajectory data, no new run) agrees: under both ideal curves the original and the rewrite have the same
  defect counts and tails (chromium 1280, close, line ideal: orig 47 (42-53) vs rewrite 49 (43-101); ref ideal: 18 vs 18; open: 49-50
  both). The only flag that changes a count is `nav:earn-no-transition` (tail 2). The rewrite's run-to-run range is wider
  (up to 100 defects with the same config hash) which is why the cadence part had to bring its own A/A pair.

## Method (two parts, both decided in Lean)

- A, continuity: Lean `Fw.Gate.Smooth` metrics (stall, jump, reversal, late tail against a straight-line ideal and against
  the original's own response) over the raw readings of 45 existing trajectory runs, chromium and macOS WebKit, widths 390 and
  1280, 1564 records. Tables: `results/smoothness-probe/continuity.table.{md,json}`.
- B, cadence: a scripted wheel scroll (hero: 60 x 42 px every 16 ms; end: approach, rest, push open, hold 1 s, push close,
  hold 1 s) in Chrome Headless Shell on the free arm runner, real compositor timing. An in-page rAF loop gives the intervals.
  Four arms interleaved per repeat with rotating order: `orig`, `base` (faithful rewrite), `aa` (same rewrite, second server),
  `cand` (`?preset=v2-proved`). 7 verdict repeats plus 3 traced repeats (reported apart). A bad frame is a gap over 34 ms; an arm
  wins only when its rate plus the A/A spread is under the other's (Lean `judge`). Tables: `results/smoothness-probe/cadence.table.{md,json}`.
- Runs: 39580977630 (1 sample per width), 39583122954 and 39585007706 (3 sets per width, each its own runner).

## Limits

- Linux runner with software rendering at 60 Hz: ranks the arms, gives no phone time. The phone hitch may differ (image decode is on
  the GPU path there).
- Chromium only. Linux WebKit renders about 150 ms frames in software, and a macOS leg needs a measured-p90 row in `Fw.Ci.Pool.Caps`.
  So WebKit smoothness is known from Part A only.
- Tracing slows the page; traced reps never enter the verdict. The rAF loop runs in every arm alike.
- The 1280 end window is noisy (11-24 % bad frames for every arm, A/A spread 6-7 points): it only shows that no arm is worse
  by more than that spread.
- Part A spans different commits and cannot judge real-time smoothness; its absolute defect counts include easing.

---
id: 2026-10-2x-morph-end-measure
kind: note
title: "Morph end bricks on the Simulator with real touches: no brick measurably cuts reversals or spring-back fights; only the scroll unthrottle removes the still runs; release has no data"
status: review
created: 2026-10-25
topics: [morph, end-of-page, touch, simulator, webkit, bricks, ci]
---

# Morph end bricks on the Simulator with real touches

## Answer

- MEASURED, small n: no brick (clamp, flip, release, all three) shows fewer reversals, spring-back fights or displaced frames per open stretch than the faithful rewrite. Rates overlap and the counts are 1 to 10 open stretches per arm.
- MEASURED: `engine.scroll:unthrottle` is the only arm that removes the still runs (1-9 frame runs per 1000 frames: 1.3 against 27 to 28 for every other arm). Its reversals and fights per open start are not lower (5.5 and 3.0 against 4.0 and 1.9).
- `release` has no usable pass (3 attempts timed out). Nothing is known about it from CI.
- The flip brick was not exercised: direction flips within a touch were 0 in every pass.
- INFERRED: clamp is not a differentiator in this lane. The pin sits at 5220 to 5223 px in every arm, below the page maximum (5227 to 5267 with the iOS toolbar, rubber band up to about 5316), so a clamp has nothing to clamp.
- The result is thin because of the runners, not the design: of 18 planned job slots in three dispatches, 5 jobs gave data, 10 passes were usable (`results/morph-end-measure/attempts.md`).

## Table per composition

Pooled over the usable passes of run 40105567688 (jobs 1, 6; 4 drag cycles) and run 40126807029 (jobs 2, 4, 6; 2 drag cycles). Run 40112979355 gave no usable pass. Reversals, fights and displaced frames are per open start, so the two cycle counts pool. Each close is by finger down, each re-open by finger up, in every pass (closes 21 of 21 by finger down; re-opens 11 of 11 by finger up; the `all` and `all-unthrottle` passes ended without a re-open).

| Composition | Usable passes | Open starts | Reversals per open start | Fights per open start | Displaced frames per open start | 1-9 frame runs per 1000 frames | Finish still runs | Lean verdict |
|---|---|---|---|---|---|---|---|---|
| faithful (rewrite) | 3 | 10 | 40 / 10 = 4.0 | 19 / 10 = 1.9 | 96 / 10 = 9.6 | 27 (24.1 to 35.1) | present | base |
| clamp | 2 | 4 | 21 / 4 = 5.25 | 10 / 4 = 2.5 | 54 / 4 = 13.5 | 28.1 | present | no-signature, not-lifted |
| flip | 2 | 4 | 16 / 4 = 4.0 | 9 / 4 = 2.25 | 38 / 4 = 9.5 | 27.2 | present | no-signature, not-lifted |
| release | 0 | 0 | no data | no data | no data | no data | no data | no-data |
| all three (`?preset=morph-end-all`) | 1 | 1 | 5 | 2 | 11 | 27.9 | present | no-data (no base in the job) |
| all three + `engine.scroll:unthrottle` | 2 | 2 | 11 / 2 = 5.5 | 6 / 2 = 3.0 | 29 / 2 = 14.5 | 1.3 (0 and 1.7) | gone | no-signature, lifted |

Run ids: faithful jobs 1 and 6 of 40105567688, job 4 of 40126807029; clamp jobs 4 and 6 of 40126807029; flip jobs 4 and 6 of 40126807029; all job 2 of 40126807029; all + unthrottle job 6 of 40105567688 and job 4 of 40126807029. Per job rows: `results/morph-end-measure/run-40105567688-table.md`, `run-40126807029-table.md`, pooled `pooled-runs-40105567688-40126807029.md`.

Tags: every number is MEASURED on CI (Simulator, real XCUITest touches); the per-open-start rates are INFERRED as poolable across cycle counts (they are a rate, but the first cycle of a pass may differ).

## What each brick changes

| Brick | Change in this lane | Status |
|---|---|---|
| clamp | none visible: reversals 5.25 and fights 2.5 per open start against 4.0 and 1.9 (2 passes against 3) | MEASURED, n small; INFERRED cause: the pin is already below the maximum |
| flip | none visible: 4.0 and 2.25 per open start; wobble fix not exercised (0 direction flips in a touch) | MEASURED, n small |
| release | unknown | no data |
| all three | one pass: 5 reversals, 2 fights on one open start | MEASURED, n 1 |
| unthrottle (added to all three) | removes the 27 to 28 per 1000 still runs (to 1.3); reversals and fights per open start do not fall (n 2) | MEASURED |

The finish runs at a frame gap of about 30 to 39 ms (25 to 35 fps median) on CI, so the Lean band metric (runs of exactly 5 to 6 frames) found a signature in 1 pass only; the cadence-aware count (runs of 1 to 9 frames) carries the unthrottle result and is exploratory.

## Limits (named)

- Few passes: dispatch 1 lost most attempts to 300 s touch timeouts and a wedged Simulator; dispatch 2 lost 4 runners (60 to 80 min frozen VM, no artifact); dispatch 3 (reset of the Simulator before a retry, 4 arms per job) gave jobs 2, 4, 6 and lost jobs 1, 3, 5. The three dispatches the task allowed are used. The host load average was 300 to 860 on every run (MEASURED), also on the earlier good run 40079501230.
- Touch-driver retries may lose passes, and a retry boots the Simulator afresh in dispatch 3 only.
- The Simulator has no phone GPU or power state. Felt smoothness is the user's phone review.
- The close and re-open counting by finger direction is a TS STAND-IN (`packages/measure-webkit/src/throttle/morph-end.mjs`, no Lean spec). Fights, reversals and displaced frames come from the twin of `Fw.Measure.TouchLock`; still runs and the band verdict from the twin of `Fw.Device.FinishRuns`.
- maxScrollY under the iOS toolbar is INFERRED.
- Dispatch 1 used 4 cycles, dispatch 3 used 2 cycles; the table pools by open start.

## Phone review (for the lead's step)

Ask the user to drag past the end of the home page on the phone, release, and drag back, on these pages (append to the composer origin): `/?fw=morph.end.clamp:on`, `/?fw=morph.end.flip:on`, `/?fw=morph.end.release:on`, `/?preset=morph-end-all`, and `/?fw=morph.end.clamp:on,morph.end.flip:on,morph.end.release:on,engine.scroll:unthrottle`, against the plain page. Questions: does the panel still re-open and push the page back when the finger turns; does the page feel steadier with release; does unthrottle make the drag smoother. Release is the one CI could not measure, so try it first.

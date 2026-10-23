---
id: 2026-10-23-carousel-swap-webkit
kind: note
title: "People carousel swap windows on the WebKit Simulator: crop against faithful, per window"
status: final
created: 2026-10-23
topics: [webkit, carousel, swap-window, measure]
---

# People carousel swap windows, WebKit Simulator

Question: inside the swap windows of the people carousel (5 avatars on, 4 off), does the crop arm (`?fw=people.carousel:crop`)
show fewer Layout, Paint, Composite and RecalculateStyles Timeline rows than the faithful arm, beyond the A/A floor of the same
passes (faithful-a and faithful-b are captured in each pass)? Task `carousel-swap-followups` adds a cause for the every-third-window Layout/Paint pattern, a minimum-n reason, and one run of 3 jobs.

## Design

- CONFIRMED (code): the schedule, the phase of a row, the counts, the background state and the cell verdict are the Lean module
  `lean/Fw/Measure/SwapWindow.lean` (golden `packages/contracts/golden/measure/wkcost.jsonl`, TS twin
  `packages/measure-webkit/src/lag/swap.mjs`). Windows: swap k < 8, rest k < 7 (the control). A (window, kind) cell is decided on its
  own, never pooled: win, loss, or unresolved with a reason (overlap, drift, noSamples, floorBroken, fewSamples).
- `unresolved:fewSamples`: a faithful slot has fewer than `minFaithful` = 3 samples (theorems `cell_fewSamples_a1`,
  `cell_fewSamples_a2`, `cell_two_samples_undecided`; golden kind `swapCell`). Background state of a swap window (`bgOf`: idle,
  busy, mixed, unknown) from the Layout rows of the two rest windows next to it (`swapNeighbours`), busy from `busyMin` = 24 rows
  (golden kinds `swapBg`, `swapNeighbours`). The by-background tables and the report code are TS stand-ins (medians, tables).
- One capture = fresh load of one arm in the same Simulator session, scroll until the whole carousel lies in the viewport, a
  MutationObserver marks every swap with `performance.mark`, the Timeline rows are counted per window. A pass = faithful-a, crop-a,
  faithful-b, crop-b (flipped on odd passes). The crop arm also gets one diagnostic capture per job (7 s, no marks, Timeline on): a
  MutationObserver counts DOM writes per owner in 100 ms buckets, and `getAnimations` is listed before and after.

## Run (MEASURED)

| run | commit | jobs | result |
|---|---|---|---|
| 39983630584 | 3bfca9339 | r1 (job 120519161250), r2 (120519161142), r3 (120525218928) | success, 2 passes each, 8 windows in every capture |

Counted: 3 completed jobs at one commit, 6 passes, 24 captures, 12 per arm (faithful-a 6, faithful-b 6, crop 12), 3 diagnostic captures.
Each sample in `results/carousel-swap-webkit/people-carousel-crop.json` carries its job (`a1Job`, `a2Job`, `cropJob`, key
`<run>.<attempt>/<vm>/p<pass>`) and its background (`a1Bg`, `a2Bg`, `cropBg`). The numeric job id is not in the file (the workflow
passes no `FW_JOB_ID`), so the table above maps vm to job id from `gh run view`. Opt-in path CONFIRMED: head commit token
`[swap-lane]` -> `SWAP: --swap` (`.github/workflows/webkit-sim.yml:415`, also `VMS` 198, `TARGET` 200, `FW` 202, `COST` 413) ->
`cli.mjs` `--swap` (line 24, `swapSetup` line 35); every `*-lag.json` holds `passes[].cost.swap` with 4 captures.

History, not counted: 39968418529 (793f38e48) started no workflow, the head commit had the swap token but no `[ci:<lane>]` token;
39968644601 (6f09b8c45) ran r1 and r2 to success and r3 was cancelled at the job limit (58 min) after a late start (queued 37 min), so
it had 2 jobs.
Report: `results/carousel-swap-webkit/people-carousel-crop.md` and `.json`.

## Result (this run alone, per window and kind)

| kind | swap windows (8) | rest windows (7) |
|---|---|---|
| Layout | 8 unresolved:overlap | 7 unresolved:overlap |
| Paint | 6 win (swap:1 to swap:6), 2 unresolved:overlap (swap:0, swap:7) | 7 unresolved:overlap |
| Composite | 8 unresolved:overlap | 7 unresolved:overlap |
| RecalculateStyles | 8 unresolved:overlap | 7 unresolved:overlap |

No window is a loss. Layout rows per swap window over all samples: faithful 6..16 (n=12 per window), crop 2..16 (n=12). The model line
"faithful 13 Layout frames, the crop none" is contradicted for the crop: the report prints the measured crop minimum next to it, 2
rows in a swap window over 96 samples, median 5.5 (idle background only: 13 samples, minimum 3, median 4).

## The every-third-window pattern: cause (item 1)

MEASURED (report, background tables). The crop's swap windows come in two groups. With a busy background (both rest windows next to it
have at least 24 Layout rows) the crop's Layout median is 11.5 to 15 and its Paint median 19 to 34; with a mixed or idle background it
is 3 to 6.5 Layout and 8 to 13 Paint. Rest windows are two-state too: the crop's rest:0 to rest:6 ranges run 4..50 (a floor of 4 or 5 rows and a busy top of 47 to 50).
In 10 of 12 crop captures the busy swap windows are every third; two captures (r1/p2 first, r3/p2 first) are high in 5 to 6 of 8 windows, also on mixed or idle backgrounds (bgOf reads only the rest-window edges). The grid is the crop `cropBg` and counts of the JSON, in window order 0..7:

| job/pass | background (B busy, m mixed, i idle) | Layout rows |
|---|---|---|
| r1/p1 (crop 1 of 2) | imBmmBmi | 6 3 15 6 3 15 5 3 |
| r1/p2 (crop 1 of 2) | BmmBmmBB | 13 16 4 14 14 3 15 12 |
| r2/p1 (crop 1 of 2) | BBmmBmmB | 3 16 4 4 16 2 4 15 |
| r3/p2 (crop 1 of 2) | imBmmBmi | 14 3 14 12 3 14 11 3 |

So the windows are not fixed: it is windows 2 and 5 in r1/p1, r3/p1 and r3/p2, windows 0, 3, 6 (and 7) in r1/p2 and r2/p2, windows 1, 4
and 7 in r2/p1 (the old run showed 1, 4, 7 because its jobs had that phase). The period is three swap periods and the phase is the
capture's start time against a page timer, so the source is independent of the carousel.

MEASURED (diagnostic capture, crop arm, 3 jobs). Layout is a row on nearly every frame in busy runs of 18 to 19 buckets (1.8 to 1.9 s)
and near zero in idle runs of 12 buckets (1.2 s), then again: r1 B13 i12 B18 i12 B15, r2 B6 i12 B19 i12 B19, r3 B4 i1 B8 i11 B8 i1 B10 i12 B15
(busy = at least 4 rows per 100 ms bucket). Each busy run starts at a `hero-accent` write (`class`, `style`, `viewBox`, `d` of the
`hero.accent` part; three `class` writes per cycle, 0.9 s and 1.2 to 1.3 s apart: r1 buckets 3, 12, 25, 34, 43, 55, 64). The animation
lists name a running `hero-accent` `width` CSSTransition of 900 ms plus the 900 ms `strokeIn` and `strokeOut` CSSAnimations. The carousel
writes (`people-carousel:childList`, 126 per capture; `src`, 63) sit every 1.02 s and do not follow the busy runs.

CONFIRMED (code) the constants: `apps/site/src/parts/hero.accent/logic.ts:10` `IDLE_WAIT = 1250`, `:12` `DRAW_WAIT = 900` (draw out, draw
in), and `accent.module.css:13` `transition: width 0.9s` on `.drawingIn`. One cycle = 1250 + 900 + 900 = 3050 ms, the carousel's three
periods are 3 x (800 + 220) = 3060 ms (`people.carousel` REST_MS, SWAP_MS), so the phase drifts 10 ms per cycle (below one 100 ms
bucket in a 7 s capture; the one-bucket gaps inside r3's busy runs are not explained). The busy run (1.8 s) is the two 900 ms draws, the idle run (1.2 s)
is the 1250 ms wait.

CONFIRMED (WebKit source @862f17d) why both draws cost a Layout row on every frame: the strokeOut and strokeIn animations change stroke-dashoffset each frame, and a strokeDashOffset change requires layout (`Source/WebCore/style/StyleDifference.cpp:161`, svgDataChangeRequiresLayout via :399); during draw-in the `width` transition adds a box-width change (`:404`); one Layout row of
the Timeline is one `LocalFrameViewLayoutContext::performLayout` (`Source/WebCore/page/LocalFrameViewLayoutContext.cpp:223`
`InspectorInstrumentation::willLayout`, `:335` `didLayout`).

Status: the timing match is MEASURED in 3 of 3 jobs; the causal link (the `hero.accent` draw animations (stroke-dashoffset on both draws, width on draw-in) make the Layout and Paint
rows of the busy windows) is INFERRED from that match and the source. The test that would confirm it: the same pass with the
`hero.accent` frozen (its reduced-motion block, accent.module.css:138-152, sets transition: none and animation: none; turning off only the transition leaves the draw-out busy) must show no busy runs and the crop Layout median in every swap window at the idle level. No fix is made in the crop
part: the carousel is not the source, so the follow-up is a measurement change (freeze `hero.accent` in the lane), not a one-line
constant of the crop.

## Does faithful show the pattern? (item 1, second half)

Yes in the rest windows, MEASURED: faithful-a rest windows 5..49 to 5..50 and faithful-b rest windows 5..47 to 6..50 over rest:0 to
rest:6, the same two states as the crop (4..50). In the swap windows it is masked: faithful has its own Layout (13 rows at 60 Hz in the
model), faithful Layout median is 13.5 to 16 on a busy background and 14 to 15 on the idle windows (swap:0, swap:7), no gap, and the
faithful Paint is 31.5 to 48.5 against the crop's 19 to 34 on busy and 8 to 13 on idle. That the source is `hero.accent` in the faithful
arm too is INFERRED: the arms differ only in the `?fw=people.carousel` flag, and the diagnostic capture ran on the crop arm only.

## Minimum n and the by-background cells

With 6 faithful samples per slot no all-samples cell is `fewSamples`. Cut by background, the cells need 3 faithful samples each: on idle
backgrounds swap:0 and swap:7 have faithful n=2+4 (`unresolved:fewSamples`) and swap:1 to swap:6 have no sample
(`unresolved:noSamples`); on busy backgrounds all 8 are `unresolved:fewSamples` (faithful n=1+1 to 4+2). So this run cannot decide a
window on a quiet background: the verdicts above are on samples whose background is busy in many windows, and a busy background
makes the crop Layout as high as the faithful one, which is why Layout stays unresolved.

## Limits

- The CI Simulator is not the phone; phone feel is the user's to judge.
- A window starts at the DOM change (MutationObserver callback), not at the first painted frame; the page-side mark to window mapping
  is I/O glue with no proof, tested only against a stand-in carousel (`packages/measure-webkit/test/lag-swap-probe.test.mjs`).
- Rest window 7 is undefined; the original arm is not in this lane, only crop against faithful of one build.
- The background class (`bgOf`, 24 rows) has a Lean golden but the by-background medians and the diagnostic digit scale are TS
  stand-ins; a "mixed" window can still be busy at one edge (r1/p2 windows 1 and 4 show 16 and 14 rows).
- The diagnostic capture has one job per capture, crop arm, no faithful twin.
- Outside the task graph: `packages/measure-webkit/src/lag/probe.mjs` now runs the swap pass before the cost passes and keeps
  `costs.swap` if a later cost step fails (earlier runs lost jobs to a `layersScroll` inspector failure after pass 1).
- Not a trigger-path change: `lean/Fw/Ci/Trigger.lean` is untouched; the `[swap-lane]` token is read in the workflow only.

## Next

- Freeze `hero.accent` (reduced motion for that part only) in the swap lane and re-run: the confirming test above, and quiet-background
  cells that can reach win or loss.
- Add `FW_JOB_ID: ${{ job.check_run_id }}` to the sim step of `.github/workflows/webkit-sim.yml` so the file holds the numeric job id.
- More passes per job (the floor needs more faithful samples per window and background).

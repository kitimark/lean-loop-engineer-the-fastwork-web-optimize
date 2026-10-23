---
id: 2026-10-23-carousel-swap-webkit
kind: note
title: "People carousel swap windows on the WebKit Simulator: crop against faithful, per window"
status: final
created: 2026-10-23
topics: [webkit, carousel, swap-window, measure]
---

# People carousel swap windows, WebKit Simulator (task carousel-swap-webkit-lane)

Question: inside the swap windows of the people carousel (5 avatars on, 4 off), does the crop arm (`?fw=people.carousel:crop`)
show fewer Layout, Paint, Composite and RecalculateStyles Timeline rows than the faithful arm, beyond the same run's A/A floor?

## Design

- CONFIRMED (code): the schedule, the phase of a row, the counts and the cell verdict are the Lean module `lean/Fw/Measure/SwapWindow.lean`
  (golden `packages/contracts/golden/measure/wkcost.jsonl`, TS twin `packages/measure-webkit/src/lag/swap.mjs`).
  Windows: swap k < 8, rest k < 7 (the control). A (window, kind) cell is decided on its own, never pooled:
  win, loss, or unresolved with a reason (overlap, drift, noSamples, floorBroken).
- One capture = fresh load of one arm in the same Simulator session, scroll until the whole carousel lies in the viewport,
  a MutationObserver marks every swap on and off with `performance.mark`, the Timeline rows are counted per observed window.
  A pass = faithful-a, crop-a, faithful-b, crop-b (flipped on odd passes). The two faithful captures are the A/A floor.
- Cell rule: the crop range against both faithful ranges; win only when the crop range lies wholly below both.

## Runs (MEASURED)

| run | commit | job | result |
|---|---|---|---|
| 39932917436 | 48142c753 | r1, r2, r3 | success, but 0 swap windows in all 24 captures (`why: deadline`); superseded |
| 39937838325 | 58b1df271 | r1, r2 | success, 2 passes each, 8 windows in each of 16 captures |
| 39937838325 | 58b1df271 | r3 | cancelled at the job limit (58 min), no log, no file |
| 39947916723 | 8dc944f90 | r3 | success, 2 passes, 8 windows in each of 8 captures |
| 39947916723 | 8dc944f90 | r1, r2 | failed in the cost `layersScroll` step after pass 1 (inspector lost, Safari relaunch refused / `layersForNode` timeout); no lag file |

Counted: 3 jobs (39937838325 r1, r2; 39947916723 r3), 6 passes, 24 captures, 12 per arm.
Report: `results/carousel-swap-webkit/people-carousel-crop.md` and `.json`.

## Negative finding: the first run saw nothing

Run 39932917436 scrolled to the end of the page. Page order is hero, people, pain, commission, platform, so the people section was far
off screen and the carousel loop (gated by an IntersectionObserver) was idle: 0 windows in every capture (INFERRED from the page
structure; the fix below confirms it). The capture now records the scroll position, the reduced-motion flag, the observer
call count and the end child count so a silent window shows its cause.

## Result (MEASURED, class counts of the Timeline over 12 captures per arm)

Verdicts of the 15 windows x 4 kinds, per cell:

| kind | swap windows (8) | rest windows (7) |
|---|---|---|
| Layout | 8 unresolved:overlap | 7 unresolved:overlap |
| Paint | 2 win (swap:1, swap:5), 6 unresolved:overlap | 7 unresolved:overlap |
| Composite | 8 unresolved:overlap | 7 unresolved:overlap |
| RecalculateStyles | 8 unresolved:overlap | 7 unresolved:overlap |

No window is a loss. Answer: Paint is a win in 2 of 8 swap windows, every other cell is unresolved.

Layout rows per swap window (12 captures per arm, sorted):

| window | faithful | crop |
|---|---|---|
| swap:0 | 6..16, median 14 | 3..12, median 3.5 |
| swap:1 | 10..16, median 15 | 3..16, median 14.5 |
| swap:2 | 6..16, median 13.5 | 3..15, median 5.5 |
| swap:3 | 5..16, median 14 | 3..14, median 3.5 |
| swap:4 | 4..16, median 14 | 3..15, median 14 |
| swap:5 | 13..16, median 14 | 3..15, median 4 |
| swap:6 | 4..16, median 14 | 3..14, median 4 |
| swap:7 | 6..16, median 13 | 3..16, median 15 |

Paint rows per swap window: faithful 8..49 (medians 31..38), crop 6..22 (medians 7..21), one crop outlier of 54 in swap:0.

What the table shows:

- MEASURED: the crop has about 3 to 7 Layout rows in most swap windows where the faithful arm has about 14, but in windows 1, 4 and 7
  (every third) its median is 14.5 to 15, the same as the faithful arm. The cause of the every-third pattern is not found (open).
- MEASURED: the faithful floor is wide (4 to 16 in a window). The 4 to 6 values occur in some captures only (9 of 96 faithful window samples), and they are enough to make the crop range overlap, so the rule leaves the cell unresolved.
- MEASURED: Paint is lower in the crop in every window (medians 7..21 against 31..38), but only swap:1 and swap:5, where the faithful
  minimum is highest (28 and 30), clear the rule.
- The Lean model line "faithful 13 Layout rows, crop none" (INFERRED from the part model) is contradicted for the crop: the crop never
  shows 0, its floor is 3 rows per window (MEASURED), so something else lays out in the window.

## Limits

- The CI Simulator is not the phone; phone feel is the user's to judge.
- A window starts at the DOM change (MutationObserver callback), not at the first painted frame; the page-side mark to window mapping is
  I/O glue with no proof, tested only against a stand-in carousel (`packages/measure-webkit/test/lag-swap-probe.test.mjs`).
- Rest window 7 is undefined (the last swap has no following rest); the original arm is not in this lane, only crop against faithful of one build.
- 3 jobs completed; the other 3 of the two runs failed in the cost step or at the job limit; this is a Simulator inspector problem, not a swap-lane result.
- Not a trigger-path change: `lean/Fw/Ci/Trigger.lean` is untouched (held by counts-font-fidelity); the `[swap-lane]` token is read in
  the workflow only.

## Next

- Find what lays out in every third crop window (windows 1, 4, 7), for example by marking the avatar swap type in the capture.
- Take more passes per job (the floor needs more than 6 faithful samples per window) before judging Layout, Composite and RecalculateStyles.

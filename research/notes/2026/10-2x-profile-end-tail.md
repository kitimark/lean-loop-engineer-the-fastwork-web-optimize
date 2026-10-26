# Chromium swipe profile: a fixed tail after the end frame

Tags: MEASURED (CI run id named), CONFIRMED (Lean theorem or source cited), INFERRED (reasoned, not seen).

## Answer

* The swipe end rule had Lean for its decision (`Fw.Measure.Profile.Swipe.ended`, golden `profile.jsonl`) but none for what follows
  it. A limit end stopped the run 3 frames after the end (hold frames plus the touch lift); a stalled end waited 2 strokes of idle
  frames (164) first. CONFIRMED: `packages/measure-chromium/src/run.mjs` before this change (`stop = true` on the first `null`
  step), counts of runs 40339630528 (stalled, 164 frames after the end) and 40339622735 (limit, 3), note `10-2x-window-own-end.md`.
* New `Fw.Measure.SwipeEnd` (`lean/Fw/Measure/SwipeEnd.lean`): the run stops at `end + tail` for both end kinds, with
  `tail = max (windowReach + endWinFrames) (idleFrames + holdFrames + 1)`, `windowReach = 120` (derived from `pushWindows`, the start of
  `end 120+`), `endWinFrames = 40`. For swipe-touch-v1: tail 165.
* run.mjs holds no end decision of its own: `swipeEndFrame`, `swipeEndReason`, `swipeStops` (twins of Lean `endFrameOf`, `endReason`,
  `Swipe.stops`) are replayed against `packages/contracts/golden/measure/swipe-end.jsonl` by
  `packages/measure-chromium/test/profile-swipe-end.test.mjs`. `counts.json` meta.input gains `endFrame` and `tailFrames`.

## Theorems (PROVED, `lean/Fw/Measure/SwipeEnd.lean`)

| statement | theorem |
|---|---|
| the tail covers every reader window and the stall wait | `tail_ge_window`, `tail_ge_stall` |
| the last window start is 120 frames after the end, derived from `pushWindows` | `windowReach_eq`, `windowReach_spec` |
| a limit end (fires on the end frame, idle 0) stops at end + tail | `stopAt_limit` |
| a stalled end (fires `idleFrames` after the end) stops at end + tail | `stopAt_stalled` |
| both end kinds get the same stop frame | `stopAt_same_tail` |
| a stall that fires later than `idleFrames` only lifts the stop frame | `stopAt_ge`, `stopAt_ge_lift` |
| no stop before end + tail; stop exactly at it; the first stop frame is the stop frame | `stops_before`, `stops_at`, `stops_first`, `stops_first_limit` |
| the end frame is recovered from the firing frame and its idle count | `endFrameOf_add`, `endFrameOf_limit` |
| the limit/stalled label follows the rule's own OR-branches | `limitEnd_of_ended`, `endReason_limit`, `endReason_stalled` |
| no reader window reaches past the tail (hi at most the stop frame + 1) | `windows_within_tail` |
| end 0-19, 20-59, 60-119 are 20, 40, 60 frames and end 120+ holds at least 40 | `end_windows_full` |
| swipe-touch-v1: tail 165, window tail 160, stalled stop frame unchanged, tail inside the frame budget | `swipeTouchV1_tail`, `swipeTouchV1_stalled_unchanged`, `swipeTouchV1_tail_in_budget` |

The reader's end frame (first maximum of the recorded scrollY) is one frame before the run's end frame (the recorded scrollY of a
frame is read at the next frame), so `e <= eRun` is the hypothesis the window theorems use; the real runs have `eRun = e + 1`.

## CI check (MEASURED)

Run 40355794611 (`chromium-counts`, push of `ci/profile-end-tail`, profile swipe-touch-v1, target rewrite = base, 2 runs: the workflow
refuses fewer than 2). Table and per-run json: `results/profile-end-tail/windows.json`; script `results/profile-end-tail/windows.mjs`.

| run | endReason | run end frame | reader end | last swipe frame | frames after the end | total | frames per window (approach / 0-19 / 20-59 / 60-119 / 120+ / finish) |
|---|---|---|---|---|---|---|---|
| r1 | stalled | 575 | 574 | 740 | 166 | 771 | 34 / 20 / 40 / 60 / 47 / 201 |
| r2 | stalled | 575 | 574 | 740 | 166 | 771 | 34 / 20 / 40 / 60 / 47 / 201 |

Every end window has frames (47 in end 120+). The stop frame is 740 = 575 + tail 165 in both runs, as `swipeTouchV1_stalled_unchanged`
says.

The morph.stage flag is not on main, so the limit-end arm was not run here. For a limit end the stop frame is `stopAt_limit`:
end + 165, so end 120+ gets 47 frames as in the base run (INFERRED from the theorem, not seen). The flag arm is the morph-stage task's rerun.

## What this does to existing comparisons

* A stalled swipe-touch-v1 run stops where it stopped before: stall fires at end + 164, the touch lifts at end + 165. Run length 771
  frames in run 40339630528 and in run 40355794611 (MEASURED), so every existing base profile and every same-commit or cross-commit
  base comparison keeps its meaning.
* A limit-end run records 165 frames after its end instead of 3. Its older results (3 frames after the end) are not comparable in the
  end windows; approach and finish windows change in length (finish gets the extra frames). Same-commit comparisons stay valid
  because both arms use the same rule and the windows read the common frames (`ownVerdicts`).
* A profile whose stall wait plus hold exceeds 160 (a larger stroke) keeps its stall tail; a wheel profile (stroke 3) gets the
  window tail 160 where it had none.
* Replay profiles (`input.mode` replay, `until: script`) have no end rule and are unchanged.

## TS stand-ins

The planner (`touchPlanner`) and the frame loop in run.mjs stay TS glue: they supply `done` (the planner returned no step) to
`swipeStops`. `Swipe.stopAt` assumes the touch lifts at most `holdFrames + 1` frames after the firing frame, read from the planner
(`touchPlanner`, run.mjs), not proved.

## Follow-ups (outside the unit)

* Morph-stage rerun with the flag arm on this tail (shows the 3 to 165 change on a limit end).
* A minimum frame count per window (`window-min-frames`).

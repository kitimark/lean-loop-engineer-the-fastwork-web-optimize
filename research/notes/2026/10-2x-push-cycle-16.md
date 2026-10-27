---
id: 2026-10-2x-push-cycle-16
kind: note
title: "Push cycles, 16-cycle full pass: the window now fits (Lean sep_fits) for every stretch up to 2988 permille, yet both arms stay undecided on the Simulator (rewrite: stretch 3289 beyond the bound, user: inseparable); touch passes are lost to restart and touch failures; H4 stays open"
status: review
created: 2026-10-27
topics: [end-of-page, touch, simulator, webkit, push-cycle, census, ci]
---

# Push cycles: full pass of 16 cycles, cycle versus clock

Task push-cycle-16, follow-up of `10-2x-push-cycle-separate.md` (run 3 there: the dwell pass took 2.39 times the full period, so the clock-matched cycle 5 fell at index 12, outside the 12-cycle pass).

## Answer

- CONFIRMED (Lean, `lean/Fw/Measure/PushCycle.lean`): the full-pass cycle count is derived, not typed. `fullCyclesFor r = clockIndex r 5 + 1`; measured stretch 2391 permille plus a 25 percent margin gives the bound `sepStretchBound = 2988` and `sepFullCycles = 16` (`sepFullCycles_eq`). Theorem `sep_fits`: every stretch r up to the bound has `clockIndex r 5 < 16`. `sep_margin`: every stretch up to the measured one leaves 3 cycles spare. `sep_noRoom_only`: `undecided:noRoom` implies a stretch beyond the bound. The lane (`--separate`) reads the count from Lean through the golden; the workflow carries no `--cycles`.
- MEASURED (Simulator, GitHub macOS, real touches, two pushes, 6 jobs each, pooled with `results/push-cycle-16/pool.mjs`): rewrite undecided, user undecided. Neither arm earns cycle-driven or clock-driven.

| Arm | Run | Full | Dwell | Stretch (permille) | Verdict |
|---|---|---|---|---|---|
| rewrite | push 1 (40361916735) | 2 | 4 | 3934 (beyond bound) | undecided:fewFull |
| rewrite | push 2 (40412970956) | 5 | 2 | 2835 | undecided:fewDwell |
| rewrite | pooled | 7 | 6 | 3289 (beyond bound) | undecided:noRoom |
| user | push 1 | 5 | 5 | 2126 | undecided:inseparable |
| user | push 2 | 2 | 3 | 2240 | undecided:fewFull |
| user | pooled | 7 | 8 | 2135 | undecided:inseparable |

- MEASURED, user pooled (n = 7 full, 8 dwell): mean slow frames per cycle over cycles 3 to 5 (x1000, Lean `rate`) 167142 by cycle index, 145523 by clock-matched index, 85666 in dwell passes. The two predictions are too close for Lean `separable` (the larger is not more than twice the gap), so the pass cannot tell the readings apart. Not a cycle result and not a clock result.
- MEASURED, rewrite pooled (n = 7 full, 6 dwell): stretch 3289 is above the bound, so the clock-matched cycle 5 falls at index 16 or later, outside the pass; the verdict is `noRoom`, as `sep_noRoom_only` requires. Push 2 alone was inside the bound (2835) but had 2 dwell passes.
- The pass count stays the limit: all 12 jobs delivered a result file, but push 1 ended with sim 2 and 5 failed and push 2 with sim 1, 3 and 4 failed (a failed job still counts its usable passes).

## Lost passes

From `results/push-cycle-16/pooled.md` (`lostOf`, per job, arm and profile):

- rewrite full: p1 job 2 not run (the job ended first); p1 job 4 touch driver timed out (restartFailed); p1 job 5 touch driver timed out (touchesFailed); p1 job 6 failed pass (restartFailed); p2 job 6 touch driver timed out (touchesFailed).
- rewrite dwell: p1 job 2 not run; p1 job 6 touch driver failed (restartFailed); p2 jobs 1 and 2 failed pass (restartFailed); p2 job 3 touch driver failed (restartFailed); p2 job 4 not run.
- user full: p1 job 3 touch driver timed out (restartFailed); p2 job 1 failed pass (restartFailed); p2 job 3 touch driver timed out (touchesFailed); p2 job 4 touch driver timed out (restartFailed); p2 job 5 touch driver timed out (restartFailed).
- user dwell: p1 job 5 not run; p2 jobs 1 and 3 not run; p2 job 4 failed pass (notReady).
- restartFailed (the Simulator restart before a pass failed) hit 4 of 6 jobs in push 1 and most of push 2. MEASURED (counts from the `failed` lists in the artifacts). Cause: INFERRED, three Simulator jobs at a time on a shared macOS runner pool and 80 to 100 minute jobs; not investigated here.

## Why the stretch overshoots (INFERRED)

- MEASURED: dwell target periods were 40000 to 70654 ms but several measured dwell periods were 100195, 119557 and 98165 ms (`periods-push1.txt`, `periods-push2.txt`), while full periods were 18000 to 36600 ms.
- INFERRED: the period is a mean over the presses (`periodMs`), so a single stalled press of 33 to 90 s moves the mean by tens of seconds and the stretch with it. Where the full pass was lost, the dwell target fell back to 40000 ms (several jobs in both pushes: a dwell target of 40000 beside a missing full pass in `periods-push*.txt`), so the planned stretch there was wrong from the start. The rewrite arm hits the bound more often than user.
- Follow-up: take the period from the median press gap, not the mean, and plan the rest from it.

## H4 (IOSurface re-allocation) stays open

MEASURED (census after each cycle of the dwell passes, Lean `across`): rewrite layers no, backing bytes no (flat in 6 of 6 passes), layers created no; user layers no, backing bytes no, layers created no (one dwell pass of 8 falls in created). Mean backing bytes after the full pass 122.2 MB (rewrite) and 104.8 MB (user); after the dwell pass 118.7 MB and 105.4 MB. This lane cannot count freed bytes, so it cannot decide H4.

## Method

Per arm (rewrite, user) per VM: one `full` pass of `sepFullCycles` = 16 cycles in one touch run, and one `dwell` pass of 6 one-cycle touch runs with a census and a rest between them (`restMs`, cap 120 s) that fills the dwell period to the target stretch times the full period. Counted window per cycle = open stretch + 8 s. Metric: mean slow frames above 50 ms per cycle over cycles 3 to 5. Verdict: Lean `sepVerdict`.

## Limits and stand-ins

- CI only: Simulator on GitHub macOS, not the iPhone. Two pushes used (the limit). A side under 3 passes is undecided.
- TS stand-ins with no Lean golden (decision parts stay in TS): `periodMs`, `activeQuiet`/`activeCycles`, `sepArm` (arm grouping and exclusions), `censusSeries`, and the report glue `lostOf`/`parseFailed`/`sepTable`. The verdict, the cycle count, the bound and the census reading (`across`) are Lean and replayed from `packages/contracts/golden/measure/push-cycle.jsonl`.
- The cycle-versus-clock question stays open on the Simulator; the lane needs more usable passes per side than the runners deliver (7 and 6 or 8 usable passes from 12 jobs).

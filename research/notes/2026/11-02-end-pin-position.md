---
id: 2026-11-02-end-pin-position
kind: note
title: "End pin vs base by where the page rests: pin rests at the end in 44 of 47 reached windows, base in 25 of 44; the across-jobs verdict is same (5 of 8 decisive jobs, 6 needed)"
status: review
created: 2026-11-02
topics: [webkit, ios, scroll, morph, pin, touch, lean, measure]
---

# End pin position: pin vs base by rest position

Task `end-pin-position`, the follow-up of `end-pin-rank` (`research/notes/2026/11-02-end-pin-rank.md`). The CI Simulator is not the phone. The pin stays look class L with the user's review pending; no preset change. A position verdict says where the page rests, not how it feels.

## Answer

- **Across jobs, pin vs base by rest position: `same`, not `second` (MEASURED, run 41380162402, state `failed` as `fw ci state` gives it; one dispatch of two used).** Decisive jobs 8 of 12, agreement needed 6; the pin is better in 5 jobs (2, 8, 9, 10, 11), same in 3 (3, 6, 12), worse in 0; 4 jobs are insufficient (1 and 4: fewer than 3 reached pin or base windows; 5 and 7: no windows). One more decisive pin-better job would have read `second`.
- **The pin never rests past the end; base and orig do (MEASURED).** Over the 10 jobs with windows (reached windows only, tolerance 10 px): pin 44 of 47 rest at the end, 0 over, 3 short; base 25 of 44 (16 over, 3 short); lock 40 of 45; orig 23 of 44 (19 over). Median gap to the end: pin 0 px, base 6 px, 90th percentile base 77 px. The pooled counts are descriptive; the verdict rule is per job.
- **The previous run, read with the same rule offline, gives `second` (MEASURED, run 41369102226, `results/end-pin-position/offline-across.md`, state `failed`).** 6 decisive jobs, 4 needed, 5 pin-better, 1 same, 0 worse; pin 30 of 33 reached windows at the end, base 19 of 36. The two runs agree in direction (10 pin-better, 4 same, 0 worse over 14 decisive jobs). That pooling of two dispatches into one rule application is a post-hoc view (INFERRED: it would read `second`, 10 of 14, 10 needed), not the pinned verdict.
- **No job has a live pin write (MEASURED).** `liveWrites` is 0 in all 12 jobs, so the guard (a job with a live write never reads pin-better) changed no verdict in either run.
- **The walk variant was not built.** The offline check on run 41369102226 and this run show the current walk separates the arms by position without a pan that ends on the target side (jobs were decisive in 6 of 7 and 8 of 12).

## Why the metric ranks where fights could not

The pin stored a lock in 4 of 43 runs here (4 of 29 before), so `lockedCmp` ranks nothing. The rest position needs no write: it reads `finalY10` against `maxY10` and the pin's target for every window.

- **Lock matches pin, so the gain is the removal of base's restore calls, not the pin's writes (MEASURED).** lock 40 of 45 vs pin 44 of 47; pin vs lock reads `same` in 7 jobs, pin-better in job 9 and undecided in 4. The pin wrote in 4 of 43 runs.
- **Windows where the first scroll came about 1 s late do not reach the end (`notReached`) in every arm** (1 to 4 per arm here) and are left out of the tally, so a slow first scroll cannot count against an arm.
- **Settle time after the last touch is 0 for nearly all windows (MEASURED):** the page had already arrived at the end when the finger lifted (pin 44 of 44, base 21 of 22, orig 23 of 23 resting windows); lock arrives later (median 0, 90th percentile 246 ms, 22 of 40 at 0). Settle does not enter the verdict.

## Faults of this run

- **Dominant fault by count: the touch driver's push server not ready after 480 s (MEASURED, `touch.why` in `job{3,4,5,7,11}`).** Named `touch-driver-not-ready` in jobs 5 and 7 (0 windows) and `lost-mid-walk: restart failed: push server: no ready file after 480 s` in jobs 3, 4, 11 (18, 14, 18 windows kept). Job 9 hit the same restart failure after its 24 windows. Jobs 1 and 8 ended on the walk deadline (16 and 13 windows, no fault name).
- **The 480 s wait (`readyMs: READY_ALLOW_MS` on both `startServer` paths) did not remove the fault.** Before, 4 of 12 jobs ended at the 240 s default (jobs 3, 7, 8, 12); now 2 jobs have no windows (5, 7), 3 are cut after a restart, with the same message at 480 s. The wait lengthened the failing jobs; that the server needs more than 480 s or never comes up is not told by this run (INFERRED: a 240 s wait would have ended the same jobs earlier).
- Jobs started with results: 10 of 12 (all but 5 and 7). Smoothness run state `failed` because jobs 5 and 7 did not succeed.

## Lean, in this task

- `Fw.Measure.TouchLock`: the window classes `restOf` (`notReached`, `atEnd`, `over`, `short`; tolerance 10 px, `restOf_atEnd`, `restOf_over`, `restOf_short`, `restOf_notReached_iff`), `settle10` and `touchEnd10` (the page-clock end of the last touch from the first event, `firstScrollMs` and `swipeAt`), the tally `tallyRest` and per-job `restCmp` (pin-better needs `3 * (pin rested * base reached - base rested * pin reached) >= pin reached * base reached`; below 3 reached windows in an arm the job is `undecided`: `restCmp_undecided_base`, `_pin`, `restCmp_better`, `_worse`, `_same`, `restCmp_self`).
- The guard: `jobVerdict` maps a job with `live > 0` and `pinBetter` to `insufficient` (`jobVerdict_live_better`, `jobVerdict_live_ne_second`), and each other branch has its own theorem (`_live_worse`, `_live_same`, `_live_undecided`, `jobVerdict_clear`). `acrossRest` is Smooth `acrossDecisive` over the job verdicts (`acrossRest_second_unguarded`, `acrossRest_all_live`, `acrossRest_insufficient`, `acrossRest_undecided`).
- Golden cases: run 41369102226 (`rank_41369102226_clear` `second`, `_decisive` 6, `_all_live`, `_two_live`, `_four_live`) and run 41380162402 (`rank_41380162402_clear` `same`, `_decisive` 8, `restCmp_run_41380162402`), plus window, settle, target and margin-edge cases. `touch-lock.jsonl` is generated (193 lines).
- TS twin: `packages/measure-webkit/src/touchlock-rest.mjs` (all decisions), wired into `touchlock.mjs` (windows table columns, summary line, `acrossReport`/`acrossMarkdown`); `test/touchlock-rest.test.mjs` replays the goldens. TS stand-ins not checked against a golden: `winOf`, `touchEndOf`, `restRow` (the glue from a result row to the Lean inputs) and the markdown text.

## Limits and follow-ups

- The tolerance 10 px and margin 3 are chosen, not measured; the sensitivity to other tolerances was not run (not measured).
- 5 of 8 decisive jobs is not enough under `agreeNeeded`; a third dispatch of the same lane would not be run here (2 allowed, 1 used; the driver fault, not the sample, costs the decisive jobs: 4 of 12 jobs undecided).
- The driver fault at 480 s needs its own task; the cause (cold Xcode test host on the shared runner, a stuck first launch) is not established.
- Results: `results/end-pin-position/run-41380162402/across.md` (rest table last), `pooled.md`, per-job `touch-lock.json`.

---
id: 2026-11-02-end-pin-rank
kind: note
title: "End pin vs base across 12 Simulator jobs: the rule is in Lean, the verdict is insufficient, the pin writes too rarely to rank"
status: review
created: 2026-11-02
topics: [webkit, ios, scroll, morph, pin, touch, lean, measure]
---

# End pin rank: pin vs base across jobs

Task `end-pin-rank`, the follow-up of `end-pin-trace` (`research/notes/2026/11-01-end-pin-trace.md`) and `sim-touch-fault-margin` (`research/notes/2026/10-2x-sim-touch-reliable.md`). The CI Simulator is not the phone. The pin stays look class L with the user's review pending; no preset change.

## Answer

- **Verdict: insufficient (MEASURED, run 41369102226, one dispatch, 12 jobs).** Decisive jobs 0 of 12; `minSamples` is 3. 7 jobs have windows; none of them can rank the pin, because `lockedCmp` ranks only runs with a stored lock and the pin stored one in 4 of its 29 accepted runs (jobs 2 and 10, 2 each; the rule needs 3 per job). The pin, not a fault, is what leaves the lane without a verdict.
- **Dominant fault by count: `touch-driver-not-ready`, 4 of 12 jobs (3, 7, 8, 12; MEASURED).** `push server: no ready file after 240 s` with 0 windows. The touch-lock lane calls `startServer` with the default `readyMs` 240 s (`touch-push.mjs` TOUCH_BUDGET) where the Simulator lane passes `READY_ALLOW_MS` 480 s (Lean `readyAllowMs`); see Follow-ups. One more job ended `lost-mid-walk` (job 11: 11 of 24 windows, the restart after a stall found no ready file in 240 s), one job (4) left no result file: its walk step ran 61.5 min, past the 40 min walk deadline, and the job was cancelled at the 60 min timeout (cause unread, no artifact). 6 jobs ran clean (1, 2, 5, 6, 9, 10: 24 windows each, 23 with frames in job 2). Faults by name: touch-driver-not-ready 4, lost-mid-walk 1, no result file 1, none 6. Even with no fault the 6 clean jobs give 0 decisive jobs, so the fault margin (12 jobs from `lateJobs`) did not decide the verdict.

## What the lane measured

Accepted runs and fights over the 7 jobs with windows (`results/end-pin-rank/run-41369102226/across.md`; fights are the frame fights of Lean `fights`):

| arm | accepted runs | fights, total | fights per run | runs with a stored lock | open scrollTo calls, total |
|---|---|---|---|---|---|
| orig | 33 | 63 | 1.9 | 33 | 716 |
| base | 30 | 62 | 2.1 | 30 | 779 |
| lock | 29 | 40 | 1.4 | 29 | 552 |
| pin | 29 | 0 | 0 | 4 | 4 |

- **The pin wrote 4 times in 29 runs (0.14 per run); base made 779 calls in 30 runs (26 per run) (MEASURED).** All 4 writes were in clear states: `writesLive` 0 (the Lean live-write replay `liveWrites` over the trace timestamps: 0 over the 39 pin windows). The 4 writing windows had fights 0 (jobs 2 and 10).
- **The pin ran in 38 of 39 pin windows** (233 `inactive` entries, 148 touches, 126 `moved`, 42 `due`). Declines: touching 99, live 18, onTarget 20, reversal 111; writes 4. The reversal decline dominates: the pan ends with the page off the target and a write would turn it around (the Lean `decline_rests_off_target`).
- **Pin fights are 0 in 29 of 29 runs, 25 of them by definition (no lock, no call).** Pin vs base per job: `n/a` in 4 jobs (no pin lock), `undecided` in 3 (below 3 locked runs, or no pin runs in job 11). Across jobs `acrossPin` reads insufficient with 0 decisive jobs.

## Lean, in this task

- `Fw.Measure.FaultNames`: the fault names (`touch-driver-not-ready` before the walk, `lost-mid-walk` once the walk ran) and `faultOf` (the report's fault, a named fault first, then the budget, kept windows, socket words, lost words, an incomplete walk). `driverEnd` names the fault by phase (golden rows replayed in TS: `driverEnd` 8 rows, `faultOf` 13, `faultName` 7).
- `Fw.Measure.WalkBudget`: `legsOf`, `lateJobs` 12 (from `lateRate` 5 of 15), the 12-job lane has 3 waves with 2 in the last; run 3 data relabelled (driver 5, lost 4 of 20 jobs).
- `Fw.Measure.TouchLock`: `pinVerdict` (pin lower = second, higher = first, overlap = same, `n/a` and `undecided` = insufficient) and `acrossPin` = Smooth `acrossDecisive` over them; `acrossPin_none_decisive` (jobs with `n/a` or `undecided` never decide), `acrossPin_second`, `_first`, `_split`, `_same`; `liveWrites` over the trace (`quiet10` 1200 and `slack10` 10 are the EndPin quiet time in tenths of a millisecond, `quiet_link`).
- TS twins: `touchlock.mjs` (`pinVerdict`, `acrossPin`, `liveWrites`, `acrossReport`, `acrossMarkdown`; `touchlock-cli.mjs across label=file ...`), `walk-budget.mjs` (`driverEnd`, `legs`), tests replay the goldens.

## Limits and follow-ups

- The Simulator is not the phone; the walk ends a pan wherever the swipe leaves it, so the pin declines `reversal` and stores no lock. Ranking the pin by fights needs a walk that ends the pan on the target side, or a metric that counts the pin's page position directly (the lane has `finalY10`); not done here.
- One dispatch of two used. A second run of the same lane would repeat the same verdict: the pin writes 0.14 per run and the rule needs 3 locked pin runs in each of 3 jobs.
- `touchlock-run.mjs` should pass `readyMs: READY_ALLOW_MS` to `startServer` (4 of 12 jobs lost only the 240 s default). Not changed here (outside the pinned unit).

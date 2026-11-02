---
id: 2026-11-03-touch-restart-device
kind: note
title: "Touch driver restart with a device-level reset: 2 of 5 restarts ready, no reset ever terminated anything; restart readiness closed as a Simulator-limit finding"
status: review
created: 2026-11-03
topics: [webkit, simulator, xcuitest, touch, ci, measure]
---

# Touch restart device

Task `touch-restart-device`, the final design round after `touch-restart-ready` (`11-02-touch-restart-ready.md`). Branch `ci/touch-restart-device`,
workflow `smoothness` (`[webkit-cadence] [sim-only] [touch-lock]`, flag `fw=morph.tween:end-pin`), 12 touch-lock simulator jobs, commit
`4afd78df2`, run `41503168296`; `fw ci state` says `failed` (jobs 3, 10 and 12 ended with the walk's hard stop; job 3 uploaded only its retry).
One dispatch used of two; the second was not needed to decide. The Simulator is not the phone. Counts are per begun restart, not rates.

## Answer

- **Restart readiness is closed as a Simulator-limit finding (MEASURED, INFERRED mechanism).** This run: 5 restarts begun, 5 decided, 2 ready (jobs 1 and 6,
  ready after 430 s and 389 s of a 470 s launch). Earlier: 4 of 10 (gated), 1 of 5 (ungated), 5 of 9 (main). Pooled 12 of 29 restarts ready. 2 of 5 is
  inside the range of the earlier forms; it is not clearly above them. No further restart form is added.
- **The reset never terminated anything (MEASURED).** Ten `simctl terminate` calls (runner and host app, 5 resets): 0 `ended`, 4 `absent` (nothing to
  terminate: jobs 6 and 7, after 9.4 s and 3.3 s) and 6 `late` (no answer in the 15 s cut: jobs 1, 2 and 8, resets of 15.4, 18.5 and 15.5 s). When the old
  `xcodebuild` has exited, its runner and host are already gone, or `simctl` itself is hung on a starved host.
- **The reset outcome does not separate ready from stuck (MEASURED).** Ready: job 1 (late), job 6 (absent). Stuck `driver-launch-stuck` at 470 s: job 2
  (late), job 7 (absent), job 8 (late). Gate names: `launch` (jobs 7, 8), `launch:driver-restart-device-unsure` (jobs 1, 2, 6). Reset faults by name:
  `driver-restart-reset-late` 3 times (jobs 1, 2, 8), `driver-restart-reset-failed` 0.
- **One stall never reached its launch (MEASURED).** Job 5: inspector dead, the guard reboot failed (`simctl shutdown failed: ETIMEDOUT`), the gate
  named `driver-restart-device-unsure` after 204 s, the walk ended `incomplete` with the reset `running`. So 6 stalls led to 5 launches. INFERRED: the guard
  ended the session while the reset ran; the reset has no end record there.
- **The in-flight launch record was not exercised by CI (MEASURED).** No restart launch was running at a snapshot (0 entries `inFlight`); jobs 7 and 8 lost
  their launch at 470 s before the deadline. The record is covered by `touch-restart-device.test.mjs` only.
- **Hosts were starved again (MEASURED).** First 150 s launch ready in 10 of 12 jobs (jobs 9 and 10 stuck first, ready later); earlier 12 of 23. Inspector
  probes failed in jobs 5, 10 and 12; job 12 had a `Runtime.evaluate` timeout of 120 s. INFERRED mechanism: stuck launches
  and late `simctl` calls come from the same slow runner service, not from an app left over from the old driver.

## Why this form, and the bound

- **Chosen: terminate the XCUITest runner and host app, not shutdown/boot (INFERRED from the runs and `xcrun simctl help`).** `xcrun simctl help terminate`, run on this Mac, prints
  "Terminate an application by identifier on a device. Usage: simctl terminate <device> <app bundle identifier>"; the same help lists `boot` ("Boot a
  device or device pair") and `shutdown` ("Shutdown a device"). Earlier artifacts
  (`11-02-touch-restart-confirm.md`, `-ready.md`): the guard reboot (`guard.mjs recover`) is a once-per-pass budget and `simctl shutdown` timed out in
  job 5 here, so a shutdown/boot restart would spend the one reboot and still hang on a starved host. Terminating two named apps is bounded
  by one 15 s call each and kills no process by pattern (`resetCallMs` in `TouchReady.lean`).
- **Bound (CONFIRMED by Lean).** Gate 200 s + reset 15 s + launch 470 s + kill 10 s = 695 s = `restartMs` <= `restartAllowMs` 700 s; the pair
  `WalkBudget.setupWorstMs` 900 s + 2 x 695 s + 100 s fits `deadlineAt job` 2400 s (`restart_pair_fits`, `restart_pair_exact`).
  Each branch has its theorem: `resetAct` (run on a `launch` without overlap, skip otherwise), `callEnd` (ended, absent, late, failed), `nameWith`.
- With the old `xcodebuild` alive the reset is skipped (`driver-restart-overlap`), so a failure is never turned into a pass.

## What the across-job verdict must tolerate (MEASURED, arithmetic from WalkBudget)

- Windows with status `ok` against the 24 planned (6 reps x 4 arms): 143 of 288 lost, mean 11.9 per job, range 0 to 23 (jobs 4 and 11 lost none,
  job 5 lost 23). Jobs with every arm at `minKept` (5) or more: 3 of 12 (jobs 4, 8, 11).
- `lateJobs` = 12 and `Fw.Gate.Smooth.minSamples` = 3, so the lock lane can have at most `lateJobs - minSamples` = 9 insufficient jobs; this run had 9, no spare job.
  The plan lane analogue is `margin` = `jobsNeeded - minSamples` = 7 (`jobsNeeded` = 10). The count uses all four arms, stricter than a two-arm pair.
- A restart costs up to `restartMs` 695 s of the `deadlineAt job` 2400 s.
  The verdict must treat a job with fewer than `minKept` windows in an arm as insufficient and not as evidence, and must not need more than `lateJobs - minSamples` of them.

## TS stand-ins (not golden-checked)

`terminateApp` (execFile and the stderr match for "nothing to terminate"), the 15 s race in `restartReset`, `launchesView`, and the in-flight entry in
`beginServer`. Lean decisions replay from `packages/contracts/golden/measure/touch-ready.jsonl` (73 lines).

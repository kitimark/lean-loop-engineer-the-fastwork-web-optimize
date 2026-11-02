---
id: 2026-11-02-touch-restart-ready
kind: note
title: "Touch driver restart gate: 4 of 10 gated restarts ready on two 12-job CI runs, the same range as 1 of 5 and 5 of 9 without it; restart readiness tracks the Simulator, not the restart form"
status: review
created: 2026-11-02
topics: [webkit, simulator, xcuitest, touch, ci, measure]
---

# Touch restart ready: a gate before the restart launch, two CI runs

Task `touch-restart-ready`, after `touch-restart-confirm` (`11-02-touch-restart-confirm.md`). Branch `ci/touch-restart-ready`, workflow `smoothness`
(`[webkit-cadence] [sim-only] [touch-lock]`, flag `fw=morph.tween:end-pin`), 12 touch-lock simulator jobs per run. The Simulator is not the phone.
Run 1 = `41460411752` (commit `0c6b07ac0`), run 2 = `41475879793` (commit `41b2aee41`); `fw ci state` says `failed` for both (jobs that ended
with an incomplete walk or a named driver fault; the touch-lock data of every job that uploaded is complete, job 3 of run 1 uploaded nothing). Two
dispatches used of two. Counts are per begun restart, not rates.

## Answer

- **The restart gate did not raise readiness (MEASURED).** Run 1 (gate on the old driver exit and the inspector): 3 restarts begun, 3 decided, 0 ready.
  Run 2 (gate also on `simctl`): 7 begun, 7 decided, 4 ready. Together 4 of 10. Without a gate: 1 of 5 (touch-restart-confirm) and 5 of 9 (main).
  The three samples are within the range a coin flip with 3 to 9 draws gives; nothing here separates the forms.
- **The two causes named before the run did not explain the failures (MEASURED).** Run 1: all 3 gates were `launch` (old driver exited after 36, 110
  and 60 s, inspector answered) and all 3 launches still stayed `driver-launch-stuck` (470, 500, 470 s). No Simulator reboot ran in jobs 4 and 11.
- **Restart readiness is of the same order as first-start readiness (MEASURED, INFERRED reading).** The first 150 s launch was ready in 5 of 11 jobs
  (run 1) and 7 of 12 (run 2): 12 of 23. The 24 restarts over four runs: 10 ready (4 here, 1 + 5). A restart is one 470 s launch, so a launch that
  does not reach `alive` in 150 s stays stuck in about half of the cases for 470 s as well. INFERRED: readiness is a property of the runner and the
  Simulator service at that moment, not of the restart form. Jobs 3 (run 2), 9 and 12 (run 1) never got a first start in 3 launches.
- **A gate that waits on `simctl` can wait for a state that does not predict readiness (MEASURED).** Run 2, gate `sim=false` (simctl silent): jobs 7 and 10
  launched named `driver-restart-device-unsure` and became ready (261 s and 229 s to `alive`); gate `sim=true`: jobs 8 and 7 (second) ready, jobs 5 and 11
  stuck. 2 of 3 versus 2 of 4.
- **The gate was longer than Lean's bound once (MEASURED, fixed after the run).** `Gate.waitMs` is 200 s. Job 6 of run 2 took 347 s and job 7 took 228 s,
  because the guard `check()` waits for a recovery in flight (about 100 s per check in job 6). `restartGate` now races each check against the
  Lean probe time (25 s); the fix and its test came after run 2 and is not CI-measured.
- **One launch overshot its cut by 626 s (MEASURED).** Run 2, job 11: `launch 1 of 1: driver-launch-stuck after 1096 s` where the cut is 470 s.
  INFERRED: the host stalled (memory free 14 percent, load about 500 to 1000); the loop reads the clock only when its timer fires. `walk deadline` still ended
  the job. A restart can therefore take longer than `restartAllowMs` in wall time on a starved runner; Lean's bound assumes timers fire.
- **Overlap was rare and one of its cases is the stop wait itself (MEASURED).** Job 6 of run 2: the old driver's body never ended (`driver-stop-late-body`,
  exit after 475 s); the gate waited 120 s, the device checks failed, and the launch was named `driver-restart-overlap,driver-restart-device-unsure`;
  it stayed stuck 470 s. Every other old driver of the 9 other restarts exited 32 to 110 s after the stop (late teardown).

## Restart forms and why

| form | what it does | reason from the evidence |
|---|---|---|
| (a) wait for the old xcodebuild to exit | `wait-exit`, up to 120 s | old teardown took 70 to 311 s in six earlier runs; the new launch started while it ran in at least 3 of 9 restarts |
| (b) check the inspector (and in run 2 `simctl`) before launching | `recheck`, 2 checks, 30 s apart | the guard reboot ran concurrently with the restart launch in at least 3 of 9 restarts |
| (c') launch anyway after the gate, name what was not clear | `launch:<names>` | a wait with no end does not fit the walk; 12 of 13 `simctl` probes in a stall did not answer, so a device reboot is not a step the gate can rely on |
| rejected: kill at the stop | | the kill caused 0 of 8 ready restarts before this task |
| rejected: device reboot as a restart step | | `simctl` does not answer and reboot steps often fail |

## Lean and the TS

- `lean/Fw/Measure/TouchReady.lean`, section Gate: `gateStep` with one theorem per branch (`gate_wait_exit`, `gate_recheck`, `gate_launch_clean`,
  `gate_launch_overlap`, `gate_launch_unsure`, `gate_launch_both`), `gate_wait_value` (200 s), `restart_total_value` (680 s), `restart_fits_allow` (700 s),
  `restart_added_le` (at most 145 s more than the old restart), `restart_pair_fits` (`readyAllowMs + 2 * restartAllowMs` within `deadlineAt job`).
  The golden `packages/contracts/golden/measure/touch-ready.jsonl` is regenerated from Lean (12 gate cases); `touch-restart-ready.test.mjs` replays it.
- The stop decision reads the log again at the decision, so a body that returned in the last 500 ms poll gap is a late teardown, not a hung press
  (`stopStep` itself is unchanged and golden-checked). Over both runs the 18 stops read: 13 `driver-stop-late-teardown`, 2 `driver-stop-late-body`
  (both run 2), 3 clean (MEASURED).
- Host probes no longer run at the stop: `probeStop` runs after the restart launch has begun (async `ps`, `memory_pressure`, `simctl`).
- **TS stand-ins (not checked against a golden):** the polling and timing of `restartGate` and `stopServer`, `hostProbes`, the `onLaunched` hook, the
  `sim` answer inside the device check, the 25 s race around one check. `loggedAt` (first log byte of a launch) is a new field in the launch records.

## Limits

- 10 gated restarts in two runs; a rate difference below about 40 points cannot be seen.
- Run 2 differs from run 1 (simctl in the gate); the pooled 4 of 10 mixes two forms.
- The 25 s bound on a check, after run 2, was not measured on CI.
- Simulator on a shared macOS runner, not the phone.

---
id: 2026-11-02-touch-restart-confirm
kind: note
title: "Touch driver restart without the stop kill: 1 of 5 decided restarts ready on two 12-job CI runs; a stopped driver outlasts 20 s because a press is in flight, then because teardown is slow"
status: review
created: 2026-11-02
topics: [webkit, simulator, xcuitest, touch, ci, measure]
---

# Touch restart confirm: restarts, late stops, two CI runs

Task `touch-restart-confirm`, after `touch-driver-ready` (`11-02-touch-driver-ready.md`). Branch `ci/touch-restart-confirm`, workflow `smoothness`
(`[webkit-cadence] [sim-only] [touch-lock]`, flag `fw=morph.tween:end-pin`), 12 touch-lock simulator jobs per run. The Simulator is not the phone.
Run 1 = `41422536168` (commit `8a01c8a32`), run 2 = `41436626306` (commit `085404679`); `fw ci state` says `failed` for both (jobs failed or cancelled,
see below; the touch-lock data of the jobs that uploaded is complete). Two pushes used of two. Counts are per job and per decided restart, not rates.

## Answer

- **Restarts without the stop kill: 1 of 5 decided became ready (MEASURED).** Run 1: 4 restarts begun, 3 decided, 0 ready (jobs 3, 8, 9 stayed
  `driver-launch-stuck` for 470, 470 and 528 s without an `alive` file; job 2 was undecided: inspector dead, `simctl shutdown` ETIMEDOUT). Run 2: 5
  begun, 2 decided, 1 ready (job 3 retry: alive 304 s, ready 307 s into the launch; job 11 `driver-launch-stuck` at 470 s); undecided: job 3's second
  restart (walk deadline), job 7 (walk deadline), job 10 (inspector dead). Against 0 of 8 with the kill (`41391781282`, `41402584809`) and 5 of 9
  on main's stop path (`41369102226`, `41380162402`): 1 of 5 is not distinguishable from 5 of 9 (Fisher exact, one-sided p about 0.24) nor from 0 of 8. The
  claim "restarts match main once the kill is gone" is **not confirmed and not refuted** at this n; 4 of 9 begun restarts never reached a decision.
- **A restart that works is slow (MEASURED).** Ready launch times on main: 74, 141, 176, 178, 220 s; here 307 s. The five working restarts all exceed the 50 s of a first start, and four of
  the five exceed 140 s, so the 150 s per-launch cap that `touch-driver-ready` tried first (0 of 6) cut them; the one 470 s launch stays.
  The four failed restarts never wrote `alive`, the same fault class as a first-start `driver-launch-stuck`.
- **Why a stopped driver outlasts 20 s: two causes (CONFIRMED from code, MEASURED from logs).**
  1. *The stop file is read between windows only.* `PushServer.swift:51` tests `stop` once per loop turn; the two presses at `:58` and `:61` are
     synchronous XCUITest calls that wait for the app to be idle before and after the event. A stalled window leaves a press in flight: the Node side gives up
     at `doneBy` (`touch-push.mjs:177-178`), the restart path then writes the stop file at once (`touchlock-run.mjs:94-95`, `touch-push.mjs:134`). The log tails kept at the end of the
     20 s wait end in `Wait for com.apple.springboard to idle` inside the press, then `Tear Down` after 63 s (job 3), 88 s (job 8), 93 s (job 4), 262 s (job 9), 343 s (job 12), 1150 s (job 1) of run 1. Run 2: 3 of 9 late stops
     (jobs 7, 10, 11) had no `Tear Down` after 20 s.
  2. *Teardown is slow after the body returned.* Once `Tear Down` or the end of the test case is in the log, xcodebuild still needs more than the
     remaining time: run 1 re-read from its stored tails, 6 of the 7 stops named late-body by the first rule already show `Tear Down` (jobs 1, 3, 4, 8, 9, 12), so 7 of 8 late stops in run 1 were
     teardown; run 2: 6 of 9 late stops named `driver-stop-late-teardown`, the body having returned 0.8 to 17 s after the stop file (jobs 3 twice, 4, 5, 9, 12). Where xcodebuild did exit
     later, it took 70.2 and 70.2 s (jobs 3, 8), 161.6 s (job 2), 254.7 s (job 9) in run 1 and 75.8, 102.2, 71.6, 310.9 s (jobs 3 twice, 10, 11) in run 2 after the stop file. Clean stops exist: 13.2 and 15.9 s (run 2 jobs 8, 6), 17.2 s (run 1 job 11).
     What xcodebuild does in those 50 to 300 s is not in the log (INFERRED: result bundle and runner teardown on a loaded host).
- **The 20 s stop wait is not the lever for restarts (INFERRED from job 3 retry).** Its restart started 20 s after the stop file while the old xcodebuild was still running (exit at +75.8 s) and
  was ready at 307 s. Jobs 3 and 8 of run 1 had their old session end at +70.2 s and the new launch still failed to reach `alive` in 470 s. So an old session alive during the new
  launch neither prevents nor guarantees a ready restart; no Lean change to the stop wait or the kill is justified by this data.
- **Host health at the stop and at a cut launch (MEASURED, run 2 only).** Memory free at nine late stops: 8 to 29 % in eight, 48 % in one (jobs 3 twice 18 and 11, 4 14, 5 48, 7 29, 9 15, 10 13, 11 8, 12 24); at the four cut launches 48 to 64 %. `xcrun simctl list devices booted` did not answer in 10 s (or exited non-zero) in 12 of 13 probes; one answered in 5.7 s (job 8, first-start launch 1 cut). A healthy local Mac answers it at once. A first-start launch that never reaches the body therefore coincides with CoreSimulator not answering (INFERRED link to the cause).
  The 10 s probe cannot tell a timeout from an error exit.
- **Two stop waits ran far over their 20 s cap (MEASURED).** `waitedMs` 34.7 s (job 10) and 108.2 s (job 11) in run 2. The loop read the whole driver log every 500 ms; on a host with 8 to 13 % free
  memory that read is a plausible cause (INFERRED, the log size was not kept). The loop now reads the last 64 KB (`fileTail`, unit test); that last change was not measured on CI.
- **First starts (MEASURED).** Run 1: 12 of 12 jobs ready (launch 1 in 7, launch 2 in 4, launch 3 in 1; 6 launches `driver-launch-stuck`, 0 `driver-body-stuck`, 0 `driver-ended`). Run 2: 10 of 10 jobs with data ready (launch 1 in 7, launch 2 in 3; 3
  `driver-launch-stuck`). Jobs 1 and 2 of run 2 were cancelled with no artifact; job 3 failed and its retry artifact is used.

## Runs

| Run | Jobs with data | First start ready (first try) | Restarts begun / decided / ready | Late stops body / teardown | Clean stops |
|---|---|---|---|---|---|
| `41422536168` (8a01c8a32) | 12 | 12 (7) | 4 / 3 / 0 | 7 / 1 by the first rule, 1 / 7 by the Tear Down rule (tails) | 1 (job 11) |
| `41436626306` (085404679) | 10 | 10 (7) | 5 / 2 / 1 | 3 / 6 | 2 (jobs 6, 8) |

Job states (`gh run view`, jobs only): run 1 failed jobs 2, 5, 7, 9, 10 (inspector dead, walk not finished, restart failed); run 2 failed 3 and 11, cancelled 1 and 2. Faults by name in the stored
`touch-lock.json`: `driver-launch-stuck` (9 launches, 4 of them restart launches), `driver-stop-late-body` and `driver-stop-late-teardown` (run 2 names; run 1 used the first rule), no `driver-body-stuck`, no `driver-ended`.
Stalls that triggered a restart: 8 pageLost, one `ok` (late), one `beginLate`.

## What changed

- **Lean** `lean/Fw/Measure/TouchReady.lean`: `stopStep c exited bodyEnded waitedMs` returns `clean`, `wait`, `driver-stop-late-body` or `driver-stop-late-teardown`; one theorem per branch
  (`stop_clean`, `stop_wait`, `stop_late_body`, `stop_late_teardown`, `stop_decides_by`, `stop_late_split`, `stop_late_names`). `stopWaitMs` (20 s) and `restartCfg` (one 470 s launch) are unchanged. Golden
  `packages/contracts/golden/measure/touch-ready.jsonl` (41 lines).
- **TS** `touch-ready.mjs` `stopStep` replays the golden; `bodyEndedIn` (the `Tear Down` line or the end of the test case) is log parsing, a TS stand-in without a decision. `touch-push.mjs` `stopServer` keeps main's stop path (stop file, wait, no kill) and records
  `server.stopTrace` {waitedMs, bodyEndedMs, exitedMs (filled in when xcodebuild exits later), top, health, tail}; `touchlock-run.mjs` `endServer` writes it into `touch.launches` as a `stop` entry for every stop.
  `hostHealth` (memory free, simctl answer time) runs at a late stop and at a cut launch.
- No kill, no retry that hides a failure: every cut launch and every late stop is a named entry.

## Follow-ups (outside this unit)

- Restarts need more decided samples; the cheapest source is a longer walk that stalls more often, or counting restarts over the next touch-lock runs (4 of 9 begun restarts end undecided because the walk deadline or a dead inspector comes first).
- Memory free falls to 8 to 29 % by the late stops of a run while it is 48 to 64 % at a first-start cut: probe it during the walk (every window) to see whether the page loss follows the fall.
- A stop that finds the body in a press cannot be shortened from Node; moving the presses off the test's main thread so that `stop` is read while one runs is a Swift change with its own risk (a press in flight during teardown).
- Run 1 job 1 and job 12: the `Wait for com.apple.springboard to idle` of 1150 s and 343 s inside a single press is itself a hang; outside this unit.

## Accepted limits

Free GitHub macOS runners (5 slots); two pushes of two used; faults named, never retried to a pass; the Simulator is not the phone; restarts are rare (a few per run), so the count is per decided restart; jobs 1 and 2 of run 2 and the original job 3 and 9 artifacts are missing.

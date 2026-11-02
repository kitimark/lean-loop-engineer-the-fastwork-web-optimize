---
id: 2026-11-02-touch-driver-ready
kind: note
title: "Why the CI Simulator touch driver sometimes has no ready file: the launch stalls before the test body, a relaunch recovers it, a restart after a stalled window does not"
status: review
created: 2026-11-02
topics: [webkit, simulator, xcuitest, touch, ci, measure]
---

# Touch driver ready: cause, Lean decisions, fix, two CI runs

Task `touch-driver-ready`. Before: run `41369102226` (4 of 12 jobs "no ready file after 240 s") and run `41380162402`
(6 of 12 at 480 s). After: runs `41391781282` (dispatch 1) and `41402584809` (dispatch 2), both `smoothness`, 12 touch-lock
simulator jobs, branch `ci/touch-driver-ready`. The Simulator is not the phone.

## Answer

- **A first-start fault is a driver launch that never reaches the XCUITest body (MEASURED).** In run `41402584809` five
  first launches (jobs 2, 6, 8, 10, 11) wrote no `alive` file in 150 s. Their xcodebuild log ends at `Writing result bundle`
  and the `IDESchemeActionSDKRecord` line, with no `Test Suite started`; `ps` shows the Simulator runtime processes at 40 to 65 %
  CPU and `diagnosticd` at 25 to 50 %. A launch that works writes `alive` after 39 to 126 s and `ready` 1 to 5 s later (11 of
  11 first starts in run `41391781282`, 9 of 9 working launches in run `41402584809`), so Safari is not the slow part.
- **A relaunch recovers most of them (MEASURED).** Launch 1 failed in 5 of 10 jobs; launch 2 or 3 became ready in 4 of those 5
  (65 to 77 s after its start). Per launch about half become ready (9 of 18). Only job 2 failed all three launches and ended
  `touch-driver-not-ready`. Per-job ready driver at the first start: 9 of 10 (was 6 or 8 of 12 before, by the earlier counts).
- **The fault rate is not constant across runs (MEASURED).** Launch 1 failed in 0 of 11 jobs in run `41391781282` and 5 of 10 in
  `41402584809`. Run 1 therefore cannot show that the relaunch works; run 2 does.
- **A restart after a stalled window fails whatever the cap (MEASURED, cause INFERRED).** Run `41391781282`: 6 of 6 restarts
  failed with three 150 s launches. Run `41402584809`: both restarts that reached a decision (jobs 3 and 12) failed with one
  470 s launch (`driver-launch-stuck@470s`, `alive` never written); jobs 10 and 11 hit the walk deadline during the restart.
  So the launch cap is not the cause (cause A refuted by the 470 s launches). Cause B stays open: every driver in both runs was
  force-killed at its stop (`driver-stop-killed`, the xcodebuild group did not exit within 20 s of the `stop` file), and the
  old code, which did not kill, saw restarts ready after 74 to 220 s. The restart state after a killed driver is the one
  difference left. One run cannot split it from "a stalled window leaves the Simulator wedged"; I did not try.
- **The final stop never exits in 20 s (MEASURED, reason unknown).** Every stop recorded in the two runs (8 of 8 in run `41402584809`, all jobs with a stop in `41391781282`) ended
  `driver-stop-killed`. Not explained: slow xcodebuild teardown or a hung test thread.

## Before and after

| Run | Jobs with data | First start ready | Launch 1 stuck | Relaunch recovered | First start not ready | Restarts failed |
|---|---|---|---|---|---|---|
| `41369102226` (240 s, old) | 12 | 8 | not recorded | none | 4 | not recorded |
| `41380162402` (480 s, old) | 12 | 6 | not recorded | none | 6 | not recorded |
| `41391781282` (3 x 150 s) | 11 (job 12 hard stop) | 11 | 0 | 0 of 0 | 0 | 6 of 6 |
| `41402584809` (3 x 150 s, restart 1 x 470 s) | 10 (jobs 7, 9 no artifact and no log) | 9 | 5 | 4 of 5 | 1 (job 2) | 2 of 2 decided |

Run 2 tally (`touchlock-cli launches`): jobs 10, ready 9, first try 5, relaunched 5, `driver-launch-stuck` 9, `driver-body-stuck` 0,
`driver-ended` 0. Job 12 is its retry artifact (`smoothness-webkit-sim-12-retry`); job 5 uploaded; jobs 7 and 9 have no
artifact and the job log is "not found", so they are not counted.

## What changed

- **Lean** `lean/Fw/Measure/TouchReady.lean`: `verdict` (ready, wait, relaunch, give), `replay`, `stopStep`, `tally`, `cfg`
  (3 launches of 150 s, kill 10 s, stop wait 20 s) and `restartCfg` (1 launch of 470 s). One theorem per OR-branch:
  `verdict_cases`, `ready_wins`, `wait_iff`, `relaunch_cap`, `give_cap`; fit in the 480 s allowance: `worst_fits`, `run_fits`,
  `restart_fits`, `restart_run_fits`; `restart_never_relaunches`; `stop_*`, `tally_*`. Golden
  `packages/contracts/golden/measure/touch-ready.jsonl` (38 lines).
- **TS** `packages/measure-webkit/src/touch-ready.mjs` replays the golden; `touch-push.mjs` `startServer` relaunches a cut launch
  with a fresh directory and names `driver-launch-stuck`, `driver-body-stuck` or `driver-ended`; `stopServer` kills after the stop
  wait and sets `driver-stop-killed`. The Swift tests write `alive` when the body starts.
- No retry hides a failure: every cut launch is in `touch.launches` of `touch-lock.json` with its fault, `ps` top and log tail.

## Verdict on the pinned unit

- Cause with log evidence: launch never reaches the test body (MEASURED above); the reason the Simulator host stalls there
  is INFERRED load (Simulator runtime and `diagnosticd` busy).
- Deterministic fix: relaunch at 150 s works for first starts (4 of 5). It does not fix restarts.
- Not a closed finding: the restart failure may be ours (the stop kill) and is not shown to be a runner limit.

## Follow-ups (not in this task)

- Restart: stop the old driver without the kill (wait longer than 20 s, or `simctl terminate` the runner) and measure one run.
  Reads against cause B.
- First start: per-launch success is about 50 %, so 3 launches leave about 12 % failing (1 of 10 seen). A 4th launch needs more
  than the 480 s allowance; `alive` was written by 126 s at the latest, so a launch cap near 135 s would fit 3 launches plus
  one more but leaves no margin on the slow ones.
- Why the stop never exits in 20 s.

## Accepted limits

Free GitHub macOS runners (5 slots); two dispatches used of two; faults named, never retried to a pass; the Simulator is not the
phone; jobs 7 and 9 of run 2 and job 12 of run 1 are missing data.

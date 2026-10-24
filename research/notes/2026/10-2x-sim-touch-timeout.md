---
id: 2026-10-2x-sim-touch-timeout
kind: note
title: "Why the CI Simulator's touch driver and simctl calls timed out, and the readiness probe, stall watch and one restart that replace the single long wait"
status: review
created: 2026-10-25
topics: [webkit, simulator, xcuitest, simctl, measure, touch, ci, timeout]
---

# Touch-driver and simctl timeouts in the CI Simulator lanes

Task `sim-touch-timeout`. Triggers: morph-end-measure run `40105567688` (6 of 6 sim jobs failed or cancelled),
unthrottle-parts-measure `finish` run `40101695202` (lifted arms lost) and `rest` run `40101702393`.

## Answer

The touch passes timed out because the 300 s wait was shorter than a loaded pass, and each timeout then poisoned the Simulator and the
retry. With a readiness probe, a progress-based stall watch and one Simulator restart per pass, no sim job was lost any more:

| Run (mode) | Jobs ended | Passes ok | Named failures | Job time |
|---|---|---|---|---|
| morph-end `40105567688` (finish), before | 0 of 6 | 3 of 36 | 6 jobs failed or cancelled | 60 min job limit |
| `40121254572` (finish), after | 3 of 3 | 15 of 18 (job 2: 6 of 6) | 3 (lift arm, start-up stall) | 75 min each |
| `40128742749` (hero drags), after | 3 of 3 | 18 of 18 | 0 | 18, 22, 28 min |

- MEASURED: one finish job (sim 2) and all three hero-drag jobs completed every arm; the Lean-machine restart path ran in CI 6 times (5 finish, 1 drags).
- MEASURED: the heavy tail is the XCUITest start-up (45 to 249 s seen, 6 of 30 finish touch runs never started in 300 s, 0 of 23 in drags), and 5 of those 6 were the lift arm. The cause of the lift-arm stalls is open.
- Restarts took 203 to 709 s each; 3 of 6 recovered the pass.

## Cause

1. **The pass is as long as its timeout (MEASURED).** A whole `xcodebuild test-without-building` pass on the runner took 252 s
   (hero drags, `rewrite-r1` second try), 269 s and 277 s (finish drags); the timeout was 300 s. Passes that hit it ended at
   303 to 362 s (`drag.timedOut`, code `null`). One warm-up cycle took about 145 s (job 4) and 220 s (job 1). A press is 10 to
   18 s, so 130 to 200 s of every pass is `xcodebuild` start-up and tear-down, not touching. A Mac pass is about 86 s (not a result,
   a reference). Source: `*-throttle.log` and `*-throttle.json` of the morph-end run's jobs 1, 4 and 6; the last 2000 characters of
   a killed pass (`flip-r1`, `drag.tail`) show the test body at t = 76 s when `xcodebuild` was stopped at 300 s, so about 220 s were
   spent outside the test body.
2. **The host is saturated after the Simulator boots (MEASURED).** Load average was 5 to 40 after the driver build and 296 to 586
   after the boot (job logs; `host.txt` of job 1: 418, 399, 413 with SimMetalHost, the WebKit GPU process and diagnosticd on top).
   XCUITest waits for the app to go idle before and after each step (CONFIRMED in `10-2x-sim-touch-reliable.md`: `XCTMainRunLoopIdleNotifier`,
   `XCTAnimationsIdleNotifier`), so start-up time scales with load. Whether the load comes from our process or from the VM is not
   separated here; warm-up load spikes outside our process are named, not fixed.
3. **A killed run leaves the Simulator in a bad state (INFERRED from the order of events).** After a timeout the following
   `simctl launch`, `openurl` and `list` calls timed out (`ETIMEDOUT`, "Operation timed out" after about 170 s) in the same job.
   The retry of the pass then failed in one of two ways:
   - exit 70 (clamp second try): `xcodebuild` printed its destination list, which is what it does when the destination is not found within
     `-destination-timeout`; the default is 30 s (CONFIRMED, `man xcodebuild`, Xcode 27.1: "-destination-timeout timeout", default 30 s). A starved host
     not resolving the destination in 30 s is INFERRED.
   - exit 64: the second try used the same `-resultBundlePath` as the first. CONFIRMED, `man xcodebuild`: "If the path already exists,
     xcodebuild will exit with an error"; exit codes follow sysexits(3): 64 `EX_USAGE`, 70 `EX_SOFTWARE`. The tag was equal for both
     tries (`cli.mjs` used `tag = <arm>-r<round>` for both), so every retry after a pass that wrote its bundle was lost this way.
4. **Blocking calls starved the stall guard (CONFIRMED by the error text).** `sim.mjs` runs `simctl` through `spawnSync`, scaled by
   `FW_WK_TIMEOUT_SCALE=8`: `openurl` waited up to 960 s, `list devices` 120 s with no retry. The CLI's own guard (`watchdog.mjs`, 300 s
   without output) cannot run while the event loop is blocked, so the job died with `stalled: no output for 604 s` and exit 130
   (morph-end run, job 4); the unthrottle `finish` run shows `simctl list devices failed: ETIMEDOUT` four times and a `simctl launch`
   timeout in job 3, a 730 s stall and the step limit (58 min) in jobs 1 and 2.
5. **The step limits were too short for the passes (MEASURED/CONFIRMED).** Six passes of 6 to 7 minutes plus a warm-up of 2 to 4 minutes
   is 40 to 46 minutes without a single retry, against a 45 minute step and a 60 minute job. Job 5 hit the 60 minute step limit,
   job 3 lost communication with the runner ("hosted runner lost communication"), jobs 1 and 2 were cancelled.

## Fix

- **Lean (`lean/Fw/Device/SimTouch.lean`, golden `packages/contracts/golden/device/sim-touch.jsonl`, 56 lines, replayed by
  `packages/measure-webkit/test/sim-touch.test.mjs`).** A pass is the machine `probing -> touching -> done` with one Simulator restart.
  Proved: every pass ends in `done` or a named failure within 5 events (`pass_ends`); at most one restart (`restarts_le_one`) and at most
  two touch attempts (`attempt_le_two`); touches start only after a ready probe (`touching_after_ready`); attempt 2 starts only after
  `restartOk` (`retry_after_restart`); an ended pass stays ended (`step_terminal`); an unexpected event ends the pass with `protocol`.
  The stall rule (`stall`, `stall_cap`, `stall_startup`, `stall_press`) and the cap `capS n = 300 + 45 n` s are proved to cover the measured
  passes (`cap_covers_samples`, `cap_twice_covers_passes`) and a job of six passes with one worst pass fits the 90 minute step
  (`job_fits`: 4530 s for drags, 4890 s for finish at four cycles, against 5400 s).
- **Driver (`driver.mjs`, `DragTests.swift`).** The XCUITest writes a mark file per step (`started`, `press-<i>`) into `TEST_RUNNER_FW_DIR`; the Node side polls every 5 s
  and applies the Lean stall rule: no mark 300 s after the start, 120 s without a new mark, or the cap. A stalled run gets SIGTERM and, 20 s later, SIGKILL
  to its process group. `-destination-timeout` is 30 s times the scale (at most 120 s). The two Swift start-up waits (20 s, 10 s) are multiplied by the scale.
  Every call has its own `.xcresult` and log (`<tag>`, `<tag>-t2`): no more exit 64.
- **Readiness probe before touches.** Up to 6 probes 10 s apart: the Simulator is `Booted`, the Safari page answers (`document.readyState`), the driver build exists.
  Not ready after 6 probes: `NotReadyError`, no `xcodebuild` is started.
- **Watchdog and restart (`cli.mjs`).** A failed probe or touch run shuts the Simulator down (which also ends the stuck XCUITest runner), boots it in a new session,
  runs a one-cycle warm-up and retries the pass once; a second failure ends the pass as a named failure (`failed:touchesFailed`, `failed:notReady`,
  `failed:restartFailed`). A record that is unusable for another reason (page lost) still gets one more machine run, outside the machine.
- **Blocking calls (`sim.mjs`).** Each blocking call ends within 200 s whatever the scale asks, so the stall guard sees the retry log lines; `listDevices` has the retry
  policy; `bootstatus` may retry 5 times.
- **Lane.** Touch step 45 -> 90 min, job 60 -> 110 min (the Lean `stepLimitS`).
- **Evidence kept.** `out/<vm>-driver-<tag>.log` (mark timeline, ready probe, killed-by, scrubbed log tail) and `machine[]` in `out/<vm>-throttle.json`.

## Before and after

Per job (MEASURED, artifacts of the runs; "ok" = `xcodebuild` code 0 and the page record kept; a pass is one arm in one round; 6 per job):

| Run | Job | Passes ok | Machine ends | Restarts (recovered) | Longest ok pass |
|---|---|---|---|---|---|
| `40105567688` before (finish) | 1 | 1 of 3 run | flip 2nd try timed out, clamp 2nd try exit 70 | none | not read |
| | 4 | 0 | stalled, no output 604 s, exit 130 | none | none |
| | 6 | 2 of 2 run | job lost afterwards | none | not read |
| | 2, 3, 5 | 0 | runner lost or step timeout or cancelled | none | none |
| `40121254572` after (finish) | 1 | 4 of 6 | lift r1 `touchesFailed`, lift r2 `restartFailed` | 2 (0) | 338 s |
| | 2 | 6 of 6 | all done | 1 (1) | 353 s |
| | 3 | 5 of 6 | lift r2 `touchesFailed` | 2 (1) | 343 s |
| `40128742749` after (drags) | 1 | 6 of 6 | all done | 1 (1, "recorder not started" after clean touches) | 215 s |
| | 2 | 6 of 6 | all done | 0 | 220 s |
| | 3 | 6 of 6 | all done | 0 | 105 s |

- MEASURED: 5 of the 15 finish passes that completed ran 307 to 353 s; the old 300 s limit would have stopped each of them. The Lean cap for 12 presses is 840 s.
- MEASURED: no `simctl` call ended a job. The finish run logged 5 `openurl` timeouts and 1 `list` timeout, all retried (2 to 4 s apart) and passed.
- MEASURED: the finish jobs took 75 min (touch step), more than the old 45 min step limit; the new 90 min step and 110 min job limits were not reached.
- The unthrottle-parts `finish` run `40101695202` (lifted arms lost; `simctl list devices` ETIMEDOUT 4 times in one job, step limit 58 min) and the `rest` run `40101702393` are not re-reduced.
- Counts for every run are the three CI jobs of each run on separate runners; the runs share the runner pool with morph-end-measure and unthrottle-follow, and the hero-drag run waited 4 min in the queue and one job started 22 min after the others (queueing, not measurement).

## What is left

- INFERRED: the lift arm starts slower or never starts under load. 5 of 6 start-up stalls and all 3 failed finish passes are lift; hero drags use the unthrottle arm instead and had no stall. Next: a start-up mark from inside the Swift test (`setUp`) to separate `xcodebuild` from the runner launch, and a persistent push server to pay the start-up once per job.
- INFERRED: a 300 s start-up cap is on the heavy tail (maximum 249 s seen when it started); a larger cap would only help if the stalled starts eventually succeed, which these runs cannot show.
- The 709 s restart (lift r2, job 1) passed the Lean 600 s restart budget, so the pass ended as `restartFailed` as the machine says.

## Limits

- Free GitHub macOS runners only, shared with morph-end-measure and unthrottle-follow (queue time is named in the table, not removed).
- The Simulator stands in for the iPhone; nothing here is phone time. The local debug run (1 cycle, one arm, a Mac) walked the progress marks only; it is not a result.
- The restart path is proved in Lean and replayed in the golden; whether a CI job needed it is in the table.
- Earlier runs are not re-reduced; the "before" column is read from their logs and artifacts as listed.
- A persistent push server (one `xcodebuild` per job) would remove the 130 to 200 s start-up of every pass; not done here.

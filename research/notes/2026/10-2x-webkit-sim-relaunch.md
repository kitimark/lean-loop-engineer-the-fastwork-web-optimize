# webkit-sim-relaunch: why the Simulator lane lost a VM, and the recover path

Date: 2026-10-25. Task `webkit-sim-relaunch`. Branch `worktree-wf_5e997045-0e6-1`, CI branch `ci/webkit-sim-relaunch`.

## Answer

- Three of the last five 3-VM runs lost a VM. Two have a CONFIRMED proximate cause in the logs, one is INFERRED.
  - Run 40153917806, r1: the Simulator device itself was `Shutdown` in the middle of pass 2. Safari relaunch then failed with `simctl launch Safari failed: ... code=405 Unable to lookup in current state: Shutdown`. The guard gave up with exit 4 (CONFIRMED, log lines and `r1-host.txt`: `simctl list devices booted` is empty).
  - Run 40156388674, r2: `simctl list devices failed: ETIMEDOUT` 123 s after the page server started, one call, no retry (CONFIRMED; the code at that run was a single `simctl list` with the 120 s default).
  - Run 40151813906, r1: the job never wrote an end for "Determinism sessions" and was cancelled at the job timeout; no log is retrievable. INFERRED: the runner VM stopped answering. Outside our process, named, not fixed.
- Why the device went down or stopped answering is INFERRED: CoreSimulator on a 3-vCPU virtual runner, which Apple/GitHub name as a known slow spot (see sources). We cannot repair CoreSimulator; we can bound every call and recover once.
- Fix: the guard asks whether the device is still booted when the inspector is dead, relaunches Safari once (device up), reboots the device once (device down, Safari died again, or its relaunch failed), and ends with a named failure after both budgets. Every simctl call of this path has a limit and one more try. The next attempt of the pass (`FW_WK_ATTEMPTS`) runs after the recovery. The `Host state on failure` step is bounded to 45 s, so a stuck Simulator command no longer costs the log upload (run 40162538610 r1).

## Evidence

| Run | Job | Last good line | Failure line | Class |
|---|---|---|---|---|
| 40153917806 | r1 | pass 2 past census y=3000 (02:45:44) | tick 02:53:45: socket gone, proxy down, page missing; terminate ok in 2 s; `launch` code=405 `Unable to lookup in current state: Shutdown`; exit 4 | CONFIRMED |
| 40156388674 | r2 | `serving` 03:13:15 (boot step done, 73 s) | 03:15:18 `simctl list devices failed: ETIMEDOUT`; exit 1 | CONFIRMED |
| 40151813906 | r1 | step "Determinism sessions" started 01:51:01 | no end for the step; 35 min step bound (02:26) did not fire; job cancelled 02:45:15 | INFERRED (runner lost) |
| 40162538610 | r1 | `Determinism sessions` 05:13:58 | step ended 05:49:12 as failure at the 35 min step bound (2114 s); `Host state on failure` then ran 16 min (05:49:15 to 06:05:21) until the job timeout cancelled it; `upload-artifact` skipped, no log | CONFIRMED (step times from the job record); cause of the hang INFERRED (a Simulator command stuck where `alarm` cannot kill it) |
| 40162538610 | r2 | `Determinism sessions` 05:09:44 | the step never ended, not even at the 35 min step bound; job cancelled at 53 min, no log | CONFIRMED (step record); same class as incident inc-sim-step-unbounded (task sim-step-watchdog) |

- Run 40162251194 passed on all three VMs (sessions 984, 1549 and 1900 s) and r3 of 40162538610 passed (1363 s). None of these four session logs has a recover, reboot or relaunch line, so the reboot path did not fire in them (MEASURED, grep of the uploaded logs). Whether it fired in the two lost VMs of 40162538610 is unknown: their logs were never uploaded. The telemetry of 40162538610 r1 answers every probe (largest gap 28 s, CPU 100 %, load 630 to 1000 as in healthy runs): the runner was alive, the Simulator side was stuck.
- The `webinspectord_sim` socket belongs to `launchd_sim`, which exits when the device shuts down. A gone socket plus a failed `launch` with code 405 therefore means the device is down, not Safari (INFERRED from the lsof rule in `sim.mjs`, CONFIRMED for the 405 text, below).
- In run 40153917806 r1 pass 1 had already stalled about 10 min between census y=3000 and y=4500 (02:29:51 to 02:39:49, probe "proxy down, page missing" at 02:39:32). That is an early sign of the same pressure (INFERRED).
- Host load1 of 700 to 900 with idle 0 % appears in healthy runs too, so it does not tell failing from healthy jobs (MEASURED, job logs).
- Runner: macOS 27.0.1, image `20261023.0307.1`, Xcode 27.1, 3 CPUs, arm64.

## Sources

- Code 405 text: fastlane/fastlane#30353 (`simctl uninstall` on a shut-down device prints `code=405 ... Unable to lookup in current state: Shutdown`) and software-mansion/argent#1029 (same wording for a shut-down device). No Apple document names code 405; the meaning "the command needs a booted device" is INFERRED from these reports.
- Slow `simctl` on virtual runners: actions/runner-images#13459 (a maintainer: "a known performance issue with the Core Simulator Runtime in virtual environments, starting with Xcode 26.0"; unofficial `yeetd` mentioned) and actions/runner-images#14888 (`simctl help list` timed out, no cause given).
- `simctl` has no documented timeout; the limits below are ours (see `lean/Fw/Device/SimRelaunch.lean`).

## The Lean machine (`Fw.Device.SimRelaunch`)

- Pass: `running`, `relaunching`, `rebooting`, `done`, `failed` with the named failures `deadAgain`, `relaunchFailed`, `rebootFailed`, `protocol`. Events `passOk`, `deadUp`, `deadDown`, `relaunchOk`, `relaunchFail`, `rebootOk`, `rebootFail`.
- Theorems (each branch of the step has its own): `reboots_le_one`, `relaunches_le_one`, `attempt_le_three`, `retry_after_answer` (the attempt number rises only on `relaunchOk` or `rebootOk`), `running_after_answer`, `done_after_pass`, `pass_ends` (done or a named failure within 5 events), `pass_time_le` (at most `boundS init` = 1527 s).
- Call: one `simctl` call is 2 tries with 2 s between; a transient result is retried only below the limit, a permanent one never (`call_retry_is_policy` ties this to `Fw.Measure.Retry.shouldRetry`); `call_ends_in_two`.
- Limits: state check 30 s per try (62 s worst), shutdown 40 s (82), boot 60 s (122), bootstatus 120 s (242), list 90 s (182). Detect = 85 s probe + 62 s = 147 s. Relaunch 320 s. Reboot = 82 + 122 + 242 + 320 = 766 s.
- "Pass" in the model is the guard's lifetime (one session): the budgets are per session, which is stricter than per pass.

## Limits and open items

- A healthy session already takes up to 31.1 min of the 35 min step bound (`SimBound.perSessionMin`, MEASURED over 56 green jobs). A late reboot (766 s) does not fit; the step ends it as a timeout. `reboot_exceeds_spare` and `step_with_recovery_fits` state this: the step bound needs `recoverMin` = 13 more minutes. That edit is in `Fw.Measure.SimBound` and `simplan.mjs`, outside this task's writes.
- The reboot path blocks the event loop in `spawnSync` for up to 446 s; the stall watchdog (720 s of silence) stays quiet because each call logs.
- A device that shuts down and a CoreSimulatorService that never answers are outside our process; the run ends with the named failure (`rebootFailed`), not with a lost VM.
- A runner that disappears (40151813906 r1) cannot be recovered from inside the job.
- A `Determinism sessions` step that does not end at the step bound (40162538610 r2, 40151813906 r1) is incident inc-sim-step-unbounded; the in-script watchdog is task sim-step-watchdog, not this one. A blocked `spawnSync` of a simctl call stuck in the kernel would stop the in-process stall watchdog too (INFERRED, Node waits for the child to exit after its timeout kill).
- TS stand-ins: `guard.mjs` (`step`, `exec`, `used`, `cost`, `timeUsed`, `RECOVER`) replays `golden/device/sim-relaunch.jsonl`; the per-call retry is `simretry.mjs` with `max` 2, replayed in `sim-relaunch.test.mjs`. The wait for the Simulator's answer (`deviceBooted`) and the shell calls are glue.

# macos-vm-loss: what stalled the Determinism sessions, and what phase 1 changes

Date: 2026-10-25. Task `macos-vm-evidence`, phase 1. Branch `worktree-wf_8b04760d-e7c-1`, CI branch `ci/macos-vm-evidence`.

## Answer

- None of the four named stalls was one simctl or inspector call that hung forever. In every readable log the time went into chains of bounded waits (120 s inspector timeouts, 480 s target waits, reboots) and silent spans with no log line (MEASURED, job logs below).
- The Simulator alternates fast and starved phases inside one job: pass 1 of 40196209240 r2 took 29 min, pass 2 of the same job reached y=4500 in 80 s (MEASURED).
- Sync simctl kept its per-try bound: the reboot `bootstatus` (limit 120 s per try, 2 tries) timed out once at 121 s, waited 2 s and passed on try 2, 174 s in total (MEASURED, 40196217959 r3 attempt 2, job 121229805389). The cost of sync simctl was the blocked event loop: while a call ran, the watchdog tick and every JS timer were blocked (CONFIRMED: `spawnSync` blocks the event loop, `sim.mjs` at 1c493c313 used it with `SYNC_CAP_MS` 200000 and `Atomics.wait` retries).
- The exit-130 case (40196217959 r3 attempt 1) was not sync simctl: the watchdog fired after 726 s of silence in `seekExperiment` and no simctl call ran then (MEASURED). This refines check.md point 3 of the corrected Q1 ranking (sync simctl explains the exit 130): it holds for the bound error, not for this exit.
- Why the VM is lost ("lost communication"): UNKNOWN. None of the 4 lost jobs has telemetry.

## The four runs

| run | job | what the log shows | class |
|---|---|---|---|
| 40196217959 r3 a1 | 121183909543 | 26 min; watchdog "no output for 726 s (limit 720 s)" after `scroll: 107 steps`; exit 130; warm-up Timeline.stop timeout 120 s | silent span, no simctl |
| 40196217959 r3 a2 | 121229805389 | 35 min step timeout; pass 1 began at minute 32; "serving" to "proxy up" 113 s; warm-up Runtime.evaluate timed out twice at 120 s; target waits 480 s twice; a reboot whose `bootstatus` timed out once at 120 s and passed on try 2 (174 s in total) | starvation chain |
| 40196209240 r2 | 121178260142 | 35 min step timeout; pass 1 took 29 min: 548 s silent span, 310 s census gap, 120 s evaluate timeout, 45 s scroll; pass 2 reached y=4500 in 80 s | starvation chain |
| 40196227509 r2 | 121178337329 | 35 min step timeout; 115 s to proxy up, 257 s before warm-up failure, 120 s evaluate timeouts | starvation chain |
| 40196227509 r1 | 121178337304 | step failed at 30:26, cause not logged; "Keep logs" 6 min, "Host state on failure" 7:19, upload-artifact cancelled at the 58 min cap | VM-level starvation (INFERRED) |
| 40196212618 r1 | 121178380700 | started 15:24:37, cancelled at the job cap 16:19:30, no log retrievable | lost, UNKNOWN |

Cancelled jobs keep no log, so the last two rows rest on step timings only.

## What phase 1 changes

- simctl calls run async (`packages/measure-webkit/src/sim.mjs` `runAsync`). The bound per call is the Lean `Fw.Ci.Telemetry.callBoundMs` (limit capped at 200 s), SIGKILL follows after a 5 s grace, so a call ends at `callSettleMs` at the latest. Theorem `retried_call_before_stall`: two settled calls plus the longest wait stay under the 720 s stall limit.
- The watchdog says when its tick came a whole period late ("event loop blocked") and lists the host calls running with their age and bound, in the warning and in the stall message. The warning does not count as output (`watchdog.mjs`).
- Each finished pass is written to `<out>.pass-N.part` (atomic), so a later loss keeps the earlier passes. The suffix is not `.json` because the workflow merge globs `v*-session-*.json`.
- The telemetry probe carries swap used, compressor size, stored pages, swapouts, compressions, the kernel pressure level and the free percentage (`scripts/ci-telemetry/lib.mjs`). Memory "used near total" stays MEASURED; pressure is now read directly.

## Not changed

- Counts: the async layer changes how simctl is called, not what is measured. Evidence is the golden replay of the decisions plus the one CI run named in the handoff.
- The 120 s inspector command timeouts and 480 s target waits are untouched (outside this task).

## Phase 2 (waits for cross-pool-pooling and push-cycle-lag)

- Upload `out/$VM-session-$s.pass-*.part` per pass and the telemetry `probes.jsonl` periodically, in `webkit-sim.yml` and `toolbar-throttle.yml`.
- A job-length cap and a load guard come only after a lost job leaves telemetry.

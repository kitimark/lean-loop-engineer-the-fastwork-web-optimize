# wk-sim-hang: why webkit-sim VMs hang in "Determinism sessions", and the retry and host gates

Date: 2026-10-26. Task `wk-sim-hang`. Branch `worktree-wf_2b596ca9-a1d-1`, CI branch `ci/wk-sim-hang`. Start commit fff591625.
Data: `results/wk-sim-hang/` (`jobs.json` per job, `segs.json` retry segments, `failed-jobs.txt`, `scripts/`). Source of every number: job logs of 127 finished sim jobs in 53 runs (40068835920 to 40284464262, 10-24..26), downloaded with `gh run view --job <id> --log`.

## Answer

- The load is not ours: the VM is at load1 87..993 (3 cores) in green and failed jobs alike, and it rises during `simctl boot`/`bootstatus`, before any measuring code runs. The busiest processes are the Simulator runtime daemons (`diagnosticd`, `backboardd`, `SimRenderServer`, `SimMetalHost`) on image macos27 20261023.0307.1. CONFIRMED (probes and host dumps below). Nothing in our code can lower it; `hostOk` only guards beyond the envelope seen.
- One piece of our code made it worse: the load stamp called `top -l 2` through `spawnSync`, which stops the whole event loop, the stall watchdog's timer included. In run 40282962088 job sim-r1 the loop stood still 1399 s (the watchdog reports it after the fact) and the job died at the watchdog stall exit after 1409 s; sim-r3 of the same run hung until the 35 min bound. CONFIRMED for sim-r1 (log line `event loop blocked 1 time(s), worst 1399 s`, last line before it `pass 1/2`, whose next action is `loadStamp()`); that `top` was the call that did not return is INFERRED (it is the only synchronous call between those two points; why `top` did not exit under load 900 is not known).
- Fix 1: `load.mjs` reads the kernel counters in process, starts no child, never blocks (`packages/measure-webkit/src/load.mjs`, test `test/load.test.mjs`).
- Fix 2: both retry levels (scroll attempts, pass attempts, `FW_WK_ATTEMPTS` 3 each) now start a retry only if it is expected to end before one shared deadline, the step bound minus 60 s (Lean `SimHost.retryFits`). Before, 3 x 3 attempts with reconnects of up to 890 s each could not end inside 35 min.
- Fix 3: a pass whose host was past load1 1320 at its start or end is not counted: repeated if a retry fits, else refused (Lean `SimHost.afterPass`). The ceiling is 1.3 x the highest load seen (1015.92), so it does not separate failed from green jobs (honest limit).
- 26 of 124 finished jobs in the sample failed (21%; the task baseline is 26 of 134 = 19%, 14 of 31 on 10-26 = 45%). Only 3 of the 26 have the loop blocked at all (47 s, 165 s, 1399 s), so the `top` call explains a minority; the other failures are listed below and are not fixed by this task.

## Failed jobs by terminal cause (sample, `results/wk-sim-hang/failed-jobs.txt`)

| Cause | Jobs | Class |
|---|---|---|
| inspector dead, `simctl shutdown`/`terminate` ETIMEDOUT, `forced exit` 20 s after the command | 9 | MEASURED (the host calls themselves time out on the starved VM; follow-up) |
| step never ended, job cancelled at the job bound, no log | 5 | MEASURED (same class as inc-sim-step-unbounded; runner lost, INFERRED) |
| watchdog stall exit (742..1409 s without output), 3 of them with a blocked loop | 5 | MEASURED |
| step bound 35 min reached, process group stopped | 4 | MEASURED |
| `simctl list`/`lsof` ETIMEDOUT at start | 2 | MEASURED |
| `setTypeOfService EINVAL` (old run 40143379767) | 1 | MEASURED, unrelated |

## Load against phase (telemetry probes, load1)

| Run / job | Result | at boot start | at boot end | 300 s into the step | max |
|---|---|---|---|---|---|
| 40282962088 sim-r1 | failed | 5.0 | 172 | 942 | 942 |
| 40282962088 sim-r3 | failed | 8.0 | 232 | 765 | 1015.9 |
| 40282951274 sim-r1 | green | 12.7 | 445 | 934 | 1011.2 |
| 40282951274 sim-r2 | green | 3.7 | 370 | 764 | 975.1 |

Sample-wide (98 green, 11 failed jobs with a load stamp in the log): highest load1 1013.15 green, 955.52 failed, medians 863 and 910. Load does not tell the two apart. CONFIRMED (`results/wk-sim-hang/jobs.json`).

## Seen maxima (Lean `SimHost.Seen`, seconds; green jobs)

| Piece | Max | Run, job | n |
|---|---|---|---|
| start ("serving" to "proxy up") | 199 | 40236531932, 121300136535 | 98 |
| warm-up | 822 | 40171953359, 121153585933 | 98 |
| first pass | 1123 | 40271367353, 121416196352 | 18 |
| second pass | 896 | 40271370582, 121405613291 | 18 |
| whole step | 1734 | 40271367353, 121416196352 | 18 |
| scroll retry (failure to end of the retried step) | 589 | 40171941566, 121153604305 | 13 |
| pass retry (failure to end of the repeated pass) | 436 | 40271367353, 121416196352 | 3 |

Pass and step times exist only for the 18 green jobs whose log has `pass k/2` markers. 65 of 98 green jobs had at least one retry, so the gate must not refuse a retry that fits the measured time: its need is the Seen retry maximum, not the worst case (890 s reconnect), which would refuse retries that succeed today. Warm-up retries (`perstep.mjs`) are outside the task's writes and are not gated.

## Lean (`lean/Fw/Measure/SimHost.lean`, `SimHostGolden.lean`)

- `run_stop_le`, `runPass_stop_le`: with each try bounded by `need` and each pass attempt by `outer`, a retry decided at either level ends within the bound, and with no retry the level ends within `need` (`outer`) of its start.
- `afterFailure_le`, `redo_fits`: a retry or repeat decided on is within the attempts and the bound.
- `refuse_not_counted`, `counted_hostOk`, `fit_counted`: a refused host never yields a counted pass; a counted pass had a fit host at both ends.
- `stepS_lt_gate`, `retry_after_warm_fits`, `late_retry_refused`, `perSession_vs_step`: the longest step seen (1734 s) is below the gate bound of 35 min (2040 s); a retry right after the longest start and warm-up fits; a retry after the longest step is refused; `perSessionMin` 35 covers the longest step plus the 60 s margin and is within a quarter of it, so the maxima do not call for raising it.
- `determinism.mjs` follows `retryFits`, `afterFailure`, `afterPass`, `gateBoundS` through `packages/contracts/golden/measure/sim-host.jsonl` (`test/sim-host.test.mjs`). The step clock is `FW_MEASURE_T0_MS` (set by `tick.mjs launch`) and `FW_WK_STEP_MIN` (workflow, from the plan); without them there is no bound, as on a local run.
- TS stand-ins: none for the decisions. Glue only: the loops in `determinism.mjs` call the replayed functions.

## CI re-measure

Pending: see the section added after the runs.

## Open

- Host calls that time out on the starved VM (`simctl terminate/shutdown`, `lsof`) block the loop for up to 137 s; nine failures end that way. Follow-up: run them asynchronously.
- The warm-up retry loop in `perstep.mjs` is not gated; with several sessions per step the deadline is shared by all of them (the clock starts at launch).
- `Classes.lean` one-pass-VM counting is out of scope.
- The Simulator runtime load itself: a runner-image or GitHub question, not ours.

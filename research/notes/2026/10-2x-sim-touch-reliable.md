---
id: 2026-10-2x-sim-touch-reliable
kind: note
title: "Real finger swipes in the CI Simulator: why a push took 50-130 s and Timeline.stop timed out, and the bound that replaces the wait"
status: review
created: 2026-10-23
topics: [webkit, simulator, xcuitest, timeline, inspector, measure, touch, ci]
---

# Why the CI Simulator's real-touch push was slow, and what bounds it now

Task `sim-touch-reliable`. Runs `39901005729` (stop wait 60 s) and `39909042070` (stop wait 240 s, two sim jobs cancelled at
the 50-minute step limit) kept real-touch end windows in only the first 1 to 3 windows of a job. WebKit cites `@862f17d`.

## Answer

- **XCUITest steps stall under runner load; the swipe itself is cheap (CONFIRMED stalls, INFERRED reason for the idle wait).** The idle wait is one instance (run `39901005729`, below); `Find the Application 'com.apple.springboard'` taking 27 s in run `39934951574` is another. The driver
  log tail kept in the run `39901005729` job 1 artifact (`sim.json` field `push.why`, read when the harness gave up) shows the
  up swipe taking 2.3 s (`Synthesize event` 584.41 to 586.71 s, post-event wait 0.01 s), the down swipe starting at 586.72 s with a
  0.01 s pre-event wait, finishing its event, and then the last line: `Wait for com.apple.mobilesafari to idle` at 591.00 s with
  nothing after it. So XCUITest was waiting for Safari to go idle after the last release. Why Safari did not go idle is
  INFERRED: the runner VM had load average 479 to 574 (`host.txt` of the same artifact; Simulator render, WebKit GPU,
  WebContent and diagnosticd at the top), and the page was running the recorder's `requestAnimationFrame` loop, a 40 ms timer,
  and the morph close animation. XCUITest's idle test is "event loop idle and animations finished"
  (strings of `XCUIAutomation` / `XCTAutomationSupport` in Xcode 27.1: `isQuiescent: ... eventLoopHasIdled ... animationsHaveFinished`,
  `XCTMainRunLoopIdleNotifier`, `XCTAnimationsIdleNotifier`, "App event loop idle notification not received, will attempt to
  continue."); the public headers (`XCUIElement.h:93-100`, `XCUICoordinate.h:46`) have no way to switch the wait off or to
  set its timeout.
- **On a quiet Mac the same push takes 4.6 s (MEASURED locally, debug evidence only, not a result).** Per press: pre-event wait
  0.02 s, interrupt check 0.2 s, five `Find the Window` snapshots inside `Synthesize event`, 2.0 s of finger (0.1 s press,
  0.5 s drag, 1 s hold), post-event wait 0.03 s. `10-2x-toolbar-throttle.md:91-102` saw 60 to 185 s per
  pass on the runner against about 50 s on a Mac.
- **Timeline.stop timed out because a touch window recorded minutes of Timeline (INFERRED mechanism, CONFIRMED volume).**
  `InspectorTimelineAgent::stop` is cheap (`InspectorTimelineAgent.cpp:112-120`, `internalStop` 186-199: no work
  proportional to the records). But the stop reply and every record share one channel in order:
  `InspectorFrontendRouter.cpp:87-97@862f17d` (`sendEvent` and `sendResponse` both call `connection->sendMessageToFrontend`),
  one XPC message each through `RemoteConnectionToTarget::sendMessageToFrontend` (`RemoteConnectionToTargetCocoa.mm:249-262`),
  and the command itself is run on the page's main run loop (`dispatchAsyncOnTarget`, `RemoteConnectionToTargetCocoa.mm:146-149,238-247`).
  The first touch windows ran 47 to 73 s with 9,440 to 21,985 records (run `39901005729`), against 7 s and about 1,500 records for a
  synthetic window. The `ios-webkit-debug-proxy` that carries it is one `select` loop with 4096-byte reads and send-queue
  back-pressure (`socket_manager.c:620-690`, `ios_webkit_debug_proxy_main.c:183@278bf48`). In job 2 the stop timeout was followed by
  `Runtime.evaluate timed out after 120000 ms`: every later command waited too. That the channel (and not only the
  starved WebContent process) is what stalls is not separated by these logs.
- **Raising the stop wait cannot fix it (MEASURED).** With 240 s, job 2 still timed out and kept 0 of 15 windows; jobs 1 and 3
  hit the 50-minute step limit.
- **The Timeline of a touch window is not needed.** Frame counts and intervals come from page timestamps (`rec.ts`); the
  Timeline only gave per-zone render work. A touch end window now records no Timeline (Lean `timelinePlan`), so no stop
  can time out there.

## CI proof (MEASURED)

Run `39934951574`, branch `ci/sim-touch-reliable`, commit `610d43d70`, smoothness workflow with `[webkit-cadence] [earn-bound] [sim-only]`
(arms base, aa, bound; 6 reps; 3 sim jobs on separate macOS 27 VMs; default variant `springboard`, no Timeline in touch windows).
All three jobs finished (`success`), 1348, 1847 and 1456 s of probe wall time; run `39909042070` had two of three jobs cancelled at the 50-minute step limit, and run `39901005729` lost the touch lane at the 2nd or 3rd window.

| job | end windows | touch pushes ok | non-ok | begin max (ms) | swipe max (ms) | done max (ms) | lane at end |
|---|---|---|---|---|---|---|---|
| 1 | 18 | 16 | 1 swipeLate (swipe 33,231 ms, done 128,351 ms) | 4,134 | 18,558 | 110,167 | off (synthetic after push 16) |
| 2 | 18 | 18 | 0 | 17,350 | 10,092 | 28,560 | on |
| 3 | 18 | 18 | 0 | 6,785 | 7,198 | 54,674 | on |
| all | 54 | 52 of 53 | 1 | 17,350 | 18,558 | 110,167 | |

Over the 52 ok pushes: begin p50 2.0 s, swipe p50 5.9 s, done p50 11.2 s and p90 26.1 s; per press p50 4.2 s, p90 5.5 s, max 19.0 s
(`sim.json` field `rows[].touched`, artifacts `smoothness-webkit-sim-1..3`). The earlier runs took 50 to 130 s per push at the
first touch windows and lost the lane at the 2nd or 3rd. Slowest push of this run: `Find the Application 'com.apple.springboard'`
inside `Synthesize event` took 27 s (log tail of job 1, 787.20 to 814.51 s), so XCUITest's element snapshot also stalls under
load, besides the idle wait. That push crossed the 20 s swipe deadline, classified `swipeLate` and turned the lane off; the retry
(synthetic wheel) first hit `Timeline.stop timed out after 60000 ms`, then succeeded: a 398 s synthetic window; the Lean bound covers touch windows only.

What this does not show: two things changed together (no Timeline in touch windows, SpringBoard coordinates), so which one
removed the stalls is not separated. A control arm needs `FW_TOUCH_VARIANTS=safari` on the same commit (not run). Non-touch
windows still lose a Timeline.stop now and then (job 3: one hero window at 60 s, one `Runtime.evaluate` at 120 s; job 1 after
the failed push), so record volume is not the only cause of stop timeouts; the inspector channel is flaky on the runner
(`inspector probe failed (tick): socket up, proxy down, page listed`).

## The bound (Lean `Fw.Measure.TouchPush`, golden `packages/contracts/golden/measure/touch-push.jsonl`, 21 lines)

| Deadline | ms | Why this size |
|---|---|---|
| ready (driver start to Safari in front) | 240000 | runs above: 51 to 214 s |
| begin (go file to first touchstart) | 45000 | a push begins within 0.4 s on a quiet Mac; 100 times that |
| swipe (first touchstart to last touchend) | 20000 | 3.6 s on a quiet Mac |
| tail (page keeps recording after the last touchend) | 600 | the morph close |
| answer (page value after it was told to stop) | 20000 | |
| done (driver's `done-n` after the swipe deadline) | 60000 | |

- `classify` has five outcomes (ok, pageLost, beginLate, swipeLate, noMove) in a fixed priority; one theorem per branch and an
  iff for `ok` (`classify_pageLost` ... `classify_ok_iff`).
- `windowCap` = begin + swipe + tail + answer = 85,600 ms; `spent_le_windowCap`.
- `lane_failures_le_one`: any job has at most one failing touch window, because a failing window or a late driver turns the
  touch lane off for the rest of the job (`laneAfter_fail`, `laneAfter_slowDone`, `laneAfter_off`).
- `lane_time_le`: n touch windows cost at most n x (windowCap + doneMs) = n x 145,600 ms. Run `39909042070` job 2 spent
  760,912 ms on one window.
  The bound is on the model `spent`; the harness meets it only if every awaited inspector call inside the window is raced against the same deadlines (run 39934951574 job 1 push 16 reached the done check at 128 s, above windowCap, because the stop evaluate was awaited with the 120 s CI evaluate timeout).
  `touchWindow` now sends the stop evaluate without awaiting it (per-call timeout answerMs) and races the start evaluate against answerMs, with tests that never-resolving stubs return within windowCap + pollMs; CI re-proof of this harness is a dispatch item.
- `timelinePlan_touch` / `timelinePlan_other`: touch window records none, any other window stops its Timeline within the stated wait.

The bound says the harness stops waiting; it does not make XCUITest finish a push when the runner is starved. One
failing push per job is the worst case, after which the job continues with the synthetic wheel (within 3 minutes, not the step limit).

## Harness changes

- `touch-push.mjs`: `touchWindow` writes `go-n` with a variant, waits for the page at most `windowCap`, tells a page that is still
  recording to stop at the deadline, and waits for `done-n` at most until begin + swipe + done after the go file. It returns the
  Lean observation (`beginAt`, `swipeAt`, `moves`, `answered`, `doneAt`) and the driver's per-press times. The page ends its own recording
  `tailMs` after the second `touchend` (`touchCountJs`), so the recorded window holds the fingers' time, not the driver's waits.
  Page times are `performance.timeOrigin + performance.now()` because the harness pins `Date`.
- `PushServer.swift`: `go-n` text `safari` takes coordinates from Safari's window (as before); `springboard` (default) takes the same
  screen point from SpringBoard, so the pre- and post-event waits are on SpringBoard, which is idle while Safari is in front. The
  local log shows the touch still reaches the page (46 to 48 moves, begin 0.3 s, swipe 3.6 s) and still shows one nested
  `Wait for com.apple.mobilesafari to idle` inside the interrupt check before the event (0.09 s on a quiet Mac). So the variant removes the
  post-event wait that stuck in the CI log, not every Safari wait (INFERRED; the CI run decides). `FW_TOUCH_VARIANTS=safari,springboard`
  alternates by push index; `FW_TOUCH_KEEP_LOG=<file>` keeps the XCUITest log.
- `sim-cadence.mjs`: touch end windows start no Timeline, rows keep `mode:'events'` with `records:0`, `timeline:false`,
  `ok:false` (`marks-missing`, as the reducer sees an empty record list), `push:'touch'`, and `touched` carries variant, outcome,
  observation and press times. A failing or late push turns the lane off, stops the driver and falls back to the synthetic wheel.

## TS stand-ins (not proved)

`classifyWindow`, `doneInTime`, `laneAfter`, `spent`, `windowCap`, `timelinePlan` in `touch-push.mjs` are replayed against the Lean golden in
`test/touch-push.test.mjs`. `touchWindow`, `touchCountJs`, `PushServer.swift` and the `sim-cadence.mjs` wiring are glue and not golden-checked.

## Open

- Phone not measured. Control arm (`FW_TOUCH_VARIANTS=safari`, same commit) needs the workflow to pass the variable (`smoothness.yml`, owned by smoothness-cpu-throttle).
- `report.mjs` labels the Timeline column from `mode`, so touch rows read "on"; a `timeline:false` label is a follow-up (outside this task's writes).
- Simulator hero windows are starved on the runner (2 to 40 frames in 7 s, runs above); not touched here.
- Lengthening the stop wait (60 s to 240 s) made the job slower and kept fewer windows.

## Job-level bound (round 3, after run 39957772249)

Run `39957772249` (commit `6928ed7c6`, 3 sim jobs one after another) broke the stated bound: job 1's walk step ran 43 min 27 s and the job
ended cancelled at 55 min; jobs 2 and 3 ended in 24 and 39 min.

- **Where job 1's time went (CONFIRMED from step times of the jobs API; log text is not served for a cancelled job).** The walk step had
  `timeout-minutes: 50`, the job `timeout-minutes: 45`. The job timeout fired first (job start 13:02:45Z, step cancelled 13:50:47Z, 3 min
  after the 45th), so the step limit could never act; the post steps carry `!cancelled()` and were skipped (Keep host state, upload), so
  no `sim.json` and no `sim.log` were kept. The always-run telemetry step began at 13:50:55Z and did not finish before the runner
  was reclaimed at 13:57:46Z.
- **Why the walk is long (MEASURED in the logs of jobs 2 and 3).** The touch bound covers 18 end windows. The 36 hero and end windows are
  the rest: typical 7 to 35 s, but job 3 has end windows of 107, 185, 247 and 291 s (31,846 and 36,311 Timeline records after the lane fell back to the
  synthetic wheel), plus retries (`Timeline.stop timed out after 60000 ms`, `Runtime.evaluate timed out after 20000 ms` with
  `FW_WK_ATTEMPTS=3`). Walk time: job 2 20.6 min, job 3 32.5 min; job 1 more than 43 min (its windows are not readable).
  The walk has no per-window bound outside the touch lane, so no sum of per-window bounds can be the job bound: 18 touch windows at
  145,600 ms already exceed the deadline below (Lean `static_sum_exceeds`).
- **The rule (Lean `Fw.Measure.WalkBudget`, golden `walk-budget.jsonl`, 12 lines).** A deadline from the job start:
  45 min timeout - 10 min post steps (host state 1, upload 2, upload retry 2, shutdown 2, telemetry 2 = 9 min of `timeout-minutes`, 1 min unused) - 2 min
  grace - 1 min slack = 32 min. The workflow records the job start, the `Walk budget` step computes the deadline and
  the walk step's `timeout-minutes` (whole minutes up to deadline + grace; `stepEnd_le`, `job_ends_inside`), and skips the walk when
  under 2 min remain (`runsWalk_false`). The harness starts no window that cannot finish (30 s reserve, `startsWindow_false`), abandons a
  window in flight at the deadline and writes the rows so far (`incomplete: walk deadline ...`), then exits explicitly. It also rewrites
  `sim.json` after every window, so a killed walk keeps its rows. Post steps run on `always()`.
- **First proof run, `39981414973` (commit `d6413d23d`): the cut worked, the bound did not hold (MEASURED, step times).** Job 1 (`[sim-walk-cap=8]`)
  ended its walk 8.5 min after the start with `walk deadline: abandoned a window in flight after 4 windows` and uploaded `sim.json`, `sim.log`,
  `walk-budget.txt` (the dynamic `timeout-minutes` expression is accepted). Job 2 finished (20.5 min). Job 3: deadline 17:00:40Z, step timeout 17:02:05Z,
  but the walk step ended at 17:06:29Z (failure), Keep host state failed at 17:10:51Z (4.1 min on a 3-min limit), the shutdown and the upload were cancelled
  by the job timeout at 17:12:38Z, no artifact. So (1) the harness did not stop itself at the deadline: its event loop was blocked in our code: `simctl` runs through `spawnSync` with `T(90000)` = 720 s timeouts, three tries with `Atomics.wait`
  (`sim.mjs:38-52,104-105`), none of which a timer can interrupt; (2) the runner enforced the step timeout 4.4 min late and the
  post steps ran 2 to 4 times slower than their limits (host starved, as in the runs above).
- **Round 3b.** A process-group hard stop 45 s after the deadline (`hardStopMs`, `hardStop_inside_step`: it falls inside the walk
  step's own timeout, so the runner is not what ends the walk), `sim.json` rewritten after every window, upload first, host state in its own small
  artifact, post allowance 10 min. The harness blocking itself is not fixed (the `spawnSync` calls stay); the kill bounds it.
- **Second proof run, `39995201296` (commit `f50ab2ba3`, `[sim-walk-cap=8] [sim-walk-hang=6]`) (MEASURED, step times and job logs).**
  Job 2 (event loop blocked by the test hook at 2 min): the hard stop fired (`walk hard stop: killing the process group`), the walk step ended
  17:56:34Z (7 min after its start, inside its 8-min step), every post step took under 15 s and `sim.json`, `sim.log`, `walk-budget.txt` were
  uploaded; the job failed as designed. Job 3 (natural, 26.6 min job) succeeded. Job 1 (cap 8): the harness stopped itself at its deadline
  (17:40:37Z, `abandoned a window in flight after 0 windows`, the hard stop did not fire), but the host was starved (load average above 500, setup
  1.8 min to serve, no tab for 5 min), so 0 windows; the first upload timed out at its 2-min limit (6 small files, listing alone took 60 s),
  the host upload after it took 11 s. Job 1 ended 17.7 min after its start. So the bound held on all 3 jobs; the one miss was an upload
  stall on a starved runner, which cost the main artifact. Round 3c: host state is written into `result/` and runs first, one upload with one
  retry under another artifact name.
- **Third proof run, `40003317485` (commit `c0cb0f0dd`, `[sim-walk-cap=10] [sim-walk-hang=6]`): all 3 jobs ended inside the bound with logs kept (MEASURED, jobs API and artifacts).**
  Job 1 (cap): 16.9 min, walk ended at its deadline with 20 windows and `incomplete: walk deadline: no time left to start aa hero rep 3`, sim.json, sim.raw.json.gz, sim.log, host.txt,
  walk-budget.txt uploaded in 59 s. Job 2 (event loop blocked): 13.1 min, `walk hard stop: killing the process group`, sim.log, host.txt and walk-budget.txt uploaded
  (no sim.json: the block came before the first window ended, setup took 114 s). Job 3 (natural, no cap): 33.9 min, walk step 30 min, ended at the deadline with 16 windows
  (`no time left to start aa hero rep 2`), uploaded. Keep host state hit its 1-min limit in job 1 (77 s on a starved host) and failed the job, so it now has `continue-on-error`
  (not re-run on CI: one attribute, actionlint clean).
- **Cost.** Setup is 3.7 to 4.6 min in the jobs, so the walk gets about 27 min; job 3 of run `39957772249` (32.5 min walk) would
  have lost its last windows, with the rows kept.
- TS stand-ins: `walk-budget.mjs` functions replayed against the golden; the `sim-cadence.mjs` loop wiring, `untilDeadline` and the workflow's hard-stop wrapper are glue
  (`untilDeadline` has a unit test; the wrapper was run once locally with `sleep` and exit codes, debug evidence only).

## Follow-ups (sim-touch-followups)

Items (1) to (6) of the 2026-10-24 review of run `40003317485`. Source data: the `sim.log` and step times of runs `39934951574`, `39995201296` and `40003317485` (`gh run download`, `gh run view --json jobs`).

### Rep plan (item 4): Lean `Fw.Measure.WalkBudget.planReps`, golden `walk-budget.jsonl` (27 lines)

- **What failed (CONFIRMED, run `40003317485`).** The rule "a job needs 5 kept end windows per arm" is `Fw.Gate.Smooth.minReps`, per job: `jobCadence` and `zoneVerdict` decide inside one job, `acrossJobs` only counts agreeing verdicts, so windows of different jobs are never pooled. Job 1 was cut by the test cap (20 windows, 3 to 4 reps), job 3 by the 32-min deadline at 16 windows because four windows took 217, 744, 84 and 84 s (host load average 718 in `host.txt`).
- **Cost of a window (MEASURED, 144 windows of the four complete 36-window walks).** Mean 35.6 s per window (job means 31.5 to 42.9 s), p50 17 to 31 s, p90 31 to 102 s. Cumulative time to the 30th window (5 reps of 3 arms): 703, 1060, 1194 and 1433 s, all under the 1644 s a walk has after a 4.6-min setup. The one starved job (`40003317485` job 3) needed 1477 s for 16 windows.
- **The plan.** `planReps dl now arms = min (repsLife arms) (repsFit dl now arms)`: `repsFit` = whole reps of `2 x arms x 45 s` that fit between now and the deadline, `repsLife` = whole reps in the Simulator's 36 windows. `outcome` is `ok` iff both give `minKept` (5), else `lifeShort` (4 arms or more: 4 reps of 8 windows) or `budgetShort` (walk started late or capped). One theorem per branch: `outcome_lifeShort`, `outcome_budgetShort`, `outcome_ok`; `outcome_ok_plan` (ok means at least 5 planned reps), `outcome_ok_time` (5 reps at 45 s fit before the deadline), `planReps_fits`, `planReps_life`. The rep-major order (hero then end, per arm, arms rotated per rep) gives arm at position p `endsDone` = `n / (2 arms)` or one more end windows after `n` windows (`endsDone_ge`, `endsDone_le`), so `kept_after` and `planReps_complete`: after the planned reps every arm has at least 5 end windows.
- **Decision.** Per job, not across jobs: pooling two jobs would need a pooled verdict in `Fw.Gate.Smooth`, and the per-job verdicts are the independent noise samples the design relies on. "Fewer reps per job" does not help (a job below 5 cannot decide); the harness now runs `--reps auto`, which for 3 arms is 6 reps (36 windows, the old `[sim-only]` value; `[earn-bound]` asked 7, which the budget never fit) and logs the outcome; 4 arms are `lifeShort` and need the arms split over jobs (follow-up, not built). The header of `smoothness.yml` no longer promises 6 reps.
- **Limit (accepted).** `windowMs` = 45 s is a mean with margin, not a bound: a starved job (3 windows over 150 s) misses 5 reps. The deadline still holds; the job ends with its rows and the verdict says insufficient.

- **Clock (INFERRED).** The plan is computed before Simulator boot and the touch driver start (50 to 66 s); 6 reps fit only because the mean window is about 33 s, not the 45 s allowance (INFERRED from run 40039631149 walls 1184/1352/1020 s (`sim.json` wallSeconds of jobs 2, 3, 4; the table's walk includes setup)). `outcome_ok_time` proves 5 reps at 45 s fit between the plan's clock read and the deadline, not that the setup after the read leaves that time.
- **Item 4 result (CONFIRMED finding, closed): with 3 SpringBoard jobs this lane cannot give an across-job verdict.** `Fw.Measure.WalkBudget.outcome` is a per-job plan; the docstring now says so. Reproduced by `node packages/measure-webkit/src/profile/cli.mjs report` over the sim artifacts of run `40039631149` (control job 4 left out by `isControl`): `sim-cadence-verdict`: `end touch | base, bound | 3 jobs | same 2 | insufficient 1 | insufficient`, and `sim-verdict`: `finish | base, bound | 3 jobs | insufficient 3 | insufficient`. Two causes. (a) `acrossDecisive` needs `minSamples` = 3 decisive jobs (`packages/gate-breakpoints/src/smooth/reduce.mjs:98`, `Fw.Gate.Smooth.minSamples`, `Smooth.lean:666`); there are only 3 SpringBoard jobs, so one starved job (job 1, 11 windows) removes the verdict. (b) Touch end windows run with no Timeline, so the gate's finish zone gets at most 3 reps per arm in any job (headline finish n per job: base 1+0+1, aa 0+0+1, bound 1+0+3); the 5 kept finish windows of `minReps` are never reached and this note counts cadence intervals in their place. The re-plan (across-job verdict, tail-quantile budget, Timeline in touch windows, job count) is graph task `sim-touch-verdict-jobs`, not built here.

### Gaps and docstring (item 5)

`Gaps` in Lean names what the 1-min slack covers, each at the longest value of the three jobs of run `40003317485` (jobs API step times): `clockMs` 6 s (runner job start to the Job clock step, 3 to 6 s), `driftMs` 50 s (the Walk budget step reads the clock; the walk step starts when it ends, step took 22, 36 and 50 s on a starved host), `completeMs` 4 s (Post and Complete job steps, 1 to 4 s). They sum to `slackMs` (`gaps_total`); `job_ends_inside_gaps` states the job end with the three gaps explicit. `postSteps` lists host state 1, upload 2, upload retry 2, shutdown 2, telemetry 2 = 9 min of the 10-min allowance (`postSteps_fit`), and the `job` docstring says so. The golden `step` line carries `hardStopInside` only when `runs` is true.

### Report labels (item 2)

`report.mjs` labels the Timeline column of the cadence tables from the rows (`timeline: false` gives `off`, mixed rows `mixed`), not from `mode`; touch end windows now read `off`. The control job is left out of the sim pool and listed in the new block `sim-touch` (`touchTable`: coordinates, pushes, outcomes, begin, swipe, done, moves per job).

### Starved and lost windows (item 3): CONFIRMED why-not, counts per job

| Run, job | Windows | Over 90 s | Over 150 s | Over 300 s | Slowest | Timeline.stop timeouts | Evaluate timeouts |
|---|---|---|---|---|---|---|---|
| 39934951574, 1 | 36 | 2 | 2 | 1 | 398 s | 1 | 0 |
| 39934951574, 2 | 36 | 5 | 1 | 0 | 151 s | 0 | 0 |
| 39934951574, 3 | 36 | 3 | 2 | 1 | 329 s | 1 | 1 |
| 39995201296, 3 | 36 | 1 | 1 | 0 | 280 s | 0 | 0 |
| 40003317485, 1 (cap) | 20 | 0 | 0 | 0 | 41 s | 0 | 0 |
| 40003317485, 3 | 16 | 2 | 2 | 1 | 744 s | 0 | 0 |
| all | 180 | 13 (7.2 %) | 8 (4.4 %) | 3 (1.7 %) | | 2 | 1 |

- Slow windows occur in 5 of 6 jobs, 1 to 5 per job, in hero and end windows alike (4 hero, 9 end). The `Timeline.stop` timeout happened in 2 of 6 jobs, once each, and only in non-touch windows (touch windows start no Timeline).
- The 744 s hero window has no retry line in the log (no timeout, no attempt, two `inspector probe failed (tick): socket up, proxy down, page missing`): a single `readWindow` waited that long inside our harness, so the wait was, INFERRED, a chain of calls that each stayed under its own timeout (`FW_WK_TIMEOUT_SCALE` 8) on a host with load average 718; the window log has no phase times, so the phase is not read.
- Why no per-window bound (CONFIRMED by reading `sim-cadence.mjs`): a window shares one inspector socket with the retry. Abandoning a window leaves its pending calls on that socket and the only recovery is `reconnect`, the path that already ran in the 744 s window. A Lean bound on the window would only rename the wait. What is bounded is the sum: the walk deadline (`startsWindow`, `untilDeadline`, hard stop) and, with this task, the rep plan (45 s allowance, the 6 jobs above: 4 of 5 uncapped jobs fit 30 windows).

### CI dispatch 1 (run 40023506144, commit 90e7c09f6): MEASURED, the plan did not reach 5 kept windows

Four sim jobs on the same commit: jobs 1 to 3 SpringBoard coordinates, job 4 the control (`FW_TOUCH_VARIANTS=safari`). The Lean plan said `ok` in every job (5 or 6 reps of 3 arms). The count per arm (`base, aa, bound`) is the end windows with intervals (`ok` rows with `ivs`, what `jobCadence` counts per window group `end` or `end touch`); a touch window carries no Timeline zones, so `zoneReps` finish counts would read 0 for it and are not used.

| job | push server | windows | walk | job | end windows kept (base, aa, bound; touch of them) | why it stopped |
|---|---|---|---|---|---|---|
| 1 | not ready in 240 s | 4 | 1288 s | 31.3 min, green | 1, 1, 0 (0) | page target lost 484 s, relaunch found no tab |
| 2 | not ready in 240 s | 4 | 1110 s | 25.3 min, green | 1, 1, 0 (0) | `Runtime.evaluate` 120 s timeout, inspector dead, relaunch found no tab |
| 3 | not ready in 241 s | 16 | 1647 s | 37.4 min, red | 3, 2, 3 (0) | walk deadline; windows of 285, 432 and 125 s; red from `Shut down and delete the Simulator` (139 s against its 2 min bound) |
| 4 (control) | ready in 66 s | 29 | 1639 s | green | 4, 5, 5 (1, 2, 1) | walk deadline before `base end` of rep 4; windows of 196, 85, 75 s and a 400 s tab wait |

- The plan is a bound on time at 45 s a window; it cannot cover a host where the inspector dies after 4 windows (jobs 1, 2) or a rep takes 285 + 432 s (job 3). The mean window in job 4 was 28 s (819 s over 29), so a healthy job fits; the tail decides.
- Touch: in jobs 1 to 3 the driver started its tests after the 240 s `readyMs` cut (job 3 log: the driver printed `Running tests...` 37 s after xcodebuild started, after the cut), so no end window was a touch window (`touch 0`); in job 4 the driver was ready after 66 s, pushes 0 to 3 passed with the Safari coordinates and push 4 ended `pageLost`, then the driver was given up. Control against test is therefore confounded by driver start time, not by coordinates (INFERRED: nothing in `touch-push.mjs`, `TouchPush.lean` or the driver build changed since the earlier runs, where the push server was ready in 45 to 142 s on hosts with load 480 to 960; here 1000).
- Keep host state (item 6): in job 3 the injected `sleep 90` hit `timeout-minutes: 1`; the step took 78 s (60 s plus about 18 s to cancel), its conclusion was `success` under `continue-on-error`, and `host.txt` was never written. The job went red only through the Simulator shutdown step. Without the hang the step took 53 s (job 1) and 22 s (job 2) with both 8 s commands. For the 77 s of the earlier run (section Job-level bound, job 1, commands bounded at 15 s then), INFERRED: two commands bounded at 15 s explain at most 30 s; the remaining 47 s was unbounded work (uptime, sort, head, shell start) or runner step overhead under load 728; no per-command times were logged.

### CI dispatch 2 (run 40039631149, commit b81f1410d, same code plus `continue-on-error` on the shutdown step): MEASURED, 3 of 4 jobs reach 6 end windows per arm

| job | variant | push server | windows | walk | job | end touch windows kept (base, aa, bound) | note |
|---|---|---|---|---|---|---|---|
| 1 | springboard | ready 64 s | 11 | 1348 s | 27.1 min, green | 1, 2, 1 | `swipeLate` push, then `Timeline.stop` timeout (60 s) and a dead inspector: INCOMPLETE |
| 2 | springboard | ready 63 s | 36 | 1240 s | 24.5 min, green | 6, 6, 6 | 18 of 18 pushes ok; one 172 s hero window |
| 3 | springboard | ready 51 s | 36 | 1462 s | 29.3 min, green | 6, 6, 6 | 18 of 18 pushes ok; one 383 s and one 172 s hero window |
| 4 (control) | safari | ready 50 s | 36 | 1088 s | 22.0 min, green | 6, 6, 6 | 18 of 18 pushes ok; one 152 s end window |

- The run concluded `success`. The Lean plan (6 reps of 3 arms, `outcome` ok) is met in jobs 2, 3 and 4 inside the bound: walks of 1240, 1462 and 1088 s against a walk budget of 1644 s (job 2: `step_minutes=31`, hard stop 1794 s), job minutes 24.5 to 29.3 against the 45 min timeout. Job 1 is the host-starved tail (item 3): 1 `swipeLate` and 1 `Timeline.stop` timeout in 11 windows, then the inspector would not come back.
- Dispatch 1 against 2 (same code except the shutdown step and merged main): the push server was ready in 50 to 66 s in 5 of 5 jobs of dispatch 2 and dispatch 1 job 4, but not within 240 s in dispatch 1 jobs 1 to 3 (load 886 to 1016). That is the host, not the plan (INFERRED).
- Control against test (item 1), pushes that passed: SpringBoard 40 of 41 (median begin 2.1 s, swipe 5.8 s, done 9.9 s, max done 59 s) and Safari 22 of 23 across both dispatches (the miss: `pageLost` in dispatch 1 job 4) (median begin 1.5 s, swipe 6.4 s, done 9.8 s, dispatch 2: max done 35.7 s). The one failed SpringBoard push was `swipeLate` (swipe 24 s against a 20 s bound). The two coordinate sources give the same median done time (9.9 against 9.8 s); the sample is too small to rank them (MEASURED, n = 18 per variant in dispatch 2).
- Steps (item 6): the shutdown step ended in 9, 19, 23 s and the Keep host state step in 11, 15, 23 s in a healthy job; the job stayed green in all four jobs. In dispatch 1 job 3 the injected hang cost 78 s and left `success`.

## Verdict jobs (sim-touch-verdict-jobs): a job plan, premises checked 2026-11-02

Lean `Fw.Measure.WalkBudget` (golden `packages/contracts/golden/measure/walk-budget.jsonl`), TS `packages/measure-webkit/src/walk-budget.mjs`, `profile/sim-cadence.mjs` `planSim`, `profile/report.mjs` `jobsTable`, `smoothness.yml` `webkit-sim`.

**Plan.**
- `jobsNeeded = minSamples + margin = 3 + 2 = 5` (`jobsNeeded_le_slots`: 5 <= `macSlots` 5, so all jobs of a run start at once; the matrix has `max-parallel: 5`). `plan_across`: with at least 5 job verdicts of which at most 2 are insufficient, `acrossDecisive` is not insufficient. `job_decisive`: a job whose four lists (base, bound, aa1, aa2) hold the minimum of kept end windows never judges insufficient; `planReps_complete`: an `ok` plan finishes at least `minKept` = 5 end windows per arm.
- The window budget is a tail quantile of 216 measured windows (`windowSecs`): body 29 s (75th percentile) per window plus one 398 s slot (99th percentile) per 20 windows, `blockMs`; `blockMs_over_mean` proves it is above the mean (37.5 s) budget. `plan_inside_job`: a plan started at or before the deadline ends its windows, grace, post steps and slack inside the job (60 min after dispatch 1, 45 min before).
- The job slack is 8 min: clock 6 s, drift 50 s, complete 4 s and 7 min for a walk step that ran 380 s past its step timeout (`overrun_covers_seen`, `job_ends_inside_gaps`). Post steps 9 min, grace 2 min, so the walk deadline is job start + 40 min of a 60 min job (dispatch 1 ran with 45 min and 25 min).
- The clock: `planSim` runs after the Simulator is booted, the touch driver answers and Safari is reconnected (`sim-cadence.mjs`), not at the first device lookup. With the driver the shape is `endOnly` (the end touch window is the decision window; 1 window per arm and rep), else `full`.
- Arms: 3 and 4 arms plan 6 reps (`repsWant`) from a walk that starts within 15 min (`setupWorstMs`, theorem `ok_at_worst_setup`) and 5 reps up to 26.6 min (3 arms) or 24.2 min (4 arms); 5 arms are ok too, 8 or more are `lifeShort` and `groupsFor` / `groupArms_cover` give the number of jobs of arms that would fit (`repPlan.groups`, shown by `jobsTable`). The matrix itself does not split arms: all 5 jobs run all arms because the across-jobs rule needs 3 decisive jobs per pair.
- Zone source: touch end windows start no Timeline (`report.mjs` labels them `off`), so they carry no zone reps; their verdict is the hitch verdict over the page's own frame intervals (`ivs`), which is what `job_decisive` covers. The finish zone has 0 Timeline reps by design in touch windows.

**Premises of the 2026-10-24 row, checked against main d530bc4f4.**

| premise | status | evidence |
|---|---|---|
| `acrossDecisive` needs 3 decisive jobs, so one starved job of 3 removes the verdict | holds | `lean/Fw/Gate/Smooth.lean:666,736`, `packages/gate-breakpoints/src/smooth/reduce.mjs:144` |
| touch end windows carry no Timeline | holds | `report.mjs:19` (rows with `timeline === false` are skipped for zones), `report.mjs:265` |
| the push server `readyMs` is 240 s and the driver can start after it at host load | holds | `touch-push.mjs:9`; runs 40023506144 jobs 1 to 3 (driver started after the cut) |
| the plan clock was read before boot and driver start | fixed here | `sim-cadence.mjs` `planSim` is called inside the session after `startServer` and `reconnect` |
| the window mean (45 s) is the budget | replaced | tail quantile above; 216 windows in runs 40023506144, 41270567124, 41275699141, 41285184069, 41289882234 |
| touch lanes now have 4 arms | partly | only the `[touch-lock]` lane (`touchlock-run.mjs`, original, faithful, CSS lock, pin; matrix `[1,2]`) has 4 arms; the `[earn-bound]` verdict lane has 3 (base, aa, bound). The touch-lock lane runs a fixed 6 reps with the walk deadline as the only cut and no `planReps`: follow-up (`touchlock-run.mjs` is not in this row's writes) |
| jobs ran 55 to 94 min | partly false | the jobs API `completedAt` of 41285184069 job 2 is 09:24 but its last step ended 08:24:42 (a 34 min job); 41270567124 job 1 ran 55 min, the one real overrun (cancelled; its walk step ran past its step timeout, now the 7 min `overrunMs`) |
| one job cut at the time limit while uploading | holds | 41275699141 job 1: `swipeLate`, then the upload step failed (job 26 min, the upload timed out at 2 min); the plan cannot prevent a stall, the margin of 2 jobs absorbs it |
| one job failed with 0 windows after `simctl openurl` timed out | holds | 41285184069 job 1 (17 min, no ready file after 285 s); a harness fault, absorbed by the margin, not retried |

**CI dispatch 1 (run 41345594217, commit 6b9a16a34, tags `[ci:smoothness] [webkit-cadence] [earn-bound] [sim-only]`, 45 min jobs, 25 min walk deadline): MEASURED, jobs started 5 of 5 at once, jobs with a result file 5, decisive 0, across-jobs end touch verdict `insufficient`.**

| job | job min | plan (shape, outcome, reps) | end touch windows kept per arm (fewest) | what stopped it |
|---|---|---|---|---|
| 1 | 30.0 | endOnly budgetShort 4 | 2 | windows of 308, 120 and 90 s; walk deadline |
| 2 | 21.6 | full budgetShort 0 | 0 | push server: no ready file after 242 s, touch off |
| 3 | 24.8 | full budgetShort 1 | 0 | push server: no ready file after 240 s, touch off |
| 4 | 31.8 | endOnly ok 6 | 2 | Node crash `setTypeOfService EINVAL` (undici socket write) after 7 windows |
| 5 | 22.2 | endOnly budgetShort 4 | 4 | plan 4 reps (12 windows), done |

- Time: all five jobs ended inside the 45 min limit (longest 31.8 min), none cut by it. The across-jobs verdict (`report` over the five artifacts, `sim-jobs` block): base, bound: 5 planned, 4 with a file (job 2 empty), 0 decisive, `insufficient`.
- Why short (MEASURED from `sim.log` and step times): the setup before the plan took 11 to 13 min under host load (job steps 4.9 min, then 6 to 8 min in the harness: tab wait 40 to 60 s, push server ready after 107 s, plus slow page loads); the plan clock was read correctly, but the 25 min deadline left 11 to 13 min, which `blockMs` (717 s for 4 reps) turns into `budgetShort`. Two jobs lost the driver within 240 s (xcodebuild had not started the tests: log tail `Command line invocation:`), one job lost its process to the undici socket fault. The margin of 2 absorbed none of this: 3 jobs lost and 2 short.
- Window times in this run (job 5: 13, 123, 5, 101, 2, 27, ... s; job 1: 2, 41, 18, 64, 4, 308 s) are above the 216-window sample: it is a heavier host, not a bug of the plan.

**Round 2 (dispatch 2), changes from this run.**
- Job timeout 60 min, so the walk deadline is job start + 40 min (`job` in Lean; `smoothness.yml` `webkit-sim` `timeout-minutes: 60`, checked by `walk-budget.test.mjs`). Free runners, no paid minutes.
- `readyAllowMs` 480 s for the driver (`startServer` `readyMs` in `sim-cadence.mjs`; the per-push `TOUCH_BUDGET.readyMs` in `touch-push.mjs` is unchanged) and `setupWorstMs` 15 min: `ok_at_worst_setup` proves a plan clocked 15 min after the job start is still `ok` for 3 and 4 arms.
- `repsWant` 6: a healthy job ends after 6 reps instead of walking to the Simulator's 36-window life.
- `guardSocketFault`: only the `setTypeOfService EINVAL` socket fault is logged and survived; any other uncaught error still ends the process (TS stand-in, unit test `profile-sim-fault.test.mjs`).

**CI dispatch 2 (run 41349666358, commit 33937b435, same tags, 60 min jobs, 40 min walk deadline): MEASURED, jobs started 5 of 5 at once, jobs with a result file 5, decisive 2, across-jobs end touch verdict `insufficient` (3 decisive needed). No job was cut by the 60 min limit (jobs API times 18.3, 33.9, 37.1, 38.3 and 43.5 min; the API times are approximate).**

| job | plan (shape, outcome, reps) | end touch windows kept per arm (fewest) | verdict | what stopped it |
|---|---|---|---|---|
| 1 | endOnly ok 6 | 6 | same | done, 735 s walk |
| 2 | endOnly ok 6 | 5 | same | done (a `Runtime.evaluate` retry cost one 120 s wait) |
| 3 | endOnly ok 6 | 0 | insufficient | pageLost on an aa push, then 304 s and 574 s windows; walk deadline before base end rep 3; 3 of 9 windows refused (drift) |
| 4 | endOnly ok 6 | 1 | insufficient | `Runtime.evaluate` timed out after 120 s (twice), pageLost on a push, `Timeline.stop` timed out after 60 s; stopped after 5 windows |
| 5 | full budgetShort 3 | 0 | insufficient | push server: no ready file after 480 s, so no touch pushes; the plan then read the clock late and ran 3 untouched full reps |

- Result: the premise "one CI run whose across-jobs end touch verdict is not insufficient" is not met in either dispatch (0 of 5 then 2 of 5 decisive jobs). Dispatch 2 is one job short of the verdict. The plan itself held: all three jobs with a plan `ok` and a working driver (1, 2, and 3 up to its faults) ran inside the deadline, and no job hit the time limit.
- Cause of the 3 lost jobs (MEASURED from `sim.log`): a driver that never became ready in 480 s (1 job), page loss and 120 s `Runtime.evaluate` hangs on a loaded host (2 jobs; 6 of 9 windows in job 3 and 3 of 5 in job 4 went through retries or drift refusals). The margin of 2 absorbed two of the three; with 3 faulty jobs in 5 the verdict is `insufficient`. The fault rates seen (dispatch 2: 3 of 5 jobs, dispatch 1: 5 of 5 jobs short) are above the 2 of 5 that a margin of 2 inside 5 macOS slots covers.
- Finding (negative result): 5 concurrent macOS jobs at margin 2 do not give a verdict per run at the harness fault rate seen on 10 jobs. The next design is not more windows per job (the faults, not the budget, ended the jobs) but a second wave: a matrix of 10 jobs with `max-parallel: 5`, each job with its own 40 min deadline, so 3 decisive jobs need about 10 jobs at a 30 to 40 percent decisive rate. That doubles the macOS minutes (free runners only) and is a follow-up (`Fw.Measure.WalkBudget.jobsNeeded` would take a fault-rate input).
- Premise "the touch driver is ready within 480 s": false for 1 job in 5 of dispatch 2 (and 2 in 5 of dispatch 1 at 240 s); the driver start is a `xcodebuild test-without-building` that sometimes logs nothing for 8 min. Follow-up: a job without a driver should end early instead of running untouched full reps (job 5 spent 28 min on windows that carry no touch).
- Time cap: the Lean cap table (`Fw.Ci.Pool.Caps`) derives `timeout-minutes` from a p90; the `webkit-sim` row is now the plan's own bound `simWallDm` (cap 60 = `WalkBudget.job.timeoutMs`, status INFERRED); the measured jobs (linear p90 38.9 min) lie below it. Files outside this row's writes: `lean/Fw/Ci/Pool/Caps.lean`, `packages/contracts/golden/ci/pool-caps.jsonl`, `scripts/ci-paths.test.mjs`.

## Fault margin (sim-touch-fault-margin): a 10-job two-wave matrix, 2026-11-02

Lean `Fw.Measure.WalkBudget` (golden `walk-budget.jsonl`), `Fw.Ci.Pool.Caps` (golden `pool-caps.jsonl`); TS `walk-budget.mjs`, `profile/sim-cadence.mjs`, `profile/report.mjs`, `touchlock-run.mjs`; `smoothness.yml`.

**CI dispatch 1 (run 41357917479, commit 8cf84b94b, tags `[ci:smoothness] [webkit-cadence] [earn-bound] [sim-only]`): MEASURED, jobs started 10 of 10, jobs with a result file 8, decisive 3 (jobs 1, 2, 9, all `same`), across-jobs end touch verdict (base, bound) `same`, not insufficient.** Jobs 7 and 10 wrote a `sim.json` with 0 windows (reported as `empty`).

| job | end touch windows kept per arm (fewest) | fault | what stopped it |
|---|---|---|---|
| 1, 2, 9 | 6, 6, 6 | none | done (walks 874, 983, 679 s) |
| 3 | 1 | touch driver | `swipeLate` |
| 4 | 4 | touch driver | `pageLost` on a push |
| 5 | 4 | hang | inspector dead, `simctl shutdown` failed (walk 2069 s) |
| 6 | 4 | touch driver | `swipeLate` |
| 7, 10 | 0 | touch driver | push server: no ready file after 480 s; early end at 644 s and 761 s |
| 8 | 1 | touch driver | the driver finished late |

- Waves (MEASURED, jobs API): jobs 1 to 5 started at once, jobs 6 to 10 as slots freed (at minutes 20, 24, 26, 32, 38); the run took 63 min and 239 job minutes, against the Lean bound of 2 waves x 60 min = 120 min (`sim_only_wall`). No job hit the 60 min limit.
- Dominant fault (MEASURED, `faults:` line of `jobsTable`): touch driver not ready or lost 6 of 10 jobs, hang 1, none 3. Over the 20 jobs of the three runs: driver 9, hang 3, budget 2, crash 1, none 5 (`driver_count`, `driver_others`, `dominant_driver`).
- Early end (item 3): jobs 7 and 10 ended after 644 and 761 s of walk with the named fault `touch-driver-not-ready`; dispatch 2 job 5 had spent 28 min on untouched full reps. `driverFault`/`driverFault_*` prove the rule (a walk with the driver asked for and not on has no untouched windows after it); `sim-cadence.mjs` and `touchlock-run.mjs` check it before planning and before each window.

**What Lean now says.**
- Reach (`reach_at_plan`, `reach_least`): at the plan rate, run 2's 2 of 5 decisive jobs, 10 jobs give at least 3 decisive ones with chance 8327 in 10000, and 9 do not reach 4 in 5, so `jobsNeeded = 10`. The rate rests on run 2 alone: the 60 min job, the 480 s driver wait and the socket guard fix the faults `budget` and `crash` of run 1. At runs 1 and 2 pooled (2 of 10) the same 10 jobs reach with chance 3222 (`reach_at_pooled`; 21 jobs would be needed, `pooled_jobs`).
- Run 3 reached the minimum with none to spare: 3 decisive of 3 needed (`run3_reached`), an event of chance about 70 percent at the new rate. At runs 2 and 3 (5 of 15, `late_rate`) 10 jobs reach with chance 7008 in 10000 (`reach_at_late`) and 12 jobs would be needed for 4 in 5 (`late_jobs`). Status: the next matrix sizes from `lateRate`; this task keeps `jobsNeeded = 10` because the 10 jobs of runs 1 and 2 are its stated source.
- "Start at once" is false for 10 jobs in every leg combination (`never_at_once`: 10 sim jobs exceed the 5 macOS slots; with webkit-mac the peak is 5 + 1 = 6, `mac_leg_peak`). It is replaced by a wave statement: sim-only 10 jobs are 2 waves, 120 min bound; with webkit-mac 13 jobs and 3 waves; with the `[sim-touch-control]` job 11 jobs and 3 waves (`sim_only_waves`, `mac_leg_waves`, `control_waves`). The tagged run used `[sim-only]`.

**Window sample (item 4).** The 102 windows kept in run 41357917479 (`window kept in N ms` lines of `sim.log`) are added to the 216: 318 windows. Body (75th percentile) 38 s (was 29), tail (99th percentile) 383 s (was 398), mean 39.6 s (was 37.5). `tailEvery` is now derived: windows per window of at least 100 s, 318 / 18 = 17 (was a fixed 20; `tailEvery_value`). The new run is a heavier host than the old sample (body 48 s over its 102 windows). Effect on the plan (golden `plan` rows): 3 arms plan 6 reps from a walk that starts within 17.1 min (was 25.2 min), 5 reps up to 24.75 min (was 26.6); 4 arms plan 6 reps up to 13.3 min and 5 reps up to 15.83 min (was 24.2); 5 arms from a 15 min start are `budgetShort`. This supersedes the "Arms" line of the verdict-jobs section above. The refreshed plan was not run on CI (dispatch 1 ran the previous 29 s / 398 s / 20 constants); it is a re-derivation from measured windows, with the golden and TS checked against Lean.

**Pool caps (item 5).** The `smoothness-webkit-sim` row is marked derived: `p90dm` is the plan's bound (461 dm, cap 60 min = job timeout), not a p90, so the golden row carries `basis:"bound"`, `boundDm` and the measured sample apart: `measuredN` 17 successful jobs (runs 41345594217, 41349666358, 41357917479; walls from the jobs API), `measuredP90dm` 392 (39.2 min), `measuredThin` false. `sim_walls_under_bound` proves the measured p90 is below the bound. A 1.3 x p90 cap would be 51 min; the 60 min timeout stays because the walk deadline (40 min) plus post steps and slack are Lean-derived from it.

**Touch-lock lane (item 6).** `planLock` gives the 4-arm lane (original, faithful, CSS lock, pin) a `planReps` plan (`endOnly`, 4 arms, `repsWant` 6 at most), `repPlan` in its snapshot and `--reps auto` by default; `--reps N` still sets by hand. It was not run on CI here (lane `[touch-lock]` was not tagged).

**Accepted limits.** Free GitHub macOS runners, 5 slots; the Simulator is not the phone; faults are counted, not retried; one dispatch used of two. Follow-ups: size the next matrix at 12 jobs from `lateRate` (3 waves of at most 5, about 12 x 24 job minutes); the cause of the driver start failures (6 of 10 jobs): `xcodebuild test-without-building` shows no ready file after 480 s in 2 jobs and `swipeLate` or a late finish in 3, which points at host load during the driver start, not at the plan.

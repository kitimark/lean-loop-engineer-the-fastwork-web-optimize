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

- **The slow step is XCUITest's wait for Safari to be idle, not the swipe (CONFIRMED position, INFERRED reason).** The driver
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
  0.5 s drag, 1 s hold), post-event wait 0.03 s. Earlier note `10-2x-toolbar-throttle.md:91-102` already saw 60 to 185 s per
  pass on the runner against about 50 s on a Mac. So the swipe itself is cheap; only the idle waits stretch under load.
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
  hit the 50-minute step limit. The wait only moved the cost into the job time.
- **The Timeline of a touch window is not needed.** Frame counts and intervals come from page timestamps (`rec.ts`); the
  Timeline only gave per-zone render work. A touch end window now records no Timeline (Lean `timelinePlan`), so no stop
  can time out there.

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
- `timelinePlan_touch` / `timelinePlan_other`: touch window records none, any other window stops its Timeline within the stated wait.

Honest limit: the bound says the harness stops waiting; it does not make XCUITest finish a push when the runner is starved. One
failing push per job is the worst case, after which the job continues with the synthetic wheel (as before, but within 3 minutes, not
within the step limit).

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
  post-event wait that stuck in the CI log, not every Safari wait (INFERRED benefit; the CI run decides). `FW_TOUCH_VARIANTS=safari,springboard`
  alternates by push index; `FW_TOUCH_KEEP_LOG=<file>` keeps the XCUITest log.
- `sim-cadence.mjs`: touch end windows start no Timeline, rows keep `mode:'events'` with `records:0`, `timeline:false`,
  `ok:false` (`marks-missing`, as the reducer sees an empty record list), `push:'touch'`, and `touched` carries variant, outcome,
  observation and press times. A failing or late push turns the lane off, stops the driver and falls back to the synthetic wheel.

## TS stand-ins (not proved)

`classifyWindow`, `doneInTime`, `laneAfter`, `spent`, `windowCap`, `timelinePlan` in `touch-push.mjs` are replayed against the Lean golden in
`test/touch-push.test.mjs`. `touchWindow`, `touchCountJs`, `PushServer.swift` and the `sim-cadence.mjs` wiring are glue and not golden-checked.

## Open

- CI proof of the bounded push is a dispatch item for the lead (handoff). Phone not measured.
- `report.mjs` labels the Timeline column from `mode`, so touch rows read "on"; a `timeline:false` label is a follow-up (outside this task's writes).
- Simulator hero windows are starved on the runner (2 to 40 frames in 7 s, runs above); not touched here.
- Negative result worth keeping: lengthening the stop wait (60 s to 240 s) made the job slower and kept fewer windows.

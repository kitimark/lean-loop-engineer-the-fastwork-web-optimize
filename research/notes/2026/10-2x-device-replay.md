---
id: 2026-10-22-device-replay
kind: note
title: "Device replay: send a recorded finger path back into the page, and check that the page saw the same path"
status: draft
created: 2026-10-22
topics: [device, replay, safaridriver, webkit, chromium]
---

# Device replay

Goal: the felt lag lives on the phone, and a person is too noisy to compare two pages with. A replay sends the same finger path to
both pages. Status words: CONFIRMED (source or
measurement cited), INFERRED, UNKNOWN (to measure), MEASURED.

## Method

1. **Profile (Lean `Fw.Device.Replay`).** A recorded pass becomes a list of swipes, each a list of samples `[t, x, y]` (time in
   hundredths of a ms, positions in tenth px) plus a start time and a lift time. A recording with a second finger gives no profile (the replay
   path has one finger).
2. **Compile (Lean `compile`, TS twin `device-replay.mjs`).** The swipes become W3C Actions for one touch pointer: down, moves, up.
   Theorem `compile_dur_le`: every tick is 0 to 16 ms. Theorem `compile_targets`: every move lands on a sample position rounded to
   a whole px (`px_err`: the rounding error is at most half a px).
3. **Why 16 ms and whole px.** CONFIRMED (WebKit@862f17d: `SimulatedInputDispatcher.cpp:331-341` TouchDown/LiftUp/MoveTo only on a
   changed location, `:201` tick timer; `_WKTouchEventGenerator.mm:46,330-343`: a move of at most 16 ms is one event, sent at the start
   of the tick; locations are IntPoint): pointer down
   sends TouchDown, up sends LiftUp; a move sends an event only if the location changed (the tick time still passes) and a move with
   duration up to 16 ms is one event; the locations are whole CSS px.
4. **Send.** Phone: safaridriver (W3C `/actions`, `pointerType touch`) to Safari on the iPhone, driver in
   `device-replay-wd.mjs`. CI: Chromium CDP `Input.dispatchTouchEvent` at wall-clock times (`src/replay/`), native
   `requestAnimationFrame`, CPU throttled 6x, never seeking.
5. **Record.** The page records with the phone recorder (`RECORD_JS`): every touch event the page saw and every frame.
6. **Check (Lean `replayMatches`).** Per swipe, five conjuncts, each with a theorem: `eventsOk` (the page saw the events the compiled
   swipe makes, same count), `posOk` (each event within `pos` of the expected, per axis), `timeOk` (each event within `time` of the
   expected, relative to the swipe's first event), `speedOk` (lift velocity over the last `window` within `speedPct` percent),
   `startOk` (swipe start within `startGap` of the expected, relative to the pass's first swipe). Limits are parameters; the defaults
   (pos 10 = 1 px, time 1700 = 17 ms, speedPct 10, startGap 5000 = 50 ms, window 5000 = 50 ms; position in tenth px, time in
   hundredths of a ms) are research starting points, not calibrated (follow-up).
   The golden has one case per failing conjunct.
7. **Worst-case profiles (Lean functions).** `fastFling` (n copies of the fastest down fling, fixed gap), `zoneLoop` (the swipe
   segment that crosses the hero or the finish zone, played down then mirrored up, repeated), `cold` (the recorded path on a first
   load). The recorded profile is the median pass. Arm order rotates per repeat (`rotation`: every arm leads once in n repeats); `schedule`
   lists kind x repeat. Golden `packages/contracts/golden/device/replay.jsonl` (24 lines), checked by the TS twin.

## The seven fixes from the check of the first plan

| # | Fix | Status |
| --- | --- | --- |
| 1 | Momentum after the lift is INFERRED, not CONFIRMED: the touch is an in-process HID event, so iOS may apply its own momentum; the check compares what the page saw, not what iOS should do | INFERRED |
| 2 | Per-tick timing jitter of safaridriver is unknown, not "sub-ms"; the check has a time limit and the CLI prints the lateness | UNKNOWN, measure in the pilot |
| 3 | The free-profile expiry claim cited the wrong source; cite Apple's free-provisioning limits; trusting the profile needs internet | INFERRED (docs) |
| 4 | The WDA mitigation does not work: `FBW3CActionsSynthesizer.m:963,974` queries interfaceOrientation, WDA waits for quiescence and uses runner CPU. Path A (WDA) is a known risk, not built | CONFIRMED (source), effect UNKNOWN |
| 5 | "A user tap ends the session" was overstated: the Safari blog says a tap lets the person choose to end it; the single-finger limit dates from 2019 and is INFERRED to hold on iOS 27 | INFERRED |
| 6 | Compatibility risk added: WDA's private XCTest use against Xcode 27.1, safaridriver against iOS 27.0.1 | UNKNOWN |
| 7 | "HEVC" dropped: the source says only "screen-mirror video" | CONFIRMED |

## What this run adds

- Lean, TS twin and driver on synthetic fixtures: MEASURED (tests pass; the Lean check and the twin agree on the golden). See the
  handoff for run ids.
- Chromium lane on GitHub CI, one profile run (the committed `user-fixture` profile, three kinds, repeats): the result is the replay
  check per swipe and recorder frame counts, not class counts.
- MEASURED, run 39646030536 (ubuntu-24.04-arm, one run, 3 kinds x 2 repeats, 5 swipes each): every dispatch left within 5 ms of its
  time (p95 at most 1.1 ms), all 5 swipes were seen in every pass, but the page saw 105 to 113 of the 300 to 307 touch events
  sent, so `eventsOk` and `replayMatches` are false in all 6 passes. Cause INFERRED: renderer-side coalescing of continuous touchmove
  (main-thread event queue, rAF-aligned input) under 6x throttle; not yet cited from Chromium source and not separated from coalescing
  at 1x. So Chromium cannot stand in for the phone's event stream; it can still load the page with the finger path. Frames
  above 34 ms: 82 to 93 of 111 to 117 moving frames.
- The phone pilot did not run (needs the user step and a booked session): UNKNOWN.

## iOS: how automation sends touches, and why the first pilot saw none (task replay-ios-fix)

Source reading, WebKit@862f17d, paths under `Source/WebKit/UIProcess/` (CONFIRMED):

- `Automation/WebAutomationSession.cpp:2421-2436` `simulateTouchInteraction` (iOS): the whole call fails with TargetOutOfBounds unless the
  point lies inside `FloatRect({}, page.unobscuredContentRect().size())`, so one move with y below 0 or at or past `innerHeight` rejects
  its `/actions` call. It sets `m_simulatingTouchInteraction` (l.2431) and clears it in the completion (l.2433).
- `Automation/ios/WebAutomationSessionIOS.mm:~190-225` `platformSimulateTouchInteraction`: the viewport point is converted to a screen
  point (`syncRootViewToScreen`), then `_WKTouchEventGenerator` does touchDown, moveToPoint and liftUp, the move with
  `duration.value_or(0)`. Mouse and touch have no `sendSynthesizedEventsToPage` path on iOS (only keyboard): touch exists only as HID events.
- `Automation/WebAutomationSession.cpp:~2696-2830` `performInteractionSequence`: on iOS a mouse or pen source is aliased to touch when only
  touch interactions are enabled; `pointerType` is otherwise unused for touch, so `pointerType: touch` changes nothing.
- `Automation/SimulatedInputDispatcher.cpp:~280-345`: TouchDown when the button goes from released to pressed, LiftUp on the reverse,
  MoveTo only when the location differs, duration `a.duration.value_or(0)`; one tick timer per keyframe of its longest duration (l.~185-200).
- `API/Cocoa/_WKTouchEventGenerator.mm`: HID digitizer events in whole px (`roundf`), a 16 ms move interval; `moveToPoints` l.318-346
  interpolates on a sine curve and sleeps with `nanosleep` on the main thread (l.92); events are enqueued via
  `RunLoop::mainSingleton().dispatch` into `[UIApplication _enqueueHIDEvent:]` (l.204-245); `liftUpAtPoints` l.294-310; completion is a
  vendor-defined marker event resolved in `receivedHIDEvent` l.383-393.

So a W3C touch action on iOS is a real HID touch that WebKit's gesture recognisers see, not a synthesized DOM event. The consequences
below replace the earlier INFERRED "the scroll recogniser takes over" reading, which the data contradicted (swipe 1 was a scrolling swipe
and the recorder saw its end).

MEASURED on an iOS 26.5 Simulator (iPhone 17e, headless, page 390 x 699 CSS px, dpr 3; own probes with a tall test page, local, not a
class count):

| gesture sent | what the page saw |
| --- | --- |
| tap (down, 50 ms, up) | pointerdown, touchstart, pointerup, touchend; session responsive |
| 3 px move under the touch slop, 100 ms, up | touchstart, 2 pointermove, touchmove, pointerup, touchend; responsive |
| 15 px over 100 ms; 5 x 16 ms moves; 5 x 100 ms moves | pointerdown, touchstart, first pointermove, then pointercancel and a few touchmove, scroll moves; no touchend or pointerup ever; 7 to 17 events |


After a scrolling swipe the session was wedged in the round-1 probes: `DELETE /actions`, `execute/sync` and `DELETE /session` timed out
(15, 30, 20 s); `safaridriver --diagnose` shows `Automation.performInteractionSequence` answered and `Automation.resolveBrowsingContext`
never answered, although that command is synchronous in the UI process (`WebAutomationSession.cpp:579-590`); MobileSafari's main thread
sampled idle and page JS kept running. This matches the lead's phone pilot (0 of 34 swipes seen, then a hang) but does not prove the
phone's cause: the pilot also had the Safari first-run tip. The tip did not reproduce on the Simulator (screenshots show the Start Page
and the page, even with the TipKit store moved away), so `HideAllTips` is INFERRED to suppress it, not verified. The phone hang has two
INFERRED candidates, the tip and the wedge; neither is confirmed.

Round-2 probes (MEASURED, local debug runs, iOS 26.5 Simulator, page 390 x 699 CSS px, a logger page posting every event to a local
server; scratch, not committed). `P` = what the page saw per 400 px swipe over 1.3 s unless noted:

| probe | page | result |
| --- | --- | --- |
| B | `touch-action:none`, 16 ms ticks | 5/5 swipes: touchstart, 78 touchmove (spacing median 17 ms, max 36), touchend; scrollY 0; call 1.42-1.45 s |
| A | root scrolls natively | swipe 1 runs away (scrollY 18843); touchmove clientY = planned y minus scrollY for all 78 events (residual 0 against B); pointercancel, no touchend; session wedged |
| long | one 1.3 s move, `touch-action:none` | 1 touchmove, 2 pointermove instead of ~78; call 2.63 s (burst, INFERRED from `_WKTouchEventGenerator.mm:92`, `:204-222`) |
| long | one 1.3 s move, root scrolls | scrollY 390 (no runaway), still pointercancel, no touchend, wedge |
| E1 | 60 px over 600 ms, root scrolls | scrollY 814, wedge: a short swipe does not avoid it |
| C1-C3 | inner fixed scroller, root offset 0 (ease, linear, with rAF loop) | scroll 385-390, 78-81 touchmove, pointercancel, no touchend, wedge |
| inject | listeners injected through WebDriver | no touch events reach the page, still wedges |
| S1 | snapshot site, logger injected | swipe 1: runaway (~5000), pointercancel, touchend 270 ms after the last touchmove, no wedge; swipes 2-3 get no touch events at all (the site cancels `touchmove` in a scroll-interception mode) |
| P1 | root page, page cancels `touchmove` and scrolls with script | swipe 1: touchstart, 77 touchmove, touchend, no wedge; scrollY drifts to 16203; swipes 2-3 get nothing (finger lands at y minus 16203) |
| P2 | as P1, `scrollTo(0)` between pieces | 5/5 swipes with touchend |
| P3 | inner scroller plus `preventDefault`, no native scroll | 5/5 swipes, 78 touchmove each, touchend; positions equal B (max |dy| 0 over 5 x 78) |

Two named reasons `replayMatches` cannot be true on a page that scrolls natively under the touch (the real site is one):

1. Drift (CONFIRMED by source, MEASURED). `WebAutomationSessionIOS.mm:205` computes `locationOnScreen = page.syncRootViewToScreen(...)`
   per touch action; `PageClientImplIOS.mm:548-551` converts with `[contentView() convertRect:rect toView:nil]`, and `WKContentView` is
   a subview of the scroll view, so the screen point is the viewport point minus the scroll offset. The page-reported `clientY` equals
   planned y minus scrollY exactly (probe A, residual 0). Inside a swipe this feeds back (the page scrolls, the finger moves with it);
   across swipes the finger lands off-screen. It cannot be compensated: `WebAutomationSession.cpp:2424-2425` bounds-checks the viewport
   point against `unobscuredContentRect().size()`, so a point offset by scrollY is refused or off-screen. P2 and P3 remove the drift and
   recover 5/5.
2. Lost `touchend` and wedge after a native scroll take-over (MEASURED in A, long, E1, C1-C3, S1; absent in B, P1-P3 where the page
   prevents native scroll). `pointercancel` comes from `WKContentViewInteraction.mm:2190` `cancelPointersForGestureRecognizer`;
   `WKTouchEventsGestureRecognizer.mm` (~l.551-560) handles `touchesEnded`/`Cancelled`. No source read explains why the end never
   arrives or why the automation session then stops answering. Mechanism UNKNOWN; it is independent of the drift (C1-C3), of an idle
   page (rAF loop), of the lift velocity, and of the injected listeners.

The leads from round 1 are cleared by B: `nanosleep` on the main thread (`_WKTouchEventGenerator.mm:85-93`) with 16 ms ticks does not
burst (spacing median 17 ms), `liftUpAtPoints` clamping (`:294-310`) is not hit (5/5 touchend), and the HID timestamps are
`mach_absolute_time()` at creation. A single long move does burst (`long` row), which is why the driver sends 16 ms ticks.

Unit check: Lean stores time in hundredths of a ms and position in tenth px; `Lim` is pos 10 (1 px), time 1700 (17 ms), speedPct 10,
startGap 5000 (50 ms), window 5000 (50 ms) (`lean/Fw/Device/Replay.lean`).

MEASURED, replay-ios-fix harness, iOS 26.5 Simulator, local debug runs in the sim slot (harness checks, not results of record).
Committed fixture `user-fixture` (5 swipes) scaled into the page, kind `recorded`, one `/actions` call per swipe (pieces).

Runs 1 and 2, the snapshot site (scrolls natively):

| run | arm | replayMatches | swipes seen of 5 | stalled | frames over 34 ms | dispatch lag per piece (ms) |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | original | false | 1 | no | 11 of 12 | not recorded |
| 1 | rewrite | false | 1 | no | 13 of 98 | not recorded |
| 2 | original | false | 1 | no | 35 of 116 | 260, 253, 202, 403, 240 |
| 2 | rewrite | false | 1 | no | 12 of 63 | 275, 248, 175, 186, 161 |

Runs 3 and 4, a local test server (stand-ins for a replay-capable page and a natively scrolling page), 1 arm:

| run | page | replayMatches | swipes seen of 5 | stalled | notes |
| --- | --- | --- | --- | --- | --- |
| 3 (3 passes) | `/ok`: root offset 0, page cancels `touchmove` | false in all 3 | 5 of 5 in each | no | piece lag 150-237 ms; per swipe `eventsOk` and `posOk` true, `timeOk` and `speedOk` false, `startOk` true for swipe 1 and false for swipes 2-5 |
| 4 (1 pass) | `/root`: tall page, native root scroll | false | unknown | yes, `replay-stall` at piece 1 of 5 | `DELETE /session/_/actions did not answer within 15000 ms`, then `quit` timed out at 20 s; 48 s total; no safaridriver left |

On `/ok` the positions and counts match; `replayMatches` is false from timing only: each piece starts about 200 ms after its plan, so the
50 ms `startOk` and 17 ms `timeOk` fail from piece 2. That is the piece lag and not the touch path. Lag compensation is a Lean change
(follow-up). Run 4 exercises the `replay-stall` path on a real Simulator: a named error, no hang, no orphan.

Dispatch lag of a piece is the wall time of its `/actions` call minus the planned duration of the piece (`pieceMs` in run.json, taken with
`performance.now()` around `perform` on this Mac). The lag is the call overhead (HID setup, completion marker, HTTP) on a Simulator with
no display; it is not phone time. The frame counts come from pages that barely scroll and are not a comparison of arms.

## Accepted limits and follow-ups

- Simulator touch delivery may differ from the phone's (the same HID generator on both; the Simulator has no display attach). The
  phone session is a follow-up the lead books: dismiss the Safari first-run tip first, then run with the pieces driver; read
  `replay-stall` as the named stop. The drift (reason 1) is in the UI process on iOS, so the phone is expected to show it too, which is
  INFERRED from the shared source path.
- The Simulator runs are local debug runs, not 3 CI jobs; a CI reproduction on a macOS runner is a follow-up.
- Lag compensation (Lean change): subtract the summed piece lag from the next lead-in pause so `startOk` and `timeOk` hold on multi-swipe
  pieces. Follow-up `replay-lag-compensation`; not implemented here.
- Wedge mechanism (reason 2) is UNKNOWN. A driver that bypasses the WebKit automation touch path (XCUITest through WebDriverAgent, or
  idb) is the next candidate; neither is installed (Homebrew install is the lead's call).
- `com.apple.TipKit.HideAllTips` suppression is unverified (the tip never appeared); check on the phone session or a fresh CI Simulator.
- Calibrating the limits needs phone replays (follow-up `limit-calibration`).
- The pilot verdict (success: all three replays of rec-1 pass `replayMatches` and their spread is below the gap between two different
  recordings): the CLI prints replayMatches per pass and the frame counts and writes run.json; the spread of the 3 replays and the
  rec-1 vs rec-4 gap are not computed yet (follow-up pilot-verdict, with the verdict function in Lean).
- Simulator lane: `--sim <udid>` now drives an iOS 26.x Simulator (see above); it does not reproduce the phone's events.
- `fromCiProfile`, `makeProfile`, `simulateEvents` and the driver glue are TS stand-ins; the decisions they feed (`compile`,
  `replayMatches`, the generators) are Lean-proved and golden-checked.
- Recordings of a person's finger stay local; tests use synthetic fixtures only.

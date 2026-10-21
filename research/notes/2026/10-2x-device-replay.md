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

## Accepted limits and follow-ups

- Calibrating the limits needs phone replays (follow-up `limit-calibration`).
- The pilot verdict (success: all three replays of rec-1 pass `replayMatches` and their spread is below the gap between two different
  recordings): the CLI prints replayMatches per pass and the frame counts and writes run.json; the spread of the 3 replays and the
  rec-1 vs rec-4 gap are not computed yet (follow-up pilot-verdict, with the verdict function in Lean).
- Simulator lane: the existing harness has no touch path (follow-up).
- `fromCiProfile`, `makeProfile`, `simulateEvents` and the driver glue are TS stand-ins; the decisions they feed (`compile`,
  `replayMatches`, the generators) are Lean-proved and golden-checked.
- Recordings of a person's finger stay local; tests use synthetic fixtures only.

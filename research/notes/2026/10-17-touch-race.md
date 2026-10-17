# Touch delivery race in the Chromium swipe-touch-v1 profile (EventDispatch, HitTest, FunctionCall, PrePaint)

Date 2026-10-17. Task `touch-race`. Harness `packages/measure-chromium` (Chromium headless shell 156.0.8078.4, pin
f842f52, sources in `.cache/upstream/chromium@f842f52/`). Status words: CONFIRMED (source or measurement cited),
MEASURED, INFERRED.

## 1. Result

| arm | before (quarantined, run 39044812879 and earlier) | after (3 CI workflow runs, 3 VMs each) |
|---|---|---|
| R rewrite | quarantined | deterministic(0,0) for all 4 types in every run |
| A original, EventDispatch | quarantined | stable(2,2), stable(2,2), stable(2,2) |
| A, FunctionCall | quarantined | stable(2,6), stable(2,6), stable(2,6) |
| A, HitTest | quarantined | stable(2,2), stable(4,2), stable(4,2) |
| A, PrePaint | quarantined | stable(2,2), quarantined(6,2), stable(4,2) |

Class cells are `(k frames that differ, t largest count spread)`. Runs: 39046992424, 39047378531, 39047820525 (final
harness, sha 4f6bfbe); 39046261820 is the throttle-only step (A: EventDispatch stable(3,2), FunctionCall stable(3,6),
HitTest quarantined(5,2), PrePaint quarantined(7,2)). Before the fix, per-job totals on A varied by up to 8 (EventDispatch
1244 / 1246 / 1252) and by dozens of frames; now by at most 2. 0 wedges: every job finished all 531 (A) / 409 (R) frames,
no FW_BEGINFRAME_HANG. Totals now: A EventDispatch 1288 or 1290, R 753.

## 2. Mechanism (CONFIRMED by source, MEASURED in a debug trace)

1. `InputHandler::DispatchWebTouchEvent` first calls `InsertVisualStateCallback`
   (`content/browser/devtools/protocol/input_handler.cc:1714@f842f52`), so touch n is forwarded only after the commit and
   draw of BeginFrame n. The CDP ack of a non-blocking touchmove then comes from the compositor thread, before the main
   thread has run it.
2. In the renderer, a touchmove is rAF-aligned (`MainThreadEventQueue`, `main_thread_event_queue.cc:891-905`) and is run
   by `DispatchRafAlignedInput(frame_time)` at the start of the next BeginMainFrame (`widget_base.cc:1175`).
3. **The hold.** `main_thread_event_queue.cc:758-770`: an async touchmove at the queue front is kept back while the queue
   holds exactly one event and `frame_time < last_async_touch_move_timestamp_ + async_touch_move_interval_`. The interval is
   200 ms (`:65-78`) and the throttle applies unless an earlier GSU was acked as unconsumed (`:1109-1130`). Whether the
   queue holds 1 or 2 events when BeginMainFrame n+1 starts depends on a thread race (did touch n+1 reach the renderer
   first), so touchmove n runs in frame n+1 or n+2: the k/k+1 shift. In dbg1, F19's main thread ran F18's touchmove
   before the compositor's own `DispatchEvent` for F19.
4. The gesture events (GSU) that the browser makes from the ack reach the compositor concurrently with the harness sending
   BeginFrame n+1, a second real-time race (scrollY of frame n+1 moved by 10 px between jobs).

## 3. What the harness does now

- Touch profiles add `--async-touch-move-throttle-time-ms=0` (switch name: `third_party/blink/common/switches.cc:17`
  at f842f52), which removes the hold in step 3. Env `FW_TOUCH_THROTTLE=default` turns it off.
- After a frame in which a touch was sent and acked, the next frame is delayed 100 ms of real time
  (`FW_TOUCH_POST_ACK_MS`) so the gesture events of step 4 arrive first. This is a margin, not a proof.
- The touch wedge fix (`--disable-features=WaitForLateScrollEvents`) is untouched; 0 wedges.

## 4. Residual, and why it cannot be removed from the harness side (INFERRED)

Three one-frame shifts remain, each in 1 job of 3: frames 176/177 (PrePaint only), 351/352 (HitTest and PrePaint), 469/470
(touch events: EventDispatch 1 versus 2, near the page end). Bound: shift of one frame, spread at most 2 for
EventDispatch, HitTest, PrePaint and 6 for FunctionCall, at most 3 frame pairs, so k is at most 6; PrePaint k=6 exceeds
kMax 4 in one of the three sets. The first two do not move EventDispatch, so they are not touch-queue shifts and are
likely page-side (scroll position thresholds 1549 and 3203). No trace is uploaded by CI, so their cause is open. To
close it, the workflow must upload a trace for these frames (`FW_EXTRA_CATEGORIES` plus a trace artifact).

## 5. Requests for the lead

- Lean: none new. The classifier works as specified; the borderline PrePaint k=6 versus kMax 4 is the policy doing its job.
- Open: a trace artifact on CI for frames 176, 351, 469 of the original to name the page-side cause.

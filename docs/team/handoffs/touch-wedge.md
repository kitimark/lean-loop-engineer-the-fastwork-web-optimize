# Handoff: touch-wedge (Chromium lane, touch input wedges BeginFrame)

State: branch worktree-wf_c2b8a932-977-2 (commit sha in the report). Detail and numbers: packages/measure-chromium/README.md,
section "Update 2026-10-17 (touch wedge: cause and fix)" at the end.

Done
- Cause found (CONFIRMED in cc source @f842f52 + scheduler trace): features::kWaitForLateScrollEvents (default on) puts the
  compositor in WAIT_FOR_SCROLL with a timer at frame_time + 0.333*interval; the driver's frame_time (T0 5,000,000 ms + vt) is ~4900 s
  ahead of the container clock, so the timer never fires, and BeginMainFrame is held back while the touch ack waits for it.
- Fix: `--disable-features=WaitForLateScrollEvents` in packages/measure-chromium/src/run.mjs CHROME_ARGS (T0 comment updated).
- Verified on the original, swipe-touch-v1: flag off 5/5 attempts wedged at the same frame; flag on 21 runs, 11 at the default
  touch settle (0 wedges, 1 attempt each), 10 at settle 300 (1 wedge, next attempt passed).
- Trajectories of 5 runs at low load are identical (521 frames); counts files are still not byte-identical (touchmove frame k vs k+1,
  async image completions): same shifting/quarantined set as before.

Open items
- One residual wedge (settle 300 ms, 1 unacked, vt 26516.67) with no trace; candidate: LATE/REGULAR deadline with a future
  deadline under IsDrawThrottled (scheduler.cc deadline modes). Reproduce with FW_DEBUG=1 FW_EXTRA_CATEGORIES=disabled-by-default-cc.debug.scheduler
  FW_TOUCH_SETTLE_MS=300 and read hang-trace.json (the host retries 5 times, so completion is not at risk).
- The touchmove k/k+1 race (EventDispatch, HitTest, PrePaint, FunctionCall shifting) is not fixed.
- Not run: rewrite with touch (apps/site/dist/aot not built in this worktree), class table on the new flags for scrollTo on the original,
  fwcore zones.json (fwcore not built in this worktree: host.mjs exits 3 after counts.json, which is expected here).
- `swipe-wheel-v1` diagnostic is no longer needed; no containers of mine are running.

Read first: README section above; src/run.mjs CHROME_ARGS; .cache/upstream/chromium@f842f52/cc/scheduler/ (gitignored).

# Handoff: touch-race

State: branch worktree-agent-a9cc844bc300845f4 (pushed as ci/touch-race, sha 4f6bfbe plus the note commit). Only
`packages/measure-chromium/src/run.mjs` changed in code. Read first: `research/notes/2026/10-17-touch-race.md`.

Done
- Race found in source (MainThreadEventQueue async touchmove hold, queue size 1 vs 2) and a second race (GSU arrival vs
  next BeginFrame). Fix: `--async-touch-move-throttle-time-ms=0` for touch profiles (env `FW_TOUCH_THROTTLE=default` to
  disable) and a 100 ms real-time hold after a touch ack (`FW_TOUCH_POST_ACK_MS`).
- CI runs (swipe-touch-v1, both targets, 3 VMs each): 39046261820 (throttle only), 39046992424, 39047378531, 39047820525.
  R deterministic everywhere. A: EventDispatch, FunctionCall, HitTest stable in all; PrePaint stable, quarantined(6,2),
  stable. 0 wedges.

Conventions: no decision logic added in TS; the post-ack hold is a real-time margin (listed as a stand-in, not provable).
CI hygiene: after each push cancel non-chromium-counts runs (webkit-sim, wktr) with `gh run cancel`.

Open
- Frames 176/177, 351/352, 469/470 of the original still shift by one frame in about 1 job of 3. Cause unknown (page-side
  for the first two). Needs a CI trace artifact for those frames (workflow change, not in this task's write list).
- Not tried: a longer post-ack hold (250 ms); an in-page dispatch counter (rejected: adds a listener, changes what is
  measured).
- trace.mjs and n0.mjs untouched (n1-lean owns them).

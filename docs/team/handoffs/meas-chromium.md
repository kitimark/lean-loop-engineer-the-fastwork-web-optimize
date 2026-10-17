# Handoff: meas-chromium (Chromium counts lane)

State: branch worktree-agent-afebbc5875983d2f8. Full detail and numbers: packages/measure-chromium/README.md, section "Update 2026-10-17".

Done
- Touch input (`swipe-touch-v1`, CDP touch events): works, no fling; HitTest stays quarantined (cause is touch-event delivery, not hover).
- Apt (211 packages, snapshot.debian.org + manifest checked at build) and npm (lock + `npm ci`) pinned; `--no-cache` rebuild passed.
- Layer census + raster invalidation rects per frame (`census.*`, `raster.*` from `LayerTreeHostImpl:snapshot`); deterministic on the rewrite.
- Rewrite served from apps/site/dist/aot; default, engine.scroll:batched, nav.hitTest:hit-skip, hero.countdown:strip run with swipe-v1
  (scrollTo); fwcore `screen`/`ticks` replies recorded (README; out/fwcore/swipe-v1-rewrite.json is gitignored, rerun src/fwcore-screen.mjs).
- Lead items: #1 flags changed (no `--deterministic-mode`, no `--disable-threaded-animation`) and fixture-checked: Paint/Layout/commit are 0 for
  a compositor animation but UpdateLayoutTree stays 1 per frame, so "0 UpdateLayoutTree" does not hold. #18 partial: `FW_BARRIER_MIN_MS=10`.
  CI: H1 `--num-raster-threads=2` is in run.mjs; H2 `FW_DOCKER_CPUS` -> `docker run --cpus` is in host.mjs (both small, done).
- Load question: all runs (also before the sampler) ran at load1 360-450; deterministic classes held; whole files were never byte-identical.

Bisect state (touch wedge, the unresolved issue)
- BeginFrame wedges (renderer compositor stops after commit; no deadline/draw) with a touch backlog of 2 unacked events or a frame without
  input during an active touch scroll. On the original it wedged at the same frame in 5/5 attempts at load1 ~8, but not under load1 ~400.
- Ruled out by test: `--deterministic-mode` re-added, `--num-raster-threads`, `--disable-threaded-animation`, the three deterministic-mode
  switches, the layers trace category, touch settle 50/300 ms, ack grace 30/200 ms, finger x (8/215), stroke start y (880/600), gap 2/12 frames.
- Not tried: `setTouchEmulationEnabled` false (no touch events API), a stroke that never lifts, Chromium trace of the renderer scheduler state
  machine at the wedge (hang-trace.json via FW_EXTRA_CATEGORIES + --debug shows commit done, no ScheduleBeginImplFrameDeadline).

Open items
- A diagnostic container for `swipe-wheel-v1` (wheel input) may still be running; it was not finished and may need `docker stop`.
- Original touch runs after the flag/pin change: none completed (wedge at low load). Class table for the original is from before that change.
- Original with the layers category (trace size) and scrollTo runs on the new flags/image: not run. Barrier sweep (#18) on the original not done.
- Per-part attribution: only via config diff; the trace has no part marks.
- `trace.UpdateLayoutTree` for compositor animations: a main-thread style update per BeginFrame remains (see fixture).
- Pure TS still needing a Lean spec: `zoneSums`, `snapshotCounts`, `classes.mjs` thresholds.

# Handoff: meas-webkit (WebKit counts lane)

State on branch worktree-agent-a350351627a0b4359 (from main 1d6c88c). Read packages/measure-webkit/README.md first
(sections "Per-step determinism without virtual time", "RenderingFrame on iOS 27.0", "Against the rewrite", "Feasibility: WKTR").
Counts only; nothing here is phone time.

## Result in one screen
- **Per-step stays quarantined** for Layout, Paint, InvalidateLayout, ObserverCallback, and for RecalculateStyles at tolerance 1
  (spread 2-3). Tried: (a) step-locking from the Mac (worse: more free-run time per step), (b) holding the page's timers
  (`__wk.hold/advance`, removes TimerFire; steadier rAF under load; no fix for layout/paint/style), (c) windowing after the step's
  first Composite (no change), (d) a warm-up scroll (no help). Deterministic per step: Composite, EventDispatch;
  FireAnimationFrame stable at low load. Jitter does not average out over 10-20 steps. Totals are gateable at 3-5 %.
- **The first load after a boot is not a sample** (FireAnimationFrame 703-709 vs 729-739). `--warmup 1` is now the default.
  The old determinism table (no warm-up, no load record) is marked pessimistic in the README.
- **Host load** was 130-450 (idle ~0 %) for part of the work. Stamped per pass (`src/load.mjs`). In the 6-pass stamped session
  base-mode counts correlate with load (r 0.55-0.81 for rAF, style, layout; Paint -0.81); hold is less sensitive for rAF/timers
  (r 0.11) but not for layout (0.61) and InvalidateLayout (0.94). n = 6 and load fell over the run, so confounded with pass order.
  Not shown: that an idle Mac makes per-step layout/paint stable. Rerun quiet before concluding "engine".
- **Simulator kept alive**: `--keep` is the default now, boot once per session (`sim down` / `--no-keep` to stop). The lead's
  sampler (`load.jsonl`) shows the Simulator process count 225-264 over the first kept-alive window (10:00Z-10:20Z) and 192-254 over
  the rewrite lane (10:33Z-10:53Z), never near 20. The dips to 9-32 (09:49-09:54Z, 10:20-10:32Z) are my own deliberate shutdowns
  (runs before `--keep` became the default; `sim down` and the iOS 26.5 runs with `--no-keep`). fw-iphone-27 is left booted.
  Safari launch under load can time out: retried 3x in `bootDevice`.
- **RenderingFrame (#8)**: 0 on iOS 27.0 (24A434) for all 7 Timeline start configurations; ~60/s on iOS 26.5 (23F77) through the same
  proxy. So it is iOS 27.0's WebKit, not our sequence and (INFERRED) not the proxy. A direct webinspectord client was **not**
  written. On 26.5 `hold` makes RenderingFrame stable at tolerance 1 per step.
- **Rewrite**: all four configs hydrate (`__fw.mode hydrate`, no style misses). Fwcore `screen`: full 12-column vectors are `mixed`
  even for two runs of the same config; with deterministic/stable columns only, hit-skip dominates 9/9 at every granularity
  (RecalculateStyles 164 -> 19), batched dominates at total (164 -> 145), strip does not (+74 rAF and FunctionCall). Not comparable
  in values with the original (74 vs 107 steps, "not aligned"; 88/16 layers vs 106+).
- **WKTR**: not buildable comfortably here (38 GB free, 16 GB RAM, Metal toolchain uninstalled, no iOS-simulator prebuilt, size/time
  undocumented). Cloud Mac (PLAN Q10) or >= 120 GB free. Adds restyled-element count, renderingUpdateCount, layerFlush/compositing
  counts, repaint rects, isThreaded.

## For CI planning
fw-iphone-27 = iPhone 15 Pro Max on **iOS 27.0 runtime build 24A434**, WebKit.framework 8625.1.29.10.29 (UA `Version/27.0`, OS
token frozen at 18_7). The second device `fw-sim 15 Pro Max` is iOS 26.5 (23F77, WebKit 8624.2.5.10.4). Compare 24A434 with the
GitHub `xcode-27` image's runtime before trusting counts across machines.

## Where things are
- Code: `src/scrollrun.mjs` (modes), `src/page.mjs` (timer hold in the bootstrap), `src/perstep.mjs`, `src/reduce.mjs`
  (`compositeCuts`, `reduceWindows`), `src/handoff.mjs` (fwcore `screen`/`ticks`, `--cols`), `src/rfprobe.mjs`, `src/load.mjs`,
  `src/session.mjs` (`--site` prerendered build), `scripts/site-lane.sh`, `scripts/stamped-lane.sh`. 21 unit tests.
- Data (gitignored `out/`): `ps2-*` (session A), `ps3-*` (stamped session B), `ps26.*` (iOS 26.5), `rfprobe-*`, `site-*-{ps,det}.json`,
  `handoff-site-*.json`, `unstamped/` (first rewrite batch taken at load ~400, superseded).

## Open / next (ranked)
1. Rerun `perstep` (base, hold; 6 passes) on a quiet Mac and say whether load explains the per-step Layout/Paint jitter.
2. Find the source of the top-level Layout/Paint/InvalidateLayout jitter (not identified; not time-in-step).
3. #22 WebKit virtual frame clock: not attempted; any rAF/animation replacement is against the PLAN rule. WKTR
   `UIHelper.renderingUpdate()` is the in-process step lock.
4. Lean: new pure functions in `reduce.mjs` (`compositeCuts`, `reduceWindows`) need a spec + goldens, as do the earlier ones;
   `handoff.mjs` only builds fwcore requests (the vectors `step`/`zone`/`total`, column choice) and decides nothing.
5. Direct webinspectord client to close "proxy vs webinspectord" for RenderingFrame (unlikely to matter given the 26.5 control).
6. The first determinism table should be regenerated with `--warmup 1` and load stamps before it is quoted.
7. Port the timer hold (b) to the Chromium lane only if its quarantined TimerFire-like counts need it (not checked).

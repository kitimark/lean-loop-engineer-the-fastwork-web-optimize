# @fw/measure-webkit

WebKit work counts from Mobile Safari in the iOS Simulator (`fw-iphone-27`, iPhone 15 Pro Max, iOS 27.0), over the
raw Web Inspector protocol through `ios_webkit_debug_proxy`. No WKTR, no Playwright. Node 24, ESM, no dependencies.
Part of PLAN §4.1-4.2 (one held state in WebKit). Counts only: no milliseconds from this Mac are phone time.

```sh
pnpm --filter @fw/measure-webkit census -- --state 0            # layer census at scroll y (list ok: 0,1500,max)
pnpm --filter @fw/measure-webkit scroll                         # Timeline counts over the scripted scroll
pnpm --filter @fw/measure-webkit seek                           # seek-overhead fixture
pnpm --filter @fw/measure-webkit determinism -- --runs 2        # the whole experiment, then the class table
pnpm --filter @fw/measure-webkit merge -- out/a.json out/b.json # classes over independent sessions (worst wins)
pnpm --filter @fw/measure-webkit perstep -- --modes base,hold --runs 3   # per-step determinism: drivers x passes, class table
pnpm --filter @fw/measure-webkit perstep-report -- out/a.json out/b.json # classes over several perstep files
pnpm --filter @fw/measure-webkit rfprobe                        # RenderingFrame probe: 7 Timeline start configurations
pnpm --filter @fw/measure-webkit handoff -- --mode base out/base.json out/var.json  # fwcore screen + ticks
pnpm --filter @fw/measure-webkit sim -- down                    # shut the device down (commands leave it booted)
pnpm --filter @fw/measure-webkit test                           # unit tests, no Simulator needed
```
Every command boots the device headless **if it is not booted already**, serves the **read-only** snapshot
(`snapshot/site` of the main checkout, or `$FW_SNAPSHOT_SITE`) or, with `--site <dist/aot> --search '?fw=...'`, a prerendered
build of `apps/site` (see "Against the rewrite") on `127.0.0.1` with `Cache-Control: no-store`, runs, and stops the proxy and
the server. **The Simulator stays booted** (`--keep` is the default; `--no-keep` or `sim down` shuts it down), so one lane
session boots once. Results go to `out/` (gitignored) as JSON. Nothing of the snapshot is copied. Options:
`--clock pinned|live`, `--hold`, `--settle`, `--window`, `--step`, `--frames`, `--ns`, `--vendors off|live`, `--out`,
`--mode base|lock|hold|lock+hold[+warm]`, `--modes a,b`, `--warmup N` (default 1 discarded load), `--site`, `--search`.
`FW_SIM_NAME` picks another device (for example the iOS 26.5 one). Every pass in `perstep` and `determinism` records the host
`load1` and CPU idle at its start and end (`src/load.mjs`).

## What is in the box

| file | role |
|---|---|
| `src/sim.mjs` | boot/launch Safari/shutdown via `simctl`; the proxy against the Simulator's inspector socket (`lsof -aUc launchd_sim`); every attached phone is written to the proxy config with port -1, so it can never attach one; ports 9341/9342 (never 9221/9222) |
| `src/serve.mjs` | read-only static server, `no-store`, `/analytics.js` answered empty (it loads Google Tag Manager from the network) unless `--vendors live`, `/__fixtures` mount |
| `src/wip.mjs` | thin raw protocol client (`Target.sendMessageToTarget`), `enable`-once, `runAsync` (Safari ignores `awaitPromise`), `navigateTab` |
| `src/page.mjs` | bootstrap script (clock pin + seeded `Math.random`, native `performance.now` and rAF kept), `Page.reload` that keeps the connection |
| `src/timeline.mjs` | `Page.enable` first, then `Timeline.start` (depth 1, `Timeline` instrument only); returns raw rows |
| `src/census.mjs` | `LayerTree.layersForNode` twice (paint deltas) + `reasonsForCompositingLayer` per layer |
| `src/scrollrun.mjs` | stepped scroll: `scrollTo` instant + 2 native rAFs per step, `performance.mark` per step |
| `src/seek.mjs`, `fixtures/seek.html` | N accelerated animations, free-running vs seeked |
| `src/reduce.mjs` | **the one pure reduction module** (see "For the Lean spec") |
| `src/determinism.mjs`, `src/cli.mjs` | orchestration and the commands |

## Protocol facts (MEASURED on this build unless noted)

- Page under test: UA `Version/27.0` (the OS token is frozen at 18_7), viewport 430x775 CSS px, DPR 3, document height 6042
  (max scroll 5267). Safari's toolbar is part of the page area: this is Mobile Safari, not a bare web view.
- Proxy: the tab appears on the tabs port a few seconds after `simctl openurl`, and the first `openurl` after a fresh
  launch is sometimes dropped; the session asks twice (cost: about 10 s). `about:blank` is never used.
- `Page.setBootstrapScript` works **only if sent on the same connection that then calls `Page.reload`** (the connection
  survives `Page.reload`; it does not survive `location.href` navigation, so the seek fixture reconnects). Sent on a
  connection that is closed before the navigation, it does nothing. It is how the date is pinned to
  `2026-10-01T00:00:00+07:00` and `Math.random` seeded (mulberry32), as in PLAN §4.2.
- `Timeline`: `RenderingFrame` records are **absent** over this proxy on iOS 27.0 (0 records in every run, although
  `PageTimelineAgent` opens them per run-loop turn on Cocoa; INFERRED: they are dropped when never completed). The
  rendering-update count is therefore not available from the Timeline; `Composite` records stand in (see the table:
  `Composite` is deterministic). Record times are real (`Page.enable` first).
- `performance.mark(name)` arrives as a `TimeStamp` record on the records' clock: used to cut a run into steps.
- `LayerTree`: 29 reason flags; a layer can disappear between `layersForNode` and `reasonsForCompositingLayer` (error
  "Missing render layer"); such a layer is recorded with reason `(gone)` and counted. Layer and node ids are per
  inspector session and are left out of anything compared between runs.
- Occasionally (3 of about 10 passes) one `Runtime.evaluate` stalls for 15 s right after a reload that follows a census at
  the page bottom; the pass reconnects and retries from a fresh load (logged as "retrying"). Counts of the retried
  attempt are from a fresh load like any other.
- The original runs a rAF loop all the time (about 105 `FireAnimationFrame` per 3 s idle in this Simulator) and keeps
  restyling and relayouting at idle. So "free-running" is real work, and wall-clock-driven counts are not reproducible.
- Never used in timed windows: `Screenshot` instrument, repaint counters, paint flashing, live `layersForNode`.

## Determinism (PLAN V-i)

> Caveat (added 2026-10-17): the tables in this section were made without a discarded warm-up load and without a host-load
> record; the Mac was heavily loaded around then. The scripted-scroll rows are pessimistic; see "Per-step determinism without
> virtual time" below for the corrected per-step tables. The census rows were not re-measured.

Method: 2 fresh-load passes in each of 2 independent Simulator boots (4 passes), pinned clock. Each pass: census at
y = 0, 1500, 3000, 4500, 5267 (hold 1.5 s, paint window 2 s), a stepped scroll (50 px steps, 107 steps, 2 rAF per step)
and the seek fixture. A count is compared cell by cell (a cell = a total, a zone sum, a step, a state):

- **deterministic**: identical in every run;
- **stable**: not identical, every cell's spread (max - min) within `max(absTol, relTol * max|v|)`: total abs 2 /
  5 %, zone abs 2 / 10 %, step abs 1, census counts abs 1 / 5 %, backing bytes 2 %, paintCount abs 2 / 10 %;
- **quarantined**: some cell beyond that. Reported, never gated on.

Across the two sessions the worse class wins (`merge`). 93 of 104 table rows had the same class in both sessions; the
rest differ by one class and the worse is shown. `out/` holds the full tables (104 rows), regenerate with
`determinism` then `merge`.

### Scripted scroll (Timeline records, 107 steps)

| count | total | per 500 px zone | per step | totals seen over 4 passes |
|---|---|---|---|---|
| `Composite` | deterministic | deterministic | deterministic | 213 x4 |
| `EventDispatch` | deterministic | deterministic | deterministic | 107 x4 |
| `RenderingFrame` | n/a (0 records) | | | 0 |
| `TimerFire` | deterministic | stable | quarantined | 42-45 |
| `FireAnimationFrame` | stable | stable | stable | 731-732 |
| `RecalculateStyles` | stable | stable | quarantined | 656-672 |
| `ScheduleStyleRecalculation` | stable | stable | quarantined | 625-642 |
| `FunctionCall` | stable | stable | quarantined | 957-968 |
| `Layout` | stable | quarantined | quarantined | 619-639 |
| `InvalidateLayout` | stable | quarantined | quarantined | 467-504 |
| `ObserverCallback` | stable | quarantined | quarantined | 88-97 |
| `Paint` (count) | stable | quarantined | quarantined | 1573-1587 |
| `Paint` clip area, px^2 | stable | quarantined | quarantined | 94.4-98.0 M |

Reading: totals over a whole scripted scroll are usable with a tolerance (about 3 % for style, 3 % for layout);
position-resolved counts (per 500 px, per step) move by a few records between runs because free-running timers fire at
wall-clock times, so they are **quarantined**, not gated. Only `Composite` and `EventDispatch` are exact. Pinning the
clock matters: with the live clock the same table gets worse (`TimerFire` and `ObserverCallback` quarantined at the
total, `FireAnimationFrame` quarantined per zone, see `--clock live`; that comparison is 2 passes of one session).

### Layer census at held scroll states

| state y | layers (4 passes) | backing MB (sum) | class: count / bytes |
|---|---|---|---|
| 0 | 106, 110, 112, 112 | 36.2-36.5 | stable / stable |
| 1500 | 112-118 | 87.0-87.1 | quarantined / stable |
| 3000 | 42 x4 | 79.4 x4 | deterministic / deterministic |
| 4500 | 47-48 | 151.4 x4 | stable / deterministic |
| 5267 (max) | 30 x4 | 89.3 x4 | deterministic / deterministic |

Per compositing reason (layers per state): deterministic for `backfaceVisibilityHidden`, `clipsCompositingDescendants`,
`filterWithCompositedDescendants`, `filters`, `maskWithCompositedDescendants`, `overflowScrollingTouch`, `perspective`,
`positionFixed`, `positionSticky`, `root`, `transform3D`, `willChange`; stable for `opacityWithCompositedDescendants`,
`overlap`, `stacking`, `transformWithCompositedDescendants`; **quarantined** for `animation` and `(gone)`. `paintCount`
(cumulative) and its 2 s delta (about 56-131 at y 0-3000, 360-400 at the bottom) are quarantined: they depend on how long
the page has run. The layer *set* (name, bounds, bytes, reasons) differs by up to a few layers near the top of the page
(churn of `will-change` layers with the page's own timers): quarantined for y = 0 and 1500, exact below.
Use y >= 3000 for gating layer counts; treat the top states as ranges.

### Seek overhead (fixture, 60 steps of 2 rAF, N transform+opacity animations)

All 32 rows (N x arm x type) were deterministic in all four passes.

| N | layers with reason `animation` | style records free | style records seeked | layout free / seeked | paint free / seeked | composite free / seeked |
|---|---|---|---|---|---|---|
| 0 | 0 | 0 | 0 | 0 / 0 | 0 / 0 | 119 / 119 |
| 10 | 10 | 0 | 122 | 0 / 2 | 0 / 4 | 119 / 119 |
| 50 | 50 | 0 | 122 | 0 / 2 | 0 / 16 | 119 / 119 |
| 100 | 100 | 0 | 122 | 0 / 2 | 0 / 30 | 119 / 119 |

Free-running accelerated animations cost no style records (0; each gets an `animation` layer: they run off the main
thread). Seeking them costs about 2.03 `RecalculateStyles` per step (122 per 60 steps) **independent of N** in this range,
plus a few Layout and N-dependent Paint records, while `Composite` is unchanged. Tag `RecalculateStyles`, `Layout`
and `Paint` as `harness-induced` for any seeked WebKit run; `Composite` is clean. (The PLAN's "invalidates style per
animation per step" is not what this build shows for N up to 100: one invalidation per step, not per animation. MEASURED.)

## Per-step determinism without virtual time (2026-10-17, original page, pinned clock)

Goal: make the **per-step** count vectors (`RecalculateStyles`, `Layout`, `Paint`, ...) deterministic or `stable` with step
tolerance 1, keeping native rAF scheduling and seeking nothing. Drivers (`--mode`), all in `src/scrollrun.mjs`, each measured
over >= 4 passes (2 boots x 2 passes for the first tables, a kept boot x 6 passes for the stamped one), 107 steps of 50 px:

| mode | what it does |
|---|---|
| `base` | in-page loop: `scrollTo`, 2 native rAFs, next step (the earlier design) |
| (a) `lock` | the Mac issues each step: `mark`+`scrollTo`, waits for a `Composite` record after the mark in the Timeline stream, then one evaluate runs 2 quiet native rAFs and marks; next step only after that mark arrives |
| (b) `hold` | bootstrap script wraps `setTimeout`/`setInterval`/`requestIdleCallback`: native until `__wk.hold()`, then every pending timer moves to a virtual queue and fires only from `__wk.advance(33.3 ms)` once per step (in due-time, creation order). rAF, `performance.now`, observers, MessageChannel and WebKit's internal timers are untouched |
| (c) window | no new run: the same raw rows re-bucketed so a step counts only from the end of its first `Composite` (`reduce.mjs: compositeCuts, reduceWindows`); reported as window `win` |
| (d) `+warm` | beyond the brief: scroll the whole page once with real pauses first (removes lazy-resource arrival from the measured scroll) |

Class of each count (total / per 500 px zone / per step with tolerance 1; `det` = identical in every pass, `stable` = within the
tolerance, `QUAR` = beyond). Session A = 2 boots x 2 passes after one discarded warm-up load, host load not recorded
(`out/ps2-*.json`); session B = one kept boot, 6 passes, host load1 136-341, idle 0-50 % (`out/ps3-*.json`).

| count | A base | A hold | B base | B hold |
|---|---|---|---|---|
| `Composite` | det/det/det | det/det/det | det/det/det | det/det/det |
| `EventDispatch` | det/det/det | det/det/det | det/det/det | det/det/det |
| `RenderingFrame` | n/a (0 records) | n/a | n/a | n/a |
| `FireAnimationFrame` | stable/stable/stable | stable/stable/stable | stable/QUAR/QUAR | stable/QUAR/QUAR |
| `TimerFire` | QUAR | det (held: 0 native fires, **by construction**) | QUAR | det (by construction) |
| `RecalculateStyles` | stable/stable/QUAR | stable/QUAR/QUAR | stable/QUAR/QUAR | stable/QUAR/QUAR |
| `ScheduleStyleRecalculation` | stable/stable/QUAR | stable/QUAR/QUAR | stable/QUAR/QUAR | stable/QUAR/QUAR |
| `FunctionCall` | stable/stable/QUAR | stable/stable/QUAR | stable/QUAR/QUAR | stable/QUAR/QUAR |
| `Layout` | stable/QUAR/QUAR | stable/QUAR/QUAR | QUAR | QUAR |
| `Paint` | stable/QUAR/QUAR | stable/QUAR/QUAR | QUAR | QUAR |
| `InvalidateLayout` | QUAR | stable/QUAR/QUAR | QUAR | QUAR |
| `ObserverCallback` | QUAR | QUAR | QUAR | QUAR |

Answers (MEASURED):

- **(a) step-locking makes it worse**, not better. Waiting for a Composite and quiet rAFs costs two inspector round trips per
  step, the page free-runs longer per step (Composite 213 -> 500-950 per run, TimerFire 44 -> 117-150), and per-step cells that
  differ rise to 90-107 of 107 (worst spread: `RecalculateStyles` 86, `Paint` 245). Not recommended; `lock+hold` is as bad.
- **(b) holding timers** removes the page-timer share: `TimerFire` and, in quiet conditions, `FireAnimationFrame` and
  `InvalidateLayout` improve (FireAnimationFrame 729 in every warmed `hold` pass of three sessions, host load not recorded). It also keeps rAF counts steadier
  under host load (B: base 722-739, hold 715-733, but one hold pass fell to 715). It does **not** make Layout, Paint or
  RecalculateStyles per step stable: per-step spread stays 2 (style), 5 (layout), 22-31 (paint).
- **(c) windowing after the first Composite** changes nothing material (same classes, spreads within 1-2).
- **(d) warm-up scroll** did not help (Layout and InvalidateLayout got worse), so network/lazy-resource arrival is not the
  source of the jitter.
- **The remaining jitter is not time-in-step.** Summing neighbouring steps does not remove it: Layout spread in `hold` is 5 at
  1 step, 13 at 10 steps and 17 at 20 steps (`rel` 71 % -> 25 % -> 24 %), so it is run-to-run difference in how much work WebKit
  does, not a shift between neighbouring steps. `Layout`, `Paint`, `RecalculateStyles` and `InvalidateLayout` are top-level
  records of the rendering update (not children of `FireAnimationFrame`; `ObserverCallback>FunctionCall` is 59-62 per run and
  varies), source not identified. Per-step stays **quarantined for Layout, Paint, InvalidateLayout and ObserverCallback**, and
  quarantined at tolerance 1 for RecalculateStyles (spread 2-3). What can be gated: totals with a 3-5 % tolerance,
  and per-step `Composite`, `EventDispatch` (det), `FireAnimationFrame` (stable at low load).
- **The first load after a boot is not a sample** (MEASURED): it runs fewer rAFs and restyles (FireAnimationFrame 703-709 vs
  729-739, style 581-642 vs 600-690). A fixed rule is now built in: `--warmup 1` (default) discards one load+scroll at the start
  of every `perstep`/`determinism` session. The first determinism table above (Determinism section) was made without it
  and without a load record, so it is **pessimistic for the scroll rows**; regenerate before quoting.
- **Host load.** The Mac was at load1 130-450 with CPU idle about 0 % while these ran (lead's sampler: 8 cores). Counts that
  depend on timing correlate with load in session B (n = 6, confounded with pass order because load fell during the run):
  Pearson r with mean pass load1 for `base`: RecalculateStyles 0.74, Layout 0.81, Paint -0.81, TimerFire 0.59, FireAnimationFrame
  0.55; for `hold`: FireAnimationFrame 0.11, RecalculateStyles 0.40, Layout 0.61, InvalidateLayout 0.94. So at least part of the
  quarantined cells is load, and `hold` is less load-sensitive for rAF and timers. Whether per-step Layout and Paint become
  stable on an idle Mac is **not shown**: rerun when the machine is quiet (the rewrite runs below were taken at load1 8-20 and
  were far steadier, but that page is also much smaller).

Class W (per-step componentwise dominance) is therefore reachable on this lane only for the columns that are
deterministic or stable (see `handoff --cols` below); a WebKit virtual frame clock (improvement #22) is the next lever and is
not attempted here (it would be a rAF/animation replacement, which the plan forbids; WKTR's `UIHelper.renderingUpdate()`
is the sanctioned version).

## RenderingFrame on iOS 27.0 (improvement #8)

`RenderingFrame` records are **0 on iOS 27.0 (runtime build 24A434, WebKit.framework 8625.1.29.10.29) for every Timeline start
configuration** and **about 60 per second on iOS 26.5 (23F77, WebKit 8624.2.5.10.4)** through the same proxy and the same
code. `rfprobe` (`out/rfprobe-*.json`) captures 60 scroll steps + 1 s idle under 7 configurations; RenderingFrame count:

| configuration | iOS 27.0 | iOS 26.5 |
|---|---|---|
| `[Timeline]`, depth 1 (ours) | 0 | 187 |
| no `setInstruments` | 0 | 187 |
| `[Timeline]`, default depth | 0 | 186 |
| `[Timeline, ScriptProfiler]` | 0 | 168 |
| `[Timeline, Animation]` | 0 | 192 |
| all six instruments | 0 | 179 |
| `[Timeline]` + `setAutoCaptureEnabled(false)` | 0 | 181 |

(Composite is 174-220 in all 14 rows, so the page composited; only the frame wrapper is missing.) Conclusion: it is a property
of iOS 27.0's WebKit, not of our start sequence and not of `ios_webkit_debug_proxy`, which forwards the page's JSON unchanged
(INFERRED: it only wraps the messages in the webinspectord plist envelope). A direct `webinspectord` client was not written,
so "proxy vs webinspectord" is not tested; the 26.5 control makes it unlikely to matter. Source reading (WebKit main, fetched
2026-10-17): on Cocoa `PageTimelineAgent::internalStart` opens a RenderingFrame record and sets `m_runLoopNestingLevel = 1`; the
record is closed by `didCompleteRenderingFrame`, which `RemoteLayerTreeDrawingArea::postRenderingUpdateRunLoopCallback` calls
once per rendering update, and a frame without children is dropped. If 27.0 never calls it for the inspected page the record
stays open and is lost at stop: INFERRED, matches the symptom, not verified in the 27.0 binary. On iOS 26.5, `perstep --modes
base,hold` gives `RenderingFrame` **stable** at total and per zone and **stable at tolerance 1 per step under `hold`**
(12 of 107 cells differ by 1; `out/ps26.json`): the only configuration where a rendering-update count per step exists.
`FW_SIM_NAME="fw-sim 15 Pro Max"` selects that device (it is not the plan's iOS 27.0; use it for mechanism cross-checks only).
Not the plan's engine: CI runners need the `xcode-27` image for 24A434.

## Against the rewrite (`apps/site`, placeholder content)

`pnpm --filter @fw/site build` makes `dist/aot` with one HTML per config hash and `configs.json` (search -> hash -> file).
`--site ../../apps/site/dist/aot --search '?fw=...'` serves `/` with the HTML of that config (a CDN-style rewrite, read-only; the
page checks `data-fw-config` against its own resolver, so a wrong file would fall to client render). Every pass records
`__fw` in `info.fw`; all runs below were `mode: "hydrate"`, `hydrated: true`, no errors, `styleMisses: []`. Scripted by
`scripts/site-lane.sh` (per config: `perstep` base+hold, 3 passes, then `determinism` 2 passes with census y = 0, 1500, max).
Raw JSON in `out/site-<default|batched|hitskip|strip>-{ps,det}.json` (same schema as for the original) and the fwcore replies in
`out/handoff-site-*.json`.

Page: 430x775 CSS px, DPR 3, document height **4378** (74 steps of 50 px) versus 6042 / 107 steps for the original; 88 layers
(16 with the countdown `strip`) versus 106-112 at y = 0 for the original.

Per-step classes of the **default** config (base mode, 3 passes): `Composite`, `RenderingFrame`(n/a), `FireAnimationFrame`,
`ObserverCallback`, `EventDispatch` det; `RecalculateStyles` stable at tolerance 1 per step; `Layout`, `Paint`, `InvalidateLayout`
quarantined per step (spread 2-3), stable at total. Under `hold`: `TimerFire`, `FunctionCall` det as well. Census: layer
counts and per-reason counts deterministic (88 or 16 in both passes); **backing bytes quarantined** at every state (pass 1 has
46.3 / 36.3 / 28.3 MB at y = 0 / 1500 / max, pass 2 38.4 / 32.8 / 25.3 MB, same in all four configs: the second load of a
process uses less), cumulative `paintCount` and the layer set (bytes) quarantined, the paint delta in a 2 s window deterministic.

Mean totals per run (hold, 3 passes; range in brackets only where it differs):

| config | RecalcStyles | Layout | Paint | FireAnimFrame | FunctionCall | Composite |
|---|---|---|---|---|---|---|
| default | 164.3 (163-165) | 118.0 | 166.0 | 222 | 296 | 147 |
| `engine.scroll:batched` | **145.0** (145) | 99.7 | 167.3 | 222 | 296 | 147 |
| `nav.hitTest:hit-skip` | **19.0** (19) | 120.0 | 168.0 | 222 | 296 | 147 |
| `hero.countdown:strip` | 162.7 | 120.7 | 154.0 | **296** | **370** | 147 |

fwcore (`handoff`, ops `screen` and `ticks`; `Fw.Screen.screen`, `Fw.Frames.tickAt`): variant vs default for every pair of the
3 + 3 passes (9 pairs) plus the noise floor (default vs default, variant vs variant) at three frame granularities (step / 500 px
zone / whole run):

| vector | batched | hit-skip | strip |
|---|---|---|---|
| all 12 counts, per step/zone/total | mixed 27/27 | mixed 26/27 (1 dominates) | mixed 27/27 |
| noise floor (default vs default) | mixed or equal | mixed or equal | mixed or equal |
| deterministic/stable columns only (RecalculateStyles, Composite, FireAnimationFrame, EventDispatch, FunctionCall, ObserverCallback) | total: **dominates 9/9**; step: dominates 4/9, mixed 5/9 | **dominates 9/9 at step, zone and total**, and variant-vs-variant `equal` 3/3 | mixed 9/9 (worse 2/9 at total); more rAF and FunctionCall |

So: with all 12 columns the screen is `mixed` even for two runs of the same config (Layout/Paint/InvalidateLayout noise), i.e. a
screen on the full vector cannot call a result; restricted to columns that are deterministic or stable it separates the
variants cleanly: **hit-skip dominates** (style recalcs 164 -> 19, nothing else changes) and **batched dominates at total**
(style 164 -> 145, layout -118 -> 100), **strip does not** (countdown strip adds 74 rAF callbacks and 74 function calls, one per
step; paint is lower, 166 -> 154). The choice of columns is the caller's (a vector must be declared complete for the mechanism,
PLAN class W), not made here. `ticks` (hz 60) on Composite start gaps: 146 gaps -> 149-152 ticks per run, 1-4 gaps above 34 ms;
these are **simulator-host times on a loaded Mac**, shown only to exercise the op.

Comparable with the original? **Only counts per mechanism, not values.** The placeholder is shorter (74 vs 107 steps, so
`screen` returns "frames or count vectors not aligned" between the two), has no images, no third-party loader and other DOM
sizes, so absolute counts, layer counts and bytes differ by construction; what carries over is the lane (hydrated build, pinned
clock, same drivers), the determinism classes, and the direction/size of a flag's effect on one page. Seek-fixture rows were
also produced (the `--no-seek` flag was parsed as a negation by mistake in these runs, fixed afterwards) and are
deterministic, as before.

## Feasibility: WKTR and `window.internals` on this Mac (research only, nothing built)

Facts (CONFIRMED unless marked):

- Host: MacBookPro18,3 (M1 Pro, 8 cores, 16 GB), macOS 27.0.1, Xcode 27.1 (27A9275), iOS 27.0 and 26.5 simulator runtimes
  installed, **38 GB free** on the data volume (research note 04 saw 69 GB earlier the same day). The Metal toolchain
  component reports `uninstalled` (`xcodebuild -showComponent MetalToolchain`), which WebKit's build docs require
  (`xcodebuild -downloadComponent MetalToolchain`).
- Source: `WebKit/WebKit` is reported by GitHub as 13.2 GB (`size` 13,192,724 KB, full history). A shallow checkout was not
  tried. There is no prebuilt: `webkit.org/build-archives` offers macOS-only release archives (Tahoe, Sequoia, Sonoma; newest
  324037@main of 2026-10-17); nothing for the iOS Simulator or WebKitTestRunner, and no macOS 27 section yet.
- Commands: `Tools/Scripts/build-webkit --release --ios-simulator`, then `Tools/Scripts/run-webkit-tests --ios-simulator
  --release <test>`; `run-safari --ios-simulator` runs the build in the Simulator. WKTR for iOS exists on main
  (`Tools/WebKitTestRunner/ios/`: `TestControllerIOS.mm`, `PlatformWebViewIOS.mm`, `UIScriptControllerIOS.mm`, `HIDEventGenerator.mm`, ...).
- Build time and size are **not documented** by WebKit; the earlier estimate (research 04 section 5) is 2-5 h and 40-60 GB of
  products plus the checkout, with peak RAM reported at 32 GB on a 20-core Mac Studio. INFERRED for this 16 GB machine:
  cap jobs at 4-6, expect swapping, 3-6 h; the 38 GB free do not fit it. Trunk may not build against Xcode 27.1 / SDK 27.1
  without changes (the CI fleet in the archive page lists macOS up to Tahoe): UNKNOWN until tried.
- What it would add (`Internals.idl` on main, fetched 2026-10-17, all present): `lastStyleUpdateSize` (restyled **elements**,
  the term the Inspector records lack), `styleRecalcCount`, `styleInvalidationTraversalCount`, `layoutUpdateCount`,
  `renderingUpdateCount` (the count `RenderingFrame` would give, missing on 27.0), `compositingUpdateCount`, `layerFlushCount`,
  `startTrackingRepaints` + `repaintRectsAsText`, `acceleratedAnimationsForElement` (`isThreaded`), `requestAnimationFrameInterval`,
  `setLowPowerModeEnabled`. And, INFERRED from the test tooling, an in-process step lock (`UIHelper.renderingUpdate()` waits for
  exactly one rendering update) with no inspector round trips, which is what the `lock` mode here tried to imitate and could not.
- What it would not add: Mobile Safari (no toolbar, different default viewport unless set per test), the shipping iOS 27.0
  WebKit (counts come from a trunk build, so a calibration run comparing Timeline counts with `internals` counts on one
  fixture is needed before anything is mixed), phone time.
- Recommendation: keep the Inspector lane for CI, and run the WKTR spike on a cloud Mac or after freeing >= 120 GB (PLAN Q10),
  starting with a shallow/partial clone (`git clone --depth 1 --filter=blob:none`) and `build-webkit --release --ios-simulator`
  with `-j4`; the first deliverable would be `lastStyleUpdateSize` and `renderingUpdateCount` per scroll step on the fixtures.

## Host load or engine on the CI runner (webkit-quiet, 2026-10-18)

Full write-up: `research/notes/2026/10-18-webkit-quiet.md`. Commands: `quiet --arms 0,6,12 --reps 3` (dose-response: busy-loop
processes during the scroll, `top` at 1 Hz and the harness timer lag recorded per pass; `src/quiet.mjs`, `src/hostmon.mjs`),
`quiet-report <quiet.json>` (arm tables and count-vs-step-duration correlation; `src/quietreport.mjs`),
`merge <sessions...> --out classes.json` (also writes the class table JSON). Workflow dispatch: `experiment=quiet`.

- More host load (up to 12 burners) does not slow the steps or raise any type's jitter; the runner is already at 0 % idle
  from the Simulator's own services. Only `TimerFire` follows pass wall time (r 0.93). The rest of the jitter is not load.
- The quiet-step rule (`lean/Fw/Measure/Quiet.lean`, op `measure.quietSteps`, `src/quietsteps.mjs`) is proved and tested but
  gives no better table on this runner.
- Class table over 3 independent CI sessions (49 deterministic / 9 stable / 46 quarantined of 104 rows):
  `classes/webkit-sim-v1.json`. Gateable per zone: `RenderingFrame`, `Composite`, `EventDispatch`.

## Limits

- `scrollTo` is not a finger: tile counts (which depend on scroll velocity) are not measured here.
- Simulator layer counts and records are mechanism evidence for iOS 27.0's WebKit on the Mac host; not phone counts.
- n = 2 passes per session is the minimum for a class; "deterministic" means identical in 4 of 4 passes.
- `--clock pinned` changes what runs (a frozen countdown): the classes above are for the pinned page.

## For the Lean spec (CLAUDE.md "Lean first")

All reduction after raw rows is in `src/reduce.mjs` (pure, no I/O) and has unit tests (`test/reduce.test.mjs`); it
needs a Lean spec and golden vectors, and none of it is a verdict, landing class or gate:
`quadArea`, `flattenRecords`, `tally`, `markTimes`/`markTime`, `bucketBySteps`, `reduceSteps`, `zones`,
`classify` (+ `TOL`), `symDiff`, `layerKey`, `summarize`. **Lean spec landed:** `lean/Fw/Measure/WebKit.lean` specifies `quadArea`, `tally`, the step join
(`bucketBySteps`/`reduceSteps`), `zones`, `classify`, `symDiff` and `summarize` (fwcore ops `measure.webkit.*`,
`measure.classify` mode `cells`, `measure.symDiff`, `measure.summarize`); `test/fwcore.test.mjs` checks every golden
line in `packages/contracts/golden/measure/` against both fwcore and these TS functions. `flattenRecords`,
`markTimes`/`markTime` and `layerKey` are extraction and stay unspecified. The existing `fwcore` ops (`ticks`, `screen`, `verdict`,
`cost`) are not used: nothing here is a frame tick, a dominance screen, a verdict or a cost.
Raw schemas are documented at the top of `reduce.mjs` (`fw.webkit.records/1`) and in `scrollrun.mjs`
(`fw.webkit.scroll/1`), `seek.mjs` (`fw.webkit.seek/1`): per-step records as plain JSON, `[type, start, end, clip|mark]`.

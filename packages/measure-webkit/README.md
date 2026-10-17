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
pnpm --filter @fw/measure-webkit sim -- down                    # shut the device down (every command already does)
pnpm --filter @fw/measure-webkit test                           # 15 unit tests, no Simulator needed
```

Every command boots the device headless, serves the **read-only** snapshot (`snapshot/site` of the main checkout, or
`$FW_SNAPSHOT_SITE`) on `127.0.0.1` with `Cache-Control: no-store`, runs, stops the proxy and the server and shuts the
Simulator down (`--keep` leaves it booted). Results go to `out/` (gitignored) as JSON. Nothing of the snapshot is
copied. Options: `--clock pinned|live` (default pinned), `--hold`, `--settle`, `--window`, `--step`, `--frames`,
`--ns`, `--vendors off|live`, `--out`.

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

## Limits

- `scrollTo` is not a finger: tile counts (which depend on scroll velocity) are not measured here.
- Simulator layer counts and records are mechanism evidence for iOS 27.0's WebKit on the Mac host; not phone counts.
- n = 2 passes per session is the minimum for a class; "deterministic" means identical in 4 of 4 passes.
- `--clock pinned` changes what runs (a frozen countdown): the classes above are for the pinned page.

## For the Lean spec (CLAUDE.md "Lean first")

All reduction after raw rows is in `src/reduce.mjs` (pure, no I/O) and has unit tests (`test/reduce.test.mjs`); it
needs a Lean spec and golden vectors, and none of it is a verdict, landing class or gate:
`quadArea`, `flattenRecords`, `tally`, `markTimes`/`markTime`, `bucketBySteps`, `reduceSteps`, `zones`,
`classify` (+ `TOL`), `symDiff`, `layerKey`, `summarize`. The existing `fwcore` ops (`ticks`, `screen`, `verdict`,
`cost`) are not used: nothing here is a frame tick, a dominance screen, a verdict or a cost.
Raw schemas are documented at the top of `reduce.mjs` (`fw.webkit.records/1`) and in `scrollrun.mjs`
(`fw.webkit.scroll/1`), `seek.mjs` (`fw.webkit.seek/1`): per-step records as plain JSON, `[type, start, end, clip|mark]`.

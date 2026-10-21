---
id: 2026-10-21-webkit-lag-probe
kind: note
title: "WebKit lag probe: where the Simulator spends its work in the two Safari lag regions, original against faithful"
status: final
created: 2026-10-21
authors: [agent:measure-engineer]
topics: [measurement, webkit, lag, attribution]
---

# WebKit lag probe (2026-10-21)

Question: in the two regions where Safari lags, which counters and which parts carry the work, and how does the
faithful rewrite (default preset, no flags) compare with the original? Region **A** is the hero cards moving out
(`y <= vh`). Region **B** is the end of the page: the last viewport of the stepped scroll (`y >= maxY - vh`) and the
nav morph that a wheel push at the end of the page opens and closes. Calm (`2vh < y < maxY - 2vh`) is the baseline.

**Accepted limits.** Simulator WebKit (iOS 27.0, 430x775 CSS px, DPR 3), not a phone. No candidate fix here; later
candidates are judged against the ranking below.

## Measured

- **MEASURED** on CI, `webkit-sim.yml` dispatch with `lag=true`, `target=both`, `vms=3`, branch `ci/webkit-lag-probe`:
  - run 39511908073: 3 jobs per arm (`v1..v3` original, `r1..r3` rewrite), each 1 geometry load, then 2 x (stepped scroll + morph run). 6 scroll passes and 6 morph passes per arm. Every number below is this run.
  - run 39503100190: cross-check, `v1 v2 r1 r3` finished (`v3`, `r2` lost to a stalled Simulator before the probe kept partial runs). Its rankings agree with run 39511908073 in every region (same first counter, same first part).
- Classes are `classify` over the per-pass region sums (`TOL.zone`, kMax 4, tMax 24) of 6 passes from 3 separate jobs. Counts per step are the window mean.

## Counters, ranked by excess over the calm baseline

Excess of a counter in a window = sum over the window minus (window steps x calm mean); a counter ranks when it is
positive. Ranking is `Fw.Measure.WebKitLag.rankWindows` (`rankDesc_sorted`, `excess_pos_iff`), golden `webkit-lag.jsonl`.
`paintArea` = sum of the Paint clip areas (css px^2) of a step, the one extra column.

Per step, window against calm (ratio, class):

| window | arm | rank 1 | rank 2 | rank 3 | rank 4 |
|---|---|---|---|---|---|
| A, scroll | original | paintArea 1.17M vs 0.81M (1.4, quar.) | Paint 17.7 vs 10.4 (1.7, quar.) | InvalidateLayout 8.4 vs 4.6 (1.8, stable) | Layout 8.5 vs 6.4 (1.3, stable) |
| A, scroll | faithful | paintArea 0.95M vs 0.66M (1.4, stable) | Paint 17.9 vs 9.3 (1.9, quar.) | FunctionCall 25.9 vs 17.6 (1.5, quar.) | EventDispatch 20.8 vs 12.8 (1.6, quar.) |
| B, scroll | original | Paint 12.8 vs 10.4 (1.2, quar.) | InvalidateLayout 5.3 vs 4.6 (1.1) | TimerFire 1.3 vs 1.1 (1.2) | |
| B, scroll | faithful | Paint 13.6 vs 9.3 (1.5, quar.) | InvalidateLayout 6.1 vs 4.5 (1.4, quar.) | ObserverCallback 0.86 vs 0.51 (1.7, stable) | |
| B, morph open | original | paintArea 95.6k vs 8.6k (11.2, quar.) | Paint 9.8 vs 3.6 (2.7, quar.) | InvalidateLayout 2.15 vs 2.00 | Layout 1.11 vs 1.00 |
| B, morph open | faithful | paintArea 74.8k vs 8.6k (8.7, quar.) | Paint 6.9 vs 3.6 (1.9, quar.) | FunctionCall 2.6 vs 2.1 (1.2) | EventDispatch 1.3 vs 1.0 (1.3) |
| B, morph close | original | paintArea 120k vs 8.6k (14.0, quar.) | Paint 10.2 vs 3.6 (2.8, quar.) | Layout 1.32 vs 1.00 (1.3) | InvalidateLayout 2.3 vs 2.0 |
| B, morph close | faithful | paintArea 99.8k vs 8.6k (11.7, quar.) | Paint 8.8 vs 3.6 (2.4, quar.) | FunctionCall 3.1 vs 2.1 (1.5) | EventDispatch 1.8 vs 1.0 (1.8) |

- Composite stays within 1.1 of its baseline in every window (deterministic in the morph), so it does not rank: the lag is not more compositor commits, it is more paint per commit.
- Style recalculation (RecalculateStyles, ScheduleStyleRecalculation) stays within 1.3 of calm in A and below calm in B: not a lag counter here.
- The rewrite's extra FunctionCall and EventDispatch in A and in the morph are its scroll and morph handlers; they rank below paint area and Paint.

## Paint attribution to parts (paint area per pass, css px^2; INFERRED join, see Method)

| window | original | faithful |
|---|---|---|
| A, scroll | people 7.97M (leaf: people-profile 6.1M), (none) 6.65M, hero 3.63M, nav 0.51M | pain 4.66M (pain-notes), (none) 4.54M, hero 3.62M, people 1.82M, nav 0.5M |
| B, scroll | platform 3.58M, nav 0.41M | platform 3.79M, morph 0.37M |
| B, morph open | nav 5.36M (563 paints), platform 0.28M | nav 2.93M (288 paints), morph 1.17M (100 paints), platform 0.22M |
| B, morph close | platform 6.02M (482 paints), nav 1.18M | platform 4.99M (303 paints), morph 0.83M (192 paints) |

- In A the original repaints the people/profile showcase most; the faithful one splits it across pain, hero and people. Both leave about a third of the area unattributed (`(none)`: no part box covers half of the clip: full-page background and ancestors).
- In B scroll the platform section dominates in both arms (90 percent of the paint area).
- In the morph the open nav panel is repainted on every frame in the original (563 nav paints per pass over 60 frames, 9.4 per frame); the rewrite does 288 nav paints plus 100 morph paints (4.8 + 1.7 per frame). The platform repaints when the panel closes.

## Filter and backdrop-filter layers

Elements with a computed `filter` or `backdrop-filter`, their visible area in the viewport and area x blur radius, at the geometry steps (untimed pass, so INFERRED for the morph):

| window | visible elements | visible area (px^2) | area x radius |
|---|---|---|---|
| calm | 4.3 | 70.7k | 734k |
| A, original / faithful | 4.1 / 4.0 | 126k / 143k | 1.41M / 1.45M |
| B scroll, both | 6.9 | 457k | 1.68M |
| morph open, both | 5.1 | 959k | 4.0M |
| morph close, both | 6.0 | 403k | 0.8M |

The open menu panel is the largest filtered area of the page: 13.6 x the calm area (958.7k against 70.7k px^2). LayerTree census (untimed, `Layers` block of the report, faithful arm): about 118 to 145 layers and 52 to 98 MB of backing, 3 to 4 filter or backdrop layers.

## Method

- Lane: `packages/measure-webkit/src/lag/` (probe `probe.mjs`, join and format `report.mjs`, reductions `reduce.mjs`, CLI `cli.mjs`). Timeline records are cut into steps by `performance.mark('wk:s<k>')` (the lane's step marks). Scroll run = the lane's stepped scroll. Morph run at the end of the page: 10 idle frames, a synthetic `WheelEvent` (delta +120) on `document.body`, 60 frames, a `WheelEvent` of -120, 60 frames, one rAF per step mark.
- The morph is real: in the sampling pass the nav box grows to the full viewport around frames 10 to 12 and shrinks back around frames 70 to 78 (nav active frames 60 open, 4 to 5 close in the table windows). The page does not call `window.scrollTo` for it (0 calls), and `--morph` reads 0 before and after because it is sampled after the close.
- Paint attribution: a Paint record is joined to the smallest part box that covers at least half of its clip; leaf parts roll up to the name before the first `-`. Boxes come from an untimed geometry pass (`getBoundingClientRect` at every scroll step; for the morph, a second pass with the same frame schedule). The original's parts are a selector table, the rewrite's are its `[data-fw]` elements. **INFERRED**: the geometry pass is another load, so the morph frame k of the sampling pass is not the timed frame k.
- Why not the node id: `PageTimelineAgent::didPaint` adds `nodeId` only when `nodeIdForRenderer` finds a persistent DOM agent id (inside `didPaint`, PageTimelineAgent.cpp:285-310@862f17dcae0a); with no DOM agent attached it is absent. Follow-up: enable the DOM agent and read the id.
- The Paint quad is in document coordinates although the source calls it root view: `contentsToRootView` goes through `ScrollView::contentsToView`, which returns the point unchanged when the native view scrolls (ScrollView.cpp:989-993@862f17dcae0a, `delegatesScrollingToNativeView()`), as it does on iOS. **MEASURED** in a local debug run (not a result): the clips stayed in document coordinates while the part boxes moved with the scroll. The first version of the report did not shift by the scroll position and put everything in `(none)`; it was fixed before the CI runs.
- The page is 36 px shorter in some loads (docH 6006 against 6042, maxY 5231 against 5267, in both arms), so geometry and timed loads can have different step counts; a timed step takes the boxes of the geometry step with the nearest y.

## What each counter means (WebKit 862f17dcae0a)

| counter | record | source |
|---|---|---|
| RecalculateStyles | one style recalculation pass | PageTimelineAgent.cpp:237-254 |
| ScheduleStyleRecalculation | a style recalculation was requested | PageTimelineAgent.cpp:227-235 |
| Layout | one layout pass | PageTimelineAgent.cpp:205-225 |
| InvalidateLayout | a layout was requested (a node was marked dirty) | PageTimelineAgent.cpp:195-203 |
| Paint | one backing-layer paint; clip = dirty rect of that layer | RenderLayerBacking.cpp:4164 and :4198, PageTimelineAgent.cpp:285-310 |
| Composite | one rendering-update display commit | Page.cpp:2587-2609, PageTimelineAgent.cpp:256-283 |
| RenderingFrame | a rendering frame boundary; always 0 on 27.0 | PageTimelineAgent.cpp:126-155, 359 |
| FireAnimationFrame | one requestAnimationFrame callback | InspectorTimelineAgent.cpp:511-518 |
| TimerFire | one timer callback | InspectorTimelineAgent.cpp:305-312 |
| ObserverCallback | one observer callback (resize, intersection, mutation) | InspectorTimelineAgent.cpp:521-528 |
| EventDispatch | one event dispatch | InspectorTimelineAgent.cpp:278-292 |
| FunctionCall | one script function call from native code | InspectorTimelineAgent.cpp:268-275 |
| paintArea | ours: sum of the Paint clip areas, css px^2 | derived from the Paint records |

Not measured, so not claimed: image decodes, style resolution counts, layers created per frame, paint cost in ms (the Simulator's timings are not a phone's).

## Proved and checked

- `lean/Fw/Measure/WebKitLag.lean`: owner (smallest covering box: `owner_smallest`, `owner_covers`, `owner_empty`), regions (`regionOf_a`, `_b`, `_calm`, `_other`), ledger totals (`regionLedger_area_total`, `byKey_total`, `rollup_total`), filter totals, ranking (`excess_pos_iff`, `rankDesc_sorted`, `rankDesc_perm`).
- Golden `packages/contracts/golden/measure/webkit-lag.jsonl` (29 lines, generated by `lean/scripts/WebkitLagGolden.lean`, checked in `lean/scripts/check.sh`); the TS twin `src/lag/reduce.mjs` is checked against it in `test/lag-reduce.test.mjs`.
- **TS stand-ins (no Lean golden):** the in-page JS (`SAMPLE_SRC`, `MORPH_JS`), `clipRect`/`clipsPerStep` (unit and coordinate shift), the nearest-y join in `scrollSteps`, the means, ratios and class columns of `report.mjs`, the Markdown, and the retry/partial-run handling in `probe.mjs`. They are covered by `test/lag-report.test.mjs` on synthetic runs only.

## Follow-ups (not in this task)

1. Read paint ownership from the DOM agent node id instead of the box join.
2. Judge each candidate fix against the rank 1 and 2 rows above (paint area and Paint in A and the morph; Paint and InvalidateLayout in B scroll).
3. Time per paint on a real phone (a booked session) before any fix is called faster.
4. Why the page is 36 px shorter in some loads.

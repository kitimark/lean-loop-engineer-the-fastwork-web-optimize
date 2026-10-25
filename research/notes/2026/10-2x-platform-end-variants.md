---
id: 2026-10-2x-platform-end-variants
kind: note
title: "platform.* at the end of the page: step 1, which parts do work (measure before building)"
status: draft
created: 2026-10-26
authors: [agent:part-builder]
topics: [platform, sweep, glint, entries, fade-threaded, end-of-page, webkit, chromium]
---

# platform.* at the end of the page: step 1 (task platform-end-variants)

## Answer first

- None of the three existing un-measured variants wins at the page end, on either engine, by the Lean verdict rule
  (`noGain` in every finish zone and push phase; table below). MEASURED.
- The variants cannot answer the step-2 question anyway. `sweep:offscreen-pause` and `glint:offscreen-pause` are no-ops
  by construction while the section is on screen, and at the page end it is on screen until the push fades it. So
  "equal counts" says the pause saves nothing there; it does not say the sweep or glint cost nothing there. INFERRED.
- Step-2 premises, one line each (details in the last section):
  - (a) `platform.sweep:layer-sweep`: premise **not measured**. The base does raster work in the first 60 frames at the
    end (971 raster tasks over 60 frames), but no arm separates the sweep from the rest of the push. From frame 60 on the
    base does 0 raster tasks, so the sweep costs nothing once the fade has finished.
  - (b) `platform.glint:transform`: premise **not measured**, and weaker: the faithful arm already unmounts the SMIL
    pair below ratio 0.35, and the pause arm changes no count on either engine.
  - (c) `platform.entries:contain`: premise **not measured**: no arm toggles the entries at all. The base does 46
    layouts in the first 60 frames at the end; the entries share that with nav, panel and columns.
  - What would make all three measurable is one attribution arm per part (part off, for measurement only). That is a
    step-2 prerequisite, not built here.
- `platform:fade-threaded` on Chromium is a no-win: it moves Paint and PrePaint work from frames 0-19 to frames 20-59 at
  the end, and raises the raster invalidation area 2.1x (292 M px against 137 M px over the zone) and the layer count
  by 0.6 %. MEASURED. Chromium column in the ledger: `unknown` becomes `no-win`.
- WebKit: sweep and glint show no effect on any counter in the Simulator, except `ObserverCallback` +2 to +4 per zone
  for sweep (its own IntersectionObserver callbacks; the Lean verdict reads this as `more`). MEASURED.
- The WebKit lane (`webkit-sim` through `fw run`) is scroll only; it has no morph open or close push. The push phases
  below are Chromium's (`swipe-touch-v1` keeps touching after the page end, and the morph push runs). A WebKit push
  split needs the lag/cost lane, which `fw run` has no input for. Not delivered here.

## Method

- Dispatch (all with `pnpm -s fw run --target rewrite --ref main`, main at 5c8cccc, code unchanged, so no `ci/*` push;
  14:45 to 14:47 UTC on 2026-10-25, 7 dispatches; webkit fade-threaded was not dispatched, it is a recorded WebKit no-win).

| lane | arm | run | result |
|---|---|---|---|
| chromium-counts, swipe-touch-v1, 3 runs | base | 40203753344 | success |
| chromium-counts | platform.sweep:offscreen-pause | 40203778407 | success |
| chromium-counts | platform.glint:offscreen-pause | 40203771621 | success |
| chromium-counts | platform:fade-threaded | 40203756095 | success |
| webkit-sim, 3 VMs, 430x775 | base | 40203774734 | r2, r3 success (4 passes); r1 cancelled after 58 min, run marked cancelled |
| webkit-sim | platform.sweep:offscreen-pause | 40203759230 | success (6 passes) |
| webkit-sim | platform.glint:offscreen-pause | 40203790654 | success (6 passes) |

- The WebKit jobs queued 1 h 50 min to 5 h for a macOS runner. The three `fw run` waiters for WebKit exited 1 ("nonce
  matches several runs (id, id); not guessing"): the same run id listed twice. The runs themselves were fine and were
  read with `fw ci wait <id>` and `gh run download`; no refile into the store. The duplicate listing is a poller bug,
  reported in `open`.
- Chromium: frames of `counts.json`, finish window = frames 540 to 740 (201 frames): zone `y05000` of the run's `zones.json`
  (frames 540-738, 191 swipe frames) plus 10 settle frames (581-584, 663-666, 739-740). The lane's own zone sums
  (`zones.json`) are shown as a separate row. The page end is reached at frame 574 in all 12 runs (scrollY 5342). Push phases are windows from the first frame at the end:
  approach (34 frames before it), end 0-19, end 20-59, end 60-119, end 120+ (47). The window edges are mine (INFERRED:
  the profile has no marks for the morph push); they are the same in every arm because the profile is deterministic.
- WebKit: `perStep` counts of `passes[].scroll.reduced`, zones by scroll y: z4500 (y 4500 to 4950, 10 steps), z5000
  (the page end). The passes do not end at one y: 2 of 4 base passes, 2 of 6 sweep passes and 3 of 6 glint passes end
  at y 5267 (107 steps); the others end at y 5231 (106 steps). The Lean rule needs one window (`sameWindow`, else
  `noData`), so every WebKit table is cut to the common window y <= 5200: z5000 = y 5000 to 5200 (5 steps), finish =
  y 4500 to 5200 (15 steps), whole run = 105 steps. Census layer counts per y are read as before.
- Verdict rule: the Lean `Fw.Measure.Offscreen` comparison, per counter `cmp` of the spread (lo-hi) of the repeats with
  slack 0, then `judge`: any `more` is `noGain`; else any `less` is `gain`; else `noGain`
  (`judge_more`, `judge_gain`, `judge_same`). The code is the golden-checked twin in
  `packages/measure-chromium/src/offscreen.mjs` (`cmp`, `judge`). TS stand-in: the key subset (the lane has no
  `BeginMainFrame`, `NeedsTick`, `TickAnimations`, so `verdict` itself would say `noData` through `hasKeys`) and the
  zone sums are scratch scripts (`scratchpad/pev/ch.mjs`, `wk.mjs`, not committed). Chromium keys: RecalcStyleCount,
  LayoutCount, UpdateLayoutTree, Layout, PrePaint, Paint, Commit, cc.Draw, FireAnimationFrame. WebKit keys:
  RecalculateStyles, Layout, Paint, Composite, FireAnimationFrame, TimerFire, ObserverCallback, InvalidateLayout,
  ScheduleStyleRecalculation. Raster counters and the invalidation area are shown, not in the verdict.

## Result: Chromium, base work and verdicts per push phase

Base sums per run (3 runs, identical spread except where a range is written), then the verdict of each arm.

| phase (frames) | Paint | Layout | RasterTask | invalidation Mpx | sweep | glint | fade-threaded |
|---|---|---|---|---|---|---|---|
| approach (34) | 114 | 6 | 236 | 2.16 | noGain: RecalcStyle 130 vs 129 (more); RasterTask 177 (-59), area -0.30 | noGain, all same | noGain, all same |
| end 0-19 (20) | 335 | 21 | 517 | 18.8 | noGain, all same (area -0.04) | noGain, all same | gain: Paint 312, PrePaint 65 vs 91 (less); area 22.0 (more), layers 4712 vs 4454 (more), RasterTask 441 (-76) |
| end 20-59 (40) | 252 | 25 | 454 | 37.4 | noGain, all same | noGain, all same | noGain: Paint 275, PrePaint 92 vs 66 (more); area 60.2 (more) |
| end 60-119 (60) | 120 | 0 | 0 | 44.4 | noGain, all same | noGain, all same | noGain: area 116.5 (more) |
| end 120+ (47) | 94 | 0 | 0 | 34.8 | noGain, all same | noGain, all same | noGain: area 91.3 (more) |
| finish window, frames 540-740 (201) | 915 | 52 | 1207 | 137.4 | noGain (+1 RecalcStyle, +1 UpdateLayoutTree) | noGain | noGain (RasterTask 1131 less, area 292.1 more) |
| zone `y05000` (191, lane sums) | 838 | 48 | 1112 | 130.0 | noGain (RecalcStyle and UpdateLayoutTree 304 vs 303, more; RasterTask 1053, less) | noGain, all same (RecalcStyle 303-304 vs 303) | noGain (Paint 861 vs 838 and PrePaint 350 vs 324, more; RasterTask 1063, less; area 276.6, more) |

Reading:
- The fade-threaded `gain` of the first push phase is not a gain over the zone: the Paint and PrePaint that it removes
  from frames 0-19 (23 and 26) come back in frames 20-59 (23 and 26), and the invalidation area is higher in every
  phase from the first frame at the end on (+17 %, +61 %, +163 %, +163 %). The unit of decision is the phase table and
  the finish zone together; the lane zone `y05000` says `noGain` (Paint 861 vs 838 and PrePaint 350 vs 324 are more in
  all 3 runs). Over the 201-frame window they are equal (915, 375) because the end 0-19 drop falls entirely in settle
  frames 581-584, which the lane zone does not contain. MEASURED.
- The sweep's one measured effect is outside the end: 59 raster tasks fewer in the approach (236 to 177, all 3 runs
  alike), which is the pause working while the section is not intersecting. It costs one style recalculation, which the
  Lean rule reads as `more`. MEASURED. At the end it does nothing (equal in all 3 runs of every end phase).
- Glint: every counter equal in every phase (FireAnimationFrame 141 to 142 in end 20-59 is inside the range). MEASURED.
- From 60 frames after the page end the base does no raster and no layout; the platform parts cannot cost anything
  there. The remaining 2 Paint and 1 style per frame are the held touch. MEASURED.

## Result: WebKit Simulator, scroll zones

Base 4 passes (VMs r2, r3), sweep and glint 6 passes (VMs r1 to r3), min-max per zone, every pass cut to the common
window y <= 5200 (the page end is y 5231 in 106-step passes and y 5267 in 107-step passes; base 2+2, sweep 4+2, glint
3+3). `Paint` shown; every other counter is listed in the verdict row. Same Lean rule.

| zone | steps | base Paint | sweep Paint | glint Paint | sweep verdict | glint verdict |
|---|---|---|---|---|---|---|
| z4500 | 10 | 105-140 | 84-145 | 133-153 | noGain (ObserverCallback 12-16 vs 10, more) | noGain, all same |
| z5000 (to y 5200) | 5 | 54-64 | 37-55 | 60-67 | noGain (ObserverCallback 6 vs 4, more) | noGain, all same |
| finish (y 4500-5200) | 15 | 166-204 | 138-188 | 193-219 | noGain (ObserverCallback 18-22 vs 14) | noGain, all same |
| whole run (to y 5200) | 105 | 1290-1361 | 1212-1304 | 1234-1345 | noGain (ObserverCallback 69-74 vs 62-63) | noGain (Layout 624-653 vs 588-619, more) |

The verdicts equal those on the full passes (round 1 used mixed 106/107-step windows, where `sameWindow` fails and the
Lean `verdict` would say `noData`). MEASURED.

- Sweep Paint at the page end is lower in the means (37-55 against 54-64) but the ranges overlap at 54-55, so the rule
  says `same`. A larger sample could turn this into a `less`; with 3 VMs and the pass-to-pass spread of the base it is
  not a measured gain. MEASURED, inside noise.
- Composite 10, 20, 30 and 209 (zone, zone, finish, whole) are equal in all arms (stable class). Census layer counts
  per y are equal within the VM-to-VM spread (4500: base 141-146, sweep 141-146, glint 141-150). Passes that end at
  y 5267 have no step at y 5231, so that cell has only the 106-step passes (blank in the others). MEASURED.
- WebKit scroll steps never reach the morph push, so this table covers the platform section on screen during the last
  steps, not a push. On WebKit no part has an effect in the end zones of the scroll lane.

## Verdict per existing variant (Lean rule)

| variant | Chromium | WebKit Simulator | ledger today | note |
|---|---|---|---|---|
| platform.sweep:offscreen-pause | noGain (finish zone) | noGain (all zones) | unknown / unknown | pause is a no-op while visible; one extra observer and recalc |
| platform.glint:offscreen-pause | noGain | noGain | unknown / unknown (negative) | agrees with the proved `faithful_no_ticks_away` |
| platform:fade-threaded | noGain (area 2.1x) | no-win (recorded) | unknown / no-win | Chromium column now `no-win` (ledger field `chromium`) |

## Step-2 candidates and their premise

A premise is "the part does work at the page end", with the end meaning the push window in which the section is still
visible (frames 0-59 after the end on Chromium).

| candidate | premise status | evidence | what is missing |
|---|---|---|---|
| (a) sweep layer-sweep | not measured; plausible | the base rasters in frames 0-59 (971 tasks); the sweep's pause saves 59 of 236 raster tasks before the end, so the sweep paints when it plays; at frames 60+ raster is 0 | an arm without the sweep inside the push window |
| (b) glint transform | not measured; unlikely | pause arm equal on both engines; unmount below ratio 0.35 is already in the base (`faithful_no_ticks_away`) | an arm without the glint, or a SMIL tick count in the push window |
| (c) entries contain | not measured | the base lays out 46 times in frames 0-59 (nav, panel, columns, entries together); no entries toggle exists | an arm with the entries frozen, and a layout owner per box |

Recommendation: build an attribution arm per part first, measurement only, one flag each (`platform.sweep:off`,
`platform.glint:off`, `platform.entries:off`, same DOM, animation or writes removed), run Chromium swipe-touch-v1 x3 and
WebKit x3, then build only the step-2 variant whose part moves a counter in frames 0-59. The sweep is the most likely
first, because the pause arm already shows it rasters. This is a follow-up round; nothing in step 2 is built here.

## Limits

- CI only, no phone (the Simulator stands in for the iPhone; phone checks come with phone-compose-counts).
- WebKit has no push, only scroll zones.
- WebKit base has 4 passes on 2 VMs (VM r1 was cancelled by the runner), the arms have 6 on 3 VMs; the ranges of the
  base are therefore a little narrower, which can only turn a `same` into `more` or `less` for a flag, and no `less`
  appeared.
- `platform:mq` stays closed.
- Scratch scripts (`scratchpad/pev/ch.mjs`, `wk.mjs`) are not committed; the numbers can be rebuilt from the run ids
  above with `gh run download <id> -p 'chromium-counts-rewrite-r*'` or `-p 'webkit-sim-r*'`.

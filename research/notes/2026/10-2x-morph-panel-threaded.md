---
id: 2026-10-2x-morph-panel-threaded
kind: note
title: "morph.panel:threaded, the panel's opacity, blur and scale as three effects per morph push"
status: draft
created: 2026-10-23
authors: [agent:part-builder]
topics: [morph, panel, webkit, compositor, flags, negative-result]
---

# morph.panel:threaded (task morph-panel-threaded)

Question: while the nav morphs, the tween writes the panel's opacity, `filter: blur()` and `transform: scale()` on every
frame. Can one Web Animation per push (two effects: opacity with transform, and filter alone) show the same panel on
every frame, so a frame needs no layout, property-tree or paint work for the panel?

## What changes
- `apps/site/src/parts/morph.panel/threaded.logic.ts`: the keyframes of one push, from Lean `MorphPanelThreaded.track`
  (golden `morph-panel-threaded.jsonl`, 210 lines, checked by `threaded.test.ts`).
- `morph.tween/driver.ts` (`createPanelEffects`): the tween owns the animate calls, so the per-frame panel writes are
  skipped and the effects start at push time with `startTime` set to the push time.
- Flag read from `window.__fw.config.variants['morph.panel']` in `morph.tween/index.tsx`.
- Consequence for the footprint: the tween now writes morph.panel, so morph.panel is no longer isolated; the Lean
  literals of `Bridge.lean` (isolated 13 to 12, chain pairs) and `FootprintRows.lean` were regenerated.

## What is proved (Lean, `MorphPanelThreaded.lean`, `MorphPanelThreadedRun.lean`)
- `interp_eq`: linear interpolation of the keyframes at eased progress `p` equals the original's opacity, blur and scale
  at morph value `f + (t - f) p`; the keyframes bend where the panel progress bends (`kA` 2/25, `kB` 4/5; `chain_offs`,
  `interp_chain`, `zone_opacity`, `zone_blur`, `zone_scale`).
- `threaded_eq`, `frame_eq`: over any event list the shown panel equals the original's, under the WAAPI premises.
  `retarget_from_shown`: a push during a live effect starts at the value on screen. `reduced_run_none`: no effect under
  reduced motion.
- `ca_accepts`: every effect meets the Core Animation conditions (rate 1, forward, nonzero duration, two or more
  keyframes, curve in [0, 1]). `props_accelerated`: opacity, filter and transform are accelerated properties.
- `ease_err`: the engines' bisection of the cubic-bezier (1/3, 1, 2/3, 1) is within 3/2^41 of the tween's ease.
- `bands_only_reduced`, `bands_equal`, `band_no_effect_else`: each media band declares effects exactly in the band the
  original writes them.
- `variant_stages`, `variant_drops`, `variant_sub`: the original's three changes cost style, layout, props and paint per
  frame; the variant's tick costs style only. `recalc_same`, `recalc_same_bundle`: the style recalculation stays, since
  the nav `--morph` write is still made on every frame.
- `layer_budget`, `layer_budget_new`: the `animation` reason adds no layer when the panel is composited already.

## Results
Inputs read from each run (CI, ci/morph-panel-threaded, f0273f680 unless noted).

### Gate and look (Chromium)
| check | run | result |
|---|---|---|
| breakpoint-gate `--gate --engines both --fw morph.panel:threaded` | 39846842455 | pass (MEASURED) |
| lean | 39853827853 (46c718709), 39855506561 (5519b5509) | success (MEASURED) |
| trajectory-probe, four widths, Chromium | 39846814254 | RED: 84 `new` units, 0 content, 84 coverage (MEASURED) |
| trajectory-probe, widths 390,640 diagnostic, GPU cells with the flag | 39855506403 (5519b5509) | RED: 42 new, 0 content, w=640 open@1 coverage only; panel-effect E in 3 of 4 units (MEASURED) |

The three failing panel rows of the probe: of 152 measured panel steps, 149 pass; the failing ones are `open@1` at
w=390, w=640 and w=641 (MEASURED, `units-chromium.json`). `open@1` is the first tenth bucket of the push. Every node
fails there (42 units per width: nav, logo, earn, panel), not the panel alone.

Why they are a harness artifact (INFERRED from MEASURED samples, run 39846814254): the first sample after a push reads
m = 0.07 or m = 0.20, nothing between, depending on whether the first frame lands one or two frames after the push.
Only the 0.07 samples fall in bucket 1. Over the four widths and five reps, the first sample is 0.07 in 9 of 20 reps in
the original, 5 of 20 in the faithful rewrite and 5 of 20 in the threaded arm (the faithful arm misses the bucket at
w=640 too). The bucket is filled by chance of the frame phase, and the threaded arm is no worse than the faithful arm
in total. The docs call a coverage-only RED sampling noise (trajectory-probe.md, check 3).
A second, independent run of the same flag (39855506403, widths 390 and 640, five reps) is RED again with 42 `new` units,
0 content, all `open@1` coverage, but now at w=640 only: the width that failed moved from 390 to 640, and the faithful arm
had no failure (MEASURED). The unit that fails changes between runs, so it is the frame phase and not the flag.

The GPU cells (landed `gpu-trajectory-cells`, `panel-effect`) now take the push line's search (workflow step edited,
`--search "$SEARCH"`): 390 open E, 390 close E, 640 open E, 640 close L in 2 of 3 reps, lag max 0.013 frame. The L is a
reference artifact: reading the panel at each sampled frame, the threaded arm and the faithful arm both stay within
0.0006 (opacity), 0.0013 px (blur) and 0.0005 (scale) of the Lean model at all 8 width and phase cells (MEASURED, raw of
39855506403); the cell compares the candidate with a chord between the faithful arm's samples, and a chord across the
kink at m = 0.8 sits up to 0.02 (opacity) and 0.23 px (blur) off the exact value. In rep 2, with no sample near the kink, the cell is E. The lag is
far below one frame, so the flag does not go to the look-review class (accepted limit). Pixels are not measured: PathPix
grades any CA blur as not E (premise c6 open), and the Chromium lane reads computed style, which a compositor
animation does not change.

### Counts, Chromium (swipe-v1, three runs)
| arm | run | RecalcStyleCount | Animation.begin | Paint | Layout |
|---|---|---|---|---|---|
| const-bounds | 39851664186 | 1832 | 143 | 2493 | 358 |
| threaded | 39851674587 | 1832 | 143 | 2494 | 357 |

MEASURED. The profile scrolls and never opens the panel (Animation.begin is equal), so the lane cannot show a
difference; the flag adds no work outside a push. Blink does not composite a pixel-moving filter effect
(compositor_animations.cc:408-416@f842f52), so a push would run the blur on the main thread there (INFERRED).

### Cost, WebKit Simulator (lag=true cost=on, passes of r1 and r2 per arm, cost-report)
Composite per frame in ms, one value per pass. Reference arm const-bounds 39846941236, threaded alone 39846909558,
threaded with `platform:fade-threaded` 39846948148 (first four of six passes).

| zone | const-bounds | threaded | threaded + platform:fade-threaded |
|---|---|---|---|
| open push, ms per frame | 213, 151, 158, 169 | 275, 236, 425, 552 | 150, 308, 140, 176 |
| close push, ms per frame | 107, 118, 129, 148 | 142, 241, 250, 184 | 86, 208, 123, 92 |
| open push, frames | 3, 4, 3, 3 | 2, 3, 2, 2 | 4, 2, 4, 3 |

MEASURED. cost-report verdicts: open push threaded against const-bounds "higher" (ranges 236-552 against 151-213 ms,
no overlap); close push overlap; every other zone overlap, including Paint per frame on the open push (3.6-10.9 ms
against 4.5-6.1 ms) and the resized layers, except new layers per 100 reads on the close push (100 against 0, "higher", 2 reads per pass). The bundle overlaps the reference on every cell. Records in the morph pass:
RecalculateStyles 306-938 (threaded) against 442-2258 (const-bounds) and 324-1280 (bundle): the passes differ by a
factor of 3 inside one arm, so these are no evidence either way. The third vm of the threaded and const-bounds runs
(r3) had not finished when this was written; the table holds the passes that exist.

## Verdict (negative on cost, with its Lean why)
- The flag shows the same panel (look: `interp_eq`, `threaded_eq`, panel-effect E) and meets the Core Animation
  conditions (`ca_accepts`), but on the Simulator the open push costs more Composite per frame than the const-bounds
  arm, and nothing less elsewhere.
- Why (PROVED in the stage model, INFERRED for the cost): `variant_drops` removes layout, props and paint from the
  frame, and `variant_stages` keeps style, so the model says "less main-thread work". The model has no Composite stage:
  the blur moves from Paint to the compositor, which on the Simulator (no GPU) runs on the CPU. The panel box still
  grows with m (`Fw.Parts.MorphConstBounds.orig_resizes_h`, `orig_resizes_w`; the threaded flag does not touch the
  box), so the blurred layer is resized on every frame, and each resize re-renders the blur in the compositor. The
  const-bounds flag removes that resize and measured 100-148 ms against 176-181 ms in its own task.
- Lesson: a stage that leaves the main thread is not a saving when the work it did lands in Composite on a lane
  without a GPU; and moving the blur cannot beat removing the resize that drives it. A variant that removes both
  (effects on a constant-bounds panel) needs a new variant of one part, since flags of one part are exclusive; not
  built here.

## Accepted limits and follow-ups
- Safari on this Mac (real GPU, `gpu-safari-lane`) and the PathPix cell are follow-ups.
- Linux WebKit trajectory walks the hero path only (4000 of 4000 clean), no panel rows.
- Run 39846909558 and 39846941236 had one vm (r3) running at the time of writing.
- Workflow edit outside the task's writes: `.github/workflows/trajectory-probe.yml`, the GPU cells step passes the search.

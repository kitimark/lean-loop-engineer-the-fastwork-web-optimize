# accent-draw-nolayout: a draw whose frames need no layout in WebKit

Flag `hero.accent:draw-nolayout`, class look-change (the user reviews the look). Task hero-accent-draw-nolayout, ledger row n=55.
WebKit lines are @862f17d (`WC` = `Source/WebCore`), Chromium lines @f842f52 (`B` = `third_party/blink/renderer/core`).

## Cause (CONFIRMED from source)
Both 900 ms draws change `stroke-dashoffset` every frame. WebKit: `svgDataChangeRequiresLayout` compares
`strokeDashOffset` (`WC/style/StyleDifference.cpp:161`), called from `changeRequiresLayout` (`:399`), so each frame is a layout.
Chromium: `invalidate: ["paint"]` (`B/css/css_properties.json5:6120`); layout only when the stroke or the dash array appears or
disappears (`B/style/computed_style.cc:998-1006`). The draw-in adds the original's `width` transition of the host: layout in both
engines (`WC/style/StyleDifference.cpp:404`, `B/css/css_properties.json5:8286`).

## Candidates (Lean `Fw.Engine.StyleDiffAccent.row`, one table; golden `hero.accent.nolayout.jsonl`)
| change | WebKit level | WebKit layout | Chromium level | Chromium layout |
|---|---|---|---|---|
| stroke-dashoffset (faithful) | layout | yes | paint | no |
| clip-path inset() on the `<svg>` (chosen) | repaint | no | paint | no |
| transform of an SVG child (mask rectangle) | layout | yes | raster | no |
| transform on a composited box | recomposite | no | direct | no |
| opacity inside (0,1) | repaint | no | raster | no |
| opacity reaching 1 | layout | yes | raster | no |
| width | layout | yes | layoutFull | yes |

A mask rectangle moved by transform stays an SVG child without a layer: `RenderElement.cpp:300-312` raises it to Layout
(`transformSvgChild_wk_layout`). A transform on a composited box needs no layout (`transformOwn_nolayout`) but needs a layer per
wrapper (two nested wrappers for a moving clip edge); not chosen. A pre-split dash with opacity needs the opacity to reach 1 at
the end: one layout frame (`opacity_split`) and K paths in the DOM; not chosen. clip-path is `Equal` plus the ClipPath context
(`StyleDifference.cpp:779-780`) raised to Repaint, or RecompositeLayer, by `RenderElement.cpp:321-326`; the legacy SVG client hook
marks layout with `needsLayout = false` (`WC/rendering/svg/legacy/SVGResourcesCache.cpp:222`).

## Arm
`.accent[data-fw-draw='nolayout']`: in the draw window the path is static (`stroke-dasharray: none; stroke-dashoffset: 0; animation:
none`), and the visible copy `.frame0` runs `clipIn` / `clipOut` (0.9 s, the original easing, `forwards`): `clip-path: inset(-20% 120%
-20% -20%)` to `inset(-20% -20% -20% -20%)` and back. Nothing per frame in React state, `sx` or Emotion; the CSS animation runs on the
engine's own timeline. Faithful is unchanged (the new rules key on the attribute; test `drawNoLayout.test.ts`).

## Proof (Lean `Fw.Engine.StyleDiffAccent`, all by `decide` over the tables of `Fw.Engine.WebKit` and `Fw.Engine.Chromium`)
- `dashoffset_wk_layout` (every layer state), `dashoffset_cr_nolayout`, `clip_nolayout` (both engines, every layer state).
- `arm_drawOut_nolayout`: the arm's draw-out frame needs no layout in WebKit or Chromium.
- `arm_drawIn_layout_only_width`: the draw-in frame needs layout, and only through `width`.
- `faithful_drawOut`: faithful draw-out needs layout in WebKit and none in Chromium (so no Chromium win exists).
- `layoutPhases_values`: layout phases per cycle 2 to 1; `arm_phase_subset`.
- `clip_endpoints`: hidden end is an empty clip, shown end covers the box.

## Visual sameness (class look-change)
Not pixel-identical by construction: the arm wipes the whole word left to right; faithful traces the stroke. Start and end frames
agree (`clip_endpoints`). Pixel numbers: NOT MEASURED. The path-pix lane pins the accent chain (`?fwpin=accent`, note
10-2x-pathpix-accent-pin) and has no mode that samples the draw window; its `PP_FLAG` is a hero.exit flag and the workflow is
outside this task's writes. The look is not tuned by eye. `part.json` limit starts with `look change`, so Lean's class is look-change.

## Measurement (MEASURED, run 39999057900, commit 08e6bcdf0, webkit-sim swap lane, 430x775)
Push with `[swap-lane] [swap-fw:accent-nolayout]` (the workflow reads the new token; one-line edit of `FW` in `webkit-sim.yml`).
Jobs r1 and r2 succeeded (2 passes each); r3 failed at "Boot the Simulator" (no data). Captures: faithful-a 4, faithful-b 4, arm 8.
The report tables call the arm `crop`.

| window class | metric | faithful-a | faithful-b (A/A) | arm |
|---|---|---:|---:|---:|
| rest (800 ms), 7 per capture | windows with at least 24 Layout rows | 20 of 28 | 18 of 28 | 17 of 56 |
| rest | Layout rows per capture | 246.5 | 226.5 | 122.3 |
| rest | median Layout rows per window | 46 | 45.5 | 5 |
| swap (220 ms), 8 per capture | median Layout rows per window | 14 | 14 | 14 |
| swap | Layout rows per capture | 112.5 | 102.5 | 109.4 |

- Layout in the rest windows halves, as `layoutPhases_values` says (2 to 1): the remaining busy runs are the draw-in (width).
  The A/A difference of the two faithful slots (2 windows, 20 rows per capture) is far below the arm difference.
  The tool's per-window verdict is unresolved:overlap for every rest window too (swap-report.md); the halving is the pooled count over the 7 rest windows of 2 jobs, not a per-window resolved result.
- Swap windows: no change. The tool's per-window verdict is `unresolved:overlap` for all 8 windows and 4 kinds (`swap-report.md`);
  a swap window's 13 Layout frames are the carousel's own, and the accent draw is not what fills them. The end-of-page swap windows
  therefore gain nothing from this arm; the gain is in the quiet windows between swaps.
- Hero exit (scroll A): the lane records frame cadence, Paint and Composite time per frame and the layer census, not Layout events.
  Against the baseline run 39983630584 (hero.accent faithful, other flag people.carousel:crop) all ranges overlap (`cost-report.md`).
  NOT DELIVERED: Layout per hero-exit frame (needs a Layout-event lane; packages/measure-webkit was out of bounds here).

## Limits
- The CI Simulator is not the phone. The hero-exit baseline is another run, with a flag unrelated to the hero.
- Strokes are assumed to stay inside 20 percent of the svg box (clip insets); the arm differs from faithful if a stroke leaves it.
- The width transition of the draw-in is the original's and moves the headline text; removing it is a separate look-changing candidate.
- `StyleDiffAccent` covers the legacy SVG renderer path; the layer-based SVG engine is not modelled.

Files: `results/accent-draw-nolayout/` (`summary.json`, `swap-report.md`, `swap-report.json`, `cost-report.md`).

# Draw-in without the width transition: `hero.accent:draw-nolayout-full` (task accent-drawin-width-nolayout, ledger `accent.drawin-width-nolayout`)

Class look-change. Same engine pins as above (WebKit @862f17d, Chromium @f842f52). No new engine row is needed: the candidate is no new
property, it is the existing `width` row (`WC/style/StyleDifference.cpp:404`, `B/css/css_properties.json5:8286`) changed once instead of every frame.

## Why not a transform
The text after the word sits in normal flow and follows the word box. Any smooth glide of that text is itself a width or position change that the
engines lay out in every frame. A `transform: scaleX` on a wrapper moves only the wrapper; the text stays where layout put it. So no same-look,
layout-free replacement exists (INFERRED: in-flow text follows the word box; `width_layout` proves the width row lays out, and no layout-free row in the table moves in-flow text). The arm gives the glide up.

## Arm
`.accent[data-fw-draw='nolayout-full'].drawingIn { transition: none }` on top of the draw-nolayout rules (those now select
`:is([data-fw-draw='nolayout'], [data-fw-draw='nolayout-full'])`). The cursor callback already sets the width in the same task as the `drawingIn`
class, so the width changes once. Faithful and draw-nolayout are unchanged (the new rule keys on the new attribute; test `drawNoLayout.test.ts`).

## Proof (Lean `Fw.Engine.StyleDiffAccent`, no sorry; `wkLayoutFrames_values` and `crLayoutFrames_values` hold for every n)
- `full_out_nolayout`, `full_inRest_nolayout`: every frame except the width set needs no layout in WebKit or Chromium.
- `full_inFirst_layout_only_width`: among the modelled draw candidates, the one frame with layout gets it only through `width`; the same frame also swaps the word (path d, viewBox, paint insets in onCursor), which lays out in every arm and is not modelled.
- Layout frames in a cycle of n+1 frames per phase: WebKit 2(n+1) faithful, n+1 draw-nolayout, 1 full; Chromium n+1, n+1, 1.
  At 54 frames (900 ms at 60 Hz): 108, 54, 1 (`wkLayoutFrames_54`). Golden rows `slot` and `cycle` in `hero.accent.nolayout.jsonl`.

## Measurement (MEASURED, run 40010826238, commit 3c1ab9970, webkit-sim swap lane, 430x775, jobs r1 r2 with 2 passes each)
Push with `[ci:webkit-sim] [swap-lane] [swap-fw:accent-nolayout-full]` (a first push without `[ci:webkit-sim]` was skipped by the guard, run 40010696479;
it is not a dispatch). Job r3 did not finish and the run was cancelled, which skipped the report jobs; the report was built from the r1 and r2
artifacts with `node src/lag/cli.mjs swap-report --files r1-lag.json,r2-lag.json` (the same command reproduces the committed run-39999057900 numbers).
The report tables call the arm `crop`.

| window class | metric | faithful-a | faithful-b (A/A) | draw-nolayout (run 39999057900) | draw-nolayout-full |
|---|---|---:|---:|---:|---:|
| rest (800 ms), 7 per capture | windows with at least 24 Layout rows | 18 of 28 | 19 of 28 | 17 of 56 | 0 of 56 |
| rest | Layout rows per capture | 225.0 | 232.8 | 122.3 | 19.4 |
| rest | median Layout rows per window | 45 | 45 | 5 | 2 |
| swap (220 ms), 8 per capture | median Layout rows per window | 14 | 14 | 14 | 13 |
| swap | Layout rows per capture | 107.8 | 109.8 | 109.4 | 96.5 |

- The rest windows lose the accent layout: no window reaches 24 rows (faithful windows reach 24 in 18 and 19 of 28). The tool's per-window verdict is
  `unresolved:overlap` for every window (`full-swap-report.md`): the result is the pooled count over 7 windows of 2 jobs, as for draw-nolayout.
- Swap windows: 96.5 against 107.8 and 109.8 rows per capture, median 13 against 14; all 8 windows unresolved:overlap, so this is not a resolved win.
- Hero exit and pixel numbers: NOT DELIVERED here (task accent-nolayout-measure; the lane records no Layout events per scroll frame).

## Limits
- The CI Simulator is not the phone; 2 jobs, 4 passes; the A/A faithful slots differ by about 8 rows per capture in the rest windows.
- The text jump is the look change; the user judges it. draw-nolayout keeps the glide.
- The pushed commit wrote `[data-fw-draw^='nolayout']`; the later commit writes `:is()` of the two values (same elements; the hero.exit
  cascade test does not parse `^=`).

# Three arms in one run: Layout per hero-exit scroll frame (task accent-nolayout-measure)

## Premise: `transition: none` makes the width one change (cites file:line@sha)
CONFIRMED in the engine source, pins WebKit@862f17d and Chromium@f842f52 (`.cache/upstream/`):
- WebKit `Source/WebCore/style/Styleable.cpp`: `updateCSSTransitions` :761 (called from `style/StyleTreeResolver.cpp:856`) walks the new style per property
  (`updateCSSTransitionsForStyleableAndProperty` :570). `hasMatchingTransitionProperty` is built from `newStyle.transitions()` :586-601 and
  `transitionMatchesProperty` :499 returns false for `CSS::Keyword::None` :508. A transition starts only if there is a match and the duration is above
  zero :648; with no match a running transition is cancelled and the function returns (:672-680). So with `transition: none` the style change to the new
  width is a single computed-value change and no per-frame animated width exists.
- Chromium `third_party/blink/renderer/core/animation/css/css_animations.cc`: `CalculateTransitionUpdate` :3076 calls
  `CalculateTransitionUpdateForProperty` :2928-2945, where `kTransitionNone` falls to `default: break` :2942 (no transition is created);
  a start delay plus duration of at most zero calls `UnstartTransition` and returns :2850-2858. `css/resolver/css_to_style_map.cc:471` maps the
  keyword `none` to `kTransitionNone`.
- Site side (INFERRED from our source): `hero.accent/index.tsx` onCursor sets `em.style.width` in the same task as the `drawingIn` class (lines 67-81);
  `accent.module.css` gives `.drawingIn { transition: width .9s }` (:12-14) and `[data-fw-draw='nolayout-full'].drawingIn { transition: none }` (:76-78).
  The draw probe below counts `transitionrun` for width per capture to MEASURE this per arm.

## Draw-only freeze (`--freeze hero-accent-draw`)
`src/lag/freeze.mjs` `FREEZE_DRAW_CSS` removes only the draw: path animations, the svg clip animation of `drawingIn` and `drawingOut`, and the width
transition, all scoped to `[data-fw="hero-accent"]`. The idle boil keeps running. The mode counts `animationstart` (`stroke|clip` In|Out) and width
`transitionrun` in `window.__fwDraw`; the unfrozen twin only counts. Lean `busyFrozen` (golden `swapBusyFrozen`) decides each window of unfrozen busy
samples against frozen samples.

## Lane (`--accent`, token `[swap-accent]`)
13 units per job (Lean `laneUnits`, golden `swapLaneUnits`): faithful, draw-nolayout and draw-nolayout-full at one build, arm order shifted by the VM
number, hero-exit zone captures aligned (slot a) and natural (slot b), one draw-frozen faithful pass. Lane budget 24 min (Lean `laneBudgetMin`); a unit
that no longer fits is listed as skipped, never silently dropped. Layout per scroll frame is `perFrameMilli` (rows over frames, thousandths).
`accent-report` prints per-window verdicts against the faithful A/A floor, the frozen comparison, the pooled numbers and the zone verdicts per pair.

## Result, run 40030735082 (MEASURED, commit 7e3e5fc96, webkit-sim, 430x775, jobs r1 r2 r3 all success, 13 units each, none failed or skipped)
Report: `results/accent-draw-nolayout/accent-report-40030735082.md` (and `.json`). Zone = hero-exit scroll region A, 32 frames per capture, 3 aligned + 3 natural captures per state.

| state | Layout rows per scroll frame | Layout median per capture (min..max) | width transitions started |
|---|---:|---|---:|
| faithful | 2.385 | 81.5 (56..85) | 28 in 6 captures |
| draw-nolayout | 1.807 | 58 (51..65) | 11 |
| draw-nolayout-full | 1.807 | 55.5 (53..71) | 0 |
| faithful, draw-only freeze | 1.990 | 61 (53..78) | 0 |

- Zone verdicts (Lean `zoneVerdict`, ranges separated): all 6+6 captures overlap for every pair; the aligned group (scroll starts inside a draw, 3+3) separates:
  faithful against draw-nolayout lower, 32% of the median; against draw-nolayout-full lower, 36%; against the draw-frozen faithful lower, 31%. Natural group: overlap.
  Paint: overlap for the arms; the draw-frozen faithful is lower than faithful in the aligned group (7%).
- `transition: none` removes the width transition in every capture (0 of 6 captures start one; faithful 28), the measured side of the premise above.
- Rest windows (pooled over 3 jobs): busy windows (at least 24 Layout rows) faithful 27 of 42, draw-nolayout 6 of 21, full 0 of 21, draw-frozen 0 of 21;
  Layout rows per capture 218.5, 109.0, 19.7, 21.0; medians 43, 5, 2, 3. Per-window verdicts against the A/A floor: nolayout Layout wins 3 of 7 rest windows, full 5 of 7; all 8 swap windows unresolved:overlap.
- Unfrozen busy samples against frozen samples (Lean `busyFrozen`): rest windows 1 and 4 (the busy ones) `removed` by the freeze; swap windows overlap or have no busy sample.
- Harness defect found: the draw-start counter matched animation names exactly (`strokeIn`), the built site hashes keyframe names, so it counted 0 animation starts in every arm (the width transition counter is not affected). Fixed in commit a3bb8cd67 (`DRAW_ANIMS` without the start anchor); run 40035116432 repeats the lane.

## Result, run 40035116432 (MEASURED, commit a3bb8cd67, same lane, jobs r1 r2 r3 all success, 13 units each, none failed or skipped)
Report: `results/accent-draw-nolayout/accent-report-40035116432.md`. Not pooled with the run above (different commit; the page and arms are the same build, only the draw counter changed).

| state | Layout rows per scroll frame | Layout median per capture (min..max) | draw starts (animations / width transitions), 6 captures |
|---|---:|---|---|
| faithful | 2.443 | 79 (72..83) | 66 / 10 |
| draw-nolayout | 1.771 | 54.5 (51..66) | 19 / 9 |
| draw-nolayout-full | 1.781 | 56.5 (50..65) | 96 / 0 |
| faithful, draw-only freeze | 1.911 | 59.5 (54..68) | 0 / 0 |

- Zone verdicts (Lean `zoneVerdict`): all 6+6 captures, faithful against draw-nolayout lower (31% of the median), against draw-nolayout-full lower (28%), against draw-frozen faithful lower (24%);
  the two arms against each other overlap. The same Layout verdicts hold in the aligned and the natural group (3+3 each, 22% to 31%). Paint: overlap, except the draw-frozen faithful in the aligned group (lower, 29%).
- Rest windows (pooled over 3 jobs): busy windows faithful 27 of 42, draw-nolayout 7 of 21, full 0 of 21, draw-frozen 0 of 21; rows per capture 223.7, 128.3, 21.7, 22.0; medians 45.5, 5, 3, 3.
  Per-window verdicts: full wins Layout in 2 of 7 rest windows, nolayout 0; every swap window is unresolved:overlap. Swap windows pooled: 109.0 faithful, 111.7 nolayout, 110.7 full rows per capture, so no swap-window difference is resolved.
- Both runs agree: per scroll frame Layout falls from about 2.4 to about 1.8 (-25%) for both arms and to about 1.9-2.0 with the draw frozen; the full arm adds nothing over draw-nolayout inside the zone (overlap in both runs);
  it differs only in the rest windows (0 busy windows against 6 and 7) and in the width transition (0 started).
- The animation counter, now matching, shows draw-nolayout-full starts clip animations (96) where faithful starts stroke animations (66): the arm draws through clip-path, as designed.

## Limits of this measurement
- The CI Simulator is not the phone. 3 jobs of one pass each per run, two runs; ranges of 3 captures per group are wide (natural group of run 1 overlaps, of run 2 separates).
- Rows per scroll frame are Timeline Layout rows over the 32 frames of scroll region A; the pixel sameness and the look review are the user's.
- Item 2 (the path-pix draw window) is not part of this round.

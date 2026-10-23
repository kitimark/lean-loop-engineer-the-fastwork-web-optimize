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

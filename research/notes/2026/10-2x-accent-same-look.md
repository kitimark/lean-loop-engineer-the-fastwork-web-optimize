# hero.accent: same-look search after the user's rejection (task accent-same-look)

## Decision recorded
On 2026-10-24 the user rejected `hero.accent:draw-nolayout-full` on the real iPhone: the draw looks different from
the original (session `results/phone/2026-10-24/summary.md`, look arm = rewrite +
`?fw=hero.accent:draw-nolayout-full`). Ledger: `userDecision` on n=56; a notes row on n=55 (`draw-nolayout`
uses the same clip-path wipe and was not reviewed on its own). Status of both stays `look-change`, so the preset
generator still leaves them out.

## Search
Lean: `Fw.Engine.StyleDiffAccent` (`srow`, `verdict`). The golden is `packages/contracts/golden/parts/hero.accent.nolayout.jsonl`,
kinds `search` and `combo`, checked by `apps/site/src/parts/hero.accent/sameLook.test.ts`. The verdict rule, in order:
the engine does not ship it, then a WebKit layout per frame, then a Lean proof that the picture differs, else pending.

| candidate | role | WebKit layout per frame | verdict | Lean / source |
|---|---|---|---|---|
| stroke-dasharray trace | stroke | yes | layout | StyleDifference.cpp:160@862f17d |
| `d` rewritten per frame | stroke | yes | layout | StyleDifference.cpp:154, StyleSVGLayoutData.h:64 |
| sprite, stepped background-position | stroke | no | look | `frames_miss` |
| CSS Paint API | stroke | n/a | unavailable | UnifiedWebPreferences.yaml:1314-1325 (default false) |
| final stroke clipped to the swept region | stroke | no | look | `clip_coverage_differs` |
| canvas 2D stroke per frame, fixed size | stroke | no | pending | HTMLCanvasElement.cpp:568-604, html_canvas_element.cc:687-711@f842f52 |
| accent at final width, neighbours translated | width | no | pending | `glide_same`, `glide_eased` |
| width set once (draw-nolayout-full) | width | no | look | `jump_differs` |

## The math, from the Lean statements
- `frames_miss`: for a progress curve e that strictly increases on [a, b) and any finite list F of sprite
  progresses, some φ in [a, b) has e(φ) not in F. The draw start is not on the display frame grid, so the
  phase is free and a sprite misses the original on some start.
- `clip_coverage_differs`: for 0 < c < 1, c·c ≠ c (an unpadded clip at a stroke side edge), and 1·1 ≠ 0 (a padded
  clip shows a later part of the same path early).
- Headline row of width T, first word p, gaps g, accent w, last word q: left = (T − (p + 2g + w + q)) / 2.
  `glide_same`: with the accent held at the final width w_f and shift (w_f − w)/2, the first word at left(w_f) + shift
  and the last word at last(w_f) − shift sit where the original has them, and the accent centre does not depend on w.
  `glide_eased`: for w = w0 + (w_f − w0)·e the shift is (w_f − w0)/2 · (1 − e), so the original easing drives it.
- `jump_differs`: w ≠ w_f moves both words, so the jump differs on every glide frame before the end.
- `combo_54` (54 frames per phase): WebKit layout frames per cycle are 108 for the original, 108 with glide alone,
  54 with canvas alone, 1 with canvas and glide.

## Result
No candidate is both proved same-look and layout-free in WebKit, so no flag is added (`pending_exact`: the pending
set is canvas and glide; `stroke_pending_only_canvas`). Both pending candidates are layout-free (`pending_nolayout`)
but their pixels are MEASURED-pending: the canvas rasters apart from the page and uses its own Bezier and dash
numerics (C4, `Fw.Engine.Visual.raster_path_fails_fracAlpha`); the glide moves text by fractional compositor
translates, which layout would snap (C5, `Fw.Engine.Visual.raster_path_fails_fracXf`).

## Run plan (not dispatched)
Path-pix sim-draw lane (`.github/workflows/path-pix.yml`, `packages/measure-webkit/src/pathpix-exit-draw-webkit.mjs`,
paused animations at fixed progress). It needs a canvas arm and a glide arm in `DRAW_FLAGS`, outside this task's
writes, and the glide needs a write to the hero part (the neighbour spans). One dispatch per arm against faithful.
Ship glide only with canvas: alone it saves no WebKit layout frame.

## Lesson
A set-level identity is not a pixel identity once two antialiased rasters multiply, and a pre-rendered sprite cannot
match a continuous animation at every start phase. The cheap same-look levers in WebKit are a repaint (canvas) and a
compositor translate (glide); both move the risk from layout to rasterisation, which only a pixel run can settle.

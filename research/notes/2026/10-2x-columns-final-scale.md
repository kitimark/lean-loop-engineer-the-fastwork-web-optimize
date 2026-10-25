# morph.columns:final-scale: columns laid out once, drawn by a per-column transform

## Answer

- The edges hold exactly and the look bound holds where the variant applies. Status: PROVED in Lean (`Fw.Parts.MorphColumnsScale`), replayed by `apps/site/src/parts/morph.columns/scale.golden.test.ts` against `packages/contracts/golden/parts/morph.columns.final-scale.jsonl` (110 rows, 11 widths x 9 morph values).
- The scale is horizontal only (`scale(sx, 1)`), not the uniform `scale(s)` that the candidate note (10-2x-end-gpu-map.md, candidate 1) assumed. The pictures have fixed pixel heights (`data.ts`), so a uniform scale would move every picture's bottom edge: `uniform_breaks_height`. Vertical scale 1 keeps heights, the 12 px gap between pictures and the 56 px drift exact (`vertical_exact`).
- Bound at 390 px: `sx >= a = 0.9767`, so at most 2.3 % horizontal squeeze (`a_390`: a >= 0.97, the proved statement). It holds for every width from 314 to 1000 px (`a_range`, `sx_range`, `squeeze_bound`: squeeze <= 3 %; `radius_bound`: horizontal corner radius within 0.36 px of 12).
- The bound fails outside that range, so the variant applies only up to 1000 px (the original's `mq.w-le-1000` edge): a = 0.786 at 1280 px, 0.694 at 1440 px (`a_desktop`), 0.9657 at 280 px (`a_narrow`). Above 1000 px the arm is the base layout. This narrows the candidate: no desktop effect.
- Per-frame layout: the variant's only `--morph`-dependent property in the columns is `transform` (`variant_no_layout`); the base's is the column `width` (`base_width_moves`: strictly increasing in m). The layout box is constant in m (`layout_const`). The backdrop box itself, owned by morph.panel, still changes width each frame; INFERRED that its fixed-width flex items skip relayout.
- CI counts: not run by this branch. The lead dispatches them (commands in the report items). Nothing here claims same look: class L, the user's look review decides.

## Geometry (Lean statements)

Backdrop width = 1.06 x nav width (`bleed`), n columns (3 up to 640 px, else 5), gap 12. Column width `colW m = (backW m - 12 (n-1)) / n`; it is affine in m (`colW_affine`). The variant lays each column out at `finalW = colW 1`, with left edge `i (finalW + 12)`, and draws it with origin at its own left edge: `translateX(tx) scale(sx, 1)`, `sx = colW m / finalW`, `tx = i (colW m - finalW)`.

- `edges_eq`: drawn left and right edge equal the base layout's edges for every m and i.
- `css_eq`: the CSS form `sx = a + (1 - a) m`, `tx = i (1 - m) d` with two per-viewport constants `a = colW 0 / finalW`, `d = colW 0 - finalW` equals the direct form. The part writes `--cs-cf`, `--cs-a`, `--cs-d` on mount and on resize only; `--col-i` is static markup.
- The phone rule (`Nav.phone`, nav width 358 to 366 px at 390 px) differs from the 342 to 350 px the candidate note inferred: a measured-by-Lean 0.9767, not 0.97 by inference.

## Source: what a transform costs against a grid re-layout

- Chromium: the track layers have `will-change: transform`; a raster scale is kept while it is at least the minimum (`cc/layers/picture_layer_impl.cc:1339-1346@f842f52`, scale floor 0.25 at :69). So the changing ancestor scale does not re-raster them. INFERRED for these layers.
- WebKit: the root-relative scale update that would re-raster is off outside LBSE (`Source/WebCore/platform/graphics/ca/GraphicsLayerCA.cpp:4378-4387@862f17d`, `m_shouldUpdateRootRelativeScaleFactor` defaults false). CONFIRMED in source; the effect on the Simulator is a measurement.
- The scale sits on `.col`, which is not a layer; the tracks inside are. INFERRED: a style-driven transform change on the non-layer parent updates the child layers' transforms, no layout.

## Accepted limits (from the task)

Look-change class (the user's review decides); the iOS Simulator stands in for the iPhone; counts are engine work, not felt smoothness; at most 3 pushes; macOS runners may queue; one failed Simulator VM is acceptable with 2 or more left per arm.

## Runs

All on `ci/columns-final-scale` at 6d8fbd72f. Raw artifacts were read in a scratch folder; only these summaries are committed.

| run | what | state |
|---|---|---|
| 40156382719 | Chromium counts, swipe-touch-v1, base, 3 runs | success |
| 40156384878 | Chromium counts, same, flag `morph.columns:final-scale`, 3 runs | success |
| 40156388674 | WebKit Simulator, base, r1 and r3 ok, r2 lost its VM (`simctl list devices failed: ETIMEDOUT`), n=2 | failure (r2) |
| 40156393010 | WebKit Simulator, flag, r1 and r3 ok, r2 same VM loss, n=2 | failure (r2) |
| 40156380619 | breakpoint gate, both engines, flag | failure (merge) |

### Chromium (MEASURED, three runs per arm, sums over all zones)

| count | base | flag |
|---|---|---|
| trace.Layout | 475, 474, 477 | 475, 474, 474 |
| trace.UpdateLayoutTree | 2388, 2392, 2388 | 2388, 2392, 2388 |
| trace.Layout.dirtyObjects | 6486, 6484, 6492 | 6485, 6482, 6480 |
| metric.RecalcStyleCount | 2371, 2375, 2371 | 2371, 2375, 2371 |

In the morph zone (y00500) Layout totalObjects is 46265 base against 46098 flag (-0.4 %); every other zone is identical. Verdict: no Layout, no UpdateLayoutTree, no style-recalc reduction.

### WebKit Simulator (MEASURED, n=2 per arm, two passes each)

Counts over the scroll zones 0 to 4999 px (records assigned by the step marks), mean of two passes:

| count | base r1, r3 | flag r1, r3 |
|---|---|---|
| Layout | 584, 613.5 | 589, 610 |
| RecalculateStyles | 618.5, 644.5 | 633, 641 |

The spread between the two sessions of one arm (about 30) is larger than the arm difference (at most 15). The last zone (from 5000 px) holds the idle tail and varies from 67 to 455 Layout between passes; it is left out. Verdict: no change.

### Breakpoint gate (run 40156380619, both engines)

The gate fails the `morph.columns` row on 19 of 30 desk, touch and other conditions, in the sweeps and in the rotation. Its failing-items table has exactly three rows, all computed style of the column: flex-basis `0px` to `auto`, flex-grow `1` to `0`, flex-shrink `1` to `0`. That is the shorthand `flex: none` the variant sets (`morph.module.css`, inside `width<=1000px`). Failures run from desk-319 to desk-1000 and none above 1000 px. Cause: the intended layout change of the look-change variant, compared as computed style; no real break (rects, margins and everything else pass: 0 differing margin cells of 1960). The follow-up is a Lean-first gate rule for visClass L: the variant declares the changed (role, property, range) set; items inside it are excused with a premise, rect equality at rest still counts, anything outside fails.

### Why no count win (INFERRED)

The Lean theorems prove the column box is constant in the morph value. They do not prove that the per-frame layouts re-lay out the column subtree: the morph zone's layouts each touch about 670 objects in both arms, so the panel and its siblings keep laying out. A per-subtree layout attribution is needed before a layout win can be claimed or ruled out.

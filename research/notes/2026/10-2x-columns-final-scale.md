# morph.columns:final-scale: columns laid out once, drawn by a per-column transform

## Answer

- The edges hold exactly; the look bound holds from 314 to 1000 px (below 314 px the variant still applies unproved, see below). Status: PROVED in Lean (`Fw.Parts.MorphColumnsScale`), replayed by `apps/site/src/parts/morph.columns/scale.golden.test.ts` against `packages/contracts/golden/parts/morph.columns.final-scale.jsonl` (11 vars rows plus 99 frame rows).
- The scale is horizontal only (`scale(sx, 1)`), not the uniform `scale(s)` that the candidate note (10-2x-end-gpu-map.md, candidate 1) assumed. The pictures have fixed pixel heights (`data.ts`), so a uniform scale would move every picture's bottom edge: `uniform_breaks_height`. Vertical scale 1 keeps heights, the 12 px gap between pictures and the 56 px drift exact (`vertical_exact`).
- Bound at 390 px: `sx >= a = 0.9767`, so at most 2.3 % horizontal squeeze (`a_390`: a >= 0.97, the proved statement). It holds for every width from 314 to 1000 px (`a_range`, `sx_range`, `squeeze_bound`: squeeze <= 3 %; `radius_bound`: horizontal corner radius within 0.36 px of 12).
- The bound fails outside that range, so the variant applies only up to 1000 px (the original's `mq.w-le-1000` edge): a = 0.786 at 1280 px, 0.694 at 1440 px (`a_desktop`), 0.9657 at 280 px (`a_narrow`). Above 1000 px the arm is the base layout. Below 314 px the variant still applies and its squeeze bound is not proved (a = 0.9657 at 280 px, `a_narrow`); named, not fixed, since the variant does not ship without a win. This narrows the candidate: no desktop effect.
- Per-frame layout: the variant's only `--morph`-dependent property in the columns is `transform` (`variant_no_layout`); the base's is the column `width` (`base_width_moves`: strictly increasing in m). The layout box is constant in m (`layout_const`). The backdrop box itself, owned by morph.panel, still changes width each frame; INFERRED that its fixed-width flex items skip relayout.
- CI counts (MEASURED, runs below): no Layout or style-recalc win on Chromium (40156382719 vs 40156384878) or the WebKit Simulator (40156388674 vs 40156393010, n=2 per arm). Class L, so the user's look review decides shipping.

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

All on `ci/columns-final-scale` at 6d8fbd72f.

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

In the morph zone (y00500) Layout totalObjects is 46265 base against 46098 flag (-0.4 %). y00500 is lower in the flag on all 3 runs by about 1 Layout and 0.4 % totalObjects (Layout flag 68/67/68 vs base 69/68/70; dirtyObjects flag 761/759/761 vs base 767/765/769); y01500 varies run to run in both arms (totalObjects 49731/49731/49784 base vs 49841/49784/49731 flag); all other zones have identical Layout, UpdateLayoutTree and RecalcStyle counts (elementCount differs by under 0.5 %). Verdict: no Layout, no UpdateLayoutTree, no style-recalc reduction.

### WebKit Simulator (MEASURED, n=2 per arm, two passes each)

Counts over the scroll zones 0 to 4999 px (records assigned by the step marks), mean of two passes:

| count | base r1, r3 | flag r1, r3 |
|---|---|---|
| Layout | 584, 613.5 | 589, 610 |
| RecalculateStyles | 618.5, 644.5 | 633, 641 |

Each flag session lies inside the base session range (Layout 589, 610 within 584 to 613.5; RecalculateStyles 633, 641 within 618.5 to 644.5).

Layout per 500 px zone, mean of 2 passes (base r1 / base r3 / flag r1 / flag r3):

| zone | base r1 | base r3 | flag r1 | flag r3 |
|---|---|---|---|---|
| z0 | 75 | 81.5 | 71.5 | 81.5 |
| z1 | 58 | 71 | 68.5 | 68.5 |
| z2 | 48 | 52.5 | 52 | 53.5 |
| z3 | 69.5 | 76 | 71 | 74 |
| z4 | 63.5 | 61.5 | 64 | 62.5 |
| z5 | 57 | 57 | 58 | 58 |
| z6 | 46.5 | 42.5 | 38 | 43.5 |
| z7 | 73 | 71 | 67.5 | 68.5 |
| z8 | 48 | 32.5 | 39 | 35 |
| z9 | 45.5 | 68 | 59.5 | 65 |

Composite is 19 in z0 and 20 in each of z1 to z9 in every pass of all four sessions (199). Backing memory at the final state is 105.8 MB base (both sessions) against 97.9 MB (r1) and 105.8 MB (r3) flag; the other states are equal within 5 MB. Verdict: z7 is lower in both flag sessions (67.5, 68.5 vs 71, 73) and z0, z6 in flag r1 only; with n=2, zones far from the morph, and the 0-4999 px sums inside the base range, no zone win is established; Composite identical; backing MB unchanged except flag r1 at its final state (-7.9 MB, one session, different final scroll y) (flag r1's final census is at scroll y 5267, the others at 5231, so this is not the same state). The last zone (from 5000 px) holds the idle tail and varies from 67 to 455 Layout between passes; it is left out. Per-engine verdict: no win on either engine.

### Breakpoint gate (run 40156380619, both engines)

The gate fails the `morph.columns` row on 19 of 30 desk, touch and other conditions, in the sweeps and in the rotation. Its failing-items table has exactly three rows, all computed style of the column: flex-basis `0px` to `auto`, flex-grow `1` to `0`, flex-shrink `1` to `0`. That is the shorthand `flex: none` the variant sets (`morph.module.css`, inside `width<=1000px`). Failures run from desk-319 to desk-1000 and none above 1000 px. Cause: the intended layout change of the look-change variant, compared as computed style; no real break (rects, margins and everything else pass: 0 differing margin cells of 1960). The follow-up is a Lean-first gate rule for visClass L: the variant declares the changed (role, property, range) set; items inside it are excused with a premise, rect equality at rest still counts, anything outside fails.

### Why no count win (INFERRED)

The Lean theorems prove the column box is constant in the morph value. They do not prove that the per-frame layouts re-lay out the column subtree. Chromium's Layout totalObjects is the size of the traversed tree, not the objects laid out (layout_subtree_root_list.cc:17-33@f842f52); dirtyObjects is about 11 per morph-zone layout in both arms (767/69 base, 761/68 flag), so the counts do not show which subtree re-lays out. A per-subtree layout attribution is needed before a layout win can be claimed or ruled out.

## Follow-ups (lead)

- Check or generate the `--morph`-dependent property set from the CSS module (`morph.module.css`), so `variant_no_layout` and `layout_const` (`MorphColumnsScale.lean`, `variantMorphDeps`) can fail when the CSS changes; today the list `[.transform]` is hand-written and `layout_const` is `rfl` over a box constant by definition.
- Breakpoint gate rule for visClass L variants (run 40156380619): the only failing items are column flex-basis, flex-grow, flex-shrink (560 Chromium, 545 WebKit), the intended `flex: none` at desk-319 to desk-1000; `pain-1440-600-1440` fails only at 600; rects and margins pass.
- Per-subtree layout attribution with a Lean why for the missing Layout win.

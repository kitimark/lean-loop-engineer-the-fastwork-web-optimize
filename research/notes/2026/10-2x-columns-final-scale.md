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

Push branch `ci/columns-final-scale` (one push, push runs skipped by path filters except `lean`). Measurement runs need the lead; see the report.

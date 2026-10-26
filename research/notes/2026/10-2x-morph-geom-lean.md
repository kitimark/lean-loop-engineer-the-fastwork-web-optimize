# morph.geom: the Lean spec (task morph-geom-lean)

This is the Lean half of the design note `10-27-morph-compositor-geometry.md`. The modules are
`lean/Fw/Parts/MorphGeom{,Rect,Earn,Anim,Gen}.lean`. The golden is `packages/contracts/golden/morph-geom.jsonl`,
written by `lean/scripts/MorphGeomGolden.lean` and checked by the `morph-geom golden check` job in `check.sh`.

Every theorem below is PROVED with no `sorry`. `#print axioms` shows only `propext`, `Classical.choice` and
`Quot.sound`. "Bands" means the 12 viewports of `bandVps`; those statements are decided with `decide +kernel`.

## Statements

| Lean name | Statement in plain words | Status |
|---|---|---|
| `AnimProp`, `Anim`, `layers`, `anims` (Anim.lean) | Only 6 properties can be animated: translate, scale, transform, opacity, filter, backdrop-filter. An effect records its element, index, property, knot set, one function per keyframe number, easings, composite, rate and direction. | defined |
| `box_eq` | Holds by definition: `boxAt v m` is the rectangle (x0, y0, x0+wd, y0+ht) with radius `rad`. The phone kink is the knot `mKnot`. | by definition |
| `clip_eq`, `cover`, `clip_pill` (MorphGeom.lean) | A point is inside all four corner clips exactly when it is inside the rounded pill at m. Each clipper covers the side it does not cut. | PROVED |
| `chord_sub_eq` | For f = (a+bm)/(1-cm), the chord error is the closed form in the design note. | PROVED |
| `net_err_x`, `net_err_y`, `net_ok_bands` | For every m in [0, 1], the K0..U chain moves content at most 1/64 px from where it should be, on every band. | PROVED |
| `logo_err`, `logo_ok_bands` (Rect.lean) | The logo track is off by at most dW·h²/8 ≤ 1/64 px on every band, where h is the largest knot step. | PROVED |
| `rect_eq` | For the bar, actions, columns, images, veil, centre, footer (with gradient and end), backdrop clip and panel centre, the composed rect equals the faithful one restated from the CSS. | PROVED |
| `fill_eq`, `fill_ev` | D at opacity m over G over bg equals the faithful colour mix over bg, per channel. The D and blur tracks are exact. | PROVED |
| `panel_eq`, `fade_eq` | Panel opacity equals clamp((m-0.08)/0.72), with blur 12(1-o); the platform tracks equal `fade` and its blur. | PROVED |
| `earn_eq`, `earn_eq_webkit`, `earn_eq_chromium` (Earn.lean) | At every frame k ≤ 90 of the 60 Hz grid, the earn clip edges, label padding, opacity, blur, shift and language edge equal the faithful run. WebKit's padding is the m-function (its transition never starts); Chromium's is the NavEarnOpt run. | PROVED |
| `accelerable_bands` | On every band and engine, every effect meets the CA rules. Its numbers match the property's arity, keyframe easing is linear, effect easing is linear or a cubic with control points in [0, 1], composite is replace, rate is 1, direction is normal. There is one effect per (element, index, property), and every knot set is sorted from 0 to 1. | PROVED |
| `noTransition_bands` | Every animated element is in the generated `.is-flip { transition: none }` list. | PROVED |
| `timed_easing_ok` | The timed cubic (1/3, 1, 2/3, 1) passes the easing rule. | PROVED |
| `end_eq` (Anim.lean) | On every band: (1) every track equals its function at the first and last keyframe; (2) the net nav map is the identity at m = 0 and m = 1; (3) at m = 1 every content transform is the identity and the panel shows at opacity 1 with no blur. | PROVED |
| `mem_bands`, `mem_phone_390` | The backing census fits the headroom `budgetB - basePeak` = 23,055,555 B only on 320×568 and 641×700. 390×844 needs 34,558,272 B. | PROVED (verdict) |

## Differences from the design note's wording

* `rect_eq`: the bar is compared on its y extent, and the centre on its centre point (title wrap stays the disclosed
  L item). An image's y uses its flow offset `Y - j·gv`. The panel has no blur at ≤ 720 px (`.panel{filter:none}`).
* `earn_eq`: stated for one push sequence, on the 60 Hz grid only. Reversal is `MorphGeomTimed`'s job.
* `accelerable`, `noTransition`, `end_eq` and `mem` are narrowed to the band table, with a sample layout `Ctx.sample`
  (logo, label and image sizes).
* `accelerable` reads only the effect fields. That the generated keyframes repeat one function-list shape is a fact
  about `Anim.tracks`, not a separate check.

## Finding: the backing census is over budget on 10 of 12 bands

These are bytes from the `Resource.layerBytes` formula (10-25 note): dpr 3 below 640 px wide, dpr 2 above. Containers,
clippers, counters, the solid D fill, the panel and the directly composited images get no backing
(`RenderLayerBacking.cpp:3509-3535,3687-3690@862f17d`, INFERRED applicability). The census counts each flip backing as new
and frees nothing.

| band | bytes | over headroom by |
|---|---|---|
| 320×568 | 22,127,616 | fits |
| 390×844 | 34,558,272 | 11.5 MB |
| 641×700 | 19,975,680 | fits |
| 1920×1080 | 99,015,680 | 76 MB |

The veil (W×H) and the platform layer (viewport size) make up about two thirds of the bytes. The design must drop or
shrink these two. Alternatively, a measurement could show that the faithful arm already pays for them (the platform's
blur, or the veil's gradient layer). Until then, `morph.geom:on` is `overBudget` on most bands.

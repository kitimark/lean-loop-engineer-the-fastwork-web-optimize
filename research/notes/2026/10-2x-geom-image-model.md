# geom-image-model: object-fit cover model for the column pictures

Status: Lean proof CONFIRMED; site follows (golden-checked); CI gate MEASURED (run 40566917070); the premise "picture scaling causes the mid-morph look difference" is REFUTED by the look numbers.

## Model (lean/Fw/Parts/MorphGeomPic.lean)
- `coverK`/`drawn`: `object-fit: cover` at `object-position: 50% 50%` scales by the larger of the two fit ratios (Blink `layout_replaced.cc:447-478@f842f52`, WebKit `RenderReplaced.cpp:582-612@862f17d`).
- The base picture at `m` is `drawn (cw v m) h iw ih` inside a `cw v m` by `h` box. The flip draws the picture at rest (`m = 1`) and moves it with a uniform scale `uImg` and a translate; the box is cut by clipper `Kc` (moved by `kcTx`), `Uc` moves back.
- `uImg` is piecewise linear with one kink where the two ratios cross, `qImg`; `kinkKnots` gives the key offsets `[0, q, 1]` when `0 < q < 1`.
- Theorems, for every `m` in [0,1]: `pic_rect_eq` (flip picture rect = base), `pic_crop_eq` (flip crop = base), `pic_eq` (both), `flip_covers` (crop inside rect, no gap), `pic_box_x` (box starts where base's does), `pic_end` (all neutral at `m = 1`), `old_height_differs` (the old both-axis scale could not equal base), `clipPad_covers_drift`.
- Compositor-only per frame: the picture moves by transform; `Kc` clips with `overflow: hidden` on a transformed box and `Uc` is a transform. No layout property changes per frame (geom.css `[data-mg='Kc']`, `[data-mg='pic']`, `.is-flip [data-mg='image']` use fixed `--pic-*` custom properties set once).

## Measured (CI run 40566917070, morph.geom:on, both engines)
- Flip cell: 48 of 48 readings pass on Chromium and on WebKit (flip-cell-* artifacts); the picture readings are included.
- Look report vs base, share of pixels differing by more than 12, range over the 12 bands. Before = run 40553185213.

| m | region | Chromium before | Chromium after | WebKit before | WebKit after |
|---|---|---|---|---|---|
| 0.25 | nav | 46.4-77.7 | 46.5-77.7 | 49.4-77.7 | 49.4-77.7 |
| 0.25 | columns | 21.6-93.1 | 21.6-93.2 | 28.7-92.5 | 28.8-92.5 |
| 0.5 | nav | 51.8-74.3 | 51.9-74.3 | 52.8-76.8 | 52.9-76.8 |
| 0.5 | columns | 23.4-76.1 | 23.4-76.1 | 26.0-76.2 | 26.0-76.1 |
| 0.75 | nav | 27.1-39.6 | 27.0-39.6 | 26.0-39.6 | 26.0-39.5 |
| 0.75 | columns | 9.6-23.4 | 9.6-23.4 | 10.0-23.3 | 9.9-23.2 |
| 1 | nav | 0.1-3.1 | 0.4-5.5 | 0.1-0.3 | 0.3-3.3 |
| 1 | columns | 0.1-2.9 | 0.1-4.2 | 0.1-0.3 | 0.1-1.7 |

## Finding
The geometry now equals base (proved, and the cell reads the pictures), yet the mid-morph difference did not move (within 0.2 points). So the picture scale was not what the look report sees at 0 < m < 1. The m = 1 shares rose a little (nav up to 5.5 %, columns up to 4.2 % on Chromium), within the accepted resampling limit at picture edges but unexplained in detail. The look run saves no images, so the remaining cause cannot be read from artifacts. Candidates (INFERRED, not shown): the base arm at pinned `m` (look.mjs pins `m` on the nav only, so other pieces such as the platform section and column text stay at their rest state in base: see 10-2x-geom-page-diff.md), text and backdrop drawn differently in the two arms.
Follow-up: look.mjs saves per-region PNGs for both arms at m = 0.5 and a per-element diff (task geom-look-fade covers the pinning).

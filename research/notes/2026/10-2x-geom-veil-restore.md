# geom-veil-restore: the veil track is back (task geom-veil-restore)

Source: `10-27-end-columns-probe.md` A2, `10-2x-geom-flip-fix.md`, finding in `10-2x-morph-geom.md`.

## What changed
- Site: tracks.ts veil track (transform, unit), tree.ts TAGS veil, geom.css veil in the no-transition list and the 0 0 origin
  list, the `display: none` rule removed. Revert of the site part of 6b376eba6 by hand (a git revert conflicted with later edits).
- Lean: `layers` and `anims` have the veil again (MorphGeomAnim), `flipEls` has it; `Item.veil` with its `faithful`/`composed` rows and the
  `rect_eq` case are back (MorphGeomRect); MorphGeomCounts has the fold shrink again (as a bound) plus exact byte theorems.
- Golden `morph-geom.jsonl` regenerated (707 lines; 653 sample rows, 12 of them veil).

## Proved (Lean, `lake build Fw`)
- `look_veil_x/y/sx/sy` (MorphGeomLook): the veil animation's four functions are `x0`, `y0`, `wd/wp`, `ht/hp`.
- `veil_rect_base`: for Valid v and m in [0, 1], the rectangle the animations draw equals the faithful one (`rect_eq`, `.veil`).
- `veil_no_opacity`: every animation of the veil is its box transform; none sets opacity, so the veil keeps the opacity the base
  page gives it (that of the panel group, itself animated by the panel opacity track).

## Memory and layers (MEASURED by Lean `decide`)
One more backed layer (the veil, final box at viewport size). Net bytes at level 0 (faithful backs the nav only), 12 bands in
`bandVps` order, `net_lvl0_veil_bytes`: 16330752, 19291392, 23753952, 27541152, 27758592, 42504192, 13629120, 20300800, 22856704,
29213696, 57072640, 73849856 (folded: `net_lvl0_fold_bytes`, about 10.8 MB less at 390x844). `mem_bands`: 2 of 12 bands inside the
23055555 byte budget (390x844 `mem_phone_390` = 34558272). At level 2 (INFERRED, the faithful page backs panel and platform) the veil
replaces the panel's backing exactly: `net_lvl2_flip_bytes` = the folded values, all 12 bands fit. The census lane that decides
the level still does not exist; the memory trade is accepted (user note: more GPU memory is fine when the work leaves the main thread).

## Look and gate on CI
See the handoff `docs/team/handoffs/geom-veil-restore.md` for run ids and readings.

# proof-morph-panel (handoff)

State: `lean/Fw/Parts/MorphPanelOpt.lean` (ns `Fw.Parts.MorphPanelOpt`, imported in `lean/Fw.lean`). Golden rows: `packages/contracts/golden/engine/morph-panel.jsonl` (20 rows: Chromium swipe-v1 + swipe-touch-v1, WebKit swipe-v1; variant `rewrite+?fw=morph.panel:rest`, base `rewrite`), generated from `goldenText` with `import Fw.Parts.MorphPanelOpt` + `def main := IO.FS.writeFile "../packages/contracts/golden/engine/morph-panel.jsonl" Fw.Parts.MorphPanelOpt.goldenText`, run with `lake env lean --run` from `lean/`. `lake build` is green; the axioms are propext, Quot.sound and Classical.choice only.

Original (snapshot CSS `.start-selling-platform`): `filter: blur(calc((1 - var(--morph-fade)) * 12px))`, `opacity: var(--morph-fade)`, `--morph-fade = 1 - min(1, r/0.55)`. `fade`/`radius` model this over Rat; `rest_iff` says the radius is 0 exactly when r ≤ 0.
- Sub-claim 1, rest (`blur(0)` → `none`):
  - Vis E: `rest_visSame_E` under the explicit premise `RG10` (grouping does not change the scene at rest: no fixed/absolute descendant uses the panel as containing block). `fade_scene_eq` gives equality during the fade with no premise.
  - Work: `cr_rest_le`/`cr_rest_lt`/`cr_rest_claim` (Chromium: one fewer effect node, so dominates). The strict step needs one of the rasterUnder, propsPanel or drawSurface bits. `wk_rest_le`/`wk_rest_lt`/`wk_rest_claim` (WebKit: only the comp draw is saved, plus one resident layer when there are composited descendants, `wk_rest_layers`). Paint is equal because blur(0) is an identity. `wk_rest_panel_not_mono` is the `wk_not_mono` caveat.
- Sub-claim 2, fade (own layer), vis Q: `fade_visSame_Q`.
  - Chromium work is a TRADE: `cr_fade_le`, `cr_fade_raster_drop` (raster −1 per frame), `fade_layers_up` (+1 layer), `cr_fade_trade` (claim = trade). The original's panel must not be own (ℓo ≠ own).
  - WebKit: `wk_fade_paint_drop` (paint −2), `wk_fade_props_up` (props +2), `wk_fade_not_le` (no per-frame order).

variant `morph.panel:rest` (TS) must: emit `filter: none` exactly when the radius is 0 (r ≤ 0) and keep `blur(Npx)` otherwise. It leaves opacity and the fade curve unchanged and gives no own layer (sub-claim 2 has no golden variant). Label runs `meta.variant=rewrite+?fw=morph.panel:rest`.

Open items:
- The toggle frames (rest↔fade) cost more. Chromium: a stacking-context flip forces full layout (`cr_toggle_not_le`, `cr_enter_layout_zero`). WebKit: one extra layout unit (`wk_toggle_layout_units`, `wk_toggle_not_le`). So the golden rows show layout/paint as `any` on Chromium and no measurable win anywhere: the rest saving is in `comp`, which has no counter.
- The WebKit rest win is comp plus resident only. The WebKit fade trade is not ordered.
- On the lane, the original panel may already be composited (own); then the fade trade gives nothing. Unverified.
- RG10 is a premise. Check it on the rewrite DOM (research/notes/2026/10-18-engine-gaps.md:462-496).

Read first: the module doc of MorphPanelOpt.lean (engine cites), then the golden section at its end.

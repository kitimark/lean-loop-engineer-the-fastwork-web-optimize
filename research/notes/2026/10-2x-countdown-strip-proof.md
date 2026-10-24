# morph.countdown:strip: same face per frame, layers 80 to 8 (census) and 160 to 16 (platform)

Task `countdown-strip-proof`, candidate 4 of `research/notes/2026/10-2x-end-gpu-map.md`. Flags
`hero.countdown:strip` + `morph.countdown:strip` (the second requires the first, `part.json`).

## Answer

- **Same look, PROVED** for one digit at every driver call: `Fw.Parts.MorphCountdownStrip.same_face_px`. The two
  runs of `createCountdownDriver` pair call by call; their slots are equal (spring, target, timing, cell) and, once the
  spacer height is known, the visible glyphs of the strip DOM equal those of the ten-face DOM inside the digit's clip
  window (`dom_same`, from `HeroCountdownOpt.strip_digit_same`). Before the first cell neither variant has written.
- **Layers, PROVED** from a cited model: `layers_80_to_16` (8 digits, Normal policy, scene active):
  faithful 80 composited RenderLayers and 160 platform layers, strip 8 and 16. `layers_7_digits`: 70/140 to 7/14
  (9 days or fewer left). `layers_ratio`: 10 to 1 under every policy, digit count and clip chain.
  `layers_conservative`, `layers_paused`: 0 in both variants.
- **Simulator census, MEASURED** (webkit-sim 40081936555 at bbd203c with both flags, against 39897814980 at 540130e9
  with none; the countdown code did not change between the two shas): every zone has 80 `hero-module_face` layers
  before and 8 `hero-module_strip` layers after; no other layer is added or removed in the finish zone.
- **Gate: no verdict.** Run 40081933958 stopped in the smoke step: `?fw=hero.countdown:strip,morph.countdown:strip`
  is not prerendered; the prerendered key is `?fw=morph.countdown:strip,hero.countdown:strip`. Both dispatches of
  the budget are spent.

## Census per zone (pass 1 / pass 2)

| y (base / flag) | layers base | layers flag | countdown layers | countdown MB base | countdown MB flag | total MB base | total MB flag |
|---|---|---|---|---|---|---|---|
| 0 | 106 / 110 | 40 / 34 | 80 -> 8 | 0.591 | 2.287 | 36.15 / 41.32 | 38.06 / 42.80 |
| 1500 | 116 / 114 | 40 / 46 | 80 -> 8 | 0 | 0 | 87.02 / 87.05 | 87.02 / 87.06 |
| 3000 | 140 / 136 | 68 / 68 | 80 -> 8 | 0 | 0 | 101.26 | 101.26 |
| 4500 | 145 / 141 | 73 / 73 | 80 -> 8 | 0 | 0 | 149.26 / 153.64 | 153.37 / 149.26 |
| finish 5231 / 5267 | 128 / 124 | 56 / 56 | 80 -> 8 | 0 | 0 | 105.79 | 97.87 |

- Finish zone, layer by layer: the only differences are the 72 countdown layers and the `#platform` section backing
  (21.19 MB to 13.27 MB). The finish y differs (5231 vs 5267) because the base harness read the document at 6006 px
  before it settled at 6042; the platform backing difference follows the tile coverage at a different scroll offset
  (INFERRED), not the strip.
- The morph.countdown clock adds no layer in any static zone in either run: its scene is paused there and
  `morph.module.css` sets `will-change: auto !important` (`layers_paused`). Its 80 to 8 saving shows only while the
  menu opens; the earlier morph-open runs measured new layers 81-83 to 9-11 (39775174615, 39776549128 base;
  39775198022, 39776554155 flag).
- Backing cost, MEASURED at y 0: 0.591 MB to 2.287 MB for the hero clock, 3.9 times per digit.
  `HeroCountdownOpt.strip_backing_gt` predicts only 12 cells against 10; why the faces back less than 10 cells was
  not read (OPEN). The finish zone has the clock off screen, 0 MB both.

## Layer model (WebKit @862f17d)

- A RenderBox with `will-change: transform` composites under the Normal policy and not under Conservative off Mac
  (`RenderLayerCompositor.cpp:3997-4018`). Faces and strips are absolute RenderBoxes with `will-change: transform`
  (`hero.module.css`, checked by `strip.test.ts`).
- Each composited layer clipped by an ancestor gets an ancestor clipping stack (`computeAncestorClippingStack`,
  `RenderLayerCompositor.cpp:3651-3764`): plain overflow clips merge into one entry, a composited scroller and a
  rounded clip are their own entries. The chain `.digit`, `.value` (overflow hidden, no radius), `.unit` (radius
  without overflow, so no clip), morph.panel `.center` (overflow hidden) gives one entry (`clipStack countdownChain`).
- One "ancestor clipping" GraphicsLayer per entry (`RenderLayerBacking.cpp:2444-2457`), without backing store
  (`backingStoreMemoryEstimate`, `RenderLayerBacking.cpp:5190-5196`). The inspector census lists composited
  RenderLayers only (`InspectorLayerTreeAgent.cpp:156-163`), so it shows 80 and 8; the platform tree (UIViews on
  iOS) holds 160 and 16.

## Golden

`packages/contracts/golden/parts/morph.countdown.strip.jsonl`, written by `Fw.Parts.MorphCountdownStrip.jsonl` and
checked by `#guard` at build time: 30 offset rows (10 springs x cells 31, 36, 52), 6 driver scenarios (ones roll,
0 to 9 wrap, reduced motion, no cell yet, restart mid-roll, uneven frame gaps), 4 layer rows. Exact rationals as
`num/den`. `apps/site/src/parts/morph.countdown/strip.test.ts` replays every scenario through `createCountdownDriver`
in both variants (tolerance 1e-9 relative) and checks the CSS premises of the layer model.

## Limits

- One digit per proof; digits share no state in the driver, so a clock is the per-digit statement repeated.
- Strip subpixel sampling against the faithful faces is left to the gate's pixel tolerance; no gate verdict yet.
- UIView creation time on the phone is not measured.
- Platform layer counts (160, 16) are from source; the census sees backings only.

## Open

- Gate verdict: one dispatch with the prerendered flag order,
  `pnpm -s fw run --gate --engines both --fw morph.countdown:strip,hero.countdown:strip --ref ci/countdown-strip-proof`.
  `packages/gate-breakpoints/src/anchors.json` has a strip variant role for hero.countdown and none for
  morph.countdown, whose `face` role (`[data-fw="morph-countdown-clock"] [data-face]`) finds no node under strip.
  The morph.countdown entry needs the same variant role (outside this task's writes) before the gate can pass.
- `fw run --gate` dispatched a flag string the build had not prerendered; a canonical order check before dispatch
  would have refused it locally.

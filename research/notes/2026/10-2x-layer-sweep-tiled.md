# platform.sweep:layer-sweep, tiled revision: the layer copies the original's repeat tiling and the snapped word width; WebKit's word pixels now match (its 35 was the original's stray pixel at the page origin), Chromium keeps 33 at the last glyph's edge column at progress 0, so the flag stays a look change (class L)

* Answer (MEASURED, CI only). The revised layer (two tiles of 3 word widths, `background-size: 50% 100%`, `repeat-x`, translate -2w to 0, width from the device-pixel word width set once per resize) leaves the look verdict where it was: class L. Premise `sweep.layer-pixels` at bound 12 (runs 40334403316 at 1ea54a376 and 40335144234 at 4eb3f50f1) fails on Chromium (33 of 255) and on WebKit (35). Run 40336086853 (70cd1645b, registered bound 40) passes and carries the split reading below.
* WebKit (MEASURED, run 40336086853): inside the word the layer and the original differ by at most 2 at every time (row 0, progress 0: 0 pixels). The 35 is one pixel at (0, 0) of the screenshot, 388 px left of the word, and it belongs to the original: the original with `repeat` and the original with `no-repeat` differ only there (35), the layer equals the `no-repeat` original everywhere (0). The earlier reading "the original's own tile seam at the word's right edge" (10-2x-platform-sweep-layer.md) was a misplacement: the pixel is not near the word. The premise test now reports it as `corner` (a 4 x 4 px box at the page origin), separate from `wordMax`. Whether the stray pixel also appears on the live page is INFERRED not measured (no pixel at the live page origin was read).
* Chromium (MEASURED, run 40336086853): at progress 0 nine pixels differ, all in column x = 526 (the word box ends at 526.8125): three by 33 (the crossbar of the last `t`, original (63, 68, 76), layer (96, 100, 106)), the rest by 8 to 9; at 0.5 s and later at most 3. None of these changes it: the tiled layer, the snapped width (the probe with the unsnapped 600% width gives 33 too), `will-change: auto` (33), `overflow: clip` on the word (33), `clip-path: inset(0)` on the word (33). A flat white gradient on both gives the same 33, and the same flat gradient at -0.5 s gives 0, so the colour of the gradient is not the cause; the pixels depend on where the original's tile ends at progress 0. The original's alpha at that column is 0.186 against the layer's 0.326 (ratio 0.57). That ratio equals the fraction of the tile's right edge when the tile is 3 x the unsnapped word width: 331 + (-2 x 195.578) + 3 x 195.578 = 526.578, so the original draws its tile with an anti-aliased end at 526.58 and, at progress 0 only, that edge lies inside the last painted column (INFERRED from the number; no source read of the tile-size choice beyond background_image_geometry.cc:392-401). The layer's own repeat seam is seamless, so it cannot show that dip. It lasts the frames at the loop start (-1 ms already gives 24).
* Lean (PROVED, `lean/Fw/Parts/PlatformSweepLayer.lean`, golden `platform-sweep-layer.jsonl` 183 lines, replayed by `apps/site/src/parts/platform.sweep/layer.test.ts`): `tiled_same_look` (the two-tile layer shows the colour of the original with `repeat` for every x from the left edge to 4w and every t, w > 0), `layerU_eq_frac` (two `repeat-x` tiles read the same fraction as a repeating image on the whole 6w), `seam_at_start` (the start-seam pixel), `snap_box` (the snapped width is within one device pixel of the true one, strictly), `snapW_grid`, `snapPx_pos`, `tile_grid` (the layer and tile sizes are whole device pixels). Unmodelled: the 1/64 LayoutUnit step, the left overhang of the glyphs (the left end of the layer starts at the progress offset, so only x >= 0 is covered), and the original's anti-aliased tile edge above. `memory_ok` now holds against 16 MiB (six word widths).
* Gate (MEASURED): breakpoint gate on both engines PASSES, run 40335795674 (`--fw platform.sweep:layer-sweep`, 4eb3f50f1; Chromium j0-j2 and WebKit j0-j3 jobs green). The ten class-L FlagDelta tuples excuse the word deltas as before; the layer's own properties are not a gated role.
* Counts (MEASURED, Chromium, Lean reader packages/measure-chromium/src/offscreen-windows-cli.mjs, profile swipe-touch-v1, 3 runs per arm, one commit 4eb3f50f1; base run 40335918249, arm run 40335928775). The table equals the untiled variant's (10-2x-platform-sweep-layer.md): the approach window is a gain, every end window is no-gain because Paint reads +1 per frame, as before.
* WebKit Simulator counts: NOT RUN (state waiting). wk-sim-hang has not landed on main (no commit, no docs/team/handoffs/wk-sim-hang.md at a39f27950). Dispatch when it has, from this branch pushed as ci/layer-sweep-tiled: `pnpm -s fw run --target rewrite --engines webkit --ref ci/layer-sweep-tiled` (base) and the same with `--fw platform.sweep:layer-sweep` (arm), 3 VMs each, read with the Lean minVms reader packages/measure-webkit/src/offscreen-webkit-cli.mjs.

## Counts per window (Chromium, swipe-touch-v1, 3 runs, end frame 574)
| window | verdict | differs |
|---|---|---|
| approach | gain | RasterTask 236 to 63, PaintImage 137 to 1 |
| end 0-19 | no-gain | Paint 335 to 360 (cost), RasterTask 517 to 467, PaintImage 495 to 423 |
| end 20-59 | no-gain | Paint 252 to 292 (cost), PaintImage 454 to 294 |
| end 60-119 | no-gain | Paint 120 to 180 (cost), PaintImage 240 to 0 |
| end 120+ | no-gain | Paint 94 to 141 (cost), PaintImage 188 to 0 |
| finish | no-gain | Paint 915 to 1087 (cost), RasterTask 1207 to 984, PaintImage 1514 to 718 |

## Runs
| what | run | commit | result |
|---|---|---|---|
| premise bound 12 | 40334403316 | 1ea54a376 | Chromium 33, WebKit 35 (fail) |
| premise bound 12 + differing pixels, clip-path and unsnapped probes | 40335144234 | 4eb3f50f1 | same; pixel lists above |
| premise bound 40 + corner split + flat-white probes | 40336086853 | 70cd1645b | pass; wordMax Chromium 33, WebKit 2 |
| breakpoint gate, both engines | 40335795674 | 4eb3f50f1 | pass |
| Chromium counts base / arm | 40335918249 / 40335928775 | 4eb3f50f1 | table above |

The site code at 70cd1645b equals 4eb3f50f1 (only part.json text differs).

Registered bound stays 40 (as before); the bound-12 reading is the one above. The variant stays class L: the FlagDelta rows (ten tuples) and the look-change candidate stay `L`; only the reasons and the premise theorem name (`tiled_same_look`) changed.

## Limits
CI only (no phone pass); the Chromium residual is not removed. One idea not tried: a gradient whose last tile column has the original's fractional alpha, which depends on the word width and is not a same-look rewrite.

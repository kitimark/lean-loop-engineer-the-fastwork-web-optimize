# platform.sweep:layer-sweep: the gradient is a transform layer under a static text mask; Chromium raster work falls, Paint still reads +1 per frame, WebKit Paint falls (undecided, 2 arm VMs); pixels differ at t=0 by up to 35/255

* Answer (MEASURED, CI only). On Chromium the variant removes the sweep's raster work like the probe arm did (finish RasterTask 1207 to 984, PaintImage 1514 to 718) but the Lean verdict reads no-gain after the approach because Paint rises 915 to 1087 (a cost by the rule). Approach window: gain (RasterTask 236 to 63, PaintImage 137 to 1). The look check passes within 40 of 255 but not within 12: at progress 0 the pixels differ by up to 33 (Chromium, 9 pixels) and 35 (WebKit, 1 pixel) of 255, later times by at most 5. The variant is not called same-look; the flag is a look change (class L): user visual review, never a preset. WebKit (MEASURED, 3 base VMs, 2 arm VMs, so undecided by the 3-VM rule): the reader reads Paint less in every zone (finish 172-214 to 129-142, whole 1197-1379 to 1051-1160).
* Lean (PROVED, `lean/Fw/Parts/PlatformSweepLayer.lean`, golden `platform-sweep-layer.jsonl`): `same_look` (layer shows the original colour at every point and time, every width), `layerX_eq`, `css_close` (CSS -66.6667% within w/1e6 px), `orig_repaints` / `layer_no_text_repaint` / `run_work` (original repaints the text mask once per word per frame, variant never, under the engines' compositor-property table), `memory_ok` (four layers at most 8 MiB at ratio 3).
* Source (CONFIRMED): transform runs on the compositor and background-position does not (Chromium `compositor_animations.cc:193-208@f842f52`; WebKit `CSSProperties.json` animation-wrapper-acceleration on transform :12112, none on background-position, `@862f17d`). Text-fill-box painting goes through a separate layer pair (Chromium `box_painter_base.cc:1557-1598`; WebKit `BackgroundPainter.cpp:443-450`).
* Why Paint is +1: INFERRED, the extra gradient layer gets its own paint per frame in the counter, as in the probe-off arm (per-frame view 640-665: Paint 2 to 3, PaintImage 4 to 0, UpdateLayer unchanged).

## Runs (all at commit fbc6ee4ff, base and arm same commit)
| engine | arm | run | n |
|---|---|---|---|
| Chromium swipe-touch-v1 | base | 40261037706 | 3 runs |
| Chromium | layer-sweep | 40261040439 | 3 runs |
| WebKit Simulator | base / layer-sweep | 40261071388 / 40261059419 | base 3 VMs (r1-r3), layer-sweep 2 VMs (r1, r3: job r2 failed twice in `Determinism sessions`, Simulator inspector dead, simctl shutdown timed out) |
| breakpoint gate, both engines | layer-sweep | 40261067591 (FAIL, no FlagDelta tuples), 40264767557 (FAIL, one tuple missing), 40266919532 (PASS at 719a63dd0, ci/platform-sweep-layer-g2) | both engines |
| look check (premise `sweep.layer-pixels`, ci/platform-sweep-layer-pix) | | 40261302718 (bound 12 failed: 33, 35), 40261606105 (bound 40 held), 40264170237 (padded layer, bound 12 failed: 33, 35), 40264978871 (mechanism probes, bound 40 held) | Chromium HS 156, WebKit 27.2 |

The counts above are at fbc6ee4ff, the gate and look runs at the later commits 719a63dd0 and d4f8f292f; the site code and CSS are the same.

## Chromium (MEASURED; Lean cmp/judge, slack 0; reader is a scratch TS stand-in)
| window | frames | verdict | differs |
|---|---|---|---|
| approach | 34 | gain | RasterTask 236 to 63, PaintImage 137 to 1 |
| end 0-19 | 20 | no-gain | Paint 335 to 360 (cost), RasterTask 517 to 467, PaintImage 495 to 423 |
| end 20-59 | 40 | no-gain | Paint 252 to 292 (cost), PaintImage 454 to 294 |
| end 60+ | 137 | no-gain | Paint 274 to 411 (cost), PaintImage 548 to 0 |
| finish | 201 | no-gain | Paint 915 to 1087 (cost), RasterTask 1207 to 984, PaintImage 1514 to 718 |

## WebKit (MEASURED, Simulator iOS 27, offscreen-webkit reader, sameWindow, common window y <= 5200; base n = 3 VMs / 6 passes, layer-sweep n = 2 VMs / 4 passes: UNDECIDED by the rule, the reader's reading is shown)
| zone | steps | reader | Paint base / arm | Layout base / arm | RecalculateStyles base / arm | Composite | FireAnimationFrame |
|---|---|---|---|---|---|---|---|
| z4500 | 10 | gain (Paint less) | 113-147 / 93-106 | 43-60 / 56-69 | 46-56 / 50-62 | 20 / 20 | 53 / 53 |
| z5000 | 5 | gain (Paint less) | 59-69 / 36-38 | 20-30 / 27-30 | 22-32 / 30-32 | 10 / 10 | 22-26 / 22 |
| finish | 15 | gain (Paint less) | 172-214 / 129-142 | 63-90 / 83-97 | 68-88 / 81-92 | 30 / 30 | 75-79 / 75 |
| whole | 105 | gain (Paint less) | 1197-1379 / 1051-1160 | 612-655 / 628-663 | 641-684 / 643-670 | 209 / 209 | 664-671 / 666-667 |

Every zone is undecided with n = 2 arm VMs; a third arm VM did not run (its job failed twice on a dead Simulator inspector, not on the variant). The ranges do not overlap for Paint in any zone; Layout and RecalculateStyles read slightly higher in the arm ranges but are inside the reader's slack.

## Gate (final run 40266919532, both engines, ci/platform-sweep-layer-g2 at 719a63dd0)
PASS. Run 40261067591 failed platform.sweep on exactly the intended computed-style deltas of the word (background-clip, background-image, display, position, mask-image, mask-clip, and the -webkit- forms on WebKit); no box, size or in-flow position item failed. `Fw.Gate.FlagDelta` now lists ten class-L tuples for `platform.sweep:layer-sweep` (role word; golden `flag-delta.jsonl`), so those readings are excused and still listed for the visual review. Run 40264767557 failed only on `position`: the original's first three words are `relative` in every motion setting, the faithful rewrite never declared `position`, and the variant declares it (under reduced motion it stays static); that tuple (relative to static) was added for 40266919532.

## Look check (the variant is NOT same-look at the pixel level)
Premise `sweep.layer-pixels` (fixed progress 0, 0.5, 1.5, 2.5, 3.9 s, paused animations, no seeking), CI run 40264978871: worst channel difference per time Chromium 33, 5, 4, 2, 2; WebKit 35, 2, 2, 4, 3 of 255. At t=0, 9 pixels differ in Chromium (3 by more than 12) and 1 in WebKit. The Lean `same_look` theorem covers the gradient position over time (the colour at each point), not the pixels.

Mechanism, from probes in the same premise (a row pair per probe):
* The first hypothesis (INFERRED: glyph overhang beyond the layer edge) is refuted. A layer padded by 6px per side (image in the content box, translate +8px; run 40264170237) left the t=0 numbers unchanged at 33 and 35, so the layer edge is not the cause. That layer was dropped.
* WebKit (MEASURED): the original with `background-repeat: repeat` differs from the original with `no-repeat` by 35, and the layer word equals the no-repeat original exactly (0). The 35 is the original's own background tile seam at progress 0, where the tile's right edge lies on the word's right edge; the variant has no seam.
* Chromium (MEASURED): repeat and no-repeat originals are identical (0), so it is not the tile seam; `will-change: auto` on the layer gives the same 33, and a delay of -1 ms gives 24. The differing pixels are 3 rows of the column at x = 526 (the word's box edge at 526.81): the original reads (63, 68, 76), the layer (96, 100, 106) (run 40264423344), a coverage difference on one edge column near progress 0. The mechanism inside Chromium's paint (INFERRED: the original's tile is pixel-snapped to end on the box edge at progress 0) is not shown by the engine source here; a reading of `background_image_geometry.cc` is the follow-up.
The bound stays 40 of 255 and the registry statement says so. The variant stays in the look-change class for the user's visual review.

## Limits
No phone pass (phone-compose-counts). Chromium reader is a TS stand-in. Memory is not measured, only bounded in Lean.

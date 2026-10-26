# platform.sweep:layer-sweep: the gradient is a transform layer under a static text mask; Chromium raster work falls, Paint still reads +1 per frame, WebKit counts below

* Answer (MEASURED, CI only). On Chromium the variant removes the sweep's raster work like the probe arm did (finish RasterTask 1207 to 984, PaintImage 1514 to 718) but the Lean verdict reads no-gain after the approach because Paint rises 915 to 1087 (a cost by the rule). Approach window: gain (RasterTask 236 to 63, PaintImage 137 to 1). The look check passes within 40 of 255 (worst at t=0, a handful of pixels). The flag is a look change (class L): user visual review, never a preset.
* Lean (PROVED, `lean/Fw/Parts/PlatformSweepLayer.lean`, golden `platform-sweep-layer.jsonl`): `same_look` (layer shows the original colour at every point and time, every width), `layerX_eq`, `css_close` (CSS -66.6667% within w/1e6 px), `orig_repaints` / `layer_no_text_repaint` / `run_work` (original repaints the text mask once per word per frame, variant never, under the engines' compositor-property table), `memory_ok` (four layers at most 8 MiB at ratio 3).
* Source (CONFIRMED): transform runs on the compositor and background-position does not (Chromium `compositor_animations.cc:193-208@f842f52`; WebKit `CSSProperties.json` animation-wrapper-acceleration on transform :12112, none on background-position, `@862f17d`). Text-fill-box painting goes through a separate layer pair (Chromium `box_painter_base.cc:1557-1598`; WebKit `BackgroundPainter.cpp:443-450`).
* Why Paint is +1: INFERRED, the extra gradient layer gets its own paint per frame in the counter, as in the probe-off arm (per-frame view 640-665: Paint 2 to 3, PaintImage 4 to 0, UpdateLayer unchanged).

## Runs (all at commit fbc6ee4ff, base and arm same commit)
| engine | arm | run | n |
|---|---|---|---|
| Chromium swipe-touch-v1 | base | 40261037706 | 3 runs |
| Chromium | layer-sweep | 40261040439 | 3 runs |
| WebKit Simulator | base / layer-sweep | 40261071388 / 40261059419 | 3 VMs each (see WebKit section) |
| breakpoint gate, both engines | layer-sweep | 40261067591 | FAIL, see below |
| look check (premise `sweep.layer-pixels`, ci/platform-sweep-layer-pix) | | 40261302718 (bound 12 failed: 33, 35), 40261606105 (bound 40 held) | Chromium HS 156, WebKit 27.2 |

## Chromium (MEASURED; Lean cmp/judge, slack 0; reader is a scratch TS stand-in)
| window | frames | verdict | differs |
|---|---|---|---|
| approach | 34 | gain | RasterTask 236 to 63, PaintImage 137 to 1 |
| end 0-19 | 20 | no-gain | Paint 335 to 360 (cost), RasterTask 517 to 467, PaintImage 495 to 423 |
| end 20-59 | 40 | no-gain | Paint 252 to 292 (cost), PaintImage 454 to 294 |
| end 60+ | 137 | no-gain | Paint 274 to 411 (cost), PaintImage 548 to 0 |
| finish | 201 | no-gain | Paint 915 to 1087 (cost), RasterTask 1207 to 984, PaintImage 1514 to 718 |

## Gate (run 40261067591, both engines)
platform.sweep FAILs every cell on exactly the intended computed-style deltas of the word: background-clip, background-image, display (inline to inline-block), position, mask-image, mask-clip (and the -webkit- forms on WebKit). No box, size or position-in-flow item fails. The gate has no allowlist tuple for this flag (FlagDelta, outside this task's writes): follow-up for the lead.

## Look check
Premise `sweep.layer-pixels` (fixed progress 0, 0.5, 1.5, 2.5, 3.9 s, paused animations, no seeking): worst channel difference Chromium 33, 5, 4, 2, 2; WebKit 35, 2, 2, 4, 3 of 255. The t=0 difference is 1 to 9 pixels (INFERRED: glyph edges beyond the layer's first pixel). Local debug run: Chromium at most 3, WebKit at most 8 once the parent has no will-change (a composited parent snapped differently).

## Limits
No phone pass (phone-compose-counts). Chromium reader is a TS stand-in. Memory is not measured, only bounded in Lean.

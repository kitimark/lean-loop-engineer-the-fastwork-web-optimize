# platform.sweep:layer-sweep: the gradient is a transform layer under a static text mask; Chromium raster work falls, Paint still reads +1 per frame, WebKit Paint falls (undecided: 2 arm VMs, then a re-run lost 5 of 6 more); pixels differ at t=0 by up to 35/255

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
| WebKit Simulator re-run (task layer-sweep-webkit-n3, ci/layer-sweep-webkit-n3 at 9493a5ddb) | base / layer-sweep | round 1 40277969074 / 40277972324, round 2 40284460392 / 40284464262 | 12 VM jobs, 9 lost; complete sessions base 2 VMs, layer-sweep 1 VM; undecided (see the re-run section) |
| breakpoint gate, both engines | layer-sweep | 40261067591 (FAIL, no FlagDelta tuples), 40264767557 (FAIL, one tuple missing), 40266919532 (PASS at 719a63dd0, ci/platform-sweep-layer-g2) | both engines |
| look check (premise `sweep.layer-pixels`, ci/platform-sweep-layer-pix) | | 40261302718 (bound 12 failed: 33, 35), 40261606105 (bound 40 held), 40264170237 (padded layer, bound 12 failed: 33, 35), 40264978871 (mechanism probes, bound 40 held) | Chromium HS 156, WebKit 27.2 |

The counts above are at fbc6ee4ff, the gate and look runs at the later commits 719a63dd0 and d4f8f292f; the site code and CSS are the same.

## Chromium (MEASURED; Lean cmp/judge, slack 0; reader packages/measure-chromium/src/offscreen-windows-cli.mjs, Lean Fw.Measure.OffscreenWindows; it splits end 60+ into 60-119, Paint 120 to 180, and 120+, Paint 94 to 141)
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

## WebKit re-run at one commit (task layer-sweep-webkit-n3, ci/layer-sweep-webkit-n3 at 9493a5ddb; still UNDECIDED)
Two rounds of `fw run --engines webkit --runs 3` per arm (base and `--fw platform.sweep:layer-sweep`), same commit, free GitHub macOS, no extra push. Of 12 VM jobs 9 were lost (MEASURED: the job log and the artifact `webkit-sim-r<k>`), so no arm reached 3 complete VMs.

| arm | run | VM job: result |
|---|---|---|
| base | 40277969074 | r1 lost (stalled at pass 2/2, pass 1 kept), r2 lost (exit 124, pass 1 kept), r3 complete |
| base | 40284460392 | r1 complete, r2 lost (pass 1 kept), r3 lost (no pass) |
| layer-sweep | 40277972324 | r1 complete, r2 lost (inspector dead, exit 4, no pass), r3 lost (same, no pass) |
| layer-sweep | 40284464262 | r1 lost (pass 1 kept), r2 lost (stalled, no pass), r3 lost (inspector dead, exit 4, no pass) |

Read with the committed reader `packages/measure-webkit/src/offscreen-webkit-cli.mjs` (Lean `Fw.Measure.OffscreenWebkit`: minVms 3, sameWindow over equal step sets, common window y <= 5200), VM dirs copied under distinct `webkit-sim-r<k>` names (a VM is one job of one run; two rounds are independent VMs at the same commit):
* Complete sessions only (the reader's input): base 2 VMs (40277969074 r3, 40284460392 r1), layer-sweep 1 VM (40277972324 r1). Every zone `undecided (n=2+1 VMs)`, pass rule `noData`.
* With the kept passes of lost VMs (a `.part` file is one finished pass, wrapped as a one-pass session for the same reader; this is not the reader's committed input): base 5 VMs / 7 passes, layer-sweep 2 VMs / 3 passes. Every zone `undecided (n=5+2 VMs)`; the pass rule alone (not the verdict) reads `gain, Paint less`.

| zone | steps | complete sessions: Paint base / arm | with kept passes: Paint base / arm | Layout base / arm (kept) | RecalculateStyles base / arm (kept) | Composite | FireAnimationFrame (kept) |
|---|---|---|---|---|---|---|---|
| z4500 | 10 | 128-150 / 65-83 | 128-150 / 65-103 | 46-63 / 44-63 | 47-60 / 44-58 | 20 / 20 | 53 / 53 |
| z5000 | 5 | 52-66 / 34-42 | 52-66 / 34-42 | 23-32 / 20-29 | 28-32 / 23-32 | 10 / 10 | 22-24 / 22-27 |
| finish | 15 | 180-215 / 107-117 | 180-215 / 107-142 | 70-95 / 64-92 | 75-92 / 69-90 | 30 / 30 | 75-77 / 75-80 |
| whole | 105 | 1229-1344 / 1146-1208 | 1229-1391 / 1008-1208 | 612-634 / 607-649 | 645-671 / 628-672 | 209 / 209 | 667-669 / 667-672 |

Paint ranges do not overlap in z4500, z5000 and finish in either read; in whole they overlap in the complete-session read (1229-1344 against 1146-1208), so the earlier whole-range "no overlap" is not repeated at this n. Layout and RecalculateStyles read the same or slightly lower. No zone is decided: the rule needs 3 VMs per arm. The direction agrees with the first read (finish 172-214 to 129-142), still as a reading and not a verdict.

Why the VMs were lost (harness cause, INFERRED from the logs; no variant effect, base lost 4 of 6 jobs and the arm 5 of 6): in all 9 lost jobs the first inspector call that timed out after 120 s (warm-up `Runtime.evaluate` in 6 jobs, scroll-run `Runtime.evaluate` or `Timeline.stop` in 3) was followed by a reconnect that found "no page target" for minutes (two of the three complete sessions had the same warm-up timeout, so the first timeout alone does not decide a VM), and the runner host sat at load average 157 to 970 on 3 CPUs, 800 to 1000 in the complete sessions too (`runner.json` cpus 3; session logs "event loop blocked: the 30 s tick came 165 s late"; `r<k>-host.txt` lists the Simulator's own daemons as the top CPU users, diagnosticd, SimRenderServer, backboardd, WebContent; our node process 1%). Lost jobs then ended in the inspector going dead (simctl shutdown ETIMEDOUT, "terminate Safari took longer than 20 s", exit 4), a 720 s no-output stall, or the 124 job timeout. The round-2 jobs also waited 50 to 120 min for a macOS slot (others' lanes held the 5 slots). Not changed here: a harness fix (an earlier abort of a VM whose first warm-up times out, or fewer Simulator daemons) is a follow-up; the variant stays undecided on WebKit.

## Gate (final run 40266919532, both engines, ci/platform-sweep-layer-g2 at 719a63dd0)
PASS. Run 40261067591 failed platform.sweep on exactly the intended computed-style deltas of the word (background-clip, background-image, display, position, mask-image, mask-clip, and the -webkit- forms on WebKit); no box, size or in-flow position item failed. `Fw.Gate.FlagDelta` now lists ten class-L tuples for `platform.sweep:layer-sweep` (role word; golden `flag-delta.jsonl`), so those readings are excused and still listed for the visual review. Run 40264767557 failed only on `position`: the original's first three words are `relative` in every motion setting, the faithful rewrite never declared `position`, and the variant declares it (under reduced motion it stays static); that tuple (relative to static) was added for 40266919532.

## Look check (the variant is NOT same-look at the pixel level)
Premise `sweep.layer-pixels` (fixed progress 0, 0.5, 1.5, 2.5, 3.9 s, paused animations, no seeking), CI run 40264978871: worst channel difference per time Chromium 33, 5, 4, 2, 2; WebKit 35, 2, 2, 4, 3 of 255. At t=0, 9 pixels differ in Chromium (3 by more than 12) and 1 in WebKit. The Lean `same_look` theorem covers the gradient position over time (the colour at each point), not the pixels.

Mechanism, from probes in the same premise (a row pair per probe):
* The first hypothesis (INFERRED: glyph overhang beyond the layer edge) is refuted. A layer padded by 6px per side (image in the content box, translate +8px; run 40264170237) left the t=0 numbers unchanged at 33 and 35, so the layer edge is not the cause. That layer was dropped.
* WebKit (MEASURED): the original with `background-repeat: repeat` differs from the original with `no-repeat` by 35, and the layer word equals the no-repeat original exactly (0). The 35 is the original's own background tile seam at progress 0, where the tile's right edge lies on the word's right edge; the variant has no seam.
* Chromium (MEASURED): repeat and no-repeat originals are identical (0), so it is not the tile seam; `will-change: auto` on the layer gives the same 33, and a delay of -1 ms gives 24. The differing pixels are 3 rows of the column at x = 526 (the word's box edge at 526.81): the original reads (63, 68, 76), the layer (96, 100, 106) (run 40264423344, a failed probe run at bound 12), a coverage difference on one edge column near progress 0.
Source trace of the t=0 column (task layer-sweep-webkit-n3, pinned Chromium f842f52, files under third_party/blink/renderer/: core/paint/ for the .cc files, platform/graphics/compositing_reasons.h, core/layout/geometry/physical_rect.h, platform/geometry/layout_unit.h):
  * Original path (CONFIRMED, code shown): a word with `background-clip: text` takes the text fill box branch (box_painter_base.cc:1492-1497, `PaintFillLayerTextFillBox`). The mask rect is `ToPixelSnappedRect(rect)` (box_painter_base.cc:1569). The background geometry snaps the dest rect and the positioning area to whole pixels (`ToPixelSnappedRect`, background_image_geometry.cc:392-401), and snaps the dest rect again after clipping (:754). The text fill box adds no dest adjustment (:275-278). `ToPixelSnappedRect` rounds the left edge and the right edge of the box separately (physical_rect.h:228 with `SnapSizeToPixel`, layout_unit.h:805-818), so a box edge at 526.81 gets a fill that ends on column 527.
  * Variant path (CONFIRMED, code shown): `.layerBg` has `will-change: transform`, which is in `kPreventingSubpixelAccumulationReasons` (compositing_reasons.h:116), so `CanPropagateSubpixelAccumulation` returns {false, false} (paint_property_tree_builder.cc:731-735) and `UpdateForPaintOffsetTranslation` rounds the paint offset and resets the fractional part to zero (:763-790, `ResetPaintOffset()`). The layer's gradient is therefore painted at a whole-pixel offset and the compositor moves it with the animated transform. With `will-change: auto` the active transform animation is a translation, which propagates the fraction (:737-747); the probe with `will-change: auto` still gave 33, so this discard is not the whole cause of column 526.
  * Not traced: which of the three differing pixels of column 526 gets which coverage, and which of the two paths puts the edge on 526 or 527. That needs a pixel-level raster trace (the snapped fill of the original against the layer's edge under the text mask) that this task did not run. So the statement "the column 526 difference is the snapped edge of the original against the layer path" is INFERRED: the two code paths differ as shown, and the column values stay MEASURED only (original 63, 68, 76; layer 96, 100, 106). An earlier draft said the layer path "is not snapped"; the source does not say that, so that wording is dropped.
The bound stays 40 of 255 and the registry statement says so. The variant stays in the look-change class for the user's visual review.

## Limits
No phone pass (phone-compose-counts). Memory is not measured, only bounded in Lean.

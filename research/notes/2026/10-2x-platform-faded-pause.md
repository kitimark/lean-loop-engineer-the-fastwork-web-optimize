# platform:faded-pause (task platform-faded-pause)

Rank 3 of research/notes/2026/10-26-end-of-page-variants.md. Status: built; gate PASS on both engines; Chromium measured; WebKit not run (reason below).

## What the flag does
- The tween reports "fade is 0" (m at or past 0.55) once per edge (`fadedBus`). The platform section's one `data-fw-scene`
  writer (`createSceneWriter`, scene.ts) writes `paused` when the observer says offscreen OR the section is faded.
- The existing paused rule (platform.module.css:22-26) pauses CSS animations and drops `will-change`. The dash svgs'
  SMIL clocks are paused and seeked through the glint pause (`createPause`, platform.glint/pause.ts).
- On the way back the scene value returns to `active`, the style is flushed (`getAnimations`) and each CSS animation's
  saved start time is put back, so it reads the uninterrupted phase. Finished animations (settled entries) are skipped.
- No `visibility:hidden` is used, so the class stays E.

## Lean (lean/Fw/Parts/PlatformFadedPause.lean)
- `zero_iff`: the fade is 0 exactly from `fadeEnd`.
- `faded_same_pixels`: at fade 0 the page pixel is the backdrop for any subtree colour (premise: no descendant escapes the
  opacity group; the census test in fadedpause.test.ts rejects portals, dialogs, popovers, fullscreen, backdrop and
  view transitions in the platform sources).
- `frame_same`, `visible_phase`: every frame with fade above 0 reads the faithful CSS phase; `faded_no_tick`,
  `faded_run`: faded frames do not tick.
- `glint_phase`: the SMIL clock is the uninterrupted one whenever it runs.
- `scene_offscreen`, `scene_faded`, `scene_neither`: one theorem per branch of the writer's OR.
- Golden: packages/contracts/golden/parts/platform-faded-pause.jsonl (generated), replayed in fadedpause.test.ts.

## Engine sources (read before citing)
- Chromium paint_layer_painter.cc:168-191@f842f52 `PaintedOutputInvisible` (opacity below 0.0004, no opacity animation,
  no will-change opacity, no backdrop filter); used at :424, where it only wraps the recording in
  `ScopedEffectivelyInvisible`. The layer is still recorded; the note's mechanism holds. A WAAPI opacity animation
  (fade-threaded) would defeat the predicate (`HasCurrentOpacityAnimation`).
- WebKit RenderLayer.cpp:6147-6150@862f17d `isSubtreeVisibilityHiddenOrOpacityZero`, used at :1522 to clear the repaint
  rects. WebKit schedules no repaint for the subtree, but the background-position animation is not accelerated and
  still resolves style per frame (INFERRED), so the gain there is style work, not paint.

## Results (MEASURED, CI only, no phone pass)
Gate: breakpoint gate run 40287895072 (fw=platform:faded-pause) PASS on both engines, at 5a82a54.

Chromium swipe-touch-v1, 3 runs per arm, base run 40287924353, flag run 40287928566, both at 5a82a54. Reader: Lean
`Fw.Measure.OffscreenWindows` through packages/measure-chromium/src/offscreen-windows-cli.mjs; end frame 574, slack 0.
`less` prints base min to flag max, `more` prints base max to flag min.

| window | Lean verdict | counts that differ |
|---|---|---|
| approach | noGain | none |
| end 0-19 | noGain | less: Paint 335 to 308, PaintImage 495 to 451; more: RecalcStyleCount 43 to 44, LayoutCount 21 to 22 |
| end 20-59 | gain | less: Paint 252 to 197, PaintImage 454 to 294 |
| end 60-119 | gain | less: Paint 120 to 0, PaintImage 240 to 0 |
| end 120+ | gain | less: Paint 94 to 0, PaintImage 188 to 0 |
| finish | noGain | less: Paint 915 to 619, PaintImage 1514 to 882; more: RecalcStyleCount 320 to 321, LayoutCount 52 to 53 |

Why finish is noGain: the verdict rule reads any counter that rises as a cost, and the flag reads exactly one more
RecalcStyle and one more Layout in every run (base max 320, flag min 321). INFERRED mechanism: the resume edge writes
`data-fw-scene` and flushes style with `getAnimations` once; those are the two extra counts, and the same +1 shows in end
0-19 (43 to 44, 21 to 22), the window where the edge falls. Paint and PaintImage fall in the finish window, so the flag
saves work; the verdict is strict about the two counters. Not isolated by a run.

WebKit: not run. The WebKit Simulator lane only scrolls (packages/measure-webkit/src/scrollrun.mjs:35 and :69 issue
`scrollTo` steps; cli.mjs:96 calls scrollRun), so the open morph is never reached there ("WebKit has no push-phase
windows", research/notes/2026/10-2x-platform-attribution.md:53). The fade never gets to 0, so the flag is a no-op on that
lane. Runs 40288001111 and 40288005328 were queued and cancelled for this reason. Follow-up: count it on a toolbar or push
lane that opens the morph.

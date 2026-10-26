# platform:faded-pause (task platform-faded-pause)

Rank 3 of research/notes/2026/10-26-end-of-page-variants.md. Status: built, CI pending (this note is filled in as runs finish).

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

## Results
Pending.

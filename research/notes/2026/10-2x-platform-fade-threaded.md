---
id: 2026-10-2x-platform-fade-threaded
kind: note
title: "platform:fade-threaded, one opacity and blur effect per morph push"
status: draft
created: 2026-10-22
authors: [agent:lean-prover]
topics: [platform, morph, end-of-page, webkit, compositor, flags]
---

# platform:fade-threaded (task platform-fade-threaded)

Question: during a morph push the tween writes `--morph-fade` on the platform section every frame, and the section's
CSS turns it into `opacity` and `filter: blur(...)` (platform.module.css:6, 12-13). Can one Web Animation per push on
`opacity` and `filter` show the same fade on every frame, so that the frames need no style or paint work for it?

## What changes
- `apps/site/src/parts/platform/fade.logic.ts`: the keyframes of one push, from Lean `PlatformFade.keyframes`
  (golden `platform-fade.jsonl`, 65 lines, checked by `fade.test.ts`).
- `fade.driver.ts`: `createThreadedFade`. A push cancels the live effect and starts
  `animate(keyframes, { duration: 680, easing: cubic-bezier(1/3, 1, 2/3, 1), fill: 'both' })` with `startTime` set to
  the push time. A settle (tween end or reduced-motion jump) writes `--morph-fade` once and cancels the effect.
- `morph.tween/driver.ts`: with `TweenEnv.fade` set the per-frame `--morph-fade` write is skipped and the sink is fed
  at push, settle and dispose. `index.tsx` and `App.tsx` turn the sink on under `?fw=platform:fade-threaded`.
- Conflicts: `morph.tween:waapi` and `morph.tween:waapi-scoped` (part.json), since both move the tween clock.

## What is proved (Lean, `lean/Fw/Parts/PlatformFade.lean`, `PlatformFadeRun.lean`)
- `keyframes f t`: two keyframes, or three when the push crosses the fade end, with the middle one at the eased
  progress `kink f t` where the morph value meets `fadeEnd`. `interp_eq`: linear interpolation of these keyframes at
  eased progress `p` in [0, 1] equals `fade (f + (t - f) p)`. `interp_blur`: the same for the blur keyframes.
- `frame_eq`, `frame_blur_eq`: under `WaapiPremises` (linear number interpolation, an exact timing curve, frames read
  the timeline at their rAF time plus one offset), the effect's value at frame time `R` is the original's fade and
  blur at `R`.
- `threaded_eq`: over any event list (pushes, frames, reduced-motion changes) the shown fade of the threaded run equals
  `fade` of the original run's value (invariant `InvF`, `invF_run`, `runB_fst`). `retarget_from_shown`: a push during a
  live effect starts the new effect at the fade on screen.
- `props_accelerated`: the animated properties are `opacity` and `filter`. `ca_accepts`: every effect of the variant
  meets the Core Animation conditions of GraphicsLayerCA (rate 1, forward, nonzero duration, at least two keyframes,
  no steps, curve inside [0, 1]); `filter` animation support is on.
- `webkit_not_exact`: on WebKit the claim is not grade E, since CA's blur is not the software blur.

## Premises
- CONFIRMED: GraphicsLayerCA accepts an accelerated animation under the conditions above
  (Source/WebCore/platform/graphics/ca/GraphicsLayerCA.cpp:1169-1196@862f17d) and supports `filter` animations
  (:289@862f17d); `opacity` and `filter` are accelerated without the threaded-animations setting
  (`animation-wrapper-acceleration: always`, Source/WebCore/css/CSSProperties.json:7114, 10263@862f17d).
- CONFIRMED: the section reads `--morph-fade` only in `opacity` and `filter` (platform.module.css:6, 12-13).
- INFERRED: the effect runs on the compositor in WebKit; a frame that only advances it needs no main-thread style or
  layout for the section.
- CONFIRMED: Chromium refuses to composite a `filter` effect with a pixel-moving filter such as blur
  (third_party/blink/renderer/core/animation/compositor_animations.cc:408-416@f842f52), so the effect runs on the main
  thread there.
- MEASURED (10-21-lag-windows.md): `--morph-fade` repaints 83% of the close-push paint area.

## Accepted limits
- The full-section blur layer is tiled above 1280 px.
- Pixels on WebKit at best grade Q (not E or E1), not measured: CA's blur differs from the software blur
  (`webkit_not_exact`).
- The iOS Simulator has no real GPU; its counts show main-thread work, not compositor cost.
- Frame percentiles only where the lane records them.

## Result: no fewer style or layout passes (negative finding)
- MEASURED, CI webkit-sim (iOS Simulator 430x775, lag and cost passes), base run 39731023406 against
  `?fw=platform:fade-threaded` run 39731104953, two passes per arm. Morph pass at the page end (y 5231, 130 frames, a
  push down and a push up): RecalculateStyles 259/259 against 261/261, Layout 169/174 against 178/174, Paint records
  740/1159 against 1162/1186. End-of-page scroll window (y >= 4500, 16-17 steps): RecalculateStyles 92/99 against
  100/76, Layout 91/101 against 112/64, inside the pass-to-pass gap.
- MEASURED, same runs, cost-report: Composite time per frame of the open push 168-269 ms against 134-167 ms (lower,
  3-4 frames per pass); the close push and the rest after it overlap. Frame percentiles are not available in this lane
  (no RenderingFrame events).
- PROVED in the write model (`recalc_same`, `writesT_sub` in `PlatformFadeRun.lean`): the variant drops only the
  section write, and the nav's `--morph` write still schedules a recalculation on every fade frame (driver.ts:129,
  index.tsx:48-52).
- CONFIRMED a second cause: the running effect invalidates the section on every tick. `KeyframeEffect::animationDidTick`
  calls `invalidate()`, which calls `invalidateElement` (Source/WebCore/animation/KeyframeEffect.cpp:2128-2130,
  1731-1734@862f17d), so moving the nav write alone would not remove the recalculation either.
- Gate: breakpoint-gate with `platform:fade-threaded`, engines both, run 39730956361 pass.
- Lesson: moving one property to the compositor saves no style pass while another write on the same frame still
  invalidates style; count every element's writes per frame first. What a threaded fade can save is paint and raster
  of the blurred section, which a Simulator count lane cannot show.
- Next: hold; no port task. Re-open only with the nav's `--morph` off the main thread and the effect on the
  threaded-animations path (no per-tick invalidate), measured on a real-GPU lane.

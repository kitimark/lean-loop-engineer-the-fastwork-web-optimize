---
id: 2026-10-22-hero-exit-threaded
kind: note
title: "hero.exit:threaded: which exit properties WebKit runs in the UI process on a scroll timeline, and how the variant hands over"
status: draft
created: 2026-10-22
topics: [hero.exit, webkit, scroll-driven, threaded-animations, ios-toolbar, lag]
---

# hero.exit:threaded

## Answer

- **All four exit properties are accelerated on a scroll timeline in WebKit: opacity, transform, translate, and
  filter (blur).** CONFIRMED from source at 862f17d (table below). Blur is not left on the main path on WebKit, unlike
  Chromium (Lean `blur_main`).
- **The variant** (`apps/site/src/parts/hero.exit/threaded.*`): one view timeline on the track, `contain` range, and
  per consumer a linear two-keyframe animation (`fill: both`). Endpoints are the Lean `keyframes` rows; the animated
  value equals the original's `calc()` value at every sampled offset (golden `hero-exit.threaded.jsonl`, `anim` rows,
  Lean `consumer_eq_s` under RG11).
- **Hand-over, not replacement.** The original's callback keeps running until `data-splash` is `done` in a browser that
  knows `animation-timeline` and without reduced motion (Lean `live`, one theorem per branch). Before that the entrance
  animations own `opacity`, `translate` and `--entered`, which a scroll animation on the same properties would hide.
- **`pointer-events`** is flipped by an IntersectionObserver on a 1 px sentinel at 19/20 of the exit range (Lean
  `sentinelTop`, `sentinel_iff_pointerOff`); it is not a per-frame write.

## Which properties run in the UI process (CONFIRMED, WebKit@862f17d)

| step | source |
| --- | --- |
| Scroll-driven threading is on by default | `Source/WTF/Scripts/Preferences/UnifiedWebPreferences.yaml:8518-8530` (`ThreadedScrollDrivenAnimationsEnabled`, WebKit and WebCore default true) |
| opacity, filter, transform, translate, scale are accelerated properties | `Source/WebCore/css/CSSProperties.json:7114` (opacity), `:10263` (filter), `:12112` (transform), `:12260` (translate), `:12281` (scale), each `"animation-wrapper-acceleration": "always"` |
| A property list is "accelerated" when each entry is | `Source/WebCore/animation/KeyframeEffect.cpp:1739-1760` (`computeAcceleratedPropertiesState`); `isCompletelyAccelerated` is `AcceleratedProperties::All` (`KeyframeEffect.h:180`) |
| The effect may be accelerated | `KeyframeEffect.cpp:1970-2010` (`canBeAccelerated`: fails on a reference filter, an accelerated property overridden by the cascade, a discrete transform interval, an unresolved offset) and `:3253-3262` (`canHaveAcceleratedRepresentation`) |
| The timeline is accelerated when its scroller has a scrolling node | `Source/WebCore/animation/ScrollTimeline.cpp:417-427` (`canBeAccelerated`); view timelines are `ScrollTimeline` subclasses (`ViewTimeline.h:72`) and send range data through `computeProgressResolutionData` (`ScrollTimeline.cpp:439-460`) |
| The UI process evaluates blur | `Source/WebCore/platform/animation/AcceleratedEffect.cpp:142` (property map), `:410-412` (`filter.blend`), `:511` |
| The UI process updates the timelines on every scroll callback | `Source/WebKit/UIProcess/RemoteLayerTree/ios/RemoteScrollingTreeIOS.cpp:55-66` (`updateProgressBasedTimelinesForNode` at `:61`) |
| The 100 ms throttle is bypassed only for a page animation that is not completely accelerated | `Source/WebCore/animation/AnimationTimelinesController.cpp:267-279` (`hasProgressBasedScrollDrivenAnimation`) |

Consequence for the design: every animation of the variant lists only accelerated properties, so none sets the
bypass flag. The page then keeps Safari's 10 Hz toolbar-collapse updates for the main thread, and the exit no longer
depends on them. A custom property in a keyframe would break this (not accelerated), so no keyframe animates one.

## Fallback and accepted limits

- Safari before 26.4: the animations run on the main thread (given by the task; INFERRED from the same source that
  they then set the bypass flag and get per-frame updates). A browser without `animation-timeline` keeps the original's
  callback for good (`CSS.supports('animation-timeline', 'view()')` is read once).
- Reduced motion keeps the callback, which writes the rest frame, as in the original.
- `hero.countdown:hidden-pause` reads the stage's inline `--exit-opacity`; the hand-over clears it, so that variant
  would not hide the countdown. The two variants are not combined by any preset (follow-up).
- The felt effect on the phone is not measured here (follow-up: phone replay).
- Open as in the Lean header: RG11 (which numbers a `contain` range gives under dynamic toolbars), the opacity-1
  crossing, resident layers.

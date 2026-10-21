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
- **Hand-over, not replacement.** The original's callback keeps running until `data-splash` is `done`, the entrance
  animations have finished (the phone cue's `copyIn` still runs at `done`; input `entranceFinished`, read from the
  stage's `getAnimations()` and re-read on `animationend`), in a browser that knows `animation-timeline` and without
  reduced motion (Lean `live`, one theorem per branch, golden `live` rows with `entranceFinished`). Before that the entrance
  animations own `opacity`, `translate` and `--entered`, which a scroll animation on the same properties would hide.
- **The entrance is the original's.** The live rules name only the exit animations. A reset in the original goes done, prep
  (`animation: none`), forced layout, run, so the engines cancel the animations at that forced layout and create them again at
  run; the variant keeps that, because its exit animations are cancelled at the same forced layout (the splash is not `done`
  there) and the hand-back runs before the next style pass. At <=600 the reset runs prep, run, done in one task and the
  observer sees only `done`: the hand-back reads the mutation records (`attributeOldValue`), and a batch that saw the
  splash leave `done` drops the latch (Lean `liveNext`, `liveNext_left`), so the cue's `copyIn` plays again as in the original.
  Lean `entrance_same` (INFERRED for the engine side, PROVED for the name lists): per node, band and path (load, restore),
  the variant's animation names minus the exit names equal the original's at every style pass, with the same restarts.
- **`pointer-events`** is flipped by an IntersectionObserver on a zero-height sentinel at 19/20 of the exit range (Lean
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

- `ENABLE(THREADED_ANIMATIONS)` is 1 only on Cocoa (`PlatformEnableCocoa.h:904-905`) and 0 elsewhere
  (`PlatformEnable.h:566-567`), so the Linux WebKit probe runs these animations on the main thread.

- Safari before 26.4: the animations run on the main thread (given by the task; INFERRED from the same source that
  they then set the bypass flag and get per-frame updates). A browser without `animation-timeline` keeps the original's
  callback for good (`CSS.supports('animation-timeline', 'view()')` is read once).
- Reduced motion keeps the callback, which writes the rest frame, as in the original.
- `hero.countdown:hidden-pause` reads the stage's inline `--exit-opacity`; the hand-over clears it, so that variant
  would not hide the countdown. The two variants are not combined by any preset (follow-up).
- The felt effect on the phone is not measured here (follow-up: phone replay).
- Open as in the Lean header: RG11 (which numbers a `contain` range gives under dynamic toolbars), the opacity-1
  crossing, resident layers.

## Trajectory probe (MEASURED, CI)

Run 39652612704 (push of cfeae169, `fw=hero.exit:threaded engines=both`, verdict run, all four widths; inputs read back
from the step name and the `trajectory-inputs` artifact). Verdict RED on both engines, and every red unit is a card that
is not rendered in that width band:

| engine | new units | which |
| --- | --- | --- |
| Chromium 156 | 25 content, 42 coverage | content: `hero.orbit.card` opacity and translate at 390, `hero.deck.card` opacity at 640 and 641; coverage: one `open@1` sample at 641 morph (sampling noise, nav only) |
| WebKit 27.2 (Linux) | 40 content, 0 coverage | the same cards (and `hero.deck.card` opacity at 1280) |

Verified in the raw legs (390 and 640): each red unit is a node whose rect is empty in all three arms (original, base,
candidate), i.e. `display: none`; the original arm changes only the computed value of the inherited variable on the unrendered box.
Every visible node of the hero path (stage, copy, cue, the visible orbit or deck cards) passes at all widths on both
engines. The first run (a8afffef) failed the same way plus the stage `count` rows: the sentinel was a `div`, which the
anchor `[data-fw="hero-exit"] > div` also matched; it is a `span` now.

Why the hidden cards differ (INFERRED from the CSS animations spec and the pattern of the rows): an element with
`display: none` runs no animation, so its computed `opacity` and `translate` stay at the rule value with the cleared
`--exit-opacity` (rest), while the original's JS keeps writing the variable they inherit. The probe reads these nodes
(`getComputedStyle` of a hidden node), and no user sees them. Making them agree needs a per-frame write, which is what
the variant removes. Open for the lead: the gate should not compare nodes that are not rendered in the band (a Lean rule
`hidden node = not a consumer`), or the variant is judged on visible nodes only.

## Proof status and the exit check

- The Lean statements this variant rests on, `consumer_eq_s` under RG11 and `proof-hero-exit`/`hero-exit-restate`,
  landed in 3dbed91c. This task adds `live_*`, `keyframe_table_*` and the golden rows (section Threaded).
- The exit check for the phone is not the stall count: a CSS animation does not write `--exit-opacity`, so the stall
  series of `Fw.Device.Session` cannot see it. The check is that `scrollY` still runs inside the exit range (still runs
  of 5 to 6 frames are the toolbar throttle) together with a `getComputedStyle` sample of one consumer (the copy's
  `opacity`) per frame. No lane records that pair yet; it is dispatch for the lead.

Round 2: run 39660528157 (push of 8eacef89, `fw=hero.exit:threaded engines=both`, verdict run). RED on both engines, only on nodes whose rect is empty in
all three arms (`hero.orbit.card` at 390, `hero.deck.card` at 640 and 641, counted in the raw legs); Chromium also reports the nav `open@1` coverage sample at 640.
The candidate arm still waits about 20.3 s (scroll-driven animations count as pending: 15 left at 390, 27 at 640 and wider), so the entrance window is not sampled.

Round 3: run 39669915362 (push of 1cd1d7bf, `fw=hero.exit:threaded engines=both`, verdict run, all four widths, merged head).
Chromium 25 and WebKit 40 content units are new, all on `hero.orbit.card` at 390 and `hero.deck.card` at 640, 641 and 1280; the rect of those nodes is
empty in every sample of every arm (counted in the raw legs: orbit cards 0 of 1260 non-empty at 390, deck cards 0 of 504 non-empty at 640 and wider, 504 of 504 at
390 for the deck on the other side), so they are the accepted empty-rect class. Every visible node passes at the golden offsets on both engines (Chromium 14349
units ok, 0 coverage failures; WebKit 3960 ok). 42 Chromium units fail only in the faithful arm. The candidate arm waits `waitedMs` 20.34 s at every width on both
engines (390, 640, 641, 1280: 20337-20347 Chromium, 20335-20347 WebKit); the original 1.33 s at 390 and 2.60 s at 640 and wider (Chromium), the base 4.40 s. The entrance and
the restore are not sampled; they rest on Lean `entrance_same` and the unit tests.

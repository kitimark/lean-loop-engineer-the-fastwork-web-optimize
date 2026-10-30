---
id: note-threaded-subpixel-why
kind: note
title: "Why WebKit reads a sub-pixel card translate under hero.exit:threaded at scroll 0"
status: done
created: 2026-10-31
topics: [hero.exit, threaded, webkit, scroll-driven-animations, float32, gate-breakpoints]
---

# Why WebKit reads a sub-pixel card translate under hero.exit:threaded at scroll 0

## Answer

- It is a numeric artifact, not a real offset. WebKit computes the view timeline's current time in `float`
  and the `contain` range start in `double`. At scroll 0 both are the same 1/3 of the timeline. In float that 1/3
  lands about 2.5e-6 % past the double start, so the card animation is already active, at progress
  p ≈ 1/(100·2^17) ≈ 7.63e-8. The card translate is p × scatter: up to 2.2e-5 px at width 601 and 5.5e-5 px at
  width 1512. The exact value is 0 px, the `from` keyframe. (CONFIRMED, WebKit 862f17d `ScrollTimeline.cpp:383-397`,
  `ViewTimeline.cpp:503-517`; MEASURED, run 41087718575.)
- No rendered pixel moves. A transform does not touch layout, so LayoutUnit (1/64 px) never sees it. The
  residue the bound covers (scatter within ±48vw on a side up to 2560 px) lies strictly between -1e-4 and 1e-4 CSS px
  (Lean `residue_lt_gateTol`), so its size is below 3e-4 device px at dpr 3. On a card that is already rotated and
  resampled, that shifts edge coverage by less than 0.1 of one 8-bit level in either direction (Lean
  `residue_level_change_lt`). A 1-level flip needs a pixel that already sits within that margin of a rounding
  boundary. (INFERRED.)
- Chromium reads 0 px, because Blink snaps a local time that lies within 1 µs of the phase boundary onto it, so
  progress is exactly 0. (CONFIRMED for the snap, Chromium f842f52 `timing_calculations.cc:95-101`; INFERRED that it
  is the step taken here.)

## Where the numbers come from (WebKit 862f17dcae0aace47ea0ec16e209d960abfd553c)

The flag (`apps/site/src/parts/hero.exit/threaded.module.css`):
- `:14` declares `view-timeline: --hero-exit block` on the 200vh track (`hero.module.css:6`).
- The orbit card runs `exitCardMove` with `fill-mode: both` and `range: contain` at `:73,79,81`; the deck card does
  the same at `:84,90,92`.
- In the keyframes (`:144` on), the `from` translate is `calc((1 - var(--entered)) * var(--orbit-enter-x))`, which
  is 0 px at `--entered: 1`. The `to` translate adds the scatter (`hero.orbit/index.tsx:36-37` vw/vh;
  `hero.deck/deck.module.css:31-60`).
- The faithful page multiplies the scatter by `--exit-scatter`, which is 0 at scroll 0
  (`hero.orbit/card.module.css:33-34`, `hero.exit/hero.module.css:11-12`). So the faithful page reads exactly 0 px.
  (CONFIRMED.)

The timeline's current time is computed in float (all CONFIRMED):
- `ScrollTimeline.h:102-105`: `Data { float scrollOffset, rangeStart, rangeEnd }`. `ViewTimeline.h:114-120` stores
  float fields too.
- `ViewTimeline.cpp:503-517`: `rangeStart = subjectOffset - scrollContainerSize`,
  `range = subjectSize + scrollContainerSize`. At scroll 0 with viewport V and track 2V, that is -V and 3V.
- `ScrollTimeline.cpp:383-397`: `distance / range` and then `* 100`, both in float. 1/3 rounds to 11184811·2^-25, and
  ×100 rounds to 8738134·2^-18 = 33.33333587646484 %.
- The compositor path does the same float math (`RemoteProgressBasedTimeline.cpp:69,73,74`,
  `ProgressResolutionData.h:36-44`).

The range start is computed in double (all CONFIRMED):
- `ViewTimeline.cpp:535` and `:563`: the `contain` start is `rangeStart + subjectSize`, the end is
  `rangeEnd - subjectSize`, and they are swapped when end < start.
- `ViewTimeline.cpp:584-592` (`mapOffsetToTimelineRange`) and `:626-646` (`intervalForAttachmentRange`) do
  offset / range × 100 in double: start 33.333333333333336 %, end 66.66666666666667 %.
- `WebAnimation.cpp:1531-1545` takes `interval.first` as the start time. `AnimationEffect.cpp:458-460` takes
  duration `auto` = `interval.second - interval.first`.

Phase and progress (all CONFIRMED):
- `WebAnimation.cpp:518`: current time = timeline time − start time ≈ +2.54e-6 %.
- `WebAnimation.cpp:520-528` with `ViewTimeline.cpp:433-441`: for a view timeline WebKit snaps a current time in [-ε, 0) % up to 0 % (ε = 0.1 pt / subjectSize × 100), but leaves a positive one as is, so the float excess is not snapped. (CONFIRMED)
- `AnimationEffectTiming.cpp:182-190`: the before-phase test. For percentages, `WebAnimationTime.cpp:165-171`
  compares exactly (`m_value < other.m_value`). The 0.000001 epsilon at `:150-155` only serves `matchingEpsilon`.
  A positive local time is therefore active, not before, and `fill-mode` does not apply.
- `AnimationEffectTiming.cpp:229` and `:279`: progress = active time / iteration duration ≈ 7.63e-8.

Blending and printing (all CONFIRMED):
- `StylePrimitiveNumericTypes+Blending.h:56-76` (Length), `:103-117` (LengthPercentage) and `:135-162` (calc
  mixed types) blend each axis. `StyleTranslate.cpp:83-114` and `StyleTranslateTransformFunction.cpp:99-125` blend
  per axis.
- `AnimationUtilities.h:111-122` computes `float(from + (to - from) * progress)`. From 0 px, that is
  `to × p` rounded to float.
- `Source/WTF/wtf/dtoa.cpp:130-147` (`numberToCSSString`) prints with `ToFixedUncapped(d, 6)`, trims trailing zeros
  and drops "-0". The residue therefore prints as `-0.000022px`. The opacity residue (0.35 × p ≈ 2.7e-8) prints as
  `1`, which is why only translate shows up.

## Chromium, briefly (f842f52ef39fd97b449eb27cff414bf05a98ddce)

- `scroll_timeline.cc:166-172` keeps offsets in double and times in µs (`scroll_timeline.h:51`). (CONFIRMED)
- `timing_calculations.cc:27-29` sets a 1 µs `TimeTolerance`. `:35-42` and `:95-101` snap a local time within that
  tolerance onto the before/active boundary, so progress is exactly 0. (CONFIRMED)
- Blink's view-timeline range math was not read, so the snap as the cause of 0 px is INFERRED.

## Measurement (run 41087718575, artifact `gate-merged-playwright-webkit`)

- MEASURED: all 704 differing card readings in probes[] (620 orbit, 84 deck) are at scrollY 0; the 634 more in sweeps[] are too and fit the same way.
- MEASURED: all 1408 components fit residue = scatterPx × p0, with p0 = 1/13107200 = 7.62939453125e-8, inside the
  6-decimal print interval. The signs match the scatter. p0 equals
  the Lean `ideal_progress` value 1/(100·2^17).
- MEASURED: card rects differ by at most 1.22e-4 px, in 631 of 1736 card rects.
- MEASURED: the orbit shows the residue only above 600 px and the deck only at ≤ 600 px. This matches their
  `display: none` rules (`hero.orbit/orbit.module.css:56-58`, `hero.deck/deck.module.css:9,12-16`); an animation
  does not run on a `display: none` element. (INFERRED)
- MEASURED: the same residue shows in the rewrite arm on properties the gate did not fail: the hero copy
  `transform` `matrix(1, 0, 0, 1, -160, -0.000001)` (83 readings), the hero copy `filter` `blur(0.000001px)` (62),
  and the hero.cue `filter` (83) and `transform` (21). Those roles declare `transform` and `filter` but not
  `translate`. Why the gate passes them was not read (follow-up).

## Lean (`lean/Fw/Parts/HeroExitSubpixel.lean`, imported in `lean/Fw.lean`)

- The scatter bounds come from `HeroOrbit.scatterX/scatterY` and `HeroDeck.slots`.
- The track height comes from `HeroExit.trackHeightPx` (`trackPx_eq`).
- `roundBits` models IEEE round-to-nearest; `ieee_steps` checks the binade and the no-tie case for each of the seven
  roundings.

| theorem | states |
|---|---|
| `ratio_third` | the scroll-0 timeline ratio is 1/3 for every viewport height |
| `after_start` | float current time > double range start: the effect is active |
| `ideal_progress` | the float excess over 100/3, relative, is exactly 1/(100·2^17) |
| `progress_near_ideal` | the double progress is within 1e-6 relative of that |
| `orbit_scatter_le`, `deck_scatter_le` | every card scatter is within ±48 vw/vh |
| `timeline32_ratio`, `start64_ratio` | the float time and the double start both round `ratio v`, for every viewport height |
| `residue_le_max` | the residue lies between its values at scatter -48 and +48 on a 2560 px side |
| `residue_lt_gateTol` | -1e-4 px < residue < 1e-4 px for scatter in [-48, 48] and viewport side ≤ 2560 px |
| `residue_level_change_lt` | at dpr ≤ 3: -0.1 < 3 × 255 × residue < 0.1 of an 8-bit level |

## Limits

- This is source reading plus the existing CI artifact; no new CI run.
- Playwright WebKit stands in for iOS Safari. The compositor path uses the same float formula, so the phone should
  show the same residue. (INFERRED)
- The pixel answer is INFERRED from the transform/layout split and the bound in `residue_level_change_lt`. No pixel
  diff was taken.

## What this changes in the plan

- **hero.exit:threaded gate failure (r603 threaded-subpixel-why):** classify the WebKit card `translate` difference
  at scroll 0 as a float32/double timeline artifact with no pixel effect. The flag is not wrong. A fix belongs in
  the gate comparison, for example an absolute tolerance on length components backed by `residue_lt_gateTol`, as a
  separate gate task decided by the lead. This task changes no flag, preset or gate. Card rects differ by up to
  2^-13 px, likely the float ulp of rect coordinates in [1024, 2048) (INFERRED), so a rect tolerance must not reuse
  `residue_lt_gateTol`.
- Follow-up (gate): find why the gate passes the same 1e-6 residue on the hero copy and cue `transform` and
  `filter` but fails it on the card `translate`, so the two paths share one rule.

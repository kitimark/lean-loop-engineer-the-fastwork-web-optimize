# Earn button transitions during the morph (task earn-transition-retarget)

Region B candidate from `10-20-webkit-lag-source.md` (earn button paragraph). Flag: `nav:earn-no-transition` (the task
named it `nav.earn:no-transition`; the earn button is part of the `nav` part, so it is a nav variant). Lean:
`lean/Fw/Parts/NavEarnOpt.lean`. Golden: `packages/contracts/golden/parts/nav-earn.jsonl` (383 lines, checked by
`apps/site/src/parts/nav/earn.golden.test.ts` and by the `nav-earn golden check` job of `lean/scripts/check.sh`).

## What changes

The earn button's `max-width`, `padding-inline` and `opacity` are functions of `--morph`
(`apps/site/src/parts/nav/nav.module.css:167-185`, restated from the original rule
`.start-selling-top-nav-btn.is-earn` in `snapshot/site/_app/immutable/assets/2.gBuqKVzi.css`). The same rule lists
`transition: max-width .68s, opacity .32s .12s, padding-inline .68s`, all `cubic-bezier(.33,0,.2,1)`. With the flag, the
nav carries `is-earn-still` while it carries `is-morphing` (`logic.ts:88-95`, `index.tsx:84,103`), and
`.nav.is-earn-still .btn.earn { transition: none }` (`nav.module.css:201-203`). The class is written in the same frame as
`data-fw-morph` (MutationObserver, `index.tsx`), so the style change that sees the new `--morph` also sees the new
transition list.

## Engine source

| Claim | Status | Source |
|---|---|---|
| WebKit: a computed-value change of a listed property while a transition runs cancels it and starts a new one from the current value, with the full duration and delay | CONFIRMED | WebKit@862f17d `Source/WebCore/style/Styleable.cpp:743-756` (in `updateCSSTransitionsForStyleableAndProperty`, :570) |
| WebKit: a change of a property that the new style does not list in `transition-property` starts no transition and cancels a running one | CONFIRMED | `Styleable.cpp:648-654`, `:683-690` |
| WebKit: `max-width` and `padding` changes need layout; an `opacity` change across 1 needs layout | CONFIRMED | `Source/WebCore/rendering/style/StyleDifference.cpp:406`, `:426`, `:208` |
| WebKit: an element whose effect stack animates `opacity` composites | CONFIRMED (code path); that this holds during the 0.12 s delay is INFERRED | `RenderLayerCompositor.cpp:3841-3853` |
| Chromium: a running transition whose end value differs from the after-change value is cancelled and a new one starts from the before-change style, which includes the current animated value | CONFIRMED | Chromium@f842f52 `third_party/blink/renderer/core/animation/css/css_animations.cc:2703-2715`, `:2727-2732`, `:3191` |
| Chromium: active transitions on properties that are no longer listed are cancelled | CONFIRMED | `css_animations.cc:3175-3182` |
| Chromium: the reversing-shortening rule does not apply, because each frame's end value is new, not the old start value | INFERRED | `css_animations.cc:2861-2876` |

So in both engines a value that `--morph` changes every frame restarts a 680 ms transition every frame. The curve starts
flat and each restart begins at its start, so the shown value creeps while the computed value moves, and the opacity
transition, whose 120 ms delay also restarts, does not move at all until the computed value stops changing.

## Lean model and theorems

A property with transition `tr` (delay, duration, curve), a computed value `g k` per frame `k`, and a switch `on k`
(the property is listed). `run` is the per-frame transition state: unlisted, it rests at `g k`; listed and unchanged, it
keeps its state; listed and changed, it starts a new transition from the value shown at that time to `g k`. The model
covers one property; the three earn properties are independent instances.

- `transitionsOn flag morphing = !(flag && morphing)`; one theorem per branch: `transitionsOn_faithful`,
  `transitionsOn_flag_rest`, `transitionsOn_flag_morphing`.
- `shown_off`: unlisted, the shown value is the computed value.
- `faithful_lags`: from rest, at the frame where the computed value changes, the faithful arm shows the old value.
- `shown_settled`: after the computed value has been constant for at least delay + duration, every arm shows it.
- `visSame_settled`: `VisSame E` between any two arms over settled frames, for any scene drawn from the shown value.
- `work_le`: over any frame range, the frames on which an arm changes the property's style (the computed value changed,
  or a transition runs) are at most the faithful arm's (`dirty_le`, `running_le`).
- `trace_eq`: the linear-time trace the golden uses equals the per-frame `run`.

Axioms of `visSame_settled`, `work_le`, `faithful_lags`, `shown_off`, `trace_eq`: `propext`, `Classical.choice`,
`Quot.sound`.

## Counts from the golden (60 Hz frames, 91 frames, `Fw.Parts.MorphTween` time tween)

Frames on which the property's style changes (`work`), same at desktop 1440 and phone 390:

| push | property | faithful | arm | last frame faithful / arm |
|---|---|---|---|---|
| open (m 0 to 1) | max-width | 43 | 3 | 43 / 3 |
| open | padding-inline | 43 | 3 | 43 / 3 |
| open | opacity | 29 | 3 | 29 / 3 |
| close (m 1 to 0) | max-width | 65 | 65 | 81 / 81 |
| close | padding-inline | 65 | 65 | 81 / 81 |
| close | opacity | 51 | 51 | 67 / 67 |

Open push: the computed values reach their end at frame 3 (`--earn-out` saturates at m = 0.2). The faithful arm keeps
restyling and laying out the button to frame 43 (717 ms). Close push: no saving. The computed values change only while
m < 0.2. The tween is below the morphing cut (m ≤ 0.001) from frame 37, so transitions are back on and the last small
steps (under 1.5 px of max-width on desktop) start 680 ms transitions in both arms. MEASURED in the model; the engine
counts are the CI section below.

The close push shows the lag most clearly. At frame 37 (617 ms, m = 0.0008) the computed max-width is 175.3 px on
desktop; the faithful arm shows 4.6 px and opacity 0 (computed 0.996), the arm 174.6 px and 0.99. The faithful arm
reaches its end at frame 81 (1.35 s), 0.67 s after the tween.

## Mid-transition: a look change

At open frame 10 (167 ms, m = 0.57) the computed max-width is 0. The arm shows 0; the faithful arm shows 152 px at
opacity 1 (golden rows; `#guard` in `NavEarnOpt.lean`). The arm is therefore not `VisSame` mid-transition. It is an
L-class change (look change, a user decision), proved equal only on settled frames.

Why the 0.68 s lag is not the design intent (INFERRED from the original's CSS and JS):

1. The CSS states collapse the button by m = 0.2 (`--earn-out: clamp(0, m / .2, 1)`). With the transition, it collapses
   over about 0.7 s instead.
2. The original turns off the same 0.68 s curve on the nav's own width (`.start-selling-top-nav:not(.is-morphing)`
   holds the width transition) and on the actions gap (`.start-selling-top-nav.is-morphing .start-selling-top-nav-actions
   {transition:none}`), but not on the earn button. The lag is the one `--morph`-driven element that kept its transition.
3. The JS removes the button from the tab order at m > 0.4 and hides it from assistive technology at m > 0.55
   (`logic.ts:18-20`, N2:12903, 13244). The faithful arm still shows it at about 150 px and full opacity then.
4. The transitions serve the hero-pill ↔ pill flip of `--nav-expand`; that flip happens outside the morph and is not
   changed by the flag.
5. The bar (z-index 3) sits above the morph panel (z-index 1), so the lingering button is visible in the faithful arm.

## Limits

- Settled frames only for `VisSame`; mid-transition the flag is a look change (above).
- Close push: transitions return at m ≤ 0.001, so the last steps (under 1.5 px) run as transitions and the close push
  keeps the faithful work count. Follow-up: hold
  `is-earn-still` until the tween's end.
- The model takes frame times at 60 Hz and the tween's own time; it does not model rAF jitter or a slower WebKit frame.
- The work count is per property style change; the engine work saved is layout of the nav subtree (WebKit and
  Chromium) and, in WebKit, the opacity transition's compositing (INFERRED). WebKit region B paint and composite
  counters are a follow-up (accepted limit).

## CI (trajectory probe)

PENDING.

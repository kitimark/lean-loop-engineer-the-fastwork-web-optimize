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

- `settled3_same`, `visSame_settled3`: on `Settled3 v a b`, the frames that end a `Settled` window of all three
  properties at once, each property shows the same value in any two arms, and any scene drawn from the three values is
  `VisSame E`. `settled3B` checks a window; `#guard` witnesses per push (open, close) and viewport (desktop 1440, phone
  390): frames 41 to 82. The morph stops at frame 41, and 41 frames (683 ms) cover the longest delay plus duration
  (680 ms); 40 frames do not.
- `valueChanges`: how often each arm's shown value changes per push (`#guard`, below).

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

Shown-value changes (`valueChanges`, faithful / arm): open max-width 43 / 3, open opacity 20 / 3, close max-width
65 / 65, close opacity 20 / 40. On the close push the opacity changes more often in the arm. The faithful arm restarts
the 120 ms opacity delay every frame, so its opacity stays at 0 until the morph stops and then runs one 440 ms
transition. The arm has no transition while the nav morphs, so its opacity follows the morph frame by frame.

The close push shows the lag most clearly. At frame 37 (617 ms, m = 0.0008) the computed max-width is 175.3 px on
desktop; the faithful arm shows 4.6 px and opacity 0 (computed 0.996), the arm 174.6 px and 0.99. The faithful arm
reaches its end at frame 81 (1.35 s), 0.67 s after the tween.

## Mid-transition: a look change

At open frame 10 (167 ms, m = 0.57) the computed max-width is 0. The arm shows 0; the faithful arm shows 152 px at
opacity 1 (golden rows; `#guard` in `NavEarnOpt.lean`). The arm is therefore not `VisSame` mid-transition. It is an
L-class change (look change), proved equal only on settled frames. The user accepted the look change on 2026-10-21; the
user's visual review of the strips below is pending.

## Look-change class

`apps/site/src/parts/nav/part.json` registers the variant as `"kind": "proposal", "visClass": "L"`. Per PLAN §6.2 a
class L change cannot be `optimized`, and look changes are `proposal`s. `visClass` is a new optional field that takes the
PLAN §4.7 class names `E`, `E-s`, `Q`, `L`. The tier `T0` was removed: it is a pixel-difference tier, and the variant
differs mid-transition.

- `Fw.Preset.Gen.parsePart` reads `visClass` from an allowlist and refuses an `optimized` variant of class `L`.
- `Fw.Preset.ok` refuses a look change, so `look_not_mem`: no class `L` flag is in `v2-proved`, whatever the ledger
  and the stored runs say. `lookCandidates_not_mem` restates this for the candidate list.
- `Fw.Preset.Gen.lookDecisions` records each user decision. For `nav:earn-no-transition` it is 2026-10-21, "accepted,
  pending user visual review". The generator writes `packages/contracts/golden/preset/look-change.candidates.jsonl`
  (one line per class `L` variant, with kind, membership and decision), checked by the `preset v2-proved check` job
  and by `apps/site/src/parts/nav/look-change.test.ts`. A decision row that names no class `L` variant stops the
  generator.

## Visual review material (CI)

Run 39473950464 (`trajectory-probe.yml` job `frames`, ci/earn-transition-retarget at c6c7cbcf, ubuntu-24.04-arm) made
one PNG strip for each engine, width (390, 1280) and push. The strips are renders of the page, so they stay out of git.
They exist only in the run's artifacts `frames-chromium` and `frames-playwright-webkit`, kept until 2026-11-19, at
path `strips/<engine>-<width>-<push>.png`, and in the lead's private review page. `results/earn-look-review/index.json`
names each strip by artifact and path, with run, expiry, engine version, crop, shot counts, the arm identity check
(all `ok`) and `usable`.

Each strip puts the no-flag row above the flag row, cropped to the actions and earn region, at most 40 columns. Both
arms get the same wheel input (kit approach, wheel push open dy 120, 900 ms hold, wheel push close dy -120); each arm
is sampled at its own real-time shot times, without animation seeking. The ms under a column is the midpoint of that
screenshot call, counted from the wheel call in Node, so columns pair the arms by shot index, not by time.

`usable` is decided per strip: usable = min(shots.faithful, shots.flag) >= 10.

| engine | 390 open | 390 close | 1280 open | 1280 close |
|---|---|---|---|---|
| Chromium 156 | 35/36 usable | 34/35 usable | 17/18 usable | 17/19 usable |
| Linux playwright-webkit (WebKit 27.2) | 1/4 | 10/10 usable | 1/7 | 2/7 |

(shots faithful/flag)

- Chromium 156: about one shot every 33 to 70 ms. On the close push at 1280, "Join waitlist" is fully shown in the flag
  row from about 600 ms and in the no-flag row from about 1070 ms. On the open push at 390, the flag row's button is
  gone by about 285 ms; the no-flag row still shows it at 244 ms and has lost it by 323 ms.
- Linux playwright-webkit: three of four strips are not usable. On both open pushes the no-flag arm got one shot,
  because the first screenshot after the wheel stalled (at 1280 its label is 3052 ms, past the 1500 ms push). This
  engine is not Safari, and the trajectory lane already decides the morph on WebKit only on macOS. WebKit review
  strips are task earn-look-review-webkit (macOS Playwright WebKit, 390 and 1280, open and close, at least 10 shots
  per arm and push). The user's visual review stays pending until that task delivers them.
- MEASURED, review material only: the strips decide nothing and make no claim of visual equality mid-morph.

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

MEASURED. Branch `ci/earn-transition-retarget` at c414428, `--engines both`, widths 390/640/641/1280, 3 reps per
run. The search field in each raw file names the arm.

| run | arm |
|---|---|
| 39463486725 | flag rep 1 (`?fw=nav:earn-no-transition`) |
| 39464309993 | flag rep 2 |
| 39464294630 | A/A rep 1 (default) |
| 39464322751 | A/A rep 2 |

New content units (`fail:apart`, fails here and not in the faithful arm), summed over widths:

| engine | run | earn opacity | earn max-width | other nodes |
|---|---|---|---|---|
| Chromium | flag 1 / flag 2 | 47 / 46 | 45 / 48 | 1 / 1 |
| Chromium | A/A 1 / A/A 2 | 1 / 0 | 2 / 0 | 1 / 1 |
| WebKit | flag 1 / flag 2 | 6 / 8 | 11 / 10 | 1 / 4 |
| WebKit | A/A 1 / A/A 2 | 0 / 2 | 0 / 4 | 2 / 5 |

- The flag adds new units only on earn opacity and max-width, in the open and close pushes. That is the L-class look
  change above, so "no new visual units" does not hold for those two properties. Every other node stays at the A/A
  level: one 641 approach `nav.background-color` unit in all four Chromium runs, plus WebKit noise.
- Coverage-new units (Chromium 0 to 42, WebKit 84 to 126) appear in the A/A runs too. On Linux WebKit the push phases
  get 3 to 9 samples, so push coverage fails by construction.

Earn value changes per push (Chromium, frames whose reading differs from the previous one, 3 reps; flag 2 shown, flag 1
within 2):

| width | push | opacity faithful / arm | max-width faithful / arm | last change faithful / arm |
|---|---|---|---|---|
| 390 | open | 18 / 1-4 | 41 / 1-4 | 353 ms / 43-59 ms |
| 640 | open | 11-12 / 4 | 29-30 / 4 | 330-347 ms / 66 ms |
| 641 | open | 11-12 / 1-2 | 29-30 / 1-2 | 335-354 ms / 43-81 ms |
| 1280 | open | 6-8 / 3 | 17-21 / 3 | 333-357 ms / 50-62 ms |
| 390 | close | 12 / 25-26 | 38-40 / 40-41 | 386 ms / 386 ms |
| 1280 | close | 9-10 / 13 | 23-25 / 21-24 | 370-374 ms / 362-377 ms |

A/A value-change noise (MEASURED; Chromium, runs 39464294630 and 39464322751 downloaded and read, no new measurement). Same
metric as the table above (frames whose reading differs from the previous one, 3 reps), counted on the `base` and `cand`
arms of an A/A run, which are the same code. For each width, push and property the cautious delta of each direction is taken
as in the panel (gain: lowest base minus highest cand; loss: highest base minus lowest cand); the noise is the largest
magnitude over the 16 rows of both runs:

| property | A/A base ranges (examples) | A/A cand ranges (examples) | largest cautious delta, either sign | noise used |
|---|---|---|---|---|
| opacity | 390 open 17-18, 1280 close 8-9 | 390 open 18-19, 1280 close 8-10 | 2 (641 open run 2 loss -2; 390 open run 1 gain -2) | 2 |
| max-width | 1280 close 23-23 / 24-27 | 1280 close 19-23 / 23-24 | 4 (1280 close, both runs, loss -4) | 4 |

- Open push: the arm settles within 43-81 ms, the faithful arm keeps changing to 330-357 ms
  (1280 rep 0: the arm reaches max-width 0 at frame 8, the faithful arm at frame 24). This matches the model's 3 vs 43
  frames.
- Close push: no reduction, as the model predicts. The arm changes opacity more often because the faithful opacity is
  held at 0 by the restarting 120 ms delay (`faithful_lags`); the faithful arm still restyles every frame.
- WebKit (playwright-webkit on Linux) samples 3 to 9 frames per push, too few for change counts; the arm's open push
  settles at 25-28 ms on 390 and 1280. WebKit paint and composite counts stay a follow-up (accepted limit).
- Read timing: gap p50 17-19 ms in Chromium, reads do not dominate.

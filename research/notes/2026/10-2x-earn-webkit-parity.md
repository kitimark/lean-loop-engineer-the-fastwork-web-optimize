# Why the earn and language buttons animate worse on WebKit (task earn-webkit-parity)

## Answer

- **CONFIRMED (source) and MEASURED (3 CI jobs):** WebKit never starts a transition on the earn button's side padding.
  The rule says `transition: ... padding-inline .68s`. `padding-inline` is a shorthand of two logical longhands. WebKit
  puts those two logical longhands in the transition list as they are. The logical longhands have no animation wrapper,
  so WebKit finds "nothing changed" and runs no transition. The computed physical `padding-left/right` then jump from
  24 px (16 px at 640 px and below) to 0 in the first frame. Chromium turns each logical longhand into its physical
  one first and eases the padding over about 570 to 600 ms.
- **What you see on WebKit:** at the flip to the hero the pill loses 48 px of width (32 px on a narrow phone) in one
  frame while its label is still 95 % visible, and the language button jumps 48 px (32 px) at once. That is the
  "snap". The opacity fade is not slower on WebKit (about 143 to 153 ms to zero, against 167 to 200 ms in
  Chromium), so the felt lag is the snap, not the fade.
- **Fix, for the next task `earn-webkit-smooth`:** list the two logical longhands instead of the shorthand,
  `padding-inline-start, padding-inline-end`, at the same duration, curve and delay. Chromium is unchanged
  (same transition key set, Lean `fixLogical_chromium_unchanged`); WebKit then equals Chromium
  (`fixLogical_webkit_eq_chromium`). Measured in one CI job so far: see the limits.
- **iPhone:** INFERRED only. iPhone Safari runs the same WebCore source; no iPhone was measured.

## Cause, with source

| Step | Source |
|---|---|
| WebKit expands a shorthand in `transition-property` to its longhands without mapping logical to physical | `Source/WebCore/style/Styleable.cpp:553-566@862f17d` (`compileTransitionPropertiesInStyle`: `resolveDirectionAwareProperty`, then `shorthandForProperty` longhands set as they are) |
| The logical longhands have a `nullptr` wrapper, "logical, handled via resolution to physical" | `Source/WebCore/css/scripts/process-css-properties.py:~5956@862f17d` |
| A property with no wrapper compares equal, so no transition starts | `Source/WebCore/style/StyleInterpolation.cpp:281-289@862f17d` (`equals` answers true) |
| Chromium maps each shorthand longhand with `ToPhysical(writing_direction)` | `third_party/blink/renderer/core/animation/css/css_animations.cc:2993-3007@f842f52` |

The same start and retarget logic sits in WebKit `Styleable.cpp:~584-760` and Chromium
`CalculateTransitionUpdateForPropertyHandle` (`css_animations.cc:2662-2925`); the earlier note
`research/notes/2026/10-20-earn-transition-retarget.md` covers the retarget side.

Site rule: `apps/site/src/parts/nav/nav.module.css:167-203` and `:286` (restated from the original earn button rule in
`snapshot/site`). `.btn.earn` has `padding-inline: calc(var(--earn-layout) * 24px)` (16 px at 640 px and below),
`max-width: calc(var(--earn-layout) * 11rem)` (9.5rem at 640 px and below) and
`transition: max-width .68s, opacity .32s .12s, padding-inline .68s` with `cubic-bezier(.33,0,.2,1)`.
`.is-hero-pill .btn.earn` has opacity `.2s` without a delay. The language button only moves through the earn width and
the `.actions` gap (`transition: gap .68s`), so it inherits the snap.

Lean (`lean/Fw/Engine/TransitionStart.lean`, golden `packages/contracts/golden/engine/transition-start.jsonl`, 588 rows):

| Statement | Theorem |
|---|---|
| WebKit never transitions a `padding-inline` list entry | `wk_paddingInline_never` |
| Chromium transitions it, left to right and right to left | `cr_paddingInline_ltr`, `cr_paddingInline_rtl` |
| The two engines agree on every property except `padding-inline` | `engines_agree_without_paddingInline` |
| Hero entry: Chromium starts max-width, opacity, padding-right, padding-left; WebKit only max-width, opacity | `hero_entry_chromium`, `hero_entry_webkit` |
| First frame after the flip, hero entry: padding is 0 on WebKit and 24 px (16 px narrow) on Chromium; the snap in width is twice the padding | `firstFrame_wide`, `firstFrame_narrow`, `padding_snap_width` |
| The three fixes | `fixLogical_*`, `fixPhysical_*`, `fixPadding_webkit_eq_chromium`, `fixPadding_chromium_differs` |

## Measured, frame by frame (hero entry, 1280 px, faithful rewrite)

Setup: one free macOS 26 runner job per run, Chromium, Playwright WebKit and Safari 26.6.2 (safaridriver) in the same
job, native `requestAnimationFrame`, no animation seeking. Values from the per-frame tables in
`results/earn-webkit-parity/<run>/1280/summary/`. `dt` is the time from the flip frame. Column "anims" is the list the
engine reports for the earn button.

Playwright WebKit (17 ms frames):

| dt ms | padding-left | max-width | opacity | earn width | anims |
|---|---|---|---|---|---|
| -23 | 24 | 176 | 1 | 137.59 | none |
| 0 | 0 | 175.3 | 0.95 | 89.59 | max-width, opacity |
| 76 | 0 | 159.9 | 0.21 | 89.59 | max-width, opacity |
| 163 | 0 | 109.8 | 0 | 89.59 | max-width, opacity |
| 205 | 0 | 83.4 | 0 | 83.41 | max-width |
| 327 | 0 | 34.0 | 0 | 33.94 | max-width |

Chromium (33 ms frames, headless without a GPU on the runner):

| dt ms | padding-left | max-width | opacity | earn width | anims |
|---|---|---|---|---|---|
| 0 | 24 | 176 | 1 | 137.59 | max-width, opacity, padding-left, padding-right |
| 83 | 22.5 | 165.3 | 0.32 | 134.66 | same |
| 150 | 18.2 | 133.7 | 0.04 | 126.03 | same |
| 250 | 9.8 | 71.6 | 0 | 71.59 | max-width, padding-left, padding-right |
| 383 | 3.5 | 25.8 | 0 | 25.80 | same |
| 600 | 0.19 | 1.4 | 0 | 1.38 | same |

Safari 26.6.2 matches Playwright WebKit (padding 24 to 0 in one frame, earn width -48 px in the flip frame, opacity gone
at about 146 ms, 17 ms frames). Hero exit is the mirror image: WebKit has no padding transition in its list.

Median [min..max] over the three CI jobs (Safari: the two valid jobs), from `results/earn-webkit-parity/across-runs.txt`:

| Width | Engine | padding-left max one-frame jump (px) | frames between | earn width jump (px) | language x jump (px) | opacity gone (ms) | frame (ms) |
|---|---|---|---|---|---|---|---|
| 1280 | Playwright WebKit | 24 [24..24] | 0 | 48 | 48.03 | 143 [135..160] | 17 |
| 1280 | Safari | 24 [24..24] | 0 | 48 | 48.1 | 146 [139..153] | 17 |
| 1280 | Chromium | 5.77 [4.38..5.88] | 15 [8..18] | 28.2 (low frame rate inflates) | 30.2 | 183 [167..200] | 33 |
| 390 | Playwright WebKit | 16 | 0 | 32 | 32.04 | 156 | - |
| 390 | Chromium | - | about 10 | - | - | 200 | 66 |

Notes on reading the table:

- The Chromium jumps are per recorded frame. At 30 fps (33 ms frames) a smooth ease still moves 6 px of padding per
  frame; on a phone at 60 fps it moves about half. The WebKit jump is 24 px in one frame at any frame rate.
- After the padding snap WebKit's earn width stays at the content width (89.59 px) until `max-width` falls under it,
  about 200 ms later, so the button looks frozen and then shrinks.

## Fix candidates, ranked

Swap the `padding-inline` entry in the `transition` of both `.btn.earn` and `.is-hero-pill .btn.earn`. Each candidate
was injected as a `transition-property` override on the faithful rewrite and recorded in the third CI job only
(2 repeats). Padding-left one-frame jump, hero entry, 1280 px:

| Rank | Candidate | WebKit | Safari | Chromium | Lean |
|---|---|---|---|---|---|
| 1 | `padding-inline-start, padding-inline-end` (logical, keeps right-to-left meaning) | 5.49 px, eased over 540 ms | 3.8 px, 537 ms | 3.52 px, 600 ms | `fixLogical_webkit_eq_chromium`, `fixLogical_chromium_unchanged` |
| 2 | `padding-left, padding-right` (physical) | 6.25 px, 534 ms | not run | 5.65 px, 584 ms | `fixPhysical_*` |
| 3 | `padding` (shorthand) | 2.52 px, 529 ms | not run | 5.17 px, 600 ms | `fixPadding_webkit_eq_chromium`, `fixPadding_chromium_differs` |
| 4 | Others, for example a registered `@property` for the padding, or moving the padding into `--morph`-driven custom properties | not measured | | | no proof yet |

Why this order: candidate 1 changes nothing in Chromium and keeps the logical semantics of the original. Candidate 2
gives the same Chromium key set but hard-codes left and right. Candidate 3 adds top and bottom keys to the Chromium
transition set (Lean proves the set differs), which can start extra transitions on other state changes, so it is last
of the three. WebKit's `anims` list showed `padding-left` and `padding-right` in every candidate arm.
Candidates are faithful "same as Chromium" on WebKit; the visual end states are identical to the original.

## Limits

- Candidate arms: **one** CI job (2 repeats). The "at least 3 jobs" bar is met only for the unfixed comparison
  (3 jobs) and for Safari (2 valid jobs). Treat the candidate numbers as a direction; `earn-webkit-smooth` repeats them.
- The first Safari job had macOS Reduce Motion on (runner default; `defaults read com.apple.universalaccess
  reduceMotion` printed 1), so the site switched its motion off and no transition ran. Its summary was dropped. The
  step now writes `reduceMotion -bool false` before starting `safaridriver`; the two later jobs are valid.
- Safari ran at 1280 px only: a Safari window narrower than 640 px is not possible on macOS. 390 px is Playwright WebKit
  and Chromium only.
- Chromium on the free runner renders 20 to 30 fps without a GPU, so its frame table is coarse. WebKit renders 60 fps.
  Only the shape (eased against snapped) and the transition lists are compared across engines, not the frame rate.
- Playwright WebKit stands in for Safari on 390 px; Safari itself agrees with it at 1280 px.
- Reading computed styles each frame forces style recalculation; the `light` page (no per-frame reads) bounds that
  effect on the nav class timeline.
- The morph (scroll between hero and card) sequences were not recorded in CI: the 15 min cap on macOS jobs
  (Lean `Fw.Ci.Pool.Caps`) allows hero sequences only (`--morph 0`).
- Felt smoothness on a device belongs to the user.

## Reproduce

`packages/gate-breakpoints/src/trajectory/transitions.mjs` (capture, summary), `transitions-safari.mjs` (safaridriver),
`transitions-combine.mjs` (across runs); CI: workflow `trajectory-probe`, commit message flag `[transitions:earn]`
(`docs/team/tools/trajectory-frames.md`). Runs: 40082730706, 40083514606, 40084115382.

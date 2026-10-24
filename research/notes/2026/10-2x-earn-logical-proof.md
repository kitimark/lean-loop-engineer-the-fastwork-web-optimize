# Earn button padding curve: proof of `nav:earn-logical`

## Answer

- **Proved in Lean** (`lean/Fw/Parts/NavEarnCurve.lean`): with the variant, WebKit's side padding at every time t after the flip
  equals Chromium's faithful padding at t (`curve_identity`), for both sides, both directions and both widths. The padding moves
  monotonically from its start value to its end value (`variant_monotone`, `variant_between`) and is exactly at the end value from
  680 ms on (`settle_680`). Chromium is unchanged by the variant (`chromium_unchanged`). The faithful rule on WebKit holds the end value
  from the flip on (`faithful_webkit_snaps`), which is the look the variant changes.
- **MEASURED** (macOS CI runs 40100783726 and 40102193302, no new dispatch): all 120 full traces stay within the Lean tolerance of
  their own arm's Lean padding. Every variant trace, on Chromium, Playwright WebKit and Safari 1280, stays within the tolerance of the
  shared curve. The faithful WebKit and Safari traces miss the curve by the full 16 or 24 px, which is the negative control.
- **INFERRED**: the iPhone, from the shared WebKit source. Playwright WebKit on macOS and Safari at 1280 px stand in for Safari.
  Paint and compositing of the eased padding are outside the proof.
- User verdict: accepted 2026-10-25 (source: chat), recorded in `Fw.Preset.Gen.lookDecisions`; ledger row `nav.earn.logicalPadding`
  is `proved` with a `userDecision`.
- **Preset:** the flag does not join v2-proved. part.json marks it `proposal` with visual class L, and `V2Proved.look_not_mem` /
  `Gen.lookCandidates_not_mem` keep every class-L flag out. The regenerated preset is still `[engine.scroll:unthrottle]`.

## The shared interpolation model (CONFIRMED)

Both engines compute the padding of a running transition as `from + (to - from) * y(s)`. Here `s` is the cubic-bezier parameter
with `x(s) = (t - delay) / dur`, for the curve `cubic-bezier(.33, 0, .2, 1)`, and the value is clamped to `to` once
`t >= delay + dur`.

| Step | WebKit@862f17d | Chromium@f842f52 | Spec |
|---|---|---|---|
| Start, from and to values, duration and delay of the transition | `Source/WebCore/animation/CSSTransition.cpp:72-88` | `third_party/blink/renderer/core/animation/css/css_animations.cc:2847, 2889-2905` | CSS Transitions 1, starting of transitions |
| Local time to progress `(t - delay) / dur`, held at 1 after the end | `Source/WebCore/animation/AnimationEffectTiming.cpp:230, 279, 408-414` | `third_party/blink/renderer/core/animation/timing_calculations.cc:152, 192, 361` | Web Animations 1, calculating progress |
| Easing: solve `x(s) = progress`, return `y(s)` | `Source/WebCore/platform/animation/TimingFunction.cpp:100-110`, `Source/WebCore/platform/graphics/UnitBezier.h:44-51, 94-168` | `third_party/blink/renderer/platform/animation/timing_function.cc:132-135`, `ui/gfx/geometry/cubic_bezier.cc:18, 22, 44-56, 181-240` | CSS Easing 1, cubic Bézier easing functions |
| Blend `from + (to - from) * p` for a length | `Source/WebCore/animation/KeyframeEffect.cpp:1849-1860`, `Source/WebCore/style/values/primitives/StylePrimitiveNumericTypes+Blending.h:74, 115`, `Source/WebCore/platform/animation/AnimationUtilities.h:98-107` | `third_party/blink/renderer/core/animation/interpolation_effect.cc:35-41`, `third_party/blink/renderer/core/animation/interpolable_length.cc:644-657`, `third_party/blink/renderer/platform/geometry/blend.h:30-31` | CSS Values 4, combining values |

The engines differ only in how precisely they solve for `s`. WebKit stops at `1 / (1000 * dur in s)`, which is 1 ms of time
(`TimingFunction.cpp:100-110`). Chromium stops at `1e-7` (`cubic_bezier.cc:22`). The tolerance below carries this difference as
the per-engine solver error `E`: 1000 µs for WebKit and 1 µs for Chromium.

## Lean model

- Exact integer arithmetic. The curve parameter runs over a grid of `M = 2^16` steps, and `x(k)` and `y(k)` are integer Bernstein
  forms scaled by `D = 100 * M^3`. `solve` bisects for the largest `k` with `x(k) * dur <= (t - delay) * D`, and the padding is
  `from * D + (to - from) * y(solve)`.
- `padAt` takes the transition each engine starts (`Fw.Engine.TransitionStart.starts`) and its timing (`NavEarnWebkit.timing`). When
  no transition starts, the padding is the end value at once: the snap.
- `curve_identity` follows from `variant_webkit_timing_eq_chromium_faithful` (same started set, duration and delay) plus the shared
  model above, so the two curves are the same function, not two close ones.
- Error bounds:
  - The grid gap: one `y` step is at most `150 * M^2`, `yBar_step`.
  - The chord slope: `100 * dy <= 261 * dx`, `chord_bound`.
  - Together they give `num_slack`: shifting the time by `w` µs moves the padding by at most
    `ceil(delta * 261 * w * 10^6 / (100 * dur)) + ceil(delta * 783 * 10^6 / (100 * M))` µpx.

## Measurement (`packages/gate-breakpoints/src/trajectory/earn-curve.mjs`)

- Each trace's own clock: the start `S` is the median of `t - currentTime` over the rows where the earn padding transition runs. The
  jitter `J` is the largest deviation from `S` plus 0.5 ms for the rounded `currentTime`. Chromium's first frames report
  `currentTime = 0` and are left out of `S`.
- The tolerance per trace is `tolMicro = slack(delta, J + E, dur) + grid gap + 50 µpx` (computed style is read to 6 significant
  digits). It comes from the recorded jitter and the Lean bounds, not from tuning. The golden `tol` rows pin the formula, and the
  site test and the reducer test replay them.
- The light mode (40 traces) records geometry only, with no computed-style read and no hero-flip flag, so it has nothing to check.
  The reducer lists these traces as skipped.

| Browser | Arm | Width | Traces | Own model | Shared curve | Worst vs curve | Largest tolerance |
|---|---|---|---|---|---|---|---|
| Chromium | faithful | 390, 1280 | 24 | 24/24 | 24/24 | 0.013 px | 0.096 px |
| Chromium | variant | 390, 1280 | 24 | 24/24 | 24/24 | 0.017 px | 0.100 px |
| Playwright WebKit | variant | 390, 1280 | 24 | 24/24 | 24/24 | 0.0005 px | 0.142 px |
| Safari | variant | 1280 | 12 | 12/12 | 12/12 | 0.0005 px | 0.142 px |
| Playwright WebKit | faithful | 390, 1280 | 24 | 24/24 (snap) | 0/24 | 16 / 24 px | 0.142 px |
| Safari | faithful | 1280 | 12 | 12/12 (snap) | 0/12 | 24 px | 0.142 px |

Per-trace verdicts and the worst frame of each trace: `results/earn-logical-proof/traces.json`. The groups are in
`results/earn-logical-proof/summary.json`.

## Checks

- Golden `packages/contracts/golden/parts/nav.earn.curve.jsonl` from `lean/scripts/NavEarnCurveGolden.lean`, with a `--check` job in
  `lean/scripts/check.sh`.
- The site test `apps/site/src/parts/nav/earn.curve.test.ts` checks three things against the golden:
  - the variant CSS rules declare the golden runs;
  - a BigInt replay reproduces every sample exactly;
  - the tolerance rows follow the formula.
- The reducer test `packages/gate-breakpoints/test/earn-curve.test.mjs` checks that:
  - the port reproduces every sample and tolerance row exactly;
  - a jittered synthetic trace passes;
  - a trace with one frame pushed off the curve fails at that frame;
  - a snapping trace fails the curve.

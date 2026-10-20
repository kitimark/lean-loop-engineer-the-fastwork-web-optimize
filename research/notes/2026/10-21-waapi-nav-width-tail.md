# waapi-nav-width-tail: the waapi driver keeps the nav width tail with a base window

The original's nav width tail after a close comes back in `morph.tween:waapi`. The driver writes the base `--morph`
inline in a window: from 100 ms before the `activeCut` marker until the animation ends. This is decision (a). It costs
9 script frames per close at 60 Hz, and the arm still skips script on 24 of the original's 41 close frames.
Lean: `Fw.Parts.MorphTweenOpt`, section `WidthTail`. The CI run of the new driver is not done yet; the lead
dispatches it.

## Mechanism (CONFIRMED, source)

| Step | Where |
|---|---|
| `is-morphing` is on iff `--morph > 0.001` | snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js:12947 |
| The class and the inline `--morph` are written in one template effect | 2.DyWL8TcE.js:13221-13243 |
| `.start-selling-top-nav:not(.is-morphing)` has `width .68s cubic-bezier(.33,0,.2,1)`; the width is a calc of `var(--morph)` | snapshot/site-pretty/_app/immutable/assets/2.gBuqKVzi.css:11320-11361 |
| Port: the same rules | apps/site/src/parts/nav/nav.module.css:41-48 |
| Chromium: the before-change style is the previous base style, without script animations | third_party/blink/renderer/core/animation/css/css_animations.cc:3214-3215, 3242-3293 @f842f52 |
| WebKit: the same; the after-change style is the new base style | Source/WebCore/style/StyleTreeResolver.cpp:894-898, Styleable.cpp:604-632 @862f17d |

On a close from 1, the value crosses 0.001 at 612 ms (`closeAt_cross`, `morphing_iff`). On the flip frame R, a width
transition starts. It runs from the base width of the frame before, P, to the width at R (`tailPx_eq`). The original
writes `--morph` inline every frame, so the jump is `(panelW - pillW) * (m(P) - m(R))` (`tail_orig_pos`). The size
depends on the frame grid (`tail_not_view`). It is 0.49 px at 1280 px at 60 Hz, 11.4 px at a 173 ms gap and 89.5 px at
411 ms (#guards). The landed waapi driver never wrote the base, so the transition started from the stale base 0.

## Fix: the base window (`baseB`, `baseDelay`, `baseW`)

- **When:** a push from `f` to `t` with `t < f` that has an `activeCut` marker (`baseWindow`).
- **At the push:** the driver writes base `--morph = t`. This is a reset, so a later miss starts from `t`.
- **In the window:** from `max(0, markerDelay(f, t, 0.001) - 100)` ms until the end, every frame writes base
  `--morph` = the frame's value. The `is-morphing` class is still on in these frames, so no width transition starts and
  the animated value hides the base.
- **At the end:** the finish writes base `--morph = t`. A retarget or a reduced-motion jump closes the window.
- **Hit:** P falls in the window whenever R - P ≤ 100 ms, because R ≥ 612 (`base_hits`). Then the base at P and at R
  is the frame's value, which equals the original's value (`tail_eq_of_base`). So the jump is the original's jump.
- **Miss** (P earlier than the window): the jump is from base 0 to `m(R) ≤ 0.001`. It is at most
  `(panelW - pillW) / 1000` = 0.256 px at 1280 px and is reversed (`tail_miss_le`).
- **Open:** the driver writes no base, so the base does not change and there is no jump
  (`tail_zero_of_base_still`; driver test "a close writes the base --morph ...; an open writes none").

## Cost decision (Lean `cost`, `tailArm`, `tailDecision`)

The cost model counts script frames on a close from 1 pushed at 0, with frames every g ms until the first frame at or
after 680 ms. `orig` counts the original's frames (every frame runs script). `fix` counts the landed driver's frames:
the finish, plus the marker polls at the driver's delays `dlTs`, 1 ms early, which is sound (`dlTs_sound`). `tail` is
`fix` plus the window frames. The rule is `model` iff `tail - fix < orig - fix`, i.e. the extra frames stay below the
saving. The decision is taken at 60 Hz and 120 Hz; `tailDecision 100 = model` (#guard).

| Gap g (ms) | Source | orig | fix | tail | Arm |
|---|---|---|---|---|---|
| 16.7 | 60 Hz | 41 | 8 | 17 | model |
| 8.3 | 120 Hz | 82 | 8 | 27 | model |
| 22 | Chromium CI flip gaps 16-44 | 31 | 7 | 13 | model |
| 45 | macOS WebKit CI flip gaps 31-215 | 16 | 7 | 10 | model |
| 100 | macOS WebKit CI, slow reps | 7 | 4 | 5 | model |
| 300 | Linux WebKit CI flip gaps of 300 ms and more | 3 | 2 | 3 | lookChange |

At 300 ms the landed driver saves 1 frame of 3, and the window costs that frame back. No probe walks the morph on
Linux WebKit (`walks_linux_webkit`), so this row is not used for the decision. A window of 50 ms would cost 3 fewer
frames at 60 Hz, but at the macOS CI gaps of 50-100 ms it would miss.

## Tail rule for the CI data (MEASURED, scratch script; the per-rep values below)

- S = the rep's `close` samples, then its `close-hold` samples, in order.
- R = the first sample in S whose nav `is-morphing` is `off`. P = the sample before R in S.
- tail = the nav width at R minus the nav width at the last `close-hold` sample.
- pred = `(panelW - pillW) * m(P)`.
- Fallbacks: no R gives `noflip`; R as the first sample of S gives `P=None` (it did not occur). There is no fallback
  to a "first m == 0" or "first close-hold" sample.

Run 39471466367 is the landed driver, before this fix. Every rewrite arm's search was checked: cand
`?fw=morph.tween:waapi`, base `''`. Values are tail/pred@(R-P) per rep, in px and ms.

| Engine | Width | Arm | rep 1 | rep 2 | rep 3 | rep 4 | rep 5 |
|---|---|---|---|---|---|---|---|
| Chromium | 1280 | orig | 0.59/0.61@23 | 0.45/0.46@22 | 0.66/0.67@17 | 0.64/0.64@35 | 0.31/0.31@22 |
| Chromium | 1280 | base | 0.38/0.38@23 | 0.38/0.38@22 | 0.73/0.74@44 | 0.55/0.56@24 | 0.36/0.36@24 |
| Chromium | 1280 | cand | 0.20/0.41@22 | 0.20/0.41@20 | 0.08/0.20@26 | 0.08/0.20@16 | 0.20/0.41@21 |
| Chromium | 390 | orig, base, cand | 0.00/0.01, gaps 18-22 in all 15 reps | | | | |
| macOS WebKit | 1280 | orig | 3.03/3.02@98 | 0.27/0.26@61 | 0.27/0.26@45 | 0.77/0.77@31 | 0.53/0.54@47 |
| macOS WebKit | 1280 | base | 0.52/0.51@61 | 0.83/0.84@45 | 0.61/0.61@39 | noflip | 0.97/0.97@44 |
| macOS WebKit | 1280 | cand | 0.00/0.56@57 | 0.20/1.48@46 | 0.25/1.08@47 | 0.02/0.44@52 | 0.20/0.95@34 |
| macOS WebKit | 390 | orig | 0.05/0.05@65 | 0.05/0.05@91 | 0.06/0.07@154 | 0.02/0.02@37 | 0.02/0.02@62 |
| macOS WebKit | 390 | base | 0.09/0.11@111 | 0.06/0.07@75 | 0.02/0.02@49 | 0.06/0.07@66 | 0.00/0.01@39 |
| macOS WebKit | 390 | cand | 0.00/0.02@110 | 0.00/0.02@33 | 0.00/0.10@215 | 0.00/0.01@42 | 0.00/0.01@37 |

orig and base match pred within 0.02 px in every rep with a flip. That confirms the before-change rule. The landed
cand does not match: its tail is the value at R, not a jump from P. With the window, every rep above with
R - P ≤ 100 is a hit. The predicted cand tail then equals pred, as for orig. The macOS 390 rep at 215 ms may miss,
with a bound of 0.008 px.

## Not measured yet

- The new driver on CI needs a dispatch with workflow inputs. A push runs search `''`, so it does not run the waapi
  arm. The command is in the handoff.
- Linux WebKit: the probe plan walks only the hero there, so there is no morph cell to report.
- The background-colour transition (0.7 s) starts at the same flip by the same mechanism, and the window covers it
  too. Start-of-close units belong to trajectory-close-start.

# waapi-nav-width-tail: the base window keeps the nav width tail on Chromium, not on WebKit

The original's nav width tail after a close comes back in `morph.tween:waapi` on Chromium. The driver writes the base
`--morph` inline in a window: from 100 ms before the `activeCut` marker until the animation ends. This is decision (a).
CI run 39504209400 (the driver at 7ae872ab) shows the waapi arm's tail equal to the original's prediction on every
Chromium 1280 rep (5 hits, |cand - pred| ≤ 0.008 px). On macOS WebKit 1280 it does not: in all 4 hit reps the waapi arm
starts no width transition at the flip (|cand - pred| 0.65-1.67 px). The WebKit half is a finding (`model-false`), not
fixed in this branch. The window costs 9 script frames per close at 60 Hz on both engines.
Lean: `Fw.Parts.MorphTweenOpt`, section `WidthTail`.

## Premise

On Linux WebKit 1280, runs 39412301221, 39457063232 and 39457767229 showed 20-55 px tails. That was runner frame
jank, not an engine effect. Those runs used an older probe that walked the morph on Linux WebKit, and their flip gaps
were 417-562 ms. The frame before the flip had m = 0.12-0.21. Cand arms: 39412301221 `?fw=morph.tween:waapi`,
39457063232 `?fw=hero.exit:faithful`, 39457767229 `?fw=morph.tween:waapi-scoped` (the same base writes as waapi).
The probe now walks only the hero there (`walks_linux_webkit`). On display grids the original's tail is at most
0.5 px at 1280 px and 60 Hz (#guard 0.49 px). The mechanism premise holds: orig and base equal the prediction within
0.02 px on every rep of 39504209400.

## Mechanism (CONFIRMED, source)

| Step | Where |
|---|---|
| `is-morphing` is on iff `--morph > 0.001` | snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js:12947 |
| The class and the inline `--morph` are written in one template effect | 2.DyWL8TcE.js:13221-13243 |
| The original writes `--morph` on every rAF frame until the close ends | 2.DyWL8TcE.js:13019-13021 (loop), 13243 (effect) |
| `.start-selling-top-nav:not(.is-morphing)` has `width .68s cubic-bezier(.33,0,.2,1)`; the width is a calc of `var(--morph)` | snapshot/site-pretty/_app/immutable/assets/2.gBuqKVzi.css:11320-11361 |
| Port: the same rules | apps/site/src/parts/nav/nav.module.css:41-48 |
| Chromium: the before-change style is the previous base style, without script animations | third_party/blink/renderer/core/animation/css/css_animations.cc:3214-3215, 3242-3293 @f842f52 |
| WebKit: the same per source; the after-change style is the new base style | Source/WebCore/style/StyleTreeResolver.cpp:894-898, Styleable.cpp:604-632 @862f17d |
| A base change during a running transition cancels it and restarts from the current value with the full duration | WebKit Styleable.cpp:705-756 @862f17d (step 4); Chromium css_animations.cc:2703-2716, 2861-2882 @f842f52 |

On a close from 1, the value crosses 0.001 at 612 ms (`closeAt_cross`, `morphing_iff`). On the flip frame R, a width
transition starts. It runs from the base width of the frame before, P, to the width at R (`tailPx_eq`). The original
writes `--morph` inline every frame, so the jump is `(panelW - pillW) * (m(P) - m(R))` (`tail_orig_pos`). The size
depends on the frame grid (`tail_not_view`): 0.49 px at 1280 px and 60 Hz, 11.4 px at a 173 ms gap, 89.5 px at
411 ms (#guards).

## Fix: the base window (`baseB`, `baseDelay`, `baseW`)

- **When:** a push from `f` to `t` with `t < f` that has an `activeCut` marker (`baseWindow`).
- **At the push:** the driver writes base `--morph = t`, so a miss starts from `t`.
- **In the window:** from `baseDelay` = `max(0, markerDelay(f, t, 0.001) - 100)` ms until the end, every frame writes
  base `--morph` = the frame's value. `is-morphing` is still on before the flip, so no width transition starts there.
- **After the flip:** the writes go on until the end. Each one retargets the running width transition, as the
  original's per-frame writes do (engine rows above), so these frames stay.
- **At the end:** the finish writes base `--morph = t`. A retarget or a reduced-motion jump closes the window.
- **Open:** no base write, no jump (`tail_zero_of_base_still`; driver test "a close writes the base --morph ...; an
  open writes none").

## Hit and miss (identity rule)

- **Hit** iff P is in the window, i.e. P - push ≥ `baseDelay` (golden `baseWindow.delay`, 511-512 ms from 1). Checked
  on the data as m(P) ≤ closeAt(baseDelay) ≈ 0.01508 (`hit_iff_mP`, #guard). `base_hits` is a sufficient condition.
- **Hit chain:** `hit_iff_mP` or `base_hits` (P is in the window), then the driver test "a close writes the base
  --morph ..." (the base written is the frame's value), then `tail_eq_of_base` (that value is the original's).
- **Miss** (P before the window): the original's tail exceeds the waapi arm's by at least
  `(panelW - pillW) * (closeAt(baseDelay) - activeCut)`: 3.60 px at 1280 px, 0.11 px at 390 px (`miss_look_ge`,
  `missFloor` #guards). No upper bound: it grows with the gap.

## CI evidence: run 39504209400 (MEASURED)

Dispatched by the lead on `ci/waapi-nav-width-tail` at 7ae872ab. Every cand arm's search is `?fw=morph.tween:waapi`
(read from each leg's raw JSON). Tail rule, per rep:

- S = the rep's `close` samples, then its `close-hold` samples, in order.
- R = the first sample in S whose nav `is-morphing` is `off`. P = the sample before R in S.
- tail = the nav width at R minus the nav width at the last `close-hold` sample. pred = `(panelW - pillW) * m(P)`.
- No fallbacks: no R gives `noflip`, R first in S gives `P=None`. Neither occurred.

Values: tail/pred@(R-P) in px and ms; M marks a miss by the identity rule.

| Engine | Width | Arm | rep 1 | rep 2 | rep 3 | rep 4 | rep 5 |
|---|---|---|---|---|---|---|---|
| Chromium | 1280 | orig | 0.58/0.59@38 | 0.34/0.36@26 | 0.25/0.26@26 | 0.44/0.44@26 | 0.25/0.26@25 |
| Chromium | 1280 | base | 0.50/0.51@27 | 0.36/0.36@27 | 0.45/0.46@38 | 1.31/1.33@66 | 0.70/0.72@26 |
| Chromium | 1280 | cand | 0.41/0.41@25 | 0.73/0.74@28 | 0.41/0.41@38 | 0.73/0.74@40 | 0.41/0.41@28 |
| macOS WebKit | 1280 | orig | 2.91/2.92@125 | 0.27/0.26@43 | 0.33/0.33@37 | 0.27/0.28@43 | 0.73/0.74@32 |
| macOS WebKit | 1280 | base | 0.62/0.64@33 | 0.61/0.61@45 | 0.81/0.82@52 | 0.83/0.84@41 | 1.70/1.72@61 |
| macOS WebKit | 1280 | cand | 0.17/0.82@39 | 0.02/1.33@89 | 0.17/7.12@141 M | 0.06/0.74@49 | 0.12/1.79@59 |
| Chromium | 390 | orig, base, cand | 0.00/0.01, gaps 18-19, all 15 reps | | | | |
| macOS WebKit | 390 | orig | 0.00/0.01@75 | 0.03/0.04@102 | 0.03/0.04@82 | 0.03/0.04@66 | 0.02/0.03@52 |
| macOS WebKit | 390 | base | 0.02/0.03@34 | 0.03/0.03@72 | 0.00/0.02@99 | 0.00/0.01@76 | 0.00/0.01@58 |
| macOS WebKit | 390 | cand | 0.00/0.06@168 | 0.00/0.07@114 | 0.00/0.02@75 | 0.00/1.37@361 M | 0.00/0.04@89 |

Cand hit/miss counts and the 0.05 px check:

| Engine | Width | Hits | Misses | Hits with \|cand - pred\| ≤ 0.05 px |
|---|---|---|---|---|
| Chromium | 1280 | 5 | 0 | 5 (max 0.008) |
| macOS WebKit | 1280 | 4 | 1 | 0 (0.65-1.67) |
| Chromium | 390 | 5 | 0 | 5 (0.013) |
| macOS WebKit | 390 | 4 | 1 | 2 (0.020, 0.041; 0.062, 0.066 above) |

macOS WebKit 390 fails the no-regression bound on 2 of 4 hits (0.062, 0.066 px), from the same cause as the 1280 finding
(cand tail 0.00 px: no width transition starts). Both WebKit cells moved to task waapi-tail-webkit (split after round 3).
The hit threshold here was computed as (1 - 511.6/680)^3 = 0.01519, not from Lean closeAt(baseDelay) (0.01507-0.01509);
no rep falls between the two. waapi-tail-webkit computes it from the golden baseWindow.delay.

The rule "hit iff R - P ≤ 100 ms" is gone: macOS 390 cand rep 1 has a 168 ms gap and is a hit (m(P) = 0.0078).
The macOS 1280 miss (m(P) = 0.0278) differs by 6.95 px, above `missFloor` 3.60 px.

## Finding: WebKit starts no width transition in the waapi arm (MEASURED; cause INFERRED, open)

On macOS WebKit 1280, the cand width at R is W(m(R)) within 0.014 px in all 5 reps. On the next sample it is the pill
width (984.000) in 4 of 5 reps. So no width transition from W(m(P)) runs. Run 39471466367, before the window, showed
the same shape (cand tail ≈ 256·m(R)). The window changes nothing on WebKit, and the hit chain's last step fails
there. orig and base (inline writes, no script animation) match pred on the same engine, so the before-change rule
holds for them. INFERRED, not checked: on WebKit the class flip (MutationObserver on `data-fw-morph`,
apps/site/src/parts/nav/index.tsx:126) and the base write fall into different style change events. Then before-change
and after-change base values are equal at the flip. Locating the cause needs a debug run (follow-up); this branch
does not patch it.

## Cost decision (Lean `cost`, `tailArm`, `tailDecision`)

The cost model counts script frames on a close from 1 pushed at 0, with frames every g ms until the first frame at or
after 680 ms. `orig` counts the original's frames. `fix` counts the landed driver's frames: the finish, plus the marker
polls at the driver's delays `dlTs`, 1 ms early (`dlTs_sound`). `tail` is `fix` plus the window frames: at 60 Hz
17 = 8 fix + 10 window - 1 shared. The rule is `model` iff `tail - fix < orig - fix`. It is lexicographic: the look
difference of `lookChange` is positive on every grid (`tail_orig_pos`), so it outranks script frames while a saving
remains. `tailDecision 100 = model` (#guard). The rule assumes the window restores the look. On WebKit it does not
(finding above), so there the 9 frames buy nothing.

| Gap g (ms) | Source | orig | fix | tail | Arm |
|---|---|---|---|---|---|
| 16.7 | 60 Hz | 41 | 8 | 17 | model |
| 8.3 | 120 Hz | 82 | 8 | 27 | model |
| 22 | Chromium CI flip gaps | 31 | 7 | 13 | model |
| 45 | macOS WebKit CI flip gaps | 16 | 7 | 10 | model |
| 100 | macOS WebKit CI, slow reps | 7 | 4 | 5 | model |
| 300 | Linux WebKit flip gaps 417-562 ms (39412301221, 39457063232, 39457767229; older probe); not decisive | 3 | 2 | 3 | lookChange |

Decision (a) also gives back the original's post-close width-transition layout frames, about 41 at 60 Hz (680 ms /
16.7 ms, full-duration restart per Styleable.cpp step 4). INFERRED, to be counted on CI before the user's choice of
option (b) (follow-up `waapi-tail-drop`).

## Accepted limits

- Linux WebKit has no morph cell (`walks_linux_webkit`).
- 390 px cells are no-regression only (panel - pill = 8 px, pred ≤ 0.12 px), not discriminating.
- A miss gives a look difference ≥ 3.60 px at 1280 px, unbounded above; stated, not patched.
- The 100 ms window is a declared bound, not a measured maximum.
- The background-colour transition (0.7 s) starts at the same flip; start-of-close units belong to
  trajectory-close-start.

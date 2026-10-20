# waapi-nav-width-tail: the nav width tail after a close is a look change

`morph.tween:waapi` has no nav width tail after a close. The original has one. On Linux WebKit at 1280 px, at the
first settled close frame, the original's nav is 20-55 px wider than the final width (runs 39457063232, 39457767229,
39412301221). Decision (b): this is a look change. The driver is unchanged, with no new golden and no CI push. Lean:
`Fw.Parts.MorphTweenOpt`, section `WidthTail`.

## Mechanism (CONFIRMED, source)

| Step | Where |
|---|---|
| `is-morphing` is on iff `--morph > 0.001` | snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js:12947 |
| The class and the inline `--morph` are written in one template effect | 2.DyWL8TcE.js:13221-13243 (class 13226, style 13243) |
| `.start-selling-top-nav:not(.is-morphing)` has `width .68s cubic-bezier(.33,0,.2,1)`; the width is a calc of `var(--morph)` | snapshot/site-pretty/_app/immutable/assets/2.gBuqKVzi.css:11355-11361, 11320-11353 |
| Port: the same rules | apps/site/src/parts/nav/nav.module.css:41-48 |
| Chromium: the before-change style is the old base style plus running transitions only | third_party/blink/renderer/core/animation/css/css_animations.cc:3214-3215, 3242-3293 @f842f52 |
| WebKit: the before-change style is recorded before animations apply; the after-change style is the new base style | Source/WebCore/style/StyleTreeResolver.cpp:894-898, Styleable.cpp:604-617, 624-632 @862f17d |

On a close, the original crosses 0.001 at 612 ms (`closeAt_cross`, `morphing_iff`). On that frame the class flips,
and a 680 ms width transition starts from `W(m_prev)`, the base width of the frame before. The original writes
`--morph` inline every frame, so the transition really does start there (`tail_orig_pos`). The jump size is
`(panelW - pillW) * closeAt(prev)` (`tailPx_eq`). That frame depends on the frame grid. At 60 Hz it is 0.49 px at
1280 px and 0.8 px at ≥1438 px. At the Linux WebKit p50 gap of 173 ms it is 11.4 px, and at the p90 gap of 411 ms it
is 89.5 px (#guards). The waapi driver never writes the base `--morph` during a tween. So before-change and
after-change are equal and no transition starts (`tail_waapi_zero`). Raw check: at 1280 px on Linux WebKit, the
original's width on the flip frame (1026.578 px) equals `W(0.1664)`, the base value of the previous frame.

## Why not model it (Lean)

- `tail_not_view`: the original's width on the flip frame is not a function of that frame alone, so it lies outside
  `waapi_vis`.
- `skip_once` and `skips_le_one`: an exact driver may skip script on at most one next-frame time after any history. So
  it runs script on essentially every close frame before 612 ms, like the faithful driver.
- `tailArm` and `tail_decided`: the decision is `.lookChange`.

## Measured difference (MEASURED)

Tail = nav width at the first close sample with `m == 0`, minus the minimum close-hold width. Values are px per rep.

| Engine | Width | orig | base | waapi cand | Runs |
|---|---|---|---|---|---|
| Chromium | 1280 | 0.25-0.64 | 0.30-0.81 | 0 | 39457767229, 39412301221, 39471466367 |
| Chromium | 390/640/641 | 0 | 0 | 0 | same |
| macOS WebKit | 1280 | 0.27-2.92 | 0.52-0.95 (one rep 102.98) | 0 | 39471466367 |
| macOS WebKit | ≤641 | ≤0.09 | ≤0.09 | 0 | 39471466367 |
| Linux WebKit | 1280 | 42.6-209.4 | 4.6-54.9 | 0 | 39457767229, 39412301221 |
| Linux WebKit | 390/640 | ≤6.3 | ≤5.9 | 0 | same |

Run 39457063232 (hero.exit:faithful) is a control. Its candidate runs the faithful morph and keeps the tail: 18.8-45.7
px at 1280 px on Linux WebKit.

## Cost

- The original animates 1 element × 1 layout property (nav `width`) for 680 ms after every close, about 41 frames of
  style, layout and paint at 60 Hz. The waapi arm drops all of it (INFERRED from the CSS rule).
- An exact tail would need script on about 37 of the about 41 close frames before 612 ms, plus that transition. The
  waapi arm runs script on 13 of 64 frames on a reverse at 300 ms and 7 of 42 on an open (INFERRED, threshold-attr
  fake replay).
- The background-colour transition (0.7 s) starts at the same flip by the same mechanism. That is
  trajectory-close-start's accepted limit (INFERRED).

## Findings-ledger row (for the lead)

- id `morph.tween.waapi.navWidthTail`; part `morph.tween`; flag `morph.tween:waapi`; status `look-change`
- candidate: the waapi arm drops the original's 680 ms nav width transition that starts when `is-morphing` turns off
  on a close
- chromium: no visible change at 60 Hz (≤0.81 px); webkit: up to 209 px on Linux WebKit at 1280 px, ≤2.92 px on macOS
- mechanism: the cited rows above; lean: tail_orig_pos, tail_waapi_zero, tail_not_view, skip_once, tail_decided
- lesson: a transition keyed on a class flip starts from the previous frame's base style. A driver that skips frames
  cannot reproduce it without running script every frame, so it is a look-change class item.

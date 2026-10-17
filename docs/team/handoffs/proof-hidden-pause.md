# proof-hidden-pause (handoff)

State: `lean/Fw/Parts/HiddenPause.lean` (ns `Fw.Parts.HiddenPause`, imported in `lean/Fw.lean`). Golden rows: `packages/contracts/golden/engine/hidden-pause.jsonl` (8 rows, scenario swipe-v1, variant `hidden-pause`, base `rewrite`; generated from `goldenJsonl` with `import Fw.Parts.HiddenPause` + `def main := IO.FS.writeFile "../packages/contracts/golden/engine/hidden-pause.jsonl" goldenJsonl`, `lake env lean --run`). `lake build` is green, mathview lint reports 0 failing and 0 warnings for this module, and the only axioms are propext, Quot.sound and Classical.choice.
- Vision (E): `hidden_pause_eq`, `hiddenPause_visSame`, `panel_visSame` (every env/band, every t). The hidden condition comes from the parts: the panel's opacity is `clamp(0,(m-.08)/.72,1)`, so `panelOpacity_eq_zero_iff` gives opacity 0 ⇔ m ≤ 0.08. The original pauses only at m ≤ 0.001 (`scenePaused_imp_hiddenPause`). `offscreen_hidden`/`sceneHidden` cover engine.scene.
- Work: `pause_le` and `skipWrites_le` hold in every engine. Chromium lane: `cr_marquee_bands` gives style 1 → 0 per frame in each band (5, 3 or 0 marquees), and `cr_pause_style_units` holds. `cr_realChrome_pause_eq` shows equality off comp in real Chrome. WebKit: `wk_pause_eq` and `wk_marquee_bands` show equality on every web-process stage, not a win. Countdown: `cr_countdown_style` and `wk_countdown_style` give style 1 → 0, which is strict.

variant-hidden-pause (TS) must:
1. Pause morph.columns tracks while `hiddenPause(m)` holds (m ≤ 0.08) and the reduced-motion and ≤640 bands are unchanged. On resume, set `currentTime` to `origClock`: the original's clock runs whenever m > 0.001. A plain `animation-play-state` is NOT E (`naive_pause_shifts`).
2. morph.countdown: keep the spring integrating every rAF and skip only the 16-per-digit face writes while hidden. On unhide, write the current state in the same frame, before paint (`hsync`).
3. Leave will-change rules as they are. Label runs `meta.variant=hidden-pause` (base rewrite).

Open items:
- The win happens only on frames with 0.001 < m ≤ 0.08 (marquee) or m ≤ 0.08 (countdown), and only once morph.panel drives `--morph` in the rewrite.
- Toggle frames are not per-frame dominated.
- Occlusion is not modelled.
- Premise gap R6 is still open.
- The WebKit comp/UI-process tick is unmeasured.
- There is no compositeFailedBits row.

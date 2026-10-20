# panel-final-size handoff

**State.** Branch `worktree-wf_473f9c96-555-2`. C1 (final-size) is refuted on the visual and closed as a finding. There is
no flag, no golden and no CI run, because the task's stop rule fired at step 1.

**Verified (Lean, `lean/Fw/Parts/MorphPanelOpt.lean`, section `FinalSize` at the end of the file):**
- `end_E` and `hidden_E`: the arms are equal at `m = 1` and while `m ≤ 0.08` (panel opacity 0).
- `size_gap`, `footer_shift`: the layout sizes differ by `(1 - m)·Δ`, and the footer sits `(1 - m)·ΔH/2` lower.
- `not_Q`, `desk_not_Q`, `phone_not_Q`: every `m` in `(0.08, 1 - 1/(2ΔH))` breaks VisSame at 1440×900 and 390×844.
- `relayouts_final`: the work bound, 0 subtree layouts. `relayouts_orig_pos` covers the original. `#guard`: 41 per push.
- `#guard` frame verdicts: push 0→1 differs on frames 2–37 and is Q on 38–40; push 1→0 differs on frames 1–23.

**Written:**
- Note: `research/notes/2026/10-21-panel-final-size.md`, with the frame tables and the engine citations for WebKit@862f17d and Chromium@f842f52.
- Ledger row: `morph.panel.finalSize.visual` (n 11, refuted).

**Open:**
- C1b (`transform: scale` with `clip-path`) needs its own VisSame model.
- A per-box partial C1 needs a size-gap bound under ½ px for each box.
- WebKit paint area waits on webkit-lag-probe.

**Conventions.**
- The model takes a layout as `Rat → Rat → List (BoxId × Rect × Rat)`, centred on the panel. `place` applies the
  panel's scale, opacity, blur and the nav clip. Both arms share `place`, so only the layout size differs.
- Frames are `frameM f t k`, 60 Hz samples of `MorphTween.tween`.

**Read first:** the note, then `FinalSize.not_Q`.

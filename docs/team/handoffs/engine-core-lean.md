# engine-core-lean (handoff)
**State:** `Fw.Engine.Core` + `Fw.Engine.Visual` done on branch `worktree-agent-a58f2d86e3b7ec1ea` (commits a50d460,
d16e29d, 6871de7, then checker fixes). `lake build` green, mathview 0 failing, axioms only propext/Quot.sound/Classical.choice.
Files: `lean/Fw/Engine.lean` (umbrella), `lean/Fw/Engine/{Core,Visual}.lean`, one `import Fw.Engine` in `lean/Fw.lean`.
**Interface the engine tables (`Fw.Engine.Chromium`, `Fw.Engine.WebKit`) must implement:**
```lean
structure Engine (P M : Type) where
  mode : M                       -- engine configuration the table is keyed on
  stagesOf : Change P → List Stage  -- stages one property change dirties (its layer state is in the Change)
  compStages : List Stage        -- stages a running compositor animation touches per frame
  base : List Stage              -- stages every updating frame runs
```
`Stage = script|style|layout|props|paint|raster|commit|comp`; `Change P = {elem, prop : P, layer : LayerState}`;
`FrameIn P = {script, forcedStyle, forcedLayout, hits, changes, compAnims}`. Each table picks its own property type P.
**Core theorems:** `frame_le_of_cover` (sub-multiset cover via `Perm` + `coverB`), `frame_le_union` (Bool `unionLe`,
per-frame union of stages, since WebKit's stage map is not monotone in level order), `run_dominates` →
`run_dominates_sound` (via `Screen.screen_sound`), `toCost_mono`/`mainUs_toCost_le`/`run_mainUs` (into
`Cost.mainUs_mono`), `claim`/`run_claim` (Resident: dominates vs trade), `Shift` with `shift_peak`/`shift_total`
(golden case B: screen says mixed, Shift holds), `leFrames_series` (into `Measure.leFrames`).
**Visual:** `BoxVis`, `Scene`, `visible vp` (drops only alpha ≤ 0, visibility hidden, clip missing ink, ink bbox
outside viewport; occlusion not modelled). `E` is `=`; `Q` = `sceneQ` built only from `Gate.near tolBox/tolStyle` and
`Gate.styleValueEq`. `VisSame rel vp o v` (∀ env t). `PathPremises` = structure with fields `raster_path`, `c1`, `c2`,
`c3o`, `c3v` (hypotheses, no axioms); `shown_eq`. Lemmas `Q_refl`, `Q_symm`, `E_imp_Q`, `E_render`, `visSame_*`.
**Conventions:** Mathlib-free; `#guard` on every Bool decision; Rat literals need `decide +kernel`; Lean binders named
like the math (o/v, ks) so the mathview binder lint stays quiet.
**Open:** engine tables (stagesOf per engine, from source); Q-to-pixels needs a raster-continuity premise (not
stated); `leAll_zip`/`run_mainUs` keep a pair binder `p` written as (v, o) in the math (lint warning only).
**Read first:** design note `research/notes/2026/10-18-engine-proof-design.md`, then the module docs of Core/Visual.

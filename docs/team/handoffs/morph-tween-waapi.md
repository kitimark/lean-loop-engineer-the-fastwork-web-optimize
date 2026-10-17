# morph-tween-waapi (lean-prover)

State: branch `worktree-agent-a77e8b6867f962894`, see its last commit. `lake build` green, mathview 0 failing, axioms standard.
Lean: `lean/Fw/Parts/MorphTweenOpt.lean` (MT1, MT2 before; this task added MT3, MT4, visual, MT-W, golden rows).
- MT3 `waapi_eq_tween` / `waapi_frame_eq`: for every event list with nondecreasing frames, the WAAPI value at every
  frame equals `MorphTween.tween` exactly in Q. Premises are fields of `WaapiPremises` (never axioms): linear
  interpolation (`premisesWk` a+(b-a)p, `premisesBlink` (1-p)a+pb, proved equal), timing = `curveY` on [0,1],
  `tl R = R + c` and `startRead n = n + c` (same offset c for timeline and the start read).
- MT4 `flags_same_frame`: discrete keyframe at offset clamp01((θ-f)/(t-f)) flips like the original `>` test, except at the
  exact tie p = offset (engines flip at p ≥ c, R3b): `flag_below_tie`, `flag_tie`, `flag_above_tie`; `ease_gt_iff`;
  run level `flags_same_run` (no tie, `tieB`). Thresholds 1/5, 23/25, fade cut, `activeCut`; `fade_css`.
- Visual `waapi_vis`: `VisSame E` for every env (all widths) and any scene function, over tie-free histories `Hist`.
- MT-W `waapi_work_le`: Chromium (lane) and WebKit (Safari): custom-prop animation is main thread (`cr_custom_main`:
  bit 13; `WebKit.custom_main`), so the frame is the rAF frame minus script: script 1 pass/k units -> 0, all other
  stages equal (`dropsScript`, generic `script_drop`); `drop_run_dominates`; `pred_sound` -> golden predictions.
- Golden: `packages/contracts/golden/parts/morph-tween-waapi.jsonl` (11 engine-check rows, base `rewrite`; bit-13 row
  is rewrite vs variant). Written by `#eval IO.FS.writeFile ... goldenJsonl` (scratch); not yet in `partsgolden`.

TS variant task (flag `morph.tween:waapi`) must implement:
- `CSS.registerProperty({name:'--morph', syntax:'<number>', inherits:false, initialValue:'0'})`.
- On push(g): if target=g and in flight, no-op; reduced motion: cancel, set --morph=g (jump). Else cancel the old
  animation, new `el.animate([{'--morph':from},{'--morph':g}], {duration:680, easing:'cubic-bezier(1/3,1,2/3,1)', fill:'both'})`
  with easing on the effect (not per keyframe), `from` = the last frame's value.
- `anim.startTime = document.timeline.currentTime` read at the push (R5: the lane's clock shim fakes performance.now()
  but document.timeline stays native; premise start = n + c). Alternative: calibrate c with one rAF.
- Flags (on-dark > 0.2, expanded > 0.92, pointer cut): discrete keyframes at offset clamp01((θ-f)/(t-f)) in the same
  animation; fade via CSS `calc(1 - min(1, var(--morph) / 0.55))`. No rAF callback per frame.
Open premises: R5 lane offset c equal for both reads; P-from (Blink may sample `from` one frame late); R2 restyle scope
(variant animates exactly the props the original writes); R8 fp rounding vs MT2; wire golden into `Fw.Parts.Golden`.
Read first: module header of MorphTweenOpt.lean, then `WaapiPremises`, `stepV`, `Inv`.

# engine-webkit-lean (handoff)
**State:** `lean/Fw/Engine/WebKit.lean` + `packages/contracts/golden/engine/webkit.jsonl` (56 rows), one import in
`lean/Fw/Engine.lean`; worktree branch, first commit 5b9129c. `lake build` green, mathview 0 failing, no WebKit
quantifier warnings, axioms ⊆ propext/Quot.sound/Classical.choice.
**Model:** `Diff` (10 levels) ← `rawDiff : WkProp → Diff × List Ctx` → `adjust` (RenderElement.cpp:297-359, layer state
none/layer/own) → `diffStages`. `webkitAt m : Engine WkProp WkMode` (`base = [commit]`, `compStages = [comp]`),
`webkit = webkitAt WkMode.safari` (threaded scroll-driven on, threaded time-based off, Normal policy).
`WkProp` = change kinds incl. value transitions (`opacityCross1`, `transformToggle`, `filterPainted`, `clipPathShape`,
`insetAbs`, `scrollPos`). Thread rule over `CssProp`/`WkAnim`: `accelerated`, `pathOf`, `canBeAccelerated`,
`caAccepts` (GraphicsLayerCA), `wkThread`. Compositing: `CompReason`, `composites policy reason`, `robust`.
**Theorems:** `transform_diff`, `opacityCross1_layout`, `strokeDashoffset_layout`, `scrollPos_stages`, `wk_not_mono`
(+ #guards), `static2D_not_own`, `willChange_dropped`, `own_robust`, `base_commit`, `scroll_commit`, `scroll_baseline`,
`path_default`, `legacy_rejects`, `custom_main`, `comp_accelerated`, `compFrame_zero`, `anim_comp_zero`,
`trade_accepted` (via `frame_le_union`), `blur_comp`, `blur_zero`.
**Source finding (new vs design note §1.3):** `translateZ(0)`/`translate3d(x,y,0)` is a 3D op but representable in 2D
(`StyleTranslateTransformFunction.h:63`), so under Conservative it does NOT composite unless the box has a filter
(`RenderLayerCompositor.cpp:3897-3904`). Robust "own" premises: non-flat 3D op, 3D op + filter, animation,
backdrop-filter. Legacy CA path also rejects drop-shadow filter animations and mismatched filter op lists
(`GraphicsLayerCA.cpp:3946-3958`).
**Golden schema** (Chromium handoff did not exist yet): `{countType, engine, prediction, scenario, stage, variant}`,
keys sorted. `variant = "original"` rows predict `=0`/`>0` (absolute); other variants predict vs the original:
`=0`, `=o`, `<o`, `>o`, `any` (first match, `predictVar`). Count types: sim `FireAnimationFrame`, `RecalculateStyles`,
`Layout`, `Paint`, `Composite`; wktr `styleRecalcs`, `layoutUpdates`, `compositingUpdates`, `renderingUpdates`
(all but renderingUpdates are quarantined in measure-wktr; the reducer must skip them). Scenarios P1, P2, P3a
(clip-path), P3b (background-position), P4, P5 = `scenarios`.
**Regenerate:** a 4-line script `import Fw.Engine.WebKit` + `def main := IO.FS.writeFile
"../packages/contracts/golden/engine/webkit.jsonl" Fw.Engine.WebKit.goldenJsonl`, run with `lake env lean --run`
from `lean/`. No staleness check in `lake test` yet (FwTest/Golden.lean was outside this task): open item.
**Open:** clip (ClipRect) cell O5; Some-state split O3; Safari prefs O2; fixed/sticky scroll-time compositing update
not modelled (`scrollPos` dirties nothing); P1-P5 not yet run on CI (blocked on webkit-sim-rewrite). **Read first:**
module doc of WebKit.lean, then design note §1.3, WebKit note §2.2/§3.3/§5.3.

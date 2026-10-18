import Lean.Data.Json
import Fw.Engine.Core
/-!
# The WebKit (iOS Safari) engine table (PLAN §4.7, design note 2026-10-18 §1.3-1.4, WebKit note §2-§5)

`webkit : Engine WkProp WkMode` instantiates `Fw.Engine.Core`. A property change `WkProp` gets its raw
`StyleDifference` (`rawDiff`), which `adjust` raises by the target's layer state exactly as
`RenderElement::adjustStyleDifference` does; `diffStages` maps the adjusted `Diff` to pipeline stages. Every rendering
update pays `commit` (`base`), a running compositor animation pays only `comp` (`compStages`).

Rules beyond the table: the compositing reasons (`composites`, a static 2D transform never composites, `will-change`
is dropped under the Conservative policy), the thread rule (`wkThread`: accelerated properties, `canBeAccelerated`,
the threaded and the legacy Core Animation path), the scroll rule (`scrollStep`: every delivered scroll position is one
rendering update plus a commit), and the golden rows for predictions P1-P5 (`goldenJsonl`, written to
`packages/contracts/golden/engine/webkit.jsonl`).

Citations are to WebKit @862f17d (`WC` = `Source/WebCore`), read in the pinned clone `.cache/upstream/WebKit@862f17d`.
Status: every row is CONFIRMED from that source unless its docstring says INFERRED. Whether the shipped Safari obeys
the model is a measured claim (P1-P5), not a theorem; the scroll-driven style rows of P1 and P4 were wrong (`=0`) until
the WKTR fixtures measured one restyle per update (`style_rate_model`, `style_rate_old_refuted`). C-2: the stage map is **not** monotone in `Diff` order
(`wk_not_mono`), so dominance goes through `frame_le_union`, never through the enum order.
-/
namespace Fw.Engine.WebKit
open Fw.Engine
open Lean (Json)

/-! ## Style differences -/

/-- The ten `StyleDifference` levels in WebKit's own order (`WC/style/StyleDifference.h:28-55`, CONFIRMED).

$$\mathrm{Diff} = \{\mathrm{equal}, \mathrm{recomposite}, \mathrm{repaint}, \mathrm{repaintIfText}, \mathrm{repaintLayer}, \mathrm{layoutOOFMoveOnly}, \mathrm{overflow}, \mathrm{overflowOOF}, \mathrm{layout}, \mathrm{newStyle}\}$$
-/
inductive Diff where
  | equal | recomposite | repaint | repaintIfText | repaintLayer
  | layoutOOFMoveOnly | overflow | overflowOOF | layout | newStyle
deriving Repr, DecidableEq, Inhabited

/-- The position of a level in the enum order (`DifferenceResult` is a `uint8_t` enum, compared with `std::max`).

$$\operatorname{rank}(d) = \text{index of } d \text{ in } [\mathrm{equal}, \mathrm{recomposite}, \mathrm{repaint}, \mathrm{repaintIfText}, \mathrm{repaintLayer}, \mathrm{layoutOOFMoveOnly}, \mathrm{overflow}, \mathrm{overflowOOF}, \mathrm{layout}, \mathrm{newStyle}] \in \{0, \dots, 9\}$$
-/
def Diff.rank : Diff → Nat
  | .equal => 0 | .recomposite => 1 | .repaint => 2 | .repaintIfText => 3 | .repaintLayer => 4
  | .layoutOOFMoveOnly => 5 | .overflow => 6 | .overflowOOF => 7 | .layout => 8 | .newStyle => 9

/-- The larger of two levels in enum order (WebKit's `std::max` on `DifferenceResult`).

$$\max(a, b) = \begin{cases} b & \operatorname{rank}(a) \le \operatorname{rank}(b) \\ a & \text{otherwise} \end{cases}$$
-/
def Diff.max (a b : Diff) : Diff := if a.rank ≤ b.rank then b else a

/-- The stages one change at an adjusted level dirties (design note §1.3; WebKit note §2.1-2.2). `recomposite` is the
compositing update S3 (`props`) and no paint; the repaint levels paint and skip S3; `overflow`/`overflowOOF` run the
simplified layout plus a full layer repaint (`RenderElement.cpp:1368-1385`); `layoutOOFMoveOnly` is the cheap
movement-only layout. The commit is not here: it is in `base`. CONFIRMED.

$$\operatorname{stages}(d) = \begin{cases} \emptyset & d = \mathrm{equal} \\ \{\mathrm{style}, \mathrm{props}\} & d = \mathrm{recomposite} \\ \{\mathrm{style}, \mathrm{paint}\} & d \in \{\mathrm{repaint}, \mathrm{repaintIfText}, \mathrm{repaintLayer}\} \\ \{\mathrm{style}, \mathrm{layout}\} & d = \mathrm{layoutOOFMoveOnly} \\ \{\mathrm{style}, \mathrm{layout}, \mathrm{paint}\} & d \in \{\mathrm{overflow}, \mathrm{overflowOOF}\} \\ \{\mathrm{style}, \mathrm{layout}, \mathrm{props}, \mathrm{paint}\} & d \in \{\mathrm{layout}, \mathrm{newStyle}\} \end{cases}$$
-/
def diffStages : Diff → List Stage
  | .equal => []
  | .recomposite => [.style, .props]
  | .repaint | .repaintIfText | .repaintLayer => [.style, .paint]
  | .layoutOOFMoveOnly => [.style, .layout]
  | .overflow | .overflowOOF => [.style, .layout, .paint]
  | .layout | .newStyle => [.style, .layout, .props, .paint]

/-- The context-sensitive properties `Style::difference` reports beside the level (WebKit note §2.1; `ClipRect` is
not modelled, open item O5).

$$\mathrm{Ctx} = \{\mathrm{transform}, \mathrm{opacity}, \mathrm{filter}, \mathrm{clipPath}, \mathrm{willChange}\}$$
-/
inductive Ctx where
  | transform | opacity | filter | clipPath | willChange
deriving Repr, DecidableEq, Inhabited

/-- **The WebKit property type**: one kind of property change, with the value transition that decides its raw
level. `transform` covers `transform`/`translate`/`scale`/`rotate`/`offset-*` value changes while a transform stays
present; `*Toggle` and `opacityCross1` are the appear/disappear and `isOpaque` flips; `filterPainted` is a filter
value change on a layer that paints its filters (`shouldPaintWithFilters`); `clipPathShape` is a clip-path a
composited layer can composite (`willCompositeClipPath`: no mask, shape layer); `willChange` is a change that
`canTriggerCompositing`; `insetAbs` moves an absolute box, `inset` moves another positioned box; `size` is
width/height/margin/padding; `scrollPos` is a delivered scroll position (no style change).

$$\mathrm{WkProp} = \{\mathrm{transform}, \mathrm{transformToggle}, \mathrm{opacity}, \mathrm{opacityCross1}, \mathrm{filter}, \mathrm{filterPainted}, \mathrm{filterToggle}, \mathrm{clipPath}, \mathrm{clipPathShape}, \mathrm{willChange}, \mathrm{background}, \mathrm{color}, \mathrm{colorCurrent}, \mathrm{mask}, \mathrm{insetAbs}, \mathrm{inset}, \mathrm{size}, \mathrm{strokeDashoffset}, \mathrm{scrollPos}\}$$
-/
inductive WkProp where
  | transform | transformToggle | opacity | opacityCross1 | filter | filterPainted | filterToggle
  | clipPath | clipPathShape | willChange | background | color | colorCurrent | mask
  | insetAbs | inset | size | strokeDashoffset | scrollPos
deriving Repr, DecidableEq, Inhabited

/-- The raw level and context set of a change (`WC/style/StyleDifference.cpp`@862f17d, WebKit note §2.2): transform
value ctx Transform (199-205, 246-252), transform toggle Layout (200-201); opacity ctx Opacity (571-578), opacity
crossing 1 Layout (208-214); filter ctx Filter (571-578), filter toggle Layout (217); clip-path ctx ClipPath
(779-780); will-change ctx WillChange (260-262); background-* Repaint (673, 856-858); color RepaintIfText (890-893),
currentColor Repaint (646, 700-707); mask RepaintLayer; top/left on an absolute box LayoutOutOfFlowMovementOnly
(436-445, 557-564), on another positioned box Layout; width/height/margin Layout (404-407, 423); stroke-dashoffset
Layout (161); a scroll position Equal. CONFIRMED.

$$\operatorname{raw}(p) = \begin{cases} (\mathrm{equal}, \{\mathrm{transform}\}) & p = \mathrm{transform} \\ (\mathrm{equal}, \{\mathrm{opacity}\}) & p = \mathrm{opacity} \\ (\mathrm{equal}, \{\mathrm{filter}\}) & p \in \{\mathrm{filter}, \mathrm{filterPainted}\} \\ (\mathrm{equal}, \{\mathrm{clipPath}\}) & p \in \{\mathrm{clipPath}, \mathrm{clipPathShape}\} \\ (\mathrm{equal}, \{\mathrm{willChange}\}) & p = \mathrm{willChange} \\ (\mathrm{repaint}, \emptyset) & p \in \{\mathrm{background}, \mathrm{colorCurrent}\} \\ (\mathrm{repaintIfText}, \emptyset) & p = \mathrm{color} \\ (\mathrm{repaintLayer}, \emptyset) & p = \mathrm{mask} \\ (\mathrm{layoutOOFMoveOnly}, \emptyset) & p = \mathrm{insetAbs} \\ (\mathrm{layout}, \emptyset) & p \in \{\mathrm{transformToggle}, \mathrm{opacityCross1}, \mathrm{filterToggle}, \mathrm{inset}, \mathrm{size}, \mathrm{strokeDashoffset}\} \\ (\mathrm{equal}, \emptyset) & p = \mathrm{scrollPos} \end{cases}$$
-/
def rawDiff : WkProp → Diff × List Ctx
  | .transform => (.equal, [.transform])
  | .opacity => (.equal, [.opacity])
  | .filter | .filterPainted => (.equal, [.filter])
  | .clipPath | .clipPathShape => (.equal, [.clipPath])
  | .willChange => (.equal, [.willChange])
  | .background | .colorCurrent => (.repaint, [])
  | .color => (.repaintIfText, [])
  | .mask => (.repaintLayer, [])
  | .insetAbs => (.layoutOOFMoveOnly, [])
  | .transformToggle | .opacityCross1 | .filterToggle | .inset | .size | .strokeDashoffset => (.layout, [])
  | .scrollPos => (.equal, [])

/-- The transform step of `adjustStyleDifference` (`WC/rendering/RenderElement.cpp:300-312`): no layer raises to
Layout, a non-composited layer to Overflow (OverflowAndOutOfFlowMovement after a movement-only level), a composited
layer to RecompositeLayer. CONFIRMED.

$$\operatorname{adjT}(d, \ell) = \begin{cases} \max(d, \mathrm{layout}) & \ell = \mathrm{none} \\ \max(d, \mathrm{overflowOOF}) & \ell = \mathrm{layer} \land d = \mathrm{layoutOOFMoveOnly} \\ \max(d, \mathrm{overflow}) & \ell = \mathrm{layer} \land d \ne \mathrm{layoutOOFMoveOnly} \\ \max(d, \mathrm{recomposite}) & \ell = \mathrm{own} \end{cases}$$
-/
def adjTransform (d : Diff) : LayerState → Diff
  | .none => d.max .layout
  | .layer => d.max (if d = .layoutOOFMoveOnly then .overflowOOF else .overflow)
  | .own => d.max .recomposite

/-- **The adjusted level** (`RenderElement::adjustStyleDifference`, `WC/rendering/RenderElement.cpp:297-359`): each
context property raises the raw level by the layer state, in source order (transform, opacity, clip-path,
will-change, filter), and RepaintLayer without a layer becomes Repaint. `fp` is `shouldPaintWithFilters`, `cc` is
`willCompositeClipPath`. The `requiresLayer` flip (`:345-352`) is carried by the toggle properties, whose raw level is
already Layout. CONFIRMED.

$$\operatorname{adjust}(d, C, \ell, \mathit{fp}, \mathit{cc}) = \operatorname{fix}(d_5),\quad \begin{aligned} d_1 &= \begin{cases} \operatorname{adjT}(d, \ell) & \mathrm{transform} \in C \\ d & \text{otherwise}\end{cases} \\ d_2 &= \begin{cases} \max(d_1, \mathrm{recomposite}) & \mathrm{opacity} \in C \land \ell = \mathrm{own} \\ \max(d_1, \mathrm{repaintLayer}) & \mathrm{opacity} \in C \land \ell \ne \mathrm{own} \\ d_1 & \text{otherwise}\end{cases} \\ d_3 &= \begin{cases} \max(d_2, \mathrm{recomposite}) & \mathrm{clipPath} \in C \land \ell \ne \mathrm{none} \land \mathit{cc} \\ \max(d_2, \mathrm{repaint}) & \mathrm{clipPath} \in C \land \lnot(\ell \ne \mathrm{none} \land \mathit{cc}) \\ d_2 & \text{otherwise}\end{cases} \\ d_4 &= \begin{cases} \max(d_3, \mathrm{recomposite}) & \mathrm{willChange} \in C \\ d_3 & \text{otherwise}\end{cases} \\ d_5 &= \begin{cases} \max(d_4, \mathrm{recomposite}) & \mathrm{filter} \in C \land \ell = \mathrm{own} \land \lnot \mathit{fp} \\ \max(d_4, \mathrm{repaintLayer}) & \mathrm{filter} \in C \land \ell \ne \mathrm{none} \land (\ell \ne \mathrm{own} \lor \mathit{fp}) \\ d_4 & \text{otherwise}\end{cases} \\ \operatorname{fix}(x) &= \begin{cases} \mathrm{repaint} & x = \mathrm{repaintLayer} \land \ell = \mathrm{none} \\ x & \text{otherwise}\end{cases} \end{aligned}$$
-/
def adjust (d : Diff) (cs : List Ctx) (ls : LayerState) (fp cc : Bool) : Diff :=
  let d1 := if Ctx.transform ∈ cs then adjTransform d ls else d
  let d2 := if Ctx.opacity ∈ cs then (if ls = .own then d1.max .recomposite else d1.max .repaintLayer) else d1
  let d3 := if Ctx.clipPath ∈ cs then
      (if ls ≠ .none ∧ cc = true then d2.max .recomposite else d2.max .repaint) else d2
  let d4 := if Ctx.willChange ∈ cs then d3.max .recomposite else d3
  let d5 := if Ctx.filter ∈ cs ∧ ls ≠ .none then
      (if ls = .own ∧ fp = false then d4.max .recomposite else d4.max .repaintLayer) else d4
  if d5 = .repaintLayer ∧ ls = .none then .repaint else d5

/-- The adjusted level of one change: its raw level and context set, adjusted by its layer state, with
`shouldPaintWithFilters` iff the property is `filterPainted` and `willCompositeClipPath` iff it is `clipPathShape` on a
composited layer (`RenderLayer.cpp:779-791`).

$$\operatorname{diff}(c) = \operatorname{adjust}\big(\operatorname{raw}(c.\mathrm{prop}),\ c.\mathrm{layer},\ [c.\mathrm{prop} = \mathrm{filterPainted}],\ [c.\mathrm{prop} = \mathrm{clipPathShape} \land c.\mathrm{layer} = \mathrm{own}]\big)$$
-/
def wkDiff (c : Change WkProp) : Diff :=
  adjust (rawDiff c.prop).1 (rawDiff c.prop).2 c.layer (decide (c.prop = .filterPainted))
    (decide (c.prop = .clipPathShape ∧ c.layer = .own))

/-! ## The engine -/

/-- WebKit's compositing policy (`RenderLayerCompositor::updateCompositingPolicy`, `WC/rendering/RenderLayerCompositor.cpp:691-719`):
Conservative under memory pressure or a memory warning, Normal otherwise. CONFIRMED.

$$\mathrm{Policy} = \{\mathrm{normal}, \mathrm{conservative}\}$$
-/
inductive Policy where
  | normal | conservative
deriving Repr, DecidableEq, Inhabited

/-- The WebKit run mode: the two threaded-animation preferences and the compositing policy.

$$\mathrm{WkMode} = \underbrace{\mathbb{B}}_{\mathrm{threadedScrollDriven}} \times \underbrace{\mathbb{B}}_{\mathrm{threadedTimeBased}} \times \underbrace{\mathrm{Policy}}_{\mathrm{policy}}$$
-/
structure WkMode where
  threadedScrollDriven : Bool
  threadedTimeBased    : Bool
  policy               : Policy
deriving Repr, DecidableEq

/-- The default mode for the Simulator and the phone: threaded scroll-driven animations on (preference stable,
default true, `UnifiedWebPreferences.yaml:8518-8531`), threaded time-based off (preview, default false, `:8557-8570`),
Normal policy. CONFIRMED as WebKit defaults; that Safari ships them is INFERRED (open item O2).

$$\mathrm{safari} = (\mathrm{true}, \mathrm{false}, \mathrm{normal})$$
-/
def WkMode.safari : WkMode := ⟨true, false, .normal⟩

/-- **The WebKit engine** in mode `m`: a change dirties the stages of its adjusted level; a running compositor
animation costs only `comp` (UI-process Core Animation tick; `KeyframeEffect.cpp:2724-2744`,
`DocumentTimeline.cpp:156-168`); every rendering update pays `commit`, the transaction walk over all layers plus the
commit sent "even if nothing changed" (`WK/WebProcess/WebPage/RemoteLayerTree/RemoteLayerTreeDrawingArea.mm:319-443`).
CONFIRMED.

$$\operatorname{webkitAt}(m) = \big(m,\ c \mapsto \operatorname{stages}(\operatorname{diff}(c)),\ [\mathrm{comp}],\ [\mathrm{commit}]\big)$$
-/
def webkitAt (m : WkMode) : Engine WkProp WkMode where
  mode := m
  stagesOf c := diffStages (wkDiff c)
  compStages := [.comp]
  base := [.commit]

/-- The WebKit engine in the default Safari mode.

$$\mathrm{webkit} = \operatorname{webkitAt}(\mathrm{safari})$$
-/
def webkit : Engine WkProp WkMode := webkitAt WkMode.safari

/-! ## The table, row by row -/

/-- A transform value change on a composited layer is RecompositeLayer, on a non-composited layer Overflow, with no
layer Layout (`RenderElement.cpp:300-312`).

$$\forall e \in \mathbb{N}:\ \operatorname{diff}(e, \mathrm{transform}, \mathrm{own}) = \mathrm{recomposite} \land \operatorname{diff}(e, \mathrm{transform}, \mathrm{layer}) = \mathrm{overflow} \land \operatorname{diff}(e, \mathrm{transform}, \mathrm{none}) = \mathrm{layout}$$
-/
theorem transform_diff (e : Nat) : wkDiff ⟨e, .transform, .own⟩ = .recomposite ∧
    wkDiff ⟨e, .transform, .layer⟩ = .overflow ∧ wkDiff ⟨e, .transform, .none⟩ = .layout := by
  refine ⟨?_, ?_, ?_⟩ <;> rfl

/-- **Opacity crossing 1 → layout.** An opacity change that flips `isOpaque` dirties layout on every layer state
(`StyleDifference.cpp:208-214`; Chromium keeps it `direct`, design note §1.4).

$$\forall m, \forall e \in \mathbb{N}, \forall \ell \in \mathrm{LayerState}:\ \mathrm{layout} \in \operatorname{webkitAt}(m).\mathrm{stagesOf}(e, \mathrm{opacityCross1}, \ell)$$
-/
theorem opacityCross1_layout (m : WkMode) (e : Nat) (ℓ : LayerState) :
    Stage.layout ∈ (webkitAt m).stagesOf ⟨e, .opacityCross1, ℓ⟩ := by
  have h : wkDiff ⟨e, .opacityCross1, ℓ⟩ = .layout := by cases ℓ <;> rfl
  simp [webkitAt, h, diffStages]

/-- **stroke-dashoffset → layout.** A stroke-dashoffset change recomputes the cached stroke bounds, so it dirties
layout on every layer state (`StyleDifference.cpp:161`; Chromium: paint).

$$\forall m, \forall e \in \mathbb{N}, \forall \ell \in \mathrm{LayerState}:\ \mathrm{layout} \in \operatorname{webkitAt}(m).\mathrm{stagesOf}(e, \mathrm{strokeDashoffset}, \ell)$$
-/
theorem strokeDashoffset_layout (m : WkMode) (e : Nat) (ℓ : LayerState) :
    Stage.layout ∈ (webkitAt m).stagesOf ⟨e, .strokeDashoffset, ℓ⟩ := by
  have h : wkDiff ⟨e, .strokeDashoffset, ℓ⟩ = .layout := by cases ℓ <;> rfl
  simp [webkitAt, h, diffStages]

/-- A delivered scroll position dirties no stage by itself; its cost is the update's `base` (the commit).

$$\forall m, \forall e \in \mathbb{N}, \forall \ell \in \mathrm{LayerState}:\ \operatorname{webkitAt}(m).\mathrm{stagesOf}(e, \mathrm{scrollPos}, \ell) = [\,]$$
-/
theorem scrollPos_stages (m : WkMode) (e : Nat) (ℓ : LayerState) :
    (webkitAt m).stagesOf ⟨e, .scrollPos, ℓ⟩ = [] := by
  cases ℓ <;> rfl

/-- **`wk_not_mono` (C-2).** RecompositeLayer is below Repaint in the enum order, yet each dirties a stage the other
does not: `props` only for recomposite, `paint` only for repaint. So the stage map is not monotone in `Diff` order.

$$\operatorname{rank}(\mathrm{recomposite}) < \operatorname{rank}(\mathrm{repaint}) \ \land\ \mathrm{props} \in \operatorname{stages}(\mathrm{recomposite}) \setminus \operatorname{stages}(\mathrm{repaint}) \ \land\ \mathrm{paint} \in \operatorname{stages}(\mathrm{repaint}) \setminus \operatorname{stages}(\mathrm{recomposite})$$
-/
theorem wk_not_mono : Diff.recomposite.rank < Diff.repaint.rank ∧
    (Stage.props ∈ diffStages .recomposite ∧ Stage.props ∉ diffStages .repaint) ∧
    (Stage.paint ∈ diffStages .repaint ∧ Stage.paint ∉ diffStages .recomposite) := by
  decide

-- C-2 counterexample: recomposite < repaint in rank, but neither stage set contains the other.
#guard Diff.recomposite.rank < Diff.repaint.rank
#guard !(diffStages .recomposite).all (· ∈ diffStages .repaint)
#guard !(diffStages .repaint).all (· ∈ diffStages .recomposite)
-- the table rows
#guard wkDiff ⟨1, .opacity, .own⟩ == .recomposite && wkDiff ⟨1, .opacity, .layer⟩ == .repaintLayer
#guard wkDiff ⟨1, .opacity, .none⟩ == .repaint
#guard wkDiff ⟨1, .filter, .own⟩ == .recomposite && wkDiff ⟨1, .filterPainted, .own⟩ == .repaintLayer
#guard wkDiff ⟨1, .filter, .layer⟩ == .repaintLayer
#guard wkDiff ⟨1, .clipPathShape, .own⟩ == .recomposite && wkDiff ⟨1, .clipPathShape, .layer⟩ == .repaint
#guard wkDiff ⟨1, .clipPath, .own⟩ == .repaint
#guard wkDiff ⟨1, .background, .own⟩ == .repaint && wkDiff ⟨1, .color, .none⟩ == .repaintIfText
#guard wkDiff ⟨1, .mask, .layer⟩ == .repaintLayer && wkDiff ⟨1, .mask, .none⟩ == .repaint
#guard wkDiff ⟨1, .insetAbs, .own⟩ == .layoutOOFMoveOnly && wkDiff ⟨1, .size, .own⟩ == .layout
#guard wkDiff ⟨1, .willChange, .none⟩ == .recomposite && wkDiff ⟨1, .scrollPos, .own⟩ == .equal
#guard adjust .layoutOOFMoveOnly [.transform] .layer false false == .overflowOOF
#guard webkit.stagesOf ⟨1, .transform, .layer⟩ == [.style, .layout, .paint]
#guard webkit.stagesOf ⟨1, .opacityCross1, .own⟩ == [.style, .layout, .props, .paint]

/-! ## Composited state -/

/-- A reason a box might get its own composited layer (`RenderLayerCompositor::requiresCompositingLayer`,
`RenderLayerCompositor.cpp:3289-3317`): a 2D transform; a 3D op representable in 2D (`translateZ(0)`,
`translate3d(x, y, 0)`), with or without a filter on the box; a 3D op not representable in 2D (`rotateX`, a
non-zero `translateZ`, a non-affine `matrix3d`); a running or style-affecting animation of an accelerated property;
backdrop-filter; `will-change` that can trigger compositing; a static filter.

$$\mathrm{CompReason} = \{\mathrm{transform2D}, \mathrm{transform3DFlat}, \mathrm{transform3DFlatFilter}, \mathrm{transform3D}, \mathrm{animation}, \mathrm{backdropFilter}, \mathrm{willChange}, \mathrm{filterStatic}\}$$
-/
inductive CompReason where
  | transform2D | transform3DFlat | transform3DFlatFilter | transform3D
  | animation | backdropFilter | willChange | filterStatic
deriving Repr, DecidableEq, Inhabited

/-- Whether a reason composites the box under a policy. Transform (`:3878-3907`): Normal needs a 3D op
(`is3DOperation`, `StyleTransformFunctionBase.h:105-117`); Conservative needs a 3D op with a filter or ops not
representable in 2D (`translateZ(0)` is, `StyleTranslateTransformFunction.h:63`). Animation (`:3842-3870`) and
backdrop-filter (`:3981-3995`) under both. `will-change` returns false under Conservative on non-Mac (`:3997-4018`).
A static filter never: the WebKit2 triggers have no FilterTrigger (`WK/WebProcess/WebCoreSupport/WebChromeClient.h:292-306`).
CONFIRMED.

$$\operatorname{composites}(p, r) = \begin{cases} \mathrm{true} & r \in \{\mathrm{transform3D}, \mathrm{transform3DFlatFilter}, \mathrm{animation}, \mathrm{backdropFilter}\} \\ [p = \mathrm{normal}] & r \in \{\mathrm{transform3DFlat}, \mathrm{willChange}\} \\ \mathrm{false} & r \in \{\mathrm{transform2D}, \mathrm{filterStatic}\} \end{cases}$$
-/
def composites : Policy → CompReason → Bool
  | _, .transform3D | _, .transform3DFlatFilter | _, .animation | _, .backdropFilter => true
  | .normal, .transform3DFlat | .normal, .willChange => true
  | .conservative, .transform3DFlat | .conservative, .willChange => false
  | _, .transform2D | _, .filterStatic => false

/-- The reasons that composite under every policy.

$$\mathrm{robust} = [\mathrm{transform3D}, \mathrm{transform3DFlatFilter}, \mathrm{animation}, \mathrm{backdropFilter}]$$
-/
def robust : List CompReason := [.transform3D, .transform3DFlatFilter, .animation, .backdropFilter]

/-- **A static 2D transform does not composite**, under either policy.

$$\forall p \in \mathrm{Policy}:\ \operatorname{composites}(p, \mathrm{transform2D}) = \mathrm{false}$$
-/
theorem static2D_not_own (p : Policy) : composites p .transform2D = false := by
  cases p <;> rfl

/-- **will-change is dropped under the Conservative policy.**

$$\operatorname{composites}(\mathrm{conservative}, \mathrm{willChange}) = \mathrm{false}$$
-/
theorem willChange_dropped : composites .conservative .willChange = false := rfl

/-- **Where an "own layer" premise may come from.** A reason composites under every policy iff it is a 3D op not
representable in 2D (or a 3D op on a filtered box), an animation, or backdrop-filter; never `will-change` alone, and
not `translateZ(0)` alone.

$$\forall r \in \mathrm{CompReason}:\ \big(\forall p \in \mathrm{Policy}:\ \operatorname{composites}(p, r) = \mathrm{true}\big) \iff r \in \mathrm{robust}$$
-/
theorem own_robust (r : CompReason) : (∀ p, composites p r = true) ↔ r ∈ robust := by
  constructor
  · intro h
    have h1 := h .conservative
    cases r <;> simp_all [composites, robust]
  · intro h p
    cases r <;> cases p <;> simp_all [composites, robust]

#guard !composites .normal .transform2D && !composites .normal .filterStatic
#guard composites .normal .transform3DFlat && !composites .conservative .transform3DFlat
#guard composites .conservative .transform3DFlatFilter && composites .conservative .animation
#guard composites .normal .willChange && !composites .conservative .willChange

/-! ## Base and scroll -/

/-- **Every rendering update pays commit.** A frame with a change or a script callback touches `commit`.

$$\forall m, \forall f \in \mathrm{FrameIn}(\mathrm{WkProp}):\ \operatorname{updates}(f) = \mathrm{true} \Rightarrow \mathrm{commit} \in \operatorname{touched}_{\operatorname{webkitAt}(m)}(f)$$
-/
theorem base_commit (m : WkMode) (f : FrameIn WkProp) (h : f.updates = true) :
    Stage.commit ∈ touched (webkitAt m) f := by
  simp [touched, h, webkitAt]

/-- A delivered scroll position: the frame plus a `scrollPos` change on the root (element 0), so the frame is a
rendering update (`Document::addPendingScrollEventTarget` schedules `RenderingUpdateStep::Scroll`,
`WC/dom/Document.cpp:5913-5937`, with or without listeners; WebKit note §4.2). CONFIRMED.

$$\operatorname{scrollStep}(f) = f \text{ with } \mathrm{changes} := (0, \mathrm{scrollPos}, \mathrm{none}) :: f.\mathrm{changes}$$
-/
def scrollStep (f : FrameIn WkProp) : FrameIn WkProp :=
  { f with changes := ⟨0, .scrollPos, .none⟩ :: f.changes }

/-- **Scroll rule.** Every delivered scroll position pays exactly one commit pass, whatever the frame does besides (design note §1.3, prediction P4).

$$\forall m, \forall f \in \mathrm{FrameIn}(\mathrm{WkProp}):\ \operatorname{frameWork}_{\operatorname{webkitAt}(m)}(\operatorname{scrollStep}(f)).\mathrm{passes}(\mathrm{commit}) = 1$$
-/
theorem scroll_commit (m : WkMode) (f : FrameIn WkProp) :
    (frameWork (webkitAt m) (scrollStep f)).passes .commit = 1 := by
  have h : (scrollStep f).updates = true := by simp [scrollStep, FrameIn.updates]
  simp [frameWork, forcedPasses, base_commit m _ h]

/-- **Equal scroll baseline (P4).** Two variants pay the same commit passes on a scroll step, so a comparison reduces
to the other stages.

$$\forall m, \forall v, o \in \mathrm{FrameIn}(\mathrm{WkProp}):\ \operatorname{frameWork}_{\operatorname{webkitAt}(m)}(\operatorname{scrollStep}(v)).\mathrm{passes}(\mathrm{commit}) = \operatorname{frameWork}_{\operatorname{webkitAt}(m)}(\operatorname{scrollStep}(o)).\mathrm{passes}(\mathrm{commit})$$
-/
theorem scroll_baseline (m : WkMode) (v o : FrameIn WkProp) :
    (frameWork (webkitAt m) (scrollStep v)).passes .commit = (frameWork (webkitAt m) (scrollStep o)).passes .commit := by
  rw [scroll_commit, scroll_commit]

/-! ## The thread rule -/

/-- An animated CSS property, for the thread rule (`WC/css/CSSProperties.json`, key "animation-wrapper-acceleration").
`offset` stands for the `offset-*` longhands; `custom` for a custom property `--x`.

$$\mathrm{CssProp} = \{\mathrm{transform}, \mathrm{translate}, \mathrm{scale}, \mathrm{rotate}, \mathrm{opacity}, \mathrm{filter}, \mathrm{backdropFilter}, \mathrm{offset}, \mathrm{clipPath}, \mathrm{background}, \mathrm{color}, \mathrm{inset}, \mathrm{size}, \mathrm{strokeDashoffset}, \mathrm{custom}\}$$
-/
inductive CssProp where
  | transform | translate | scale | rotate | opacity | filter | backdropFilter | offset
  | clipPath | background | color | inset | size | strokeDashoffset | custom
deriving Repr, DecidableEq, Inhabited

/-- The two accelerated paths: the threaded `AcceleratedEffect` path (UI-process `RemoteAnimationStack`) and the
legacy `GraphicsLayerCA` CAAnimation path.

$$\mathrm{Path} = \{\mathrm{threaded}, \mathrm{legacy}\}$$
-/
inductive Path where
  | threaded | legacy
deriving Repr, DecidableEq, Inhabited

/-- **The accelerated property set** of a path: "always" (opacity, filter, backdrop-filter, transform, translate,
scale, rotate) on both paths, `offset-*` on the threaded path only (`CSSProperties.json` via
`process-css-properties.py:3823, 4093-4096`). Custom properties are never accelerated
(`WC/style/StyleInterpolation.cpp:256-265`). CONFIRMED; `offset` gated on the path itself is INFERRED.

$$\operatorname{accel}(\pi, q) = \begin{cases} \mathrm{true} & q \in \{\mathrm{transform}, \mathrm{translate}, \mathrm{scale}, \mathrm{rotate}, \mathrm{opacity}, \mathrm{filter}, \mathrm{backdropFilter}\} \\ [\pi = \mathrm{threaded}] & q = \mathrm{offset} \\ \mathrm{false} & \text{otherwise} \end{cases}$$
-/
def accelerated : Path → CssProp → Bool
  | _, .transform | _, .translate | _, .scale | _, .rotate | _, .opacity | _, .filter | _, .backdropFilter => true
  | .threaded, .offset => true
  | _, _ => false

/-- An animation's timeline: the document (time-based) or a scroll/view (progress-based) timeline.

$$\mathrm{Timeline} = \{\mathrm{time}, \mathrm{scroll}\}$$
-/
inductive Timeline where
  | time | scroll
deriving Repr, DecidableEq, Inhabited

/-- An animation's easing, as far as the paths care: linear, a cubic Bézier with both control y in [0, 1], a cubic
Bézier with a control y outside [0, 1], `steps()`, `linear()` with points.

$$\mathrm{Easing} = \{\mathrm{linear}, \mathrm{cubic}, \mathrm{cubicYOut}, \mathrm{steps}, \mathrm{linearPoints}\}$$
-/
inductive Easing where
  | linear | cubic | cubicYOut | steps | linearPoints
deriving Repr, DecidableEq, Inhabited

/-- The path-independent disqualifiers of `KeyframeEffect::canBeAccelerated` (`KeyframeEffect.cpp:1970-1992`): no
timeline, skipped content, an accelerated property overridden by the cascade, a `url()` filter, anchor geometry, a
size-dependent transform with size animated, a discrete transform interval, unresolved keyframe offsets, a site quirk.

$$\mathrm{Blocker} = \{\mathrm{noTimeline}, \mathrm{skippedContent}, \mathrm{overridden}, \mathrm{referenceFilter}, \mathrm{anchorGeometry}, \mathrm{sizeDependentTransform}, \mathrm{discreteTransform}, \mathrm{unresolvedOffsets}, \mathrm{quirk}\}$$
-/
inductive Blocker where
  | noTimeline | skippedContent | overridden | referenceFilter | anchorGeometry | sizeDependentTransform
  | discreteTransform | unresolvedOffsets | quirk
deriving Repr, DecidableEq, Inhabited

/-- One CSS animation or transition (a keyframe effect), with the facts the thread rule reads: animated properties,
timeline, easing, playback rate equal to 1, forwards direction, positive duration, keyframe count, a single interval
with linear timing, composite `replace` (no per-keyframe composite on an accelerated property), pending, the scroll
source has a scrolling node, a drop-shadow in the filter values, the filter op lists match, and the blockers.

$$\mathrm{WkAnim} = \mathrm{CssProp}^{*} \times \mathrm{Timeline} \times \mathrm{Easing} \times \underbrace{\mathbb{B}}_{\mathrm{rateOne}} \times \underbrace{\mathbb{B}}_{\mathrm{forwards}} \times \underbrace{\mathbb{B}}_{\mathrm{positiveDuration}} \times \underbrace{\mathbb{N}}_{\mathrm{keyframes}} \times \underbrace{\mathbb{B}}_{\mathrm{singleLinearInterval}} \times \underbrace{\mathbb{B}}_{\mathrm{compositeReplace}} \times \underbrace{\mathbb{B}}_{\mathrm{pending}} \times \underbrace{\mathbb{B}}_{\mathrm{scrollerAsync}} \times \underbrace{\mathbb{B}}_{\mathrm{dropShadow}} \times \underbrace{\mathbb{B}}_{\mathrm{filterOpsMatch}} \times \mathrm{Blocker}^{*}$$
-/
structure WkAnim where
  props                : List CssProp
  timeline             : Timeline
  easing               : Easing
  rateOne              : Bool
  forwards             : Bool
  positiveDuration     : Bool
  keyframes            : Nat
  singleLinearInterval : Bool
  compositeReplace     : Bool
  pending              : Bool
  scrollerAsync        : Bool
  dropShadow           : Bool
  filterOpsMatch       : Bool
  blockers             : List Blocker
deriving Repr, DecidableEq

/-- The path an animation takes (`KeyframeEffect::canHaveAcceleratedRepresentation`, `KeyframeEffect.cpp:3253-3264`):
threaded for a scroll timeline when threaded scroll-driven animations are on, threaded for a time timeline when threaded
time-based animations are on, else legacy. CONFIRMED.

$$\operatorname{path}(m, a) = \begin{cases} \mathrm{threaded} & a.\mathrm{timeline} = \mathrm{scroll} \land m.\mathrm{threadedScrollDriven} \\ \mathrm{threaded} & a.\mathrm{timeline} = \mathrm{time} \land m.\mathrm{threadedTimeBased} \\ \mathrm{legacy} & \text{otherwise} \end{cases}$$
-/
def pathOf (m : WkMode) (a : WkAnim) : Path :=
  match a.timeline with
  | .scroll => if m.threadedScrollDriven then .threaded else .legacy
  | .time => if m.threadedTimeBased then .threaded else .legacy

/-- **`canBeAccelerated`** (`KeyframeEffect::canBeAccelerated`, `KeyframeEffect.cpp:1970-2033`): no blocker, some
animated property accelerated (state not None); on the threaded path not pending and the timeline accelerable (a
scroll timeline needs a source with a scrolling node, `ScrollTimeline.cpp:417-427`; the document timeline always,
`DocumentTimeline.cpp:538-541`); on the legacy path a time timeline, no `steps()`, no `linear()` with points, and
composite replace. CONFIRMED.

$$\operatorname{cba}(m, a) \iff a.\mathrm{blockers} = [\,] \land \big(\exists q \in a.\mathrm{props}:\ \operatorname{accel}(\operatorname{path}(m, a), q)\big) \land \begin{cases} \lnot a.\mathrm{pending} \land (a.\mathrm{timeline} = \mathrm{time} \lor a.\mathrm{scrollerAsync}) & \operatorname{path}(m, a) = \mathrm{threaded} \\ a.\mathrm{timeline} = \mathrm{time} \land a.\mathrm{easing} \notin \{\mathrm{steps}, \mathrm{linearPoints}\} \land a.\mathrm{compositeReplace} & \operatorname{path}(m, a) = \mathrm{legacy} \end{cases}$$
-/
def canBeAccelerated (m : WkMode) (a : WkAnim) : Bool :=
  a.blockers.isEmpty && a.props.any (accelerated (pathOf m a)) &&
    match pathOf m a with
    | .threaded => !a.pending && (decide (a.timeline = .time) || a.scrollerAsync)
    | .legacy => decide (a.timeline = .time) && decide (a.easing ≠ .steps) && decide (a.easing ≠ .linearPoints) &&
        a.compositeReplace

/-- Whether an animated property is a filter list (`filter` or `backdrop-filter`).

$$\operatorname{isFilter}(q) \iff q \in \{\mathrm{filter}, \mathrm{backdropFilter}\}$$
-/
def isFilter (q : CssProp) : Bool := q == .filter || q == .backdropFilter

/-- **The legacy Core Animation gate** (`GraphicsLayerCA::addAnimation` and `animationCanBeAccelerated`,
`GraphicsLayerCA.cpp:1169-1215`; filters `createFilterAnimationsFromKeyframes` `:3946-3958` with
`GraphicsLayer::validateFilterOperations` `GraphicsLayer.cpp:816-846`): playback rate 1, forwards, positive duration,
at least 2 keyframes, no `steps()`, a cubic with y outside [0, 1] only over a single linear interval, and for a filter
animation no drop-shadow and matching op lists. CONFIRMED.

$$\operatorname{ca}(a) \iff a.\mathrm{rateOne} \land a.\mathrm{forwards} \land a.\mathrm{positiveDuration} \land 2 \le a.\mathrm{keyframes} \land a.\mathrm{easing} \ne \mathrm{steps} \land (a.\mathrm{easing} = \mathrm{cubicYOut} \Rightarrow a.\mathrm{singleLinearInterval}) \land \big((\exists q \in a.\mathrm{props}:\ \operatorname{isFilter}(q)) \Rightarrow \lnot a.\mathrm{dropShadow} \land a.\mathrm{filterOpsMatch}\big)$$
-/
def caAccepts (a : WkAnim) : Bool :=
  a.rateOne && a.forwards && a.positiveDuration && decide (2 ≤ a.keyframes) && decide (a.easing ≠ .steps) &&
    (decide (a.easing ≠ .cubicYOut) || a.singleLinearInterval) &&
    (!a.props.any isFilter || (!a.dropShadow && a.filterOpsMatch))

/-- **The thread rule** (design note §1.3): an animation runs in the UI process iff every animated property is
accelerated on its path (a Some-state effect ticks on main, `KeyframeEffect.cpp:1737-1769, 2724-2744`; INFERRED for the
split, open item O3), `canBeAccelerated` holds, and on the legacy path Core Animation accepts it.

$$\operatorname{wkThread}(m, a) = \begin{cases} \mathrm{comp} & \big(\forall q \in a.\mathrm{props}:\ \operatorname{accel}(\operatorname{path}(m, a), q)\big) \land \operatorname{cba}(m, a) \land \big(\operatorname{path}(m, a) = \mathrm{threaded} \lor \operatorname{ca}(a)\big) \\ \mathrm{main} & \text{otherwise} \end{cases}$$
-/
def wkThread (m : WkMode) (a : WkAnim) : Thread :=
  if a.props.all (accelerated (pathOf m a)) && canBeAccelerated m a && (decide (pathOf m a = .threaded) || caAccepts a)
  then .comp else .main

/-- An animation with no disqualifier: the given properties and timeline, a cubic easing in [0, 1], rate 1,
forwards, positive duration, 2 keyframes, composite replace, not pending, an async-scrollable source, no drop-shadow,
matching filter ops, no blockers.

$$\operatorname{clean}(P, \tau) = (P, \tau, \mathrm{cubic}, \mathrm{true}, \mathrm{true}, \mathrm{true}, 2, \mathrm{false}, \mathrm{true}, \mathrm{false}, \mathrm{true}, \mathrm{false}, \mathrm{true}, [\,])$$
-/
def WkAnim.clean (ps : List CssProp) (τ : Timeline) : WkAnim :=
  ⟨ps, τ, .cubic, true, true, true, 2, false, true, false, true, false, true, []⟩

/-- **Scroll-driven animations take the threaded path by default; time-based ones the legacy path.**

$$\forall a \in \mathrm{WkAnim}:\ \big(a.\mathrm{timeline} = \mathrm{scroll} \Rightarrow \operatorname{path}(\mathrm{safari}, a) = \mathrm{threaded}\big) \land \big(a.\mathrm{timeline} = \mathrm{time} \Rightarrow \operatorname{path}(\mathrm{safari}, a) = \mathrm{legacy}\big)$$
-/
theorem path_default (a : WkAnim) : (a.timeline = .scroll → pathOf .safari a = .threaded) ∧
    (a.timeline = .time → pathOf .safari a = .legacy) := by
  constructor <;> intro h <;> simp [pathOf, h, WkMode.safari]

/-- **The legacy path rejects** `steps()`, `linear()` with points, a playback rate other than 1, and a cubic with y
outside [0, 1] over more than a single linear interval.

$$\forall m, \forall a:\ \operatorname{path}(m, a) = \mathrm{legacy} \land \big(a.\mathrm{easing} \in \{\mathrm{steps}, \mathrm{linearPoints}\} \lor \lnot a.\mathrm{rateOne} \lor (a.\mathrm{easing} = \mathrm{cubicYOut} \land \lnot a.\mathrm{singleLinearInterval})\big) \Rightarrow \operatorname{wkThread}(m, a) = \mathrm{main}$$
-/
theorem legacy_rejects (m : WkMode) (a : WkAnim) (hp : pathOf m a = .legacy)
    (h : a.easing = .steps ∨ a.easing = .linearPoints ∨ a.rateOne = false ∨
      (a.easing = .cubicYOut ∧ a.singleLinearInterval = false)) : wkThread m a = .main := by
  rcases h with h | h | h | ⟨h1, h2⟩
  · simp [wkThread, canBeAccelerated, hp, h]
  · simp [wkThread, canBeAccelerated, hp, h]
  · simp [wkThread, caAccepts, hp, h]
  · simp [wkThread, caAccepts, hp, h1, h2]

/-- **Custom properties never run in the UI process.**

$$\forall m, \forall a:\ \mathrm{custom} \in a.\mathrm{props} \Rightarrow \operatorname{wkThread}(m, a) = \mathrm{main}$$
-/
theorem custom_main (m : WkMode) (a : WkAnim) (h : CssProp.custom ∈ a.props) : wkThread m a = .main := by
  have : a.props.all (accelerated (pathOf m a)) = false := by
    rw [List.all_eq_false]; exact ⟨_, h, by cases pathOf m a <;> decide⟩
  simp [wkThread, this]

/-- A UI-process animation animates accelerated properties only.

$$\forall m, \forall a:\ \operatorname{wkThread}(m, a) = \mathrm{comp} \Rightarrow \forall q \in a.\mathrm{props}:\ \operatorname{accel}(\operatorname{path}(m, a), q) = \mathrm{true}$$
-/
theorem comp_accelerated (m : WkMode) (a : WkAnim) (h : wkThread m a = .comp) :
    ∀ q ∈ a.props, accelerated (pathOf m a) q = true := by
  unfold wkThread at h
  split at h
  · rename_i hc
    simp only [Bool.and_eq_true, List.all_eq_true] at hc
    exact hc.1.1
  · cases h

-- the thread rule
#guard wkThread .safari (.clean [.transform, .opacity] .scroll) == .comp
#guard wkThread .safari (.clean [.opacity] .time) == .comp
#guard wkThread .safari (.clean [.offset] .time) == .main && wkThread .safari (.clean [.offset] .scroll) == .comp
#guard wkThread .safari (.clean [.transform, .clipPath] .time) == .main
#guard wkThread .safari (.clean [.custom] .scroll) == .main
#guard wkThread .safari { WkAnim.clean [.transform] .time with easing := .steps } == .main
#guard wkThread .safari { WkAnim.clean [.transform] .time with easing := .linearPoints } == .main
#guard wkThread .safari { WkAnim.clean [.transform] .time with rateOne := false } == .main
#guard wkThread .safari { WkAnim.clean [.transform] .time with easing := .cubicYOut } == .main
#guard wkThread .safari { WkAnim.clean [.transform] .time with easing := .cubicYOut, singleLinearInterval := true } == .comp
#guard wkThread .safari { WkAnim.clean [.transform] .scroll with easing := .steps } == .comp
#guard wkThread .safari { WkAnim.clean [.transform] .scroll with scrollerAsync := false } == .main
#guard wkThread .safari { WkAnim.clean [.filter] .time with dropShadow := true } == .main
#guard wkThread .safari { WkAnim.clean [.opacity] .time with blockers := [.overridden] } == .main
#guard wkThread ⟨false, false, .normal⟩ (.clean [.transform] .scroll) == .main
#guard wkThread ⟨true, true, .normal⟩ { WkAnim.clean [.transform] .time with rateOne := false } == .comp

/-! ## Frames of animations -/

/-- A frame with only `n` running compositor animations: no script, no forced pass, no hit test, no change.

$$\operatorname{compFrame}(n) = (0, 0, 0, 0, [\,], n)$$
-/
def compFrame (n : Nat) : FrameIn WkProp := ⟨0, 0, 0, 0, [], n⟩

/-- The per-frame input of one running animation: one compositor animation when it runs in the UI process, else its
main-thread changes `cs` (a CSS animation tick runs no script).

$$\operatorname{animFrame}(m, a, \mathit{cs}) = \begin{cases} \operatorname{compFrame}(1) & \operatorname{wkThread}(m, a) = \mathrm{comp} \\ (0, 0, 0, 0, \mathit{cs}, 0) & \text{otherwise} \end{cases}$$
-/
def animFrame (m : WkMode) (a : WkAnim) (cs : List (Change WkProp)) : FrameIn WkProp :=
  if wkThread m a = .comp then compFrame 1 else ⟨0, 0, 0, 0, cs, 0⟩

/-- **A compositor animation costs no web-process pass or unit**: no pass and no unit on any stage but `comp`.

$$\forall m, \forall n \in \mathbb{N}, \forall s \ne \mathrm{comp}:\ \operatorname{frameWork}_{\operatorname{webkitAt}(m)}(\operatorname{compFrame}(n)).\mathrm{passes}(s) = 0 \land \operatorname{frameWork}_{\operatorname{webkitAt}(m)}(\operatorname{compFrame}(n)).\mathrm{units}(s) = 0$$
-/
theorem compFrame_zero (m : WkMode) (n : Nat) (s : Stage) (hs : s ≠ .comp) :
    (frameWork (webkitAt m) (compFrame n)).passes s = 0 ∧ (frameWork (webkitAt m) (compFrame n)).units s = 0 := by
  cases s <;> first
    | exact absurd rfl hs
    | (constructor <;>
        simp [frameWork, touched, stageUnits, forcedPasses, compFrame, webkitAt, FrameIn.updates] <;>
        by_cases hn : 0 < n <;> simp [hn])

/-- A UI-process animation's frame has no pass and no unit on any stage but `comp` (`KeyframeEffect.cpp:2724-2744`: a completely
accelerated running effect does not tick; `DocumentTimeline.cpp:156-168`: no per-frame resolution).

$$\forall m, a, \mathit{cs}:\ \operatorname{wkThread}(m, a) = \mathrm{comp} \Rightarrow \forall s \ne \mathrm{comp}:\ \operatorname{frameWork}_{\operatorname{webkitAt}(m)}(\operatorname{animFrame}(m, a, \mathit{cs})).\mathrm{passes}(s) = 0 \land \operatorname{frameWork}_{\operatorname{webkitAt}(m)}(\operatorname{animFrame}(m, a, \mathit{cs})).\mathrm{units}(s) = 0$$
-/
theorem anim_comp_zero (m : WkMode) (a : WkAnim) (cs : List (Change WkProp)) (h : wkThread m a = .comp)
    (s : Stage) (hs : s ≠ .comp) :
    (frameWork (webkitAt m) (animFrame m a cs)).passes s = 0 ∧
      (frameWork (webkitAt m) (animFrame m a cs)).units s = 0 := by
  simp only [animFrame, h, ↓reduceIte]
  exact compFrame_zero m 1 s hs

/-! ## Worked theorems -/

/-- A JS frame: one script callback and the given changes.

$$\operatorname{js}(\mathit{cs}) = (1, 0, 0, 0, \mathit{cs}, 0)$$
-/
def jsFrame (cs : List (Change WkProp)) : FrameIn WkProp := ⟨1, 0, 0, 0, cs, 0⟩

/-- **Repaint → recomposite accepted when the original already pays `props`.** Per scroll step, the original's
handler repaints a background on box 1 (layer) and resizes box 2 (Layout, which pays `props`); the variant moves box 1
by a transform on its composited layer (recomposite) and box 2 by `top` on an absolute box. Box 1 now pays a `props`
unit and no paint; the original's Layout on box 2 already paid one `props` unit, so the union check holds.

$$\operatorname{frameWork}_{\mathrm{webkit}}\big(\operatorname{scrollStep}(\operatorname{js}[(1, \mathrm{transform}, \mathrm{own}), (2, \mathrm{insetAbs}, \mathrm{none})])\big) \preceq \operatorname{frameWork}_{\mathrm{webkit}}\big(\operatorname{scrollStep}(\operatorname{js}[(1, \mathrm{background}, \mathrm{layer}), (2, \mathrm{size}, \mathrm{none})])\big)$$
-/
theorem trade_accepted :
    (frameWork webkit (scrollStep (jsFrame [⟨1, .transform, .own⟩, ⟨2, .insetAbs, .none⟩]))).le
      (frameWork webkit (scrollStep (jsFrame [⟨1, .background, .layer⟩, ⟨2, .size, .none⟩]))) :=
  frame_le_union webkit (by decide)

-- the bare trade is not accepted: the original pays no `props`, the variant does (C-2).
#guard !unionLe webkit (scrollStep (jsFrame [⟨1, .transform, .own⟩])) (scrollStep (jsFrame [⟨1, .background, .layer⟩]))
#guard unionLe webkit (scrollStep (jsFrame [⟨1, .transform, .own⟩, ⟨2, .insetAbs, .none⟩]))
  (scrollStep (jsFrame [⟨1, .background, .layer⟩, ⟨2, .size, .none⟩]))

/-- The blur filter animation: a time-based `filter` animation (blur, no drop-shadow) with no disqualifier.

$$\mathrm{blurAnim} = \operatorname{clean}([\mathrm{filter}], \mathrm{time})$$
-/
def blurAnim : WkAnim := .clean [.filter] .time

/-- **The blur filter animation is comp on WebKit**, in every mode: on the threaded path, and on the legacy path
(the clean animation passes every `caAccepts` clause; for a filter animation the legacy gate additionally rejects
only drop-shadow and mismatched op lists, `GraphicsLayerCA.cpp:3946-3958`). Chromium contrasts: bit 12
(blur or drop-shadow in `filter`, `compositor_animations.cc:405-417`@f842f52) keeps it on main (design note §1.4).

$$\forall m \in \mathrm{WkMode}:\ \operatorname{wkThread}(m, \mathrm{blurAnim}) = \mathrm{comp}$$
-/
theorem blur_comp (m : WkMode) : wkThread m blurAnim = .comp := by
  obtain ⟨tsd, ttb, p⟩ := m
  cases tsd <;> cases ttb <;> cases p <;> decide

/-- **A blur animation costs no pass and no unit per frame on any stage but `comp`**, whatever main-thread changes it would otherwise make.

$$\forall m, \mathit{cs}, \forall s \ne \mathrm{comp}:\ \operatorname{frameWork}_{\operatorname{webkitAt}(m)}(\operatorname{animFrame}(m, \mathrm{blurAnim}, \mathit{cs})).\mathrm{passes}(s) = 0 \land \operatorname{frameWork}_{\operatorname{webkitAt}(m)}(\operatorname{animFrame}(m, \mathrm{blurAnim}, \mathit{cs})).\mathrm{units}(s) = 0$$
-/
theorem blur_zero (m : WkMode) (cs : List (Change WkProp)) (s : Stage) (hs : s ≠ .comp) :
    (frameWork (webkitAt m) (animFrame m blurAnim cs)).passes s = 0 ∧
      (frameWork (webkitAt m) (animFrame m blurAnim cs)).units s = 0 :=
  anim_comp_zero m blurAnim cs (blur_comp m) s hs

/-! ## Engine mechanisms (why-engines)

Each section below closes one ledger statement (`research/findings/ledger.json`, `missingWhy` of
`Fw.Engine.WebKit`) with the mechanism read from WebKit source @862f17d (`WC/` = `Source/WebCore/`, `WK/` =
`Source/WebKit/`). The tables above stay unchanged (the golden rows and `Fw.Parts` read them); a corrected rule is a
new definition with a bridge theorem back to the old one. -/

/-! ### The extended property type and engine -/

/-- **WebKit properties with the why-engines rows.** `base p` is a row of the table above; `restyle` is a style
invalidation with an equal difference (an animation tick on a target, a descendant reached by an inherited change);
`customInherited` is a write of an inherited custom property; `pointerEvents` a `pointer-events` write; `svgResourceAttr`
a geometry attribute (`x1`, `x2`, `y1`, `y2`) of an SVG gradient.

$$\mathrm{WkPropX} = \{\mathrm{base}(p) \mid p \in \mathrm{WkProp}\} \cup \{\mathrm{restyle}, \mathrm{customInherited}, \mathrm{pointerEvents}, \mathrm{svgResourceAttr}\}$$

The WebKit property type extended by the rows this section proves. -/
inductive WkPropX where
  | base (p : WkProp)
  | restyle
  | customInherited
  | pointerEvents
  | svgResourceAttr
deriving Repr, DecidableEq

/-- **Stages of the extended rows.**
* `restyle`: the element is resolved again (`Element::invalidateStyleForAnimation` from
  `KeyframeEffect::invalidate`, `WC/animation/KeyframeEffect.cpp:127-135, 1731-1735`); no stage beyond style is
  claimed. CONFIRMED for style, the absence of more stages INFERRED (lower bound).
* `customInherited`: custom properties live in the inherited rare data
  (`WC/style/computed/data/StyleInheritedRareData.h:153`), so a change is `Change::Inherited`
  (`WC/style/StyleChange.cpp:42-43`) and the element's children are resolved (`WC/style/StyleTreeResolver.cpp:283-311,
  1185-1212`). Style only for the writer; readers that change other properties are separate changes. CONFIRMED.
* `pointerEvents`: `RecompositeLayer` (`WC/style/StyleDifference.cpp:921-922`), so a compositing update where the
  event region is rebuilt (`WC/rendering/RenderLayerBacking.cpp:2223-2279`). CONFIRMED.
* `svgResourceAttr`: `SVGGradientElement::invalidateGradientResource` calls `updateSVGRendererForElementChange`
  (`WC/svg/SVGLinearGradientElement.cpp:94-104`, `WC/svg/SVGGradientElement.cpp:83-92`, `WC/svg/SVGElement.cpp:1052-1056`),
  which queues a render-tree update and so a style resolution (`WC/dom/Document.cpp:2968-2990`); the updater marks the
  renderer for layout (`WC/rendering/updating/RenderTreeUpdater.cpp:399-414`; legacy SVG
  `markForLayoutAndParentResourceInvalidation`, `WC/rendering/svg/legacy/LegacyRenderSVGResource.cpp:157-215`), and
  layout repaints. CONFIRMED for both SVG engines.

$$\operatorname{stagesOf}^{X}_{\mathrm{wk}}(e, x, \ell) = \begin{cases} \operatorname{diffStages}(\operatorname{wkDiff}(e, p, \ell)) & x = \mathrm{base}(p) \\ [\mathrm{style}] & x \in \{\mathrm{restyle}, \mathrm{customInherited}\} \\ [\mathrm{style}, \mathrm{props}] & x = \mathrm{pointerEvents} \\ [\mathrm{style}, \mathrm{layout}, \mathrm{paint}] & x = \mathrm{svgResourceAttr} \end{cases}$$

The stages each extended WebKit change dirties. -/
def wkStagesOfX (c : Change WkPropX) : List Stage :=
  match c.prop with
  | .base p => diffStages (wkDiff ⟨c.elem, p, c.layer⟩)
  | .restyle | .customInherited => [.style]
  | .pointerEvents => [.style, .props]
  | .svgResourceAttr => [.style, .layout, .paint]

/-- **The extended WebKit engine in mode `m`**: `webkitAt m` with the extended rows.

$$\operatorname{webkitX}(m) = \big(m,\ \operatorname{stagesOf}^{X}_{\mathrm{wk}},\ [\mathrm{comp}],\ [\mathrm{commit}]\big)$$

The WebKit engine over the extended property type. -/
def webkitX (m : WkMode) : Engine WkPropX WkMode where
  mode := m
  stagesOf := wkStagesOfX
  compStages := [.comp]
  base := [.commit]

/-- A table change as an extended change.

$$\operatorname{lift}(e, p, \ell) = (e, \mathrm{base}(p), \ell)$$

Wraps an old WebKit change in the extended type. -/
def liftWk (c : Change WkProp) : Change WkPropX := ⟨c.elem, .base c.prop, c.layer⟩

/-- A frame of table changes as an extended frame.

$$\operatorname{liftF}(f) = f[\mathrm{changes} := [\,\operatorname{lift}(c) \mid c \in f.\mathrm{changes}\,]]$$

Wraps every change of an old WebKit frame. -/
def liftWkFrame (f : FrameIn WkProp) : FrameIn WkPropX :=
  ⟨f.script, f.forcedStyle, f.forcedLayout, f.hits, f.changes.map liftWk, f.compAnims⟩

/-- **The extension keeps the old table.** A lifted frame has the same passes, units and hit tests under the
extended engine.

$$\forall m \in \mathrm{WkMode},\ \forall f \in \mathrm{FrameIn}(\mathrm{WkProp}),\ \forall s \in \mathrm{Stage}:\ W^{X}.\mathrm{passes}(s) = W.\mathrm{passes}(s) \land W^{X}.\mathrm{units}(s) = W.\mathrm{units}(s) \land W^{X}.\mathrm{hits} = W.\mathrm{hits}$$
$$\text{where } W^{X} = \operatorname{frameWork}_{\operatorname{webkitX}(m)}(\operatorname{liftF}(f)),\ W = \operatorname{frameWork}_{\operatorname{webkitAt}(m)}(f)$$

Every theorem about the old WebKit rows carries over to the extended engine. -/
theorem webkitX_lift (m : WkMode) (f : FrameIn WkProp) (s : Stage) :
    (frameWork (webkitX m) (liftWkFrame f)).passes s = (frameWork (webkitAt m) f).passes s ∧
      (frameWork (webkitX m) (liftWkFrame f)).units s = (frameWork (webkitAt m) f).units s ∧
      (frameWork (webkitX m) (liftWkFrame f)).hits = (frameWork (webkitAt m) f).hits := by
  have hs : ∀ c : Change WkProp, wkStagesOfX (liftWk c) = (webkitAt m).stagesOf c := fun _ => rfl
  have hfm : (f.changes.map liftWk).flatMap wkStagesOfX = f.changes.flatMap (webkitAt m).stagesOf := by
    induction f.changes with
    | nil => rfl
    | cons c cs ih => simp only [List.map_cons, List.flatMap_cons, hs, ih]
  have hcount : (f.changes.map liftWk).countP (fun c => decide (s ∈ wkStagesOfX c)) =
      f.changes.countP (fun c => decide (s ∈ (webkitAt m).stagesOf c)) := by
    induction f.changes with
    | nil => rfl
    | cons c cs ih => simp only [List.map_cons, List.countP_cons, hs, ih]
  refine ⟨?_, ?_, rfl⟩
  · simp only [frameWork, touched, liftWkFrame, FrameIn.updates, forcedPasses, List.isEmpty_map]
    rw [show (webkitX m).stagesOf = wkStagesOfX from rfl, hfm]
    rfl
  · simp only [frameWork, stageUnits, liftWkFrame]
    rw [show (webkitX m).stagesOf = wkStagesOfX from rfl, hcount]
    rfl

#guard wkStagesOfX ⟨1, .svgResourceAttr, .none⟩ == [.style, .layout, .paint]
#guard wkStagesOfX ⟨1, .pointerEvents, .own⟩ == [.style, .props]
#guard wkStagesOfX ⟨1, .base .transform, .own⟩ == [.style, .props]
#guard wkStagesOfX ⟨1, .restyle, .own⟩ == [.style] && wkStagesOfX ⟨1, .customInherited, .none⟩ == [.style]

/-! ### Accelerated animations still tick (ledger n=8 and n=10) -/

/-- **Does an accelerated animation tick in this update?** Each rendering update asks every timeline
(`AnimationTimelinesController::updateAnimationsAndSendEvents`, `WC/animation/AnimationTimelinesController.cpp:138-178`);
a timeline that answers yes ticks every relevant animation, and `WebAnimation::tick` calls
`KeyframeEffect::animationDidTick` (`WC/animation/WebAnimation.cpp:1558-1582`), which invalidates the target's style
(`KeyframeEffect.cpp:2129-2132, 1731-1735, 127-135`), accelerated or not. A scroll timeline answers yes in every
update while its source is connected (`WC/animation/ScrollTimeline.cpp:291-298`); the document timeline only when an
update was scheduled for it (`WC/animation/DocumentTimeline.cpp:190-205, 350-399`), and a completely accelerated
running effect does not schedule one (`KeyframeEffect.cpp:2724-2745`). `upd`: the frame is a rendering update;
`sched`: the document timeline has a scheduled update (e.g. another, main-thread animation on it). CONFIRMED.

$$\operatorname{ticks}(\tau, u, \sigma) \iff (\tau = \mathrm{scroll} \land u) \lor \sigma$$

An accelerated animation is ticked when its scroll timeline sees an update or its document timeline was scheduled. -/
def wkTicks (τ : Timeline) (upd sched : Bool) : Bool := (τ == .scroll && upd) || sched

/-- **A frame plus one running animation** on element `e` with layer state `ℓ`: a UI-process animation adds one
compositor animation and, when it ticks, one `restyle` of its target; a main-thread animation adds its changes `cs`.

$$\operatorname{withAnim}(m, a, e, \ell, \mathit{cs}, f, \sigma) = \begin{cases} f[\mathrm{changes} \mathrel{+\!\!+}= [(e, \mathrm{restyle}, \ell) \mid \operatorname{ticks}(a.\tau, \operatorname{updates}(f), \sigma)],\ \mathrm{compAnims} \mathrel{+}= 1] & \operatorname{wkThread}(m, a) = \mathrm{comp} \\ f[\mathrm{changes} \mathrel{+\!\!+}= \mathit{cs}] & \text{otherwise} \end{cases}$$

The frame after adding an animation, with the style ride-along of an accelerated one. -/
def withAnim (m : WkMode) (a : WkAnim) (e : Nat) (ℓ : LayerState) (cs : List (Change WkPropX))
    (f : FrameIn WkPropX) (sched : Bool) : FrameIn WkPropX :=
  if wkThread m a = .comp then
    ⟨f.script, f.forcedStyle, f.forcedLayout, f.hits,
      f.changes ++ (if wkTicks a.timeline f.updates sched then [⟨e, .restyle, ℓ⟩] else []), f.compAnims + 1⟩
  else ⟨f.script, f.forcedStyle, f.forcedLayout, f.hits, f.changes ++ cs, f.compAnims⟩

/-- **A time-based accelerated animation rides along only when its timeline was scheduled** (refutes ledger n=8 as
stated: a rendering update alone does not tick it).

$$\forall m, a, e, \ell, \mathit{cs}, f:\ \operatorname{wkThread}(m, a) = \mathrm{comp} \land a.\tau = \mathrm{time} \Rightarrow \operatorname{withAnim}(m, a, e, \ell, \mathit{cs}, f, \mathrm{false}).\mathrm{changes} = f.\mathrm{changes}$$

An unscheduled document timeline adds no style work for a UI-process animation, even in an updating frame. -/
theorem time_comp_no_ride (m : WkMode) (a : WkAnim) (e : Nat) (ℓ : LayerState) (cs : List (Change WkPropX))
    (f : FrameIn WkPropX) (hc : wkThread m a = .comp) (ht : a.timeline = .time) :
    (withAnim m a e ℓ cs f false).changes = f.changes := by
  simp [withAnim, hc, wkTicks, ht]

/-- **When the ride-along happens.** A UI-process animation adds a change to the frame iff it ticks.

$$\forall m, a, e, \ell, \mathit{cs}, f, \sigma:\ \operatorname{wkThread}(m, a) = \mathrm{comp} \Rightarrow \big(|\operatorname{withAnim}(m, a, e, \ell, \mathit{cs}, f, \sigma).\mathrm{changes}| = |f.\mathrm{changes}| + 1 \iff \operatorname{ticks}(a.\tau, \operatorname{updates}(f), \sigma)\big)$$

An accelerated animation costs main-thread style exactly in the updates where its timeline ticks it. -/
theorem ride_iff (m : WkMode) (a : WkAnim) (e : Nat) (ℓ : LayerState) (cs : List (Change WkPropX))
    (f : FrameIn WkPropX) (sched : Bool) (hc : wkThread m a = .comp) :
    (withAnim m a e ℓ cs f sched).changes.length = f.changes.length + 1 ↔
      wkTicks a.timeline f.updates sched = true := by
  simp only [withAnim, hc, ↓reduceIte, List.length_append]
  cases wkTicks a.timeline f.updates sched <;> simp

/-- **A scroll-driven accelerated animation restyles its target in every updating frame** (ledger n=10: the style
floor of the compositor morph). It adds a style pass and exactly one style unit.

$$\forall m, a, e, \ell, \mathit{cs}, f, \sigma:\ \operatorname{wkThread}(m, a) = \mathrm{comp} \land a.\tau = \mathrm{scroll} \land \operatorname{updates}(f) \Rightarrow \mathrm{style} \in \operatorname{touched}_{\operatorname{webkitX}(m)}(g) \land \operatorname{units}(g, \mathrm{style}) = \operatorname{units}(f, \mathrm{style}) + 1$$
$$\text{where } g = \operatorname{withAnim}(m, a, e, \ell, \mathit{cs}, f, \sigma),\ \operatorname{units} = \operatorname{units}_{\operatorname{webkitX}(m)}$$

On a scroll timeline the threaded path still costs one restyle per scroll update. -/
theorem scroll_comp_ride (m : WkMode) (a : WkAnim) (e : Nat) (ℓ : LayerState) (cs : List (Change WkPropX))
    (f : FrameIn WkPropX) (sched : Bool) (hc : wkThread m a = .comp) (hs : a.timeline = .scroll)
    (hu : f.updates = true) :
    Stage.style ∈ touched (webkitX m) (withAnim m a e ℓ cs f sched) ∧
      stageUnits (webkitX m) (withAnim m a e ℓ cs f sched) .style = stageUnits (webkitX m) f .style + 1 := by
  have ht : wkTicks a.timeline f.updates sched = true := by simp [wkTicks, hs, hu]
  constructor
  · simp [withAnim, hc, ht, touched, webkitX, wkStagesOfX]
  · simp [withAnim, hc, ht, stageUnits, webkitX, wkStagesOfX, List.countP_append]

/-- The empty extended frame: nothing runs.

$$\varnothing = (0, 0, 0, 0, [\,], 0)$$

A frame with no script, no change and no animation. -/
def emptyX : FrameIn WkPropX := ⟨0, 0, 0, 0, [], 0⟩

/-- **Consistency with `anim_comp_zero`.** Alone in a frame with no rendering update and no scheduled timeline, a
UI-process animation costs nothing but `comp`.

$$\forall m, a, e, \ell, \mathit{cs}:\ \operatorname{wkThread}(m, a) = \mathrm{comp} \Rightarrow \forall s \ne \mathrm{comp}:\ W.\mathrm{passes}(s) = 0 \land W.\mathrm{units}(s) = 0\quad\text{where } W = \operatorname{frameWork}_{\operatorname{webkitX}(m)}(\operatorname{withAnim}(m, a, e, \ell, \mathit{cs}, \varnothing, \mathrm{false}))$$

The old zero-cost theorem is the case where nothing else updates. -/
theorem withAnim_idle_zero (m : WkMode) (a : WkAnim) (e : Nat) (ℓ : LayerState) (cs : List (Change WkPropX))
    (hc : wkThread m a = .comp) (s : Stage) (hs : s ≠ .comp) :
    (frameWork (webkitX m) (withAnim m a e ℓ cs emptyX false)).passes s = 0 ∧
      (frameWork (webkitX m) (withAnim m a e ℓ cs emptyX false)).units s = 0 := by
  cases s <;> first
    | exact absurd rfl hs
    | (constructor <;>
        simp [withAnim, hc, wkTicks, emptyX, FrameIn.updates, frameWork, touched, stageUnits, forcedPasses, webkitX])

#guard wkTicks .scroll true false && !wkTicks .scroll false false && !wkTicks .time true false && wkTicks .time true true

/-- A delivered scroll position in an extended frame (as `scrollStep`).

$$\operatorname{scrollStep}^{X}(f) = f \text{ with } \mathrm{changes} := (0, \mathrm{base}(\mathrm{scrollPos}), \mathrm{none}) :: f.\mathrm{changes}$$
-/
def scrollStepX (f : FrameIn WkPropX) : FrameIn WkPropX :=
  { f with changes := ⟨0, .base .scrollPos, .none⟩ :: f.changes }

/-- **The lift commutes with a scroll step.**

$$\forall f \in \mathrm{FrameIn}(\mathrm{WkProp}):\ \operatorname{liftF}(\operatorname{scrollStep}(f)) = \operatorname{scrollStep}^{X}(\operatorname{liftF}(f))$$
-/
theorem lift_scrollStep (f : FrameIn WkProp) : liftWkFrame (scrollStep f) = scrollStepX (liftWkFrame f) := rfl

/-! ### The WKTR fixtures: style recalcs per rendering update (task wktr-p1p4)

Premise (empirical, tested on CI by `packages/measure-wktr/fixtures`, WebKitTestRunner of the iOS 26.5 Simulator,
`internals.styleRecalcCount()` per rendering update; MEASURED over three independent macOS jobs): a page that only
scrolls costs `0` style recalcs per update; the same page with a `transform` animation on `animation-timeline:
scroll(root)` costs exactly `1`; with the same animation on the document timeline (`4s linear infinite alternate`)
`0`. The goldens P1 and P4 had claimed `0` for the scroll-driven arm. -/

/-- The measured style recalcs per rendering update of the three fixture pages.

$$\mu = (\mu_{\mathrm{control}}, \mu_{\mathrm{timeline}}, \mu_{\mathrm{timeAccel}}) \in \mathbb{N}^3$$
-/
structure WktrStyleRate where
  control   : Nat
  timeline  : Nat
  timeAccel : Nat

/-- **The premise** `prem.wktr_scroll_timeline_restyle`: what the fixtures measured.

$$\operatorname{Holds}(\mu) \iff \mu_{\mathrm{control}} = 0 \ \land\ \mu_{\mathrm{timeline}} = 1 \ \land\ \mu_{\mathrm{timeAccel}} = 0$$
-/
def WktrStyleRate.Holds (μ : WktrStyleRate) : Prop := μ.control = 0 ∧ μ.timeline = 1 ∧ μ.timeAccel = 0

/-- The scroll-only frame (the control page): one delivered scroll position, nothing animated.

$$\mathrm{ctl} = \operatorname{scrollStep}^{X}(\varnothing)$$
-/
def ctlFrame : FrameIn WkPropX := scrollStepX emptyX

/-- The scroll-timeline page: a UI-process `transform` animation on the scroll timeline, in the scroll update.

$$\mathrm{tl} = \operatorname{withAnim}(\mathrm{safari}, \mathrm{clean}([\mathrm{transform}], \mathrm{scroll}), 1, \mathrm{layer}, [\,], \mathrm{ctl}, \mathrm{false})$$
-/
def tlFrame : FrameIn WkPropX :=
  withAnim WkMode.safari (.clean [.transform] .scroll) 1 .layer [] ctlFrame false

/-- The time-accelerated page: the same animation on the document timeline, in the scroll update.

$$\mathrm{ta} = \operatorname{withAnim}(\mathrm{safari}, \mathrm{clean}([\mathrm{transform}], \mathrm{time}), 1, \mathrm{layer}, [\,], \mathrm{ctl}, \mathrm{false})$$
-/
def taFrame : FrameIn WkPropX :=
  withAnim WkMode.safari (.clean [.transform] .time) 1 .layer [] ctlFrame false

/-- **The corrected model agrees with the measurement.** Under the premise, the style passes per update of the three
frames equal the measured recalcs per update.

$$\forall \mu:\ \operatorname{Holds}(\mu) \Rightarrow W(\mathrm{ctl}).\mathrm{passes}(\mathrm{style}) = \mu_{\mathrm{control}} \land W(\mathrm{tl}).\mathrm{passes}(\mathrm{style}) = \mu_{\mathrm{timeline}} \land W(\mathrm{ta}).\mathrm{passes}(\mathrm{style}) = \mu_{\mathrm{timeAccel}}$$
$$\text{where } W = \operatorname{frameWork}_{\operatorname{webkitX}(\mathrm{safari})}$$

Scroll alone restyles nothing, a scroll-driven accelerated animation restyles once per update, a document-timeline one never. -/
theorem style_rate_model (μ : WktrStyleRate) (h : μ.Holds) :
    (frameWork (webkitX WkMode.safari) ctlFrame).passes .style = μ.control ∧
    (frameWork (webkitX WkMode.safari) tlFrame).passes .style = μ.timeline ∧
    (frameWork (webkitX WkMode.safari) taFrame).passes .style = μ.timeAccel := by
  obtain ⟨h0, h1, h2⟩ := h
  rw [h0, h1, h2]
  decide

/-- **The earlier golden is refuted by the measurement.** The old scroll-driven arm (`animFrame`: a bare compositor
animation, no ride-along) predicts `0` style passes; the premise says `1`.

$$\forall \mu:\ \operatorname{Holds}(\mu) \Rightarrow \operatorname{frameWork}_{\operatorname{webkitAt}(\mathrm{safari})}(\operatorname{animFrame}(\mathrm{safari}, \mathrm{clean}([\mathrm{transform}], \mathrm{scroll}), [\,])).\mathrm{passes}(\mathrm{style}) \ne \mu_{\mathrm{timeline}}$$
-/
theorem style_rate_old_refuted (μ : WktrStyleRate) (h : μ.Holds) :
    (frameWork (webkitAt WkMode.safari) (animFrame WkMode.safari (.clean [.transform] .scroll) [])).passes .style ≠
      μ.timeline := by
  obtain ⟨_, h1, _⟩ := h
  rw [h1]
  decide

/-! ## Golden rows: predictions P1-P5 (WebKit note §5.3) -/

/-- A predicted relation of one stage's count: `=0` none, `>0` some (original arm, against no work), `=o` equal to
the original, `<o` at most the original and below it somewhere, `>o` at least the original and above it somewhere,
`any` incomparable.

$$\mathrm{Pred} = \{\mathrm{zero}, \mathrm{pos}, \mathrm{eqO}, \mathrm{ltO}, \mathrm{gtO}, \mathrm{any}\}$$
-/
inductive Pred where
  | zero | pos | eqO | ltO | gtO | any
deriving Repr, DecidableEq, Inhabited

/-- The wire string of a prediction.

$$\operatorname{str}(\mathrm{zero}, \mathrm{pos}, \mathrm{eqO}, \mathrm{ltO}, \mathrm{gtO}, \mathrm{any}) = (\texttt{=0}, \texttt{>0}, \texttt{=o}, \texttt{<o}, \texttt{>o}, \texttt{any})$$
-/
def Pred.str : Pred → String
  | .zero => "=0" | .pos => ">0" | .eqO => "=o" | .ltO => "<o" | .gtO => ">o" | .any => "any"

/-- The prediction for the original arm's stage `s`: `=0` when it has no pass and no unit, else `>0`.

$$\operatorname{predO}(o, s) = \begin{cases} \mathrm{zero} & o.\mathrm{passes}(s) = 0 \land o.\mathrm{units}(s) = 0 \\ \mathrm{pos} & \text{otherwise} \end{cases}$$
-/
def predictOrig (o : Work) (s : Stage) : Pred :=
  if o.passes s = 0 ∧ o.units s = 0 then .zero else .pos

/-- The prediction for a variant's stage `s` against the original, first match: zero, equal, below, above, else any.

$$\operatorname{predV}(v, o, s) = \begin{cases} \mathrm{zero} & v.\mathrm{passes}(s) = 0 \land v.\mathrm{units}(s) = 0 \\ \mathrm{eqO} & \text{else if } v.\mathrm{passes}(s) = o.\mathrm{passes}(s) \land v.\mathrm{units}(s) = o.\mathrm{units}(s) \\ \mathrm{ltO} & \text{else if } v.\mathrm{passes}(s) \le o.\mathrm{passes}(s) \land v.\mathrm{units}(s) \le o.\mathrm{units}(s) \\ \mathrm{gtO} & \text{else if } o.\mathrm{passes}(s) \le v.\mathrm{passes}(s) \land o.\mathrm{units}(s) \le v.\mathrm{units}(s) \\ \mathrm{any} & \text{otherwise} \end{cases}$$
-/
def predictVar (v o : Work) (s : Stage) : Pred :=
  if v.passes s = 0 ∧ v.units s = 0 then .zero
  else if v.passes s = o.passes s ∧ v.units s = o.units s then .eqO
  else if v.passes s ≤ o.passes s ∧ v.units s ≤ o.units s then .ltO
  else if o.passes s ≤ v.passes s ∧ o.units s ≤ v.units s then .gtO
  else .any

/-- The lane that reads a scenario: the iOS Simulator Web Inspector timeline (`measure-webkit`) or WebKitTestRunner
`internals` counters (`measure-wktr`).

$$\mathrm{Lane} = \{\mathrm{sim}, \mathrm{wktr}\}$$
-/
inductive Lane where
  | sim | wktr
deriving Repr, DecidableEq, Inhabited

/-- The stages a lane counts, with the count type (design note §3.2): Simulator FireAnimationFrame, RecalculateStyles,
Layout, Paint, Composite; WKTR styleRecalcs, layoutUpdates, compositingUpdates, renderingUpdates.

$$\operatorname{counts}(\ell) = \begin{cases} [(\mathrm{script}, \texttt{FireAnimationFrame}), (\mathrm{style}, \texttt{RecalculateStyles}), (\mathrm{layout}, \texttt{Layout}), (\mathrm{paint}, \texttt{Paint}), (\mathrm{commit}, \texttt{Composite})] & \ell = \mathrm{sim} \\ [(\mathrm{style}, \texttt{styleRecalcs}), (\mathrm{layout}, \texttt{layoutUpdates}), (\mathrm{props}, \texttt{compositingUpdates}), (\mathrm{commit}, \texttt{renderingUpdates})] & \ell = \mathrm{wktr} \end{cases}$$
-/
def Lane.counts : Lane → List (Stage × String)
  | .sim => [(.script, "FireAnimationFrame"), (.style, "RecalculateStyles"), (.layout, "Layout"), (.paint, "Paint"),
      (.commit, "Composite")]
  | .wktr => [(.style, "styleRecalcs"), (.layout, "layoutUpdates"), (.props, "compositingUpdates"),
      (.commit, "renderingUpdates")]

/-- The wire name of a stage.

$$\operatorname{name}(s) = \text{the constructor name of } s,\ \text{e.g. } \operatorname{name}(\mathrm{props}) = \texttt{props}$$
-/
def stageName : Stage → String
  | .script => "script" | .style => "style" | .layout => "layout" | .props => "props" | .paint => "paint"
  | .raster => "raster" | .commit => "commit" | .comp => "comp"

/-- A prediction scenario: its id, lane, the original arm's frame and the named variant frames (one frame = one
scroll step or one animation frame).

$$\mathrm{Scenario} = \mathrm{String} \times \mathrm{Lane} \times \mathrm{FrameIn}(\mathrm{WkPropX}) \times (\mathrm{String} \times \mathrm{FrameIn}(\mathrm{WkPropX}))^{*}$$
-/
structure Scenario where
  id       : String
  lane     : Lane
  original : FrameIn WkPropX
  variants : List (String × FrameIn WkPropX)

/-- The six scenarios (P3 split in two) of WebKit note §5.3, in the default Safari mode (box 1 is the animated box):
- P1 (sim, per scroll step): a JS scroll handler writing a 2D transform on a non-composited layer vs a threaded
  scroll-driven transform animation;
- P2 (sim, idle frame): a permanent rAF loop that writes nothing vs a CSS time-based opacity animation;
- P3a / P3b (sim, per frame): a rAF writer of clip-path (composited box) / background-position vs the same as a CSS
  animation (never accelerated);
- P4 (wktr, per scroll step): a JS scroll handler repainting a background vs a threaded scroll-driven animation;
- P5 (wktr, per frame): a rAF writer of a 2D transform without a compositing reason vs the same with a 3D op.

$$\begin{aligned} \mathrm{scenarios} = [\ &(\texttt{P1}, \mathrm{sim}, L(\operatorname{scrollStep}(\operatorname{jsFrame}([(1, \mathrm{transform}, \mathrm{layer})]))), [(\texttt{scrollDriven}, \mathit{sd})]), \\ &(\texttt{P2}, \mathrm{sim}, L(\operatorname{jsFrame}([\,])), [(\texttt{cssTime}, \mathit{wa}(\operatorname{clean}([\mathrm{opacity}], \mathrm{time}), \mathrm{own}, [(1, \mathrm{opacity}, \mathrm{own})]))]), \\ &(\texttt{P3a}, \mathrm{sim}, L(\operatorname{jsFrame}([(1, \mathrm{clipPath}, \mathrm{own})])), [(\texttt{cssAnim}, \mathit{wa}(\operatorname{clean}([\mathrm{clipPath}], \mathrm{time}), \mathrm{own}, [(1, \mathrm{clipPath}, \mathrm{own})]))]), \\ &(\texttt{P3b}, \mathrm{sim}, L(\operatorname{jsFrame}([(1, \mathrm{background}, \mathrm{layer})])), [(\texttt{cssAnim}, \mathit{wa}(\operatorname{clean}([\mathrm{background}], \mathrm{time}), \mathrm{layer}, [(1, \mathrm{background}, \mathrm{layer})]))]), \\ &(\texttt{P4}, \mathrm{wktr}, L(\operatorname{scrollStep}(\operatorname{jsFrame}([(1, \mathrm{background}, \mathrm{layer})]))), [(\texttt{scrollDriven}, \mathit{sd})]), \\ &(\texttt{P5}, \mathrm{wktr}, L(\operatorname{jsFrame}([(1, \mathrm{transform}, \mathrm{layer})])), [(\texttt{js3d}, L(\operatorname{jsFrame}([(1, \mathrm{transform}, \mathrm{own})])))])\ ], \\ \text{with } L = {} &\operatorname{liftWkFrame},\ \mathit{wa}(a, \ell, \mathit{cs}) = \operatorname{withAnim}(\mathrm{safari}, a, 1, \ell, \mathit{cs}, \varnothing, \mathrm{false}), \\ \mathit{sd} = {} &\operatorname{withAnim}(\mathrm{safari}, \operatorname{clean}([\mathrm{transform}], \mathrm{scroll}), 1, \mathrm{layer}, [(1, \mathrm{transform}, \mathrm{layer})], \operatorname{scrollStep}^{X}(\varnothing), \mathrm{false}) \end{aligned}$$
-/
def scenarios : List Scenario :=
  let L := liftWkFrame
  let wk (e : Nat) (p : WkProp) (l : LayerState) : Change WkPropX := ⟨e, .base p, l⟩
  let anim (a : WkAnim) (e : Nat) (l : LayerState) (cs : List (Change WkPropX)) :=
    withAnim WkMode.safari a e l cs emptyX false
  -- the animation is added to the scroll frame, so its timeline sees the update (`wkTicks`)
  let sd := withAnim WkMode.safari (.clean [.transform] .scroll) 1 .layer [wk 1 .transform .layer] (scrollStepX emptyX) false
  [ ⟨"P1", .sim, L (scrollStep (jsFrame [⟨1, .transform, .layer⟩])), [("scrollDriven", sd)]⟩,
    ⟨"P2", .sim, L (jsFrame []), [("cssTime", anim (.clean [.opacity] .time) 1 .own [wk 1 .opacity .own])]⟩,
    ⟨"P3a", .sim, L (jsFrame [⟨1, .clipPath, .own⟩]),
      [("cssAnim", anim (.clean [.clipPath] .time) 1 .own [wk 1 .clipPath .own])]⟩,
    ⟨"P3b", .sim, L (jsFrame [⟨1, .background, .layer⟩]),
      [("cssAnim", anim (.clean [.background] .time) 1 .layer [wk 1 .background .layer])]⟩,
    ⟨"P4", .wktr, L (scrollStep (jsFrame [⟨1, .background, .layer⟩])), [("scrollDriven", sd)]⟩,
    ⟨"P5", .wktr, L (jsFrame [⟨1, .transform, .layer⟩]), [("js3d", L (jsFrame [⟨1, .transform, .own⟩]))]⟩ ]

/-- One golden row: `{engine, scenario, variant, stage, prediction, countType}`.

$$\mathrm{Row} = \mathrm{String}^{6}$$
-/
structure Row where
  engine     : String
  scenario   : String
  variant    : String
  stage      : String
  prediction : String
  countType  : String
deriving Repr, DecidableEq

/-- The rows of one scenario: for each counted stage of its lane, the original arm (`predO`, variant name
`original`), then each variant (`predV` against the original; variants outer, counts inner), all under `webkit`.
Stage and prediction are stored as their wire strings.

$$\begin{aligned} \forall \sigma:\quad \operatorname{rows}(\sigma) = {} &\big[(\texttt{webkit}, \sigma.\mathrm{id}, \texttt{original}, \operatorname{name}(s), \operatorname{str}(\operatorname{predO}(W_o, s)), k)\big]_{(s, k) \in \operatorname{counts}(\sigma.\mathrm{lane})} \\ \mathbin{+\!\!+} {} &\big[(\texttt{webkit}, \sigma.\mathrm{id}, n, \operatorname{name}(s), \operatorname{str}(\operatorname{predV}(W_v, W_o, s)), k)\big]_{(n, v) \in \sigma.\mathrm{variants},\ (s, k) \in \operatorname{counts}(\sigma.\mathrm{lane})}, \\ \text{with } W_o = {} &\operatorname{frameWork}_{\mathrm{webkit}}(\sigma.\mathrm{original}),\ W_v = \operatorname{frameWork}_{\mathrm{webkit}}(v) \end{aligned}$$
-/
def rowsOf (sc : Scenario) : List Row :=
  let o := frameWork (webkitX WkMode.safari) sc.original
  let cs := sc.lane.counts
  cs.map (fun (s, k) => ⟨"webkit", sc.id, "original", stageName s, (predictOrig o s).str, k⟩) ++
    sc.variants.flatMap fun (n, v) =>
      let w := frameWork (webkitX WkMode.safari) v
      cs.map fun (s, k) => ⟨"webkit", sc.id, n, stageName s, (predictVar w o s).str, k⟩

/-- All golden rows.

$$\mathrm{goldenRows} = \operatorname{flatMap}(\mathrm{scenarios}, \operatorname{rows})$$
-/
def goldenRows : List Row := scenarios.flatMap rowsOf

/-- One row as compact JSON (keys sorted by `Json.mkObj`).

$$\operatorname{json}(r) = \{\texttt{countType}, \texttt{engine}, \texttt{prediction}, \texttt{scenario}, \texttt{stage}, \texttt{variant}\} \text{ of } r$$
-/
def Row.json (r : Row) : String :=
  (Json.mkObj [("engine", .str r.engine), ("scenario", .str r.scenario), ("variant", .str r.variant),
    ("stage", .str r.stage), ("prediction", .str r.prediction), ("countType", .str r.countType)]).compress

/-- The contents of `packages/contracts/golden/engine/webkit.jsonl`: one JSON row per line, newline-terminated, in the
order of `goldenRows`.

$$\mathrm{goldenJsonl} = \mathop{\Vert}_{r \in \mathrm{goldenRows}} \big(\operatorname{json}(r) \mathbin{+\!\!+} \texttt{\textbackslash n}\big)$$
-/
def goldenJsonl : String := String.join (goldenRows.map fun r => r.json ++ "\n")

/-- Look up one golden prediction (for the guards below); `"?"` when absent.

$$\operatorname{pred}(\sigma, n, k) = \begin{cases} r.\mathrm{prediction} & r \text{ the first row with } (\sigma, n, k) \\ \texttt{?} & \text{no such row} \end{cases}$$
-/
def predOf (sc n k : String) : String :=
  ((goldenRows.find? fun r => r.scenario == sc && r.variant == n && r.countType == k).map (·.prediction)).getD "?"

#guard goldenRows.length == 56
-- P1: the threaded scroll-driven variant adds no layout or paint per step and the commit stays; it restyles once per
-- update, as the original's write does (corrected after the WKTR fixtures: the golden had said `=0`).
#guard predOf "P1" "original" "Layout" == ">0" && predOf "P1" "scrollDriven" "Layout" == "=0"
#guard predOf "P1" "scrollDriven" "RecalculateStyles" == "=o" && predOf "P1" "scrollDriven" "Paint" == "=0"
#guard predOf "P1" "scrollDriven" "Composite" == "=o" && predOf "P1" "scrollDriven" "FireAnimationFrame" == "=0"
-- P2: the idle rAF loop costs a callback and a commit per frame; the CSS animation neither.
#guard predOf "P2" "original" "FireAnimationFrame" == ">0" && predOf "P2" "original" "Composite" == ">0"
#guard predOf "P2" "cssTime" "FireAnimationFrame" == "=0" && predOf "P2" "cssTime" "Composite" == "=0"
-- P3: clip-path and background-position paint every frame either way.
#guard predOf "P3a" "original" "Paint" == ">0" && predOf "P3a" "cssAnim" "Paint" == "=o"
#guard predOf "P3b" "original" "Paint" == ">0" && predOf "P3b" "cssAnim" "Paint" == "=o"
-- P4: rendering updates per scroll step equal; the style recalcs stay (one per update: the scroll timeline ticks), the
-- layout and compositing updates are as before.
#guard predOf "P4" "scrollDriven" "renderingUpdates" == "=o" && predOf "P4" "scrollDriven" "styleRecalcs" == "=o"
#guard predOf "P4" "scrollDriven" "layoutUpdates" == "=0" && predOf "P4" "scrollDriven" "compositingUpdates" == "=0"
-- P5: the 2D transform lays out (Overflow); the 3D op removes layout and adds a compositing update.
#guard predOf "P5" "original" "layoutUpdates" == ">0" && predOf "P5" "js3d" "layoutUpdates" == "=0"
#guard predOf "P5" "js3d" "compositingUpdates" == ">o" && predOf "P5" "js3d" "renderingUpdates" == "=o"
#guard predOf "P9" "original" "Layout" == "?"

/-! ### Backing store attach and detach (ledger n=7 and n=11) -/

/-- **Does a layer keep its backing store?** `GraphicsLayerCA` requires backing iff the layer meets the coverage
rect, or does not allow detaching, or has an ancestor with a transform animation, or runs a transform animation of
unknown extent (`WC/platform/graphics/ca/GraphicsLayerCA.cpp:3036-3061`; the last two are `animPinned`). CONFIRMED.

$$\operatorname{attached}(c, d, p) \iff c \lor \lnot d \lor p$$

A layer keeps its backing while it meets the coverage rect or is pinned. -/
def coverageAttached (meets allowsDetach animPinned : Bool) : Bool := meets || !allowsDetach || animPinned

/-- **Paint on a re-attach.** Attaching a backing store calls `setNeedsDisplay`
(`WK/WebProcess/WebPage/RemoteLayerTree/PlatformCALayerRemote.mm:719-731`), which dirties the whole layer bounds
(`WK/Shared/RemoteLayerTree/RemoteLayerBackingStore.mm:240-243`); detaching drops the store. A new backing also has
no front buffer, so its first display is full (`WK/Shared/graphics/ImageBufferSet.cpp:42-50`). CONFIRMED.

$$\operatorname{attachPaint}(p, c, A) = \begin{cases} A & c \land \lnot p \\ 0 & \text{otherwise} \end{cases}$$

A layer that gains a backing store repaints its whole area. -/
def attachPaint (prev cur : Bool) (area : Nat) : Nat := if cur && !prev then area else 0

/-- **Re-attach paint over a run**: the attach paint of every pair of consecutive frames.

$$\operatorname{reattach}(A, [\,]) = \operatorname{reattach}(A, [x]) = 0,\qquad \operatorname{reattach}(A, x :: y :: L) = \operatorname{attachPaint}(x, y, A) + \operatorname{reattach}(A, y :: L)$$

The total repaint a layer pays for regaining its backing store during a run. -/
def reattachPaint (area : Nat) : List Bool → Nat
  | x :: y :: l => attachPaint x y area + reattachPaint area (y :: l)
  | _ => 0

/-- A longer run pays at least the re-attach paint of its tail.

$$\forall A \in \mathbb{N},\ \forall P, L \in \mathbb{B}^{*}:\ \operatorname{reattach}(A, L) \le \operatorname{reattach}(A, P \mathbin{+\!\!+} L)$$

Prepending frames never lowers the re-attach paint. -/
theorem reattachPaint_prefix (area : Nat) (pre l : List Bool) :
    reattachPaint area l ≤ reattachPaint area (pre ++ l) := by
  induction pre with
  | nil => simp
  | cons x pre ih =>
    rw [List.cons_append]
    cases hp : pre ++ l with
    | nil =>
      have : l = [] := (List.append_eq_nil_iff.1 hp).2
      subst this; simp [reattachPaint]
    | cons y r =>
      rw [hp] at ih
      simp only [reattachPaint]
      omega

/-- A run that is detached and later attached pays at least one full re-attach.

$$\forall A \in \mathbb{N},\ \forall M, Q \in \mathbb{B}^{*}:\ A \le \operatorname{reattach}(A, \mathrm{false} :: (M \mathbin{+\!\!+} \mathrm{true} :: Q))$$

Going from detached to attached somewhere costs the whole area. -/
theorem reattachPaint_rise (area : Nat) (mid q : List Bool) :
    area ≤ reattachPaint area (false :: (mid ++ true :: q)) := by
  induction mid with
  | nil => simp [reattachPaint, attachPaint]
  | cons x mid ih =>
    cases x
    · simp only [List.cons_append, reattachPaint, attachPaint] at ih ⊢
      simp only [Bool.and_true, Bool.not_false, Bool.false_eq_true, ↓reduceIte, Nat.zero_add]
      exact ih
    · simp only [List.cons_append, reattachPaint, attachPaint]
      simp

/-- **A strip that always meets the coverage rect never re-attaches** (ledger n=7, the strip side).

$$\forall A, n \in \mathbb{N},\ \forall d, p \in \mathbb{B}:\ \operatorname{reattach}\big(A, [\operatorname{attached}(\mathrm{true}, d, p)]^{n}\big) = 0$$

A layer that stays inside the coverage rect keeps its backing and pays no re-attach paint. -/
theorem strip_no_reattach (area n : Nat) (d p : Bool) :
    reattachPaint area (List.replicate n (coverageAttached true d p)) = 0 := by
  simp only [coverageAttached, Bool.true_or]
  induction n with
  | zero => rfl
  | succ n ih =>
    cases n with
    | zero => rfl
    | succ k =>
      simp only [List.replicate_succ] at ih ⊢
      simp only [reattachPaint, attachPaint, Bool.not_true, Bool.and_false, Bool.false_eq_true, ↓reduceIte,
        Nat.zero_add]
      exact ih

/-- **A face that leaves the coverage rect and comes back repaints in full** (ledger n=7, the face side): with
detaching allowed and no animation pin, a run of coverage flags that is out somewhere and later in again pays at
least the face's area.

$$\forall A \in \mathbb{N},\ \forall P, M, Q \in \mathbb{B}^{*}:\ A \le \operatorname{reattach}\big(A, [\operatorname{attached}(x, \mathrm{true}, \mathrm{false}) \mid x \in P \mathbin{+\!\!+} \mathrm{false} :: (M \mathbin{+\!\!+} \mathrm{true} :: Q)]\big)$$

Every roll that moves a face out of the coverage rect and back costs a full repaint of the face. -/
theorem face_reattach (area : Nat) (pre mid q : List Bool) :
    area ≤ reattachPaint area ((pre ++ false :: (mid ++ true :: q)).map fun x => coverageAttached x true false) := by
  have hid : (fun x => coverageAttached x true false) = id := by
    funext x; cases x <;> rfl
  rw [hid, List.map_id]
  exact Nat.le_trans (reattachPaint_rise area mid q) (reattachPaint_prefix area pre _)

/-- **Does a layer use a backing store?** Only when it draws content or delegates display; otherwise the store is
dropped (`PlatformCALayerRemote.mm:224-228`). CONFIRMED.

$$\operatorname{usesBacking}(c, g) \iff c \lor g$$

A layer that neither draws nor delegates display has no backing store. -/
def usesBacking (drawsContent delegates : Bool) : Bool := drawsContent || delegates

/-- **Resident backing of a layer** of area `A` kpx.

$$\operatorname{resident}(c, g, A) = \begin{cases} A & \operatorname{usesBacking}(c, g) \\ 0 & \text{otherwise} \end{cases}$$

A layer with a backing store holds its area in memory; a simple layer holds none. -/
def residentKpx (drawsContent delegates : Bool) (areaKpx : Nat) : Nat :=
  if usesBacking drawsContent delegates then areaKpx else 0

/-- **Paint of a resize.** `setBounds` re-creates the backing parameters with the new size
(`PlatformCALayerRemote.mm:596-608, 333-355`); changed parameters clear the store and dirty the whole layer
(`RemoteLayerBackingStore.mm:139-152`); with no attached store there is nothing to dirty (`PlatformCALayerRemote.mm:357-375`).
CONFIRMED.

$$\operatorname{resizePaint}(c, g, t, A) = \begin{cases} A & \operatorname{usesBacking}(c, g) \land t \\ 0 & \text{otherwise} \end{cases}$$

A resized layer with an attached backing store repaints in full; a simple layer paints nothing. -/
def resizePaint (drawsContent delegates attached : Bool) (areaKpx : Nat) : Nat :=
  if usesBacking drawsContent delegates && attached then areaKpx else 0

/-- **A simple layer costs no backing and no resize paint** (ledger n=11, first statement).

$$\forall t \in \mathbb{B},\ \forall A \in \mathbb{N}:\ \operatorname{resident}(\mathrm{false}, \mathrm{false}, A) = 0 \land \operatorname{resizePaint}(\mathrm{false}, \mathrm{false}, t, A) = 0$$

A layer that only shows a background colour or a clip holds no store and paints nothing when it grows. -/
theorem simple_layer (t : Bool) (a : Nat) : residentKpx false false a = 0 ∧ resizePaint false false t a = 0 := by
  simp [residentKpx, resizePaint, usesBacking]

/-- **A backed layer repaints in full on resize.**

$$\forall c, g \in \mathbb{B},\ \forall A \in \mathbb{N}:\ \operatorname{usesBacking}(c, g) \Rightarrow \operatorname{resizePaint}(c, g, \mathrm{true}, A) = A$$

Growing a layer with an attached backing store repaints its whole area. -/
theorem backed_resize (c g : Bool) (a : Nat) (h : usesBacking c g = true) : resizePaint c g true a = a := by
  simp [resizePaint, h]

/-- **Promote per tween** (ledger n=11, second statement): an element composited only while it animates gains a
backing store of its area in the tween's first frame and repaints it in full there.

$$\forall A \in \mathbb{N},\ \forall L \in \mathbb{B}^{*}:\ A \le \operatorname{reattach}(A, \mathrm{false} :: \mathrm{true} :: L) \land \operatorname{resident}(\mathrm{true}, \mathrm{false}, A) \mathbin{\dot{-}} \operatorname{resident}(\mathrm{false}, \mathrm{false}, A) = A$$

Each tween that promotes the element pays one full paint and adds its area to resident memory. -/
theorem promote_tween (a : Nat) (l : List Bool) :
    a ≤ reattachPaint a (false :: true :: l) ∧ residentKpx true false a - residentKpx false false a = a := by
  simp [reattachPaint, attachPaint, residentKpx, usesBacking]

#guard reattachPaint 5 [true, false, true, false, true] == 10 && reattachPaint 5 [true, true, true] == 0
#guard coverageAttached false true false == false && coverageAttached false false false == true
#guard coverageAttached false true true == true
#guard residentKpx false false 9 == 0 && residentKpx false true 9 == 9 && resizePaint true false false 9 == 0
#guard attachPaint false true 4 == 4 && attachPaint true true 4 == 0

/-! ### Display area of a dirty rect (ledger n=13, WebKit half) -/

/-- **Does a backing store paint only the dirty rect?** `supportsPartialRepaint` is false when the backend area is at
most 64 × 64 = 4096 device pixels (`WK/Shared/RemoteLayerTree/RemoteLayerBackingStore.mm:293-307`; the
dynamic-content-scaling display-list case is not modelled). CONFIRMED.

$$\operatorname{partial}(B) \iff 4096 < B$$

Small backing stores always repaint in full. -/
def partialRepaint (backendPx : Nat) : Bool := decide (4096 < backendPx)

/-- **Painted pixels of one display** of a store with backend area `B` and dirty area `a`. With a valid front buffer
and partial repaint the host paints only the dirty rect and copies the rest forward from the back buffer
(`WK/Shared/graphics/ImageBufferSet.cpp:103-147`); with no front buffer, a purged one, or no partial repaint it paints
the whole store (`:42-56`). The copy is not painting and is not counted. CONFIRMED.

$$\operatorname{display}(B, a, v) = \begin{cases} a & v \land \operatorname{partial}(B) \\ B & \text{otherwise} \end{cases}$$

The pixels painted for one dirty rect: the rect in the steady state, the whole store otherwise. -/
def displayPx (B a : Nat) (frontValid : Bool) : Nat := if frontValid && partialRepaint B then a else B

/-- **Bounds of the display term.**

$$\forall B, a \in \mathbb{N},\ \forall v \in \mathbb{B}:\ a \le B \Rightarrow a \le \operatorname{display}(B, a, v) \le B$$

A display paints at least the dirty rect and at most the whole store. -/
theorem display_bounds (B a : Nat) (v : Bool) (h : a ≤ B) : a ≤ displayPx B a v ∧ displayPx B a v ≤ B := by
  unfold displayPx
  split <;> omega

/-- **A large host in the steady state paints only the dirty rect**, so moving the content to its own layer cannot
paint less (refutes ledger n=13's $D_{\mathrm{wk}}(o) = B$).

$$\forall B, b, a \in \mathbb{N},\ \forall v \in \mathbb{B}:\ \operatorname{partial}(B) \land a \le b \Rightarrow \operatorname{display}(B, a, \mathrm{true}) = a \le \operatorname{display}(b, a, v)$$

The whole-host repaint happens only after a buffer loss, not every frame. -/
theorem host_steady_le_own (B b a : Nat) (v : Bool) (hB : partialRepaint B = true) (hab : a ≤ b) :
    displayPx B a true = a ∧ displayPx B a true ≤ displayPx b a v := by
  have h1 : displayPx B a true = a := by simp [displayPx, hB]
  refine ⟨h1, ?_⟩
  rw [h1]
  exact (display_bounds b a v hab).1

#guard displayPx 10000 30 true == 30 && displayPx 10000 30 false == 10000 && displayPx 4096 30 true == 4096
#guard partialRepaint 4097 && !partialRepaint 4096

/-! ### Inherited custom property writes (ledger n=16) -/

/-- **A write of an inherited custom property on `e`**: the writer and every descendant the resolver reaches are
restyled. The writer's change is `Change::Inherited`, so each child is resolved in full, and a child whose style
changes (it inherits the new value) passes the resolution to its own children (`WC/style/StyleTreeResolver.cpp:283-311,
1185-1212`). `reached` lists the descendants reached (the subtree, minus branches under an element that overrides
the property). CONFIRMED.

$$\operatorname{customWrite}(e, \ell, R) = (e, \mathrm{customInherited}, \ell) :: [\,(d, \mathrm{restyle}, \mathrm{none}) \mid d \in R\,]$$

The changes one inherited custom-property write makes. -/
def customWrite (e : Nat) (ℓ : LayerState) (reached : List Nat) : List (Change WkPropX) :=
  ⟨e, .customInherited, ℓ⟩ :: reached.map fun d => ⟨d, .restyle, .none⟩

/-- **Style units of the write.**

$$\forall m, \forall s, e \in \mathbb{N}, \forall \ell, \forall R \in \mathbb{N}^{*}:\ \operatorname{units}_{\operatorname{webkitX}(m)}\big((s, 0, 0, 0, \operatorname{customWrite}(e, \ell, R), 0), \mathrm{style}\big) = 1 + |R|$$

A custom-property write restyles the writer and every reached descendant. -/
theorem custom_style_units (m : WkMode) (s e : Nat) (ℓ : LayerState) (reached : List Nat) :
    stageUnits (webkitX m) ⟨s, 0, 0, 0, customWrite e ℓ reached, 0⟩ .style = 1 + reached.length := by
  simp [stageUnits, customWrite, webkitX, wkStagesOfX]
  induction reached with
  | nil => rfl
  | cons d r ih => simp [ih]; omega

/-- **Skipping the write is strictly less work** (the MQ-gated shrink of `people.card`): the same frame without the
write is strictly below it.

$$\forall m, \forall s, e \in \mathbb{N}, \forall \ell, \forall R \in \mathbb{N}^{*}:\ \operatorname{frameWork}_{\operatorname{webkitX}(m)}\big((s, 0, 0, 0, [\,], 0)\big) \prec \operatorname{frameWork}_{\operatorname{webkitX}(m)}\big((s, 0, 0, 0, \operatorname{customWrite}(e, \ell, R), 0)\big)$$

On every frame where the value would move, not writing it saves style work. -/
theorem customSkip_lt (m : WkMode) (s e : Nat) (ℓ : LayerState) (reached : List Nat) :
    (frameWork (webkitX m) ⟨s, 0, 0, 0, [], 0⟩).lt (frameWork (webkitX m) ⟨s, 0, 0, 0, customWrite e ℓ reached, 0⟩) := by
  have hu := custom_style_units m s e ℓ reached
  refine ⟨⟨fun st => ?_, Nat.le_refl _⟩, Or.inl ⟨.style, Or.inr ?_⟩⟩
  · constructor
    · cases st <;> by_cases h : 0 < s <;>
        simp [frameWork, touched, forcedPasses, FrameIn.updates, customWrite, webkitX, wkStagesOfX, h]
    · simp only [frameWork, stageUnits, List.countP_nil, Nat.zero_add]
      omega
  · simp only [frameWork] at hu ⊢
    rw [hu]
    simp [stageUnits]
    omega

#guard stageUnits (webkitX .safari) ⟨0, 0, 0, 0, customWrite 1 .none [2, 3, 4], 0⟩ .style == 4

/-! ### The effect stack (ledger n=17) -/

/-- An effect in an element's effect stack: the animation, whether a motion path applies (in the underlying style or
animated), and whether an earlier accelerated start failed.

$$\mathrm{StackEffect} = \mathrm{WkAnim} \times \underbrace{\mathbb{B}}_{\mathrm{motionPath}} \times \underbrace{\mathbb{B}}_{\mathrm{failed}}$$

One keyframe effect as the stack rule sees it. -/
structure StackEffect where
  anim : WkAnim
  motionPath : Bool := false
  failed : Bool := false
deriving Repr

/-- **Does an effect block acceleration of its stack?** `KeyframeEffect::preventsAcceleration`
(`WC/animation/KeyframeEffect.cpp:2035-2058`): never on the threaded path; always with a motion path; never when the
effect animates no accelerated property; else when it cannot be accelerated or its accelerated run failed. CONFIRMED.

$$\operatorname{prevents}(m, x) \iff \operatorname{path}(m, x.a) \ne \mathrm{threaded} \land \Big(x.\mathrm{motionPath} \lor \big((\exists q \in x.a.\mathrm{props}:\ \operatorname{accel}(\mathrm{legacy}, q)) \land (\lnot\operatorname{cba}(m, x.a) \lor x.\mathrm{failed})\big)\Big)$$

An effect blocks its stack only if it is on the legacy path and has a motion path or an accelerated property it
cannot run accelerated. -/
def prevents (m : WkMode) (x : StackEffect) : Bool :=
  if pathOf m x.anim = .threaded then false
  else x.motionPath || (x.anim.props.any (accelerated .legacy) && (!canBeAccelerated m x.anim || x.failed))

/-- **The thread of an effect in its stack.** `KeyframeEffectStack::allowsAcceleration` is false if any effect
prevents acceleration, or two effects animate a shared accelerated property with an implicit keyframe, or threaded and
non-threaded effects share an accelerated property (`WC/animation/KeyframeEffectStack.cpp:215-283`; the last two are
`extra`); then every effect is stopped (`:285-300`). CONFIRMED.

$$\operatorname{stackThread}(m, X, E, x) = \begin{cases} \mathrm{comp} & \lnot E \land (\forall y \in X:\ \lnot\operatorname{prevents}(m, y)) \land \operatorname{wkThread}(m, x.a) = \mathrm{comp} \\ \mathrm{main} & \text{otherwise} \end{cases}$$

An effect runs in the UI process only if its own rule allows it and no effect of its stack blocks. -/
def stackThread (m : WkMode) (xs : List StackEffect) (extra : Bool) (x : StackEffect) : Thread :=
  if !extra && xs.all (fun y => !prevents m y) && decide (wkThread m x.anim = .comp) then .comp else .main

/-- **The stack rule.** One blocking effect sends every effect of the stack to the main thread.

$$\forall m, X, E:\ (\exists y \in X:\ \operatorname{prevents}(m, y)) \Rightarrow \forall x:\ \operatorname{stackThread}(m, X, E, x) = \mathrm{main}$$

A single effect that cannot accelerate an accelerated property stops the whole stack. -/
theorem stack_rule (m : WkMode) (xs : List StackEffect) (extra : Bool) (h : ∃ y ∈ xs, prevents m y = true)
    (x : StackEffect) : stackThread m xs extra x = .main := by
  obtain ⟨y, hy, hp⟩ := h
  have : xs.all (fun y => !prevents m y) = false := by
    rw [List.all_eq_false]; exact ⟨y, hy, by simp [hp]⟩
  simp [stackThread, this]

/-- **Main-thread effects that do not block** (refutes ledger n=17's "any non-accelerable effect stops the stack"):
on the legacy path, an effect with no motion path that animates no accelerated property never prevents acceleration,
even though it runs on the main thread itself; nor does any threaded-path effect.

$$\forall m, x:\ \big(\operatorname{path}(m, x.a) = \mathrm{threaded} \lor (\lnot x.\mathrm{motionPath} \land \forall q \in x.a.\mathrm{props}:\ \lnot\operatorname{accel}(\mathrm{legacy}, q))\big) \Rightarrow \lnot\operatorname{prevents}(m, x)$$

Only effects on accelerated properties (or with a motion path) can hold the stack back. -/
theorem stack_free (m : WkMode) (x : StackEffect)
    (h : pathOf m x.anim = .threaded ∨
      (x.motionPath = false ∧ ∀ q ∈ x.anim.props, accelerated .legacy q = false)) :
    prevents m x = false := by
  unfold prevents
  rcases h with h | ⟨hm, hq⟩
  · simp [h]
  · split
    · rfl
    · have : x.anim.props.any (accelerated .legacy) = false := by
        rw [List.any_eq_false]; intro q hq'; simp [hq q hq']
      simp [hm, this]

/-- **Stack demo**: a legacy-path background animation (main thread, no accelerated property) and a transform
animation on one element.

$$\mathrm{stackDemo} = [\,(\mathrm{clean}([\mathrm{background}], \mathrm{time}), \mathrm{false}, \mathrm{false}),\ (\mathrm{clean}([\mathrm{transform}], \mathrm{time}), \mathrm{false}, \mathrm{false})\,]$$

Two effects on one element, used to show a main-thread effect that does not block the stack. -/
def stackDemo : List StackEffect := [{ anim := .clean [.background] .time }, { anim := .clean [.transform] .time }]

#guard wkThread .safari (WkAnim.clean [.background] .time) == .main
#guard stackDemo.map (stackThread .safari stackDemo false) == [.main, .comp]
#guard stackThread .safari [{ anim := .clean [.transform] .time, failed := true }, { anim := .clean [.opacity] .time }]
  false { anim := .clean [.opacity] .time } == .main
#guard stackThread .safari stackDemo true { anim := .clean [.transform] .time } == .main
#guard prevents .safari { anim := .clean [.transform] .time, motionPath := true }
#guard !prevents .safari { anim := { WkAnim.clean [.transform] .scroll with blockers := [.quirk] } }

/-! ### Size containers interleave style and layout (ledger n=20 and n=22, WebKit half) -/

/-- The largest value of `f` over a list, 0 for the empty list.

$$\operatorname{wkMaxOf}(f, [\,]) = 0,\qquad \operatorname{wkMaxOf}(f, x :: L) = \max(f(x), \operatorname{wkMaxOf}(f, L))$$

The maximum of a measure over a list. -/
def wkMaxOf {β : Type} (f : β → Nat) : List β → Nat
  | [] => 0
  | x :: l => max (f x) (wkMaxOf f l)

/-- **WebKit style rounds of one style update.** Each chain lists the size containers on one root-to-leaf path the
style traversal reaches, outermost first. Every reached element whose style makes it a size query container skips
its descendants and queues a container query state (`WC/style/StyleTreeResolver.cpp:1460-1478`, called at `:1377`,
deferral `:1391-1394`); `resolve()` then asks for an interleaved layout (`:1515-1522`), and `Document::resolveStyle`
loops while one is needed (`WC/dom/Document.cpp:2897-2911`). So the style resolution runs once more per nesting level
of reached containers, layout-dirty or not. CONFIRMED.

$$\operatorname{wkRounds}(\mathcal{C}) = 1 + \operatorname{wkMaxOf}(|\cdot|, \mathcal{C})$$

WebKit resolves style once more per nesting level of size containers in the traversal. -/
def wkRounds (chains : List (List Nat)) : Nat := 1 + wkMaxOf List.length chains

/-- **Interleaved layouts of a style update.** Between two style rounds `Document::resolveStyle` runs a layout only
if the render tree needs one (`WC/dom/Document.cpp:2897-2911`); `dirty r` says whether it does after round `r`.

$$\operatorname{wkLayouts}(\mathcal{C}, D) = \big|[\,r \in [0, \operatorname{wkRounds}(\mathcal{C}) \mathbin{\dot{-}} 1) \mid D(r)\,]\big|$$

The layouts WebKit runs inside one style update. -/
def wkLayouts (chains : List (List Nat)) (dirty : Nat → Bool) : Nat :=
  ((List.range (wkRounds chains - 1)).filter dirty).length

/-- **A reached container costs a second style round.**

$$\forall \mathcal{C} \in (\mathbb{N}^{*})^{*}:\ (\exists \mathit{ch} \in \mathcal{C}:\ \mathit{ch} \ne [\,]) \Rightarrow 2 \le \operatorname{wkRounds}(\mathcal{C})$$

If the traversal reaches any size container, style resolves at least twice. -/
theorem wkRounds_ge_two (chains : List (List Nat)) (h : ∃ ch ∈ chains, ch ≠ []) : 2 ≤ wkRounds chains := by
  obtain ⟨ch, hc, hne⟩ := h
  have hle : ch.length ≤ wkMaxOf List.length chains := by
    clear hne
    induction chains with
    | nil => simp at hc
    | cons y l ih =>
      simp only [wkMaxOf]
      rcases List.mem_cons.1 hc with rfl | h
      · omega
      · have := ih h; omega
  have : 1 ≤ ch.length := by
    cases ch with
    | nil => exact absurd rfl hne
    | cons _ _ => simp
  simp only [wkRounds]; omega

/-- **Interleaved layouts are at most rounds minus one, and can be zero** (refutes ledger n=20's "a reached
container forces a layout pass": a layout runs only if the tree is layout-dirty between rounds).

$$\forall \mathcal{C}, D:\ \operatorname{wkLayouts}(\mathcal{C}, D) \le \operatorname{wkRounds}(\mathcal{C}) \mathbin{\dot{-}} 1 \ \land\ \operatorname{wkLayouts}(\mathcal{C}, r \mapsto \mathrm{false}) = 0$$

A size container costs style rounds for sure, but layouts only when something is layout-dirty. -/
theorem wkLayouts_le (chains : List (List Nat)) (dirty : Nat → Bool) :
    wkLayouts chains dirty ≤ wkRounds chains - 1 ∧ wkLayouts chains (fun _ => false) = 0 := by
  constructor
  · have := List.length_filter_le dirty (List.range (wkRounds chains - 1))
    simpa [wkLayouts] using this
  · simp [wkLayouts]

/-- **Removing a container never adds a round** (WebKit).

$$\forall \mathcal{C},\ \forall c \in \mathbb{N}:\ \operatorname{wkRounds}\big([\,[\,i \in \mathit{ch} \mid i \ne c\,] \mid \mathit{ch} \in \mathcal{C}\,]\big) \le \operatorname{wkRounds}(\mathcal{C})$$

Dropping `container-type` from one element can only lower WebKit's style rounds. -/
theorem wkRounds_remove (chains : List (List Nat)) (c : Nat) :
    wkRounds (chains.map fun ch => ch.filter fun i => decide (i ≠ c)) ≤ wkRounds chains := by
  have hmap : ∀ (l : List (List Nat)), wkMaxOf List.length (l.map fun ch => ch.filter fun i => decide (i ≠ c)) ≤
      wkMaxOf List.length l := by
    intro l
    induction l with
    | nil => simp [wkMaxOf]
    | cons ch l ih =>
      simp only [List.map_cons, wkMaxOf]
      have := List.length_filter_le (fun i => decide (i ≠ c)) ch
      omega
  have := hmap chains
  simp only [wkRounds]; omega

/-- **Removing a reached container need not lower the rounds** (refutes ledger n=22's "lowers WebKit layout passes
iff $c \in \mathrm{trav}(f)$"): container 1 is reached, but a deeper chain sets the count.

$$\operatorname{wkRounds}([[1], [2, 3]]) = \operatorname{wkRounds}([[\,], [2, 3]]) = 3$$

Only a container on a deepest chain lowers the round count. -/
theorem wkRounds_not_iff : wkRounds [[1], [2, 3]] = wkRounds [[], [2, 3]] ∧ wkRounds [[], [2, 3]] = 3 := by decide

#guard wkRounds [] == 1 && wkRounds [[7]] == 2 && wkRounds [[1, 2], [3]] == 3
#guard wkLayouts [[1, 2]] (fun r => r == 0) == 1 && wkLayouts [[1, 2]] (fun _ => true) == 2

/-! ### SVG gradient attributes lay out (ledger n=24, WebKit half) -/

/-- **An SVG gradient attribute lays out in WebKit** (ledger n=24): one change of `x1`/`x2`/`y1`/`y2` in a frame
with nothing else costs one style, one layout and one paint pass.

$$\forall m \in \mathrm{WkMode},\ \forall e \in \mathbb{N},\ \forall \ell:\ W.\mathrm{passes}(\mathrm{style}) = W.\mathrm{passes}(\mathrm{layout}) = W.\mathrm{passes}(\mathrm{paint}) = 1\quad\text{where } W = \operatorname{frameWork}_{\operatorname{webkitX}(m)}\big((0, 0, 0, 0, [(e, \mathrm{svgResourceAttr}, \ell)], 0)\big)$$

In WebKit a SMIL gradient attribute step costs a layout, unlike Chromium. -/
theorem svgAttr_layout (m : WkMode) (e : Nat) (ℓ : LayerState) :
    (frameWork (webkitX m) ⟨0, 0, 0, 0, [⟨e, .svgResourceAttr, ℓ⟩], 0⟩).passes .style = 1 ∧
      (frameWork (webkitX m) ⟨0, 0, 0, 0, [⟨e, .svgResourceAttr, ℓ⟩], 0⟩).passes .layout = 1 ∧
      (frameWork (webkitX m) ⟨0, 0, 0, 0, [⟨e, .svgResourceAttr, ℓ⟩], 0⟩).passes .paint = 1 := by
  simp [frameWork, touched, webkitX, wkStagesOfX, forcedPasses, FrameIn.updates]

end Fw.Engine.WebKit

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
the model is a measured claim (P1-P5), not a theorem. C-2: the stage map is **not** monotone in `Diff` order
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

/-- **Opacity crossing 1 → layout.** An opacity change that flips `isOpaque` is a full Layout on every layer state
(`StyleDifference.cpp:208-214`; Chromium keeps it `direct`, design note §1.4).

$$\forall m, \forall e \in \mathbb{N}, \forall \ell \in \mathrm{LayerState}:\ \mathrm{layout} \in \operatorname{webkitAt}(m).\mathrm{stagesOf}(e, \mathrm{opacityCross1}, \ell)$$
-/
theorem opacityCross1_layout (m : WkMode) (e : Nat) (ℓ : LayerState) :
    Stage.layout ∈ (webkitAt m).stagesOf ⟨e, .opacityCross1, ℓ⟩ := by
  have h : wkDiff ⟨e, .opacityCross1, ℓ⟩ = .layout := by cases ℓ <;> rfl
  simp [webkitAt, h, diffStages]

/-- **stroke-dashoffset → layout.** A stroke-dashoffset change recomputes the cached stroke bounds, a full Layout on
every layer state (`StyleDifference.cpp:161`; Chromium: paint).

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

/-- **Scroll rule.** Every delivered scroll position is exactly one rendering update with one commit pass, whatever the
frame does besides (design note §1.3, prediction P4).

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

/-- **A compositor animation costs zero web-process work**: no pass and no unit on any stage but `comp`.

$$\forall m, \forall n \in \mathbb{N}, \forall s \ne \mathrm{comp}:\ \operatorname{frameWork}_{\operatorname{webkitAt}(m)}(\operatorname{compFrame}(n)).\mathrm{passes}(s) = 0 \land \operatorname{frameWork}_{\operatorname{webkitAt}(m)}(\operatorname{compFrame}(n)).\mathrm{units}(s) = 0$$
-/
theorem compFrame_zero (m : WkMode) (n : Nat) (s : Stage) (hs : s ≠ .comp) :
    (frameWork (webkitAt m) (compFrame n)).passes s = 0 ∧ (frameWork (webkitAt m) (compFrame n)).units s = 0 := by
  cases s <;> first
    | exact absurd rfl hs
    | (constructor <;>
        simp [frameWork, touched, stageUnits, forcedPasses, compFrame, webkitAt, FrameIn.updates] <;>
        by_cases hn : 0 < n <;> simp [hn])

/-- A UI-process animation's frame has zero web-process work (`KeyframeEffect.cpp:2724-2744`: a completely
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
(which rejects only drop-shadow and mismatched op lists, `GraphicsLayerCA.cpp:3946-3958`). Chromium contrasts: bit 12
(blur or drop-shadow in `filter`, `compositor_animations.cc:405-417`@f842f52) keeps it on main (design note §1.4).

$$\forall m \in \mathrm{WkMode}:\ \operatorname{wkThread}(m, \mathrm{blurAnim}) = \mathrm{comp}$$
-/
theorem blur_comp (m : WkMode) : wkThread m blurAnim = .comp := by
  obtain ⟨tsd, ttb, p⟩ := m
  cases tsd <;> cases ttb <;> cases p <;> decide

/-- **A blur animation costs no web-process work per frame**, whatever main-thread changes it would otherwise make.

$$\forall m, \mathit{cs}, \forall s \ne \mathrm{comp}:\ \operatorname{frameWork}_{\operatorname{webkitAt}(m)}(\operatorname{animFrame}(m, \mathrm{blurAnim}, \mathit{cs})).\mathrm{passes}(s) = 0 \land \operatorname{frameWork}_{\operatorname{webkitAt}(m)}(\operatorname{animFrame}(m, \mathrm{blurAnim}, \mathit{cs})).\mathrm{units}(s) = 0$$
-/
theorem blur_zero (m : WkMode) (cs : List (Change WkProp)) (s : Stage) (hs : s ≠ .comp) :
    (frameWork (webkitAt m) (animFrame m blurAnim cs)).passes s = 0 ∧
      (frameWork (webkitAt m) (animFrame m blurAnim cs)).units s = 0 :=
  anim_comp_zero m blurAnim cs (blur_comp m) s hs

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

$$\mathrm{Scenario} = \mathrm{String} \times \mathrm{Lane} \times \mathrm{FrameIn}(\mathrm{WkProp}) \times (\mathrm{String} \times \mathrm{FrameIn}(\mathrm{WkProp}))^{*}$$
-/
structure Scenario where
  id       : String
  lane     : Lane
  original : FrameIn WkProp
  variants : List (String × FrameIn WkProp)

/-- The five scenarios of WebKit note §5.3, in the default Safari mode (box 1 is the animated box):
- P1 (sim, per scroll step): a JS scroll handler writing a 2D transform on a non-composited layer vs a threaded
  scroll-driven transform animation;
- P2 (sim, idle frame): a permanent rAF loop that writes nothing vs a CSS time-based opacity animation;
- P3a / P3b (sim, per frame): a rAF writer of clip-path (composited box) / background-position vs the same as a CSS
  animation (never accelerated);
- P4 (wktr, per scroll step): a JS scroll handler repainting a background vs a threaded scroll-driven animation;
- P5 (wktr, per frame): a rAF writer of a 2D transform without a compositing reason vs the same with a 3D op.

$$\mathrm{scenarios} = [\mathrm{P1}, \mathrm{P2}, \mathrm{P3a}, \mathrm{P3b}, \mathrm{P4}, \mathrm{P5}] \text{ as listed}$$
-/
def scenarios : List Scenario :=
  let sd := animFrame .safari (.clean [.transform] .scroll) [⟨1, .transform, .layer⟩]
  [ ⟨"P1", .sim, scrollStep (jsFrame [⟨1, .transform, .layer⟩]), [("scrollDriven", scrollStep sd)]⟩,
    ⟨"P2", .sim, jsFrame [], [("cssTime", animFrame .safari (.clean [.opacity] .time) [⟨1, .opacity, .own⟩])]⟩,
    ⟨"P3a", .sim, jsFrame [⟨1, .clipPath, .own⟩],
      [("cssAnim", animFrame .safari (.clean [.clipPath] .time) [⟨1, .clipPath, .own⟩])]⟩,
    ⟨"P3b", .sim, jsFrame [⟨1, .background, .layer⟩],
      [("cssAnim", animFrame .safari (.clean [.background] .time) [⟨1, .background, .layer⟩])]⟩,
    ⟨"P4", .wktr, scrollStep (jsFrame [⟨1, .background, .layer⟩]), [("scrollDriven", scrollStep sd)]⟩,
    ⟨"P5", .wktr, jsFrame [⟨1, .transform, .layer⟩], [("js3d", jsFrame [⟨1, .transform, .own⟩])]⟩ ]

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
`original`), then each variant (`predV` against the original), all under `webkit`.

$$\operatorname{rows}(\sigma) = \big[(\texttt{webkit}, \sigma.\mathrm{id}, \texttt{original}, s, \operatorname{predO}(W_o, s), k)\big]_{(s, k) \in \operatorname{counts}(\sigma.\mathrm{lane})} \mathbin{+\!\!+} \big[(\texttt{webkit}, \sigma.\mathrm{id}, n, s, \operatorname{predV}(W_v, W_o, s), k)\big]_{(n, v) \in \sigma.\mathrm{variants},\ (s, k) \in \operatorname{counts}(\sigma.\mathrm{lane})},\quad W_x = \operatorname{frameWork}_{\mathrm{webkit}}(x)$$
-/
def rowsOf (sc : Scenario) : List Row :=
  let o := frameWork webkit sc.original
  let cs := sc.lane.counts
  cs.map (fun (s, k) => ⟨"webkit", sc.id, "original", stageName s, (predictOrig o s).str, k⟩) ++
    sc.variants.flatMap fun (n, v) =>
      let w := frameWork webkit v
      cs.map fun (s, k) => ⟨"webkit", sc.id, n, stageName s, (predictVar w o s).str, k⟩

/-- All golden rows.

$$\mathrm{rows} = \operatorname{flatMap}(\operatorname{rows}, \mathrm{scenarios})$$
-/
def goldenRows : List Row := scenarios.flatMap rowsOf

/-- One row as compact JSON (keys sorted by `Json.mkObj`).

$$\operatorname{json}(r) = \{\texttt{countType}, \texttt{engine}, \texttt{prediction}, \texttt{scenario}, \texttt{stage}, \texttt{variant}\} \text{ of } r$$
-/
def Row.json (r : Row) : String :=
  (Json.mkObj [("engine", .str r.engine), ("scenario", .str r.scenario), ("variant", .str r.variant),
    ("stage", .str r.stage), ("prediction", .str r.prediction), ("countType", .str r.countType)]).compress

/-- The contents of `packages/contracts/golden/engine/webkit.jsonl`: one JSON row per line, newline-terminated.

$$\mathrm{goldenJsonl} = \mathop{\Vert}_{r \in \mathrm{rows}} \big(\operatorname{json}(r) \mathbin{+\!\!+} \texttt{\textbackslash n}\big)$$
-/
def goldenJsonl : String := String.join (goldenRows.map fun r => r.json ++ "\n")

/-- Look up one golden prediction (for the guards below); `"?"` when absent.

$$\operatorname{pred}(\sigma, n, k) = \begin{cases} r.\mathrm{prediction} & r \text{ the first row with } (\sigma, n, k) \\ \texttt{?} & \text{no such row} \end{cases}$$
-/
def predOf (sc n k : String) : String :=
  ((goldenRows.find? fun r => r.scenario == sc && r.variant == n && r.countType == k).map (·.prediction)).getD "?"

#guard goldenRows.length == 56
-- P1: the threaded scroll-driven variant adds no style, layout or paint per step; the commit stays.
#guard predOf "P1" "original" "Layout" == ">0" && predOf "P1" "scrollDriven" "Layout" == "=0"
#guard predOf "P1" "scrollDriven" "RecalculateStyles" == "=0" && predOf "P1" "scrollDriven" "Paint" == "=0"
#guard predOf "P1" "scrollDriven" "Composite" == "=o" && predOf "P1" "scrollDriven" "FireAnimationFrame" == "=0"
-- P2: the idle rAF loop costs a callback and a commit per frame; the CSS animation neither.
#guard predOf "P2" "original" "FireAnimationFrame" == ">0" && predOf "P2" "original" "Composite" == ">0"
#guard predOf "P2" "cssTime" "FireAnimationFrame" == "=0" && predOf "P2" "cssTime" "Composite" == "=0"
-- P3: clip-path and background-position paint every frame either way.
#guard predOf "P3a" "original" "Paint" == ">0" && predOf "P3a" "cssAnim" "Paint" == "=o"
#guard predOf "P3b" "original" "Paint" == ">0" && predOf "P3b" "cssAnim" "Paint" == "=o"
-- P4: rendering updates per scroll step equal; style work gone.
#guard predOf "P4" "scrollDriven" "renderingUpdates" == "=o" && predOf "P4" "scrollDriven" "styleRecalcs" == "=0"
-- P5: the 2D transform lays out (Overflow); the 3D op removes layout and adds a compositing update.
#guard predOf "P5" "original" "layoutUpdates" == ">0" && predOf "P5" "js3d" "layoutUpdates" == "=0"
#guard predOf "P5" "js3d" "compositingUpdates" == ">o" && predOf "P5" "js3d" "renderingUpdates" == "=o"
#guard predOf "P9" "original" "Layout" == "?"

end Fw.Engine.WebKit

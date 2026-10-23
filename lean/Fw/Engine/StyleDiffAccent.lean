import Lean.Data.Json
import Fw.Engine
/-!
# StyleDifference of the hero.accent draw candidates (WebKit and Chromium)

One canonical table (`row`) of the property changes a hero.accent draw could use, each mapped to the WebKit property
(`Fw.Engine.WebKit.wkDiff`) and the Chromium key (`Fw.Engine.Chromium.keyLevel`) whose rows are the cited source lines,
and the theorems the arm `hero.accent:draw-nolayout` rests on. WebKit @862f17d (`WC` = `Source/WebCore`), Chromium
@f842f52 (`B` = `third_party/blink/renderer/core`).

* `stroke-dashoffset` (the faithful draw): layout in WebKit (`WC/style/StyleDifference.cpp:161` in
  `svgDataChangeRequiresLayout`, called at `:399`), paint in Chromium (`B/css/css_properties.json5:6120`
  `invalidate: ["paint"]`; `B/style/computed_style.cc:998-1006` adds layout only when the stroke or the dash array
  appears or disappears).
* `clip-path` (the arm): `Equal` plus the ClipPath context at `WC/style/StyleDifference.cpp:779-780`, raised to Repaint,
  or RecompositeLayer, by `WC/rendering/RenderElement.cpp:321-326`; never Layout. The legacy SVG renderer marks the
  client for layout with `needsLayout = false` (`WC/rendering/svg/legacy/SVGResourcesCache.cpp:222`, called from
  `WC/rendering/svg/legacy/LegacyRenderSVGRoot.cpp:400`). Chromium: `invalidate: ["clip-path"]`
  (`B/css/css_properties.json5:3112`), `clip_path_changed` (`B/style/computed_style.cc:838-840`).
* `transform`: Layout without a layer, Overflow on a plain layer, RecompositeLayer on a composited one
  (`WC/rendering/RenderElement.cpp:300-312`; the context is added at `WC/style/StyleDifference.cpp:199-205`).
* `opacity` leaving 1 or reaching 1: Layout (`WC/style/StyleDifference.cpp:208`).
* `width`: Layout (`WC/style/StyleDifference.cpp:404`; `B/css/css_properties.json5:8286` `invalidate: ["layout", ...]`).

Status: the table rows are CONFIRMED from those lines; whether the shipped Safari obeys them is a measured claim.
-/
namespace Fw.Engine.StyleDiffAccent
open Fw.Engine

/-- A property change a draw could use: the faithful dash offset, a clip-path on the `<svg>` box, a transform on an SVG
child (a mask rectangle), a transform on a composited box, an opacity inside the open interval, an opacity that
reaches 1, and the box width of the draw-in transition. -/
inductive Cand where
  | dashoffset | clipInset | transformSvgChild | transformOwn | opacityInside | opacityTo1 | width
deriving Repr, DecidableEq, Inhabited

/-- Every candidate once, in table order. -/
def Cand.all : List Cand :=
  [.dashoffset, .clipInset, .transformSvgChild, .transformOwn, .opacityInside, .opacityTo1, .width]

/-- A row of the table: the WebKit property and the layer state it is changed on, the Chromium key and its layer state,
and the source lines. -/
structure Row where
  name : String
  wk : WebKit.WkProp
  wkLayer : LayerState
  cr : Chromium.CrKey
  crLayer : LayerState
  cite : String

/-- **The canonical table.** -/
def row : Cand → Row
  | .dashoffset => ⟨"stroke-dashoffset", .strokeDashoffset, .none, .strokeDashoffset, .none,
      "WC/style/StyleDifference.cpp:161,399; B/css/css_properties.json5:6120; B/style/computed_style.cc:998-1006"⟩
  | .clipInset => ⟨"clip-path inset()", .clipPath, .layer, .clipPath, .layer,
      "WC/style/StyleDifference.cpp:779-780; WC/rendering/RenderElement.cpp:321-326; B/css/css_properties.json5:3112"⟩
  | .transformSvgChild => ⟨"transform of an SVG child", .transform, .none, .transform, .none,
      "WC/rendering/RenderElement.cpp:300-312; WC/style/StyleDifference.cpp:199-205"⟩
  | .transformOwn => ⟨"transform on a composited box", .transform, .own, .transform, .own,
      "WC/rendering/RenderElement.cpp:300-312; B/style/computed_style.cc:879-890"⟩
  | .opacityInside => ⟨"opacity inside (0,1)", .opacity, .none, .opacity, .none,
      "WC/style/StyleDifference.cpp:571-578; WC/rendering/RenderElement.cpp:314-319"⟩
  | .opacityTo1 => ⟨"opacity reaching 1", .opacityCross1, .none, .opacity, .none,
      "WC/style/StyleDifference.cpp:208-214"⟩
  | .width => ⟨"width", .size, .none, .width, .none,
      "WC/style/StyleDifference.cpp:404; B/css/css_properties.json5:8286"⟩

/-- Does one WebKit change of property `p` on a box in layer state `l` dirty layout? -/
def wkLayout (p : WebKit.WkProp) (l : LayerState) : Bool :=
  decide (Stage.layout ∈ WebKit.wkStages ⟨0, p, l⟩)

/-- Does one Chromium change of key `k` on a box in layer state `l` dirty layout? -/
def crLayout (k : Chromium.CrKey) (l : LayerState) : Bool :=
  decide (Stage.layout ∈ (Chromium.crLevel (.css k) l).stages)

/-- WebKit layout of a candidate, at the row's layer state. -/
def Cand.wkL (c : Cand) : Bool := wkLayout (row c).wk (row c).wkLayer

/-- Chromium layout of a candidate, at the row's layer state. -/
def Cand.crL (c : Cand) : Bool := crLayout (row c).cr (row c).crLayer

/-- Whether a candidate needs layout in neither engine. -/
def Cand.noLayout (c : Cand) : Bool := !c.wkL && !c.crL

/-- The two draw phases of the accent (each lasts 900 ms). -/
inductive Phase where
  | drawOut | drawIn
deriving Repr, DecidableEq

/-- Faithful per-frame changes: the dash offset of the three stacked copies, and in the draw-in the box width. -/
def faithfulFrame : Phase → List Cand
  | .drawOut => [.dashoffset, .dashoffset, .dashoffset]
  | .drawIn => [.dashoffset, .dashoffset, .dashoffset, .width]

/-- The arm's per-frame changes: one clip-path on the visible copy, and in the draw-in the box width (the width
transition is the original's and moves the headline text). -/
def armFrame : Phase → List Cand
  | .drawOut => [.clipInset]
  | .drawIn => [.clipInset, .width]

/-- Whether a frame with these changes runs layout in WebKit. -/
def wkFrameLayout (cs : List Cand) : Bool := cs.any Cand.wkL

/-- Whether a frame with these changes runs layout in Chromium. -/
def crFrameLayout (cs : List Cand) : Bool := cs.any Cand.crL

/-- Draw phases (of the two per cycle) whose frames run layout in WebKit. -/
def wkLayoutPhases (f : Phase → List Cand) : Nat := ([Phase.drawOut, .drawIn].filter fun p => wkFrameLayout (f p)).length

/-- The three layer states. -/
def layers : List LayerState := [.none, .layer, .own]

/-- **Faithful dash offset needs layout in WebKit.** On every layer state (CONFIRMED, `StyleDifference.cpp:161`). -/
theorem dashoffset_wk_layout : ∀ l ∈ layers, wkLayout .strokeDashoffset l = true := by decide

/-- **Faithful dash offset needs no layout in Chromium** (paint level). The faithful draw is already layout-free there,
so the arm cannot win a Layout row on Chromium. -/
theorem dashoffset_cr_nolayout : ∀ l ∈ layers, crLayout .strokeDashoffset l = false := by decide

/-- **clip-path needs no layout in either engine, on every layer state.** -/
theorem clip_nolayout : ∀ l ∈ layers, wkLayout .clipPath l = false ∧ crLayout .clipPath l = false := by decide

/-- **clip-path of a shape a layer can composite** also needs none (RecompositeLayer). -/
theorem clipShape_nolayout : ∀ l ∈ layers, wkLayout .clipPathShape l = false := by decide

/-- A transform on an SVG child (a mask rectangle) needs layout in WebKit (no layer, `RenderElement.cpp:305-306`). -/
theorem transformSvgChild_wk_layout : Cand.transformSvgChild.wkL = true := by decide

/-- A transform on a composited box needs none in either engine (but needs the compositing reason, which costs
layers; not chosen). -/
theorem transformOwn_nolayout : Cand.transformOwn.noLayout = true := by decide

/-- An opacity inside the open interval needs none; one that reaches 1 needs layout in WebKit
(`StyleDifference.cpp:208`). -/
theorem opacity_split : Cand.opacityInside.noLayout = true ∧ Cand.opacityTo1.wkL = true := by decide

/-- The box width needs layout in both engines. -/
theorem width_layout : Cand.width.wkL = true ∧ Cand.width.crL = true := by decide

/-- **The arm's draw-out frames need no layout in WebKit or Chromium.** -/
theorem arm_drawOut_nolayout : wkFrameLayout (armFrame .drawOut) = false ∧ crFrameLayout (armFrame .drawOut) = false := by
  decide

/-- **The arm's draw-in frames layout only through `width`**: every change that needs layout in either engine is the
width, and the width is present. -/
theorem arm_drawIn_layout_only_width :
    (∀ c ∈ armFrame .drawIn, (c.wkL = true ∨ c.crL = true) → c = .width) ∧ Cand.width ∈ armFrame .drawIn := by
  decide

/-- **Faithful draw-out frames need layout in WebKit, none in Chromium.** -/
theorem faithful_drawOut :
    wkFrameLayout (faithfulFrame .drawOut) = true ∧ crFrameLayout (faithfulFrame .drawOut) = false := by decide

/-- **Layout phases per cycle**: faithful 2 (both draws), arm 1 (the draw-in, by the width). -/
theorem layoutPhases_values : wkLayoutPhases faithfulFrame = 2 ∧ wkLayoutPhases armFrame = 1 := by decide

/-- **The arm never has more layout phases than faithful, and each one it keeps is a phase with a width change.** -/
theorem arm_phase_subset : ∀ p ∈ [Phase.drawOut, .drawIn], wkFrameLayout (armFrame p) = true → wkFrameLayout (faithfulFrame p) = true := by
  decide

/-- The clip inset on the right edge, in percent of the box width, for the hidden and the shown end. The other three
edges are `-20`, so strokes beyond the box stay visible in the shown end. -/
def hiddenRight : Int := 120
def shownRight : Int := -20
def edgeOut : Int := -20

/-- The visible x-range of the clip, in percent of the box, for a right inset. -/
def visibleRange (r : Int) : Int × Int := (edgeOut, 100 - r)

/-- **Endpoints equal the faithful endpoints.** Hidden: the clip range is empty (`hi ≤ lo`). Shown: it contains the
whole box [0, 100]. Mid-draw the clip is a wipe, the faithful draw a trace along the stroke: not pixel-identical. -/
theorem clip_endpoints :
    (visibleRange hiddenRight).2 ≤ (visibleRange hiddenRight).1 ∧
    (visibleRange shownRight).1 ≤ 0 ∧ 100 ≤ (visibleRange shownRight).2 := by decide

/-- The CSS value of the clip for a right inset. -/
def insetStr (r : Int) : String := s!"inset({edgeOut}% {r}% {edgeOut}% {edgeOut}%)"

/-- The `data-fw-draw` attribute a variant writes: `nolayout` for `draw-nolayout`, `one` for `draw-one`, none otherwise. -/
def attrOf (variant : String) : Option String :=
  if variant = "draw-nolayout" then some "nolayout" else if variant = "draw-one" then some "one" else none

#guard attrOf "draw-nolayout" == some "nolayout" && attrOf "faithful" == none
#guard insetStr hiddenRight == "inset(-20% 120% -20% -20%)"

private def diffName : WebKit.Diff → String
  | .equal => "equal" | .recomposite => "recomposite" | .repaint => "repaint" | .repaintIfText => "repaintIfText"
  | .repaintLayer => "repaintLayer" | .layoutOOFMoveOnly => "layoutOOFMoveOnly" | .overflow => "overflow"
  | .overflowOOF => "overflowOOF" | .layout => "layout" | .newStyle => "newStyle"

private def candRow (c : Cand) : Lean.Json :=
  let r := row c
  Lean.Json.mkObj
    [("cite", r.cite), ("crLayout", c.crL), ("crLevel", Chromium.levelName (Chromium.keyLevel r.cr r.crLayer)),
     ("kind", "cand"), ("name", r.name), ("wkDiff", diffName (WebKit.wkDiff ⟨0, r.wk, r.wkLayer⟩)),
     ("wkLayout", c.wkL)]

private def phaseName : Phase → String
  | .drawOut => "draw-out" | .drawIn => "draw-in"

private def frameRow (arm : Bool) (p : Phase) : Lean.Json :=
  let cs := if arm then armFrame p else faithfulFrame p
  Lean.Json.mkObj
    [("arm", if arm then "draw-nolayout" else "faithful"), ("changes", cs.length), ("crLayout", crFrameLayout cs),
     ("kind", "frame"), ("phase", phaseName p), ("wkLayout", wkFrameLayout cs)]

private def keyframeRows : List Lean.Json :=
  [Lean.Json.mkObj [("from", insetStr hiddenRight), ("kind", "keyframe"), ("name", "clipIn"), ("to", insetStr shownRight)],
   Lean.Json.mkObj [("from", insetStr shownRight), ("kind", "keyframe"), ("name", "clipOut"), ("to", insetStr hiddenRight)]]

private def attrRows : List Lean.Json :=
  ["faithful", "steps", "draw-one", "draw-nolayout"].map fun v =>
    Lean.Json.mkObj [("attr", match attrOf v with | some a => Lean.Json.str a | none => Lean.Json.null),
      ("kind", "attr"), ("variant", v)]

/-- The golden text (`packages/contracts/golden/parts/hero.accent.nolayout.jsonl`). -/
def goldenText : String :=
  String.join
    ((Cand.all.map candRow ++
      ([false, true].flatMap fun a => [Phase.drawOut, .drawIn].map fun p => frameRow a p) ++
      keyframeRows ++ attrRows).map fun r => r.compress ++ "\n")

/-- Prints the golden text, or with `--check <path>` compares it with the file. -/
def run (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    let cur ← IO.FS.readFile path
    if cur == goldenText then
      IO.eprintln s!"accent nolayout golden: {path} is up to date"
      return 0
    IO.eprintln s!"accent nolayout golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print goldenText
    return 0

end Fw.Engine.StyleDiffAccent

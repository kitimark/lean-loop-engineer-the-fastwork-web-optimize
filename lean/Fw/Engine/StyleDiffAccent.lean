import Lean.Data.Json
import Fw.Engine
/-! WebKit @862f17d and Chromium @f842f52 StyleDifference of the hero.accent draw candidates; cites in `row`. -/
namespace Fw.Engine.StyleDiffAccent
open Fw.Engine

inductive Cand where
  | dashoffset | clipInset | transformSvgChild | transformOwn | opacityInside | opacityTo1 | width
deriving Repr, DecidableEq, Inhabited

def Cand.all : List Cand :=
  [.dashoffset, .clipInset, .transformSvgChild, .transformOwn, .opacityInside, .opacityTo1, .width]

structure Row where
  name : String
  wk : WebKit.WkProp
  wkLayer : LayerState
  cr : Chromium.CrKey
  crLayer : LayerState
  cite : String

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

def wkLayout (p : WebKit.WkProp) (l : LayerState) : Bool :=
  decide (Stage.layout ∈ WebKit.wkStages ⟨0, p, l⟩)

def crLayout (k : Chromium.CrKey) (l : LayerState) : Bool :=
  decide (Stage.layout ∈ (Chromium.crLevel (.css k) l).stages)

def Cand.wkL (c : Cand) : Bool := wkLayout (row c).wk (row c).wkLayer

def Cand.crL (c : Cand) : Bool := crLayout (row c).cr (row c).crLayer

def Cand.noLayout (c : Cand) : Bool := !c.wkL && !c.crL

inductive Phase where
  | drawOut | drawIn
deriving Repr, DecidableEq

def faithfulFrame : Phase → List Cand
  | .drawOut => [.dashoffset, .dashoffset, .dashoffset]
  | .drawIn => [.dashoffset, .dashoffset, .dashoffset, .width]

def armFrame : Phase → List Cand
  | .drawOut => [.clipInset]
  | .drawIn => [.clipInset, .width]

def wkFrameLayout (cs : List Cand) : Bool := cs.any Cand.wkL

def crFrameLayout (cs : List Cand) : Bool := cs.any Cand.crL

def wkLayoutPhases (f : Phase → List Cand) : Nat := ([Phase.drawOut, .drawIn].filter fun p => wkFrameLayout (f p)).length

def layers : List LayerState := [.none, .layer, .own]

theorem dashoffset_wk_layout : ∀ l ∈ layers, wkLayout .strokeDashoffset l = true := by decide

theorem dashoffset_cr_nolayout : ∀ l ∈ layers, crLayout .strokeDashoffset l = false := by decide

theorem clip_nolayout : ∀ l ∈ layers, wkLayout .clipPath l = false ∧ crLayout .clipPath l = false := by decide

theorem clipShape_nolayout : ∀ l ∈ layers, wkLayout .clipPathShape l = false := by decide

theorem transformSvgChild_wk_layout : Cand.transformSvgChild.wkL = true := by decide

theorem transformOwn_nolayout : Cand.transformOwn.noLayout = true := by decide

theorem opacity_split : Cand.opacityInside.noLayout = true ∧ Cand.opacityTo1.wkL = true := by decide

theorem width_layout : Cand.width.wkL = true ∧ Cand.width.crL = true := by decide

theorem arm_drawOut_nolayout : wkFrameLayout (armFrame .drawOut) = false ∧ crFrameLayout (armFrame .drawOut) = false := by
  decide

theorem arm_drawIn_layout_only_width :
    (∀ c ∈ armFrame .drawIn, (c.wkL = true ∨ c.crL = true) → c = .width) ∧ Cand.width ∈ armFrame .drawIn := by
  decide

theorem faithful_drawOut :
    wkFrameLayout (faithfulFrame .drawOut) = true ∧ crFrameLayout (faithfulFrame .drawOut) = false := by decide

theorem layoutPhases_values : wkLayoutPhases faithfulFrame = 2 ∧ wkLayoutPhases armFrame = 1 := by decide

theorem arm_phase_subset : ∀ p ∈ [Phase.drawOut, .drawIn], wkFrameLayout (armFrame p) = true → wkFrameLayout (faithfulFrame p) = true := by
  decide

def hiddenRight : Int := 120
def shownRight : Int := -20
def edgeOut : Int := -20

def visibleRange (r : Int) : Int × Int := (edgeOut, 100 - r)

theorem clip_endpoints :
    (visibleRange hiddenRight).2 ≤ (visibleRange hiddenRight).1 ∧
    (visibleRange shownRight).1 ≤ 0 ∧ 100 ≤ (visibleRange shownRight).2 := by decide

def insetStr (r : Int) : String := s!"inset({edgeOut}% {r}% {edgeOut}% {edgeOut}%)"

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

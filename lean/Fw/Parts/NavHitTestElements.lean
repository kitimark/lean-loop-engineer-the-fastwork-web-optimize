import Lean.Data.Json
import Fw.Parts.NavHitTest
import Fw.Parts.NavHitTestOpt

/-! nav.hitTest: the faithful probe (`pointer-events: none` on the nav, `elementFromPoint`, restore) and `elements-skip`
(`elementsFromPoint`, skip the nav's own boxes) decide the same `is-on-dark` class, and only the faithful one dirties style. -/
namespace Fw.Parts.NavHitTestElements

open Lean (Json)
open Fw.Parts.NavHitTest (HitFlags classifyHit isOnDark)
open Fw.Parts.EngineScroll (Access Role styleRole layoutRole)

inductive Src where
  | fixed (hit : Bool)
  | root
deriving Repr, BEq, DecidableEq

structure Box where
  insideNav : Bool
  src : Src
  allow : Bool
  inExclude : Bool
  inInclude : Bool
  inShrinking : Bool
deriving Repr, BEq, DecidableEq

/-- Used `pointer-events` is not `none`: a box inherits the nav root's value unless a declaration at or below it
(inside the nav) or outside the nav sets it. Inheritance: Chromium
`third_party/blink/renderer/core/css/css_properties.json5:5316-5320`@f842f52, WebKit
`Source/WebCore/css/CSSProperties.json:7872-7874`@862f17d. -/
def usedHit (rootHit : Bool) (b : Box) : Bool :=
  match b.src with
  | .fixed h => h
  | .root => rootHit

/-- The boxes a hit test reports at the probe point, top-most first, from the paint-order boxes `g` under the point: a
box with used `pointer-events: none` is skipped, its descendants are still tested. Chromium
`third_party/blink/renderer/core/paint/box_fragment_painter.cc:139-143,2373-2377`@f842f52 and
`layout/layout_object.h:2738-2743`@f842f52; WebKit `Source/WebCore/rendering/RenderElementStyleInlines.h:162-168`,
`RenderBlock.cpp:2084-2086`, `RenderBox.cpp:1721`@862f17d. Neither request sets the ignore-pointer-events flag. -/
def hitList (rootHit : Bool) (g : List Box) : List Box := g.filter (usedHit rootHit)

def htmlBox : Box := ⟨false, .fixed true, false, false, false, false⟩

/-- `elementsFromPoint`: the penetrating list hit test, then the document element appended. Chromium
`third_party/blink/renderer/core/dom/tree_scope.cc:396-437`@f842f52; WebKit `Source/WebCore/dom/TreeScope.cpp:436-490`@862f17d. -/
def elementsFromPoint (rootHit : Bool) (g : List Box) : List Box := hitList rootHit g ++ [htmlBox]

/-- `elementFromPoint`: the first box of the same walk, or null. Chromium `tree_scope.cc:268-302`@f842f52; WebKit
`TreeScope.cpp:402-434`@862f17d. -/
def elementFromPoint (rootHit : Bool) (g : List Box) : Option Box := (hitList rootHit g).head?

def classOf : Option Box → Bool
  | none => false
  | some b => classifyHit ⟨true, b.inExclude, b.inInclude, b.inShrinking⟩

def probeFaithful (g : List Box) : Bool := classOf (elementFromPoint false g)

def skipSel (b : Box) : Bool := !b.insideNav || b.allow

def probeElements (rootHit : Bool) (g : List Box) : Bool := classOf ((elementsFromPoint rootHit g).find? skipSel)

/-- Site premises on the boxes under the probe. Outside the nav the root's value never reaches a box (inheritance runs
to DOM descendants only, and `nav.contains` is the DOM subtree). Inside the nav, `closest(ALLOW_SELECTOR)` holds on
exactly the boxes whose own or nav-internal ancestor declaration lets hits through, and never on a box that inherits
from the root: `apps/site/src/parts/nav/nav.module.css:128-132,177,186-200`, `morph.panel/morph.module.css:12-20`,
`nav.hitTest/logic.ts:87-88`. -/
def Premises (g : List Box) : Prop :=
  ∀ b ∈ g, (b.insideNav = false → b.src ≠ .root) ∧
    (b.insideNav = true → (b.allow = true → b.src ≠ .root) ∧ (b.src = .fixed true → b.allow = true))

instance (g : List Box) : Decidable (Premises g) := by unfold Premises; infer_instance

theorem find?_congr {α : Type} (p q : α → Bool) (l : List α) (h : ∀ a ∈ l, p a = q a) : l.find? p = l.find? q := by
  induction l with
  | nil => rfl
  | cons a l ih =>
    simp only [List.find?_cons, h a (by simp), ih (fun b hb => h b (by simp [hb]))]

theorem sel_eq (r : Bool) (b : Box)
    (hb : (b.insideNav = false → b.src ≠ .root) ∧
      (b.insideNav = true → (b.allow = true → b.src ≠ .root) ∧ (b.src = .fixed true → b.allow = true))) :
    (usedHit r b && skipSel b) = usedHit false b := by
  obtain ⟨hout, hin⟩ := hb
  cases hi : b.insideNav
  · have hs := hout hi
    cases hsrc : b.src with
    | root => exact absurd hsrc hs
    | fixed h => simp [usedHit, skipSel, hi, hsrc]
  · obtain ⟨ha, hf⟩ := hin hi
    cases hsrc : b.src with
    | root =>
      cases hal : b.allow
      · simp [usedHit, skipSel, hi, hsrc, hal]
      · exact absurd hsrc (ha hal)
    | fixed h =>
      cases h
      · simp [usedHit, hsrc]
      · simp [usedHit, skipSel, hi, hsrc, hf hsrc]

/-- The elements stack's first non-skipped box is the faithful hit, for every normal state `r` of the nav root. -/
theorem elements_find_eq (r : Bool) (g : List Box) (h : Premises g) :
    (hitList r g).find? skipSel = elementFromPoint false g := by
  unfold elementFromPoint hitList
  rw [List.find?_filter, List.head?_filter]
  exact find?_congr _ _ g (fun b hb => by simpa using sel_eq r b (h b hb))

theorem classOf_html : classOf (some htmlBox) = false := by decide

/-- Same class: the hit answer of `elements-skip` equals the faithful probe's. -/
theorem same_class (r : Bool) (g : List Box) (h : Premises g) : probeElements r g = probeFaithful g := by
  unfold probeElements probeFaithful elementsFromPoint
  rw [List.find?_append, elements_find_eq r g h]
  cases elementFromPoint false g with
  | some y => rfl
  | none => exact classOf_html

/-- Same `is-on-dark` class on the frame, at every morph. -/
theorem same_onDark (r : Bool) (g : List Box) (m : Rat) (h : Premises g) :
    isOnDark (probeElements r g) m = isOnDark (probeFaithful g) m := by
  rw [same_class r g h]

/-- Every frame of a run: the class sequence of `elements-skip` equals the faithful one. -/
theorem same_onDark_run (run : List (Bool × List Box × Rat)) (h : ∀ f ∈ run, Premises f.2.1) :
    run.map (fun f => isOnDark (probeElements f.1 f.2.1) f.2.2) = run.map (fun f => isOnDark (probeFaithful f.2.1) f.2.2) := by
  apply List.map_congr_left
  intro f hf
  exact same_onDark f.1 f.2.1 f.2.2 (h f hf)

/-- The index model `NavHitTest.faithfulHit` uses (first box outside the nav or re-enabled inside it, on the
`elementsFromPoint` stack) follows from the engine premises with `allow` read as "re-enabled". -/
theorem faithful_is_first_reEnabled (r : Bool) (g : List Box) (h : Premises g) :
    elementFromPoint false g = (hitList r g).find? (fun b => !b.insideNav || b.allow) :=
  (elements_find_eq r g h).symm

def actionsBox : Box := ⟨true, .fixed true, true, false, false, false⟩
def barBox : Box := ⟨true, .root, false, false, false, false⟩
def painBox : Box := ⟨false, .fixed true, false, false, true, false⟩

/-- The allow-list premise is needed: an allow-listed box that inherits from the root makes the answers differ. -/
theorem needs_allow_not_root :
    probeElements true [⟨true, .root, true, false, false, false⟩, painBox] ≠
      probeFaithful [⟨true, .root, true, false, false, false⟩, painBox] := by decide

/-- The allow-list premise is needed: a re-enabled box missing from the allow-list makes the answers differ. -/
theorem needs_allow_reEnabled :
    probeElements true [⟨true, .fixed true, false, false, false, false⟩, painBox] ≠
      probeFaithful [⟨true, .fixed true, false, false, false, false⟩, painBox] := by decide

/-- The outside premise is needed: an outside box that tracked the nav root would make the answers differ. -/
theorem needs_outside_fixed :
    probeElements true [⟨false, .root, false, false, true, false⟩] ≠
      probeFaithful [⟨false, .root, false, false, true, false⟩] := by decide

#guard probeFaithful [barBox, painBox] == true && probeElements true [barBox, painBox] == true
#guard probeFaithful [actionsBox, painBox] == false && probeElements true [actionsBox, painBox] == false
#guard probeFaithful [] == false && probeElements false [] == false
#guard probeElements false [barBox, painBox] == true

/-! No style invalidation from the toggle. The faithful probe's two inline writes are the only dirtying accesses:
Chromium `InlineCSSStyleDeclaration::DidMutate` → `Element::InvalidateStyleAttribute` → `SetNeedsStyleRecalc`
(`third_party/blink/renderer/core/css/inline_css_style_declaration.cc:36-53`, `dom/element.cc:13299-13308`@f842f52),
paid at the next hit test's `UpdateStyleAndLayout(kHitTest)` (`dom/tree_scope.cc:232`@f842f52); WebKit
`InlineCSSStyleProperties::didMutate` → `StyledElement::invalidateStyleAttribute` → `Node::invalidateStyle`
(`Source/WebCore/css/CSSStyleProperties.cpp:622-643`, `dom/StyledElement.cpp:190-204`@862f17d), paid at
`Document::hitTest` → `updateLayout` (`dom/Document.cpp:11545-11546`@862f17d). -/

def dirtying (ρ : Access → Role) (as : List Access) : List Access := as.filter (fun a => ρ a == .dirty)

theorem elements_no_style_dirt : dirtying styleRole NavHitTestOpt.probeElements = [] := by decide

theorem faithful_style_dirt : dirtying styleRole NavHitTestOpt.probeFaithful = [.writeStyle, .writeStyle] := by decide

theorem probes_no_layout_dirt :
    dirtying layoutRole NavHitTestOpt.probeElements = [] ∧ dirtying layoutRole NavHitTestOpt.probeFaithful = [] := by
  decide

theorem dirtying_append (ρ : Access → Role) (as bs : List Access) :
    dirtying ρ (as ++ bs) = dirtying ρ as ++ dirtying ρ bs := List.filter_append ..

/-- In every frame context, `elements-skip` adds no style invalidation: the frame's dirtying accesses are those of the
callbacks around the probe. -/
theorem elements_frame_no_style_dirt (pre post : List Access) :
    dirtying styleRole (pre ++ NavHitTestOpt.probeElements ++ post) = dirtying styleRole (pre ++ post) := by
  simp only [dirtying_append, elements_no_style_dirt, List.append_nil]

/-- In every frame context, the faithful probe adds exactly its two `pointer-events` writes. -/
theorem faithful_frame_style_dirt (pre post : List Access) :
    (dirtying styleRole (pre ++ NavHitTestOpt.probeFaithful ++ post)).length = (dirtying styleRole (pre ++ post)).length + 2 := by
  simp only [dirtying_append, faithful_style_dirt, List.length_append]
  simp
  omega

/-! Golden: `packages/contracts/golden/parts/nav.hitTest.elements.jsonl`. -/

def srcWire : Src → String
  | .root => "root"
  | .fixed true => "auto"
  | .fixed false => "none"

def boxJson (b : Box) : Json :=
  Json.mkObj [("insideNav", .bool b.insideNav), ("src", .str (srcWire b.src)), ("allow", .bool b.allow),
    ("inExclude", .bool b.inExclude), ("inInclude", .bool b.inInclude), ("inShrinking", .bool b.inShrinking)]

def ratJson (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

def sceneLine (rootHit : Bool) (g : List Box) (m : Rat) : String :=
  (Json.mkObj [("fn", .str "probes"),
    ("in", Json.mkObj [("rootHit", .bool rootHit), ("stack", .arr (g.map boxJson).toArray), ("morph", ratJson m)]),
    ("out", Json.mkObj [("premises", .bool (decide (Premises g))), ("faithful", .bool (probeFaithful g)),
      ("elements", .bool (probeElements rootHit g)), ("onDarkFaithful", .bool (isOnDark (probeFaithful g) m)),
      ("onDarkElements", .bool (isOnDark (probeElements rootHit g) m))])]).compress

def kinds : List Box :=
  [barBox, actionsBox, ⟨true, .fixed false, true, false, false, false⟩, ⟨true, .fixed false, false, false, false, false⟩,
   ⟨false, .fixed true, false, false, false, false⟩, painBox, ⟨false, .fixed true, false, true, true, false⟩,
   ⟨false, .fixed true, false, false, false, true⟩, ⟨false, .fixed false, false, false, true, false⟩]

def stacks : List (List Box) := [[]] ++ kinds.map ([·]) ++ kinds.flatMap (fun a => kinds.map (fun b => [a, b]))

def morphs : List Rat := [0, 1 / 5, 1 / 4]

def scenes : List (Bool × List Box × Rat) :=
  [(true, [barBox, ⟨true, .root, false, false, false, false⟩, painBox], 0),
   (true, [⟨true, .fixed true, true, false, false, false⟩, actionsBox, barBox, painBox], 0),
   (true, [⟨true, .fixed true, true, false, false, false⟩, ⟨true, .fixed true, true, false, false, false⟩, painBox], 24 / 25),
   (true, [⟨true, .fixed false, false, false, false, false⟩, barBox, ⟨false, .fixed true, false, true, true, false⟩], 1 / 10),
   (false, [barBox, painBox], 0),
   (true, [], 0),
   (true, [⟨true, .root, true, false, false, false⟩, painBox], 0),
   (true, [⟨true, .fixed true, false, false, false, false⟩, painBox], 0),
   (true, [⟨false, .root, false, false, true, false⟩], 0)]

/-- The golden lines: named scenes, then every stack of at most two box kinds for both root states and three morphs. -/
def goldenLines : List String :=
  scenes.map (fun (r, g, m) => sceneLine r g m) ++
    stacks.flatMap (fun g => [true, false].flatMap (fun r => morphs.map (fun m => sceneLine r g m)))

theorem stacks_premises : ∀ g ∈ stacks, Premises g := by decide

#guard goldenLines.length == 9 + 91 * 6

def path : String := "../packages/contracts/golden/parts/nav.hitTest.elements.jsonl"

def text : String := String.join (goldenLines.map (· ++ "\n"))

/-- Write the golden file, or with `--check` fail when it differs from `goldenLines`. -/
def gen (args : List String) : IO Unit := do
  if args.contains "--check" then
    let disk ← IO.FS.readFile path
    if disk != text then throw (IO.userError s!"nav.hitTest.elements: {path} is stale; regenerate with Fw.Parts.NavHitTestElements.gen []")
    IO.println s!"nav.hitTest.elements: {path} equals the Lean output, {goldenLines.length} lines"
  else
    IO.FS.writeFile path text

end Fw.Parts.NavHitTestElements

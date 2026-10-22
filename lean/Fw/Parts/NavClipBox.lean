import Lean.Data.Json
import Fw.Parts.Nav
import Fw.Parts.NavHitTest
/-!
# nav clip box: the nav at a constant union box, the pill drawn as a clip (`nav:clip-box`)
Spec of `apps/site/src/parts/nav/nav.module.css` (rules under `.is-morphing` without `.is-locale-open`) and of the probe in nav.hitTest.
-/
namespace Fw.Parts.NavClipBox
open Fw.Parts.Nav
open Fw.Parts.NavHitTest (Rect hitPoint)

/-- The box of the nav as the original lays it out (`navLeft` is the `left: 50%` centring). -/
def origRect (v : Vp) (m : Rat) : Rect :=
  ⟨(v.w - navWidth v false m) / 2, navTop v m, navWidth v false m, navHeight v m⟩

/-- Union box width: the panel width, which no pill width exceeds (`panel_ge_pill`). -/
def unionW (v : Vp) : Rat := panelW v

/-- Union box top: the least `navTop` over the morph. -/
def unionTop (v : Vp) : Rat := if phone v.w then 12 else 16

/-- Union box height: from the top to the greatest `navTop + navHeight` over the morph. -/
def unionH (v : Vp) : Rat := panelH v + if phone v.w then 0 else 4

/-- The union box, centred like the nav. -/
def unionRect (v : Vp) : Rect := ⟨(v.w - unionW v) / 2, unionTop v, unionW v, unionH v⟩

/-- Distances from the union box to the pill, left and right equal. -/
structure Insets where
  x : Rat
  t : Rat
  b : Rat
deriving Repr, BEq, DecidableEq

/-- The insets as the CSS custom properties `--box-ix`, `--box-it`, `--box-ib` compute them. -/
def insets (v : Vp) (m : Rat) : Insets :=
  ⟨(panelW v - pillW v) * (1 - m) / 2,
   if phone v.w then 4 * (1 - m) else 4 * m,
   (panelH v - pillH v + if phone v.w then -4 else 4) * (1 - m)⟩

/-- The rectangle `clip-path: inset(t x b x)` leaves visible in the union box. -/
def clipRect (v : Vp) (m : Rat) : Rect :=
  let i := insets v m
  ⟨(unionRect v).left + i.x, unionTop v + i.t, unionW v - i.x - i.x, unionH v - i.t - i.b⟩

/-- The corner radius of the clip; the box itself has radius 0. -/
def clipRadius (m : Rat) : Rat := navRadius m

/-- The rule applies while the nav morphs and its locale menu is closed. -/
def active (m : Rat) (localeOpen : Bool) : Bool := decide (morphingCut < m) && !localeOpen

/-- The border box the nav has under the flag. -/
def navBox (v : Vp) (m : Rat) (localeOpen : Bool) : Rect := if active m localeOpen then unionRect v else origRect v m

/-- The region the nav shows under the flag. -/
def visibleRect (v : Vp) (m : Rat) (localeOpen : Bool) : Rect := if active m localeOpen then clipRect v m else origRect v m

/-- Union, clip and original agree on the pill, on every viewport and every morph value. -/
theorem box_eq (v : Vp) (m : Rat) : clipRect v m = origRect v m := by
  have h := panel_ge_pill v
  unfold clipRect origRect unionRect unionW unionTop unionH insets navWidth navHeight navTop pillW panelW panelH pillH at *
  cases hph : phone v.w <;> simp only [Rect.mk.injEq] <;> refine ⟨?_, ?_, ?_, ?_⟩ <;> grind

/-- The insets are the CSS closed forms; each branch of the phone band checked on its own. -/
theorem insets_phone (v : Vp) (m : Rat) (h : phone v.w = true) :
    insets v m = ⟨(panelW v - pillW v) * (1 - m) / 2, 4 * (1 - m), (panelH v - pillH v - 4) * (1 - m)⟩ := by
  simp [insets, h]
  grind

/-- The insets of the wide band. -/
theorem insets_wide (v : Vp) (m : Rat) (h : phone v.w = false) :
    insets v m = ⟨(panelW v - pillW v) * (1 - m) / 2, 4 * m, (panelH v - pillH v + 4) * (1 - m)⟩ := by
  simp [insets, h]

/-- Why the union box: all three insets are non-negative, so the pill lies inside it for `0 ≤ m ≤ 1`. -/
theorem insets_nonneg (v : Vp) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) (hv : pillH v + 4 ≤ panelH v) :
    0 ≤ (insets v m).x ∧ 0 ≤ (insets v m).t ∧ 0 ≤ (insets v m).b := by
  have hw := panel_ge_pill v
  have a := Rat.mul_nonneg (show 0 ≤ panelW v - pillW v by grind) (show 0 ≤ 1 - m by grind)
  have b := Rat.mul_nonneg (show 0 ≤ panelH v - pillH v - 4 by grind) (show 0 ≤ 1 - m by grind)
  have c := Rat.mul_nonneg (show 0 ≤ panelH v - pillH v + 4 by grind) (show 0 ≤ 1 - m by grind)
  unfold insets
  cases hph : phone v.w <;> simp <;> refine ⟨?_, ?_, ?_⟩ <;> grind

/-- Above the morphing cut with the menu closed the box is the same for every morph value. -/
theorem union_const (v : Vp) (m m' : Rat) (h : morphingCut < m) (h' : morphingCut < m') :
    navBox v m false = navBox v m' false := by
  have a : active m false = true := by simp [active, h]
  have b : active m' false = true := by simp [active, h']
  simp [navBox, a, b]

/-- The `width` the rule declares while it applies: the pill width, constant in the morph. The box reaches the union
width through `min-width`, which the original's transition lists do not name. -/
def declW (v : Vp) : Rat := pillW v

/-- The `min-width` the rule declares while it applies. -/
def minW (v : Vp) : Rat := panelW v

/-- The used width: the greater of `width` and `min-width`. -/
def usedW (v : Vp) : Rat := max (declW v) (minW v)

/-- The declared width the original has at rest (no hero pill; `--nav-expand` is 1 while it morphs). -/
def restW (v : Vp) (m : Rat) : Rat := navWidth v false m

/-- The used width of the rule is the union width. -/
theorem usedW_eq_unionW (v : Vp) : usedW v = unionW v := by
  have h := panel_ge_pill v
  unfold usedW declW minW unionW
  grind

/-- Where the morph ends at 0 the rest width is the declared width, so dropping `.is-morphing` starts no width transition. -/
theorem decl_eq_rest_zero (v : Vp) : declW v = restW v 0 := by
  unfold declW restW navWidth
  grind

/-- Where `.is-morphing` is dropped (`m` at most the cut) the declared width differs from the rest width by at most
the cut times the panel overhang, the same step the original's own width takes in that frame. -/
theorem decl_close_rest (v : Vp) (m : Rat) (h0 : 0 ≤ m) (h : m ≤ morphingCut) :
    0 ≤ restW v m - declW v ∧ restW v m - declW v ≤ morphingCut * (panelW v - pillW v) := by
  have hp := panel_ge_pill v
  have a := Rat.mul_nonneg (show 0 ≤ panelW v - pillW v by grind) h0
  have b : (panelW v - pillW v) * m ≤ (panelW v - pillW v) * morphingCut :=
    Rat.mul_le_mul_of_nonneg_left h (by grind)
  unfold restW declW navWidth
  refine ⟨by grind, by grind⟩

/-- Where the morph ends at 1 the box stays active and its used width is the original's width. -/
theorem used_eq_rest_one (v : Vp) : usedW v = restW v 1 := by
  rw [usedW_eq_unionW]
  unfold unionW restW navWidth
  grind

/-- Layout happens only at the endpoints: two morph values with the menu closed that give different boxes have one at
or below the cut. Above the cut the box never changes (`union_const`), so a frame inside the morph lays out nothing. -/
theorem layout_only_at_endpoints (v : Vp) (m m' : Rat) (h : navBox v m false ≠ navBox v m' false) :
    m ≤ morphingCut ∨ m' ≤ morphingCut := by
  by_cases a : m ≤ morphingCut
  · exact Or.inl a
  by_cases b : m' ≤ morphingCut
  · exact Or.inr b
  exfalso
  refine h (union_const v m m' ?_ ?_)
  all_goals grind

/-- At or below the morphing cut the flag changes nothing: box and visible region are the original's. -/
theorem rest_same_morph (v : Vp) (m : Rat) (l : Bool) (h : m ≤ morphingCut) :
    navBox v m l = origRect v m ∧ visibleRect v m l = origRect v m := by
  have a : active m l = false := by simp [active]; grind
  simp [navBox, visibleRect, a]

/-- With the locale menu open the flag changes nothing, at every morph value. -/
theorem rest_same_locale (v : Vp) (m : Rat) :
    navBox v m true = origRect v m ∧ visibleRect v m true = origRect v m := by
  simp [navBox, visibleRect, active]

/-- The shown region is the original's box in both branches of the rule. -/
theorem visible_eq (v : Vp) (m : Rat) (l : Bool) : visibleRect v m l = origRect v m := by
  unfold visibleRect
  split
  · exact box_eq v m
  · rfl

/-- The probe point of the shown region is the original's probe point. -/
theorem probe_eq (v : Vp) (m : Rat) (l : Bool) : hitPoint (visibleRect v m l) = hitPoint (origRect v m) := by
  rw [visible_eq]

/-- Reading the union box instead would move the probe: at 390 x 844 and m = 1/100 the y values differ. -/
theorem probe_union_ne : hitPoint (unionRect ⟨390, 844⟩) ≠ hitPoint (origRect ⟨390, 844⟩ (1 / 100)) := by
  decide +kernel

#guard unionRect ⟨430, 932⟩ == ⟨12, 12, 406, 908⟩
#guard unionRect ⟨1280, 800⟩ == ⟨20, 16, 1240, 764⟩
#guard clipRect ⟨1280, 800⟩ 1 == origRect ⟨1280, 800⟩ 1
#guard (insets ⟨1280, 800⟩ 0).b == 700 && (insets ⟨390, 844⟩ 0).t == 4

/-- A rational as the JSON wire form `{"num","den"}`. -/
def jrat (q : Rat) : Lean.Json := Lean.Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

/-- Viewports on both sides of the 640 px edge and the usual sizes. -/
def viewports : List (Rat × Rat) :=
  [(375, 667), (390, 844), (430, 932), (640, 900), (641, 900), (768, 1024), (1000, 700), (1280, 800), (1440, 900), (1920, 1080)]

/-- Morph values around the cuts. -/
def samples : List Rat := [0, 1 / 1000, 11 / 10000, 1 / 20, 1 / 5, 2 / 5, 1 / 2, 4 / 5, 23 / 25, 1]

/-- Golden rows of `nav-clip-box.jsonl`. -/
def rows (_ : Unit := ()) : List String :=
  viewports.flatMap fun (w, h) => samples.map fun m =>
    let v : Vp := ⟨w, h⟩
    let i := insets v m
    let o := origRect v m
    let u := unionRect v
    let p := hitPoint o
    (Lean.Json.mkObj [("vw", jrat w), ("vh", jrat h), ("m", jrat m), ("active", .bool (active m false)),
      ("unionL", jrat u.left), ("unionT", jrat u.top), ("unionW", jrat u.width), ("unionH", jrat u.height),
      ("insetX", jrat i.x), ("insetT", jrat i.t), ("insetB", jrat i.b), ("radius", jrat (clipRadius m)),
      ("origL", jrat o.left), ("origT", jrat o.top), ("origW", jrat o.width), ("origH", jrat o.height),
      ("probeX", jrat p.1), ("probeY", jrat p.2)]).compress

/-- File contents of `packages/contracts/golden/parts/nav-clip-box.jsonl`. -/
def jsonl (_ : Unit := ()) : String := String.join ((rows ()).map (· ++ "\n"))

#guard (rows ()).length == 100

#guard jsonl () == include_str "../../../packages/contracts/golden/parts/nav-clip-box.jsonl"

end Fw.Parts.NavClipBox

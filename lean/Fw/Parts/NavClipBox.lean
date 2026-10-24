import Lean.Data.Json
import Fw.Parts.Nav
import Fw.Parts.NavHitTest
namespace Fw.Parts.NavClipBox
open Fw.Parts.Nav
open Fw.Parts.NavHitTest (Rect hitPoint)

def origRect (v : Vp) (m : Rat) : Rect :=
  ⟨(v.w - navWidth v false m) / 2, navTop v m, navWidth v false m, navHeight v m⟩

def unionW (v : Vp) : Rat := panelW v

def unionTop (v : Vp) : Rat := if phone v.w then 12 else 16

def unionH (v : Vp) : Rat := panelH v + if phone v.w then 0 else 4

def unionRect (v : Vp) : Rect := ⟨(v.w - unionW v) / 2, unionTop v, unionW v, unionH v⟩

structure Insets where
  x : Rat
  t : Rat
  b : Rat
deriving Repr, BEq, DecidableEq

def insets (v : Vp) (m : Rat) : Insets :=
  ⟨(panelW v - pillW v) * (1 - m) / 2,
   if phone v.w then 4 * (1 - m) else 4 * m,
   (panelH v - pillH v + if phone v.w then -4 else 4) * (1 - m)⟩

def clipRect (v : Vp) (m : Rat) : Rect :=
  let i := insets v m
  ⟨(unionRect v).left + i.x, unionTop v + i.t, unionW v - i.x - i.x, unionH v - i.t - i.b⟩

def clipRadius (m : Rat) : Rat := navRadius m

def active (m : Rat) (localeOpen : Bool) : Bool := decide (morphingCut < m) && !localeOpen

def navBox (v : Vp) (m : Rat) (localeOpen : Bool) : Rect := if active m localeOpen then unionRect v else origRect v m

def visibleRect (v : Vp) (m : Rat) (localeOpen : Bool) : Rect := if active m localeOpen then clipRect v m else origRect v m

theorem box_eq (v : Vp) (m : Rat) : clipRect v m = origRect v m := by
  have h := panel_ge_pill v
  unfold clipRect origRect unionRect unionW unionTop unionH insets navWidth navHeight navTop pillW panelW panelH pillH at *
  cases hph : phone v.w <;> simp only [Rect.mk.injEq] <;> refine ⟨?_, ?_, ?_, ?_⟩ <;> grind

theorem insets_phone (v : Vp) (m : Rat) (h : phone v.w = true) :
    insets v m = ⟨(panelW v - pillW v) * (1 - m) / 2, 4 * (1 - m), (panelH v - pillH v - 4) * (1 - m)⟩ := by
  simp [insets, h]
  grind

theorem insets_wide (v : Vp) (m : Rat) (h : phone v.w = false) :
    insets v m = ⟨(panelW v - pillW v) * (1 - m) / 2, 4 * m, (panelH v - pillH v + 4) * (1 - m)⟩ := by
  simp [insets, h]

theorem insets_nonneg (v : Vp) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) (hv : pillH v + 4 ≤ panelH v) :
    0 ≤ (insets v m).x ∧ 0 ≤ (insets v m).t ∧ 0 ≤ (insets v m).b := by
  have hw := panel_ge_pill v
  have a := Rat.mul_nonneg (show 0 ≤ panelW v - pillW v by grind) (show 0 ≤ 1 - m by grind)
  have b := Rat.mul_nonneg (show 0 ≤ panelH v - pillH v - 4 by grind) (show 0 ≤ 1 - m by grind)
  have c := Rat.mul_nonneg (show 0 ≤ panelH v - pillH v + 4 by grind) (show 0 ≤ 1 - m by grind)
  unfold insets
  cases hph : phone v.w <;> simp <;> refine ⟨?_, ?_, ?_⟩ <;> grind

theorem union_const (v : Vp) (m m' : Rat) (h : morphingCut < m) (h' : morphingCut < m') :
    navBox v m false = navBox v m' false := by
  have a : active m false = true := by simp [active, h]
  have b : active m' false = true := by simp [active, h']
  simp [navBox, a, b]

def declW (v : Vp) : Rat := pillW v

def minW (v : Vp) : Rat := panelW v

def usedW (v : Vp) : Rat := max (declW v) (minW v)

def restW (v : Vp) (h : Bool) (m : Rat) : Rat := navWidth v h m

theorem usedW_eq_unionW (v : Vp) : usedW v = unionW v := by
  have h := panel_ge_pill v
  unfold usedW declW minW unionW
  grind

theorem decl_eq_rest_zero (v : Vp) (h : Bool) : declW v = restW v h 0 := by
  unfold declW restW navWidth
  grind

theorem decl_close_rest (v : Vp) (h : Bool) (m : Rat) (h0 : 0 ≤ m) (hm : m ≤ morphingCut) :
    0 ≤ restW v h m - declW v ∧ restW v h m - declW v ≤ morphingCut * (panelW v - pillW v) := by
  have hp := panel_ge_pill v
  have a := Rat.mul_nonneg (show 0 ≤ panelW v - pillW v by grind) h0
  have b : (panelW v - pillW v) * m ≤ (panelW v - pillW v) * morphingCut :=
    Rat.mul_le_mul_of_nonneg_left hm (by grind)
  unfold restW declW navWidth
  refine ⟨by grind, by grind⟩

theorem used_eq_rest_one (v : Vp) (h : Bool) : usedW v = restW v h 1 := by
  rw [usedW_eq_unionW]
  unfold unionW restW navWidth
  grind

theorem layout_only_at_endpoints (v : Vp) (m m' : Rat) (h : navBox v m false ≠ navBox v m' false) :
    m ≤ morphingCut ∨ m' ≤ morphingCut := by
  by_cases a : m ≤ morphingCut
  · exact Or.inl a
  by_cases b : m' ≤ morphingCut
  · exact Or.inr b
  exfalso
  refine h (union_const v m m' ?_ ?_)
  all_goals grind

theorem rest_same_morph (v : Vp) (m : Rat) (l : Bool) (h : m ≤ morphingCut) :
    navBox v m l = origRect v m ∧ visibleRect v m l = origRect v m := by
  have a : active m l = false := by simp [active]; grind
  simp [navBox, visibleRect, a]

theorem rest_same_locale (v : Vp) (m : Rat) :
    navBox v m true = origRect v m ∧ visibleRect v m true = origRect v m := by
  simp [navBox, visibleRect, active]

theorem visible_eq (v : Vp) (m : Rat) (l : Bool) : visibleRect v m l = origRect v m := by
  unfold visibleRect
  split
  · exact box_eq v m
  · rfl

theorem probe_eq (v : Vp) (m : Rat) (l : Bool) : hitPoint (visibleRect v m l) = hitPoint (origRect v m) := by
  rw [visible_eq]

theorem probe_union_ne : hitPoint (unionRect ⟨390, 844⟩) ≠ hitPoint (origRect ⟨390, 844⟩ (1 / 100)) := by
  decide +kernel

#guard unionRect ⟨430, 932⟩ == ⟨12, 12, 406, 908⟩
#guard unionRect ⟨1280, 800⟩ == ⟨20, 16, 1240, 764⟩
#guard clipRect ⟨1280, 800⟩ 1 == origRect ⟨1280, 800⟩ 1
#guard (insets ⟨1280, 800⟩ 0).b == 700 && (insets ⟨390, 844⟩ 0).t == 4

def jrat (q : Rat) : Lean.Json := Lean.Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

def viewports : List (Rat × Rat) :=
  [(375, 667), (390, 844), (430, 932), (640, 900), (641, 900), (768, 1024), (1000, 700), (1280, 800), (1440, 900), (1920, 1080)]

def samples : List Rat := [0, 1 / 1000, 11 / 10000, 1 / 20, 1 / 5, 2 / 5, 1 / 2, 4 / 5, 23 / 25, 1]

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

def jsonl (_ : Unit := ()) : String := String.join ((rows ()).map (· ++ "\n"))

#guard (rows ()).length == 100

#guard jsonl () == include_str "../../../packages/contracts/golden/parts/nav-clip-box.jsonl"

end Fw.Parts.NavClipBox

import Lean.Data.Json
import Fw.Parts.Nav
import Fw.Parts.MorphPanel
namespace Fw.Parts.MorphConstBounds
open Fw.Parts.Nav Fw.Parts.MorphPanel

def scaleAbout (s c p : Rat) : Rat := s * (p - c) + c

def origPos (w s p : Rat) : Rat := scaleAbout s (w / 2) p

def panelOrg (w1 w : Rat) : Rat := (w - w1) / 2

def off (w1 w : Rat) : Rat := (w1 - w) / 2

def newPos (w1 w s p : Rat) : Rat := panelOrg w1 w + scaleAbout s (w1 / 2) (off w1 w + p)

theorem paint_eq (w1 w s p : Rat) : newPos w1 w s p = origPos w s p := by
  unfold newPos origPos panelOrg off scaleAbout
  grind

theorem visible_iff (w1 w s p : Rat) :
    (0 ≤ newPos w1 w s p ∧ newPos w1 w s p ≤ w) ↔ (0 ≤ origPos w s p ∧ origPos w s p ≤ w) := by
  rw [paint_eq]

theorem nav_origin (w1 w : Rat) : panelOrg w1 w + off w1 w = 0 := by
  unfold panelOrg off; grind

theorem pivot_same (w1 w : Rat) : panelOrg w1 w + w1 / 2 = w / 2 := by
  unfold panelOrg; grind

theorem inset_width_eq (w1 w l r : Rat) : w1 - (off w1 w + l) - (off w1 w + r) = w - l - r := by
  unfold off; grind

theorem backdrop_eq (w1 w : Rat) :
    w1 - (off w1 w - 3 / 100 * w) - (off w1 w - 3 / 100 * w) = 53 / 50 * w ∧
      off w1 w - 3 / 100 * w + panelOrg w1 w = -(3 / 100 * w) := by
  unfold off panelOrg; constructor <;> grind

def origBox (v : Vp) (hp : Bool) (m : Rat) : Rat × Rat := (navWidth v hp m, navHeight v m)

def morphing (m : Rat) : Bool := decide (morphingCut < m)

def varBox (v : Vp) (hp : Bool) (m : Rat) : Rat × Rat := if morphing m then (panelW v, panelH v) else origBox v hp m

theorem varBox_rest (v : Vp) (hp : Bool) (m : Rat) (h : m ≤ morphingCut) : varBox v hp m = origBox v hp m := by
  have : morphing m = false := by unfold morphing; simp; grind
  simp [varBox, this]

theorem varBox_const (v : Vp) (hp : Bool) (m m' : Rat) (h : morphingCut < m) (h' : morphingCut < m') :
    varBox v hp m = varBox v hp m' := by
  have a : morphing m = true := by unfold morphing; simp; grind
  have b : morphing m' = true := by unfold morphing; simp; grind
  simp [varBox, a, b]

theorem orig_resizes_h (v : Vp) (hh : pillH v < panelH v) (m m' : Rat) (h : m < m') :
    navHeight v m < navHeight v m' := by
  unfold navHeight
  have : 0 < panelH v - pillH v := by grind
  have := Rat.mul_pos this (show 0 < m' - m by grind)
  grind

theorem orig_resizes_w (v : Vp) (hp : Bool) (hw : pillW v < panelW v) (m m' : Rat) (h : m < m') :
    navWidth v hp m < navWidth v hp m' := by
  unfold navWidth
  have : 0 < panelW v - pillW v := by grind
  have := Rat.mul_pos this (show 0 < m' - m by grind)
  grind

theorem end_same (v : Vp) (hp : Bool) :
    varBox v hp 1 = origBox v hp 1 ∧ off (panelW v) (navWidth v hp 1) = 0 := by
  have h := end_box v hp
  constructor
  · have : morphing 1 = true := by unfold morphing morphingCut; simp; grind
    simp [varBox, origBox, this, h.1, h.2.1]
  · unfold off; rw [h.2.1]; grind

theorem off_nonneg (v : Vp) (hp : Bool) (m : Rat) (h1 : m ≤ 1) (hh : pillH v ≤ panelH v) :
    0 ≤ off (panelW v) (navWidth v hp m) ∧ 0 ≤ off (panelH v) (navHeight v m) := by
  have hw := panel_ge_pill v
  unfold off navWidth navHeight
  have a := Rat.mul_nonneg (show 0 ≤ panelW v - pillW v by grind) (show 0 ≤ 1 - m by grind)
  have b := Rat.mul_nonneg (show 0 ≤ panelH v - pillH v by grind) (show 0 ≤ 1 - m by grind)
  constructor <;> grind

def colW (n g w : Rat) : Rat := (w * (53 / 50) - (n - 1) * g) / n

def pitch (n g w : Rat) : Rat := colW n g w + g

theorem colW_mono (n g w w' : Rat) (hn : 0 < n) (h : w < w') : colW n g w < colW n g w' := by
  unfold colW
  have hi : 0 < n⁻¹ := Rat.inv_pos.mpr hn
  rw [Rat.div_def, Rat.div_def]
  have := Rat.mul_pos (show 0 < w' * (53 / 50) - w * (53 / 50) by grind) hi
  grind

theorem pitch_scaled_ne (n g w w1 : Rat) (hn : 0 < n) (hg : g ≠ 0) (hw1 : 0 < w1) (hne : w ≠ w1) :
    pitch n g w ≠ pitch n g w1 * (w / w1) := by
  intro h
  unfold pitch colW at h
  rw [Rat.div_def, Rat.div_def, Rat.div_def] at h
  have e1 : n * n⁻¹ = 1 := Rat.mul_inv_cancel _ (by grind)
  have e2 : w1 * w1⁻¹ = 1 := Rat.mul_inv_cancel _ (by grind)
  have key : g * (w1 - w) = 0 := by grind
  rcases Rat.mul_eq_zero.mp key with h1 | h1
  · exact hg h1
  · exact hne (by grind)

def viewports : List (Rat × Rat) :=
  [(375, 667), (390, 844), (640, 900), (641, 900), (768, 1024), (1000, 700), (1280, 800), (1440, 900), (1920, 1080)]

def samples : List Rat := [0, 1 / 1000, 1 / 20, 1 / 5, 2 / 5, 1 / 2, 4 / 5, 23 / 25, 1]

open Lean in
private def jrat (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

open Lean in
def boxRows (_ : Unit := ()) : List String :=
  viewports.flatMap fun (w, h) => samples.map fun m =>
    let v : Vp := ⟨w, h⟩
    let nw := navWidth v false m
    let nh := navHeight v m
    (Json.mkObj [("kind", .str "box"), ("vw", jrat w), ("vh", jrat h), ("m", jrat m), ("morphing", .bool (morphing m)),
      ("navW", jrat nw), ("navH", jrat nh), ("varW", jrat (varBox v false m).1), ("varH", jrat (varBox v false m).2),
      ("newW", jrat (panelW v)), ("newH", jrat (panelH v)),
      ("orgX", jrat (panelOrg (panelW v) nw)), ("orgY", jrat (panelOrg (panelH v) nh)),
      ("offX", jrat (off (panelW v) nw)), ("offY", jrat (off (panelH v) nh)),
      ("bdLeft", jrat (off (panelW v) nw - 3 / 100 * nw)), ("bdW", jrat (53 / 50 * nw))]).compress

open Lean in
def paintRows (_ : Unit := ()) : List String :=
  viewports.flatMap fun (w, h) => samples.map fun m =>
    let v : Vp := ⟨w, h⟩
    let nw := navWidth v false m
    let pts : List Rat := [0, nw / 2, nw]
    (Json.mkObj [("kind", .str "paint"), ("vw", jrat w), ("vh", jrat h), ("m", jrat m), ("scale", jrat (panelScale m)),
      ("orig", Json.arr (pts.map fun p => jrat (origPos nw (panelScale m) p)).toArray),
      ("new", Json.arr (pts.map fun p => jrat (newPos (panelW v) nw (panelScale m) p)).toArray)]).compress

/-- The contents of `packages/contracts/golden/parts/morph-const-bounds.jsonl`. -/
def boundsJsonl (_ : Unit := ()) : String := String.join ((boxRows () ++ paintRows ()).map (· ++ "\n"))

#guard ((paintRows ()).length, (boxRows ()).length) == (81, 81)

#guard boundsJsonl () == include_str "../../../packages/contracts/golden/parts/morph-const-bounds.jsonl"

end Fw.Parts.MorphConstBounds

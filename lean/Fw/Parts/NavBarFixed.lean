import Fw.Parts.NavClipBox
namespace Fw.Parts.NavBarFixed
open Fw.Parts.Nav Fw.Parts.NavClipBox

def barInset (v : Vp) : Rat := if phone v.w then 16 else 24

def barWOrig (v : Vp) (m : Rat) : Rat := navWidth v false m

def barW (v : Vp) (_m : Rat) : Rat := unionW v

def barY (v : Vp) (m : Rat) : Rat := (insets v m).t

def logoX (v : Vp) (m : Rat) : Rat := (insets v m).x + logoLeft (barInset v) (navWidth v false m) m - barInset v

def logoXq (v : Vp) (m : Rat) : Rat :=
  let d := panelW v - pillW v
  d / 2 + ((pillW v - d) / 2 - barInset v) * m + d / 2 * m * m

def actionsX (v : Vp) (m : Rat) : Rat := -(unionW v - navWidth v false m) / 2

def actionsXa (v : Vp) (m : Rat) : Rat := (panelW v - pillW v) / 2 * m - (panelW v - pillW v) / 2

theorem barW_const (v : Vp) (m m' : Rat) : barW v m = barW v m' := rfl

theorem barWOrig_resizes (v : Vp) (hw : pillW v < panelW v) (m m' : Rat) (h : m < m') : barWOrig v m < barWOrig v m' := by
  unfold barWOrig navWidth
  have : 0 < panelW v - pillW v := by grind
  have := Rat.mul_pos this (show 0 < m' - m by grind)
  grind

theorem barW_ge_orig (v : Vp) (m : Rat) (h1 : m ≤ 1) : barWOrig v m ≤ barW v m := by
  have := panel_ge_pill v
  unfold barWOrig barW unionW navWidth
  have h := Rat.mul_nonneg (show 0 ≤ panelW v - pillW v by grind) (show 0 ≤ 1 - m by grind)
  grind

theorem logoX_eq (v : Vp) (m : Rat) :
    barInset v + logoX v m = (insets v m).x + logoLeft (barInset v) (navWidth v false m) m := by
  unfold logoX; grind

theorem logoX_quad (v : Vp) (m : Rat) : logoX v m = logoXq v m := by
  unfold logoX logoXq insets logoLeft navWidth
  simp only [expand]
  grind

theorem actionsX_eq (v : Vp) (m : Rat) : barW v m + actionsX v m = (insets v m).x + navWidth v false m := by
  unfold barW actionsX insets unionW navWidth
  grind

theorem actionsX_affine (v : Vp) (m : Rat) : actionsX v m = actionsXa v m ∧ actionsX v 1 = 0 := by
  unfold actionsX actionsXa unionW navWidth
  constructor <;> grind

theorem barY_eq (v : Vp) (m : Rat) : unionTop v + barY v m = navTop v m := by
  unfold barY insets unionTop navTop
  cases phone v.w <;> simp <;> grind

def scaleAbout (s o p : Rat) : Rat := o + s * (p - o)

theorem translate_scale_order (s o p t : Rat) (hs : s ≠ 1) (ht : t ≠ 0) :
    scaleAbout s o (p + t) ≠ scaleAbout s o p + t := by
  unfold scaleAbout
  intro h
  have : (s - 1) * t = 0 := by grind
  rcases Rat.mul_eq_zero.mp this with h1 | h1
  · exact hs (by grind)
  · exact ht h1

#guard barInset ⟨430, 932⟩ == 16 && actionsX ⟨1280, 800⟩ 0 == -128 && logoX ⟨1280, 800⟩ 1 == 596

def rows (_ : Unit := ()) : List String :=
  viewports.flatMap fun (w, h) => samples.map fun m =>
    let v : Vp := ⟨w, h⟩
    (Lean.Json.mkObj [("vw", jrat w), ("vh", jrat h), ("m", jrat m), ("barW", jrat (barW v m)),
      ("barWOrig", jrat (barWOrig v m)), ("barY", jrat (barY v m)), ("inset", jrat (barInset v)),
      ("logoX", jrat (logoX v m)), ("logoLeft", jrat (logoLeft (barInset v) (navWidth v false m) m)),
      ("actionsX", jrat (actionsX v m)), ("insetX", jrat (insets v m).x)]).compress

def jsonl (_ : Unit := ()) : String := String.join ((rows ()).map (· ++ "\n"))

#guard (rows ()).length == 100

#guard jsonl () == include_str "../../../packages/contracts/golden/parts/nav-bar-fixed.jsonl"

end Fw.Parts.NavBarFixed

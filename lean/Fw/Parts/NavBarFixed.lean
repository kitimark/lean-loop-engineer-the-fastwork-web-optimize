import Fw.Parts.NavClipBox
/-!
# nav bar fixed: the bar keeps the union width, logo and actions are moved by `--morph` (`nav:bar-fixed`, `nav:logo-3d`)
Spec of the `.bar`, `.logo` and `.actions` rules under `.is-morphing` in `apps/site/src/parts/nav/nav.module.css`.
-/
namespace Fw.Parts.NavBarFixed
open Fw.Parts.Nav Fw.Parts.NavClipBox

/-- `--nav-bar-inset-x`: the bar's left padding (phone 16, else 24). -/
def barInset (v : Vp) : Rat := if phone v.w then 16 else 24

/-- Bar width of the original (`left: 0; right: 0` in a nav of width `navWidth`). -/
def barWOrig (v : Vp) (m : Rat) : Rat := navWidth v false m

/-- Bar width under `nav:bar-fixed`: the union width. -/
def barW (v : Vp) (_m : Rat) : Rat := unionW v

/-- Bar offset from the union top under `nav:bar-fixed` (a `translate`, not a layout offset). -/
def barY (v : Vp) (m : Rat) : Rat := (insets v m).t

/-- Logo translation in the fixed bar, from the static `left` of `barInset`: pill offset plus the original's left shift. -/
def logoX (v : Vp) (m : Rat) : Rat := (insets v m).x + logoLeft (barInset v) (navWidth v false m) m - barInset v

/-- `logoX` as the quadratic in `m` that the CSS calc spells out. -/
def logoXq (v : Vp) (m : Rat) : Rat :=
  let d := panelW v - pillW v
  d / 2 + ((pillW v - d) / 2 - barInset v) * m + d / 2 * m * m

/-- Actions translation in the fixed bar: the right edge moves from the union edge to the pill edge. -/
def actionsX (v : Vp) (m : Rat) : Rat := -(unionW v - navWidth v false m) / 2

/-- `actionsX` as the affine function that the CSS calc spells out. -/
def actionsXa (v : Vp) (m : Rat) : Rat := (panelW v - pillW v) / 2 * m - (panelW v - pillW v) / 2

/-- The bar width does not depend on the morph value. -/
theorem barW_const (v : Vp) (m m' : Rat) : barW v m = barW v m' := rfl

/-- The original's bar width grows with the morph, so it is not constant when the panel is wider than the pill. -/
theorem barWOrig_resizes (v : Vp) (hw : pillW v < panelW v) (m m' : Rat) (h : m < m') : barWOrig v m < barWOrig v m' := by
  unfold barWOrig navWidth
  have : 0 < panelW v - pillW v := by grind
  have := Rat.mul_pos this (show 0 < m' - m by grind)
  grind

/-- The fixed bar is as wide as the union and the bar of the original is never wider. -/
theorem barW_ge_orig (v : Vp) (m : Rat) (h1 : m ≤ 1) : barWOrig v m ≤ barW v m := by
  have := panel_ge_pill v
  unfold barWOrig barW unionW navWidth
  have h := Rat.mul_nonneg (show 0 ≤ panelW v - pillW v by grind) (show 0 ≤ 1 - m by grind)
  grind

/-- The logo stays where the original puts it: static left plus translation is pill offset plus the original left. -/
theorem logoX_eq (v : Vp) (m : Rat) :
    barInset v + logoX v m = (insets v m).x + logoLeft (barInset v) (navWidth v false m) m := by
  unfold logoX; grind

/-- The translation is the quadratic of the CSS calc. -/
theorem logoX_quad (v : Vp) (m : Rat) : logoX v m = logoXq v m := by
  unfold logoX logoXq insets logoLeft navWidth
  simp only [expand]
  grind

/-- The actions keep their distance from the pill's right edge. -/
theorem actionsX_eq (v : Vp) (m : Rat) : barW v m + actionsX v m = (insets v m).x + navWidth v false m := by
  unfold barW actionsX insets unionW navWidth
  grind

/-- The translation is the affine function of the CSS calc, zero at the end of the morph. -/
theorem actionsX_affine (v : Vp) (m : Rat) : actionsX v m = actionsXa v m ∧ actionsX v 1 = 0 := by
  unfold actionsX actionsXa unionW navWidth
  constructor <;> grind

/-- The bar sits at the pill's top: union top plus bar offset is the nav top of the original. -/
theorem barY_eq (v : Vp) (m : Rat) : unionTop v + barY v m = navTop v m := by
  unfold barY insets unionTop navTop
  cases phone v.w <;> simp <;> grind

/-- Position of a point under a scale about an origin. -/
def scaleAbout (s o p : Rat) : Rat := o + s * (p - o)

/-- Translate-then-scale and scale-then-translate disagree for a scaled phone logo: the order must follow the original's. -/
theorem translate_scale_order (s o p t : Rat) (hs : s ≠ 1) (ht : t ≠ 0) :
    scaleAbout s o (p + t) ≠ scaleAbout s o p + t := by
  unfold scaleAbout
  intro h
  have : (s - 1) * t = 0 := by grind
  rcases Rat.mul_eq_zero.mp this with h1 | h1
  · exact hs (by grind)
  · exact ht h1

#guard barInset ⟨430, 932⟩ == 16 && actionsX ⟨1280, 800⟩ 0 == -128 && logoX ⟨1280, 800⟩ 1 == 596

/-- Golden rows of `nav-bar-fixed.jsonl`. -/
def rows (_ : Unit := ()) : List String :=
  viewports.flatMap fun (w, h) => samples.map fun m =>
    let v : Vp := ⟨w, h⟩
    (Lean.Json.mkObj [("vw", jrat w), ("vh", jrat h), ("m", jrat m), ("barW", jrat (barW v m)),
      ("barWOrig", jrat (barWOrig v m)), ("barY", jrat (barY v m)), ("inset", jrat (barInset v)),
      ("logoX", jrat (logoX v m)), ("logoLeft", jrat (logoLeft (barInset v) (navWidth v false m) m)),
      ("actionsX", jrat (actionsX v m)), ("insetX", jrat (insets v m).x)]).compress

/-- File contents of `packages/contracts/golden/parts/nav-bar-fixed.jsonl`. -/
def jsonl (_ : Unit := ()) : String := String.join ((rows ()).map (· ++ "\n"))

#guard (rows ()).length == 100

#guard jsonl () == include_str "../../../packages/contracts/golden/parts/nav-bar-fixed.jsonl"

end Fw.Parts.NavBarFixed

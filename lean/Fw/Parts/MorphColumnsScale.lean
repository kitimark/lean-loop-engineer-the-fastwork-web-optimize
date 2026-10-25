import Lean.Data.Json
import Fw.Parts.Nav
import Fw.Parts.Golden
/-!
# morph.columns, variant `final-scale`: columns laid out once at the final width, drawn by a per-column transform
Note: research/notes/2026/10-2x-columns-final-scale.md.
-/
namespace Fw.Parts.MorphColumnsScale

open Fw.Parts.Nav

def gap (_ : Unit := ()) : Rat := 12
def bleed (_ : Unit := ()) : Rat := 53 / 50
def cols (v : Vp) : Rat := if phone v.w then 3 else 5

/-- The width below which the variant draws nothing different (the original's `mq.w-le-1000`). -/
def scaleMaxW (_ : Unit := ()) : Rat := 1000
def applies (v : Vp) : Bool := decide (v.w ≤ scaleMaxW)

def backW (v : Vp) (m : Rat) : Rat := bleed * navWidth v false m
def colW (v : Vp) (m : Rat) : Rat := (backW v m - gap * (cols v - 1)) / cols v
def finalW (v : Vp) : Rat := colW v 1

def baseLeft (v : Vp) (m i : Rat) : Rat := i * (colW v m + gap)
def baseRight (v : Vp) (m i : Rat) : Rat := baseLeft v m i + colW v m

def finalLeft (v : Vp) (i : Rat) : Rat := i * (finalW v + gap)
def sx (v : Vp) (m : Rat) : Rat := colW v m / finalW v
def tx (v : Vp) (m i : Rat) : Rat := i * (colW v m - finalW v)
def drawnLeft (v : Vp) (m i : Rat) : Rat := finalLeft v i + tx v m i
def drawnRight (v : Vp) (m i : Rat) : Rat := drawnLeft v m i + sx v m * finalW v

/-- The two constants the part writes once per viewport; the rest is `calc()` of `--morph`. -/
def a (v : Vp) : Rat := colW v 0 / finalW v
def d (v : Vp) : Rat := colW v 0 - finalW v
def sxCss (v : Vp) (m : Rat) : Rat := a v + (1 - a v) * m
def txCss (v : Vp) (m i : Rat) : Rat := i * (1 - m) * d v

theorem div_le_of (x y z : Rat) (hy : 0 < y) (h : x ≤ z * y) : x / y ≤ z := by
  rw [Rat.div_def]
  have e : y * y⁻¹ = 1 := Rat.mul_inv_cancel _ (by grind)
  have p0 : 0 < y⁻¹ := Rat.inv_pos.mpr hy
  have p : 0 ≤ y⁻¹ := by grind
  have q : z * y * y⁻¹ = z := by rw [Rat.mul_assoc, e, Rat.mul_one]
  have := Rat.mul_le_mul_of_nonneg_right h p
  grind

theorem le_div_of (x y z : Rat) (hy : 0 < y) (h : z * y ≤ x) : z ≤ x / y := by
  rw [Rat.div_def]
  have e : y * y⁻¹ = 1 := Rat.mul_inv_cancel _ (by grind)
  have p0 : 0 < y⁻¹ := Rat.inv_pos.mpr hy
  have p : 0 ≤ y⁻¹ := by grind
  have q : z * y * y⁻¹ = z := by rw [Rat.mul_assoc, e, Rat.mul_one]
  have := Rat.mul_le_mul_of_nonneg_right h p
  grind

theorem cols_pos (v : Vp) : 0 < cols v := by unfold cols; split <;> grind

theorem colW_affine (v : Vp) (m : Rat) : colW v m = colW v 0 + (finalW v - colW v 0) * m := by
  have := cols_pos v
  unfold finalW colW backW navWidth
  rw [Rat.div_def, Rat.div_def, Rat.div_def]
  have h : (cols v)⁻¹ * cols v = 1 := Rat.inv_mul_cancel _ (by grind)
  grind

theorem edges_eq (v : Vp) (hf : finalW v ≠ 0) (m i : Rat) :
    drawnLeft v m i = baseLeft v m i ∧ drawnRight v m i = baseRight v m i := by
  have h : colW v m / finalW v * finalW v = colW v m := Rat.div_mul_cancel hf
  unfold drawnRight drawnLeft finalLeft tx sx baseRight baseLeft
  constructor <;> grind

theorem css_eq (v : Vp) (hf : finalW v ≠ 0) (m i : Rat) : sxCss v m = sx v m ∧ txCss v m i = tx v m i := by
  have h := colW_affine v m
  have e : finalW v * (finalW v)⁻¹ = 1 := Rat.mul_inv_cancel _ hf
  constructor
  · unfold sxCss sx a
    rw [h, Rat.div_def, Rat.div_def]
    grind
  · unfold txCss tx d
    grind

theorem final_at_one (v : Vp) (hf : finalW v ≠ 0) : sx v 1 = 1 ∧ tx v 1 0 = 0 := by
  unfold sx tx finalW
  exact ⟨by rw [Rat.div_def]; exact Rat.mul_inv_cancel _ hf, by grind⟩

/-! ## Look-change bound -/

def radiusX (v : Vp) (m : Rat) : Rat := 12 * sx v m
def radiusY (_ : Unit := ()) : Rat := 12
def gapDrawn (_ : Unit := ()) : Rat := gap * 1
def driftDrawn (_ : Unit := ()) : Rat := 56 * 1

theorem vertical_exact (h : Rat) : gapDrawn = 12 ∧ driftDrawn = 56 ∧ radiusY = 12 ∧ h * 1 = h := by
  unfold gapDrawn driftDrawn radiusY gap; refine ⟨by grind, by grind, rfl, by grind⟩

theorem uniform_breaks_height (s h : Rat) (hs : s < 1) (hh : 0 < h) : h * s ≠ h := by
  intro e; have := Rat.mul_pos hh (show 0 < 1 - s by grind); grind

theorem sx_mem (v : Vp) (hf : 0 < finalW v) (h0 : colW v 0 ≤ finalW v) (m : Rat)
    (hm0 : 0 ≤ m) (hm1 : m ≤ 1) : a v ≤ sx v m ∧ sx v m ≤ 1 := by
  have e := (css_eq v (by grind) m 0).1
  rw [← e]
  unfold sxCss
  have : a v ≤ 1 := by
    unfold a; exact div_le_of _ _ _ hf (by grind)
  have h1 : 0 ≤ 1 - a v := by grind
  have := Rat.mul_nonneg h1 hm0
  have := Rat.mul_le_mul_of_nonneg_left hm1 h1
  grind

def vp390 (_ : Unit := ()) : Vp := ⟨390, 844⟩

theorem a_390 : 97 / 100 ≤ a vp390 := by
  decide +kernel

theorem a_390_le : a vp390 ≤ 98 / 100 := by
  decide +kernel

theorem colW_phone (w h m : Rat) (h2 : w ≤ 640) :
    colW ⟨w, h⟩ m = (53 / 50 * ((w - 32) + (w - 24 - (w - 32)) * m) - 24) / 3 := by
  unfold colW backW navWidth bleed gap cols pillW panelW phone expand
  have : decide (w ≤ 640) = true := by simp [h2]
  simp only [this, ite_true]
  have e : min 984 (w - 32) = w - 32 := by grind
  rw [e]
  have e3 : (3 : Rat) - 1 = 2 := by grind
  grind

theorem colW_wide (w h m : Rat) (h1 : 640 < w) (h2 : w ≤ 1000) :
    colW ⟨w, h⟩ m = (53 / 50 * ((w - 48) + (w - 40 - (w - 48)) * m) - 48) / 5 := by
  unfold colW backW navWidth bleed gap cols pillW panelW phone expand
  have : decide (w ≤ 640) = false := by simp; grind
  simp only [this, Bool.false_eq_true, ite_false]
  have e : min 984 (w - 48) = w - 48 := by grind
  have e2 : min 1398 (w - 40) = w - 40 := by grind
  rw [e, e2]
  grind

theorem a_of (v : Vp) (hf : 0 < finalW v) (h : 97 / 100 * finalW v ≤ colW v 0) : 97 / 100 ≤ a v :=
  le_div_of _ _ _ hf h

theorem a_range (w h : Rat) (h1 : 314 ≤ w) (h2 : w ≤ 1000) : 97 / 100 ≤ a ⟨w, h⟩ := by
  by_cases hp : w ≤ 640
  · apply a_of
    · unfold finalW; rw [colW_phone _ _ _ hp]; grind
    · unfold finalW; rw [colW_phone _ _ _ hp, colW_phone _ _ _ hp]; grind
  · have hp' : 640 < w := by grind
    apply a_of
    · unfold finalW; rw [colW_wide _ _ _ hp' h2]; grind
    · unfold finalW; rw [colW_wide _ _ _ hp' h2, colW_wide _ _ _ hp' h2]; grind

theorem range_facts (w h : Rat) (h1 : 314 ≤ w) (h2 : w ≤ 1000) :
    0 < finalW ⟨w, h⟩ ∧ colW ⟨w, h⟩ 0 ≤ finalW ⟨w, h⟩ := by
  by_cases hp : w ≤ 640
  · unfold finalW; rw [colW_phone _ _ _ hp, colW_phone _ _ _ hp]; constructor <;> grind
  · have hp' : 640 < w := by grind
    unfold finalW; rw [colW_wide _ _ _ hp' h2, colW_wide _ _ _ hp' h2]; constructor <;> grind

theorem sx_range (w h m : Rat) (h1 : 314 ≤ w) (h2 : w ≤ 1000) (hm0 : 0 ≤ m) (hm1 : m ≤ 1) :
    97 / 100 ≤ sx ⟨w, h⟩ m ∧ sx ⟨w, h⟩ m ≤ 1 := by
  obtain ⟨hf, hc⟩ := range_facts w h h1 h2
  have := sx_mem ⟨w, h⟩ hf hc m hm0 hm1
  have := a_range w h h1 h2
  grind

theorem radius_bound (w h m : Rat) (h1 : 314 ≤ w) (h2 : w ≤ 1000) (hm0 : 0 ≤ m) (hm1 : m ≤ 1) :
    0 ≤ radiusY - radiusX ⟨w, h⟩ m ∧ radiusY - radiusX ⟨w, h⟩ m ≤ 36 / 100 := by
  have := sx_range w h m h1 h2 hm0 hm1
  unfold radiusY radiusX
  constructor <;> grind

theorem squeeze_bound (w h m : Rat) (h1 : 314 ≤ w) (h2 : w ≤ 1000) (hm0 : 0 ≤ m) (hm1 : m ≤ 1) :
    1 - sx ⟨w, h⟩ m ≤ 3 / 100 := by
  have := sx_range w h m h1 h2 hm0 hm1
  grind

/-! ## No layout write per frame -/

inductive Css | transform | width | height | left | top | gap | flexBasis | opacity | filter
deriving DecidableEq

def layoutAffecting : Css → Bool
  | .transform | .opacity | .filter => false
  | .width | .height | .left | .top | .gap | .flexBasis => true

/-- The properties the columns' rules compute from `--morph`, one list per arm. -/
def baseMorphDeps : List Css := [.width]
def variantMorphDeps : List Css := [.transform]

theorem variant_no_layout : ∀ p ∈ variantMorphDeps, layoutAffecting p = false := by decide
theorem base_has_layout : ∃ p ∈ baseMorphDeps, layoutAffecting p = true := ⟨.width, by decide, rfl⟩

def layoutBox (v : Vp) (_m : Rat) : Rat × Rat := (finalW v, gap)

theorem layout_const (v : Vp) (m m' : Rat) : layoutBox v m = layoutBox v m' := rfl

theorem base_width_moves (w h m m' : Rat) (h2 : w ≤ 1000) (hm : m < m') :
    colW ⟨w, h⟩ m < colW ⟨w, h⟩ m' := by
  by_cases hp : w ≤ 640
  · rw [colW_phone _ _ _ hp, colW_phone _ _ _ hp]; grind
  · have hp' : 640 < w := by grind
    rw [colW_wide _ _ _ hp' h2, colW_wide _ _ _ hp' h2]; grind

theorem a_desktop : a ⟨1440, 900⟩ < 7 / 10 := by
  decide +kernel

theorem a_narrow : a ⟨280, 600⟩ < 97 / 100 := by
  decide +kernel

def widths (_ : Unit := ()) : List Int := [320, 360, 390, 414, 640, 641, 768, 834, 1000, 1001, 1280]

def morphs (_ : Unit := ()) : List Int := [0, 1, 100, 250, 500, 750, 900, 999, 1000]

def vpOf (w : Int) : Vp := ⟨w, 800⟩

def colIdx (v : Vp) : List Rat := (List.range (cols v).num.toNat).map fun (i : Nat) => (i : Rat)

open Lean Fw.Parts.Golden in
def lines (_ : Unit) : List String :=
  widths.map (fun w =>
    line "vars" [("w", jint w)]
      (Json.mkObj [("applies", .bool (applies (vpOf w))), ("n", ratWire (cols (vpOf w))), ("cf", ratWire (finalW (vpOf w))),
        ("a", ratWire (a (vpOf w))), ("d", ratWire (d (vpOf w)))])) ++
  widths.flatMap fun w => morphs.map fun (mm : Int) =>
    let v := vpOf w
    let m : Rat := ((mm : Int) : Rat) / 1000
    line "frame" [("w", jint w), ("mm", jint mm)]
      (Json.mkObj [("sx", ratWire (sxCss v m)),
        ("tx", .arr ((colIdx v).map (fun i => ratWire (txCss v m i))).toArray),
        ("baseLeft", .arr ((colIdx v).map (fun i => ratWire (baseLeft v m i))).toArray),
        ("baseRight", .arr ((colIdx v).map (fun i => ratWire (baseRight v m i))).toArray)])

def goldenText (_ : Unit) : String := String.join ((lines ()).map (· ++ "\n"))

def gen (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText () then
      IO.eprintln s!"morph-columns-scale golden: {path} is up to date ({(lines ()).length} lines)"
      return 0
    IO.eprintln s!"morph-columns-scale golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Parts.MorphColumnsScale

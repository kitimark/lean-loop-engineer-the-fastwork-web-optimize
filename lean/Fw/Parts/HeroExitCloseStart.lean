import Fw.Parts.MorphTween
import Fw.Parts.Nav
import Fw.Parts.HeroExitOpt

/-! Start colour of the nav background after a close, on the probe's red channel, and the frame-gap floor that bounds it. -/

namespace Fw.Parts.HeroExitCloseStart

open Fw.Parts.MorphTween

/-- Morph value of a close from fully open, `e` ms after the push. -/
def closeAt (e : Rat) : Rat := (tween 1 0 e).value

/-- A frame sees `is-morphing` while the morph value is above the nav's cut. -/
def morphingAt (e : Rat) : Bool := decide (Fw.Parts.Nav.morphingCut < closeAt e)

/-- The share of the close that remains at `e` ms. -/
def share (e : Rat) : Rat := 1 - e / 680

/-- The close value is the cube of the remaining share. -/
theorem closeAt_cube (e : Rat) (h0 : 0 ≤ e) (h1 : e < 680) :
    closeAt e = share e * share e * share e := by
  have hc : clamp01 (e / duration) = e / 680 := by
    unfold clamp01
    rw [div_dur]
    grind
  have hn : ¬ (1 ≤ e / 680) := by grind
  have hc' : clamp01 (e / 680) = e / 680 := by
    unfold clamp01
    grind
  unfold closeAt tween share
  rw [hc]
  simp only [hn, ite_false]
  unfold ease
  rw [hc']
  grind

/-- The close is zero once its 680 ms are over. -/
theorem closeAt_end (e : Rat) (h : 680 ≤ e) : closeAt e = 0 := tween_end 1 0 e h

/-- The cube is increasing on the non-negative numbers. -/
theorem cube_le (a b : Rat) (ha : 0 ≤ a) (hab : a ≤ b) : a * a * a ≤ b * b * b := by
  have hb : 0 ≤ b := by grind
  have h1 : a * a ≤ b * b := by
    have := Rat.mul_le_mul_of_nonneg_left hab ha
    have := Rat.mul_le_mul_of_nonneg_right hab hb
    grind
  have h2 := Rat.mul_le_mul_of_nonneg_right h1 hb
  have h3 := Rat.mul_le_mul_of_nonneg_left hab (Rat.mul_nonneg ha ha)
  grind

/-- The cube is strictly increasing on the non-negative numbers. -/
theorem cube_lt (a b : Rat) (ha : 0 ≤ a) (hab : a < b) : a * a * a < b * b * b := by
  have hb : 0 < b := by grind
  have h1 : a * a < b * b := by
    have := Rat.mul_lt_mul_of_pos_right hab hb
    have := Rat.mul_le_mul_of_nonneg_left (show a ≤ b by grind) ha
    grind
  have := Rat.mul_lt_mul_of_pos_right h1 hb
  have := Rat.mul_le_mul_of_nonneg_left (show a ≤ b by grind) (Rat.mul_nonneg ha ha)
  grind

/-- `1/10` cubed is the nav's cut. -/
theorem tenth_cube : (1 / 10 : Rat) * (1 / 10) * (1 / 10) = Fw.Parts.Nav.morphingCut := by
  unfold Fw.Parts.Nav.morphingCut
  decide +kernel

/-- A frame before the last 68 ms of the close sees `is-morphing`; `68 = 680 / 10`. -/
theorem morphing_of_lt (e : Rat) (h0 : 0 ≤ e) (h : e < 612) : morphingAt e = true := by
  unfold morphingAt
  rw [decide_eq_true_iff, closeAt_cube e h0 (by grind), ← tenth_cube]
  unfold share
  exact cube_lt _ _ (by grind) (by grind)

/-- A frame in the last 68 ms of the close does not see `is-morphing`. -/
theorem not_morphing_of_ge (e : Rat) (h : 612 ≤ e) : morphingAt e = false := by
  unfold morphingAt
  by_cases h1 : e < 680
  · have h0 : 0 ≤ e := by grind
    rw [decide_eq_false_iff_not, closeAt_cube e h0 h1, ← tenth_cube]
    unfold share
    have := cube_le (1 - e / 680) (1 / 10) (by grind) (by grind)
    grind
  · rw [closeAt_end e (by grind)]
    decide +kernel

/-- Bound on the morph value of the last morphing frame when the next frame comes `g` ms later. -/
def prevBound (g : Rat) : Rat := (1 / 10 + g / 680) * (1 / 10 + g / 680) * (1 / 10 + g / 680)

/-- The last morphing frame `ea` is at most `prevBound (eb - ea)`, `eb` the first frame without `is-morphing`. -/
theorem prev_le_bound (ea eb : Rat) (h0 : 0 ≤ ea) (hab : ea < eb) (ha : ea < 680) (hb : morphingAt eb = false) :
    closeAt ea ≤ prevBound (eb - ea) := by
  have h612 : 612 ≤ eb := by
    refine Classical.byContradiction fun hc => ?_
    have := morphing_of_lt eb (by grind) (by grind)
    grind
  rw [closeAt_cube ea h0 ha]
  unfold prevBound share
  exact cube_le _ _ (by grind) (by grind)

/-- The last morphing frame is above the cut. -/
theorem prev_gt_cut (ea : Rat) (ha : morphingAt ea = true) : Fw.Parts.Nav.morphingCut < closeAt ea := by
  unfold morphingAt at ha
  exact of_decide_eq_true ha

/-- Alpha of the nav background at morph value `m` (`color-mix(in srgb, #ffffff1a, #131922)`, alpha `26/255` to 1). -/
def bgAlpha (m : Rat) : Rat := 26 / 255 * (1 - m) + m

/-- A higher morph value gives a higher alpha. -/
theorem bgAlpha_lt (m n : Rat) (h : m < n) : bgAlpha m < bgAlpha n := by
  unfold bgAlpha
  grind

/-- The alpha names the morph value. -/
theorem bgAlpha_inj (m n : Rat) (h : bgAlpha m = bgAlpha n) : m = n := by
  by_cases h1 : m < n
  · have := bgAlpha_lt m n h1
    grind
  · by_cases h2 : n < m
    · have := bgAlpha_lt n m h2
      grind
    · grind

/-- The alpha is positive for every non-negative morph value. -/
theorem bgAlpha_pos (m : Rat) (h : 0 ≤ m) : 0 < bgAlpha m := by
  unfold bgAlpha
  grind

/-- Red (0 to 255) of the nav background at morph value `m`: the premultiplied red `26 (1 - m) + 19 m` over `bgAlpha m`. -/
def bgRed (m : Rat) : Rat := (26 * (1 - m) + 19 * m) / bgAlpha m

/-- The red times the alpha is the premultiplied red. -/
theorem bgRed_mul (m : Rat) (h : 0 ≤ m) : bgRed m * bgAlpha m = 26 * (1 - m) + 19 * m := by
  unfold bgRed
  have := bgAlpha_pos m h
  rw [Rat.div_mul_cancel (by grind)]

/-- A higher morph value gives a lower red: the red falls from 255 at `m = 0` to 19 at `m = 1`. -/
theorem bgRed_lt (m n : Rat) (h0 : 0 ≤ m) (h : m < n) : bgRed n < bgRed m := by
  have ha := bgAlpha_pos m h0
  have hb := bgAlpha_pos n (by grind)
  have e1 := bgRed_mul m h0
  have e2 := bgRed_mul n (by grind)
  have key : (26 * (1 - n) + 19 * n) * bgAlpha m < (26 * (1 - m) + 19 * m) * bgAlpha n := by
    unfold bgAlpha
    grind
  refine Classical.byContradiction fun hc => ?_
  have hc' : bgRed m ≤ bgRed n := by grind
  have h1 := Rat.mul_le_mul_of_nonneg_right hc' (Rat.le_of_lt (Rat.mul_pos ha hb))
  have : (bgRed m * bgAlpha m) * bgAlpha n ≤ (bgRed n * bgAlpha n) * bgAlpha m := by
    have := h1
    grind
  rw [e1, e2] at this
  grind

/-- A lower-or-equal red names a higher-or-equal morph value (the order of `bgRed_lt`, read backwards). -/
theorem bgRed_le_iff (m n : Rat) (h0 : 0 ≤ m) (h1 : 0 ≤ n) : bgRed n ≤ bgRed m ↔ m ≤ n := by
  constructor
  · intro h
    refine Classical.byContradiction fun hc => ?_
    have := bgRed_lt n m h1 (by grind)
    grind
  · intro h
    by_cases he : m = n
    · rw [he]
      exact Rat.le_refl
    · have := bgRed_lt m n h0 (by grind)
      exact Rat.le_of_lt this

/-- The bound grows with the gap. -/
theorem prevBound_mono (g h : Rat) (h0 : 0 ≤ g) (hgh : g ≤ h) : prevBound g ≤ prevBound h := by
  unfold prevBound
  exact cube_le _ _ (by grind) (by grind)

/-- Lowest red a close start shows when the last morphing frame is at most `g` ms before the first frame without the class. -/
def redFloor (g : Rat) : Rat := bgRed (prevBound g)

/-- A longer gap lowers the floor. -/
theorem redFloor_anti (g h : Rat) (h0 : 0 ≤ g) (hgh : g ≤ h) : redFloor h ≤ redFloor g := by
  unfold redFloor
  have hg : 0 ≤ prevBound g := by
    unfold prevBound
    exact Rat.mul_nonneg (Rat.mul_nonneg (by grind) (by grind)) (by grind)
  have hh : 0 ≤ prevBound h := by
    have := prevBound_mono g h h0 hgh
    grind
  exact (bgRed_le_iff _ _ hg hh).2 (prevBound_mono g h h0 hgh)

/-- The reading passes when it is no darker than the floor of the reference gap `cap` plus the read lag `lag` (ms); `cap` is the original's. -/
def floorOk (cap lag reading : Rat) : Bool := decide (redFloor (cap + lag) ≤ reading)

/-- Every start the tween makes is accepted when its frame gap is within `cap + lag`, whichever arm made it. -/
theorem floorOk_tween (cap lag ea eb : Rat) (h0 : 0 ≤ ea) (hab : ea < eb)
    (ha : morphingAt ea = true) (hb : morphingAt eb = false) (hgap : eb - ea ≤ cap + lag) :
    floorOk cap lag (bgRed (closeAt ea)) = true := by
  have h680 : ea < 680 := by
    refine Classical.byContradiction fun hc => ?_
    have := closeAt_end ea (by grind)
    have := prev_gt_cut ea ha
    unfold Fw.Parts.Nav.morphingCut at this
    grind
  have hge := prev_gt_cut ea ha
  have hle := prev_le_bound ea eb h0 hab h680 hb
  have hmono := prevBound_mono (eb - ea) (cap + lag) (by grind) hgap
  have hc0 : 0 ≤ closeAt ea := by
    unfold Fw.Parts.Nav.morphingCut at hge
    grind
  have hp : 0 ≤ prevBound (cap + lag) := by
    unfold prevBound
    exact Rat.mul_nonneg (Rat.mul_nonneg (by grind) (by grind)) (by grind)
  unfold floorOk redFloor
  rw [decide_eq_true_iff]
  exact (bgRed_le_iff _ _ hc0 hp).2 (by grind)

/-- A reading darker than the floor is rejected. -/
theorem floorOk_below (cap lag reading : Rat) (h : reading < redFloor (cap + lag)) : floorOk cap lag reading = false := by
  unfold floorOk
  rw [decide_eq_false_iff_not]
  grind

/-- A rejected tween start came from a frame gap longer than `cap + lag`: the cause is frame time, not colour. -/
theorem floorOk_reject_gap (cap lag ea eb : Rat) (h0 : 0 ≤ ea) (hab : ea < eb)
    (ha : morphingAt ea = true) (hb : morphingAt eb = false)
    (hrej : floorOk cap lag (bgRed (closeAt ea)) = false) : cap + lag < eb - ea := by
  refine Classical.byContradiction fun hc => ?_
  have := floorOk_tween cap lag ea eb h0 hab ha hb (by grind)
  grind

/-- A wider reference gap accepts more. -/
theorem floorOk_mono (cap cap' lag reading : Rat) (h0 : 0 ≤ cap + lag) (hc : cap ≤ cap')
    (h : floorOk cap lag reading = true) : floorOk cap' lag reading = true := by
  unfold floorOk at *
  rw [decide_eq_true_iff] at *
  have := redFloor_anti (cap + lag) (cap' + lag) h0 (by grind)
  grind

/-- The reference gap of a width: the largest gap the original arm showed there. -/
def capOf : List Rat → Rat
  | [] => 0
  | g :: gs => if g ≤ capOf gs then capOf gs else g

/-- No gap of the original arm exceeds its cap. -/
theorem capOf_ge (g : Rat) (gs : List Rat) (h : g ∈ gs) : g ≤ capOf gs := by
  induction gs with
  | nil => simp at h
  | cons x xs ih =>
    unfold capOf
    by_cases hx : x ≤ capOf xs
    · simp only [hx, ↓reduceIte]
      rcases List.mem_cons.mp h with rfl | hm
      · exact hx
      · exact ih hm
    · simp only [hx, ↓reduceIte]
      rcases List.mem_cons.mp h with rfl | hm
      · exact Rat.le_refl
      · have := ih hm
        grind

/-- Every start an original pass made is accepted by the cap of the original arm's gaps, at any lag of zero or more. -/
theorem floorOk_orig (gs : List Rat) (lag ea eb : Rat) (hlag : 0 ≤ lag) (h0 : 0 ≤ ea) (hab : ea < eb)
    (ha : morphingAt ea = true) (hb : morphingAt eb = false) (hm : eb - ea ∈ gs) :
    floorOk (capOf gs) lag (bgRed (closeAt ea)) = true :=
  floorOk_tween (capOf gs) lag ea eb h0 hab ha hb (by have := capOf_ge _ _ hm; grind)

#guard prevBound 0 == Fw.Parts.Nav.morphingCut
#guard decide (138 / 10000 ≤ prevBound 114)
#guard decide (258 / 10000 ≤ prevBound 158)
#guard decide (282 / 10000 ≤ prevBound 203)
#guard decide (156 / 10000 ≤ prevBound 146)
-- red channel against the probe's readings (nav.background-color while `is-morphing` is on, 39466179818 and 39508414669)
#guard decide (bgRed (138 / 10000) < 226569 / 1000 + 15 / 100 ∧ 226569 / 1000 - 15 / 100 < bgRed (138 / 10000))
#guard decide (bgRed (585 / 10000) < 165621 / 1000 + 15 / 100 ∧ 165621 / 1000 - 15 / 100 < bgRed (585 / 10000))
#guard decide (bgRed (22 / 10000) < 249911 / 1000 + 15 / 100 ∧ 249911 / 1000 - 15 / 100 < bgRed (22 / 10000))
-- values the TS twin (`packages/gate-breakpoints/src/trajectory/closegap.mjs`) is tested against
#guard (bgRed 0 * 1000000).floor == 255000000
#guard (bgRed 1 * 1000000).floor == 19000000
#guard (bgRed (1 / 1000) * 1000000).floor == 252705593
#guard (bgRed (138 / 10000) * 1000000).floor == 226519948
#guard (bgRed (22 / 10000) * 1000000).floor == 250004640
#guard (redFloor 113 * 1000000).floor == 217567243
#guard (redFloor 202 * 1000000).floor == 161602802
#guard capOf [36, 67, 29] == 67
#guard capOf [] == 0
#guard floorOk 67 17 235 == true
#guard floorOk 67 17 160 == false

/-- Custom properties the nav background reads. -/
def navBgReads : List String := ["--morph"]

/-- Over the `frameWrites` model (the driver also sets `pointer-events` on the hero), no write is to a property the nav background reads. -/
theorem scoped_writes_miss_nav_bg : ∀ w ∈ Fw.Parts.HeroExitOpt.frameWrites, w.2 ∉ navBgReads := by
  decide +kernel

/-- Over the `frameWrites` model, no write lands on a nav element. -/
theorem scoped_writes_miss_nav_elements : ∀ w ∈ Fw.Parts.HeroExitOpt.frameWrites, ¬ w.1.startsWith "nav" := by
  decide +kernel

end Fw.Parts.HeroExitCloseStart

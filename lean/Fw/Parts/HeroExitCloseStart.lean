import Fw.Parts.MorphTween
import Fw.Parts.Nav
import Fw.Parts.HeroExitOpt

/-! Start colour of the nav background after a close: a frame-phase value that no `hero.exit` write reaches. -/

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

/-- Start alpha of the background transition: the before-change style is the last frame that saw `is-morphing`
(Styleable.cpp:606-617, 646-676@862f17d). -/
def startAlpha (ea : Rat) : Rat := bgAlpha (closeAt ea)

/-- Start alphas a close may show when its last frames are `g` ms apart: above the cut, at most `prevBound g`'s. -/
def startAccepts (reading g : Rat) : Bool :=
  decide (bgAlpha Fw.Parts.Nav.morphingCut < reading ∧ reading ≤ bgAlpha (prevBound g))

/-- Every start the tween makes is accepted at its own frame gap, whichever arm made it. -/
theorem startAccepts_tween (ea eb : Rat) (h0 : 0 ≤ ea) (hab : ea < eb) (ha : morphingAt ea = true)
    (hb : morphingAt eb = false) : startAccepts (startAlpha ea) (eb - ea) = true := by
  have h680 : ea < 680 := by
    refine Classical.byContradiction fun hc => ?_
    have := closeAt_end ea (by grind)
    have := prev_gt_cut ea ha
    unfold Fw.Parts.Nav.morphingCut at this
    grind
  have hge := prev_gt_cut ea ha
  have hle := prev_le_bound ea eb h0 hab h680 hb
  unfold startAccepts startAlpha
  rw [decide_eq_true_iff]
  constructor
  · exact bgAlpha_lt _ _ hge
  · unfold bgAlpha at *
    grind

/-- An alpha above `prevBound g`'s is rejected. -/
theorem startAccepts_above (reading g : Rat) (h : bgAlpha (prevBound g) < reading) : startAccepts reading g = false := by
  unfold startAccepts
  rw [decide_eq_false_iff_not]
  grind

#guard prevBound 0 == Fw.Parts.Nav.morphingCut
#guard decide (138 / 10000 ≤ prevBound 114)
#guard decide (258 / 10000 ≤ prevBound 158)
#guard decide (282 / 10000 ≤ prevBound 203)
#guard decide (156 / 10000 ≤ prevBound 146)
#guard decide ((bgAlpha (138 / 10000) * 255 - 29154 / 1000) < 1 / 50 ∧ (29154 / 1000 - bgAlpha (138 / 10000) * 255) < 1 / 50)

/-- Custom properties the nav background reads. -/
def navBgReads : List String := ["--morph"]

/-- The scoped exit writes no property the nav background reads. -/
theorem scoped_writes_miss_nav_bg : ∀ w ∈ Fw.Parts.HeroExitOpt.frameWrites, w.2 ∉ navBgReads := by
  decide +kernel

/-- No scoped write lands on a nav element. -/
theorem scoped_writes_miss_nav_elements : ∀ w ∈ Fw.Parts.HeroExitOpt.frameWrites, ¬ w.1.startsWith "nav" := by
  decide +kernel

end Fw.Parts.HeroExitCloseStart

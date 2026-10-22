import Fw.Parts.MorphTween

namespace Fw.Parts.PlatformFade
open Fw.Parts.MorphTween

def blurMax : Rat := 12

def blurOf (v : Rat) : Rat := (1 - v) * blurMax

theorem fade_lo (m : Rat) (h : m ≤ fadeEnd) : fade m = 1 - m * (20 / 11) := by
  unfold fade fadeEnd at *; grind

theorem fade_hi (m : Rat) (h : fadeEnd ≤ m) : fade m = 0 := by
  unfold fade fadeEnd at *; grind

structure Kf where
  off : Rat
  val : Rat
deriving Repr, DecidableEq

def interpKf (ι : Rat → Rat → Rat → Rat) : List Kf → Rat → Rat
  | [], _ => 0
  | [a], _ => a.val
  | a :: b :: rest, p =>
    if p ≤ b.off then ι a.val b.val ((p - a.off) / (b.off - a.off)) else interpKf ι (b :: rest) p

def lerp (a b p : Rat) : Rat := a + (b - a) * p

def kink (f t : Rat) : Rat := (fadeEnd - f) / (t - f)

def easing : Rat × Rat × Rat × Rat := (1 / 3, 1, 2 / 3, 1)

def crosses (f t : Rat) : Bool := decide (0 < kink f t) && decide (kink f t < 1)

def keyframes (f t : Rat) : List Kf :=
  if crosses f t then [⟨0, fade f⟩, ⟨kink f t, 0⟩, ⟨1, fade t⟩] else [⟨0, fade f⟩, ⟨1, fade t⟩]

#guard keyframes 0 1 == [⟨0, 1⟩, ⟨11 / 20, 0⟩, ⟨1, 0⟩]
#guard keyframes 1 0 == [⟨0, 0⟩, ⟨9 / 20, 0⟩, ⟨1, 1⟩]
#guard keyframes 0 0 == [⟨0, 1⟩, ⟨1, 1⟩]
#guard keyframes (3 / 4) 1 == [⟨0, 0⟩, ⟨1, 0⟩]
#guard keyframes (1 / 4) 0 == [⟨0, 6 / 11⟩, ⟨1, 1⟩]
#guard (keyframes (1 / 5) 1).length == 3
#guard crosses 0 1 && crosses 1 0 && !crosses 0 0 && !crosses (11 / 20) 1 && !crosses 1 (11 / 20)

theorem keyframes_length (f t : Rat) : 2 ≤ (keyframes f t).length := by
  unfold keyframes; split <;> simp

theorem keyframes_head (f t : Rat) : (keyframes f t).head? = some ⟨0, fade f⟩ := by
  unfold keyframes; split <;> rfl

theorem keyframes_last (f t : Rat) : (keyframes f t).getLast? = some ⟨1, fade t⟩ := by
  unfold keyframes; split <;> rfl

theorem interp_two (f t p : Rat) (hp1 : p ≤ 1) (hc : crosses f t = false) :
    interpKf lerp (keyframes f t) p = fade f + (fade t - fade f) * p := by
  simp only [keyframes, hc, Bool.false_eq_true, ite_false, interpKf, lerp]
  split <;> grind

theorem kink_up (f t : Rat) (h : f < t) : (0 < kink f t ↔ f < fadeEnd) ∧ (kink f t < 1 ↔ fadeEnd < t) := by
  unfold kink
  rw [Rat.lt_div_iff (by grind), Rat.div_lt_iff (by grind)]
  grind

theorem kink_down (f t : Rat) (h : t < f) : (0 < kink f t ↔ fadeEnd < f) ∧ (kink f t < 1 ↔ t < fadeEnd) := by
  unfold kink
  have : (fadeEnd - f) / (t - f) = (f - fadeEnd) / (f - t) := by grind
  rw [this, Rat.lt_div_iff (by grind), Rat.div_lt_iff (by grind)]
  grind

theorem two_eq (f t p : Rat) (hp0 : 0 ≤ p) (hp1 : p ≤ 1) (hc : crosses f t = false) :
    fade f + (fade t - fade f) * p = fade (f + (t - f) * p) := by
  have hk : ¬ (0 < kink f t ∧ kink f t < 1) := by
    unfold crosses at hc; simp only [Bool.and_eq_false_iff, decide_eq_false_iff_not] at hc; grind
  by_cases hft : f < t
  · have := kink_up f t hft
    have hd1 := Rat.mul_le_mul_of_nonneg_left hp1 (show 0 ≤ t - f by grind)
    have hd0 := Rat.mul_nonneg (show 0 ≤ t - f by grind) hp0
    by_cases hlo : t ≤ fadeEnd
    · rw [fade_lo f (by grind), fade_lo t hlo, fade_lo _ (by grind)]; grind
    · rw [fade_hi f (by grind), fade_hi t (by grind), fade_hi _ (by grind)]; grind
  by_cases hft' : t < f
  · have := kink_down f t hft'
    have hd1 := Rat.mul_le_mul_of_nonneg_left hp1 (show 0 ≤ f - t by grind)
    have hd0 := Rat.mul_nonneg (show 0 ≤ f - t by grind) hp0
    by_cases hlo : f ≤ fadeEnd
    · rw [fade_lo f hlo, fade_lo t (by grind), fade_lo _ (by grind)]; grind
    · rw [fade_hi f (by grind), fade_hi t (by grind), fade_hi _ (by grind)]; grind
  · have : f = t := by grind
    subst this; grind

theorem kink_mul (f t : Rat) (h : f ≠ t) : kink f t * (t - f) = fadeEnd - f := by
  unfold kink; exact Rat.div_mul_cancel (by grind)

theorem three_eq (f t p : Rat) (hp0 : 0 ≤ p) (hp1 : p ≤ 1) (hc : crosses f t = true) :
    interpKf lerp (keyframes f t) p = fade (f + (t - f) * p) := by
  have hk : 0 < kink f t ∧ kink f t < 1 := by
    unfold crosses at hc; simp only [Bool.and_eq_true, decide_eq_true_eq] at hc; exact hc
  have hne : f ≠ t := by
    intro he; subst he; unfold kink at hk; rw [show f - f = 0 by grind, Rat.div_def, Rat.inv_zero, Rat.mul_zero] at hk; grind
  have hkm := kink_mul f t hne
  simp only [keyframes, hc, ite_true, interpKf, lerp]
  by_cases hft : f < t
  · have hku := kink_up f t hft
    have hu : f + (t - f) * p > fadeEnd ↔ kink f t < p := by
      unfold kink; rw [Rat.div_lt_iff (by grind)]; grind
    by_cases hpk : p ≤ kink f t
    · simp only [hpk, ↓reduceIte]; rw [fade_lo f (by grind), fade_lo _ (by grind)]
      rw [show p - 0 = p by grind, show kink f t - 0 = kink f t by grind]
      have hq : p / kink f t * kink f t = p := Rat.div_mul_cancel (by grind)
      generalize p / kink f t = q at hq ⊢
      generalize kink f t = k at hq hkm ⊢
      subst hq
      unfold fadeEnd at hkm
      grind
    · simp only [hpk, hp1, ↓reduceIte]; rw [fade_hi t (by grind), fade_hi _ (by grind)]; grind
  · have hft' : t < f := by grind
    have hkd := kink_down f t hft'
    have hd : f + (t - f) * p > fadeEnd ↔ p < kink f t := by
      unfold kink
      have : (fadeEnd - f) / (t - f) = (f - fadeEnd) / (f - t) := by grind
      rw [this, Rat.lt_div_iff (by grind)]; grind
    by_cases hpk : p ≤ kink f t
    · simp only [hpk, ↓reduceIte]; rw [fade_hi f (by grind)]
      have hm : fadeEnd ≤ f + (t - f) * p := by
        have := Rat.mul_le_mul_of_nonneg_left hpk (show 0 ≤ f - t by grind)
        grind
      rw [fade_hi _ hm]; grind
    · simp only [hpk, hp1, ↓reduceIte]; rw [fade_lo t (by grind), fade_lo _ (by grind)]
      have hr : (p - kink f t) / (1 - kink f t) * (1 - kink f t) = p - kink f t := Rat.div_mul_cancel (by grind)
      generalize (p - kink f t) / (1 - kink f t) = r at hr ⊢
      generalize kink f t = k at hr hkm ⊢
      unfold fadeEnd at hkm
      grind

theorem interp_eq (f t p : Rat) (hp0 : 0 ≤ p) (hp1 : p ≤ 1) :
    interpKf lerp (keyframes f t) p = fade (f + (t - f) * p) := by
  cases hc : crosses f t
  · rw [interp_two f t p hp1 hc]; exact two_eq f t p hp0 hp1 hc
  · exact three_eq f t p hp0 hp1 hc

def blurKfs (ks : List Kf) : List Kf := ks.map fun k => ⟨k.off, blurOf k.val⟩

theorem interp_blur (ks : List Kf) (h : ks ≠ []) (p : Rat) :
    interpKf lerp (blurKfs ks) p = blurOf (interpKf lerp ks p) := by
  induction ks with
  | nil => exact absurd rfl h
  | cons a rest ih =>
    cases rest with
    | nil => rfl
    | cons b rest' =>
      simp only [blurKfs, List.map_cons, interpKf] at ih ⊢
      split
      · simp only [lerp, blurOf]; grind
      · exact ih (by simp)

end Fw.Parts.PlatformFade

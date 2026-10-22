import Fw.Parts.PlatformFade
import Fw.Parts.MorphPanel
import Fw.Parts.MorphConstBounds
import Fw.Engine.WebKit
import Fw.Gate.PathPix

namespace Fw.Parts.MorphPanelThreaded
open Fw.Parts.MorphPanel Fw.Parts.PlatformFade Fw.Parts.MorphTween
open Fw.Engine Fw.Engine.WebKit

def kA : Rat := 2 / 25

def kB : Rat := 4 / 5

def mAt (f t o : Rat) : Rat := f + (t - f) * o

def at_ (f t c : Rat) : Rat := (c - f) / (t - f)

/-- The morph values where the panel's progress bends, as offsets strictly inside a push `f -> t`, in time order. -/
def inner (f t : Rat) : List Rat :=
  if f < t then
    (if f < kA ∧ kA < t then [at_ f t kA] else []) ++ (if f < kB ∧ kB < t then [at_ f t kB] else [])
  else
    (if t < kB ∧ kB < f then [at_ f t kB] else []) ++ (if t < kA ∧ kA < f then [at_ f t kA] else [])

def offs (f t : Rat) : List Rat := 0 :: (inner f t ++ [1])

def track (g : Rat → Rat) (f t : Rat) : List Kf := (offs f t).map fun o => ⟨o, g (mAt f t o)⟩

#guard offs 0 1 == [0, 2 / 25, 4 / 5, 1]
#guard offs 1 0 == [0, 1 / 5, 23 / 25, 1]
#guard offs (1 / 2) 1 == [0, 3 / 5, 1]
#guard offs 0 (1 / 25) == [0, 1]
#guard offs (9 / 10) (1 / 2) == [0, 1 / 4, 1]
#guard offs (1 / 2) (1 / 2) == [0, 1]
#guard (track panelOpacity 0 1) == [⟨0, 0⟩, ⟨2 / 25, 0⟩, ⟨4 / 5, 1⟩, ⟨1, 1⟩]
#guard (track panelBlurPx 1 0) == [⟨0, 0⟩, ⟨1 / 5, 0⟩, ⟨23 / 25, 12⟩, ⟨1, 12⟩]

theorem at_mAt (f t c : Rat) (h : f ≠ t) : mAt f t (at_ f t c) = c := by
  unfold mAt at_
  have : (t - f) ≠ 0 := by grind
  rw [Rat.mul_comm, Rat.div_mul_cancel this]; grind

theorem at_mem_up (f t c : Rat) (h1 : f < c) (h2 : c < t) : 0 < at_ f t c ∧ at_ f t c < 1 := by
  unfold at_
  rw [Rat.lt_div_iff (by grind), Rat.div_lt_iff (by grind)]
  grind

theorem at_mem_down (f t c : Rat) (h1 : t < c) (h2 : c < f) : 0 < at_ f t c ∧ at_ f t c < 1 := by
  unfold at_
  have : (c - f) / (t - f) = (f - c) / (f - t) := by grind
  rw [this, Rat.lt_div_iff (by grind), Rat.div_lt_iff (by grind)]
  grind

theorem div_lt_div_pos (x y d : Rat) (hd : 0 < d) : x / d < y / d ↔ x < y := by
  rw [Rat.div_lt_iff hd, Rat.div_mul_cancel (by grind)]

theorem at_lt_up (f t a b : Rat) (h : f < t) (hab : a < b) : at_ f t a < at_ f t b := by
  unfold at_
  rw [div_lt_div_pos _ _ _ (by grind)]; grind

theorem at_lt_down (f t a b : Rat) (h : t < f) (hab : a < b) : at_ f t b < at_ f t a := by
  unfold at_
  have e : ∀ c, (c - f) / (t - f) = (f - c) / (f - t) := fun c => by grind
  rw [e, e, div_lt_div_pos _ _ _ (by grind)]; grind

def SameZone (u v : Rat) : Prop :=
  (u ≤ kA ∧ v ≤ kA) ∨ (kA ≤ u ∧ u ≤ kB ∧ kA ≤ v ∧ v ≤ kB) ∨ (kB ≤ u ∧ kB ≤ v)

def Chain (f t : Rat) : List Rat → Prop
  | o :: o' :: rest => o < o' ∧ SameZone (mAt f t o) (mAt f t o') ∧ Chain f t (o' :: rest)
  | _ => True

def ZoneAff (g : Rat → Rat) : Prop :=
  ∃ c0 s0 c1 s1 c2 s2 : Rat,
    (∀ m, m ≤ kA → g m = c0 + s0 * m) ∧ (∀ m, kA ≤ m → m ≤ kB → g m = c1 + s1 * m) ∧
      (∀ m, kB ≤ m → g m = c2 + s2 * m)

theorem lerp_le (u v q c : Rat) (h0 : 0 ≤ q) (h1 : q ≤ 1) (hu : u ≤ c) (hv : v ≤ c) : u + (v - u) * q ≤ c := by
  by_cases h : u ≤ v
  · have b := Rat.mul_le_mul_of_nonneg_left h1 (show 0 ≤ v - u by grind)
    grind
  · have a := Rat.mul_nonneg (show 0 ≤ u - v by grind) h0
    grind

theorem lerp_ge (u v q c : Rat) (h0 : 0 ≤ q) (h1 : q ≤ 1) (hu : c ≤ u) (hv : c ≤ v) : c ≤ u + (v - u) * q := by
  by_cases h : u ≤ v
  · have a := Rat.mul_nonneg (show 0 ≤ v - u by grind) h0
    grind
  · have b := Rat.mul_le_mul_of_nonneg_left h1 (show 0 ≤ u - v by grind)
    grind

theorem seg (g : Rat → Rat) (hz : ZoneAff g) (f t o o' p : Rat) (ho : o < o') (hp : o ≤ p) (hp' : p ≤ o')
    (hs : SameZone (mAt f t o) (mAt f t o')) :
    lerp (g (mAt f t o)) (g (mAt f t o')) ((p - o) / (o' - o)) = g (mAt f t p) := by
  obtain ⟨c0, s0, c1, s1, c2, s2, h0, h1, h2⟩ := hz
  have hq : (p - o) / (o' - o) * (o' - o) = p - o := Rat.div_mul_cancel (by grind)
  have hq0 : 0 ≤ (p - o) / (o' - o) := by
    by_cases hn : (p - o) / (o' - o) < 0
    · rw [Rat.div_lt_iff (by grind)] at hn; grind
    · grind
  have hq1 : (p - o) / (o' - o) ≤ 1 := by
    by_cases hn : 1 < (p - o) / (o' - o)
    · rw [Rat.lt_div_iff (by grind)] at hn; grind
    · grind
  generalize (p - o) / (o' - o) = q at hq hq0 hq1 ⊢
  have hw : mAt f t p = mAt f t o + (mAt f t o' - mAt f t o) * q := by
    unfold mAt
    have : (t - f) * (o' - o) * q = (t - f) * (p - o) := by
      rw [Rat.mul_assoc, Rat.mul_comm (o' - o) q, hq]
    grind
  rw [hw]
  generalize mAt f t o = u at *
  generalize mAt f t o' = v at *
  unfold lerp
  unfold SameZone at hs
  rcases hs with ⟨a, b⟩ | ⟨a, b, c, d⟩ | ⟨a, b⟩
  · rw [h0 u a, h0 v b, h0 _ (lerp_le u v q kA hq0 hq1 a b)]; grind
  · rw [h1 u a b, h1 v c d, h1 _ (lerp_ge u v q kA hq0 hq1 a c) (lerp_le u v q kB hq0 hq1 b d)]; grind
  · rw [h2 u a, h2 v b, h2 _ (lerp_ge u v q kB hq0 hq1 a b)]; grind

theorem interp_chain (g : Rat → Rat) (hz : ZoneAff g) (f t p : Rat) :
    ∀ (l : List Rat) (o : Rat), Chain f t (o :: l) → (o :: l).getLast? = some 1 → o ≤ p → p ≤ 1 →
      interpKf lerp ((o :: l).map fun o => (⟨o, g (mAt f t o)⟩ : Kf)) p = g (mAt f t p)
  | [], o, _, hl, hp, hp1 => by
    simp only [List.getLast?_singleton, Option.some.injEq] at hl
    have : p = o := by grind
    subst this; subst hl; simp [interpKf]
  | o' :: rest, o, hc, hl, hp, hp1 => by
    obtain ⟨ho, hs, hc'⟩ := hc
    have hl' : (o' :: rest).getLast? = some 1 := by
      simpa [List.getLast?_cons_cons] using hl
    simp only [List.map_cons, interpKf]
    split
    · exact seg g hz f t o o' p ho hp (by assumption) hs
    · exact interp_chain g hz f t p rest o' hc' hl' (by grind) hp1

theorem mAt_zero (f t : Rat) : mAt f t 0 = f := by unfold mAt; grind

theorem mAt_one (f t : Rat) : mAt f t 1 = t := by unfold mAt; grind

theorem chain_offs (f t : Rat) : Chain f t (offs f t) := by
  have hA : kA < kB := by unfold kA kB; grind
  by_cases hft : f < t
  · have hne : f ≠ t := by grind
    simp only [offs, inner, hft, ite_true]
    by_cases ha : f < kA ∧ kA < t <;> by_cases hb : f < kB ∧ kB < t
    · have m1 := at_mem_up f t kA ha.1 ha.2
      have m2 := at_mem_up f t kB hb.1 hb.2
      have lt := at_lt_up f t kA kB hft hA
      simp only [ha, hb, and_self, ite_true, List.cons_append, List.nil_append, List.append_nil, Chain, SameZone, at_mAt f t _ hne,
        mAt_zero, mAt_one]
      refine ⟨by grind, ?_, by grind, ?_, by grind, ?_, trivial⟩ <;> unfold kA kB at * <;> grind
    · have m1 := at_mem_up f t kA ha.1 ha.2
      simp only [ha, hb, and_self, ite_true, ite_false, List.cons_append, List.nil_append, List.append_nil, Chain, SameZone, at_mAt f t _ hne,
        mAt_zero, mAt_one]
      refine ⟨by grind, ?_, by grind, ?_, trivial⟩ <;> unfold kA kB at * <;> grind
    · have m2 := at_mem_up f t kB hb.1 hb.2
      simp only [ha, hb, and_self, ite_true, ite_false, List.cons_append, List.nil_append, List.append_nil, Chain, SameZone, at_mAt f t _ hne,
        mAt_zero, mAt_one]
      refine ⟨by grind, ?_, by grind, ?_, trivial⟩ <;> unfold kA kB at * <;> grind
    · simp only [ha, hb, and_self, ite_false, List.nil_append, List.cons_append, Chain, SameZone, mAt_zero, mAt_one]
      refine ⟨by grind, ?_, trivial⟩ <;> unfold kA kB at * <;> grind
  · have hne : f ≠ t ∨ f = t := by grind
    simp only [offs, inner, hft, ite_false]
    by_cases ha : t < kA ∧ kA < f <;> by_cases hb : t < kB ∧ kB < f
    · have hne : f ≠ t := by grind
      have m1 := at_mem_down f t kA ha.1 ha.2
      have m2 := at_mem_down f t kB hb.1 hb.2
      have lt := at_lt_down f t kA kB (by grind) hA
      simp only [ha, hb, and_self, ite_true, List.cons_append, List.nil_append, List.append_nil, Chain, SameZone, at_mAt f t _ hne,
        mAt_zero, mAt_one]
      refine ⟨by grind, ?_, by grind, ?_, by grind, ?_, trivial⟩ <;> unfold kA kB at * <;> grind
    · have hne : f ≠ t := by grind
      have m1 := at_mem_down f t kA ha.1 ha.2
      simp only [ha, hb, and_self, ite_true, ite_false, List.cons_append, List.nil_append, List.append_nil, Chain, SameZone, at_mAt f t _ hne,
        mAt_zero, mAt_one]
      refine ⟨by grind, ?_, by grind, ?_, trivial⟩ <;> unfold kA kB at * <;> grind
    · have hne : f ≠ t := by grind
      have m2 := at_mem_down f t kB hb.1 hb.2
      simp only [ha, hb, and_self, ite_true, ite_false, List.cons_append, List.nil_append, List.append_nil, Chain, SameZone, at_mAt f t _ hne,
        mAt_zero, mAt_one]
      refine ⟨by grind, ?_, by grind, ?_, trivial⟩ <;> unfold kA kB at * <;> grind
    · simp only [ha, hb, and_self, ite_false, List.nil_append, List.cons_append, Chain, SameZone, mAt_zero, mAt_one]
      refine ⟨by grind, ?_, trivial⟩ <;> unfold kA kB at * <;> grind

theorem progress_form (m : Rat) : (m - 2 / 25) / (18 / 25) = 25 / 18 * m - 1 / 9 := by grind

theorem progress_lo (m : Rat) (h : m ≤ kA) : panelProgress m = 0 := panelProgress_zero m (by unfold kA at h; exact h)

theorem progress_hi (m : Rat) (h : kB ≤ m) : panelProgress m = 1 := panelProgress_one m (by unfold kB at h; exact h)

theorem progress_mid (m : Rat) (h1 : kA ≤ m) (h2 : m ≤ kB) : panelProgress m = 25 / 18 * m - 1 / 9 := by
  unfold kA kB at *
  unfold panelProgress Fw.Parts.MorphPanel.clamp01
  rw [progress_form]
  grind

theorem zone_opacity : ZoneAff panelOpacity :=
  ⟨0, 0, -1 / 9, 25 / 18, 1, 0, fun m h => by unfold panelOpacity; rw [progress_lo m h]; grind,
    fun m h1 h2 => by unfold panelOpacity; rw [progress_mid m h1 h2]; grind,
    fun m h => by unfold panelOpacity; rw [progress_hi m h]; grind⟩

theorem zone_blur : ZoneAff panelBlurPx :=
  ⟨12, 0, 40 / 3, -50 / 3, 0, 0, fun m h => by unfold panelBlurPx; rw [progress_lo m h]; grind,
    fun m h1 h2 => by unfold panelBlurPx; rw [progress_mid m h1 h2]; grind,
    fun m h => by unfold panelBlurPx; rw [progress_hi m h]; grind⟩

theorem zone_scale : ZoneAff panelScale :=
  ⟨24 / 25, 1 / 25, 24 / 25, 1 / 25, 24 / 25, 1 / 25, fun m _ => by unfold panelScale; grind, fun m _ _ => by unfold panelScale; grind, fun m _ => by unfold panelScale; grind⟩

theorem track_eq (g : Rat → Rat) (hz : ZoneAff g) (f t p : Rat) (hp0 : 0 ≤ p) (hp1 : p ≤ 1) :
    interpKf lerp (track g f t) p = g (f + (t - f) * p) := by
  have hl : (offs f t).getLast? = some 1 := by
    unfold offs; rw [← List.cons_append]; exact List.getLast?_concat ..
  have := interp_chain g hz f t p (inner f t ++ [1]) 0 (chain_offs f t) hl hp0 hp1
  exact this

theorem interp_eq (f t p : Rat) (hp0 : 0 ≤ p) (hp1 : p ≤ 1) :
    interpKf lerp (track panelOpacity f t) p = panelOpacity (f + (t - f) * p) ∧
      interpKf lerp (track panelBlurPx f t) p = panelBlurPx (f + (t - f) * p) ∧
      interpKf lerp (track panelScale f t) p = panelScale (f + (t - f) * p) :=
  ⟨track_eq _ zone_opacity f t p hp0 hp1, track_eq _ zone_blur f t p hp0 hp1, track_eq _ zone_scale f t p hp0 hp1⟩

inductive Band where
  | always | w1000 | w720 | reduced | w640 | w600
deriving Repr, DecidableEq

inductive Anim3 where
  | opacity | filter | transform
deriving Repr, DecidableEq

def Band.query : Band → String
  | .always => "base"
  | .w1000 => "(width<=1000px)"
  | .w720 => "(width<=720px)"
  | .reduced => "(prefers-reduced-motion: reduce)"
  | .w640 => "(width<=640px)"
  | .w600 => "(width<=600px)"

/-- Which of the three animated properties the `.panel` rule of a band declares. -/
def declared : Band → List Anim3
  | .always => [.opacity, .filter, .transform]
  | .reduced => [.filter]
  | _ => []

def installed (reduced : Bool) : Bool := !reduced

theorem bands_only_reduced (b : Band) (hb : b ≠ .always) (p : Anim3) (hp : p ∈ declared b) : b = .reduced := by
  cases b <;> simp_all [declared]

theorem bands_equal (b : Band) (hb : b ≠ .reduced) (p : Anim3) (hp : p ∈ declared b) : b = .always := by
  cases b <;> simp_all [declared]

theorem reduced_no_effect : installed true = false := rfl

theorem band_no_effect_else (b : Band) (hb : b ≠ .reduced) : installed false = true ∧ ∀ p ∈ declared b, b = .always :=
  ⟨rfl, bands_equal b hb⟩

theorem pivot_same (w1 w : Rat) : Fw.Parts.MorphConstBounds.panelOrg w1 w + w1 / 2 = w / 2 :=
  Fw.Parts.MorphConstBounds.pivot_same w1 w

def panelProps : List Fw.Engine.WebKit.CssProp := [.opacity, .filter, .transform]

theorem props_accelerated : Fw.Gate.PathPix.Accelerated panelProps :=
  (Fw.Gate.PathPix.accelerated_iff panelProps).1 rfl

def chg (p : WkProp) : Change WkProp := ⟨0, p, .own⟩

def origChanges : List (Change WkProp) := [chg .opacity, chg .filter, chg .transform]

def stagesOf (cs : List (Change WkProp)) : List Stage :=
  Stage.all.filter fun s => cs.any fun c => decide (s ∈ wkStages c)

/-- A running effect invalidates style on every tick (`KeyframeEffect::animationDidTick`, KeyframeEffect.cpp:2128-2130@862f17d). -/
def tickStages : List Stage := [.style]

#guard stagesOf origChanges == [.style, .layout, .props, .paint]
#guard stagesOf [chg .filter] == [.style, .layout, .props, .paint]
#guard stagesOf [chg .opacity] == [.style]
#guard stagesOf [chg .transform] == [.style, .props]

theorem stagesO_eq : stagesOf origChanges = [.style, .layout, .props, .paint] := by decide +kernel

theorem filter_layout : Stage.layout ∈ wkStages (chg .filter) := by decide +kernel

theorem variant_stages : tickStages = (stagesOf origChanges).filter (· = .style) := by decide +kernel

theorem variant_drops (s : Stage) (h : s = .layout ∨ s = .props ∨ s = .paint) :
    s ∈ stagesOf origChanges ∧ s ∉ tickStages := by
  rcases h with rfl | rfl | rfl <;> decide +kernel

theorem variant_sub : ∀ s ∈ tickStages, s ∈ stagesOf origChanges := by decide +kernel

inductive Tgt where
  | nav
  | platform
  | panel (p : Anim3)
deriving DecidableEq, Repr

def writesO (a b : Rat) : List (Tgt × String) :=
  (if a = b then [] else [(.nav, "--morph")]) ++
    (if fade a = fade b then [] else [(.platform, "--morph-fade")]) ++
    (if panelOpacity a = panelOpacity b then [] else [(.panel .opacity, "opacity")]) ++
    (if panelBlurPx a = panelBlurPx b then [] else [(.panel .filter, "filter")]) ++
    (if panelScale a = panelScale b then [] else [(.panel .transform, "transform")])

def writesP (a b : Rat) : List (Tgt × String) :=
  (if a = b then [] else [(.nav, "--morph")]) ++ (if fade a = fade b then [] else [(.platform, "--morph-fade")])

def writesB (a b : Rat) : List (Tgt × String) := if a = b then [] else [(.nav, "--morph")]

def recalc (w : List (Tgt × String)) : Bool := !w.isEmpty

#guard writesO 0 (1 / 2) ==
  [(.nav, "--morph"), (.platform, "--morph-fade"), (.panel .opacity, "opacity"), (.panel .filter, "filter"),
    (.panel .transform, "transform")]
#guard writesP 0 (1 / 2) == [(.nav, "--morph"), (.platform, "--morph-fade")]
#guard writesB 0 (1 / 2) == [(.nav, "--morph")] && writesB (1 / 2) (1 / 2) == []

theorem writesP_sub (a b : Rat) : writesP a b = (writesO a b).filter fun w => w.1 = .nav ∨ w.1 = .platform := by
  unfold writesP writesO
  by_cases h : a = b <;> by_cases hf : fade a = fade b <;>
    by_cases h1 : panelOpacity a = panelOpacity b <;> by_cases h2 : panelBlurPx a = panelBlurPx b <;>
    by_cases h3 : panelScale a = panelScale b <;> simp [h, hf, h1, h2, h3]

theorem writesB_sub (a b : Rat) : writesB a b = (writesO a b).filter (·.1 = .nav) := by
  unfold writesB writesO
  by_cases h : a = b <;> by_cases hf : fade a = fade b <;>
    by_cases h1 : panelOpacity a = panelOpacity b <;> by_cases h2 : panelBlurPx a = panelBlurPx b <;>
    by_cases h3 : panelScale a = panelScale b <;> simp [h, hf, h1, h2, h3]

theorem recalc_same (a b : Rat) : recalc (writesP a b) = recalc (writesO a b) := by
  unfold recalc writesP writesO
  by_cases h : a = b
  · subst h; simp
  · simp [h]

theorem recalc_same_bundle (a b : Rat) : recalc (writesB a b) = recalc (writesO a b) := by
  unfold recalc writesB writesO
  by_cases h : a = b
  · subst h; simp
  · simp [h]

def layersOf (p : Policy) (rs : List (List CompReason)) : Nat :=
  (rs.filter fun r => r.any (composites p)).length

theorem animation_composites (p : Policy) : composites p .animation = true :=
  (own_robust .animation).2 (by simp [robust]) p

/-- Layer budget: the effect adds the `animation` reason to the panel. If the panel already has a layer, no layer is added. -/
theorem layer_budget (p : Policy) (others : List (List CompReason)) (rs : List CompReason)
    (h : rs.any (composites p) = true) :
    layersOf p (others ++ [.animation :: rs]) = layersOf p (others ++ [rs]) := by
  simp [layersOf, List.filter_append, h, animation_composites]

theorem layer_budget_new (p : Policy) (others : List (List CompReason)) (rs : List CompReason)
    (h : rs.any (composites p) = false) :
    layersOf p (others ++ [.animation :: rs]) = layersOf p (others ++ [rs]) + 1 := by
  simp [layersOf, List.filter_append, h, animation_composites]

end Fw.Parts.MorphPanelThreaded

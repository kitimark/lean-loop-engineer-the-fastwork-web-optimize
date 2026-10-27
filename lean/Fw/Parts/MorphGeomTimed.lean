import Fw.Parts.MorphGeomGen
import Fw.Parts.MorphTweenOpt
namespace Fw.Parts.MorphGeomTimed
open Fw.Parts.MorphGeom Fw.Parts.MorphTween
open Fw.Parts.MorphTweenOpt (curveX curveY bezier_eq_ease curveY_eq_ease solver_exact curveY_sub slope_mem)


def Asc : Track → Prop
  | (p, _) :: (q, b) :: rest => p < q ∧ Asc ((q, b) :: rest)
  | _ => True

def lin (p a q b m : Rat) : Rat := a + (b - a) * (m - p) / (q - p)

def cutL : Track → Rat → Track
  | (p, a) :: (q, b) :: rest, m0 =>
    if m0 < q then (m0, lin p a q b m0) :: (q, b) :: rest else cutL ((q, b) :: rest) m0
  | l, _ => l

def cutR : Track → Rat → Track
  | (p, a) :: (q, b) :: rest, g =>
    if g ≤ q then [(p, a), (g, lin p a q b g)] else (p, a) :: cutR ((q, b) :: rest) g
  | l, _ => l

theorem lin_same (p a q b m0 m : Rat) (hpq : p < q) (h0 : m0 < q) :
    lin m0 (lin p a q b m0) q b m = lin p a q b m := by
  unfold lin
  have h1 : q - p ≠ 0 := by grind
  have h2 : q - m0 ≠ 0 := by grind
  grind

theorem lin_at_right (p a q b : Rat) (h : p < q) : lin p a q b q = b := by
  unfold lin
  have h1 : q - p ≠ 0 := by grind
  grind

theorem lin_at_left (p a q b : Rat) : lin p a q b p = a := by
  unfold lin; grind

theorem lin_cut (p a q b g m : Rat) (hpq : p < q) (hpm : p ≤ m) (hmg : m ≤ g) :
    lin p a g (lin p a q b g) m = lin p a q b m := by
  by_cases hg : g = p
  · have : m = p := by grind
    subst this; rw [lin_at_left, lin_at_left]
  · unfold lin
    have h1 : q - p ≠ 0 := by grind
    have h2 : g - p ≠ 0 := by grind
    grind

theorem asc_cutL : ∀ (l : Track) (m0 : Rat), Asc l → Asc (cutL l m0)
  | [], _, _ => trivial
  | [_], _, _ => trivial
  | (p, a) :: (q, b) :: rest, m0, h => by
    unfold cutL
    split
    · exact ⟨by grind, h.2⟩
    · exact asc_cutL ((q, b) :: rest) m0 h.2

theorem eval_head : ∀ (q b : Rat) (rest : Track), Asc ((q, b) :: rest) → Track.eval ((q, b) :: rest) q = b
  | q, b, [], _ => by simp [Track.eval]
  | q, b, (r, c) :: rest, h => by
    have : q < r := h.1
    simp only [Track.eval, show q ≤ r by grind, ite_true]
    grind

theorem cutL_head : ∀ (l : Track) (p : Rat) (a : Rat) (rest : Track) (m0 : Rat), l = (p, a) :: rest → p ≤ m0 →
    ∃ p' a' rest', cutL l m0 = (p', a') :: rest' ∧ p' ≤ m0
  | _, p, a, [], m0, h, hp => ⟨p, a, [], by subst h; simp [cutL], hp⟩
  | _, p, a, (q, b) :: rest, m0, h, hp => by
    subst h
    unfold cutL
    split
    · exact ⟨m0, _, _, rfl, Rat.le_refl⟩
    · rename_i hq
      exact cutL_head ((q, b) :: rest) q b rest m0 rfl (by grind)

theorem eval_cutL : ∀ (l : Track) (m0 m : Rat), Asc l → m0 ≤ m → Track.eval (cutL l m0) m = Track.eval l m
  | [], _, _, _, _ => by simp [cutL]
  | [_], _, _, _, _ => by simp [cutL]
  | (p, a) :: (q, b) :: rest, m0, m, h, hm => by
    have hpq : p < q := h.1
    unfold cutL
    split
    · rename_i h0
      simp only [Track.eval]
      by_cases hmq : m ≤ q
      · simp only [hmq, ite_true]
        exact lin_same p a q b m0 m hpq h0
      · simp only [hmq, ite_false]
    · rename_i h0
      rw [eval_cutL ((q, b) :: rest) m0 m h.2 hm]
      by_cases hmq : m ≤ q
      · have hm' : m = q := by grind
        subst hm'
        rw [eval_head _ _ _ h.2]
        simp only [Track.eval, Rat.le_refl, ite_true]
        exact (lin_at_right p a m b hpq).symm
      · simp only [Track.eval, hmq, ite_false]

theorem cutR_cons : ∀ (q b : Rat) (r : Track) (g : Rat), ∃ t, cutR ((q, b) :: r) g = (q, b) :: t
  | q, b, [], g => ⟨[], by simp [cutR]⟩
  | q, b, (s, c) :: r, g => by
    unfold cutR
    split
    · exact ⟨_, rfl⟩
    · exact ⟨_, rfl⟩

theorem eval_cutR : ∀ (rest : Track) (p a g m : Rat), Asc ((p, a) :: rest) → p ≤ m → m ≤ g →
    Track.eval (cutR ((p, a) :: rest) g) m = Track.eval ((p, a) :: rest) m
  | [], _, _, _, _, _, _, _ => by simp [cutR]
  | (q, b) :: rest, p, a, g, m, h, hpm, hmg => by
    have hpq : p < q := h.1
    unfold cutR
    split
    · simp only [Track.eval, hmg, ite_true]
      by_cases hmq : m ≤ q
      · simp only [hmq, ite_true]
        exact lin_cut p a q b g m hpq hpm hmg
      · simp only [hmq, ite_false]
        grind
    · rename_i hg
      obtain ⟨t, ht⟩ := cutR_cons q b rest g
      rw [ht]
      by_cases hmq : m ≤ q
      · simp only [Track.eval, hmq, ite_true]
      · have := eval_cutR rest q b g m h.2 (by grind) hmg
        rw [ht] at this
        simp only [Track.eval, hmq, ite_false]
        exact this

def trim (l : Track) (m0 g : Rat) : Track := cutR (cutL l m0) g

theorem eval_trim (p a : Rat) (rest : Track) (m0 m g : Rat) (h : Asc ((p, a) :: rest)) (hp : p ≤ m0)
    (h1 : m0 ≤ m) (h2 : m ≤ g) :
    Track.eval (trim ((p, a) :: rest) m0 g) m = Track.eval ((p, a) :: rest) m := by
  obtain ⟨p', a', r', hc, hp'⟩ := cutL_head _ p a rest m0 rfl hp
  unfold trim
  rw [hc]
  have hA := asc_cutL _ m0 h
  rw [hc] at hA
  rw [eval_cutR r' p' a' g m hA (by grind) h2, ← hc]
  exact eval_cutL _ m0 m h h1

def pull (l : Track) (m0 c : Rat) : Track := l.map fun x => ((x.1 - m0) / c, x.2)

theorem eval_pull : ∀ (l : Track) (m0 c u : Rat), Asc l → 0 < c →
    Track.eval (pull l m0 c) u = Track.eval l (m0 + c * u)
  | [], _, _, _, _, _ => by simp [pull, Track.eval]
  | [_], _, _, _, _, _ => by simp [pull, Track.eval]
  | (p, a) :: (q, b) :: rest, m0, c, u, h, hc => by
    have hpq : p < q := h.1
    have ih := eval_pull ((q, b) :: rest) m0 c u h.2 hc
    simp only [pull, List.map_cons] at ih ⊢
    simp only [Track.eval]
    have hiff : u ≤ (q - m0) / c ↔ m0 + c * u ≤ q := by
      constructor
      · intro h1
        have : c * u ≤ c * ((q - m0) / c) := Rat.mul_le_mul_of_nonneg_left h1 (by grind)
        have hc0 : c ≠ 0 := by grind
        have e : c * ((q - m0) / c) = q - m0 := by grind
        grind
      · intro h1
        have h2 : c * u ≤ q - m0 := by grind
        have h3 : (c * u) / c ≤ (q - m0) / c := by
          rw [Rat.div_def, Rat.div_def]
          exact Rat.mul_le_mul_of_nonneg_right h2 (Rat.le_of_lt (Rat.inv_pos.mpr hc))
        have : (c * u) / c = u := by grind
        grind
    by_cases hq : u ≤ (q - m0) / c
    · have hq' : m0 + c * u ≤ q := hiff.mp hq
      simp only [hq, hq', ite_true]
      have h1 : q - p ≠ 0 := by grind
      have h2 : c ≠ 0 := by grind
      grind
    · have hq' : ¬ m0 + c * u ≤ q := fun x => hq (hiff.mpr x)
      simp only [hq, hq', ite_false]
      exact ih

def rebaseUp (l : Track) (m0 g : Rat) : Track := pull (trim l m0 g) m0 (g - m0)

theorem asc_cutR : ∀ (rest : Track) (p a g : Rat), Asc ((p, a) :: rest) → p < g → Asc (cutR ((p, a) :: rest) g)
  | [], _, _, _, _, _ => trivial
  | (q, b) :: rest, p, a, g, h, hg => by
    unfold cutR
    split
    · rename_i h1
      exact ⟨hg, trivial⟩
    · rename_i h1
      obtain ⟨t, ht⟩ := cutR_cons q b rest g
      have := asc_cutR rest q b g h.2 (by grind)
      rw [ht] at this ⊢
      exact ⟨h.1, this⟩

theorem rebaseUp_eval (p a : Rat) (rest : Track) (m0 g u : Rat) (h : Asc ((p, a) :: rest)) (hp : p ≤ m0)
    (hg : m0 < g) (hu0 : 0 ≤ u) (hu1 : u ≤ 1) :
    Track.eval (rebaseUp ((p, a) :: rest) m0 g) u = Track.eval ((p, a) :: rest) (m0 + (g - m0) * u) := by
  obtain ⟨p', a', r', hc, hp'⟩ := cutL_head _ p a rest m0 rfl hp
  have hA := asc_cutL _ m0 h
  rw [hc] at hA
  have hB : Asc (trim ((p, a) :: rest) m0 g) := by
    unfold trim; rw [hc]; exact asc_cutR r' p' a' g hA (by grind)
  unfold rebaseUp
  rw [eval_pull _ m0 (g - m0) u hB (by grind)]
  have hm1 : m0 ≤ m0 + (g - m0) * u := by
    have : 0 ≤ (g - m0) * u := Rat.mul_nonneg (by grind) hu0
    grind
  have hm2 : m0 + (g - m0) * u ≤ g := by
    have : (g - m0) * u ≤ (g - m0) * 1 := Rat.mul_le_mul_of_nonneg_left hu1 (by grind)
    grind
  exact eval_trim p a rest m0 _ g h hp hm1 hm2


def mirror (l : Track) : Track := l.reverse.map fun x => (-x.1, x.2)

def lastP : Rat → Track → Rat
  | p, [] => p
  | _, (q, _) :: r => lastP q r

theorem mirror_cons (p a : Rat) (l : Track) : mirror ((p, a) :: l) = mirror l ++ [(-p, a)] := by
  simp [mirror]

theorem asc_snoc : ∀ (Y : Track) (z bz w c : Rat), Asc (Y ++ [(z, bz)]) → z < w → Asc (Y ++ [(z, bz), (w, c)])
  | [], _, _, _, _, _, hw => ⟨hw, trivial⟩
  | [(_, _)], _, _, _, _, h, hw => ⟨h.1, hw, trivial⟩
  | (_, _) :: (q, b) :: Y, z, bz, w, c, h, hw => ⟨h.1, asc_snoc ((q, b) :: Y) z bz w c h.2 hw⟩

theorem mirror_head : ∀ (F : Track) (q b : Rat), ∃ y rest, mirror ((q, b) :: F) = (-(lastP q F), y) :: rest
  | [], q, b => ⟨b, [], by simp [mirror, lastP]⟩
  | (r, c) :: F, q, b => by
    obtain ⟨y, rest, h⟩ := mirror_head F r c
    refine ⟨y, rest ++ [(-q, b)], ?_⟩
    rw [mirror_cons, h]
    simp [lastP]

theorem asc_mirror : ∀ (F : Track) (q b : Rat), Asc ((q, b) :: F) → Asc (mirror ((q, b) :: F))
  | [], q, b, _ => by simp [mirror, Asc]
  | (r, c) :: F, q, b, h => by
    obtain ⟨y, rest, hm⟩ := mirror_head F r c
    have ih := asc_mirror F r c h.2
    rw [mirror_cons]
    obtain ⟨Y, hY⟩ : ∃ Y, mirror ((r, c) :: F) = Y ++ [(-r, c)] := ⟨mirror F, mirror_cons r c F⟩
    rw [hY] at ih ⊢
    simpa [List.append_assoc] using asc_snoc Y (-r) c (-q) b ih (by have := h.1; grind)

theorem asc_lt_mem : ∀ (Y : Track) (q b : Rat), Asc ((q, b) :: Y) → ∀ x ∈ Y, q < x.1
  | [], _, _, _, x, hx => by simp at hx
  | (r, c) :: Y, q, b, h, x, hx => by
    have h1 : q < r := h.1
    rcases List.mem_cons.mp hx with rfl | hx'
    · exact h1
    · have := asc_lt_mem Y r c h.2 x hx'
      grind

theorem eval_snoc : ∀ (Y : Track) (z bz w c m : Rat),
    Asc (Y ++ [(z, bz), (w, c)]) → (∀ p a rest, Y ++ [(z, bz)] = (p, a) :: rest → p ≤ m) → m ≤ w →
    Track.eval (Y ++ [(z, bz), (w, c)]) m = if m ≤ z then Track.eval (Y ++ [(z, bz)]) m else lin z bz w c m
  | [], z, bz, w, c, m, h, hd, hw => by
    have hz : z ≤ m := hd z bz [] rfl
    simp only [List.nil_append, Track.eval, hw, ite_true]
    by_cases hmz : m ≤ z
    · have : m = z := by grind
      subst this
      simp only [Rat.le_refl, ite_true]
      grind
    · simp only [hmz, ite_false]; unfold lin; grind
  | [(p, a)], z, bz, w, c, m, h, hd, hw => by
    simp only [List.cons_append, List.nil_append, Track.eval, hw, ite_true]
    by_cases hmz : m ≤ z
    · simp [hmz]
    · simp only [hmz, ite_false]; unfold lin; grind
  | (p, a) :: (q, b) :: Y, z, bz, w, c, m, h, hd, hw => by
    have hqz : q < z := by
      have := asc_lt_mem (Y ++ [(z, bz), (w, c)]) q b h.2 (z, bz) (by simp)
      exact this
    by_cases hmq : m ≤ q
    · have hmz : m ≤ z := by grind
      simp only [List.cons_append, Track.eval, hmq, hmz, ite_true]
    · have hqm : q ≤ m := by grind
      have ih := eval_snoc ((q, b) :: Y) z bz w c m h.2
        (fun p' a' rest' e => by
          simp only [List.cons_append, List.cons.injEq] at e
          grind) hw
      simp only [List.cons_append] at ih ⊢
      simp only [Track.eval, hmq, ite_false]
      exact ih

theorem eval_mirror : ∀ (F : Track) (p a m : Rat), Asc ((p, a) :: F) → p ≤ m → m ≤ lastP p F →
    Track.eval (mirror ((p, a) :: F)) (-m) = Track.eval ((p, a) :: F) m
  | [], p, a, m, _, _, _ => by simp [mirror, Track.eval]
  | (q, b) :: F, p, a, m, h, hpm, hml => by
    have hpq : p < q := h.1
    obtain ⟨y, rest, hh⟩ := mirror_head F q b
    have ih := eval_mirror F q b
    rw [mirror_cons, show mirror ((q, b) :: F) = mirror F ++ [(-q, b)] from mirror_cons q b F]
    have hA : Asc (mirror F ++ [(-q, b), (-p, a)]) := by
      have h1 := asc_mirror F q b h.2
      rw [mirror_cons] at h1
      exact asc_snoc (mirror F) (-q) b (-p) a h1 (by grind)
    have hs := eval_snoc (mirror F) (-q) b (-p) a (-m) hA (by
      intro p' a' rest' e
      have e' : mirror ((q, b) :: F) = (p', a') :: rest' := by rw [mirror_cons]; exact e
      rw [hh] at e'
      simp only [List.cons.injEq] at e'
      have : lastP p ((q, b) :: F) = lastP q F := rfl
      grind) (by grind)
    simp only [List.append_assoc, List.cons_append, List.nil_append] at hs ⊢
    rw [hs]
    by_cases hqm : q ≤ m
    · have hle : -m ≤ -q := by grind
      simp only [hle, ite_true]
      rw [← mirror_cons q b F]
      have hml' : m ≤ lastP q F := hml
      rw [ih m h.2 hqm hml']
      simp only [Track.eval]
      by_cases hmq : m ≤ q
      · have : m = q := by grind
        subst this
        rw [eval_head _ _ _ h.2]
        simp only [Rat.le_refl, ite_true]
        exact (lin_at_right p a m b hpq).symm
      · simp [hmq]
    · have hn : ¬ (-m ≤ -q) := by grind
      simp only [hn, ite_false]
      have hmq : m ≤ q := by grind
      simp only [Track.eval, hmq, ite_true]
      have : q - p ≠ 0 := by grind
      unfold lin; grind


def rebase (l : Track) (m0 g : Rat) : Track :=
  if m0 < g then rebaseUp l m0 g else rebaseUp (mirror l) (-m0) (-g)

theorem rebase_eval (p a : Rat) (rest : Track) (m0 g u : Rat) (h : Asc ((p, a) :: rest)) (hp : p ≤ m0)
    (hm : m0 ≤ lastP p rest) (hgp : p ≤ g) (_hgl : g ≤ lastP p rest) (hne : m0 ≠ g) (hu0 : 0 ≤ u) (hu1 : u ≤ 1) :
    Track.eval (rebase ((p, a) :: rest) m0 g) u = Track.eval ((p, a) :: rest) (m0 + (g - m0) * u) := by
  unfold rebase
  split
  · rename_i hlt
    exact rebaseUp_eval p a rest m0 g u h hp hlt hu0 hu1
  · rename_i hlt
    have hgt : g < m0 := by grind
    obtain ⟨y, r', hh⟩ := mirror_head rest p a
    have hA := asc_mirror rest p a h
    rw [hh] at hA
    have hmid0 : p ≤ m0 + (g - m0) * u := by
      have : (m0 - g) * u ≤ (m0 - g) * 1 := Rat.mul_le_mul_of_nonneg_left hu1 (by grind)
      grind
    have hmid1 : m0 + (g - m0) * u ≤ lastP p rest := by
      have : 0 ≤ (m0 - g) * u := Rat.mul_nonneg (by grind) hu0
      grind
    have key := rebaseUp_eval (-(lastP p rest)) y r' (-m0) (-g) u hA (by grind) (by grind) hu0 hu1
    rw [← hh] at key
    rw [key]
    have e : -m0 + (-g - -m0) * u = -(m0 + (g - m0) * u) := by grind
    rw [e]
    exact eval_mirror rest p a _ h hmid0 hmid1


theorem clamp01_mem (x : Rat) : 0 ≤ clamp01 x ∧ clamp01 x ≤ 1 := by unfold clamp01; grind

theorem ease_mem (x : Rat) : 0 ≤ ease x ∧ ease x ≤ 1 := by
  have := clamp01_mem x
  unfold ease
  generalize hcc : 1 - clamp01 x = c
  have hc : 0 ≤ c ∧ c ≤ 1 := by grind
  have a : c * c ≤ c * 1 := Rat.mul_le_mul_of_nonneg_left hc.2 hc.1
  have a0 : 0 ≤ c * c := Rat.mul_nonneg hc.1 hc.1
  have b : c * c * c ≤ c * c * 1 := Rat.mul_le_mul_of_nonneg_left hc.2 a0
  have b0 : 0 ≤ c * c * c := Rat.mul_nonneg a0 hc.1
  grind

theorem tween_value (f t el : Rat) : (tween f t el).value = f + (t - f) * ease (el / duration) := by
  have hc := clamp01_mem (el / duration)
  by_cases h : 1 ≤ clamp01 (el / duration)
  · have h1 : clamp01 (el / duration) = 1 := by grind
    have h2 : ease (el / duration) = 1 := by unfold ease; rw [h1]; grind
    simp only [tween, h, ite_true, h2]
    grind
  · have h1 : clamp01 (clamp01 (el / duration)) = clamp01 (el / duration) := by unfold clamp01; grind
    have h2 : ease (clamp01 (el / duration)) = ease (el / duration) := by unfold ease; rw [h1]
    simp only [tween, h, ite_false, h2]



def idealM (s : St) (t : Rat) : Rat := (tween s.f s.t (t - s.start)).value

def pushAt (s : St) (g e : Rat) : St := push { s with value := idealM s e } g false e

structure Ev where
  e : Rat
  g : Rat

def run (evs : List Ev) : St := evs.foldl (fun s ev => pushAt s ev.g ev.e) MorphTween.rest

def shown (tr : Track) (s : St) (t : Rat) : Rat :=
  Track.eval (rebase tr s.f s.t) (curveY ((t - s.start) / duration))

def InUnit (s : St) : Prop := 0 ≤ s.f ∧ s.f ≤ 1 ∧ 0 ≤ s.t ∧ s.t ≤ 1

theorem frac_mem (el : Rat) (h0 : 0 ≤ el) (h1 : el ≤ 680) : 0 ≤ el / duration ∧ el / duration ≤ 1 := by
  unfold duration
  have e : 680 * (el / 680) = el := by grind
  have : 0 ≤ el / 680 := by
    rw [Rat.div_def]; exact Rat.mul_nonneg h0 (by grind)
  grind

theorem timed_eq_ideal_set (p a : Rat) (rest : Track) (s : St) (t : Rat) (h : Asc ((p, a) :: rest))
    (hp : p ≤ s.f) (hf : s.f ≤ lastP p rest) (hgp : p ≤ s.t) (hgl : s.t ≤ lastP p rest) (hne : s.f ≠ s.t)
    (ht0 : s.start ≤ t) (ht1 : t ≤ s.start + 680) :
    shown ((p, a) :: rest) s t = Track.eval ((p, a) :: rest) (idealM s t) := by
  have hx := frac_mem (t - s.start) (by grind) (by grind)
  have hy := ease_mem ((t - s.start) / duration)
  unfold shown idealM
  rw [(curveY_eq_ease _ hx.1 hx.2 : curveY ((t - s.start) / duration) = ease ((t - s.start) / duration)),
    rebase_eval p a rest s.f s.t _ h hp hf hgp hgl hne hy.1 hy.2, tween_value]

theorem reverse_continuous (p a : Rat) (rest : Track) (s : St) (g e : Rat) (h : Asc ((p, a) :: rest))
    (hs : InUnit s) (hg0 : 0 ≤ g) (hg1 : g ≤ 1) (hp : p ≤ 0) (hl : 1 ≤ lastP p rest) (hne : s.t ≠ g)
    (hne' : idealM s e ≠ g) (he0 : s.start ≤ e) (he1 : e ≤ s.start + 680) (hmem : 0 ≤ idealM s e ∧ idealM s e ≤ 1)
    (hold : s.f ≠ s.t) :
    shown ((p, a) :: rest) (pushAt s g e) e = shown ((p, a) :: rest) s e := by
  have hn : pushAt s g e = { s with value := idealM s e, target := g, f := idealM s e, t := g, start := e, pending := true } := by
    unfold pushAt push
    have : ¬ (s.target = g ∧ s.t = g) := fun hh => hne hh.2
    simp [this]
  have h1 := timed_eq_ideal_set p a rest s e h (by grind [InUnit]) (by grind [InUnit]) (by grind [InUnit]) (by grind [InUnit]) hold he0 he1
  have h2 := timed_eq_ideal_set p a rest (pushAt s g e) e h (by rw [hn]; grind) (by rw [hn]; grind) (by rw [hn]; grind)
    (by rw [hn]; grind) (by rw [hn]; exact hne') (by rw [hn]; grind) (by rw [hn]; grind)
  rw [h1, h2]
  have : idealM (pushAt s g e) e = idealM s e := by
    rw [hn]; unfold idealM; simp only [tween_value]
    have z : ease ((e - e) / duration) = 0 := by
      have : e - e = 0 := by grind
      rw [this]; unfold ease clamp01 duration; decide +kernel
    rw [z]; grind
  rw [this]


theorem clamp_lip (x y d : Rat) (h1 : x - y ≤ d) (h2 : y - x ≤ d) :
    clamp01 x - clamp01 y ≤ d ∧ clamp01 y - clamp01 x ≤ d := by
  unfold clamp01; grind

theorem mul_bd (A B D : Rat) (hA : -1 ≤ A ∧ A ≤ 1) (hB1 : B ≤ D) (hB2 : -B ≤ D) :
    A * B ≤ D ∧ -(A * B) ≤ D := by
  have a1 : 0 ≤ (1 + A) * (D - B) := Rat.mul_nonneg (by grind) (by grind)
  have a2 : 0 ≤ (1 - A) * (D + B) := Rat.mul_nonneg (by grind) (by grind)
  have a3 : 0 ≤ (1 - A) * (D - B) := Rat.mul_nonneg (by grind) (by grind)
  have a4 : 0 ≤ (1 + A) * (D + B) := Rat.mul_nonneg (by grind) (by grind)
  grind

theorem ease_eq_curveY (x : Rat) : ease x = curveY (clamp01 x) := by
  have h := clamp01_mem x
  rw [curveY_eq_ease _ h.1 h.2]
  have : clamp01 (clamp01 x) = clamp01 x := by unfold clamp01; grind
  unfold ease; rw [this]

theorem ease_lip_half (x y d : Rat) (h1 : x - y ≤ d) (h2 : y - x ≤ d) : ease x - ease y ≤ 3 * d := by
  have hc := clamp_lip x y d h1 h2
  have hx := clamp01_mem x
  have hy := clamp01_mem y
  rw [ease_eq_curveY x, ease_eq_curveY y, curveY_sub]
  have hw := slope_mem (1 - clamp01 x) (1 - clamp01 y) (by grind) (by grind) (by grind) (by grind)
  generalize (1 - clamp01 x) * (1 - clamp01 x) + (1 - clamp01 x) * (1 - clamp01 y) + (1 - clamp01 y) * (1 - clamp01 y) = w at *
  generalize hA : clamp01 x - clamp01 y = A at *
  have hd : 0 ≤ d := by grind
  have b2 : 0 ≤ (3 - w) * (d + A) := Rat.mul_nonneg (by grind) (by grind)
  have b3 : 0 ≤ w * (d - A) := Rat.mul_nonneg (by grind) (by grind)
  have b5 : 0 ≤ (3 - w) * d := Rat.mul_nonneg (by grind) (by grind)
  grind

theorem ease_lip (x y d : Rat) (h1 : x - y ≤ d) (h2 : y - x ≤ d) :
    ease x - ease y ≤ 3 * d ∧ ease y - ease x ≤ 3 * d :=
  ⟨ease_lip_half x y d h1 h2, ease_lip_half y x d h2 h1⟩

theorem faithful_gap (s : St) (fr e g t Δ : Rat) (hs : InUnit s)
    (h2 : fr ≤ e) (h3 : e - fr ≤ Δ) :
    (tween (idealM s fr) g (t - e)).value - (tween (idealM s e) g (t - e)).value ≤ 3 * Δ / 680 ∧
    (tween (idealM s e) g (t - e)).value - (tween (idealM s fr) g (t - e)).value ≤ 3 * Δ / 680 := by
  have hE := ease_mem ((t - e) / duration)
  have hd : e / duration - fr / duration ≤ Δ / 680 := by unfold duration; grind
  have hd2 : fr / duration - e / duration ≤ Δ / 680 := by unfold duration; grind
  have hl := ease_lip ((fr - s.start) / duration) ((e - s.start) / duration) (Δ / 680) (by unfold duration; grind)
    (by unfold duration; grind)
  have hm := mul_bd (s.t - s.f) (ease ((fr - s.start) / duration) - ease ((e - s.start) / duration)) (3 * (Δ / 680))
    (by grind [InUnit]) hl.1 (by grind)
  have hv : (idealM s fr) - (idealM s e) = (s.t - s.f) * (ease ((fr - s.start) / duration) - ease ((e - s.start) / duration)) := by
    unfold idealM; simp only [tween_value]; grind
  have hw := mul_bd (1 - ease ((t - e) / duration)) ((idealM s fr) - (idealM s e)) (3 * (Δ / 680)) (by grind)
    (by rw [hv]; exact hm.1) (by rw [hv]; exact hm.2)
  simp only [tween_value]
  constructor <;> grind



theorem idealM_mem (s : St) (t : Rat) (hs : InUnit s) : 0 ≤ idealM s t ∧ idealM s t ≤ 1 := by
  have hE := ease_mem ((t - s.start) / duration)
  unfold idealM
  rw [tween_value]
  generalize ease ((t - s.start) / duration) = E at *
  have a1 : 0 ≤ (1 - E) * s.f := Rat.mul_nonneg (by grind) (by grind [InUnit])
  have a2 : 0 ≤ E * s.t := Rat.mul_nonneg (by grind) (by grind [InUnit])
  have a3 : 0 ≤ (1 - E) * (1 - s.f) := Rat.mul_nonneg (by grind) (by grind [InUnit])
  have a4 : 0 ≤ E * (1 - s.t) := Rat.mul_nonneg (by grind) (by grind [InUnit])
  constructor <;> grind

theorem pushAt_in (s : St) (g e : Rat) (hs : InUnit s) (hg0 : 0 ≤ g) (hg1 : g ≤ 1) : InUnit (pushAt s g e) := by
  have hm := idealM_mem s e hs
  unfold pushAt push
  split
  · exact hs
  · exact ⟨hm.1, hm.2, hg0, hg1⟩

theorem run_in (evs : List Ev) (hg : ∀ ev ∈ evs, 0 ≤ ev.g ∧ ev.g ≤ 1) : InUnit (run evs) := by
  unfold run
  suffices ∀ (l : List Ev) (s : St), InUnit s → (∀ ev ∈ l, 0 ≤ ev.g ∧ ev.g ≤ 1) →
      InUnit (l.foldl (fun s ev => pushAt s ev.g ev.e) s) from
    this evs MorphTween.rest ⟨by decide, by decide, by decide, by decide⟩ hg
  intro l
  induction l with
  | nil => intro s hs _; exact hs
  | cons ev l ih =>
    intro s hs hl
    exact ih _ (pushAt_in s ev.g ev.e hs (hl ev (by simp)).1 (hl ev (by simp)).2) (fun x hx => hl x (by simp [hx]))

theorem timed_eq_ideal (evs : List Ev) (hg : ∀ ev ∈ evs, 0 ≤ ev.g ∧ ev.g ≤ 1) (p a : Rat) (rest : Track)
    (h : Asc ((p, a) :: rest)) (hp : p ≤ 0) (hl : 1 ≤ lastP p rest) (t : Rat) (hne : (run evs).f ≠ (run evs).t)
    (ht0 : (run evs).start ≤ t) (ht1 : t ≤ (run evs).start + 680) :
    shown ((p, a) :: rest) (run evs) t = Track.eval ((p, a) :: rest) (idealM (run evs) t) := by
  have hs := run_in evs hg
  exact timed_eq_ideal_set p a rest _ t h (by grind [InUnit]) (by grind [InUnit]) (by grind [InUnit])
    (by grind [InUnit]) hne ht0 ht1

theorem rebase_end (p a : Rat) (rest : Track) (m0 g : Rat) (h : Asc ((p, a) :: rest)) (hp : p ≤ m0)
    (hm : m0 ≤ lastP p rest) (hgp : p ≤ g) (hgl : g ≤ lastP p rest) (hne : m0 ≠ g) :
    Track.eval (rebase ((p, a) :: rest) m0 g) 1 = Track.eval ((p, a) :: rest) g := by
  rw [rebase_eval p a rest m0 g 1 h hp hm hgp hgl hne (by decide) (by decide)]
  congr 1; grind

theorem rebase_start (p a : Rat) (rest : Track) (m0 g : Rat) (h : Asc ((p, a) :: rest)) (hp : p ≤ m0)
    (hm : m0 ≤ lastP p rest) (hgp : p ≤ g) (hgl : g ≤ lastP p rest) (hne : m0 ≠ g) :
    Track.eval (rebase ((p, a) :: rest) m0 g) 0 = Track.eval ((p, a) :: rest) m0 := by
  rw [rebase_eval p a rest m0 g 0 h hp hm hgp hgl hne (by decide) (by decide)]
  congr 1; grind

theorem solver_gap (m0 g s x ε : Rat) (hm0 : 0 ≤ m0) (hm1 : m0 ≤ 1) (hg0 : 0 ≤ g) (hg1 : g ≤ 1) (hs0 : 0 ≤ s)
    (hs1 : s ≤ 1) (hx0 : 0 ≤ x) (hx1 : x ≤ 1) (hlo : -ε < curveX s - x) (hhi : curveX s - x < ε) :
    (m0 + (g - m0) * curveY s) - (m0 + (g - m0) * ease x) ≤ 3 * ε ∧
    (m0 + (g - m0) * ease x) - (m0 + (g - m0) * curveY s) ≤ 3 * ε := by
  have hsx := solver_exact s x ε hs0 hs1 hx0 hx1 hlo hhi
  have hm := mul_bd (g - m0) (curveY s - ease x) (3 * ε) (by grind) (by grind) (by grind)
  constructor <;> grind


def firstFrom (P : Nat → Bool) : Nat → Nat → Option Nat
  | _, 0 => none
  | n, k + 1 => if P n then some n else firstFrom P (n + 1) k

theorem firstFrom_spec (P : Nat → Bool) : ∀ (k n r : Nat), firstFrom P n k = some r →
    P r = true ∧ n ≤ r ∧ ∀ j, n ≤ j → j < r → P j = false
  | 0, n, r, h => by simp [firstFrom] at h
  | k + 1, n, r, h => by
    unfold firstFrom at h
    by_cases hp : P n = true
    · simp only [hp, ite_true, Option.some.injEq] at h
      subst h
      exact ⟨hp, Nat.le_refl _, fun j h1 h2 => by omega⟩
    · simp only [hp] at h
      have ⟨a, b, c⟩ := firstFrom_spec P k (n + 1) r h
      refine ⟨a, by omega, fun j h1 h2 => ?_⟩
      by_cases hj : j = n
      · subst hj; simpa using hp
      · exact c j (by omega) h2

def crossedAt (m0 g c : Rat) (n : Nat) : Bool :=
  let v := m0 + (g - m0) * ease ((n : Rat) / duration)
  if m0 ≤ g then decide (c ≤ v) else decide (v ≤ c)

def crossMs (m0 g c : Rat) : Option Nat := firstFrom (crossedAt m0 g c) 0 681

theorem crossMs_some (m0 g c : Rat) (h : (m0 ≤ c ∧ c ≤ g) ∨ (g ≤ c ∧ c ≤ m0)) : (crossMs m0 g c).isSome = true := by
  have e : ease ((680 : Nat) / duration) = 1 := by unfold ease clamp01 duration; decide +kernel
  have hP : crossedAt m0 g c 680 = true := by
    unfold crossedAt
    simp only [e]
    by_cases hmg : m0 ≤ g
    · simp only [hmg, ite_true]; simp only [decide_eq_true_eq]; grind
    · simp only [hmg, ite_false]; simp only [decide_eq_true_eq]; grind
  unfold crossMs
  suffices ∀ k n, n + k = 681 → n ≤ 680 → (firstFrom (crossedAt m0 g c) n k).isSome = true from this 681 0 (by omega) (by omega)
  intro k
  induction k with
  | zero => intro n h1 h2; omega
  | succ k ih =>
    intro n h1 h2
    unfold firstFrom
    by_cases hn : crossedAt m0 g c n = true
    · simp [hn]
    · simp only [hn]
      by_cases hn680 : n = 680
      · subst hn680; exact absurd hP hn
      · exact ih (n + 1) (by omega) (by omega)



theorem asc_mk (f : Rat → Rat) : ∀ ps : List Rat, sortedB ps = true → Asc (mk f ps)
  | [], _ => trivial
  | [_], _ => trivial
  | p :: q :: rest, h => by
    simp only [sortedB, Bool.and_eq_true, decide_eq_true_eq] at h
    exact ⟨h.1, asc_mk f (q :: rest) (by simpa [sortedB] using h.2)⟩

theorem lastP_mk (f : Rat → Rat) : ∀ (ps : List Rat) (p : Rat), lastP p (mk f ps) = lastL (p :: ps)
  | [], p => by simp [mk, lastP, lastL]
  | q :: r, p => by
    have ih := lastP_mk f r q
    simp only [mk, List.map_cons] at ih ⊢
    simp only [lastP]
    rw [ih]
    cases r <;> simp [lastL]

theorem commit_eq (v : Fw.Parts.Nav.Vp) (hv : v ∈ bandVps) (k : Ks) (hk : k ≠ .time) (f : Rat → Rat) (m0 : Rat)
    (h0 : 0 ≤ m0) (h1 : m0 ≤ 1) :
    (m0 ≠ 1 → Track.eval (rebase (mk f (k.list v)) m0 1) 1 = f k.last) ∧
    (m0 ≠ 0 → Track.eval (rebase (mk f (k.list v)) m0 0) 1 = f 0) := by
  have h := List.all_eq_true.mp (List.all_eq_true.mp ends_bands v hv) k (by cases k <;> simp [allKs])
  have hl1 : k.last = 1 := by unfold Ks.last; simp [hk]
  unfold endsOk at h
  generalize k.list v = ks at h ⊢
  cases ks with
  | nil => simp at h
  | cons p ps =>
    simp only [Bool.and_eq_true, beq_iff_eq, List.head?_cons, Option.some.injEq] at h
    obtain ⟨⟨hs, rfl⟩, hl⟩ := h
    have hA := asc_mk f _ hs
    have hLp : lastP 0 (mk f ps) = 1 := by rw [lastP_mk]; grind
    have e0 := eval_start f 0 ps hs
    have e1 := eval_end f ps 0 hs
    simp only [mk, List.map_cons] at hA hLp e0 e1 ⊢
    refine ⟨fun hne => ?_, fun hne => ?_⟩
    · rw [rebase_end 0 (f 0) _ m0 1 hA h0 (by grind) (by grind) (by grind) hne]
      rw [hl, hl1] at e1
      rw [hl1]; simpa [mk] using e1
    · rw [rebase_end 0 (f 0) _ m0 0 hA h0 (by grind) (by grind) (by grind) hne]
      simpa [mk] using e0

/-! ### Take rule with retry (probe note A5)

A push is taken onto the timed tracks at the first frame where the nav reads on-dark, or at once when a timed set
is already entered. Frame 0 is the push itself; frame k is the k-th tick of the faithful tween. The direction
plays no part, so a close takes like an open. -/

/-- The take decision at one frame. `anims`: a timed set is already entered; `dark`: the nav reads on-dark. -/
def takeOk (_f _t : Rat) (anims dark : Bool) : Bool := anims || dark

theorem takeOk_up (f t : Rat) (_h : f < t) (anims dark : Bool) : takeOk f t anims dark = (anims || dark) := rfl

theorem takeOk_down (f t : Rat) (_h : t < f) (anims dark : Bool) : takeOk f t anims dark = (anims || dark) := rfl

/-- The retry machine: `none` while pending on the faithful tween, `some j` once taken at frame `j`. -/
def stepTake (s : Option Nat) (k : Nat) (d : Bool) : Option Nat :=
  match s with
  | some j => some j
  | none => if d then some k else none

/-- Run the machine over `n` frames from frame `k`. -/
def scanTake (P : Nat → Bool) : Nat → Nat → Option Nat → Option Nat
  | _, 0, s => s
  | k, n + 1, s => scanTake P (k + 1) n (stepTake s k (P k))

/-- Once taken, a frame never changes the answer: no fallback to the faithful tween. -/
theorem stepTake_taken (j k : Nat) (d : Bool) : stepTake (some j) k d = some j := rfl

theorem scanTake_taken (P : Nat → Bool) : ∀ (n k j : Nat), scanTake P k n (some j) = some j
  | 0, _, _ => rfl
  | n + 1, k, j => by simp only [scanTake, stepTake_taken]; exact scanTake_taken P n (k + 1) j

/-- The machine takes at the first frame the decision holds. -/
theorem scanTake_none_eq (P : Nat → Bool) : ∀ (n k : Nat), scanTake P k n none = firstFrom P k n
  | 0, k => rfl
  | n + 1, k => by
    by_cases h : P k = true
    · simp [scanTake, stepTake, firstFrom, h, scanTake_taken]
    · simp [scanTake, stepTake, firstFrom, h]
      exact scanTake_none_eq P n (k + 1)

/-- Taken frame of one push: the decision at each of its `n` frames is `takeOk` on the dark reading. -/
def takeFrame (f t : Rat) (anims : Bool) (dark : Nat → Bool) (n : Nat) : Option Nat :=
  scanTake (fun k => takeOk f t anims (dark k)) 0 n none

/-- Branch: the nav reads dark at frame `r` and at no earlier frame, no timed set entered: taken at `r`. -/
theorem take_at_first_dark (f t : Rat) (dark : Nat → Bool) (n r : Nat) (hr : r < n) (hd : dark r = true)
    (hb : ∀ j, j < r → dark j = false) : takeFrame f t false dark n = some r := by
  unfold takeFrame
  rw [scanTake_none_eq]
  have key : ∀ (k m : Nat), k ≤ r → r < k + m → firstFrom (fun k => takeOk f t false (dark k)) k m = some r := by
    intro k m
    induction m generalizing k with
    | zero => intro _ h; omega
    | succ m ih =>
      intro h1 h2
      by_cases hk : k = r
      · subst hk; simp [firstFrom, takeOk, hd]
      · have : dark k = false := hb k (by omega)
        simp [firstFrom, takeOk, this]
        exact ih (k + 1) (by omega) (by omega)
  exact key 0 n (by omega) (by omega)

/-- Branch: a timed set is already entered (a reversal after a take): taken at frame 0, dark or not. -/
theorem take_entered (f t : Rat) (dark : Nat → Bool) (n : Nat) : takeFrame f t true dark (n + 1) = some 0 := by
  simp [takeFrame, scanTake, stepTake, takeOk, scanTake_taken]

/-- Branch: the nav never reads dark and nothing is entered: the push stays faithful. -/
theorem take_never (f t : Rat) (dark : Nat → Bool) (hn : ∀ j, dark j = false) :
    ∀ n, takeFrame f t false dark n = none := by
  have g : ∀ (P : Nat → Bool), (∀ j, P j = false) → ∀ (n k : Nat), scanTake P k n none = none := by
    intro P hP n
    induction n with
    | zero => intro k; rfl
    | succ n ih => intro k; simp only [scanTake, stepTake, hP]; exact ih (k + 1)
  intro n
  exact g _ (fun j => by simp [takeOk, hn]) n 0

/-- A longer window keeps the taken frame: once taken, the answer stays. -/
theorem firstFrom_stable (P : Nat → Bool) : ∀ (k n r m : Nat), firstFrom P n k = some r → firstFrom P n (k + m) = some r
  | 0, n, r, m, h => by simp [firstFrom] at h
  | k + 1, n, r, m, h => by
    by_cases hp : P n = true
    · have e : k + 1 + m = (k + m) + 1 := by omega
      rw [e]; simp only [firstFrom, hp, ite_true] at h ⊢; exact h
    · have e : k + 1 + m = (k + m) + 1 := by omega
      rw [e]; simp only [firstFrom, hp] at h ⊢
      exact firstFrom_stable P k (n + 1) r m h

/-- Continuity across the switch. The faithful frame at time `t` shows `(frame s t).value`; the timed set taken
at any later frame, started at the push's own start time, shows the same value there. The jump is exactly 0. -/
theorem switch_jump_zero (p a : Rat) (rest : Track) (s : St) (t : Rat) (h : Asc ((p, a) :: rest))
    (hp : p ≤ s.f) (hf : s.f ≤ lastP p rest) (hgp : p ≤ s.t) (hgl : s.t ≤ lastP p rest) (hne : s.f ≠ s.t)
    (ht0 : s.start ≤ t) (ht1 : t ≤ s.start + 680) :
    shown ((p, a) :: rest) s t = Track.eval ((p, a) :: rest) (frame s t).value := by
  rw [timed_eq_ideal_set p a rest s t h hp hf hgp hgl hne ht0 ht1]
  rfl


end Fw.Parts.MorphGeomTimed

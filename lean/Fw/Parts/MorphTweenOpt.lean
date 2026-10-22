import Fw.Parts.MorphTween
import Fw.Engine
import Fw.Site.Breakpoints
import Fw.Parts.EndFlags
import Fw.Parts.Nav
import Fw.Parts.MorphPanel
import Fw.Parts.NavHitTest
import Fw.Parts.MorphListen

namespace Fw.Parts.MorphTweenOpt

open Fw.Parts.MorphTween

def bez (a b s : Rat) : Rat := 3 * a * s * (1 - s) * (1 - s) + 3 * b * s * s * (1 - s) + s * s * s

structure Coeffs where
  c : Rat
  b : Rat
  a : Rat
  deriving DecidableEq, Repr

/-- The engines' coefficients of one axis from its inner control coordinates
(`cubic_bezier.cc:50-56`@f842f52, `UnitBezier.h:45-51`@862f17d).

How Chromium and WebKit set up a curve axis. -/
def coeffs (p1 p2 : Rat) : Coeffs :=
  let c := 3 * p1
  let b := 3 * (p2 - p1) - c
  ⟨c, b, 1 - c - b⟩

/-- The engines' evaluation of one axis (Horner's rule; `cubic_bezier.h:23-37`@f842f52, `UnitBezier.h:94-108`@862f17d).

How the engines sample a curve axis. -/
def horner (k : Coeffs) (t : Rat) : Rat := ((k.a * t + k.b) * t + k.c) * t

theorem horner_eq_bez (p1 p2 t : Rat) : horner (coeffs p1 p2) t = bez p1 p2 t := by
  simp only [horner, coeffs, bez]
  grind

def p1x : Rat := 1 / 3
def p1y : Rat := 1
def p2x : Rat := 2 / 3
def p2y : Rat := 1

def curveX (s : Rat) : Rat := bez p1x p2x s

def curveY (s : Rat) : Rat := bez p1y p2y s

#guard curveX (1 / 2) == 1 / 2
#guard curveY (1 / 2) == 7 / 8
#guard curveY (1 / 2) == ease (1 / 2)
#guard coeffs p1x p2x == ⟨1, 0, 0⟩
#guard coeffs p1y p2y == ⟨3, -3, 1⟩

theorem coeffs_x : coeffs p1x p2x = ⟨1, 0, 0⟩ := by
  simp only [coeffs, p1x, p2x, Coeffs.mk.injEq]
  exact ⟨by grind, by grind, by grind⟩

theorem coeffs_y : coeffs p1y p2y = ⟨3, -3, 1⟩ := by
  simp only [coeffs, p1y, p2y, Coeffs.mk.injEq]
  exact ⟨by grind, by grind, by grind⟩

theorem bezier_eq_ease (s : Rat) :
    curveX s = s ∧ curveY s = 1 - (1 - s) * (1 - s) * (1 - s) := by
  simp only [curveX, curveY, bez, p1x, p2x, p1y, p2y]
  constructor <;> grind

theorem curveY_eq_ease (s : Rat) (h0 : 0 ≤ s) (h1 : s ≤ 1) : curveY s = ease s := by
  have hc : clamp01 s = s := by unfold clamp01; grind
  rw [(bezier_eq_ease s).2]
  unfold ease
  rw [hc]

theorem solver_exact_zero (t x : Rat) (h : curveX t = x) (hx0 : 0 ≤ x) (hx1 : x ≤ 1) :
    curveY t = ease x := by
  have ht : t = x := by rw [← (bezier_eq_ease t).1]; exact h
  subst ht
  exact curveY_eq_ease t hx0 hx1

theorem curveY_sub (t x : Rat) :
    curveY t - curveY x = (t - x) * ((1 - t) * (1 - t) + (1 - t) * (1 - x) + (1 - x) * (1 - x)) := by
  rw [(bezier_eq_ease t).2, (bezier_eq_ease x).2]
  grind

theorem slope_mem (u v : Rat) (hu0 : 0 ≤ u) (hu1 : u ≤ 1) (hv0 : 0 ≤ v) (hv1 : v ≤ 1) :
    0 ≤ u * u + u * v + v * v ∧ u * u + u * v + v * v ≤ 3 := by
  have huu : u * u ≤ u * 1 := Rat.mul_le_mul_of_nonneg_left hu1 hu0
  have huv : u * v ≤ u * 1 := Rat.mul_le_mul_of_nonneg_left hv1 hu0
  have hvv : v * v ≤ v * 1 := Rat.mul_le_mul_of_nonneg_left hv1 hv0
  have h1 : 0 ≤ u * u := Rat.mul_nonneg hu0 hu0
  have h2 : 0 ≤ u * v := Rat.mul_nonneg hu0 hv0
  have h3 : 0 ≤ v * v := Rat.mul_nonneg hv0 hv0
  grind

theorem solver_exact (t x ε : Rat) (ht0 : 0 ≤ t) (ht1 : t ≤ 1) (hx0 : 0 ≤ x) (hx1 : x ≤ 1)
    (hlo : -ε < curveX t - x) (hhi : curveX t - x < ε) :
    -(3 * ε) ≤ curveY t - ease x ∧ curveY t - ease x ≤ 3 * ε := by
  rw [(bezier_eq_ease t).1] at hlo hhi
  rw [← curveY_eq_ease x hx0 hx1, curveY_sub]
  have hw := slope_mem (1 - t) (1 - x) (by grind) (by grind) (by grind) (by grind)
  generalize (1 - t) * (1 - t) + (1 - t) * (1 - x) + (1 - x) * (1 - x) = w at *
  generalize t - x = d at *
  by_cases hd : 0 ≤ d
  · have h1 : d * w ≤ d * 3 := Rat.mul_le_mul_of_nonneg_left hw.2 hd
    have h2 : 0 ≤ d * w := Rat.mul_nonneg hd hw.1
    grind
  · have hd' : 0 ≤ -d := by grind
    have h1 : -d * w ≤ -d * 3 := Rat.mul_le_mul_of_nonneg_left hw.2 hd'
    have h2 : 0 ≤ -d * w := Rat.mul_nonneg hd' hw.1
    grind

open Fw.Engine

/-- WebKit's interpolation of two numbers (R3, `AnimationUtilities.h:98-108`@862f17d).

The start plus the eased share of the distance. -/
def interpWk (a b p : Rat) : Rat := a + (b - a) * p

/-- Blink's interpolation of two numbers (R3, `interpolable_value.cc:105-115`@f842f52).

The weighted mean of the two ends. -/
def interpBlink (a b p : Rat) : Rat := (1 - p) * a + p * b

theorem interpBlink_eq_wk (a b p : Rat) : interpBlink a b p = interpWk a b p := by
  unfold interpBlink interpWk; grind

def interpDiscrete (a b p : Rat) : Rat := if p < 1 / 2 then a else b

#guard interpDiscrete 0 1 (1 / 4) == 0 && interpWk 0 1 (1 / 4) == 1 / 4 && interpBlink 0 1 (1 / 4) == 1 / 4

theorem discrete_not_linear : interpDiscrete 0 1 (1 / 4) ≠ interpWk 0 1 (1 / 4) := by
  unfold interpDiscrete interpWk; grind

structure WaapiPremises where
  c : Rat
  interp : Rat → Rat → Rat → Rat
  interp_lin : ∀ a b p, interp a b p = a + (b - a) * p
  timing : Rat → Rat
  timing_eq : ∀ x, 0 ≤ x → x ≤ 1 → timing x = curveY x
  tl : Rat → Rat
  tl_eq : ∀ R, tl R = R + c
  startRead : Rat → Rat
  start_eq : ∀ n, startRead n = n + c

def premisesWk (c : Rat) : WaapiPremises :=
  ⟨c, interpWk, fun _ _ _ => rfl, curveY, fun _ _ _ => rfl, (· + c), fun _ => rfl, (· + c), fun _ => rfl⟩

def premisesBlink (c : Rat) : WaapiPremises :=
  ⟨c, interpBlink, interpBlink_eq_wk, curveY, fun _ _ _ => rfl, (· + c), fun _ => rfl, (· + c), fun _ => rfl⟩

structure Anim where
  f : Rat
  t : Rat
  st : Rat
deriving Repr, DecidableEq

def progress (st T : Rat) : Rat := clamp01 ((T - st) / duration)

def valA (P : WaapiPremises) (a : Anim) (T : Rat) : Rat := P.interp a.f a.t (P.timing (progress a.st T))

theorem clamp01_idem (x : Rat) : clamp01 (clamp01 x) = clamp01 x := by unfold clamp01; grind

theorem ease_clamp (x : Rat) : ease (clamp01 x) = ease x := by unfold ease; rw [clamp01_idem]

theorem tween_value_eq (f t e : Rat) : (tween f t e).value = f + (t - f) * ease (e / duration) := by
  unfold tween
  have hm := clamp01_mem (e / duration)
  dsimp only
  split
  · have h1 : clamp01 (e / duration) = 1 := by grind
    rw [← ease_clamp, h1]; unfold ease clamp01; grind
  · simp only [ease_clamp]

theorem timing_progress (P : WaapiPremises) (n R : Rat) :
    P.timing (progress (P.startRead n) (P.tl R)) = ease ((R - n) / duration) := by
  unfold progress
  rw [P.tl_eq, P.start_eq]
  have he : R + P.c - (n + P.c) = R - n := by grind
  rw [he]
  have hm := clamp01_mem ((R - n) / duration)
  rw [P.timing_eq _ hm.1 hm.2, curveY_eq_ease _ hm.1 hm.2, ease_clamp]

theorem valA_eq (P : WaapiPremises) (f t n R : Rat) :
    valA P ⟨f, t, P.startRead n⟩ (P.tl R) = (tween f t (R - n)).value := by
  unfold valA
  rw [timing_progress, P.interp_lin, tween_value_eq]

inductive Ev where
  | push (g : Rat) (rm : Bool) (n : Rat)
  | tick (R : Rat)
deriving Repr, DecidableEq

def stepO (s : St) : Ev → St
  | .push g rm n => push s g rm n
  | .tick R => if s.pending then frame s R else s

def runO (s : St) (es : List Ev) : St := es.foldl stepO s

structure VSt where
  target : Rat
  aim : Rat
  anim : Option Anim
  base : Rat
  cur : Rat
deriving Repr, DecidableEq

def initV : VSt := ⟨0, 0, none, 0, 0⟩

def valV (P : WaapiPremises) (w : VSt) (T : Rat) : Rat :=
  match w.anim with
  | none => w.base
  | some a => valA P a T

def stepV (P : WaapiPremises) (w : VSt) : Ev → VSt
  | .push g rm n =>
    if w.target = g ∧ w.aim = g then w
    else if rm then { w with target := g, aim := g, anim := none, base := g, cur := g }
    else { w with target := g, aim := g, anim := some ⟨w.cur, g, P.startRead n⟩ }
  | .tick R => { w with cur := valV P w (P.tl R) }

def runV (P : WaapiPremises) (w : VSt) (es : List Ev) : VSt := es.foldl (stepV P) w

def monoB : Rat → List Ev → Bool
  | _, [] => true
  | l, .push _ _ _ :: es => monoB l es
  | l, .tick R :: es => decide (l ≤ R) && monoB R es

def Inv (P : WaapiPremises) (l : Rat) (s : St) (w : VSt) : Prop :=
  w.target = s.target ∧ w.aim = s.t ∧ w.cur = s.value ∧
    (s.pending = true → w.anim = some ⟨s.f, s.t, P.startRead s.start⟩) ∧
    (s.pending = false → (w.anim = none ∧ w.base = s.value) ∨
      ∃ f, w.anim = some ⟨f, s.t, P.startRead s.start⟩ ∧ s.value = s.t ∧ s.start + duration ≤ l)

theorem inv_init (P : WaapiPremises) (l : Rat) : Inv P l rest initV := by
  unfold Inv rest initV; simp

theorem inv_push (P : WaapiPremises) (l : Rat) (s : St) (w : VSt) (g : Rat) (rm : Bool) (n : Rat)
    (h : Inv P l s w) : Inv P l (stepO s (.push g rm n)) (stepV P w (.push g rm n)) := by
  obtain ⟨ht, ha, hc, hp, hn⟩ := h
  simp only [stepO, stepV, push]
  by_cases hg : s.target = g ∧ s.t = g
  · have hw : w.target = g ∧ w.aim = g := by rw [ht, ha]; exact hg
    simp only [hg, hw, and_self, ite_true]
    exact ⟨ht, ha, hc, hp, hn⟩
  · have hw : ¬ (w.target = g ∧ w.aim = g) := by rw [ht, ha]; exact hg
    simp only [hg, hw, ite_false]
    cases rm
    · simp only [Bool.false_eq_true, ite_false]
      refine ⟨rfl, rfl, hc, fun _ => by rw [hc], fun h => by simp at h⟩
    · simp only [ite_true]
      refine ⟨rfl, rfl, rfl, fun h => by simp at h, fun _ => Or.inl ⟨rfl, rfl⟩⟩

theorem inv_tick (P : WaapiPremises) (l R : Rat) (s : St) (w : VSt) (h : Inv P l s w) (hl : l ≤ R) :
    Inv P R (stepO s (.tick R)) (stepV P w (.tick R)) := by
  obtain ⟨ht, ha, hc, hp, hn⟩ := h
  cases hs : s.pending
  · simp only [stepO, stepV, hs, Bool.false_eq_true, ite_false]
    rcases hn hs with ⟨hnone, hb⟩ | ⟨f, hsome, hv, hd⟩
    · refine ⟨ht, ha, ?_, fun h => by simp [hs] at h, fun _ => Or.inl ⟨hnone, hb⟩⟩
      simp only [valV, hnone]; exact hb
    · refine ⟨ht, ha, ?_, fun h => by simp [hs] at h, fun _ => Or.inr ⟨f, hsome, hv, by grind⟩⟩
      simp only [valV, hsome]
      rw [valA_eq, tween_end _ _ _ (by unfold duration at hd; grind), hv]
  · have ha' := hp hs
    simp only [stepO, stepV, hs, ite_true, frame]
    refine ⟨ht, ha, ?_, ?_, ?_⟩
    · simp only [valV, ha']; exact valA_eq P _ _ _ _
    · intro _; exact ha'
    · intro hd
      have hdone : (tween s.f s.t (R - s.start)).done = true := by
        cases hz : (tween s.f s.t (R - s.start)).done
        · simp [hz] at hd
        · rfl
      have h680 := (tween_done_iff _ _ _).1 hdone
      refine Or.inr ⟨s.f, ha', tween_end _ _ _ h680, ?_⟩
      unfold duration; grind

theorem inv_run (P : WaapiPremises) :
    ∀ (es : List Ev) (l : Rat) (s : St) (w : VSt) (es' : List Ev), Inv P l s w → monoB l (es ++ es') = true →
      ∃ l', Inv P l' (runO s es) (runV P w es) ∧ monoB l' es' = true
  | [], l, _, _, _, h, hm => ⟨l, h, hm⟩
  | .push g rm n :: es, l, s, w, es', h, hm => by
    simp only [List.cons_append, monoB] at hm
    exact inv_run P es l _ _ es' (inv_push P l s w g rm n h) hm
  | .tick R :: es, l, s, w, es', h, hm => by
    simp only [List.cons_append, monoB, Bool.and_eq_true, decide_eq_true_eq] at hm
    exact inv_run P es R _ _ es' (inv_tick P l R s w h hm.1) hm.2

theorem waapi_eq_tween (P : WaapiPremises) (es : List Ev) (l : Rat) (hm : monoB l es = true) :
    (runV P initV es).cur = (runO rest es).value := by
  obtain ⟨_, h, _⟩ := inv_run P es l rest initV [] (inv_init P l) (by simpa using hm)
  exact h.2.2.1

theorem waapi_frame_eq (P : WaapiPremises) (es : List Ev) (R l : Rat) (hm : monoB l (es ++ [.tick R]) = true) :
    valV P (runV P initV es) (P.tl R) = (runO rest (es ++ [.tick R])).value := by
  have := waapi_eq_tween P (es ++ [.tick R]) l hm
  simpa [runV, List.foldl_append, stepV] using this

#guard (runV (premisesWk 0) initV [.push 1 false 100, .tick 440]).cur == (runO rest [.push 1 false 100, .tick 440]).value
#guard (runV (premisesWk 7) initV [.push 1 false 100, .tick 300, .push 0 false 350, .tick 500]).cur ==
  (runO rest [.push 1 false 100, .tick 300, .push 0 false 350, .tick 500]).value
#guard (runV (premisesBlink 3) initV [.push 1 false 0, .tick 700, .tick 900, .push 0 true 950, .tick 960]).cur == 0

def flipAt (c : Rat) (a b : Bool) (p : Rat) : Bool := if p < c then a else b

def kfOffset (θ f t : Rat) : Rat := (θ - f) / (t - f)

def flagV (θ f t p : Rat) : Bool := flipAt (clamp01 (kfOffset θ f t)) (decide (f > θ)) (decide (t > θ)) p

def flagO (θ f t p : Rat) : Bool := decide (f + (t - f) * p > θ)

theorem up_iff (θ f t x : Rat) (hd : f < t) : f + (t - f) * x > θ ↔ kfOffset θ f t < x := by
  unfold kfOffset
  rw [Rat.div_lt_iff (by grind)]
  grind

theorem down_iff (θ f t x : Rat) (hd : t < f) : f + (t - f) * x > θ ↔ x < kfOffset θ f t := by
  unfold kfOffset
  have : (θ - f) / (t - f) = (f - θ) / (f - t) := by grind
  rw [this, Rat.lt_div_iff (by grind)]
  grind

theorem kfOffset_flat (θ f : Rat) : kfOffset θ f f = 0 := by unfold kfOffset; grind

theorem kfOffset_mem (θ f t : Rat) (hf : f ≤ θ) (ht : θ < t) :
    0 ≤ kfOffset θ f t ∧ kfOffset θ f t < 1 ∧ clamp01 (kfOffset θ f t) = kfOffset θ f t := by
  have h0 := up_iff θ f t 0 (by grind)
  have h1 := up_iff θ f t 1 (by grind)
  have : ¬ kfOffset θ f t < 0 := by grind
  refine ⟨by grind, by grind, ?_⟩
  unfold clamp01; grind

theorem flag_below_tie (θ f t p : Rat) (hf : f ≤ θ) (ht : θ < t) (hp : p < kfOffset θ f t) :
    flagV θ f t p = false ∧ flagO θ f t p = false := by
  have hk := kfOffset_mem θ f t hf ht
  have hu := up_iff θ f t p (by grind)
  unfold flagV flipAt flagO
  rw [hk.2.2]
  refine ⟨by simp [hp]; grind, by simp; grind⟩

theorem flag_tie (θ f t p : Rat) (hf : f ≤ θ) (ht : θ < t) (hp : p = kfOffset θ f t) :
    flagV θ f t p = true ∧ flagO θ f t p = false := by
  have hk := kfOffset_mem θ f t hf ht
  have hu := up_iff θ f t p (by grind)
  unfold flagV flipAt flagO
  rw [hk.2.2]
  refine ⟨by simp; grind, by simp; grind⟩

theorem flag_above_tie (θ f t p : Rat) (hf : f ≤ θ) (ht : θ < t) (hp : kfOffset θ f t < p) :
    flagV θ f t p = true ∧ flagO θ f t p = true := by
  have hk := kfOffset_mem θ f t hf ht
  have hu := up_iff θ f t p (by grind)
  unfold flagV flipAt flagO
  rw [hk.2.2]
  refine ⟨by simp; grind, by simp; grind⟩

theorem flags_same_frame (θ f t p : Rat) (hp0 : 0 ≤ p) (hp1 : p ≤ 1)
    (hnt : ¬ (f ≤ θ ∧ θ < t ∧ p = kfOffset θ f t)) : flagV θ f t p = flagO θ f t p := by
  unfold flagV flipAt flagO
  rcases (show f < t ∨ f = t ∨ t < f by grind) with hd | hd | hd
  · have h0 := up_iff θ f t 0 hd
    have h1 := up_iff θ f t 1 hd
    have hp := up_iff θ f t p hd
    simp only [Rat.mul_zero, Rat.add_zero, Rat.mul_one] at h0 h1
    unfold clamp01
    by_cases hθf : θ < f
    · have hmx : max 0 (kfOffset θ f t) = 0 := by grind
      rw [hmx]; simp; grind
    · by_cases hθt : θ < t
      · have hmx : min 1 (max 0 (kfOffset θ f t)) = kfOffset θ f t := by grind
        rw [hmx]
        have hne : p ≠ kfOffset θ f t := fun h => hnt ⟨by grind, hθt, h⟩
        by_cases hpc : p < kfOffset θ f t
        · simp [hpc]; grind
        · simp [hpc]; grind
      · have hmx : min 1 (max 0 (kfOffset θ f t)) = 1 := by grind
        rw [hmx]
        by_cases hpc : p < 1
        · simp [hpc]; grind
        · simp [hpc]; grind
  · subst hd
    rw [kfOffset_flat]
    unfold clamp01
    simp; grind
  · have h0 := down_iff θ f t 0 hd
    have h1 := down_iff θ f t 1 hd
    have hp := down_iff θ f t p hd
    simp only [Rat.mul_zero, Rat.add_zero, Rat.mul_one] at h0 h1
    unfold clamp01
    by_cases hθf : θ < f
    · by_cases hθt : θ < t
      · have hmx : min 1 (max 0 (kfOffset θ f t)) = 1 := by grind
        rw [hmx]
        by_cases hpc : p < 1
        · simp [hpc]; grind
        · simp [hpc]; grind
      · have hmx : min 1 (max 0 (kfOffset θ f t)) = kfOffset θ f t := by grind
        rw [hmx]
        by_cases hpc : p < kfOffset θ f t
        · simp [hpc]; grind
        · simp [hpc]; grind
    · have hmx : min 1 (max 0 (kfOffset θ f t)) = 0 := by grind
      rw [hmx]; simp; grind

theorem flagV_one (θ f t : Rat) : flagV θ f t 1 = decide (t > θ) := by
  unfold flagV flipAt
  have := clamp01_mem (kfOffset θ f t)
  have h : ¬ (1 : Rat) < clamp01 (kfOffset θ f t) := by grind
  simp only [h, ite_false]

theorem ease_gt_iff (θ x : Rat) (h0 : 0 ≤ x) (h1 : x ≤ 1) :
    ease x > θ ↔ (1 - x) * (1 - x) * (1 - x) < 1 - θ := by
  have : clamp01 x = x := by unfold clamp01; grind
  unfold ease; rw [this]; grind

#guard flagV (1 / 5) 0 1 (1 / 5) == true && flagO (1 / 5) 0 1 (1 / 5) == false
#guard flagV (1 / 5) 0 1 (1 / 10) == flagO (1 / 5) 0 1 (1 / 10)
#guard flagV (1 / 5) 0 1 (3 / 10) == flagO (1 / 5) 0 1 (3 / 10)
#guard flagV (1 / 5) 1 0 (4 / 5) == flagO (1 / 5) 1 0 (4 / 5)
#guard flagV (23 / 25) (1 / 2) (1 / 2) (1 / 3) == flagO (23 / 25) (1 / 2) (1 / 2) (1 / 3)

def thresholds : List Rat := [1 / 5, 23 / 25, 209 / 400, activeCut]

theorem pointerNone_eq (m : Rat) : pointerNone m = decide (m > 209 / 400) := by
  have := pointerNone_iff m
  cases h : pointerNone m <;> simp_all

theorem fade_css (m : Rat) : fade m = 1 - min 1 (m / (55 / 100)) := by
  unfold fade fadeEnd
  have : (55 / 100 : Rat) = 11 / 20 := by grind
  rw [this]

def flagW (P : WaapiPremises) (w : VSt) (θ T : Rat) : Bool :=
  match w.anim with
  | none => decide (w.base > θ)
  | some a => flagV θ a.f a.t (P.timing (progress a.st T))

def tieB (s : St) (θ R : Rat) : Bool :=
  s.pending && decide (s.f ≤ θ) && decide (θ < s.t) && decide (ease ((R - s.start) / duration) = kfOffset θ s.f s.t)

theorem flags_same_run (P : WaapiPremises) (es : List Ev) (l R θ : Rat) (hm : monoB l (es ++ [.tick R]) = true)
    (ht : tieB (runO rest es) θ R = false) :
    flagW P (runV P initV es) θ (P.tl R) = decide ((runO rest (es ++ [.tick R])).value > θ) := by
  obtain ⟨l', hI, hm'⟩ := inv_run P es l rest initV [.tick R] (inv_init P l) hm
  simp only [monoB, Bool.and_true, decide_eq_true_eq] at hm'
  have hrun : runO rest (es ++ [.tick R]) = stepO (runO rest es) (.tick R) := by
    simp [runO, List.foldl_append]
  rw [hrun]
  generalize runO rest es = s at hI ht
  generalize runV P initV es = w at hI
  obtain ⟨_, _, _, hp, hn⟩ := hI
  cases hs : s.pending
  · simp only [stepO, hs, Bool.false_eq_true, ite_false]
    rcases hn hs with ⟨hnone, hb⟩ | ⟨f, hsome, hv, hd⟩
    · simp only [flagW, hnone, hb]
    · simp only [flagW, hsome]
      rw [timing_progress]
      have he : ease ((R - s.start) / duration) = 1 := by
        have h1 : 1 ≤ (R - s.start) / duration := by
          rw [div_dur]; unfold duration at hd; grind
        rw [← ease_clamp]
        have : clamp01 ((R - s.start) / duration) = 1 := by unfold clamp01; grind
        rw [this]; unfold ease clamp01; grind
      rw [he, flagV_one, hv]
  · have ha := hp hs
    simp only [stepO, hs, ite_true, frame, flagW, ha]
    rw [timing_progress, tween_value_eq]
    have hnt : ¬ (s.f ≤ θ ∧ θ < s.t ∧ ease ((R - s.start) / duration) = kfOffset θ s.f s.t) := by
      intro h
      simp [tieB, hs, h.1, h.2.1, h.2.2] at ht
    have hm := ease_mem ((R - s.start) / duration)
    exact flags_same_frame θ s.f s.t _ hm.1 hm.2 hnt

structure View where
  m : Rat
  target : Rat
  flags : List Bool
deriving Repr, DecidableEq

def viewO (es : List Ev) (R : Rat) : View :=
  let s := runO rest (es ++ [.tick R])
  ⟨s.value, s.target, thresholds.map fun θ => decide (s.value > θ)⟩

def viewV (P : WaapiPremises) (es : List Ev) (R : Rat) : View :=
  let w := runV P initV es
  ⟨valV P w (P.tl R), w.target, thresholds.map fun θ => flagW P w θ (P.tl R)⟩

def Hist : Type :=
  {x : List Ev × Rat × Rat // monoB x.2.2 (x.1 ++ [.tick x.2.1]) = true ∧
    thresholds.all (fun θ => !tieB (runO rest x.1) θ x.2.1) = true}

theorem view_eq (P : WaapiPremises) (h : Hist) : viewV P h.1.1 h.1.2.1 = viewO h.1.1 h.1.2.1 := by
  obtain ⟨⟨es, R, l⟩, hm, ht⟩ := h
  have hv := waapi_frame_eq P es R l hm
  obtain ⟨l', hI, _⟩ := inv_run P es l rest initV [.tick R] (inv_init P l) hm
  have htg : (runO rest (es ++ [.tick R])).target = (runV P initV es).target := by
    have hrun : runO rest (es ++ [.tick R]) = stepO (runO rest es) (.tick R) := by
      simp [runO, List.foldl_append]
    rw [hrun, hI.1]
    simp only [stepO]; split <;> rfl
  simp only [viewV, viewO, hv, htg, View.mk.injEq, true_and]
  apply List.map_congr_left
  intro θ hθ
  have hθ' : tieB (runO rest es) θ R = false := by simpa using List.all_eq_true.1 ht θ hθ
  exact flags_same_run P es l R θ hm hθ'

inductive Cmp where
  | gt
  | lt
deriving Repr, DecidableEq

structure AttrReader where
  sel : String
  cmp : Cmp
  θ : Rat
deriving Repr, DecidableEq

def AttrReader.test (r : AttrReader) (m : Rat) : Bool :=
  match r.cmp with
  | .gt => decide (r.θ < m)
  | .lt => decide (m < r.θ)

def attrReaders : List AttrReader :=
  [⟨"nav.is-morphing", .gt, 1 / 1000⟩, ⟨"nav.is-on-dark", .gt, 1 / 5⟩, ⟨"nav.earn.tabindex", .gt, 2 / 5⟩,
    ⟨"nav.earn.aria-hidden", .gt, 11 / 20⟩, ⟨"nav.is-expanded", .gt, 23 / 25⟩,
    ⟨"panel.data-start-selling-scene", .gt, 1 / 1000⟩, ⟨"panel.aria-hidden", .lt, 7 / 20⟩,
    ⟨"panel.cta.tabindex", .lt, 11 / 20⟩, ⟨"panel.data-expanded", .gt, 23 / 25⟩]

def band (m : Rat) : List Bool := attrReaders.map (·.test m)

structure AttrCtx where
  past : Bool
  ready : Bool
  localeOpen : Bool
  hit : Bool
  stuck : Bool
deriving Repr, DecidableEq

structure AttrScene where
  nav : Nav.View
  earn : Nav.Earn
  onDark : Bool
  panel : List Bool
deriving Repr, DecidableEq

def attrScene (c : AttrCtx) (m : Rat) : AttrScene :=
  let v := Nav.view c.past c.ready c.localeOpen c.hit c.stuck m
  ⟨v, Nav.earn v.heroPill m, NavHitTest.isOnDark c.hit m,
    [MorphPanel.sceneActive m, MorphPanel.ariaHidden m, MorphPanel.ctaTabOff m, MorphPanel.expanded m]⟩

def sceneOfBand (c : AttrCtx) (b : List Bool) : AttrScene :=
  let morphing := b.getD 0 false
  let v : Nav.View := ⟨!c.past && !morphing, c.ready, morphing, b.getD 4 false, c.hit || b.getD 1 false,
    c.localeOpen, c.stuck && !morphing⟩
  ⟨v, ⟨b.getD 2 false || v.heroPill, v.heroPill || b.getD 3 false⟩, c.hit || b.getD 1 false,
    [b.getD 5 false, b.getD 6 false, b.getD 7 false, b.getD 8 false]⟩

theorem attrScene_eq_band (c : AttrCtx) (m : Rat) : attrScene c m = sceneOfBand c (band m) := rfl

theorem attrScene_band (c : AttrCtx) (m m' : Rat) (h : band m = band m') : attrScene c m = attrScene c m' := by
  rw [attrScene_eq_band, attrScene_eq_band, h]

#guard attrScene ⟨true, true, false, false, false⟩ (1 / 2) == attrScene ⟨true, true, false, false, false⟩ (21 / 40)
#guard attrScene ⟨true, true, false, false, false⟩ (1 / 2) != attrScene ⟨true, true, false, false, false⟩ (3 / 5)
#guard band 0 == [false, false, false, false, false, false, true, true, false]
#guard band 1 == [true, true, true, true, true, true, false, false, true]

def pastS (f t θ m : Rat) : Prop := (f < t ∧ θ < m) ∨ (t < f ∧ m < θ)

instance (f t θ m : Rat) : Decidable (pastS f t θ m) :=
  inferInstanceAs (Decidable ((f < t ∧ θ < m) ∨ (t < f ∧ m < θ)))

def reach (f t θ m : Rat) : Prop := (f < t ∧ θ ≤ m) ∨ (t < f ∧ m ≤ θ)

instance (f t θ m : Rat) : Decidable (reach f t θ m) :=
  inferInstanceAs (Decidable ((f < t ∧ θ ≤ m) ∨ (t < f ∧ m ≤ θ)))

def ahd (f t u v : Rat) : Prop := (f < t → u ≤ v) ∧ (t < f → v ≤ u) ∧ (f = t → u = v)

def pathAt (f t x : Rat) : Rat := f + (t - f) * ease x

theorem ahd_refl (f t u : Rat) : ahd f t u u := by unfold ahd; grind

theorem ahd_trans (f t u v w : Rat) (h1 : ahd f t u v) (h2 : ahd f t v w) : ahd f t u w := by
  unfold ahd at *; grind

theorem ahd_antisymm (f t u v : Rat) (h1 : ahd f t u v) (h2 : ahd f t v u) : u = v := by
  unfold ahd at *; grind

theorem ahd_lin (f t a b : Rat) (h : a ≤ b) : ahd f t (f + (t - f) * a) (f + (t - f) * b) := by
  unfold ahd
  refine ⟨fun hft => ?_, fun hft => ?_, fun hft => by subst hft; grind⟩
  · have := Rat.mul_nonneg (show 0 ≤ t - f by grind) (show 0 ≤ b - a by grind); grind
  · have := Rat.mul_nonneg (show 0 ≤ f - t by grind) (show 0 ≤ b - a by grind); grind

theorem reach_mono (f t θ u v : Rat) (h : reach f t θ u) (hv : ahd f t u v) : reach f t θ v := by
  unfold reach ahd at *; grind

theorem pastS_mono (f t θ u v : Rat) (h : pastS f t θ u) (hv : ahd f t u v) : pastS f t θ v := by
  unfold pastS ahd at *; grind

theorem ease_nonpos (x : Rat) (h : x ≤ 0) : ease x = 0 := by
  have : clamp01 x = 0 := by unfold clamp01; grind
  unfold ease; rw [this]; grind

theorem pathAt_from (f t x : Rat) : ahd f t f (pathAt f t x) := by
  have h := ahd_lin f t 0 (ease x) (ease_mem x).1
  have e : f + (t - f) * 0 = f := by grind
  rw [e] at h; exact h

theorem pathAt_to (f t x : Rat) : ahd f t (pathAt f t x) t := by
  have h := ahd_lin f t (ease x) 1 (ease_mem x).2
  have e : f + (t - f) * 1 = t := by grind
  rw [e] at h; exact h

theorem pathAt_mono (f t x y : Rat) (h : x ≤ y) : ahd f t (pathAt f t x) (pathAt f t y) :=
  ahd_lin f t _ _ (ease_mono x y h)

theorem valA_path (P : WaapiPremises) (a : Anim) (T : Rat) :
    valA P a T = pathAt a.f a.t ((T - a.st) / duration) := by
  have hm := clamp01_mem ((T - a.st) / duration)
  unfold valA progress pathAt
  rw [P.interp_lin, P.timing_eq _ hm.1 hm.2, curveY_eq_ease _ hm.1 hm.2, ease_clamp]

theorem valA_mono (P : WaapiPremises) (a : Anim) (T T' : Rat) (h : T ≤ T') :
    ahd a.f a.t (valA P a T) (valA P a T') := by
  rw [valA_path, valA_path]
  apply pathAt_mono
  rw [div_dur, div_dur]; grind

theorem test_flip (f t u v : Rat) (r : AttrReader) (hv : ahd f t u v) (h : r.test u ≠ r.test v) :
    u ≠ v ∧ reach f t r.θ v ∧ ¬ pastS f t r.θ u := by
  refine ⟨fun he => h (by rw [he]), ?_⟩
  unfold AttrReader.test at h
  unfold reach pastS ahd at *
  cases r.cmp <;> simp only [ne_eq] at h <;> grind

theorem band_ne (u v : Rat) (h : band u ≠ band v) : ∃ r ∈ attrReaders, r.test u ≠ r.test v := by
  refine Classical.byContradiction fun hc => h ?_
  unfold band
  apply List.map_congr_left
  intro r hr
  exact Classical.byContradiction fun hne => hc ⟨r, hr, hne⟩

structure ASt where
  w : VSt
  attr : Rat
deriving Repr, DecidableEq

def initA : ASt := ⟨initV, 0⟩

/-- The variant's step: a push writes its start value, a frame writes its value iff `wr` says so. Premise, not proved:
a frame's marker finish events (update animations and send events: `B/core/page/page_animator.cc:292-311`@f842f52,
WebKit `animation/AnimationTimelinesController.cpp:217-232`@862f17d) and frame callbacks (`page_animator.cc:335`,
WebKit `page/Page.cpp:2330`) run before that frame's style and layout (WebKit `Page.cpp:2337`). -/
def stepAttr (P : WaapiPremises) (wr : VSt → Rat → Bool) (x : ASt) : Ev → ASt
  | .push g rm n =>
    ⟨stepV P x.w (.push g rm n), if x.w.target = g ∧ x.w.aim = g then x.attr else if rm then g else x.w.cur⟩
  | .tick R => ⟨stepV P x.w (.tick R), if wr x.w (P.tl R) then valV P x.w (P.tl R) else x.attr⟩

def runAttr (P : WaapiPremises) (wr : VSt → Rat → Bool) (x : ASt) (es : List Ev) : ASt := es.foldl (stepAttr P wr) x

theorem runAttr_w (P : WaapiPremises) (wr : VSt → Rat → Bool) :
    ∀ (es : List Ev) (x : ASt), (runAttr P wr x es).w = runV P x.w es
  | [], _ => rfl
  | e :: es, x => by
    have := runAttr_w P wr es (stepAttr P wr x e)
    simp only [runAttr, runV, List.foldl_cons] at *
    rw [this]; cases e <;> rfl

def finishW (w : VSt) (T : Rat) : Bool :=
  match w.anim with
  | none => false
  | some a => decide (a.st + duration ≤ T)

def oldW : VSt → Rat → Bool := finishW

def markerB (f t θ : Rat) : Bool := !decide (pastS f t θ f) && decide (reach f t θ t)

def pollW (dl : Rat → Rat → Rat → Rat) (w : VSt) (T : Rat) : Bool :=
  match w.anim with
  | none => false
  | some a => attrReaders.any fun r =>
    markerB a.f a.t r.θ && decide (a.st + dl a.f a.t r.θ ≤ T) && !decide (pastS a.f a.t r.θ w.cur)

def fixW (dl : Rat → Rat → Rat → Rat) (w : VSt) (T : Rat) : Bool := finishW w T || pollW dl w T

def WrOk (P : WaapiPremises) (wr : VSt → Rat → Bool) : Prop :=
  ∀ (w : VSt) (a : Anim) (T : Rat), w.anim = some a → ahd a.f a.t a.f w.cur → ahd a.f a.t w.cur (valA P a T) →
    band w.cur ≠ band (valA P a T) → wr w T = true

def DlSound (dl : Rat → Rat → Rat → Rat) : Prop :=
  ∀ f t θ e, 0 < e → reach f t θ (pathAt f t (e / duration)) → dl f t θ ≤ e

theorem fixW_ok (P : WaapiPremises) (dl : Rat → Rat → Rat → Rat) (hd : DlSound dl) : WrOk P (fixW dl) := by
  intro w a T ha hf hv hb
  obtain ⟨r, hr, hne⟩ := band_ne _ _ hb
  obtain ⟨huv, hreach, hnp⟩ := test_flip _ _ _ _ r hv hne
  have hval := valA_path P a T
  have he : 0 < T - a.st := by
    refine Classical.byContradiction fun hn => huv ?_
    have h0 : pathAt a.f a.t ((T - a.st) / duration) = a.f := by
      unfold pathAt; rw [ease_nonpos _ (by rw [div_dur]; grind)]; grind
    have hvf : valA P a T = a.f := hval.trans h0
    rw [hvf] at hv ⊢
    exact (ahd_antisymm _ _ _ _ hf hv).symm
  have hdl := hd a.f a.t r.θ (T - a.st) he (by rw [← hval]; exact hreach)
  have hto : reach a.f a.t r.θ a.t := reach_mono _ _ _ _ _ hreach (by rw [hval]; exact pathAt_to _ _ _)
  have hfr : ¬ pastS a.f a.t r.θ a.f := fun hp => hnp (pastS_mono _ _ _ _ _ hp hf)
  unfold fixW pollW
  rw [ha]
  simp only [Bool.or_eq_true, List.any_eq_true, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true,
    decide_eq_false_iff_not, decide_eq_true_eq, markerB]
  exact Or.inr ⟨r, hr, ⟨⟨by simpa using hfr, hto⟩, by grind⟩, hnp⟩

def AInv (P : WaapiPremises) (l : Rat) (x : ASt) : Prop :=
  band x.attr = band x.w.cur ∧ (x.w.anim = none → x.w.cur = x.w.base) ∧
    ∀ a, x.w.anim = some a → ahd a.f a.t a.f x.w.cur ∧ ∀ T, P.tl l ≤ T → ahd a.f a.t x.w.cur (valA P a T)

theorem ainv_init (P : WaapiPremises) (l : Rat) : AInv P l initA := by
  refine ⟨rfl, fun _ => rfl, fun a h => ?_⟩
  simp [initA, initV] at h

theorem ainv_push (P : WaapiPremises) (wr : VSt → Rat → Bool) (l g n : Rat) (rm : Bool) (x : ASt)
    (h : AInv P l x) : AInv P l (stepAttr P wr x (.push g rm n)) := by
  obtain ⟨hb, hn, hs⟩ := h
  by_cases hg : x.w.target = g ∧ x.w.aim = g
  · simp only [stepAttr, stepV, hg, and_self, ite_true]
    exact ⟨hb, hn, hs⟩
  · cases rm
    · simp only [stepAttr, stepV, hg, ite_false, Bool.false_eq_true]
      refine ⟨rfl, fun h => by simp at h, fun a ha => ?_⟩
      simp only [Option.some.injEq] at ha
      subst ha
      refine ⟨ahd_refl _ _ _, fun T _ => ?_⟩
      rw [valA_path]; exact pathAt_from _ _ _
    · simp only [stepAttr, stepV, hg, ite_false, ite_true]
      exact ⟨rfl, fun _ => rfl, fun a ha => by simp at ha⟩

theorem ainv_tick (P : WaapiPremises) (wr : VSt → Rat → Bool) (hw : WrOk P wr) (l R : Rat) (x : ASt)
    (h : AInv P l x) (hl : l ≤ R) : AInv P R (stepAttr P wr x (.tick R)) := by
  obtain ⟨hb, hn, hs⟩ := h
  have htl : P.tl l ≤ P.tl R := by rw [P.tl_eq, P.tl_eq]; grind
  cases ha : x.w.anim with
  | none =>
    have hv : valV P x.w (P.tl R) = x.w.cur := by simp only [valV, ha]; exact (hn ha).symm
    simp only [stepAttr, stepV, hv]
    refine ⟨?_, fun _ => hn ha, fun a h => by simp [ha] at h⟩
    split <;> simp only [hb]
  | some a =>
    obtain ⟨hf, hT⟩ := hs a ha
    have hv : valV P x.w (P.tl R) = valA P a (P.tl R) := by simp only [valV, ha]
    simp only [stepAttr, stepV, hv]
    refine ⟨?_, fun h => by simp [ha] at h, fun a' h' => ?_⟩
    · split
      · rfl
      · rename_i hnw
        refine hb.trans (Classical.byContradiction fun hne => hnw ?_)
        exact hw x.w a (P.tl R) ha hf (hT _ htl) hne
    · simp only [ha, Option.some.injEq] at h'
      subst h'
      exact ⟨ahd_trans _ _ _ _ _ hf (hT _ htl), fun T hT' => valA_mono P _ _ _ hT'⟩

theorem ainv_run (P : WaapiPremises) (wr : VSt → Rat → Bool) (hw : WrOk P wr) :
    ∀ (es : List Ev) (l : Rat) (x : ASt), AInv P l x → monoB l es = true → ∃ l', AInv P l' (runAttr P wr x es)
  | [], l, _, h, _ => ⟨l, h⟩
  | .push g rm n :: es, l, x, h, hm => by
    simp only [monoB] at hm
    exact ainv_run P wr hw es l _ (ainv_push P wr l g n rm x h) hm
  | .tick R :: es, l, x, h, hm => by
    simp only [monoB, Bool.and_eq_true, decide_eq_true_eq] at hm
    exact ainv_run P wr hw es R _ (ainv_tick P wr hw l R x h hm.1) hm.2

theorem attr_band (P : WaapiPremises) (dl : Rat → Rat → Rat → Rat) (hd : DlSound dl) (es : List Ev) (l : Rat)
    (hm : monoB l es = true) : band (runAttr P (fixW dl) initA es).attr = band (runO rest es).value := by
  obtain ⟨_, hb, _⟩ := ainv_run P (fixW dl) (fixW_ok P dl hd) es l initA (ainv_init P l) hm
  rw [hb, runAttr_w, ← waapi_eq_tween P es l hm]
  rfl

def bisect (f t θ : Rat) : Nat → Rat → Rat → Rat × Rat
  | 0, lo, hi => (lo, hi)
  | k + 1, lo, hi =>
    if reach f t θ (pathAt f t ((lo + hi) / 2)) then bisect f t θ k lo ((lo + hi) / 2)
    else bisect f t θ k ((lo + hi) / 2) hi

def dlLo (k : Nat) (f t θ : Rat) : Rat :=
  if reach f t θ f then 0 else duration * (bisect f t θ k 0 1).1

theorem bisect_lo (f t θ : Rat) :
    ∀ (k : Nat) (lo hi : Rat), ¬ reach f t θ (pathAt f t lo) → ¬ reach f t θ (pathAt f t (bisect f t θ k lo hi).1)
  | 0, _, _, h => h
  | k + 1, lo, hi, h => by
    unfold bisect
    split
    · exact bisect_lo f t θ k _ _ h
    · rename_i hm; exact bisect_lo f t θ k _ _ hm

theorem dlLo_sound (k : Nat) : DlSound (dlLo k) := by
  intro f t θ e he hr
  unfold dlLo
  split
  · grind
  · rename_i hf
    have h0 : pathAt f t 0 = f := by unfold pathAt; rw [ease_nonpos 0 (by grind)]; grind
    have hlo := bisect_lo f t θ k 0 1 (by rw [h0]; exact hf)
    refine Classical.byContradiction fun hlt => hlo ?_
    refine reach_mono _ _ _ _ _ hr (pathAt_mono _ _ _ _ ?_)
    rw [div_dur]; unfold duration at hlt; grind

#guard dlLo 20 0 1 (1 / 1000) < 1
#guard 386 < dlLo 20 0 1 (23 / 25) && dlLo 20 0 1 (23 / 25) < 387

theorem old_attr_stale :
    band (runAttr (premisesWk 0) oldW initA [.push 1 false 0, .tick 340]).attr ≠
      band (runO rest [.push 1 false 0, .tick 340]).value := by decide +kernel

#guard (runAttr (premisesWk 0) oldW initA [.push 1 false 0, .tick 340]).attr == 0
#guard (runO rest [.push 1 false 0, .tick 340]).value == 7 / 8
#guard (runAttr (premisesWk 0) (fixW (dlLo 20)) initA [.push 1 false 0, .tick 340]).attr == 7 / 8
#guard oldW ⟨1, 1, some ⟨0, 1, 0⟩, 0, 0⟩ 680 && !oldW ⟨1, 1, some ⟨0, 1, 0⟩, 0, 0⟩ 679
#guard pollW (dlLo 20) ⟨1, 1, some ⟨0, 1, 0⟩, 0, 0⟩ 1 && !pollW (dlLo 20) ⟨1, 1, some ⟨1, 1, 0⟩, 0, 1⟩ 1
#guard markerB 0 1 (1 / 5) && !markerB (1 / 2) 1 (1 / 5) && !markerB 1 1 (1 / 5) && markerB 1 0 (1 / 5)
#guard decide (pastS 0 1 (1 / 5) (1 / 4)) && !decide (pastS 0 1 (1 / 5) (1 / 5)) && decide (reach 0 1 (1 / 5) (1 / 5))
#guard (AttrReader.test ⟨"x", .lt, 7 / 20⟩ (1 / 3)) && !(AttrReader.test ⟨"x", .gt, 7 / 20⟩ (1 / 3))

def ratJ (q : Rat) : Lean.Json := Lean.Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

def Cmp.name : Cmp → String
  | .gt => "gt"
  | .lt => "lt"

def AttrReader.json (r : AttrReader) : String :=
  (Lean.Json.mkObj [("kind", .str "attrReader"), ("sel", .str r.sel), ("cmp", .str r.cmp.name),
    ("theta", ratJ r.θ)]).compress

def markerThetas : List Rat := (attrReaders.map (·.θ)).eraseDups

def delayDepth : Nat := 24

def markerJson (f t θ : Rat) : String :=
  (Lean.Json.mkObj [("kind", .str "marker"), ("from", ratJ f), ("to", ratJ t), ("theta", ratJ θ),
    ("marker", .bool (markerB f t θ)),
    ("delay", if markerB f t θ then ratJ (dlLo delayDepth f t θ) else .null)]).compress

def markerFroms : List Rat := [0, 1 / 10, 1 / 5, 3 / 10, 2 / 5, 1 / 2, 3 / 5, 9 / 10, 1]

def markerRows (_ : Unit) : List String :=
  markerFroms.flatMap fun f => [0, 1].flatMap fun t => markerThetas.map fun θ => markerJson f t θ

def ticks17 (a b : Nat) : List Ev := (List.range (b + 1 - a)).map fun i => .tick (17 * ((a + i : Nat) : Rat))

def attrCases : List (String × List Ev) :=
  [("open", .push 1 false 0 :: ticks17 1 42),
    ("reverse", (.push 1 false 0 :: ticks17 1 17) ++ .push 0 false 300 :: ticks17 18 64),
    ("close", (.push 1 false 0 :: ticks17 1 42) ++ .push 0 false 720 :: ticks17 43 84)]

def attrP : WaapiPremises := premisesWk 0

def bandJ (m : Rat) : Lean.Json := .arr ((band m).map Lean.Json.bool).toArray

def attrTrace (wr : VSt → Rat → Bool) (es : List Ev) : List (Ev × ASt × St) :=
  (es.foldl (fun (acc, x, s) e =>
    let x' := stepAttr attrP wr x e
    let s' := stepO s e
    (acc ++ [(e, x', s')], x', s')) (([] : List (Ev × ASt × St)), initA, rest)).1

def attrEvJson (c : String) : Ev × ASt × St → String
  | (.push g _ n, _, _) => (Lean.Json.mkObj [("kind", .str "attrEv"), ("case", .str c), ("ev", .str "push"),
      ("t", ratJ n), ("goal", ratJ g)]).compress
  | (.tick R, x, s) => (Lean.Json.mkObj [("kind", .str "attrEv"), ("case", .str c), ("ev", .str "tick"),
      ("t", ratJ R), ("value", ratJ s.value), ("band", bandJ s.value), ("old", bandJ x.attr)]).compress

def attrEvRows (c : String) (es : List Ev) : List String := (attrTrace oldW es).map (attrEvJson c)

def bandsAgree (wr : VSt → Rat → Bool) (es : List Ev) : Bool :=
  (attrTrace wr es).all fun (_, x, s) => band x.attr == band s.value

def attrJsonl (_ : Unit) : String :=
  String.join (attrReaders.map fun r => r.json ++ "\n") ++ String.join ((markerRows ()).map (· ++ "\n")) ++
    String.join (attrCases.flatMap fun (c, es) => (attrEvRows c es).map (· ++ "\n"))

#guard attrCases.all fun (_, es) => bandsAgree (fixW (dlLo delayDepth)) es && !bandsAgree oldW es
#guard markerThetas == [1 / 1000, 1 / 5, 2 / 5, 11 / 20, 23 / 25, 7 / 20]
#guard (markerRows ()).length == 108

theorem waapi_vis (P : WaapiPremises) (dl : Rat → Rat → Rat → Rat) (hd : DlSound dl)
    (vp : Fw.Site.Breakpoints.Env → Rect) (c : Fw.Site.Breakpoints.Env → Hist → AttrCtx)
    (S : Fw.Site.Breakpoints.Env → View → AttrScene → Scene) :
    VisSame E vp
      (fun env (h : Hist) =>
        S env (viewO h.1.1 h.1.2.1) (attrScene (c env h) (runO rest (h.1.1 ++ [.tick h.1.2.1])).value))
      (fun env h => S env (viewV P h.1.1 h.1.2.1)
        (attrScene (c env h) (runAttr P (fixW dl) initA (h.1.1 ++ [.tick h.1.2.1])).attr)) :=
  visSame_of_eq vp fun env h => by
    rw [view_eq P h, attrScene_band _ _ _ (attr_band P dl hd _ _ h.2.1)]

#guard viewV (premisesWk 0) [.push 1 false 100] 440 == viewO [.push 1 false 100] 440
#guard viewV (premisesBlink 5) [.push 1 false 0, .tick 100, .push 0 false 120] 400 ==
  viewO [.push 1 false 0, .tick 100, .push 0 false 120] 400

def dropsScript (v o : Work) (k : Nat) : Prop :=
  v.lt o ∧ (∀ s, s ≠ Stage.script → v.passes s = o.passes s ∧ v.units s = o.units s) ∧
    v.passes .script = 0 ∧ v.units .script = 0 ∧ o.passes .script = 1 ∧ o.units .script = k

theorem script_drop {P M : Type} (eng : Engine P M) (cs : List (Change P)) (k n : Nat) (hk : 0 < k) (hcs : cs ≠ [])
    (hS : ∀ c ∈ cs, Stage.script ∉ eng.stagesOf c) (hC : Stage.script ∉ eng.compStages)
    (hB : Stage.script ∉ eng.base) :
    dropsScript (frameWork eng ⟨0, 0, 0, 0, cs, n⟩) (frameWork eng ⟨k, 0, 0, 0, cs, n⟩) k := by
  have hcsE : cs.isEmpty = false := by cases cs <;> simp_all
  have hfp : ∀ (q : Nat) (s : Stage), forcedPasses (⟨q, 0, 0, 0, cs, n⟩ : FrameIn P) s = 0 := by
    intro q s; cases s <;> rfl
  have hto : touched eng ⟨k, 0, 0, 0, cs, n⟩ = touched eng ⟨0, 0, 0, 0, cs, n⟩ ++ [.script] := by
    simp [touched, FrameIn.updates, hcsE, hk]
  have hnot : Stage.script ∉ touched eng ⟨0, 0, 0, 0, cs, n⟩ := by
    simp only [touched, FrameIn.updates, hcsE, List.mem_append, List.mem_flatMap]
    intro h
    rcases h with ((⟨c, hc, hsc⟩ | h) | h) | h
    · exact hS c hc hsc
    · split at h
      · exact hC h
      · simp at h
    · simp at h; exact hB h
    · simp at h
  have hcount : cs.countP (fun c => decide (Stage.script ∈ eng.stagesOf c)) = 0 := by
    rw [List.countP_eq_zero]; intro c hc; simpa using hS c hc
  have hpass : ∀ s, s ≠ Stage.script →
      (frameWork eng ⟨0, 0, 0, 0, cs, n⟩).passes s = (frameWork eng ⟨k, 0, 0, 0, cs, n⟩).passes s := by
    intro s hs
    simp only [frameWork, hfp, hto, List.mem_append, List.mem_singleton, hs, or_false]
  have hunit : ∀ s, s ≠ Stage.script →
      (frameWork eng ⟨0, 0, 0, 0, cs, n⟩).units s = (frameWork eng ⟨k, 0, 0, 0, cs, n⟩).units s := by
    intro s hs
    simp [frameWork, stageUnits, hs]
  have hv1 : (frameWork eng ⟨0, 0, 0, 0, cs, n⟩).passes .script = 0 := by
    simp only [frameWork, hfp, hnot, ite_false]
  have hv2 : (frameWork eng ⟨0, 0, 0, 0, cs, n⟩).units .script = 0 := by
    simp [frameWork, stageUnits, hcount, hC]
  have ho1 : (frameWork eng ⟨k, 0, 0, 0, cs, n⟩).passes .script = 1 := by
    simp [frameWork, hfp, hto]
  have ho2 : (frameWork eng ⟨k, 0, 0, 0, cs, n⟩).units .script = k := by
    simp [frameWork, stageUnits, hcount, hC]
  refine ⟨⟨⟨fun s => ?_, Nat.le_refl _⟩, Or.inl ⟨.script, Or.inl (by rw [hv1, ho1]; decide)⟩⟩,
    fun s hs => ⟨hpass s hs, hunit s hs⟩, hv1, hv2, ho1, ho2⟩
  by_cases hs : s = .script
  · subst hs; rw [hv1, hv2, ho1, ho2]; exact ⟨Nat.zero_le _, Nat.zero_le _⟩
  · rw [hpass s hs, hunit s hs]; exact ⟨Nat.le_refl _, Nat.le_refl _⟩

theorem cr_custom_main (m : Chromium.CrMode) (a : Chromium.CrAnim)
    (h : ∃ i rs, Chromium.CrProp.custom i rs ∈ a.props) :
    Chromium.crThread m a = .main ∧ 13 ∈ Chromium.failBits m a := by
  obtain ⟨i, rs, hm⟩ := h
  have hall : a.props.all Chromium.CrProp.eligible = false := by
    rw [List.all_eq_false]; exact ⟨_, hm, by simp [Chromium.CrProp.eligible]⟩
  refine ⟨?_, ?_⟩
  · simp [Chromium.crThread, hall]
  · simp [Chromium.failBits, hall]

theorem cr_no_script (c : Change Chromium.CrProp) : Stage.script ∉ Chromium.crStagesOf c := by
  unfold Chromium.crStagesOf
  generalize Chromium.crLevel c.prop c.layer = L
  have hL : Stage.script ∉ L.stages := by cases L <;> decide
  have hX : Stage.script ∉ c.prop.extra := by
    cases c.prop with
    | scroll r => cases r <;> decide
    | _ => simp [Chromium.CrProp.extra]
  simp only [List.mem_append, not_or]; exact ⟨hL, hX⟩

theorem waapi_work_le_chromium (as : List Chromium.CrAnim) (k : Nat) (hk : 0 < k)
    (hne : as.flatMap Chromium.CrAnim.changes ≠ [])
    (hcu : ∀ a ∈ as, ∃ i rs, Chromium.CrProp.custom i rs ∈ a.props) :
    dropsScript (frameWork Chromium.chromium (Chromium.animFrame Chromium.lane as))
      (frameWork Chromium.chromium (Chromium.jsWrite k (as.flatMap Chromium.CrAnim.changes))) k := by
  have hmain : as.filter (fun a => decide (Chromium.crThread Chromium.lane a = .main)) = as := by
    rw [List.filter_eq_self]; intro a ha; simp [(cr_custom_main _ a (hcu a ha)).1]
  have hcomp : (as.filter fun a => decide (Chromium.crThread Chromium.lane a = .comp)).length = 0 := by
    rw [List.length_eq_zero_iff, List.filter_eq_nil_iff]; intro a ha; simp [(cr_custom_main _ a (hcu a ha)).1]
  have hv : Chromium.animFrame Chromium.lane as = ⟨0, 0, 0, 0, as.flatMap Chromium.CrAnim.changes, 0⟩ := by
    simp only [Chromium.animFrame, hmain, hcomp]
  rw [hv]
  refine script_drop _ _ k 0 hk hne (fun c _ => cr_no_script c) ?_ (by simp [Chromium.chromium, Chromium.chromiumAt])
  simp [Chromium.chromium, Chromium.chromiumAt, Chromium.crCompStages, Chromium.lane]

theorem wk_no_script (d : WebKit.Diff) : Stage.script ∉ WebKit.diffStages d := by cases d <;> decide

theorem waapi_work_le_webkit (a : WebKit.WkAnim) (cs : List (Change WebKit.WkProp)) (k : Nat) (hk : 0 < k)
    (hne : cs ≠ []) (hc : WebKit.CssProp.custom ∈ a.props) :
    dropsScript (frameWork WebKit.webkit (WebKit.animFrame .safari a cs)) (frameWork WebKit.webkit ⟨k, 0, 0, 0, cs, 0⟩) k := by
  have hv : WebKit.animFrame .safari a cs = ⟨0, 0, 0, 0, cs, 0⟩ := by
    simp [WebKit.animFrame, WebKit.custom_main _ a hc]
  rw [hv]
  exact script_drop _ _ k 0 hk hne (fun c _ h => by
    simp only [WebKit.webkit, WebKit.webkitAt] at h
    exact wk_no_script _ ((WebKit.mem_wkStages_of_ne c (s := .script) (by decide)).1 h)) (by decide) (by decide)

theorem waapi_work_le (as : List Chromium.CrAnim) (a : WebKit.WkAnim) (cs : List (Change WebKit.WkProp)) (k : Nat)
    (hk : 0 < k) (hne : as.flatMap Chromium.CrAnim.changes ≠ [])
    (hcu : ∀ a' ∈ as, ∃ i rs, Chromium.CrProp.custom i rs ∈ a'.props) (hcs : cs ≠ [])
    (hc : WebKit.CssProp.custom ∈ a.props) :
    dropsScript (frameWork Chromium.chromium (Chromium.animFrame Chromium.lane as))
        (frameWork Chromium.chromium (Chromium.jsWrite k (as.flatMap Chromium.CrAnim.changes))) k ∧
      dropsScript (frameWork WebKit.webkit (WebKit.animFrame .safari a cs))
        (frameWork WebKit.webkit ⟨k, 0, 0, 0, cs, 0⟩) k :=
  ⟨waapi_work_le_chromium as k hk hne hcu, waapi_work_le_webkit a cs k hk hcs hc⟩

theorem drop_run_dominates (v o : Work) (k N : Nat) (h : dropsScript v o k) (hN : 0 < N) :
    Screen.screen (toRun (List.replicate N o)) (toRun (List.replicate N v)) = .ok .dominates := by
  have hle : ∀ N, leAll (List.replicate N v) (List.replicate N o) = true := by
    intro N; induction N with
    | zero => rfl
    | succ N ih => simp [List.replicate_succ, leAll, ih, (Work.leb_iff v o).2 h.1.1]
  have hlt : someLt (List.replicate N v) (List.replicate N o) = true := by
    obtain ⟨N', rfl⟩ : ∃ N', N = N' + 1 := ⟨N - 1, by omega⟩
    simp [someLt, List.replicate_succ, (Work.ltb_iff v o).2 h.1]
  exact run_dominates (hle N) hlt

def crMorph : Chromium.CrAnim := { elem := 0, props := [.custom 0 [.opacity]], layer := .none }

def wkMorph : WebKit.WkAnim := .clean [.custom] .time

def predW (v o : Work) (s : Stage) : String :=
  if v.passes s = o.passes s ∧ v.units s = o.units s then "=o"
  else if v.passes s ≤ o.passes s ∧ v.units s ≤ o.units s then "<o"
  else "any"

def predStage (s : Stage) : String := if s = .script then "<o" else "=o"

theorem pred_sound (v o : Work) (k : Nat) (h : dropsScript v o k) (s : Stage) : predW v o s = predStage s := by
  obtain ⟨_, heq, hv1, hv2, ho1, ho2⟩ := h
  unfold predW predStage
  by_cases hs : s = .script
  · subst hs; simp [hv1, hv2, ho1, ho2]
  · simp [hs, (heq s hs).1, (heq s hs).2]

#guard Stage.all.all fun s =>
  predW (frameWork Chromium.chromium (Chromium.animFrame Chromium.lane [crMorph]))
    (frameWork Chromium.chromium (Chromium.jsWrite 1 crMorph.changes)) s == predStage s
#guard Stage.all.all fun s =>
  predW (frameWork WebKit.webkit (WebKit.animFrame .safari wkMorph [⟨0, .opacity, .none⟩]))
    (frameWork WebKit.webkit (WebKit.jsFrame [⟨0, .opacity, .none⟩])) s == predStage s
#guard Chromium.failBits Chromium.lane crMorph == [13]

def seenAt (inh : Bool) (a i : Rat) : Nat → Rat
  | 0 => a
  | d + 1 => if inh then seenAt inh a i d else i

theorem seenAt_true (a i : Rat) (d : Nat) : seenAt true a i d = a := by
  induction d with
  | zero => rfl
  | succ d ih => simp [seenAt, ih]

theorem seenAt_false_succ (a i : Rat) (d : Nat) : seenAt false a i (d + 1) = i := rfl

structure Reader where
  prop : String
  sel : String
  depth : Nat
deriving Repr, DecidableEq

def readers : List Reader :=
  [⟨"--morph", "nav", 0⟩, ⟨"--morph", "logo", 2⟩, ⟨"--morph", "actions", 2⟩, ⟨"--morph", "earn", 3⟩,
   ⟨"--morph", "panel", 1⟩, ⟨"--morph", "section", 0⟩, ⟨"--morph-fade", "section", 0⟩]

def readersOf (p : String) : List Nat := (readers.filter (·.prop == p)).map (·.depth)

def needsInherit (ds : List Nat) : Bool := ds.any (0 < ·)

#guard needsInherit (readersOf "--morph") && !needsInherit (readersOf "--fw-morph-dark")
#guard !needsInherit [] && !needsInherit [0, 0] && needsInherit [0, 1]

theorem sees_iff (inh : Bool) (i : Rat) (ds : List Nat) :
    (∀ a, ∀ d ∈ ds, seenAt inh a i d = a) ↔ (inh = true ∨ needsInherit ds = false) := by
  constructor
  · intro h
    cases inh with
    | true => exact Or.inl rfl
    | false =>
      refine Or.inr ?_
      simp only [needsInherit, List.any_eq_false, decide_eq_true_eq, Nat.not_lt, Nat.le_zero]
      intro d hd
      cases d with
      | zero => rfl
      | succ d =>
        have := h (i + 1) (d + 1) hd
        rw [seenAt_false_succ] at this
        grind
  · rintro (h | h) a d hd
    · subst h; exact seenAt_true a i d
    · simp only [needsInherit, List.any_eq_false, decide_eq_true_eq, Nat.not_lt, Nat.le_zero] at h
      rw [h d hd]; rfl

structure Registration where
  name : String
  syntaxStr : String
  inherits : Bool
  initialValue : String
deriving Repr, DecidableEq

/-- Whether the original has the property `p` as an inherited custom property: `--morph` and `--morph-fade` are
written there unregistered, so inherited (Chromium `custom_property.cc:22-23`@f842f52, WebKit
`StyleBuilder.cpp:103-106`@862f17d); the flags are classes there, and any other name is absent.

The original's inheritance bit per property. -/
def origInheritsOf (p : String) : Bool := p == "--morph" || p == "--morph-fade"

def registrations : List Registration :=
  [⟨"--morph", "<number>", true, "0"⟩, ⟨"--morph-fade", "<number>", true, "1"⟩,
   ⟨"--fw-morph-dark", "<number>", false, "0"⟩, ⟨"--fw-morph-expanded", "<number>", false, "0"⟩]

theorem registrations_rule :
    ∀ r ∈ registrations, r.inherits = (needsInherit (readersOf r.name) || origInheritsOf r.name) := by decide

theorem registrations_see :
    ∀ r ∈ registrations, ∀ a i : Rat, ∀ d ∈ readersOf r.name, seenAt r.inherits a i d = a := by
  intro r hr a i d hd
  refine (sees_iff r.inherits i (readersOf r.name)).2 ?_ a d hd
  rw [registrations_rule r hr]
  cases needsInherit (readersOf r.name) <;> cases origInheritsOf r.name <;> simp

theorem panel_blind_without_inherit (a i : Rat) (h : a ≠ i) :
    (⟨"--morph", "panel", 1⟩ : Reader) ∈ readers ∧ seenAt false a i 1 ≠ a :=
  ⟨by decide, fun e => h (by rw [seenAt_false_succ] at e; exact e.symm)⟩

def regInherits (p : String) : Bool := ((registrations.find? (·.name == p)).map (·.inherits)).getD false

def recalcs (inh : Bool) (d : Nat) : Bool := d == 0 || inh

theorem morph_scope_eq :
    (∀ (p : String) (ds : List Nat) (a i : Rat) (d : Nat), origInheritsOf p = true →
      ds.filter (recalcs (regInherits p)) = ds.filter (recalcs (origInheritsOf p)) ∧
        seenAt (regInherits p) a i d = seenAt (origInheritsOf p) a i d) ∧
    (∀ ds : List Nat, needsInherit ds = true → ds.filter (recalcs false) ≠ ds.filter (recalcs true)) := by
  refine ⟨fun p ds a i d hp => ?_, fun ds h e => ?_⟩
  · have hv : regInherits p = true := by
      simp only [origInheritsOf, Bool.or_eq_true, beq_iff_eq] at hp
      rcases hp with rfl | rfl <;> decide
    rw [hv, hp]; exact ⟨rfl, rfl⟩
  · simp only [needsInherit, List.any_eq_true, decide_eq_true_eq] at h
    obtain ⟨d, hd, hpos⟩ := h
    have hin : d ∈ ds.filter (recalcs true) := by simp [recalcs, hd]
    rw [← e] at hin
    simp [recalcs] at hin
    omega

#guard regInherits "--morph" && regInherits "--morph-fade" && !regInherits "--fw-morph-dark" && !regInherits "--x"
#guard registrations.head? == some ⟨"--morph", "<number>", true, "0"⟩
#guard readers.all fun r => (registrations.find? (·.name == r.prop)).isSome
#guard seenAt false 1 0 1 == 0 && seenAt true 1 0 3 == 1

def Registration.json (r : Registration) : String :=
  (Lean.Json.mkObj [("name", .str r.name), ("syntax", .str r.syntaxStr), ("inherits", .bool r.inherits),
    ("initialValue", .str r.initialValue)]).compress

def Reader.json (r : Reader) : String :=
  (Lean.Json.mkObj [("prop", .str r.prop), ("sel", .str r.sel), ("depth", (r.depth : Lean.Json))]).compress

#guard registrations.head?.map Registration.json ==
  some "{\"inherits\":true,\"initialValue\":\"0\",\"name\":\"--morph\",\"syntax\":\"<number>\"}"
#guard readers.head?.map Reader.json == some "{\"depth\":0,\"prop\":\"--morph\",\"sel\":\"nav\"}"

def readersScoped : List Reader :=
  [⟨"--morph", "nav", 0⟩, ⟨"--morph", "logo", 2⟩, ⟨"--morph", "actions", 2⟩, ⟨"--morph", "earn", 3⟩,
   ⟨"--morph", "panel", 1⟩, ⟨"--platform-morph", "section", 0⟩, ⟨"--morph-fade", "section", 0⟩]

def readersOfS (p : String) : List Nat := (readersScoped.filter (·.prop == p)).map (·.depth)

def registrationsScoped : List Registration :=
  [⟨"--morph", "<number>", true, "0"⟩, ⟨"--morph-fade", "<number>", false, "1"⟩,
   ⟨"--fw-morph-dark", "<number>", false, "0"⟩, ⟨"--fw-morph-expanded", "<number>", false, "0"⟩,
   ⟨"--platform-morph", "<number>", false, "0"⟩]

theorem registrationsScoped_rule :
    ∀ r ∈ registrationsScoped, r.inherits = needsInherit (readersOfS r.name) := by decide

theorem registrationsScoped_see :
    ∀ r ∈ registrationsScoped, ∀ a i : Rat, ∀ d ∈ readersOfS r.name, seenAt r.inherits a i d = a := by
  intro r hr a i d hd
  refine (sees_iff r.inherits i (readersOfS r.name)).2 ?_ a d hd
  rw [registrationsScoped_rule r hr]
  cases needsInherit (readersOfS r.name) <;> simp

def regInheritsS (p : String) : Bool := ((registrationsScoped.find? (·.name == p)).map (·.inherits)).getD false

theorem scoped_scope_le :
    ∀ (p : String) (ds : List Nat) (a i : Rat), origInheritsOf p = true →
      (ds.filter (recalcs (regInheritsS p))).Sublist (ds.filter (recalcs (origInheritsOf p))) ∧
        ∀ d ∈ readersOfS p, seenAt (regInheritsS p) a i d = seenAt (origInheritsOf p) a i d := by
  intro p ds a i hp
  rw [hp]
  refine ⟨?_, ?_⟩
  · have : ds.filter (recalcs true) = ds := by simp [recalcs]
    rw [this]; exact List.filter_sublist
  · simp only [origInheritsOf, Bool.or_eq_true, beq_iff_eq] at hp
    rcases hp with rfl | rfl
    · intro d _; rfl
    · intro d hd
      have : d = 0 := by simpa [readersOfS, readersScoped] using hd
      subst this; rfl

theorem platform_morph_local (ds : List Nat) :
    ds.filter (recalcs (regInheritsS "--platform-morph")) = ds.filter (· == 0) := by
  have : regInheritsS "--platform-morph" = false := by decide
  rw [this]; congr 1; funext d; simp [recalcs]

/-- The strict descendants of the platform section (depths `ds`) that one frame restyles through a property with
inheritance bit `inh` whose value on the section goes from `x` to `y`. An unchanged value restyles none: an animated
value that computes equal gives no style difference, and an equal inline write is dropped (Chromium
`css/abstract_property_set_css_style_declaration.cc:278-281`@f842f52). -/
def frameBelow (inh : Bool) (x y : Rat) (ds : List Nat) : List Nat :=
  if x = y then [] else ds.filter fun d => decide (0 < d) && recalcs inh d

theorem waapi_section_finding (m m' : Rat) (ds : List Nat) (hm : fadeEnd ≤ m) (hm' : fadeEnd ≤ m')
    (hne : m ≠ m') :
    frameBelow true (fade m) (fade m') ds = [] ∧ frameBelow true m m' ds = ds.filter (0 < ·) := by
  refine ⟨?_, ?_⟩
  · simp [frameBelow, fade_ends.2 m hm, fade_ends.2 m' hm']
  · simp [frameBelow, hne, recalcs]

theorem orig_below_le_waapi (m m' : Rat) (ds : List Nat) :
    (frameBelow true (fade m) (fade m') ds).Sublist (frameBelow true m m' ds) := by
  unfold frameBelow
  by_cases h : m = m'
  · subst h; simp
  · simp only [h, ↓reduceIte]; split <;> simp

theorem scoped_below_nil (x y x' y' : Rat) (ds : List Nat) :
    frameBelow (regInheritsS "--platform-morph") x y ds = [] ∧
      frameBelow (regInheritsS "--morph-fade") x' y' ds = [] := by
  have h1 : regInheritsS "--platform-morph" = false := by decide
  have h2 : regInheritsS "--morph-fade" = false := by decide
  rw [h1, h2]
  have key : ∀ a b : Rat, frameBelow false a b ds = [] := by
    intro a b
    unfold frameBelow
    split
    · rfl
    · simp only [recalcs, Bool.or_false, List.filter_eq_nil_iff, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq]
      omega
  exact ⟨key x y, key x' y'⟩

def platformMorphV (P : WaapiPremises) (es : List Ev) (R : Rat) : Rat := valV P (runV P initV es) (P.tl R)

def fadeScopedEval (x : Rat) : Rat := 1 - min 1 (x / (55 / 100))

theorem fade_eq (P : WaapiPremises) (h : Hist) :
    fadeScopedEval (platformMorphV P h.1.1 h.1.2.1) = fade (viewO h.1.1 h.1.2.1).m := by
  have hm : (viewV P h.1.1 h.1.2.1).m = (viewO h.1.1 h.1.2.1).m := by rw [view_eq P h]
  simp only [viewV] at hm
  unfold platformMorphV fadeScopedEval
  rw [hm, fade_css]

#guard !regInheritsS "--morph-fade" && regInheritsS "--morph" && !regInheritsS "--platform-morph"
#guard readersScoped.all fun r => (registrationsScoped.find? (·.name == r.prop)).isSome
#guard fadeScopedEval 0 == 1 && fadeScopedEval (11 / 40) == 1 / 2 && fadeScopedEval (3 / 5) == 0
#guard (readers ++ readersScoped).all (·.prop.startsWith "--")
#guard frameBelow true (fade (3 / 5)) (fade (7 / 10)) [0, 1, 2] == [] && frameBelow true (3 / 5) (7 / 10) [0, 1, 2] == [1, 2]
#guard frameBelow false (3 / 5) (7 / 10) [0, 1, 2] == []

def Registration.jsonArm (arm : String) (r : Registration) : String :=
  (Lean.Json.mkObj [("arm", .str arm), ("name", .str r.name), ("syntax", .str r.syntaxStr),
    ("inherits", .bool r.inherits), ("initialValue", .str r.initialValue)]).compress

def Reader.jsonArm (arm : String) (r : Reader) : String :=
  (Lean.Json.mkObj [("arm", .str arm), ("prop", .str r.prop), ("sel", .str r.sel),
    ("depth", (r.depth : Lean.Json))]).compress

#guard readersScoped.getLast?.map (Reader.jsonArm "waapi-scoped") ==
  some "{\"arm\":\"waapi-scoped\",\"depth\":0,\"prop\":\"--morph-fade\",\"sel\":\"section\"}"

inductive Mode where
  | scroll
  | wheel
  | touch
deriving Repr, DecidableEq

def modeOf : String → Mode
  | "swipe-touch-v1" => .touch
  | "swipe-wheel-v1" => .wheel
  | _ => .scroll

inductive Input where
  | scrollTo
  | wheel (g : Rat) (rm : Bool) (n : Rat)
  | touchmove (g : Rat) (rm : Bool) (n : Rat)
  | frame (R : Rat)
deriving Repr, DecidableEq

def Input.sentBy : Mode → Input → Bool
  | _, .frame _ => true
  | .scroll, .scrollTo => true
  | .wheel, .wheel .. => true
  | .touch, .touchmove .. => true
  | _, _ => false

def drive : Input → List Ev
  | .scrollTo => []
  | .wheel g rm n => [.push g rm n]
  | .touchmove g rm n => [.push g rm n]
  | .frame R => [.tick R]

def pushes (m : Mode) : Bool := m != .scroll

def noPushB (es : List Ev) : Bool := es.all fun | .push .. => false | .tick _ => true

def tweenFlags : St → List Ev → List Bool
  | _, [] => []
  | s, .push g rm n :: es => tweenFlags (push s g rm n) es
  | s, .tick R :: es => s.pending :: tweenFlags (stepO s (.tick R)) es

#guard tweenFlags rest [.tick 0, .push 1 false 0, .tick 16, .tick 800, .tick 816] == [false, true, true, false]
#guard Input.sentBy .scroll .scrollTo && !Input.sentBy .scroll (.wheel 1 false 0) &&
  Input.sentBy .touch (.touchmove 1 false 0) && !Input.sentBy .touch .scrollTo
#guard noPushB ([Input.scrollTo, .frame 0, .scrollTo, .frame 16].flatMap drive)
#guard !noPushB ([Input.touchmove 1 false 0, .frame 0].flatMap drive)
#guard (["swipe-v1", "swipe-touch-v1", "swipe-wheel-v1"].map fun p => pushes (modeOf p)) == [false, true, true]

theorem noPush_scroll (xs : List Input) (h : ∀ x ∈ xs, Input.sentBy .scroll x = true) :
    noPushB (xs.flatMap drive) = true := by
  induction xs with
  | nil => rfl
  | cons x xs ih =>
    have hx := h x (by simp)
    have ht := ih fun y hy => h y (by simp [hy])
    rw [List.flatMap_cons, noPushB, List.all_append]
    rw [noPushB] at ht
    rw [ht, Bool.and_true]
    cases x <;> simp_all [Input.sentBy, drive]

theorem tweenFlags_noPush (s : St) (es : List Ev) (hs : s.pending = false) (h : noPushB es = true) :
    ∀ b ∈ tweenFlags s es, b = false := by
  induction es generalizing s with
  | nil => simp [tweenFlags]
  | cons e es ih =>
    cases e with
    | push g rm n => simp [noPushB] at h
    | tick R =>
      have h' : noPushB es = true := by simpa [noPushB] using h
      intro b hb
      simp only [tweenFlags, List.mem_cons] at hb
      rcases hb with rfl | hb
      · exact hs
      · exact ih _ (by simp [stepO, hs]) h' b hb

theorem anim_noPush (P : WaapiPremises) (w : VSt) (es : List Ev) (hw : w.anim = none) (h : noPushB es = true) :
    (runV P w es).anim = none := by
  induction es generalizing w with
  | nil => exact hw
  | cons e es ih =>
    cases e with
    | push g rm n => simp [noPushB] at h
    | tick R => exact ih _ (by simpa [stepV] using hw) (by simpa [noPushB] using h)

theorem noPush_eqO (P : WaapiPremises) (xs : List Input) (h : ∀ x ∈ xs, Input.sentBy .scroll x = true)
    (cbs : List Nat) :
    Chromium.rafSeries (cbs.zip (tweenFlags rest (xs.flatMap drive))) false =
        Chromium.rafSeries (cbs.zip (tweenFlags rest (xs.flatMap drive))) true ∧
      (runV P initV (xs.flatMap drive)).anim = none := by
  have hn := noPush_scroll xs h
  refine ⟨(Chromium.waapi_raf_eq_iff _).2 fun x hx => ?_, anim_noPush P initV _ rfl hn⟩
  exact tweenFlags_noPush rest _ rfl hn x.2 (List.of_mem_zip hx).2

theorem raf_sum_eq (fs : List (Nat × Bool)) :
    (Chromium.rafSeries fs true).sum = (Chromium.rafSeries fs false).sum + (fs.filter (·.2)).length := by
  induction fs with
  | nil => rfl
  | cons y ys ih =>
    simp only [Chromium.rafSeries, List.map_cons, List.sum_cons, List.filter_cons] at ih ⊢
    simp at ih ⊢; cases y.2 <;> simp <;> omega

theorem raf_sum_lt (fs : List (Nat × Bool)) (h : ∃ x ∈ fs, x.2 = true) :
    (Chromium.rafSeries fs false).sum < (Chromium.rafSeries fs true).sum := by
  obtain ⟨x, hx, hx2⟩ := h
  have : 0 < (fs.filter (·.2)).length := List.length_pos_of_mem (List.mem_filter.2 ⟨hx, by simpa using hx2⟩)
  rw [raf_sum_eq]
  omega

theorem tween_of_push (s : St) (g n R : Rat) (es : List Ev) (hg : s.target ≠ g) :
    tweenFlags s (.push g false n :: .tick R :: es) = true :: tweenFlags (frame (push s g false n) R) es := by
  simp [tweenFlags, push, hg, stepO]

def predProfile (m : Mode) (s : Stage) : String := if pushes m then predStage s else "=o"

def compPred (m : Mode) : String := if pushes m then "<o" else "=o"

theorem predProfile_push (m : Mode) (h : pushes m = true) (s : Stage) : predProfile m s = predStage s := by
  simp [predProfile, h]

theorem predProfile_noPush (m : Mode) (h : pushes m = false) (s : Stage) :
    predProfile m s = "=o" ∧ compPred m = "=o" := by
  simp [predProfile, compPred, h]

#guard (Stage.all.map (predProfile .scroll)).all (· == "=o")
#guard Stage.all.map (predProfile .touch) == Stage.all.map predStage
#guard compPred .touch == "<o" && compPred .scroll == "=o"

theorem start_eq_refuted (sr : Rat → Rat) (n₁ n₂ : Rat) (h₁ : sr n₁ = n₁) (h₂ : sr n₂ < n₂) :
    ¬ ∃ c : Rat, ∀ n, sr n = n + c := by
  rintro ⟨c, hc⟩
  rw [hc] at h₁ h₂
  grind

theorem lead_within_frame (n δ R p : Rat) (hδ : 0 < δ) (hp : δ < p) :
    R - n < R - (n - δ) ∧ R - (n - δ) < (R + p) - n := by
  constructor <;> grind

structure PredRow where
  engine : String
  scenario : String
  variant : String
  stage : String
  prediction : String
  countType : String
  base : String
deriving Repr, DecidableEq

def armV : String := "rewrite+?fw=morph.tween:waapi"

def countsOf : String → List (Stage × String)
  | "chromium" => [(.script, "trace.FireAnimationFrame"), (.style, "trace.UpdateLayoutTree"), (.layout, "trace.Layout"),
      (.paint, "trace.Paint"), (.commit, "trace.cc.Commit")]
  | "webkit" => [(.script, "FireAnimationFrame"), (.style, "RecalculateStyles"), (.layout, "Layout"),
      (.paint, "Paint"), (.commit, "Composite")]
  | _ => []

def rowsFor (sc : String) : List PredRow :=
  (["chromium", "webkit"].flatMap fun e => (countsOf e).map fun (s, k) =>
    ⟨e, sc, armV, WebKit.stageName s, predProfile (modeOf sc) s, k, "rewrite"⟩) ++
  [⟨"chromium", sc, "rewrite", "comp", compPred (modeOf sc), "trace.Animation.compositeFailedBits", armV⟩]

def goldenRows : List PredRow := rowsFor "swipe-touch-v1"

def swipeRows : List PredRow := rowsFor "swipe-v1"

theorem swipeRows_eqO : ∀ r ∈ swipeRows, r.prediction = "=o" := by decide

def PredRow.json (r : PredRow) : String :=
  (Lean.Json.mkObj [("engine", .str r.engine), ("scenario", .str r.scenario), ("variant", .str r.variant),
    ("stage", .str r.stage), ("prediction", .str r.prediction), ("countType", .str r.countType),
    ("base", .str r.base)]).compress

def goldenJsonl : String :=
  String.join (goldenRows.map fun r => r.json ++ "\n") ++ String.join (registrations.map fun r => r.json ++ "\n") ++
    String.join (readers.map fun r => r.json ++ "\n") ++
    String.join (registrationsScoped.map fun r => r.jsonArm "waapi-scoped" ++ "\n") ++
    String.join (readersScoped.map fun r => r.jsonArm "waapi-scoped" ++ "\n")

#guard goldenJsonl == include_str "../../../packages/contracts/golden/parts/morph-tween-waapi.jsonl"

#guard attrJsonl () == include_str "../../../packages/contracts/golden/parts/morph-tween-waapi.attr.jsonl"

def swipeJsonl : String := String.join (swipeRows.map fun r => r.json ++ "\n")

#guard swipeJsonl == include_str "../../../packages/contracts/golden/parts/morph-tween-waapi.swipe-v1.jsonl"
#guard swipeRows.length == 11
#guard goldenRows.length == 11
#guard (goldenRows.filter fun r => r.prediction == "<o").length == 3
#guard goldenRows.head?.map PredRow.json ==
  some "{\"base\":\"rewrite\",\"countType\":\"trace.FireAnimationFrame\",\"engine\":\"chromium\",\"prediction\":\"<o\",\"scenario\":\"swipe-touch-v1\",\"stage\":\"script\",\"variant\":\"rewrite+?fw=morph.tween:waapi\"}"

section EndPass

open Fw.Parts.EndFlags

theorem waapi_work_leE (as : List Chromium.CrAnim) (a : WebKit.WkAnim) (cs : List (Change WebKit.WkProp)) (k : Nat)
    (hk : 0 < k) (hne : as.flatMap Chromium.CrAnim.changes ≠ [])
    (hcu : ∀ a' ∈ as, ∃ i rs, Chromium.CrProp.custom i rs ∈ a'.props) (hcs : cs ≠ [])
    (hc : WebKit.CssProp.custom ∈ a.props) (e1 e2 e3 e4 : Stage → Bool)
    (h1 : ∀ s, s ∈ touched Chromium.chromium (Chromium.animFrame Chromium.lane as) → e1 s = true)
    (h2 : ∀ s, s ∈ touched Chromium.chromium (Chromium.jsWrite k (as.flatMap Chromium.CrAnim.changes)) →
      e2 s = true)
    (h3 : ∀ s, s ∈ touched WebKit.webkit (WebKit.animFrame .safari a cs) → e3 s = true)
    (h4 : ∀ s, s ∈ touched WebKit.webkit ⟨k, 0, 0, 0, cs, 0⟩ → e4 s = true) :
    dropsScript (frameWorkE Chromium.chromium (Chromium.animFrame Chromium.lane as) e1)
        (frameWorkE Chromium.chromium (Chromium.jsWrite k (as.flatMap Chromium.CrAnim.changes)) e2) k ∧
      dropsScript (frameWorkE WebKit.webkit (WebKit.animFrame .safari a cs) e3)
        (frameWorkE WebKit.webkit ⟨k, 0, 0, 0, cs, 0⟩ e4) k := by
  rw [frameWorkE_eq_of_dirty _ _ e1 h1, frameWorkE_eq_of_dirty _ _ e2 h2, frameWorkE_eq_of_dirty _ _ e3 h3,
    frameWorkE_eq_of_dirty _ _ e4 h4]
  exact waapi_work_le as a cs k hk hne hcu hcs hc

end EndPass

def overlayOf (innerW clientW : Int) : Bool := decide (innerW - clientW ≤ 0)

def lockOn (overlay active : Bool) : Bool := overlay && active

def lockWrite (overlay l active : Bool) : Option Bool :=
  if lockOn overlay active = l then none else some (lockOn overlay active)

structure LSt where
  s : St
  locked : Bool
deriving Repr, DecidableEq

def stepL (overlay : Bool) (x : LSt) (e : Ev) : LSt :=
  let s := stepO x.s e
  ⟨s, lockOn overlay s.isActive⟩

def runL (overlay : Bool) (es : List Ev) : LSt := es.foldl (stepL overlay) ⟨rest, false⟩

def writesL (overlay : Bool) : LSt → List Ev → List (Option Bool)
  | _, [] => []
  | x, e :: es =>
    let y := stepL overlay x e
    lockWrite overlay x.locked y.s.isActive :: writesL overlay y es

theorem foldl_stepL_s (ov : Bool) (es : List Ev) (x : LSt) : (es.foldl (stepL ov) x).s = es.foldl stepO x.s := by
  induction es generalizing x with
  | nil => rfl
  | cons e es ih => simp only [List.foldl, ih, stepL]

theorem runL_s (ov : Bool) (es : List Ev) : (runL ov es).s = runO rest es := foldl_stepL_s ov es _

theorem foldl_stepL_locked (ov : Bool) (es : List Ev) (x : LSt) (h : x.locked = lockOn ov x.s.isActive) :
    (es.foldl (stepL ov) x).locked = lockOn ov (es.foldl (stepL ov) x).s.isActive := by
  induction es generalizing x with
  | nil => exact h
  | cons e es ih => exact ih _ rfl

theorem runL_locked (ov : Bool) (es : List Ev) : (runL ov es).locked = lockOn ov (runO rest es).isActive := by
  have h : (0 : Rat) < activeCut := by
    rw [activeCut, Rat.div_def, Rat.one_mul]; exact Rat.inv_pos.2 (by decide)
  rw [← runL_s]
  exact foldl_stepL_locked ov es _ (by
    cases ov <;> simp [lockOn, St.isActive, active, rest, Rat.not_lt.2 (Rat.le_of_lt h)])

theorem classic_writes (x : LSt) (es : List Ev) (hx : x.locked = false) : ∀ w ∈ writesL false x es, w = none := by
  induction es generalizing x with
  | nil => simp [writesL]
  | cons e es ih =>
    intro w hw
    simp only [writesL, List.mem_cons] at hw
    rcases hw with rfl | hw
    · simp [lockWrite, lockOn, hx]
    · exact ih _ (by simp [stepL, lockOn]) w hw

theorem write_flips (ov l a b : Bool) (h : lockWrite ov l a = some b) : b = !l := by
  unfold lockWrite at h; split at h <;> simp_all; cases l <;> simp_all

theorem write_iff (ov l a : Bool) : (lockWrite ov l a).isSome = true ↔ lockOn ov a ≠ l := by
  unfold lockWrite; split <;> simp_all

#guard overlayOf 1280 1280 && !overlayOf 1280 1265 && overlayOf 390 393
#guard lockOn true true && !lockOn false true && !lockOn true false
#guard lockWrite true false true == some true && lockWrite true true false == some false && lockWrite false false true == none
#guard (runL true [.push 1 false 0]).locked && !(runL false [.push 1 false 0]).locked
#guard writesL true ⟨rest, false⟩ [.push 1 true 0, .push 0 true 10] == [some true, some false]

def readsAt (was now : Bool) : Bool := !was && now

structure RSt where
  s : St
  locked : Bool
  ov : Bool
deriving Repr, DecidableEq

def stepR (env : Bool) (x : RSt) (e : Ev) : RSt :=
  let s := stepO x.s e
  let ov := if readsAt x.s.isActive s.isActive then env else x.ov
  ⟨s, lockOn ov s.isActive, ov⟩

def runR (env : Bool) (es : List Ev) : RSt := es.foldl (stepR env) ⟨rest, false, false⟩

def readsR (env : Bool) : RSt → List Ev → List Bool
  | _, [] => []
  | x, e :: es =>
    let y := stepR env x e
    readsAt x.s.isActive y.s.isActive :: readsR env y es

theorem foldl_stepR (env : Bool) (es : List Ev) (x : RSt) (hl : x.locked = lockOn env x.s.isActive)
    (ho : x.s.isActive = true → x.ov = env) :
    (es.foldl (stepR env) x).s = es.foldl stepO x.s ∧
      (es.foldl (stepR env) x).locked = lockOn env (es.foldl (stepR env) x).s.isActive ∧
      ((es.foldl (stepR env) x).s.isActive = true → (es.foldl (stepR env) x).ov = env) := by
  induction es generalizing x with
  | nil => exact ⟨rfl, hl, ho⟩
  | cons e es ih =>
    have hs : ((stepO x.s e).isActive = true → (if readsAt x.s.isActive (stepO x.s e).isActive then env else x.ov) = env) := by
      intro ha
      cases hx : x.s.isActive
      · simp [readsAt, ha]
      · simp [readsAt, ho hx]
    refine ih (stepR env x e) ?_ hs
    show lockOn (if readsAt x.s.isActive (stepO x.s e).isActive then env else x.ov) (stepO x.s e).isActive =
      lockOn env (stepO x.s e).isActive
    by_cases ha : (stepO x.s e).isActive = true
    · rw [hs ha]
    · simp [lockOn, ha]

theorem runR_eq (env : Bool) (es : List Ev) :
    (runR env es).s = (runL env es).s ∧ (runR env es).locked = (runL env es).locked := by
  have h : (0 : Rat) < activeCut := by
    rw [activeCut, Rat.div_def, Rat.one_mul]; exact Rat.inv_pos.2 (by decide)
  have hr : rest.isActive = false := by simp [St.isActive, active, rest, Rat.not_lt.2 (Rat.le_of_lt h)]
  obtain ⟨h1, h2, -⟩ := foldl_stepR env es ⟨rest, false, false⟩ (by simp [lockOn, hr]) (by simp [hr])
  refine ⟨by rw [runR, h1, runL_s]; rfl, ?_⟩
  rw [runR, h2, runL_locked, h1]; rfl

theorem reads_iff (was now : Bool) : readsAt was now = true ↔ was = false ∧ now = true := by
  cases was <;> cases now <;> simp [readsAt]

def lockAllowed (hoverNone : Bool) : Bool := !hoverNone

def engage (hoverNone overlay : Bool) : Bool := lockAllowed hoverNone && overlay

theorem engage_touch (overlay : Bool) : engage true overlay = false := by
  cases overlay <;> rfl

theorem engage_classic (hoverNone : Bool) : engage hoverNone false = false := by
  cases hoverNone <;> rfl

theorem engage_on : engage false true = true := rfl

def hoverNoneOf (read : Option Bool) : Bool := read.getD true

theorem engage_unread (overlay : Bool) : engage (hoverNoneOf none) overlay = false := engage_touch overlay

theorem engage_read_touch (overlay : Bool) : engage (hoverNoneOf (some true)) overlay = false := engage_touch overlay

theorem engage_off_writes (hoverNone overlay : Bool) (h : engage hoverNone overlay = false) (es : List Ev) :
    ∀ w ∈ writesL (engage hoverNone overlay) ⟨rest, false⟩ es, w = none := by
  rw [h]; exact classic_writes _ es rfl

#guard engage false true && !engage true true && !engage false false && !engage true false
#guard engage (hoverNoneOf (some false)) true && !engage (hoverNoneOf none) true &&
  !engage (hoverNoneOf (some true)) true

/-- One frame of a span: the delta of a gesture in flight on the async scroller, and whether the engine drops it on a
root that is not user-scrollable (`ScrollTree::ScrollBy`, `property_tree.cc:2471-2480`@f842f52;
`ScrollingTreeScrollingNode::canHandleWheelEvent`, `ScrollingTreeScrollingNode.cpp:233-236`@862f17d). -/
structure Gest where
  delta : Int
  gated : Bool
deriving Repr, DecidableEq

def applied (lock : Bool) (k i : Nat) (g : Gest) : Int := if lock && decide (k ≤ i) && g.gated then 0 else g.delta

def span (lock : Bool) (k : Nat) (p : Int) : Nat → Int → List Gest → List (Int × Int × Bool)
  | _, _, [] => []
  | i, y, g :: gs =>
    let z := y + applied lock k i g
    let y' := if z = p then z else p
    (z, y', decide (z ≠ p)) :: span lock k p (i + 1) y' gs

def forced (r : List (Int × Int × Bool)) : Nat := r.countP (·.2.2)

theorem span_seen (lock : Bool) (k : Nat) (p : Int) (i : Nat) (y : Int) (gs : List Gest) :
    (span lock k p i y gs).map (·.2.1) = List.replicate gs.length p := by
  induction gs generalizing i y with
  | nil => rfl
  | cons g gs ih =>
    simp only [span, List.map_cons, ih, List.length_cons, List.replicate_succ, List.cons.injEq, and_true]
    split <;> simp_all

theorem seen_eq (k : Nat) (p : Int) (i : Nat) (y : Int) (gs : List Gest) :
    (span true k p i y gs).map (·.2.1) = (span false k p i y gs).map (·.2.1) := by
  rw [span_seen, span_seen]

theorem span_tail (lock : Bool) (k : Nat) (p : Int) (i : Nat) (y : Int) (g : Gest) (gs : List Gest) :
    span lock k p i y (g :: gs) = (y + applied lock k i g, p, decide (y + applied lock k i g ≠ p)) ::
      span lock k p (i + 1) p gs := by
  simp only [span]
  split <;> simp_all

theorem forced_le (k : Nat) (p : Int) (i : Nat) (gs : List Gest) :
    forced (span true k p i p gs) ≤ forced (span false k p i p gs) := by
  induction gs generalizing i with
  | nil => simp [span, forced]
  | cons g gs ih =>
    rw [span_tail, span_tail]
    simp only [forced, List.countP_cons] at ih ⊢
    have := ih (i + 1)
    have ha : applied true k i g = 0 ∨ applied true k i g = applied false k i g := by
      unfold applied; split <;> simp
    rcases ha with ha | ha <;> by_cases h2 : p + applied false k i g = p <;> simp [ha, h2] <;> omega

theorem forced_lt (k : Nat) (p : Int) (i : Nat) (gs : List Gest) (hk : k ≤ i)
    (h : ∃ g ∈ gs, g.gated = true ∧ g.delta ≠ 0) :
    forced (span true k p i p gs) < forced (span false k p i p gs) := by
  induction gs generalizing i with
  | nil => simp at h
  | cons g gs ih =>
    rw [span_tail, span_tail]
    simp only [forced, List.countP_cons] at ih ⊢
    have hle := forced_le k p (i + 1) gs
    simp only [forced] at hle
    obtain ⟨g0, hg0, hgt, hd⟩ := h
    rcases List.mem_cons.1 hg0 with rfl | hg
    · have h1 : applied true k i g0 = 0 := by simp [applied, hk, hgt]
      have h2 : applied false k i g0 = g0.delta := by simp [applied]
      have h3 : p + g0.delta ≠ p := by omega
      simp [h1, h2, h3]
      omega
    · have := ih (i + 1) (by omega) ⟨g0, hg, hgt, hd⟩
      have ha : applied true k i g = 0 ∨ applied true k i g = applied false k i g := by
        unfold applied; split <;> simp
      rcases ha with ha | ha <;> by_cases h2 : p + applied false k i g = p <;> simp [ha, h2] <;> omega

theorem ungated_eq (k : Nat) (p : Int) (i : Nat) (y : Int) (gs : List Gest) (h : ∀ g ∈ gs, g.gated = false) :
    span true k p i y gs = span false k p i y gs := by
  induction gs generalizing i y with
  | nil => rfl
  | cons g gs ih =>
    have hg := h g (by simp)
    simp only [span, applied, hg, Bool.and_false, Bool.false_eq_true, ite_false]
    rw [ih _ _ fun g' hg' => h g' (by simp [hg'])]

theorem still_eq (lock : Bool) (k : Nat) (p : Int) (i : Nat) (gs : List Gest) (h : ∀ g ∈ gs, g.delta = 0) :
    span lock k p i p gs = List.replicate gs.length (p, p, false) := by
  induction gs generalizing i with
  | nil => rfl
  | cons g gs ih =>
    have hg := h g (by simp)
    rw [span_tail, ih _ fun g' hg' => h g' (by simp [hg'])]
    have : applied lock k i g = 0 := by unfold applied; split <;> simp [hg]
    simp [this, List.replicate_succ]

theorem shown_lock (k : Nat) (p : Int) (i : Nat) (gs : List Gest) (hk : k ≤ i) (h : ∀ g ∈ gs, g.gated = true) :
    ∀ r ∈ span true k p i p gs, r.1 = p ∧ r.2.2 = false := by
  induction gs generalizing i with
  | nil => simp [span]
  | cons g gs ih =>
    rw [span_tail]
    intro r hr
    rcases List.mem_cons.1 hr with rfl | hr
    · simp [applied, hk, h g (by simp)]
    · exact ih (i + 1) (by omega) (fun g' hg' => h g' (by simp [hg'])) r hr

theorem forced_still (k : Nat) (p : Int) (gs : List Gest) (h : ∀ g ∈ gs, g.delta = 0) :
    forced (span true k p 0 p gs) = forced (span false k p 0 p gs) := by
  rw [still_eq true k p 0 gs h, still_eq false k p 0 gs h]

theorem forced_ungated (k : Nat) (p : Int) (gs : List Gest) (h : ∀ g ∈ gs, g.gated = false) :
    forced (span true k p 0 p gs) = forced (span false k p 0 p gs) := by
  rw [ungated_eq k p 0 p gs h]

def rootWrites (ov : Bool) (es : List Ev) : Nat := (writesL ov ⟨rest, false⟩ es).countP Option.isSome

def stylePasses (lock : Bool) : Nat := if lock then 2 else 0

theorem style_passes : stylePasses true = stylePasses false + 2 := rfl

theorem rootWrites_classic (es : List Ev) : rootWrites false es = 0 := by
  rw [rootWrites, List.countP_eq_zero]
  intro w hw
  simp [classic_writes _ es rfl w hw]

#guard forced (span true 1 1200 0 1200 [⟨12, true⟩, ⟨10, true⟩, ⟨8, true⟩]) == 1
#guard forced (span false 1 1200 0 1200 [⟨12, true⟩, ⟨10, true⟩, ⟨8, true⟩]) == 3
#guard span true 1 1200 0 1200 [⟨12, false⟩, ⟨10, false⟩] == span false 1 1200 0 1200 [⟨12, false⟩, ⟨10, false⟩]

/-- The width the root's vertical scrollbar takes from the layout viewport, `w` the classic scrollbar's thickness
(`LocalFrameView::scrollbarGutterWidth`, `LocalFrameView.cpp:7322-7333`@862f17d;
`LayoutBox::HasScrollbarGutters`, `layout_box.cc:1474-1494`@f842f52). -/
def gutter (classic hidden stable : Bool) (w : Nat) : Nat := if classic && (!hidden || stable) then w else 0

theorem gutter_same (hn c a : Bool) (w : Nat) : gutter c (lockOn (engage hn (!c)) a) false w = gutter c false false w := by
  cases hn <;> cases c <;> cases a <;> rfl

theorem gutter_shift (w : Nat) (hw : 0 < w) : gutter true true false w ≠ gutter true false false w := by
  simp [gutter]; omega

theorem gutter_stable (w : Nat) : gutter true true true w = gutter true false false w := rfl

#guard gutter true false false 15 == 15 && gutter true true false 15 == 0 && gutter false false false 15 == 0

theorem lock_vis (vp : Fw.Site.Breakpoints.Env → Rect) (cl : Fw.Site.Breakpoints.Env → Bool) (w k : Nat) (p : Int)
    (S : Fw.Site.Breakpoints.Env → St → Int → Nat → Scene) :
    VisSame E vp
      (fun env (h : List Ev × List Gest × Nat) =>
        S env (runO rest h.1) (((span false k p 0 p h.2.1).map (·.2.1)).getD h.2.2 p) (gutter (cl env) false false w))
      (fun env h => S env (runL (engage (decide (env.hover = .none)) (!cl env)) h.1).s
        (((span (engage (decide (env.hover = .none)) (!cl env)) k p 0 p h.2.1).map (·.2.1)).getD h.2.2 p)
        (gutter (cl env) (runL (engage (decide (env.hover = .none)) (!cl env)) h.1).locked false w)) :=
  visSame_of_eq vp fun env h => by
    rw [runL_s, runL_locked, gutter_same, span_seen, span_seen]

def lockCases : List (String × Bool × List Ev) :=
  [("open-close", true, [.push 1 false 0, .tick 17, .tick 340, .tick 680, .tick 697, .push 0 false 1000, .tick 1017,
      .tick 1700, .tick 1717]),
    ("open-close-classic", false, [.push 1 false 0, .tick 17, .tick 340, .tick 680, .push 0 false 1000, .tick 1017,
      .tick 1700]),
    ("reduced", true, [.push 1 true 0, .push 0 true 50]),
    ("retarget", true, [.push 1 false 0, .tick 100, .push 0 false 150, .tick 300, .tick 830, .tick 847])]

def evFields : Ev → List (String × Lean.Json)
  | .push g rm n => [("ev", .str "push"), ("goal", ratJ g), ("reduced", .bool rm), ("t", ratJ n)]
  | .tick R => [("ev", .str "tick"), ("t", ratJ R)]

def writeJ : Option Bool → Lean.Json
  | none => .null
  | some b => .bool b

def lockRows (c : String) (ov : Bool) (es : List Ev) : List String :=
  ((List.range es.length).zip (es.zip ((writesL ov ⟨rest, false⟩ es).zip (readsR ov ⟨rest, false, false⟩ es)))).map
    fun (i, e, w, r) =>
    let x := runL ov (es.take (i + 1))
    (Lean.Json.mkObj ([("kind", .str "lock"), ("case", .str c), ("overlay", .bool ov), ("i", .num (i : Int)),
      ("active", .bool x.s.isActive), ("locked", .bool x.locked), ("write", writeJ w), ("read", .bool r)] ++
      evFields e)).compress

def spanCases : List (String × Nat × Int × List Gest) :=
  [("still", 1, 1200, List.replicate 4 ⟨0, true⟩),
    ("trackpad-in-flight", 1, 1200, [⟨12, true⟩, ⟨10, true⟩, ⟨8, true⟩, ⟨5, true⟩, ⟨2, true⟩]),
    ("ios-pan-in-flight", 1, 1200, [⟨12, false⟩, ⟨10, false⟩, ⟨8, false⟩, ⟨5, false⟩, ⟨2, false⟩]),
    ("mixed", 1, 1200, [⟨6, true⟩, ⟨0, true⟩, ⟨-4, true⟩, ⟨3, false⟩])]

def spanRows (c : String) (k : Nat) (p : Int) (gs : List Gest) (lock : Bool) : List String :=
  ((List.range gs.length).zip (gs.zip (span lock k p 0 p gs))).map fun (i, g, z, y, f) =>
    (Lean.Json.mkObj [("kind", .str "span"), ("case", .str c), ("lock", .bool lock), ("k", .num (k : Int)),
      ("p", .num p), ("i", .num (i : Int)), ("delta", .num g.delta), ("gated", .bool g.gated), ("shown", .num z),
      ("seen", .num y), ("scrollTo", .bool f)]).compress

def overlayRows : List String :=
  ([(1280, 1280), (1280, 1265), (390, 390), (390, 393), (641, 626)] : List (Int × Int)).map fun (a, b) =>
    (Lean.Json.mkObj [("kind", .str "overlay"), ("innerWidth", .num a), ("clientWidth", .num b),
      ("overlay", .bool (overlayOf a b))]).compress

def engageRows : List String :=
  ([some false, some true, none] : List (Option Bool)).flatMap fun r => [false, true].map fun ov =>
    (Lean.Json.mkObj [("kind", .str "engage"), ("hoverNone", r.elim .null .bool), ("overlay", .bool ov),
      ("allowed", .bool (lockAllowed (hoverNoneOf r))), ("engage", .bool (engage (hoverNoneOf r) ov))]).compress

def lockJsonl : String :=
  String.join (overlayRows.map (· ++ "\n")) ++ String.join (engageRows.map (· ++ "\n")) ++
    String.join (lockCases.flatMap fun (c, ov, es) => (lockRows c ov es).map (· ++ "\n")) ++
    String.join (spanCases.flatMap fun (c, k, p, gs) => ([true, false].flatMap (spanRows c k p gs)).map (· ++ "\n"))

#guard lockCases.all fun (_, ov, es) => (runL ov es).s == runO rest es

#guard lockCases.all fun (_, ov, es) =>
  (es.zip (readsR ov ⟨rest, false, false⟩ es)).all fun (e, r) => match e with | .tick _ => !r | .push .. => true

#guard (lockCases.map fun (_, ov, es) => ((readsR ov ⟨rest, false, false⟩ es).countP id, rootWrites ov es)) ==
  [(1, 2), (1, 0), (1, 2), (1, 2)]

#guard lockJsonl == include_str "../../../packages/contracts/golden/parts/morph-tween-scroll-lock.jsonl"

section WidthTail

def closeAt (T : Rat) : Rat := 1 - ease (T / duration)

def crossMs : Rat := 612

theorem closeAt_cross : closeAt crossMs = activeCut := by
  have h : min 1 (max 0 ((612 : Rat) / 680)) = 612 / 680 := by grind
  unfold closeAt ease clamp01 crossMs duration activeCut; rw [h]; grind

theorem cube_lt (a b : Rat) (hb : 0 ≤ b) (h : b < a) : b * b * b < a * a * a := by
  have ha : 0 < a := by grind
  have h1 : 0 < a - b := by grind
  have h2 : 0 < a * a := Rat.mul_pos ha ha
  have h3 : 0 ≤ a * b := Rat.mul_nonneg (by grind) hb
  have h4 : 0 ≤ b * b := Rat.mul_nonneg hb hb
  have h5 : 0 < (a - b) * (a * a + a * b + b * b) := Rat.mul_pos h1 (by grind)
  grind

theorem closeAt_eq (T : Rat) (h0 : 0 ≤ T) (h1 : T ≤ duration) :
    closeAt T = (1 - T / duration) * (1 - T / duration) * (1 - T / duration) := by
  have hd : T / duration = T * (1 / 680) := div_dur T
  have hc : clamp01 (T / duration) = T / duration := by unfold clamp01 duration at *; grind
  unfold closeAt ease; rw [hc]; grind

theorem closeAt_strict (T T' : Rat) (h0 : 0 ≤ T) (h : T < T') (h1 : T' ≤ duration) : closeAt T' < closeAt T := by
  rw [closeAt_eq T h0 (by grind), closeAt_eq T' (by grind) h1]
  have hd : ∀ e : Rat, e / duration = e * (1 / 680) := div_dur
  apply cube_lt
  · rw [hd]; unfold duration at h1; grind
  · rw [hd, hd]; grind

theorem closeAt_inj (T T' : Rat) (h0 : 0 ≤ T) (h1 : T ≤ duration) (h0' : 0 ≤ T') (h1' : T' ≤ duration)
    (h : closeAt T = closeAt T') : T = T' := by
  rcases (show T < T' ∨ T = T' ∨ T' < T by grind) with hl | he | hg
  · have := closeAt_strict T T' h0 hl h1'; grind
  · exact he
  · have := closeAt_strict T' T h0' hg h1; grind

theorem closeAt_after (R : Rat) (h : crossMs ≤ R) : closeAt R ≤ activeCut := by
  rw [← closeAt_cross]
  unfold closeAt
  have := ease_mono (crossMs / duration) (R / duration) (by
    rw [div_dur, div_dur]; exact Rat.mul_le_mul_of_nonneg_right h (by grind))
  grind

theorem morphing_iff (T : Rat) (h0 : 0 ≤ T) : activeCut < closeAt T ↔ T < crossMs := by
  constructor
  · intro h
    rcases (show T < crossMs ∨ T = crossMs ∨ crossMs < T by grind) with hl | he | hg
    · exact hl
    · rw [he, closeAt_cross] at h; grind
    · have := closeAt_after T (by grind); grind
  · intro h
    have := closeAt_strict T crossMs h0 h (by unfold crossMs duration; decide)
    rw [closeAt_cross] at this; exact this

/-- The jump of the nav width when a `width` transition starts, from the base value `before` to `after`.
The engines start it from the before-change style, the base style of the previous style change event without script
animations (Chromium `css_animations.cc:3214-3215,3242-3293`@f842f52; WebKit `Styleable.cpp:604-617`@862f17d and
`StyleTreeResolver.cpp:894-898`@862f17d), to the after-change base style (`Styleable.cpp:624-632`@862f17d). -/
def tailPx (v : Nav.Vp) (hp : Bool) (before after : Rat) : Rat := Nav.navWidth v hp before - Nav.navWidth v hp after

theorem tailPx_eq (v : Nav.Vp) (hp : Bool) (b a : Rat) : tailPx v hp b a = (Nav.panelW v - Nav.pillW v) * (b - a) := by
  unfold tailPx Nav.navWidth; grind

theorem tail_orig_pos (v : Nav.Vp) (hp : Bool) (prev R : Rat) (hD : Nav.pillW v < Nav.panelW v) (h0 : 0 ≤ prev)
    (hl : prev < crossMs) (hR : crossMs ≤ R) : 0 < tailPx v hp (closeAt prev) (closeAt R) := by
  rw [tailPx_eq]
  have h1 := (morphing_iff prev h0).mpr hl
  have h2 := closeAt_after R hR
  exact Rat.mul_pos (by grind) (by grind)

theorem tail_zero_of_base_still (v : Nav.Vp) (hp : Bool) (before after : Rat) (h : before = after) :
    tailPx v hp before after = 0 := by
  subst h; unfold tailPx; grind

theorem tail_not_view (v : Nav.Vp) (hp : Bool) (hD : Nav.pillW v < Nav.panelW v) :
    tailPx v hp (closeAt 500) (closeAt crossMs) ≠ tailPx v hp (closeAt 600) (closeAt crossMs) := by
  rw [tailPx_eq, tailPx_eq]
  intro h
  have hs := closeAt_strict 500 600 (by decide) (by decide) (by unfold duration; decide)
  have hpos : 0 < Nav.panelW v - Nav.pillW v := by grind
  have := Rat.mul_lt_mul_of_pos_left (show closeAt 600 - closeAt crossMs < closeAt 500 - closeAt crossMs by grind) hpos
  grind

def tailWindow : Rat := 100

def baseB (f t : Rat) : Bool := decide (t < f) && markerB f t activeCut

def baseDelay (dl : Rat → Rat → Rat → Rat) (G f t : Rat) : Rat := max 0 (dl f t activeCut - G)

/-- The window writes the base `--morph` on frame `T`: from its delay until the animation ends. The writes after the
flip keep the original's per-frame width retargets (WebKit `Styleable.cpp:705-756`@862f17d; Chromium
`css_animations.cc:2703-2716,2861-2882`@f842f52). -/
def baseW (dl : Rat → Rat → Rat → Rat) (G : Rat) (w : VSt) (T : Rat) : Bool :=
  match w.anim with
  | none => false
  | some a => baseB a.f a.t && decide (a.st + baseDelay dl G a.f a.t ≤ T) && decide (T < a.st + duration)

theorem base_hits (P : WaapiPremises) (dl : Rat → Rat → Rat → Rat) (hd : DlSound dl) (G : Rat) (w : VSt) (a : Anim)
    (hw : w.anim = some a) (hb : baseB a.f a.t = true) (T R : Rat) (hR : reach a.f a.t activeCut (valA P a R))
    (hst : a.st < R) (h0 : a.st ≤ T) (hT : R - G ≤ T) (hend : T < a.st + duration) : baseW dl G w T = true := by
  have hdl := hd a.f a.t activeCut (R - a.st) (by grind) (by rw [← valA_path]; exact hR)
  have hm : max 0 (dl a.f a.t activeCut - G) ≤ T - a.st := by
    rw [Rat.max_def]; split <;> grind
  unfold baseW baseDelay
  simp only [hw, hb, Bool.true_and, Bool.and_eq_true, decide_eq_true_eq]
  exact ⟨by grind, hend⟩

theorem tail_eq_of_base (P : WaapiPremises) (v : Nav.Vp) (hp : Bool) (es es' : List Ev) (T R l l' : Rat)
    (h : monoB l (es ++ [.tick T]) = true) (h' : monoB l' (es' ++ [.tick R]) = true) :
    tailPx v hp (valV P (runV P initV es) (P.tl T)) (valV P (runV P initV es') (P.tl R)) =
      tailPx v hp (runO rest (es ++ [.tick T])).value (runO rest (es' ++ [.tick R])).value := by
  rw [waapi_frame_eq P es T l h, waapi_frame_eq P es' R l' h']

theorem tail_miss_le (v : Nav.Vp) (hp : Bool) (m : Rat) (hD : Nav.pillW v ≤ Nav.panelW v) (h0 : 0 ≤ m)
    (h1 : m ≤ activeCut) :
    -((Nav.panelW v - Nav.pillW v) * activeCut) ≤ tailPx v hp 0 m ∧ tailPx v hp 0 m ≤ 0 := by
  rw [tailPx_eq]
  have hD' : 0 ≤ Nav.panelW v - Nav.pillW v := by grind
  have := Rat.mul_le_mul_of_nonneg_left h1 hD'
  have := Rat.mul_nonneg hD' h0
  constructor <;> grind

theorem hit_iff_mP (dl : Rat → Rat → Rat → Rat) (G : Rat) (w : VSt) (a : Anim) (hw : w.anim = some a) (hf : a.f = 1)
    (ht : a.t = 0) (hb : baseB 1 0 = true) (hbd : baseDelay dl G 1 0 ≤ duration) (T : Rat) (h0 : a.st ≤ T)
    (hend : T < a.st + duration) :
    baseW dl G w T = true ↔ closeAt (T - a.st) ≤ closeAt (baseDelay dl G 1 0) := by
  have hbd0 : 0 ≤ baseDelay dl G 1 0 := by unfold baseDelay; rw [Rat.max_def]; split <;> grind
  unfold baseW
  simp only [hw, hf, ht, hb, Bool.true_and, Bool.and_eq_true, decide_eq_true_eq]
  constructor
  · intro ⟨h1, _⟩
    rcases (show baseDelay dl G 1 0 < T - a.st ∨ baseDelay dl G 1 0 = T - a.st by grind) with hl | he
    · exact Rat.le_of_lt (closeAt_strict _ _ hbd0 hl (by unfold duration at *; grind))
    · rw [he]; exact Rat.le_refl
  · intro h
    refine ⟨?_, hend⟩
    rcases (show T - a.st < baseDelay dl G 1 0 ∨ baseDelay dl G 1 0 ≤ T - a.st by grind) with hl | hg
    · have := closeAt_strict _ _ (by grind) hl hbd; grind
    · grind

theorem miss_look_ge (v : Nav.Vp) (hp : Bool) (dl : Rat → Rat → Rat → Rat) (G st P R c : Rat)
    (hD : Nav.pillW v ≤ Nav.panelW v) (hbd : baseDelay dl G 1 0 ≤ duration) (h0 : st ≤ P)
    (hP : P < st + baseDelay dl G 1 0) (hR : st + crossMs ≤ R) (hc : 0 ≤ c) :
    (Nav.panelW v - Nav.pillW v) * (closeAt (baseDelay dl G 1 0) - activeCut) ≤
      tailPx v hp (closeAt (P - st)) (closeAt (R - st)) - tailPx v hp 0 c := by
  rw [tailPx_eq, tailPx_eq]
  have h1 := closeAt_strict (P - st) (baseDelay dl G 1 0) (by grind) (by grind) hbd
  have h2 := closeAt_after (R - st) (by grind)
  have hD' : 0 ≤ Nav.panelW v - Nav.pillW v := by grind
  have := Rat.mul_le_mul_of_nonneg_left
    (show closeAt (baseDelay dl G 1 0) - activeCut ≤ closeAt (P - st) - closeAt (R - st) - (0 - c) by grind) hD'
  grind

def missFloor (v : Nav.Vp) : Rat :=
  (Nav.panelW v - Nav.pillW v) * (closeAt (baseDelay (dlLo delayDepth) tailWindow 1 0) - activeCut)

#guard baseDelay (dlLo delayDepth) tailWindow 1 0 ≤ duration
#guard let c := closeAt (baseDelay (dlLo delayDepth) tailWindow 1 0); 1507 / 100000 < c && c < 1509 / 100000
#guard 360 / 100 < missFloor ⟨1280, 800⟩ && missFloor ⟨1280, 800⟩ < 361 / 100
#guard 11 / 100 < missFloor ⟨390, 844⟩ && missFloor ⟨390, 844⟩ < 12 / 100

structure Cost where
  frames : Nat
  orig : Nat
  fix : Nat
  tail : Nat
deriving Repr, DecidableEq

def costStep (dl : Rat → Rat → Rat → Rat) (G : Rat) : St × VSt × Bool × Cost → Ev → St × VSt × Bool × Cost
  | (s, w, d, c), .push g rm n =>
    (stepO s (.push g rm n), stepV attrP w (.push g rm n), d && decide (w.target = g ∧ w.aim = g), c)
  | (s, w, d, c), .tick R =>
    let T := attrP.tl R
    let fin := finishW w T && !d
    let fx := fin || pollW dl w T
    (stepO s (.tick R), stepV attrP w (.tick R), d || fin,
      ⟨c.frames + 1, c.orig + (if s.pending then 1 else 0), c.fix + (if fx then 1 else 0),
        c.tail + (if fx || baseW dl G w T then 1 else 0)⟩)

def dlTs (f t θ : Rat) : Rat := if reach f t θ f then 0 else max 0 (dlLo delayDepth f t θ - 1)

theorem dlTs_sound : DlSound dlTs := by
  intro f t θ e he hr
  have := dlLo_sound delayDepth f t θ e he hr
  unfold dlTs
  split
  · grind
  · rw [Rat.max_def]; split <;> grind

def cost (G : Rat) (s : St) (w : VSt) (es : List Ev) : Cost :=
  (es.foldl (costStep dlTs G) (s, w, false, ⟨0, 0, 0, 0⟩)).2.2.2

def atOne : St × VSt :=
  let es := [Ev.push 1 false (-1000), .tick 0]
  (runO rest es, runV attrP initV es)

def closeEvs (g : Rat) : List Ev :=
  .push 0 false 0 :: (List.range ((duration / g).ceil.toNat)).map fun k => .tick (g * ((k + 1 : Nat) : Rat))

def closeCost (G g : Rat) : Cost := cost G atOne.1 atOne.2 (closeEvs g)

inductive TailArm where
  | model
  | lookChange
deriving DecidableEq, Repr

def tailArm (c : Cost) : TailArm := if c.tail - c.fix < c.orig - c.fix then .model else .lookChange

theorem tailArm_model (c : Cost) (h : c.tail - c.fix < c.orig - c.fix) : tailArm c = .model := by
  unfold tailArm; simp [h]

theorem tailArm_look (c : Cost) (h : c.orig - c.fix ≤ c.tail - c.fix) : tailArm c = .lookChange := by
  unfold tailArm; simp; omega

def displayGaps : List Rat := [50 / 3, 25 / 3]

def tailDecision (G : Rat) : TailArm :=
  if displayGaps.all fun g => tailArm (closeCost G g) == .model then .model else .lookChange

def costGaps : List Rat := [50 / 3, 25 / 3, 22, 45, 100, 300]

def TailArm.name : TailArm → String
  | .model => "model"
  | .lookChange => "lookChange"

def costFields (c : Cost) : List (String × Lean.Json) :=
  [("frames", .num c.frames), ("orig", .num c.orig), ("fix", .num c.fix), ("tail", .num c.tail)]

def tailJsonl (_ : Unit) : String :=
  let rows := [Lean.Json.mkObj [("kind", .str "tailWindow"), ("ms", ratJ tailWindow)]] ++
    markerFroms.flatMap (fun f => [0, 1].map fun t => Lean.Json.mkObj [("kind", .str "baseWindow"), ("from", ratJ f),
      ("to", ratJ t), ("window", .bool (baseB f t)),
      ("delay", if baseB f t then ratJ (baseDelay (dlLo delayDepth) tailWindow f t) else .null)]) ++
    attrCases.map (fun (n, es) => Lean.Json.mkObj ([("kind", .str "scriptFrames"), ("case", .str n)] ++
      costFields (cost tailWindow rest initV es))) ++
    costGaps.map fun g => let c := closeCost tailWindow g
      Lean.Json.mkObj ([("kind", .str "closeCost"), ("gap", ratJ g)] ++ costFields c ++
        [("arm", .str (tailArm c).name)])
  String.join (rows.map fun r => r.compress ++ "\n")

#guard tailDecision tailWindow == .model
#guard closeCost tailWindow (50 / 3) == ⟨41, 41, 8, 17⟩ && closeCost tailWindow (25 / 3) == ⟨82, 82, 8, 27⟩
#guard closeCost tailWindow 22 == ⟨31, 31, 7, 13⟩ && tailArm (closeCost tailWindow 22) == .model
#guard closeCost tailWindow 45 == ⟨16, 16, 7, 10⟩ && tailArm (closeCost tailWindow 45) == .model
#guard closeCost tailWindow 100 == ⟨7, 7, 4, 5⟩ && tailArm (closeCost tailWindow 100) == .model
#guard closeCost tailWindow 300 == ⟨3, 3, 2, 3⟩ && tailArm (closeCost tailWindow 300) == .lookChange
#guard baseB 1 0 && baseB (1 / 2) 0 && !baseB 0 1 && !baseB (1 / 2000) 0 && !baseB 1 1
#guard baseDelay (dlLo delayDepth) tailWindow 1 0 < 512 && 511 < baseDelay (dlLo delayDepth) tailWindow 1 0
#guard let c : VSt := ⟨0, 0, some ⟨1, 0, 0⟩, 0, 1⟩
  baseW dlTs tailWindow c 600 && !baseW dlTs tailWindow c 500 && !baseW dlTs tailWindow c 680
#guard !baseW dlTs tailWindow ⟨1, 1, some ⟨0, 1, 0⟩, 0, 0⟩ 600 && !baseW dlTs tailWindow ⟨0, 0, none, 0, 0⟩ 600
#guard tailJsonl () == include_str "../../../packages/contracts/golden/parts/morph-tween-waapi.tail.jsonl"
#guard closeAt crossMs == activeCut && closeAt 0 == 1 && closeAt 680 == 0 && closeAt 900 == 0
#guard let t := tailPx ⟨1280, 800⟩ false (closeAt (crossMs - 50 / 3)) 0; 49 / 100 < t && t < 1 / 2
#guard let t := tailPx ⟨1440, 900⟩ false (closeAt (crossMs - 50 / 3)) 0; 79 / 100 < t && t < 4 / 5
#guard let t := tailPx ⟨390, 844⟩ false (closeAt (crossMs - 50 / 3)) 0; 0 < t && t < 1 / 50
#guard let t := tailPx ⟨1280, 800⟩ false (closeAt (crossMs - 173)) 0; 11 < t && t < 12
#guard let t := tailPx ⟨1280, 800⟩ false (closeAt (crossMs - 411)) 0; 89 < t && t < 90

end WidthTail

end Fw.Parts.MorphTweenOpt

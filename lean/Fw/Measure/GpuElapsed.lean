import Lean.Data.Json
import Fw.Parts.MorphTween

/-!
Paused-effect time of a morph state for the GPU lane: the largest 1/1000 ms grid time whose `ease` does not pass `m`.
-/
namespace Fw.Measure.GpuElapsed
open Fw.Parts.MorphTween

def steps : Nat := 680000

def past (m : Rat) (j : Nat) : Prop := (1 - m) * (steps : Rat) ^ 3 ≤ (j : Rat) ^ 3

instance (m : Rat) : DecidablePred (past m) := fun j => by unfold past; infer_instance

def least (p : Nat → Bool) : Nat → Nat → Nat
  | i, 0 => i
  | i, f + 1 => if p i then i else least p (i + 1) f

theorem least_spec (p : Nat → Bool) (f : Nat) :
    ∀ i, p (i + f) = true →
      i ≤ least p i f ∧ least p i f ≤ i + f ∧ p (least p i f) = true ∧
        ∀ j, i ≤ j → j < least p i f → p j = false := by
  induction f with
  | zero =>
    intro i h
    simp only [least, Nat.add_zero] at *
    exact ⟨Nat.le_refl _, Nat.le_refl _, h, fun j h1 h2 => absurd h2 (by omega)⟩
  | succ f ih =>
    intro i h
    unfold least
    by_cases hp : p i = true
    · simp only [hp, ↓reduceIte]
      exact ⟨Nat.le_refl _, by omega, by simp, fun j h1 h2 => absurd h2 (by omega)⟩
    · have hp' : p i = false := by simpa using hp
      have h' : p ((i + 1) + f) = true := by rwa [show i + 1 + f = i + (f + 1) by omega]
      obtain ⟨a, b, c, d⟩ := ih (i + 1) h'
      simp only [hp', Bool.false_eq_true, ↓reduceIte]
      refine ⟨by omega, by omega, c, ?_⟩
      intro j hj1 hj2
      by_cases hji : j = i
      · subst hji; exact hp'
      · exact d j (by omega) hj2

def remain (m : Rat) : Nat := least (fun j => decide (past m j)) 0 steps

def elapsedMilli (m : Rat) : Nat := steps - remain m

theorem past_steps (m : Rat) (h : 0 ≤ m) : past m steps := by
  unfold past
  have h0 : (0 : Rat) ≤ (steps : Rat) := by unfold steps; grind
  have h3 : (0 : Rat) ≤ (steps : Rat) ^ 3 := by
    rw [show (steps : Rat) ^ 3 = steps * steps * steps by grind]
    exact Rat.mul_nonneg (Rat.mul_nonneg h0 h0) h0
  have := Rat.mul_nonneg h h3
  grind

theorem remain_spec (m : Rat) (h : 0 ≤ m) :
    remain m ≤ steps ∧ past m (remain m) ∧ ∀ j, j < remain m → ¬ past m j := by
  have := least_spec (fun j => decide (past m j)) steps 0 (by simpa using past_steps m h)
  obtain ⟨_, b, c, d⟩ := this
  refine ⟨by unfold remain; omega, by simpa [remain] using c, ?_⟩
  intro j hj
  have := d j (by omega) hj
  simpa [remain] using this

theorem ease_grid (k : Nat) (hk : k ≤ steps) :
    ease ((k : Rat) / steps) = 1 - (((steps - k : Nat) : Rat) / steps) ^ 3 := by
  have hs : (0 : Rat) < steps := by unfold steps; grind
  have hkr : (k : Rat) ≤ steps := by exact_mod_cast hk
  have hk0 : (0 : Rat) ≤ k := by exact_mod_cast Nat.zero_le k
  have hmul : (k : Rat) / steps * steps = k := Rat.div_mul_cancel (by grind)
  have h0 : 0 ≤ (k : Rat) / steps := by
    refine Classical.byContradiction fun hn => ?_
    have hn' : (k : Rat) / steps < 0 := by grind
    have := Rat.mul_lt_mul_of_pos_right hn' hs
    grind
  have h1 : (k : Rat) / steps ≤ 1 := by
    refine Classical.byContradiction fun hn => ?_
    have hn' : 1 < (k : Rat) / steps := by grind
    have := Rat.mul_lt_mul_of_pos_right hn' hs
    grind
  have hc : clamp01 ((k : Rat) / steps) = (k : Rat) / steps := by unfold clamp01; grind
  have hj : (((steps - k : Nat) : Rat) / steps) = 1 - (k : Rat) / steps := by
    have e : ((steps - k : Nat) : Rat) + k = steps := by exact_mod_cast Nat.sub_add_cancel hk
    have e2 : ((steps - k : Nat) : Rat) = steps - k := by grind
    rw [e2, Rat.div_def, Rat.div_def]
    grind
  unfold ease
  rw [hc, hj]
  grind

theorem ease_le_iff (m : Rat) (k : Nat) (hk : k ≤ steps) :
    ease ((k : Rat) / steps) ≤ m ↔ past m (steps - k) := by
  have hs : (0 : Rat) < steps := by unfold steps; grind
  have h3 : (0 : Rat) < (steps : Rat) ^ 3 := by
    rw [show (steps : Rat) ^ 3 = steps * steps * steps by grind]
    exact Rat.mul_pos (Rat.mul_pos hs hs) hs
  have hq : (((steps - k : Nat) : Rat) / steps) ^ 3 * (steps : Rat) ^ 3 = ((steps - k : Nat) : Rat) ^ 3 := by
    have hmul : ((steps - k : Nat) : Rat) / steps * steps = ((steps - k : Nat) : Rat) := Rat.div_mul_cancel (by grind)
    have cube : ∀ x y : Rat, (x * y) ^ 3 = x ^ 3 * y ^ 3 := by intro x y; grind
    rw [← cube, hmul]
  rw [ease_grid k hk]
  unfold past
  constructor
  · intro h
    have h' : 1 - m ≤ (((steps - k : Nat) : Rat) / steps) ^ 3 := by grind
    have := Rat.mul_le_mul_of_nonneg_right h' (Rat.le_of_lt h3)
    grind
  · intro h
    refine Classical.byContradiction fun hn => ?_
    have h' : (((steps - k : Nat) : Rat) / steps) ^ 3 < 1 - m := by grind
    have := Rat.mul_lt_mul_of_pos_right h' h3
    grind

theorem elapsed_not_past (m : Rat) (h : 0 ≤ m) : ease ((elapsedMilli m : Rat) / steps) ≤ m := by
  obtain ⟨hle, hpast, _⟩ := remain_spec m h
  have e : steps - elapsedMilli m = remain m := by unfold elapsedMilli; omega
  have key := ease_le_iff m (elapsedMilli m) (by unfold elapsedMilli; omega)
  rw [e] at key
  exact key.mpr hpast

theorem elapsed_next_past (m : Rat) (h : 0 ≤ m) (hk : elapsedMilli m < steps) :
    m < ease (((elapsedMilli m + 1 : Nat) : Rat) / steps) := by
  obtain ⟨hle, _, hleast⟩ := remain_spec m h
  have hk1 : elapsedMilli m + 1 ≤ steps := hk
  refine Classical.byContradiction fun hc => ?_
  have hc' : ease (((elapsedMilli m + 1 : Nat) : Rat) / steps) ≤ m := by grind
  rw [ease_le_iff m _ hk1] at hc'
  have e : steps - (elapsedMilli m + 1) = remain m - 1 := by unfold elapsedMilli at *; omega
  rw [e] at hc'
  exact hleast (remain m - 1) (by unfold elapsedMilli at hk; omega) hc'

/-- Every grid time after `elapsedMilli m` (up to the end) passes `m`: the time is the largest one whose ease does not. -/
theorem elapsed_largest (m : Rat) (h : 0 ≤ m) (k : Nat) (hk : elapsedMilli m < k) (hks : k ≤ steps) :
    m < ease ((k : Rat) / steps) := by
  obtain ⟨hle, _, hleast⟩ := remain_spec m h
  refine Classical.byContradiction fun hc => ?_
  have hc' : ease ((k : Rat) / steps) ≤ m := by grind
  rw [ease_le_iff m k hks] at hc'
  have hlt : steps - k < remain m := by unfold elapsedMilli at hk; omega
  exact hleast (steps - k) hlt hc'

def elapsedMs (m : Rat) : Rat := (elapsedMilli m : Rat) / 1000


def values : List Rat := [0, 1 / 100, 1 / 10, 1 / 4, 2 / 5, 1 / 2, 3 / 4, 9 / 10, 99 / 100, 1]

def ratJson (q : Rat) : Lean.Json :=
  Lean.Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

def lines (_ : Unit) : List String :=
  values.map fun m =>
    (Lean.Json.mkObj [("fn", .str "elapsedMilli"), ("in", Lean.Json.mkObj [("m", ratJson m)]),
      ("out", .num (.fromNat (elapsedMilli m)))]).compress

def goldenText (_ : Unit) : String := String.join ((lines ()).map (· ++ "\n"))

def gen (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText () then
      IO.eprintln s!"gpu-elapsed golden: {path} is up to date ({(lines ()).length} lines)"
      return 0
    IO.eprintln s!"gpu-elapsed golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Measure.GpuElapsed

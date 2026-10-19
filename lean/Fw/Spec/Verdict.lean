import Lean.Data.Json
/-!
# The v1 A/B verdict ("better only when the ranges don't overlap, n ≥ 3")

v1 `tools/lib/ab-stats.mjs` l.34-39 as a total, decidable function, plus the theorems the loop
relies on. Values are integers in the metric's own unit (frame counts, or µs).
-/
namespace Fw.Verdict

/-- The direction of a metric: lower is better (frame counts, dt) or higher is better (fps). -/
inductive Dir where
  | lower   -- lower is better (frame counts, dt)
  | higher  -- higher is better (fps)
deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

/-- The four outcomes of an A/B comparison. -/
inductive Verdict where
  | better | worse | noise | tooFew
deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

/-- Every value of `b` is strictly below every value of `a` (for non-empty lists: max b < min a,
written without min/max).

Edge: if either list is empty, `below` is true (vacuously); a single tie `y = x`
makes it false.
-/
def below (b a : List Int) : Bool := b.all fun y => a.all fun x => decide (y < x)

#guard below [] [1, 2] && below [1] [] && below [1, 2] [3] && !below [1, 3] [3]

/-- The minimum number of runs on each side before any verdict other than `tooFew`. -/
def minRuns : Nat := 3

/-- The v1 verdict: with at least 3 runs per side, the variant is better only if every variant run
beats every control run, worse if every control run beats every variant run, noise otherwise.

With control runs `C ∈ ℤ^(*)` and variant runs `V ∈ ℤ^(*)`, first match wins.

Edge: `|·|` counts repeats, so `[5,5,5]` is 3 runs; ties give noise.
-/
def verdict (d : Dir) (ctl var : List Int) : Verdict :=
  if ctl.length < minRuns ∨ var.length < minRuns then .tooFew
  else match d with
    | .lower  => if below var ctl then .better else if below ctl var then .worse else .noise
    | .higher => if below ctl var then .better else if below var ctl then .worse else .noise

#guard verdict .lower [10, 11, 12] [9, 10, 8] == .noise
#guard verdict .lower [5, 5, 5] [4, 4, 4] == .better
#guard verdict .lower [5, 5] [4, 4, 4] == .tooFew
#guard verdict .lower [1, 2, 3] [4, 5, 6] == .worse
#guard verdict .higher [1, 2, 3] [4, 5, 6] == .better

/-- The Bool test `below` means exactly what it says. -/
theorem below_spec (b a : List Int) : below b a = true ↔ ∀ y ∈ b, ∀ x ∈ a, y < x := by
  simp [below]

/-- Soundness for lower-is-better: "better" means every variant run was strictly lower than every
control run (for higher-is-better see `better_sound_higher`).
-/
theorem better_sound {ctl var : List Int} (h : verdict .lower ctl var = .better) :
    ∀ y ∈ var, ∀ x ∈ ctl, y < x := by
  unfold verdict at h
  split at h
  · cases h
  · simp only at h
    split at h
    · exact (below_spec _ _).mp ‹_›
    · split at h <;> cases h

/-- No "better" verdict without at least 3 runs on each side, in either direction. -/
theorem better_needs_runs {d : Dir} {ctl var : List Int} (h : verdict d ctl var = .better) :
    minRuns ≤ ctl.length ∧ minRuns ≤ var.length := by
  unfold verdict at h
  split at h
  · cases h
  · omega

/-- Two non-empty lists cannot each be strictly below the other (with an empty list both tests are
vacuously true, hence the hypotheses).
-/
theorem below_antisymm {a b : List Int} (ha : a ≠ []) (hb : b ≠ [])
    (h1 : below b a = true) (h2 : below a b = true) : False := by
  rw [below_spec] at h1 h2
  obtain ⟨x, hx⟩ := List.exists_mem_of_ne_nil a ha
  obtain ⟨y, hy⟩ := List.exists_mem_of_ne_nil b hb
  have := h1 y hy x hx
  have := h2 x hx y hy
  omega

/-- Swapping control and variant turns "better" into "worse" (this direction only; worse to better
and noise to noise are not stated here).
-/
theorem swap_better {d : Dir} {ctl var : List Int} (h : verdict d ctl var = .better) :
    verdict d var ctl = .worse := by
  have hn := better_needs_runs h
  have hc : ctl ≠ [] := by intro e; simp [e, minRuns] at hn
  have hv : var ≠ [] := by intro e; simp [e, minRuns] at hn
  unfold verdict at h ⊢
  have hlen : ¬ (var.length < minRuns ∨ ctl.length < minRuns) := by omega
  simp only [hlen, ite_false]
  have hlen' : ¬ (ctl.length < minRuns ∨ var.length < minRuns) := by omega
  simp only [hlen', ite_false] at h
  cases d with
  | lower =>
    simp only at h ⊢
    split at h
    · rename_i hb
      have : below ctl var = false := by
        cases e : below ctl var
        · rfl
        · exact (below_antisymm hc hv hb e).elim
      simp [this, hb]
    · split at h <;> cases h
  | higher =>
    simp only at h ⊢
    split at h
    · rename_i hb
      have : below var ctl = false := by
        cases e : below var ctl
        · rfl
        · exact (below_antisymm hv hc hb e).elim
      simp [this, hb]
    · split at h <;> cases h

/-- Negating both lists flips which one is below. -/
theorem below_neg (a b : List Int) : below (a.map (- ·)) (b.map (- ·)) = below b a := by
  apply Bool.eq_iff_iff.mpr
  rw [below_spec, below_spec]
  simp only [List.mem_map]
  constructor
  · intro h y hy x hx
    have := h (-x) ⟨x, hx, rfl⟩ (-y) ⟨y, hy, rfl⟩
    omega
  · rintro h _ ⟨x, hx, rfl⟩ _ ⟨y, hy, rfl⟩
    have := h y hy x hx
    omega

/-- Direction duality: "higher is better" on `x` is exactly "lower is better" on `-x`. -/
theorem verdict_higher_eq_lower_neg (ctl var : List Int) :
    verdict .higher ctl var = verdict .lower (ctl.map (- ·)) (var.map (- ·)) := by
  simp only [verdict, List.length_map, below_neg]

/-- Soundness for higher-is-better: "better" means every variant run was strictly higher than every
control run (gap G7 of the Lean-to-math note).
-/
theorem better_sound_higher {ctl var : List Int} (h : verdict .higher ctl var = .better) :
    ∀ y ∈ var, ∀ x ∈ ctl, x < y := by
  rw [verdict_higher_eq_lower_neg] at h
  intro y hy x hx
  have := better_sound h (-y) (List.mem_map.mpr ⟨y, hy, rfl⟩) (-x) (List.mem_map.mpr ⟨x, hx, rfl⟩)
  omega

end Fw.Verdict

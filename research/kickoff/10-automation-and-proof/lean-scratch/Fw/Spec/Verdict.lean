import Lean.Data.Json
/-!
# The v1 A/B verdict ("better only when the ranges don't overlap, n ≥ 3")

v1 `tools/lib/ab-stats.mjs` l.34-39 as a total, decidable function, plus the theorems the loop
relies on. Values are integers in the metric's own unit (frame counts, or µs).
-/
namespace Fw.Verdict

inductive Dir where
  | lower   -- lower is better (frame counts, dt)
  | higher  -- higher is better (fps)
deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

inductive Verdict where
  | better | worse | noise | tooFew
deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

/-- Every value of `b` is strictly below every value of `a` (max b < min a, without min/max). -/
def below (b a : List Int) : Bool := b.all fun y => a.all fun x => decide (y < x)

def minRuns : Nat := 3

def verdict (d : Dir) (ctl var : List Int) : Verdict :=
  if ctl.length < minRuns ∨ var.length < minRuns then .tooFew
  else match d with
    | .lower  => if below var ctl then .better else if below ctl var then .worse else .noise
    | .higher => if below ctl var then .better else if below var ctl then .worse else .noise

theorem below_spec (b a : List Int) : below b a = true ↔ ∀ y ∈ b, ∀ x ∈ a, y < x := by
  simp [below]

/-- Soundness: "better" (lower is better) means every variant run beat every control run. -/
theorem better_sound {ctl var : List Int} (h : verdict .lower ctl var = .better) :
    ∀ y ∈ var, ∀ x ∈ ctl, y < x := by
  unfold verdict at h
  split at h
  · cases h
  · simp only at h
    split at h
    · exact (below_spec _ _).mp ‹_›
    · split at h <;> cases h

/-- No verdict without ≥ 3 runs on each side. -/
theorem better_needs_runs {d : Dir} {ctl var : List Int} (h : verdict d ctl var = .better) :
    minRuns ≤ ctl.length ∧ minRuns ≤ var.length := by
  unfold verdict at h
  split at h
  · cases h
  · omega

/-- Both sides can't be strictly below each other when both are non-empty. -/
theorem below_antisymm {a b : List Int} (ha : a ≠ []) (hb : b ≠ [])
    (h1 : below b a = true) (h2 : below a b = true) : False := by
  rw [below_spec] at h1 h2
  obtain ⟨x, hx⟩ := List.exists_mem_of_ne_nil a ha
  obtain ⟨y, hy⟩ := List.exists_mem_of_ne_nil b hb
  have := h1 y hy x hx
  have := h2 x hx y hy
  omega

/-- Symmetry: swapping control and variant turns "better" into "worse". -/
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

/-- Direction duality: "higher is better" on x is "lower is better" on -x. -/
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

theorem verdict_higher_eq_lower_neg (ctl var : List Int) :
    verdict .higher ctl var = verdict .lower (ctl.map (- ·)) (var.map (- ·)) := by
  simp only [verdict, List.length_map, below_neg]

end Fw.Verdict

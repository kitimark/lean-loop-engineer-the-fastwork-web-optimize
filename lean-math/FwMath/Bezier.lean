import Mathlib.Topology.Algebra.Ring.Real
import Fw.Parts.Bezier

/-! `Fw.Parts.Bezier` over `ℝ`: `x(s) = t` has one solution `s*` in `[0,1]`, and the Rat code's `bisect` and `ease`
are within `1 / 2^41` of `s*` and `3 / 2^41` of `y(s*)`; the Rat code enters through `Rat.cast`. -/

namespace FwMath.Bezier

open Fw.Parts.Bezier Set

/-- `coord` over `ℝ`. -/
def coordR (a b s : ℝ) : ℝ := 3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s

/-- `bx` over `ℝ`. -/
def bxR (c : Bez) (s : ℝ) : ℝ := coordR c.x1 c.x2 s

/-- `by'` over `ℝ`. -/
def byR (c : Bez) (s : ℝ) : ℝ := coordR c.y1 c.y2 s

/-- The Rat code's `coord`, cast to `ℝ`, is `coordR` at the cast arguments. -/
theorem coord_cast (a b s : ℚ) : ((coord a b s : ℚ) : ℝ) = coordR a b s := by
  simp only [coord, coordR]; push_cast; ring

/-- `bx` cast to `ℝ` is `bxR`. -/
theorem bx_cast (c : Bez) (s : ℚ) : ((bx c s : ℚ) : ℝ) = bxR c s := coord_cast _ _ _

/-- `by'` cast to `ℝ` is `byR`. -/
theorem by_cast (c : Bez) (s : ℚ) : ((by' c s : ℚ) : ℝ) = byR c s := coord_cast _ _ _

/-- For `0 < t < 1`, the Rat code's `ease`, cast to `ℝ`, is `byR` at the cast `bisect` result. -/
theorem ease_cast (c : Bez) (t : ℚ) (ht0 : 0 < t) (ht1 : t < 1) :
    ((ease c t : ℚ) : ℝ) = byR c (bisect c t steps 0 1) := by
  have n0 : ¬ t ≤ 0 := not_le.2 ht0
  have n1 : ¬ 1 ≤ t := not_le.2 ht1
  simp only [ease, n0, n1, ite_false, by_cast]

/-- The difference quotient of `coordR a b` between `u` and `v`. -/
def slopeR (a b u v : ℝ) : ℝ :=
  (1 - a) * ((1 - b) * (u * u + u * v + v * v)
      + b * (2 * (u * (1 - u)) + 2 * (v * (1 - v)) + u * (1 - v) + v * (1 - u)))
    + a * ((1 - b) * (3 * (u + v - 1) ^ 2 + (v - u) ^ 2)
      + b * ((1 - u) ^ 2 + (1 - u) * (1 - v) + (1 - v) ^ 2))

theorem coordR_sub (a b u v : ℝ) : coordR a b v - coordR a b u = (v - u) * slopeR a b u v := by
  simp only [coordR, slopeR]; ring

theorem mix_pos {x y w : ℝ} (hx : 0 < x) (hy : 0 < y) (h0 : 0 ≤ w) (h1 : w ≤ 1) : 0 < (1 - w) * x + w * y := by
  rcases h1.lt_or_eq with h | rfl
  · nlinarith [mul_pos (sub_pos.2 h) hx, mul_nonneg h0 hy.le]
  · simpa

theorem mix_mem {x y w : ℝ} (hx : x ∈ Icc (0 : ℝ) 3) (hy : y ∈ Icc (0 : ℝ) 3) (h0 : 0 ≤ w) (h1 : w ≤ 1) :
    (1 - w) * x + w * y ∈ Icc (0 : ℝ) 3 := by
  obtain ⟨hx0, hx3⟩ := hx
  obtain ⟨hy0, hy3⟩ := hy
  constructor <;> nlinarith [mul_nonneg (sub_nonneg.2 h1) hx0, mul_nonneg h0 hy0,
    mul_nonneg (sub_nonneg.2 h1) (sub_nonneg.2 hx3), mul_nonneg h0 (sub_nonneg.2 hy3)]

theorem slopeR_pos {a b u v : ℝ} (ha0 : 0 ≤ a) (ha1 : a ≤ 1) (hb0 : 0 ≤ b) (hb1 : b ≤ 1)
    (hu : 0 ≤ u) (huv : u < v) (hv : v ≤ 1) : 0 < slopeR a b u v := by
  have v0 : 0 < v := hu.trans_lt huv
  have u1 : 0 < 1 - u := by linarith
  have v1 : 0 ≤ 1 - v := by linarith
  apply mix_pos (mix_pos _ _ hb0 hb1) (mix_pos _ _ hb0 hb1) ha0 ha1
  · nlinarith [mul_nonneg hu v0.le, mul_nonneg hu hu]
  · nlinarith [mul_pos v0 u1, mul_nonneg hu u1.le, mul_nonneg v0.le v1, mul_nonneg hu v1]
  · nlinarith [sq_nonneg (u + v - 1), pow_pos (sub_pos.2 huv) 2]
  · nlinarith [pow_pos u1 2, mul_nonneg u1.le v1, sq_nonneg (1 - v)]

theorem slopeR_mem {a b u v : ℝ} (ha0 : 0 ≤ a) (ha1 : a ≤ 1) (hb0 : 0 ≤ b) (hb1 : b ≤ 1)
    (hu0 : 0 ≤ u) (hu1 : u ≤ 1) (hv0 : 0 ≤ v) (hv1 : v ≤ 1) : slopeR a b u v ∈ Icc (0 : ℝ) 3 := by
  have pu := sub_nonneg.2 hu1
  have pv := sub_nonneg.2 hv1
  apply mix_mem (mix_mem _ _ hb0 hb1) (mix_mem _ _ hb0 hb1) ha0 ha1 <;> constructor
  · nlinarith [mul_nonneg hu0 hv0, mul_nonneg hu0 hu0, mul_nonneg hv0 hv0]
  · nlinarith [mul_nonneg hu0 pu, mul_nonneg hv0 pv, mul_nonneg hu0 hv0, mul_nonneg pu pv]
  · nlinarith [mul_nonneg hu0 pu, mul_nonneg hv0 pv, mul_nonneg hu0 pv, mul_nonneg hv0 pu]
  · nlinarith [mul_nonneg hu0 pu, mul_nonneg hv0 pv, mul_nonneg hu0 hv0, mul_nonneg pu pv,
      mul_nonneg hu0 hu0, mul_nonneg hv0 hv0, mul_nonneg pu pu, mul_nonneg pv pv]
  · nlinarith [sq_nonneg (u + v - 1), sq_nonneg (v - u)]
  · nlinarith [mul_nonneg hu0 pu, mul_nonneg hv0 pv, mul_nonneg hu0 pv, mul_nonneg hv0 pu]
  · nlinarith [mul_nonneg pu pv, mul_nonneg pu pu, mul_nonneg pv pv]
  · nlinarith [mul_nonneg pu pv, mul_nonneg hu0 pu, mul_nonneg hv0 pv, mul_nonneg hu0 hv0]

/-- `x` is strictly increasing on `[0,1]` for `0 ≤ x_1, x_2 ≤ 1`. -/
theorem bxR_strictMonoOn (c : Bez) (h1 : 0 ≤ c.x1) (h2 : c.x1 ≤ 1) (h3 : 0 ≤ c.x2) (h4 : c.x2 ≤ 1) :
    StrictMonoOn (bxR c) (Icc 0 1) := by
  have q1 : (0 : ℝ) ≤ c.x1 := by exact_mod_cast h1
  have q2 : (c.x1 : ℝ) ≤ 1 := by exact_mod_cast h2
  have q3 : (0 : ℝ) ≤ c.x2 := by exact_mod_cast h3
  have q4 : (c.x2 : ℝ) ≤ 1 := by exact_mod_cast h4
  intro u hu v hv huv
  have e := coordR_sub c.x1 c.x2 u v
  have := mul_pos (sub_pos.2 huv) (slopeR_pos q1 q2 q3 q4 hu.1 huv hv.2)
  simp only [bxR]; linarith

/-- `y` is 3-Lipschitz on `[0,1]` for `0 ≤ y_1, y_2 ≤ 1`. -/
theorem byR_lipschitz (c : Bez) (h1 : 0 ≤ c.y1) (h2 : c.y1 ≤ 1) (h3 : 0 ≤ c.y2) (h4 : c.y2 ≤ 1)
    {u v : ℝ} (hu : u ∈ Icc (0 : ℝ) 1) (hv : v ∈ Icc (0 : ℝ) 1) : |byR c v - byR c u| ≤ 3 * |v - u| := by
  have q1 : (0 : ℝ) ≤ c.y1 := by exact_mod_cast h1
  have q2 : (c.y1 : ℝ) ≤ 1 := by exact_mod_cast h2
  have q3 : (0 : ℝ) ≤ c.y2 := by exact_mod_cast h3
  have q4 : (c.y2 : ℝ) ≤ 1 := by exact_mod_cast h4
  obtain ⟨s0, s3⟩ := slopeR_mem q1 q2 q3 q4 hu.1 hu.2 hv.1 hv.2
  simp only [byR]
  rw [coordR_sub, abs_mul, abs_of_nonneg s0, mul_comm]
  exact mul_le_mul_of_nonneg_right s3 (abs_nonneg _)

/-- `x` is continuous. -/
theorem bxR_continuous (c : Bez) : Continuous (bxR c) := by
  unfold bxR coordR; fun_prop

/-- For `t ∈ [0,1]` and `0 ≤ x_1, x_2 ≤ 1`, `x(s) = t` has exactly one solution in `[0,1]`. -/
theorem existsUnique_root (c : Bez) (h1 : 0 ≤ c.x1) (h2 : c.x1 ≤ 1) (h3 : 0 ≤ c.x2) (h4 : c.x2 ≤ 1)
    (t : ℝ) (ht : t ∈ Icc (0 : ℝ) 1) : ∃! s, s ∈ Icc (0 : ℝ) 1 ∧ bxR c s = t := by
  have e0 : bxR c 0 = 0 := by simp [bxR, coordR]
  have e1 : bxR c 1 = 1 := by simp [bxR, coordR]
  have hivt := intermediate_value_Icc (zero_le_one' ℝ) (bxR_continuous c).continuousOn
  rw [e0, e1] at hivt
  obtain ⟨s, hs, hst⟩ := hivt ht
  refine ⟨s, ⟨hs, hst⟩, fun s' ⟨hs', hst'⟩ => ?_⟩
  exact (bxR_strictMonoOn c h1 h2 h3 h4).injOn hs' hs (hst'.trans hst.symm)

/-- For `0 < t < 1` and `0 ≤ x_1, x_2 ≤ 1`, the `steps`-step `bisect` result is within `1 / 2^41` of the solution. -/
theorem bisect_err (c : Bez) (h1 : 0 ≤ c.x1) (h2 : c.x1 ≤ 1) (h3 : 0 ≤ c.x2) (h4 : c.x2 ≤ 1)
    (t : ℚ) (ht0 : 0 < t) (ht1 : t < 1) (s : ℝ) (hs : s ∈ Icc (0 : ℝ) 1) (hst : bxR c s = t) :
    |((bisect c t steps 0 1 : ℚ) : ℝ) - s| ≤ 1 / 2 ^ (steps + 1) := by
  obtain ⟨l0, llh, hh1, hw, hl, hh⟩ := bracket_unit c t steps ht0 ht1
  have hm := bisect_eq_mid c t steps 0 1
  set l := (bracket c t steps 0 1).1
  set h := (bracket c t steps 0 1).2
  have mono := bxR_strictMonoOn c h1 h2 h3 h4
  have rl : ((bx c l : ℚ) : ℝ) < t := by exact_mod_cast hl
  have rh : (t : ℝ) ≤ ((bx c h : ℚ) : ℝ) := by exact_mod_cast hh
  rw [bx_cast] at rl rh
  have l0' : (0 : ℝ) ≤ l := by exact_mod_cast l0
  have h1' : (h : ℝ) ≤ 1 := by exact_mod_cast hh1
  have lh' : (l : ℝ) ≤ h := by exact_mod_cast llh
  have sl : (l : ℝ) < s := by
    by_contra hc
    have := mono.monotoneOn hs ⟨l0', lh'.trans h1'⟩ (not_lt.1 hc)
    linarith
  have sh : s ≤ (h : ℝ) := by
    by_contra hc
    have := mono ⟨l0'.trans lh', h1'⟩ hs (not_le.1 hc)
    linarith
  have p : (0 : ℝ) < 2 ^ steps := by positivity
  have hw' : ((h : ℝ) - l) * 2 ^ steps = 1 := by exact_mod_cast hw
  have w : (h : ℝ) - l = 1 / 2 ^ steps := (eq_div_iff p.ne').2 hw'
  have hm' : ((bisect c t steps 0 1 : ℚ) : ℝ) = ((l : ℝ) + h) / 2 := by rw [hm]; push_cast; ring
  have key : (1 : ℝ) / 2 ^ (steps + 1) = ((h : ℝ) - l) / 2 := by rw [pow_succ, w, div_div]
  rw [hm', key, abs_le]
  constructor <;> linarith

/-- For `0 < t < 1` and all control values in `[0,1]`, `ease` is within `3 / 2^41` of `y` at the solution. -/
theorem ease_err (c : Bez) (hx1 : 0 ≤ c.x1) (hx2 : c.x1 ≤ 1) (hx3 : 0 ≤ c.x2) (hx4 : c.x2 ≤ 1)
    (hy1 : 0 ≤ c.y1) (hy2 : c.y1 ≤ 1) (hy3 : 0 ≤ c.y2) (hy4 : c.y2 ≤ 1)
    (t : ℚ) (ht0 : 0 < t) (ht1 : t < 1) (s : ℝ) (hs : s ∈ Icc (0 : ℝ) 1) (hst : bxR c s = t) :
    |((ease c t : ℚ) : ℝ) - byR c s| ≤ 3 / 2 ^ (steps + 1) := by
  have hb := bisect_mem c t steps 0 1 (by decide)
  have m : ((bisect c t steps 0 1 : ℚ) : ℝ) ∈ Icc (0 : ℝ) 1 := ⟨by exact_mod_cast hb.1, by exact_mod_cast hb.2⟩
  have e := bisect_err c hx1 hx2 hx3 hx4 t ht0 ht1 s hs hst
  have L := byR_lipschitz c hy1 hy2 hy3 hy4 hs m
  rw [ease_cast c t ht0 ht1]
  calc |byR c (bisect c t steps 0 1) - byR c s| ≤ 3 * |((bisect c t steps 0 1 : ℚ) : ℝ) - s| := L
    _ ≤ 3 * (1 / 2 ^ (steps + 1)) := by gcongr
    _ = 3 / 2 ^ (steps + 1) := by ring

/-- The header claim of `Fw.Parts.Bezier`: for `0 < t < 1` and control values in `[0,1]`, the solution `s*` of
`x(s) = t` in `[0,1]` exists and is unique, `|bisect - s*| ≤ 2^-40` and `|ease - y(s*)| ≤ 3 · 2^-40`. -/
theorem ease_exact (c : Bez) (hx1 : 0 ≤ c.x1) (hx2 : c.x1 ≤ 1) (hx3 : 0 ≤ c.x2) (hx4 : c.x2 ≤ 1)
    (hy1 : 0 ≤ c.y1) (hy2 : c.y1 ≤ 1) (hy3 : 0 ≤ c.y2) (hy4 : c.y2 ≤ 1) (t : ℚ) (ht0 : 0 < t) (ht1 : t < 1) :
    ∃! s, s ∈ Icc (0 : ℝ) 1 ∧ bxR c s = t ∧
      |((bisect c t steps 0 1 : ℚ) : ℝ) - s| ≤ 1 / 2 ^ 40 ∧ |((ease c t : ℚ) : ℝ) - byR c s| ≤ 3 / 2 ^ 40 := by
  have ht : (t : ℝ) ∈ Icc (0 : ℝ) 1 := ⟨by exact_mod_cast ht0.le, by exact_mod_cast ht1.le⟩
  obtain ⟨s, ⟨hs, hst⟩, hu⟩ := existsUnique_root c hx1 hx2 hx3 hx4 t ht
  have p : (0 : ℝ) < 2 ^ 40 := by positivity
  have r : (1 : ℝ) / 2 ^ (steps + 1) ≤ 1 / 2 ^ 40 := by
    rw [show steps + 1 = 40 + 1 from rfl, pow_succ]; gcongr; linarith
  refine ⟨s, ⟨hs, hst, (bisect_err c hx1 hx2 hx3 hx4 t ht0 ht1 s hs hst).trans r, ?_⟩,
    fun s' ⟨hs', hst', _⟩ => hu s' ⟨hs', hst'⟩⟩
  calc |((ease c t : ℚ) : ℝ) - byR c s| ≤ 3 / 2 ^ (steps + 1) :=
        ease_err c hx1 hx2 hx3 hx4 hy1 hy2 hy3 hy4 t ht0 ht1 s hs hst
    _ = 3 * (1 / 2 ^ (steps + 1)) := by ring
    _ ≤ 3 * (1 / 2 ^ 40) := by gcongr
    _ = 3 / 2 ^ 40 := by ring

end FwMath.Bezier

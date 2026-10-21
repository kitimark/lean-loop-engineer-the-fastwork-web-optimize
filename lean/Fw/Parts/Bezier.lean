/-! CSS `cubic-bezier` timing curves over `Rat`; `ease` solves `x(s) = t` by 40 bisection steps on `[0,1]`.
Exactness: `bx_strictMono`, `bracket_cut`, `ease_err`; the real-root form is `FwMath.Bezier` in `lean-math/`. -/
namespace Fw.Parts.Bezier

/-- A cubic Bezier timing function with control points `(x_1, y_1)` and `(x_2, y_2)`. -/
structure Bez where
  x1 : Rat
  y1 : Rat
  x2 : Rat
  y2 : Rat
deriving Repr, BEq, DecidableEq

/-- The CSS keyword `ease-in-out`. Used by the drawer's panel and backdrop. -/
def easeInOut : Bez := ⟨21 / 50, 0, 29 / 50, 1⟩

/-- The design system's `--ease-standard`. Used by the dialog's enter animation. -/
def easeStandard : Bez := ⟨6 / 25, 1, 2 / 5, 1⟩

/-- One coordinate of the Bezier at parameter `s`. -/
def coord (a b s : Rat) : Rat :=
  3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s

/-- Time coordinate. The curve's horizontal position. -/
def bx (c : Bez) (s : Rat) : Rat := coord c.x1 c.x2 s

/-- Value coordinate. The curve's vertical position. -/
def by' (c : Bez) (s : Rat) : Rat := coord c.y1 c.y2 s

/-- Bisection for `x(s) = t` on `[lo, hi]` with `n` steps, returning the midpoint at the end. -/
def bisect (c : Bez) (t : Rat) : Nat → Rat → Rat → Rat
  | 0, lo, hi => (lo + hi) / 2
  | n + 1, lo, hi =>
    let m := (lo + hi) / 2
    if bx c m < t then bisect c t n m hi else bisect c t n lo m

/-- Number of bisection steps. How fine the solve is. -/
def steps : Nat := 40

/-- The eased fraction for a time fraction `t`: the curve's value at the parameter that `N = 40` bisection steps for
`x(s) = t` on `[0, 1]` reach (an approximation of the exact inverse, not the exact `s`). -/
def ease (c : Bez) (t : Rat) : Rat :=
  if t ≤ 0 then 0 else if 1 ≤ t then 1 else by' c (bisect c t steps 0 1)

/-- The curve starts at 0. -/
theorem ease_zero (c : Bez) : ease c 0 = 0 := by simp [ease]

/-- The curve ends at 1. -/
theorem ease_one (c : Bez) : ease c 1 = 1 := by
  have h : ¬ ((1 : Rat) ≤ 0) := by decide
  simp [ease, h]

/-- Below the start the curve holds 0. -/
theorem ease_nonpos (c : Bez) (t : Rat) (h : t ≤ 0) : ease c t = 0 := by simp [ease, h]

/-- After the end the curve holds 1. -/
theorem ease_ge_one (c : Bez) (t : Rat) (h : 1 ≤ t) : ease c t = 1 := by
  unfold ease; split <;> grind

/-- The coordinate polynomial starts at 0. -/
theorem coord_zero (a b : Rat) : coord a b 0 = 0 := by unfold coord; grind

/-- The coordinate polynomial ends at 1. -/
theorem coord_one (a b : Rat) : coord a b 1 = 1 := by unfold coord; grind

/-- A coordinate with control values in `[0,1]` stays in `[0,1]` for `s ∈ [0,1]`.

(Bernstein weights are non-negative and sum to 1.) -/
theorem coord_mem (a b s : Rat) (ha0 : 0 ≤ a) (ha1 : a ≤ 1) (hb0 : 0 ≤ b) (hb1 : b ≤ 1)
    (hs0 : 0 ≤ s) (hs1 : s ≤ 1) : 0 ≤ coord a b s ∧ coord a b s ≤ 1 := by
  unfold coord
  have hu : 0 ≤ 1 - s := by grind
  have hss : 0 ≤ s * s := Rat.mul_nonneg hs0 hs0
  have huu : 0 ≤ (1 - s) * (1 - s) := Rat.mul_nonneg hu hu
  have hus : 0 ≤ (1 - s) * s := Rat.mul_nonneg hu hs0
  have hw1 : 0 ≤ (1 - s) * (1 - s) * s := Rat.mul_nonneg huu hs0
  have hw2 : 0 ≤ (1 - s) * s * s := Rat.mul_nonneg hus hs0
  have hw3 : 0 ≤ s * s * s := Rat.mul_nonneg hss hs0
  have hw0 : 0 ≤ (1 - s) * (1 - s) * (1 - s) := Rat.mul_nonneg huu hu
  have e1 := Rat.mul_le_mul_of_nonneg_left ha1 hw1
  have e2 := Rat.mul_le_mul_of_nonneg_left hb1 hw2
  have f1 := Rat.mul_nonneg hw1 ha0
  have f2 := Rat.mul_nonneg hw2 hb0
  constructor
  · grind
  · grind

/-- Bisection keeps the answer inside the start interval. -/
theorem bisect_mem (c : Bez) (t : Rat) (n : Nat) :
    ∀ lo hi : Rat, lo ≤ hi → lo ≤ bisect c t n lo hi ∧ bisect c t n lo hi ≤ hi := by
  induction n with
  | zero => intro lo hi h; simp only [bisect]; grind
  | succ n ih =>
    intro lo hi h
    simp only [bisect]
    split
    · have := ih ((lo + hi) / 2) hi (by grind); grind
    · have := ih lo ((lo + hi) / 2) (by grind); grind

/-- The difference quotient of `coord a b` between `u` and `v` (`coord_sub`). -/
def slope (a b u v : Rat) : Rat :=
  3 * a * (1 - 2 * (u + v) + (u * u + u * v + v * v)) + 3 * b * ((u + v) - (u * u + u * v + v * v))
    + (u * u + u * v + v * v)

/-- A coordinate difference factors through `slope`. -/
theorem coord_sub (a b u v : Rat) : coord a b v - coord a b u = (v - u) * slope a b u v := by
  unfold coord slope; grind

/-- `slope` at control values `(0, 0)`. -/
def q00 (u v : Rat) : Rat := u * u + u * v + v * v

/-- `slope` at control values `(1, 0)`. -/
def q10 (u v : Rat) : Rat := 3 * ((u + v - 1) * (u + v - 1)) + (v - u) * (v - u)

/-- `slope` at control values `(0, 1)`. -/
def q01 (u v : Rat) : Rat := 2 * (u * (1 - u)) + 2 * (v * (1 - v)) + u * (1 - v) + v * (1 - u)

/-- `slope` at control values `(1, 1)`. -/
def q11 (u v : Rat) : Rat := (1 - u) * (1 - u) + (1 - u) * (1 - v) + (1 - v) * (1 - v)

/-- `slope` is affine in each control value, so it is the bilinear mix of its four corner values. -/
theorem slope_mix (a b u v : Rat) :
    slope a b u v = (1 - a) * ((1 - b) * q00 u v + b * q01 u v) + a * ((1 - b) * q10 u v + b * q11 u v) := by
  unfold slope q00 q01 q10 q11; grind

/-- A square is non-negative. -/
theorem self_mul_nonneg (x : Rat) : 0 ≤ x * x := by
  by_cases h : 0 ≤ x
  · exact Rat.mul_nonneg h h
  · have := Rat.mul_nonneg (show 0 ≤ -x by grind) (show 0 ≤ -x by grind)
    grind

/-- A mix of two positive values with a weight in `[0,1]` is positive. -/
theorem mix_pos {x y w : Rat} (hx : 0 < x) (hy : 0 < y) (h0 : 0 ≤ w) (h1 : w ≤ 1) :
    0 < (1 - w) * x + w * y := by
  by_cases h : w < 1
  · have := Rat.mul_pos (show 0 < 1 - w by grind) hx
    have := Rat.mul_nonneg h0 (Rat.le_of_lt hy)
    grind
  · have hw : w = 1 := by grind
    subst hw; grind

/-- A mix of two non-negative values with a weight in `[0,1]` is non-negative. -/
theorem mix_nonneg {x y w : Rat} (hx : 0 ≤ x) (hy : 0 ≤ y) (h0 : 0 ≤ w) (h1 : w ≤ 1) :
    0 ≤ (1 - w) * x + w * y := by
  have := Rat.mul_nonneg (show 0 ≤ 1 - w by grind) hx
  have := Rat.mul_nonneg h0 hy
  grind

/-- The four corner values are positive between two distinct points of `[0,1]`. -/
theorem corners_pos {u v : Rat} (hu : 0 ≤ u) (huv : u < v) (hv : v ≤ 1) :
    0 < q00 u v ∧ 0 < q10 u v ∧ 0 < q01 u v ∧ 0 < q11 u v := by
  have vp : 0 < v := by grind
  have up : 0 < 1 - u := by grind
  have hvv := Rat.mul_pos vp vp
  have huu := Rat.mul_nonneg hu hu
  have huv0 := Rat.mul_nonneg hu (Rat.le_of_lt vp)
  have hd := Rat.mul_pos (show 0 < v - u by grind) (show 0 < v - u by grind)
  have hs := self_mul_nonneg (u + v - 1)
  have h1 := Rat.mul_nonneg hu (Rat.le_of_lt up)
  have h2 := Rat.mul_nonneg (Rat.le_of_lt vp) (show 0 ≤ 1 - v by grind)
  have h3 := Rat.mul_nonneg hu (show 0 ≤ 1 - v by grind)
  have h4 := Rat.mul_pos vp up
  have h5 := Rat.mul_pos up up
  have h6 := Rat.mul_nonneg (Rat.le_of_lt up) (show 0 ≤ 1 - v by grind)
  have h7 := Rat.mul_nonneg (show 0 ≤ 1 - v by grind) (show 0 ≤ 1 - v by grind)
  unfold q00 q10 q01 q11
  grind

/-- The four corner values lie in `[0,3]` at any two points of `[0,1]`. -/
theorem corners_mem {u v : Rat} (hu0 : 0 ≤ u) (hu1 : u ≤ 1) (hv0 : 0 ≤ v) (hv1 : v ≤ 1) :
    (0 ≤ q00 u v ∧ q00 u v ≤ 3) ∧ (0 ≤ q10 u v ∧ q10 u v ≤ 3) ∧ (0 ≤ q01 u v ∧ q01 u v ≤ 3) ∧
      (0 ≤ q11 u v ∧ q11 u v ≤ 3) := by
  have pu : 0 ≤ 1 - u := by grind
  have pv : 0 ≤ 1 - v := by grind
  have a1 := Rat.mul_nonneg hu0 hu0
  have a2 := Rat.mul_nonneg hu0 hv0
  have a3 := Rat.mul_nonneg hv0 hv0
  have a4 := Rat.mul_nonneg hu0 pu
  have a5 := Rat.mul_nonneg hv0 pv
  have a6 := Rat.mul_nonneg hu0 pv
  have a7 := Rat.mul_nonneg hv0 pu
  have a8 := Rat.mul_nonneg pu pu
  have a9 := Rat.mul_nonneg pu pv
  have a10 := Rat.mul_nonneg pv pv
  have a11 := self_mul_nonneg (u + v - 1)
  have a12 := self_mul_nonneg (v - u)
  unfold q00 q10 q01 q11
  grind

/-- `slope` is positive between two distinct points of `[0,1]` when both control values are in `[0,1]`. -/
theorem slope_pos {a b u v : Rat} (ha0 : 0 ≤ a) (ha1 : a ≤ 1) (hb0 : 0 ≤ b) (hb1 : b ≤ 1)
    (hu : 0 ≤ u) (huv : u < v) (hv : v ≤ 1) : 0 < slope a b u v := by
  have ⟨c00, c10, c01, c11⟩ := corners_pos hu huv hv
  rw [slope_mix]
  exact mix_pos (mix_pos c00 c01 hb0 hb1) (mix_pos c10 c11 hb0 hb1) ha0 ha1

/-- `slope` lies in `[0,3]` at any two points of `[0,1]` when both control values are in `[0,1]`. -/
theorem slope_mem {a b u v : Rat} (ha0 : 0 ≤ a) (ha1 : a ≤ 1) (hb0 : 0 ≤ b) (hb1 : b ≤ 1)
    (hu0 : 0 ≤ u) (hu1 : u ≤ 1) (hv0 : 0 ≤ v) (hv1 : v ≤ 1) : 0 ≤ slope a b u v ∧ slope a b u v ≤ 3 := by
  have ⟨⟨c00, d00⟩, ⟨c10, d10⟩, ⟨c01, d01⟩, ⟨c11, d11⟩⟩ := corners_mem hu0 hu1 hv0 hv1
  have lo := mix_nonneg (mix_nonneg c00 c01 hb0 hb1) (mix_nonneg c10 c11 hb0 hb1) ha0 ha1
  have hi := mix_nonneg (mix_nonneg (show 0 ≤ 3 - q00 u v by grind) (show 0 ≤ 3 - q01 u v by grind) hb0 hb1)
    (mix_nonneg (show 0 ≤ 3 - q10 u v by grind) (show 0 ≤ 3 - q11 u v by grind) hb0 hb1) ha0 ha1
  rw [slope_mix]
  constructor
  · exact lo
  · grind

/-- A coordinate with control values in `[0,1]` is strictly increasing on `[0,1]`. -/
theorem coord_strictMono {a b u v : Rat} (ha0 : 0 ≤ a) (ha1 : a ≤ 1) (hb0 : 0 ≤ b) (hb1 : b ≤ 1)
    (hu : 0 ≤ u) (huv : u < v) (hv : v ≤ 1) : coord a b u < coord a b v := by
  have h := coord_sub a b u v
  have := Rat.mul_pos (show 0 < v - u by grind) (slope_pos ha0 ha1 hb0 hb1 hu huv hv)
  grind

/-- A coordinate with control values in `[0,1]` rises by at most 3 times the step on `[0,1]`. -/
theorem coord_lipschitz {a b u v : Rat} (ha0 : 0 ≤ a) (ha1 : a ≤ 1) (hb0 : 0 ≤ b) (hb1 : b ≤ 1)
    (hu : 0 ≤ u) (huv : u ≤ v) (hv : v ≤ 1) :
    0 ≤ coord a b v - coord a b u ∧ coord a b v - coord a b u ≤ 3 * (v - u) := by
  have h := coord_sub a b u v
  have ⟨s0, s3⟩ := slope_mem ha0 ha1 hb0 hb1 hu (by grind) (by grind) hv
  have d0 : 0 ≤ v - u := by grind
  have := Rat.mul_nonneg d0 s0
  have := Rat.mul_le_mul_of_nonneg_left s3 d0
  grind

/-- The time coordinate is strictly increasing on `[0,1]` when `0 ≤ x_1, x_2 ≤ 1`. -/
theorem bx_strictMono (c : Bez) (h1 : 0 ≤ c.x1) (h2 : c.x1 ≤ 1) (h3 : 0 ≤ c.x2) (h4 : c.x2 ≤ 1)
    {u v : Rat} (hu : 0 ≤ u) (huv : u < v) (hv : v ≤ 1) : bx c u < bx c v :=
  coord_strictMono h1 h2 h3 h4 hu huv hv

/-- The time coordinate is monotone on `[0,1]` when `0 ≤ x_1, x_2 ≤ 1`. -/
theorem bx_mono (c : Bez) (h1 : 0 ≤ c.x1) (h2 : c.x1 ≤ 1) (h3 : 0 ≤ c.x2) (h4 : c.x2 ≤ 1)
    {u v : Rat} (hu : 0 ≤ u) (huv : u ≤ v) (hv : v ≤ 1) : bx c u ≤ bx c v := by
  have := (coord_lipschitz h1 h2 h3 h4 hu huv hv).1
  unfold bx; grind

/-- The interval `(lo, hi)` that `n` bisection steps for `x(s) = t` end on. `bisect` returns its midpoint. -/
def bracket (c : Bez) (t : Rat) : Nat → Rat → Rat → Rat × Rat
  | 0, lo, hi => (lo, hi)
  | n + 1, lo, hi =>
    let m := (lo + hi) / 2
    if bx c m < t then bracket c t n m hi else bracket c t n lo m

/-- `bisect` returns the midpoint of `bracket`. -/
theorem bisect_eq_mid (c : Bez) (t : Rat) (n : Nat) :
    ∀ lo hi : Rat, bisect c t n lo hi = ((bracket c t n lo hi).1 + (bracket c t n lo hi).2) / 2 := by
  induction n with
  | zero => intro lo hi; rfl
  | succ n ih =>
    intro lo hi
    simp only [bisect, bracket]
    split
    · exact ih _ _
    · exact ih _ _

/-- After `n` steps the bracket lies in `[lo, hi]`, has width `(hi - lo) / 2^n`, `x < t` at its left end, `t ≤ x` at its right end. -/
theorem bracket_inv (c : Bez) (t : Rat) (n : Nat) :
    ∀ lo hi : Rat, lo ≤ hi → bx c lo < t → t ≤ bx c hi →
      lo ≤ (bracket c t n lo hi).1 ∧ (bracket c t n lo hi).1 ≤ (bracket c t n lo hi).2 ∧
      (bracket c t n lo hi).2 ≤ hi ∧ ((bracket c t n lo hi).2 - (bracket c t n lo hi).1) * 2 ^ n = hi - lo ∧
      bx c (bracket c t n lo hi).1 < t ∧ t ≤ bx c (bracket c t n lo hi).2 := by
  induction n with
  | zero => intro lo hi h hl hh; simp only [bracket]; grind
  | succ n ih =>
    intro lo hi h hl hh
    simp only [bracket, Rat.pow_succ]
    split
    · have := ih ((lo + hi) / 2) hi (by grind) (by assumption) hh; grind
    · have := ih lo ((lo + hi) / 2) (by grind) hl (by grind); grind

/-- For `0 < t < 1` the bracket of the solve on `[0,1]` has width `1 / 2^n`, `x < t` at its left end, `t ≤ x` at its right end. -/
theorem bracket_unit (c : Bez) (t : Rat) (n : Nat) (ht0 : 0 < t) (ht1 : t < 1) :
    0 ≤ (bracket c t n 0 1).1 ∧ (bracket c t n 0 1).1 ≤ (bracket c t n 0 1).2 ∧ (bracket c t n 0 1).2 ≤ 1 ∧
      ((bracket c t n 0 1).2 - (bracket c t n 0 1).1) * 2 ^ n = 1 ∧
      bx c (bracket c t n 0 1).1 < t ∧ t ≤ bx c (bracket c t n 0 1).2 := by
  have h0 : bx c 0 = 0 := coord_zero _ _
  have h1 : bx c 1 = 1 := coord_one _ _
  have := bracket_inv c t n 0 1 (by decide) (by grind) (by grind)
  grind

/-- For `0 < t < 1` and `0 ≤ x_1, x_2 ≤ 1`, points of `[0,1]` left of the bracket have `x < t`, points right of it `t < x`. -/
theorem bracket_cut (c : Bez) (t : Rat) (n : Nat) (ht0 : 0 < t) (ht1 : t < 1)
    (h1 : 0 ≤ c.x1) (h2 : c.x1 ≤ 1) (h3 : 0 ≤ c.x2) (h4 : c.x2 ≤ 1) (s : Rat) (hs0 : 0 ≤ s) (hs1 : s ≤ 1) :
    (s ≤ (bracket c t n 0 1).1 → bx c s < t) ∧ ((bracket c t n 0 1).2 < s → t < bx c s) := by
  have ⟨l0, llh, h1', _, hl, hh⟩ := bracket_unit c t n ht0 ht1
  constructor
  · intro hs
    have := bx_mono c h1 h2 h3 h4 hs0 hs (by grind)
    grind
  · intro hs
    have := bx_strictMono c h1 h2 h3 h4 (by grind) hs hs1
    grind

/-- At a rational solution `s` of `x(s) = t` the midpoint is within `1 / 2^(n+1)` of `s`, its value within `3 / 2^(n+1)`. -/
theorem bisect_value_err (c : Bez) (t : Rat) (n : Nat) (ht0 : 0 < t) (ht1 : t < 1)
    (hx1 : 0 ≤ c.x1) (hx2 : c.x1 ≤ 1) (hx3 : 0 ≤ c.x2) (hx4 : c.x2 ≤ 1)
    (hy1 : 0 ≤ c.y1) (hy2 : c.y1 ≤ 1) (hy3 : 0 ≤ c.y2) (hy4 : c.y2 ≤ 1)
    (s : Rat) (hs0 : 0 ≤ s) (hs1 : s ≤ 1) (hs : bx c s = t) :
    (bisect c t n 0 1 - s) * 2 ^ (n + 1) ≤ 1 ∧ (s - bisect c t n 0 1) * 2 ^ (n + 1) ≤ 1 ∧
      (by' c (bisect c t n 0 1) - by' c s) * 2 ^ (n + 1) ≤ 3 ∧
      (by' c s - by' c (bisect c t n 0 1)) * 2 ^ (n + 1) ≤ 3 := by
  have ⟨l0, llh, h1', hw, hl, hh⟩ := bracket_unit c t n ht0 ht1
  have ⟨cl, cr⟩ := bracket_cut c t n ht0 ht1 hx1 hx2 hx3 hx4 s hs0 hs1
  have sl : (bracket c t n 0 1).1 < s := by
    false_or_by_contra
    have := cl (by grind); grind
  have sr : s ≤ (bracket c t n 0 1).2 := by
    false_or_by_contra
    have := cr (by grind); grind
  have hm := bisect_eq_mid c t n 0 1
  have p0 : (0 : Rat) ≤ 2 ^ n := Rat.le_of_lt (Rat.pow_pos (by decide))
  have m0 : 0 ≤ bisect c t n 0 1 := by grind
  have m1 : bisect c t n 0 1 ≤ 1 := by grind
  have e1 : bisect c t n 0 1 - s ≤ ((bracket c t n 0 1).2 - (bracket c t n 0 1).1) / 2 := by grind
  have e2 : s - bisect c t n 0 1 ≤ ((bracket c t n 0 1).2 - (bracket c t n 0 1).1) / 2 := by grind
  have y1 : by' c (bisect c t n 0 1) - by' c s ≤ 3 * (((bracket c t n 0 1).2 - (bracket c t n 0 1).1) / 2) ∧
      by' c s - by' c (bisect c t n 0 1) ≤ 3 * (((bracket c t n 0 1).2 - (bracket c t n 0 1).1) / 2) := by
    unfold by'
    by_cases hc : s ≤ bisect c t n 0 1
    · have := coord_lipschitz hy1 hy2 hy3 hy4 hs0 hc m1; grind
    · have := coord_lipschitz hy1 hy2 hy3 hy4 m0 (show bisect c t n 0 1 ≤ s by grind) hs1; grind
  have f1 := Rat.mul_le_mul_of_nonneg_left e1 p0
  have f2 := Rat.mul_le_mul_of_nonneg_left e2 p0
  have f3 := Rat.mul_le_mul_of_nonneg_left y1.1 p0
  have f4 := Rat.mul_le_mul_of_nonneg_left y1.2 p0
  simp only [Rat.pow_succ]
  grind

/-- The eased fraction stays in `[0,1]` for control values in `[0,1]`.

The animation never overshoots (true of both curves used: `ease-in-out` and `--ease-standard`). -/
theorem ease_mem (c : Bez) (t : Rat) (h1 : 0 ≤ c.y1) (h2 : c.y1 ≤ 1) (h3 : 0 ≤ c.y2) (h4 : c.y2 ≤ 1) :
    0 ≤ ease c t ∧ ease c t ≤ 1 := by
  unfold ease
  split
  · grind
  · split
    · grind
    · have hb := bisect_mem c t steps 0 1 (by grind)
      exact coord_mem _ _ _ h1 h2 h3 h4 hb.1 hb.2

/-- For `0 < t < 1` and control values in `[0,1]`, `ease` is within `3 / 2^41` of `y(s)` at every rational solution `s`. -/
theorem ease_err (c : Bez) (t : Rat) (ht0 : 0 < t) (ht1 : t < 1)
    (hx1 : 0 ≤ c.x1) (hx2 : c.x1 ≤ 1) (hx3 : 0 ≤ c.x2) (hx4 : c.x2 ≤ 1)
    (hy1 : 0 ≤ c.y1) (hy2 : c.y1 ≤ 1) (hy3 : 0 ≤ c.y2) (hy4 : c.y2 ≤ 1)
    (s : Rat) (hs0 : 0 ≤ s) (hs1 : s ≤ 1) (hs : bx c s = t) :
    (ease c t - by' c s) * 2 ^ (steps + 1) ≤ 3 ∧ (by' c s - ease c t) * 2 ^ (steps + 1) ≤ 3 := by
  have e := bisect_value_err c t steps ht0 ht1 hx1 hx2 hx3 hx4 hy1 hy2 hy3 hy4 s hs0 hs1 hs
  have n0 : ¬ t ≤ 0 := by grind
  have n1 : ¬ 1 ≤ t := by grind
  simp only [ease, n0, n1, ite_false]
  exact ⟨e.2.2.1, e.2.2.2⟩

#guard slope 1 0 (1 / 2) (1 / 2) == 0
#guard slope 1 0 (1 / 4) (3 / 4) == q10 (1 / 4) (3 / 4) && slope 0 1 (1 / 4) (3 / 4) == q01 (1 / 4) (3 / 4)
#guard coord 1 0 (3 / 4) - coord 1 0 (1 / 4) == (3 / 4 - 1 / 4) * slope 1 0 (1 / 4) (3 / 4)
#guard let b := bracket easeInOut (1 / 2) steps 0 1; (b.2 - b.1) * 2 ^ steps == 1 && b.1 < 1 / 2 && 1 / 2 ≤ b.2
#guard let b := bracket easeStandard (1 / 3) steps 0 1; bx easeStandard b.1 < 1 / 3 && 1 / 3 ≤ bx easeStandard b.2
#guard bisect easeInOut (1 / 2) steps 0 1 == (bracket easeInOut (1 / 2) steps 0 1).1 / 2
  + (bracket easeInOut (1 / 2) steps 0 1).2 / 2
#guard ease easeInOut 0 == 0
#guard ease easeInOut 1 == 1
#guard ease easeStandard (1 / 2) > 9 / 10
#guard ease easeInOut (1 / 2) > 49 / 100 && ease easeInOut (1 / 2) < 51 / 100

end Fw.Parts.Bezier

/-!
# CSS cubic-bezier timing curves (shared by the overlay parts)

Restated from the CSS Easing Functions spec: a timing function `cubic-bezier(x1, y1, x2, y2)` is the curve through
$P_0 = (0,0)$, $P_1 = (x_1, y_1)$, $P_2 = (x_2, y_2)$, $P_3 = (1,1)$; for input time fraction $t$ the output is
$y(s^*)$ where $x(s^*) = t$. The browser solves $x(s) = t$ numerically; here it is solved by 40 bisection steps on
$s \in [0,1]$, which is exact to $2^{-40}$ in $s$ ($x$ is monotone for the control points used: $0 \le x_1, x_2 \le 1$).
All values `Rat`; no `Float`.
-/
namespace Fw.Parts.Bezier

/-- A cubic Bezier timing function with control points $(x_1, y_1)$ and $(x_2, y_2)$. $$\mathrm{cubic\text{-}bezier}(x_1, y_1, x_2, y_2)$$ -/
structure Bez where
  x1 : Rat
  y1 : Rat
  x2 : Rat
  y2 : Rat
deriving Repr, BEq, DecidableEq

/-- The CSS keyword `ease-in-out`. $$\mathrm{cubic\text{-}bezier}(0.42,\ 0,\ 0.58,\ 1)$$ Used by the drawer's panel and backdrop. -/
def easeInOut : Bez := ⟨21 / 50, 0, 29 / 50, 1⟩

/-- The design system's `--ease-standard`. $$\mathrm{cubic\text{-}bezier}(0.24,\ 1,\ 0.4,\ 1)$$ Used by the dialog's enter animation. -/
def easeStandard : Bez := ⟨6 / 25, 1, 2 / 5, 1⟩

/-- One coordinate of the Bezier at parameter $s$.

$$B(s; a, b) = 3(1-s)^2 s\,a + 3(1-s) s^2\,b + s^3$$

with the end points fixed at $0$ and $1$. -/
def coord (a b s : Rat) : Rat :=
  3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s

/-- Time coordinate. $$x(s) = B(s; x_1, x_2)$$ The curve's horizontal position. -/
def bx (c : Bez) (s : Rat) : Rat := coord c.x1 c.x2 s

/-- Value coordinate. $$y(s) = B(s; y_1, y_2)$$ The curve's vertical position. -/
def by' (c : Bez) (s : Rat) : Rat := coord c.y1 c.y2 s

/-- Bisection for $x(s) = t$ on $[lo, hi]$ with $n$ steps, returning the midpoint at the end.

$$\operatorname{bis}_{n+1}(lo, hi) = \begin{cases} \operatorname{bis}_n(m, hi) & x(m) < t \\ \operatorname{bis}_n(lo, m) & \text{otherwise}\end{cases},\quad m = \tfrac{lo+hi}{2}$$ -/
def bisect (c : Bez) (t : Rat) : Nat → Rat → Rat → Rat
  | 0, lo, hi => (lo + hi) / 2
  | n + 1, lo, hi =>
    let m := (lo + hi) / 2
    if bx c m < t then bisect c t n m hi else bisect c t n lo m

/-- Number of bisection steps. $$N = 40$$ How fine the solve is. -/
def steps : Nat := 40

/-- The eased fraction for a time fraction $t$.

$$\operatorname{ease}_c(t) = \begin{cases} 0 & t \le 0 \\ 1 & t \ge 1 \\ y(s^*),\ x(s^*) = t & \text{otherwise}\end{cases}$$ -/
def ease (c : Bez) (t : Rat) : Rat :=
  if t ≤ 0 then 0 else if 1 ≤ t then 1 else by' c (bisect c t steps 0 1)

/-- The curve starts at 0. $$\operatorname{ease}_c(0) = 0$$ -/
theorem ease_zero (c : Bez) : ease c 0 = 0 := by simp [ease]

/-- The curve ends at 1. $$\operatorname{ease}_c(1) = 1$$ -/
theorem ease_one (c : Bez) : ease c 1 = 1 := by
  have h : ¬ ((1 : Rat) ≤ 0) := by decide
  simp [ease, h]

/-- Below the start the curve holds 0. $$t \le 0 \Rightarrow \operatorname{ease}_c(t) = 0$$ -/
theorem ease_nonpos (c : Bez) (t : Rat) (h : t ≤ 0) : ease c t = 0 := by simp [ease, h]

/-- After the end the curve holds 1. $$t \ge 1 \Rightarrow \operatorname{ease}_c(t) = 1$$ -/
theorem ease_ge_one (c : Bez) (t : Rat) (h : 1 ≤ t) : ease c t = 1 := by
  unfold ease; split <;> grind

/-- The coordinate polynomial starts at 0. $$B(0; a, b) = 0$$ -/
theorem coord_zero (a b : Rat) : coord a b 0 = 0 := by unfold coord; grind

/-- The coordinate polynomial ends at 1. $$B(1; a, b) = 1$$ -/
theorem coord_one (a b : Rat) : coord a b 1 = 1 := by unfold coord; grind

/-- A coordinate with control values in $[0,1]$ stays in $[0,1]$ for $s \in [0,1]$.

$$0 \le a, b \le 1,\ 0 \le s \le 1 \Rightarrow 0 \le B(s; a, b) \le 1$$

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

/-- Bisection keeps the answer inside the start interval.

$$lo \le hi \Rightarrow lo \le \operatorname{bis}_n(lo, hi) \le hi$$ -/
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

/-- The eased fraction stays in $[0,1]$ for control values in $[0,1]$.

$$0 \le y_1, y_2 \le 1 \Rightarrow \forall t:\ 0 \le \operatorname{ease}_c(t) \le 1$$

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

#guard ease easeInOut 0 == 0
#guard ease easeInOut 1 == 1
#guard ease easeStandard (1 / 2) > 9 / 10
#guard ease easeInOut (1 / 2) > 49 / 100 && ease easeInOut (1 / 2) < 51 / 100

end Fw.Parts.Bezier

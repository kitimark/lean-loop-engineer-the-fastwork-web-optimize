import Fw.Parts.MorphTween

/-!
# morph.tween, variant `waapi`: the curve (MT1, MT2)

The WAAPI variant of morph.tween runs the tween as a CSS animation with the timing function
`cubic-bezier(1/3, 1, 2/3, 1)`. This module proves that this curve *is* the original's ease
$1-(1-s)^3$ (MT1), and bounds what the engines' numeric solver can change (MT2).
Design: `research/notes/2026/10-18-engine-proof-design.md` §0 and §4.1.

Engine model, restated (not copied) from the pinned sources:

* Chromium `ui/gfx/geometry/cubic_bezier.cc:50-56`@f842f52 and WebKit
  `Source/WebCore/platform/graphics/UnitBezier.h:45-51`@862f17d build the coefficients
  $c = 3p_1$, $b = 3(p_2-p_1) - c$, $a = 1 - c - b$ for each axis and evaluate
  $((a t + b) t + c) t$ (Horner; `cubic_bezier.h:23-37`@f842f52, `UnitBezier.h:94-108`@862f17d).
* Both solve $X(t) = x$ by spline guess, at most 4 Newton steps with exit $|X(t)-x| < \min(10^{-7}, \varepsilon)$,
  then bisection with exit $|X(t)-x| < \varepsilon$ (`cubic_bezier.cc:181-237`@f842f52,
  `UnitBezier.h:111-160`@862f17d), and return $Y(t)$.

All values `Rat`; no `Float`. The IEEE double side (does `3.0*(1/3)` round to 1.0?) is checked by the
golden test `apps/site/src/parts/morph.tween/curve.golden.test.ts` (gap R8).
-/
namespace Fw.Parts.MorphTweenOpt

open Fw.Parts.MorphTween

/-! ## The cubic Bézier, two forms -/

/-- One coordinate of a cubic Bézier from 0 to 1 with inner control coordinates $a, b$ (Bernstein form).

$$\operatorname{bez}(a, b, s) = 3a\,s \cdot (1-s)^2 + 3b\,s^2 \cdot (1-s) + s^3$$

The textbook curve with end points 0 and 1. -/
def bez (a b s : Rat) : Rat := 3 * a * s * (1 - s) * (1 - s) + 3 * b * s * s * (1 - s) + s * s * s

/-- Polynomial coefficients of one axis, as both engines store them.

$$(c, b, a) \in \mathbb{Q}^3 \ \text{stands for}\ t \mapsto a t^3 + b t^2 + c t$$

The three numbers an engine keeps per axis. -/
structure Coeffs where
  /-- coefficient of $t^1$ -/
  c : Rat
  /-- coefficient of $t^2$ -/
  b : Rat
  /-- coefficient of $t^3$ -/
  a : Rat
  deriving DecidableEq, Repr

/-- The engines' coefficients of one axis from its inner control coordinates
(`cubic_bezier.cc:50-56`@f842f52, `UnitBezier.h:45-51`@862f17d).

$$\operatorname{coeffs}(p_1, p_2) = (c, b, a), \quad c = 3p_1,\quad b = 3(p_2 - p_1) - c,\quad a = 1 - c - b$$

How Chromium and WebKit set up a curve axis. -/
def coeffs (p1 p2 : Rat) : Coeffs :=
  let c := 3 * p1
  let b := 3 * (p2 - p1) - c
  ⟨c, b, 1 - c - b⟩

/-- The engines' evaluation of one axis (Horner's rule; `cubic_bezier.h:23-37`@f842f52, `UnitBezier.h:94-108`@862f17d).

$$\operatorname{horner}((c, b, a), t) = ((a t + b) t + c)\, t$$

How the engines sample a curve axis. -/
def horner (k : Coeffs) (t : Rat) : Rat := ((k.a * t + k.b) * t + k.c) * t

/-- The engines' Horner form is the Bézier curve.

$$\forall p_1, p_2, t \in \mathbb{Q}:\quad \operatorname{horner}(\operatorname{coeffs}(p_1, p_2), t) = \operatorname{bez}(p_1, p_2, t)$$

The engine's polynomial and the textbook curve agree everywhere. -/
theorem horner_eq_bez (p1 p2 t : Rat) : horner (coeffs p1 p2) t = bez p1 p2 t := by
  simp only [horner, coeffs, bez]
  grind

/-! ## The control points of the variant -/

/-- First control point, x. $$p_{1x} = \tfrac13$$ One third. -/
def p1x : Rat := 1 / 3
/-- First control point, y. $$p_{1y} = 1$$ One. -/
def p1y : Rat := 1
/-- Second control point, x. $$p_{2x} = \tfrac23$$ Two thirds. -/
def p2x : Rat := 2 / 3
/-- Second control point, y. $$p_{2y} = 1$$ One. -/
def p2y : Rat := 1

/-- The variant's timing curve, x axis. $$X(s) = \operatorname{bez}(\tfrac13, \tfrac23, s)$$ Time component of `cubic-bezier(1/3,1,2/3,1)`. -/
def curveX (s : Rat) : Rat := bez p1x p2x s

/-- The variant's timing curve, y axis. $$Y(s) = \operatorname{bez}(1, 1, s)$$ Progress component of `cubic-bezier(1/3,1,2/3,1)`. -/
def curveY (s : Rat) : Rat := bez p1y p2y s

#guard curveX (1 / 2) == 1 / 2
#guard curveY (1 / 2) == 7 / 8
#guard curveY (1 / 2) == ease (1 / 2)
#guard coeffs p1x p2x == ⟨1, 0, 0⟩
#guard coeffs p1y p2y == ⟨3, -3, 1⟩

/-- The x coefficients are exactly $(1, 0, 0)$, so the engines' x axis is the identity.

$$\operatorname{coeffs}(\tfrac13, \tfrac23) = (c_x, b_x, a_x) = (1, 0, 0)$$

The exact-arithmetic side of the fp premise R8. -/
theorem coeffs_x : coeffs p1x p2x = ⟨1, 0, 0⟩ := by
  simp only [coeffs, p1x, p2x, Coeffs.mk.injEq]
  exact ⟨by grind, by grind, by grind⟩

/-- The y coefficients are $(3, -3, 1)$, so the engines evaluate $((t-3)t+3)t$.

$$\operatorname{coeffs}(1, 1) = (c_y, b_y, a_y) = (3, -3, 1)$$

The progress polynomial the engines run. -/
theorem coeffs_y : coeffs p1y p2y = ⟨3, -3, 1⟩ := by
  simp only [coeffs, p1y, p2y, Coeffs.mk.injEq]
  exact ⟨by grind, by grind, by grind⟩

/-! ## MT1: the curve is the ease -/

/-- **MT1.** The control points $P_1 = (\tfrac13, 1)$, $P_2 = (\tfrac23, 1)$ give $X(s) = s$ and
$Y(s) = 1-(1-s)^3$ for every rational $s$ (not only in $[0,1]$).

$$\forall s \in \mathbb{Q}:\quad X(s) = s \ \wedge\ Y(s) = 3s \cdot (1-s)^2 + 3s^2 \cdot (1-s) + s^3 = 1 - (1-s)^3$$

Over the rationals the curve is the polynomial $1-(1-s)^3$ with time as its own parameter; it equals the original's clamped ease on $[0,1]$ (`curveY_eq_ease`). -/
theorem bezier_eq_ease (s : Rat) :
    curveX s = s ∧ curveY s = 1 - (1 - s) * (1 - s) * (1 - s) := by
  simp only [curveX, curveY, bez, p1x, p2x, p1y, p2y]
  constructor <;> grind

/-- **MT1, tied to `MorphTween.ease`.** On the unit interval the curve's y equals the original's ease.

$$\forall s \in \mathbb{Q},\ 0 \le s \le 1:\quad Y(s) = \operatorname{ease}(s)$$

On every progress the animation can reach, the WAAPI curve is the original's ease. -/
theorem curveY_eq_ease (s : Rat) (h0 : 0 ≤ s) (h1 : s ≤ 1) : curveY s = ease s := by
  have hc : clamp01 s = s := by unfold clamp01; grind
  rw [(bezier_eq_ease s).2]
  unfold ease
  rw [hc]

/-- **MT1 at a solver answer.** If the solver returns $t$ with $X(t) = x$ exactly and $0 \le x \le 1$, the engine
value is the ease.

$$\forall t, x \in \mathbb{Q}:\quad X(t) = x \ \wedge\ 0 \le x \le 1 \implies Y(t) = \operatorname{ease}(x)$$

An exact solve gives the original's value exactly. -/
theorem solver_exact_zero (t x : Rat) (h : curveX t = x) (hx0 : 0 ≤ x) (hx1 : x ≤ 1) :
    curveY t = ease x := by
  have ht : t = x := by rw [← (bezier_eq_ease t).1]; exact h
  subst ht
  exact curveY_eq_ease t hx0 hx1

/-! ## MT2: the solver's tolerance costs at most $3\varepsilon$ -/

/-- The y difference factors through the t difference.

$$\forall t, x \in \mathbb{Q}:\quad Y(t) - Y(x) = (t - x)\,\bigl((1-t)^2 + (1-t)(1-x) + (1-x)^2\bigr)$$

The bracket is a mean slope, bounded by 3 when $t, x \in [0,1]$ (`slope_mem`). -/
theorem curveY_sub (t x : Rat) :
    curveY t - curveY x = (t - x) * ((1 - t) * (1 - t) + (1 - t) * (1 - x) + (1 - x) * (1 - x)) := by
  rw [(bezier_eq_ease t).2, (bezier_eq_ease x).2]
  grind

/-- For $u, v \in [0,1]$, the mean slope $u^2 + uv + v^2$ lies in $[0, 3]$.

$$\forall u, v \in \mathbb{Q},\ 0 \le u \le 1,\ 0 \le v \le 1:\quad 0 \le u^2 + uv + v^2 \le 3$$

The mean slope of $1-(1-s)^3$ between two points of the unit interval is between 0 and 3. -/
theorem slope_mem (u v : Rat) (hu0 : 0 ≤ u) (hu1 : u ≤ 1) (hv0 : 0 ≤ v) (hv1 : v ≤ 1) :
    0 ≤ u * u + u * v + v * v ∧ u * u + u * v + v * v ≤ 3 := by
  have huu : u * u ≤ u * 1 := Rat.mul_le_mul_of_nonneg_left hu1 hu0
  have huv : u * v ≤ u * 1 := Rat.mul_le_mul_of_nonneg_left hv1 hu0
  have hvv : v * v ≤ v * 1 := Rat.mul_le_mul_of_nonneg_left hv1 hv0
  have h1 : 0 ≤ u * u := Rat.mul_nonneg hu0 hu0
  have h2 : 0 ≤ u * v := Rat.mul_nonneg hu0 hv0
  have h3 : 0 ≤ v * v := Rat.mul_nonneg hv0 hv0
  grind

/-- **MT2.** If the solver stops at $t \in [0,1]$ with $|X(t) - x| < \varepsilon$ for $x \in [0,1]$, the engine value
$Y(t)$ is within $3\varepsilon$ of the original's ease (the bound $|Y'| \le 3$ on $[0,1]$).

$$\forall t, x, \varepsilon \in \mathbb{Q}:\quad 0 \le t \le 1 \ \wedge\ 0 \le x \le 1 \ \wedge\ -\varepsilon < X(t) - x < \varepsilon \implies -3\varepsilon \le Y(t) - \operatorname{ease}(x) \le 3\varepsilon$$

The solver's stopping tolerance moves the eased value by at most three times that tolerance. -/
theorem solver_exact (t x ε : Rat) (ht0 : 0 ≤ t) (ht1 : t ≤ 1) (hx0 : 0 ≤ x) (hx1 : x ≤ 1)
    (hlo : -ε < curveX t - x) (hhi : curveX t - x < ε) :
    -(3 * ε) ≤ curveY t - ease x ∧ curveY t - ease x ≤ 3 * ε := by
  rw [(bezier_eq_ease t).1] at hlo hhi
  rw [← curveY_eq_ease x hx0 hx1, curveY_sub]
  have hw := slope_mem (1 - t) (1 - x) (by grind) (by grind) (by grind) (by grind)
  generalize (1 - t) * (1 - t) + (1 - t) * (1 - x) + (1 - x) * (1 - x) = w at *
  generalize t - x = d at *
  -- d·w lies between d·0 and d·3 (in the order fixed by the sign of d), and |d| < ε
  by_cases hd : 0 ≤ d
  · have h1 : d * w ≤ d * 3 := Rat.mul_le_mul_of_nonneg_left hw.2 hd
    have h2 : 0 ≤ d * w := Rat.mul_nonneg hd hw.1
    grind
  · have hd' : 0 ≤ -d := by grind
    have h1 : -d * w ≤ -d * 3 := Rat.mul_le_mul_of_nonneg_left hw.2 hd'
    have h2 : 0 ≤ -d * w := Rat.mul_nonneg hd' hw.1
    grind

end Fw.Parts.MorphTweenOpt

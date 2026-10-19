import Fw.Parts.MorphTween
import Fw.Engine
import Fw.Site.Breakpoints
import Fw.Parts.EndFlags

/-!
# morph.tween, variant `waapi`: curve, value, flags, work (MT1, MT2, MT3, MT4, MT-W)

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

MT3 (`waapi_eq_tween`): with linear interpolation (R3), the exact curve (MT1) and a timeline whose clock is the
rAF clock plus one constant `c` (R5; the start time is read from `document.timeline.currentTime`), the WAAPI value at
every frame equals `MorphTween.tween` in $\mathbb{Q}$, over every push sequence. MT4 (`flags_same_frame`): the four
flags, as discrete keyframes at the eased-progress offset, flip on the same frame as the original's strict
`>` tests, except at an exact tie $p = c$ (R3b: the engines flip at $p \ge c$). Visual (`waapi_vis`): the scene is
`VisSame E` for every env. MT-W (`waapi_work_le`): per tween frame the variant drops the script stage and keeps
every other stage, in both engine tables (a custom property animates on the main thread in both). MT-R
(`registrations_see`, `morph_scope_eq`): `--morph` and `--morph-fade` are registered inherited, so every reader below
the nav (the hosted panel included) sees the animated value and the style invalidation scope equals the original's
(the waapi arm also animates `--morph` on the platform section, whose subtree both arms already invalidate every frame
through the inherited `--morph-fade`).
Golden rows (predictions, registrations, readers): `packages/contracts/golden/parts/morph-tween-waapi.jsonl`
(`goldenJsonl`).
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

/-! ## MT3: the WAAPI value function is the tween -/

open Fw.Engine

/-- WebKit's interpolation of two numbers (R3, `AnimationUtilities.h:98-108`@862f17d).

$$\forall a, b, p \in \mathbb{Q}:\quad \operatorname{interp}_{\mathrm{wk}}(a, b, p) = a + (b - a)\,p$$

The start plus the eased share of the distance. -/
def interpWk (a b p : Rat) : Rat := a + (b - a) * p

/-- Blink's interpolation of two numbers (R3, `interpolable_value.cc:105-115`@f842f52).

$$\forall a, b, p \in \mathbb{Q}:\quad \operatorname{interp}_{\mathrm{bl}}(a, b, p) = (1 - p)\,a + p\,b$$

The weighted mean of the two ends. -/
def interpBlink (a b p : Rat) : Rat := (1 - p) * a + p * b

/-- In $\mathbb{Q}$ Blink's form equals WebKit's (in doubles they may differ in the last bit; that side is gap R8).

$$\forall a, b, p \in \mathbb{Q}:\quad (1 - p)\,a + p\,b = a + (b - a)\,p$$

Both engines interpolate a registered number linearly. -/
theorem interpBlink_eq_wk (a b p : Rat) : interpBlink a b p = interpWk a b p := by
  unfold interpBlink interpWk; grind

/-- An unregistered custom property interpolates discretely: it flips at progress $\tfrac12$ (R3).

$$\forall a, b, p \in \mathbb{Q}:\quad \operatorname{interp}_{\mathrm{disc}}(a, b, p) = \begin{cases} a & p < \tfrac12 \\ b & \text{otherwise} \end{cases}$$

Without `@property` the morph would jump half way. -/
def interpDiscrete (a b p : Rat) : Rat := if p < 1 / 2 then a else b

#guard interpDiscrete 0 1 (1 / 4) == 0 && interpWk 0 1 (1 / 4) == 1 / 4 && interpBlink 0 1 (1 / 4) == 1 / 4

/-- The discrete form is not linear, so the premise `interp_lin` needs the `@property` registration.

$$\operatorname{interp}_{\mathrm{disc}}(0, 1, \tfrac14) = 0 \ne \tfrac14 = \operatorname{interp}_{\mathrm{wk}}(0, 1, \tfrac14)$$

An unregistered `--morph` breaks MT3. -/
theorem discrete_not_linear : interpDiscrete 0 1 (1 / 4) ≠ interpWk 0 1 (1 / 4) := by
  unfold interpDiscrete interpWk; grind

/-- **The premises of MT3**, as structure fields (none is an axiom). `c` is the timeline offset: the timeline time
of a moment minus its rAF/`performance.now()` time. It is 0 in both engines (R5 CONFIRMED: Blink
`document_timeline.cc:150-157`, WebKit `DocumentTimeline.cpp:58-60`) and one constant per run under the lane's clock
shim, which fakes `performance.now()` but not `document.timeline`.

$$\mathcal{P} = (c, \iota, \tau, \mathrm{tl}, \mathrm{sr}) \text{ with } \forall a, b, p \in \mathbb{Q}:\ \iota(a, b, p) = a + (b - a)\,p;\quad \forall x \in \mathbb{Q},\ 0 \le x \le 1:\ \tau(x) = Y(x);\quad \forall R \in \mathbb{Q}:\ \mathrm{tl}(R) = R + c;\quad \forall n \in \mathbb{Q}:\ \mathrm{sr}(n) = n + c$$

Linear interpolation, the exact curve, and one clock offset shared by frames and start reads. -/
structure WaapiPremises where
  /-- the timeline offset $c$ -/
  c : Rat
  /-- the engine's number interpolation $\iota(a, b, p)$ -/
  interp : Rat → Rat → Rat → Rat
  /-- R3, registered `<number>`: linear (`interpBlink_eq_wk`) -/
  interp_lin : ∀ a b p, interp a b p = a + (b - a) * p
  /-- the effect's timing function $\tau$ -/
  timing : Rat → Rat
  /-- MT1 with an exact solve: $\tau = Y$ on $[0,1]$ (the solver error is MT2, the double side R8) -/
  timing_eq : ∀ x, 0 ≤ x → x ≤ 1 → timing x = curveY x
  /-- the timeline time of the frame whose rAF timestamp is $R$ -/
  tl : Rat → Rat
  /-- R5: frames see the timeline at their rAF time plus $c$ -/
  tl_eq : ∀ R, tl R = R + c
  /-- the start time the variant reads from `document.timeline.currentTime` at a push whose `performance.now()` is $n$ -/
  startRead : Rat → Rat
  /-- R5 in the lead's form: the read is the push time plus the same $c$ -/
  start_eq : ∀ n, startRead n = n + c

/-- The premises hold for WebKit's form with any offset $c$ (so they are consistent).

$$\forall c \in \mathbb{Q}:\quad \mathcal{P}_{\mathrm{wk}}(c) = (c, \operatorname{interp}_{\mathrm{wk}}, Y, R \mapsto R + c, n \mapsto n + c)$$

One model of the premises. -/
def premisesWk (c : Rat) : WaapiPremises :=
  ⟨c, interpWk, fun _ _ _ => rfl, curveY, fun _ _ _ => rfl, (· + c), fun _ => rfl, (· + c), fun _ => rfl⟩

/-- The premises hold for Blink's form with any offset $c$.

$$\forall c \in \mathbb{Q}:\quad \mathcal{P}_{\mathrm{bl}}(c) = (c, \operatorname{interp}_{\mathrm{bl}}, Y, R \mapsto R + c, n \mapsto n + c)$$

The other model of the premises. -/
def premisesBlink (c : Rat) : WaapiPremises :=
  ⟨c, interpBlink, interpBlink_eq_wk, curveY, fun _ _ _ => rfl, (· + c), fun _ => rfl, (· + c), fun _ => rfl⟩

/-- One WAAPI animation of `--morph`: from, to, start time on the timeline. $$(f, t, \sigma) \in \mathbb{Q}^3$$
Keyframes $f \to t$ over 680 ms from timeline time $\sigma$. -/
structure Anim where
  /-- the from keyframe -/
  f : Rat
  /-- the to keyframe -/
  t : Rat
  /-- the start time on the timeline -/
  st : Rat
deriving Repr, DecidableEq

/-- Iteration progress at timeline time $T$ with `fill: 'both'`: 0 before the start, 1 after the end.

$$\forall \sigma, T \in \mathbb{Q}:\quad \operatorname{prog}(\sigma, T) = \operatorname{clamp}_{[0,1]}\!\big((T - \sigma)/680\big)$$

The share of the 680 ms elapsed, held at the ends. -/
def progress (st T : Rat) : Rat := clamp01 ((T - st) / duration)

/-- The animated value at timeline time $T$: interpolate the keyframes at the eased progress.

$$\forall \mathcal{P},\ \forall a \in \mathrm{Anim},\ \forall T \in \mathbb{Q}:\quad \operatorname{val}_{\mathcal{P}}(a, T) = \iota\big(a.f,\ a.t,\ \tau(\operatorname{prog}(a.\sigma, T))\big)$$

What the engine writes into `--morph` on that frame. -/
def valA (P : WaapiPremises) (a : Anim) (T : Rat) : Rat := P.interp a.f a.t (P.timing (progress a.st T))

/-- Clamping twice is clamping once. $$\forall x \in \mathbb{Q}:\ \operatorname{clamp}_{[0,1]}(\operatorname{clamp}_{[0,1]}(x)) = \operatorname{clamp}_{[0,1]}(x)$$
The clamp is idempotent. -/
theorem clamp01_idem (x : Rat) : clamp01 (clamp01 x) = clamp01 x := by unfold clamp01; grind

/-- The ease clamps its argument itself. $$\forall x \in \mathbb{Q}:\ \operatorname{ease}(\operatorname{clamp}_{[0,1]}(x)) = \operatorname{ease}(x)$$
Pre-clamping changes nothing. -/
theorem ease_clamp (x : Rat) : ease (clamp01 x) = ease x := by unfold ease; rw [clamp01_idem]

/-- The tween's value in closed form: the done branch is the same formula at $\operatorname{ease} = 1$.

$$\forall f, t, e \in \mathbb{Q}:\quad \operatorname{tween}(f, t, e).v = f + (t - f)\,\operatorname{ease}(e / 680)$$

One formula for the whole tween. -/
theorem tween_value_eq (f t e : Rat) : (tween f t e).value = f + (t - f) * ease (e / duration) := by
  unfold tween
  have hm := clamp01_mem (e / duration)
  dsimp only
  split
  · have h1 : clamp01 (e / duration) = 1 := by grind
    rw [← ease_clamp, h1]; unfold ease clamp01; grind
  · simp only [ease_clamp]

/-- The eased progress of an animation started by a push at $n$, seen by the frame at $R$, is the original's ease.

$$\forall \mathcal{P},\ \forall n, R \in \mathbb{Q}:\quad \tau\big(\operatorname{prog}(\mathrm{sr}(n), \mathrm{tl}(R))\big) = \operatorname{ease}\big((R - n)/680\big)$$

The offset $c$ cancels and the curve is the ease. -/
theorem timing_progress (P : WaapiPremises) (n R : Rat) :
    P.timing (progress (P.startRead n) (P.tl R)) = ease ((R - n) / duration) := by
  unfold progress
  rw [P.tl_eq, P.start_eq]
  have he : R + P.c - (n + P.c) = R - n := by grind
  rw [he]
  have hm := clamp01_mem ((R - n) / duration)
  rw [P.timing_eq _ hm.1 hm.2, curveY_eq_ease _ hm.1 hm.2, ease_clamp]

/-- **The value function, one frame.** An animation from $f$ to $t$ started by a push at $n$ shows, on the frame at
$R$, exactly the original's tween value.

$$\forall \mathcal{P},\ \forall f, t, n, R \in \mathbb{Q}:\quad \operatorname{val}_{\mathcal{P}}\big((f, t, \mathrm{sr}(n)), \mathrm{tl}(R)\big) = \operatorname{tween}(f, t, R - n).v$$

Same push, same frame, same number. -/
theorem valA_eq (P : WaapiPremises) (f t n R : Rat) :
    valA P ⟨f, t, P.startRead n⟩ (P.tl R) = (tween f t (R - n)).value := by
  unfold valA
  rw [timing_progress, P.interp_lin, tween_value_eq]

/-- An input event: a taken push toward $g$ (reduced motion `rm`, `performance.now()` $n$), or an animation frame
with rAF timestamp $R$. $$\mathrm{Ev} = \{\mathrm{push}(g, \mathit{rm}, n) \mid g, n \in \mathbb{Q},\ \mathit{rm} \in \mathbb{B}\} \cup \{\mathrm{tick}(R) \mid R \in \mathbb{Q}\}$$
What happens to the morph over time. -/
inductive Ev where
  | push (g : Rat) (rm : Bool) (n : Rat)
  | tick (R : Rat)
deriving Repr, DecidableEq

/-- The original's step: a push is `MorphTween.push`; a frame runs the tween iff a frame was requested.

$$\operatorname{step}_o(s, \mathrm{push}(g, \mathit{rm}, n)) = \operatorname{push}(s, g, \mathit{rm}, n),\qquad \operatorname{step}_o(s, \mathrm{tick}(R)) = \begin{cases} \operatorname{frame}(s, R) & s.n \\ s & \text{otherwise} \end{cases}$$

The rAF loop of the original. -/
def stepO (s : St) : Ev → St
  | .push g rm n => push s g rm n
  | .tick R => if s.pending then frame s R else s

/-- The original's state after a list of events. $$\forall s, \forall E \in \mathrm{Ev}^{*}:\ \operatorname{run}_o(s, E) = \operatorname{foldl}(\operatorname{step}_o, s, E)$$
Replay the events. -/
def runO (s : St) (es : List Ev) : St := es.foldl stepO s

/-- The variant's script state: target, aim, the running animation (none after a reduced-motion jump), the base value
without an animation, and the value the last frame showed. $$w = (w.\mathrm{tg}, w.\mathrm{aim}, w.\mathrm{an}, w.\mathrm{base}, w.\mathrm{cur}) \in \mathbb{Q}^2 \times \mathrm{Option}(\mathrm{Anim}) \times \mathbb{Q}^2$$
No per-frame script. -/
structure VSt where
  /-- the target $w.\mathrm{tg}$ -/
  target : Rat
  /-- where the running animation aims, $w.\mathrm{aim}$ -/
  aim : Rat
  /-- the running animation $w.\mathrm{an}$ -/
  anim : Option Anim
  /-- the value without an animation $w.\mathrm{base}$ -/
  base : Rat
  /-- the value the last frame showed $w.\mathrm{cur}$ -/
  cur : Rat
deriving Repr, DecidableEq

/-- The variant at rest. $$w_0 = (0, 0, \bot, 0, 0)$$ Before any push. -/
def initV : VSt := ⟨0, 0, none, 0, 0⟩

/-- The variant's `--morph` at timeline time $T$. $$\forall \mathcal{P}, w, T:\ \operatorname{val}_{\mathcal{P}}(w, T) = \begin{cases} w.\mathrm{base} & w.\mathrm{an} = \bot \\ \operatorname{val}_{\mathcal{P}}(a, T) & w.\mathrm{an} = a \end{cases}$$
The animation's value, or the base without one. -/
def valV (P : WaapiPremises) (w : VSt) (T : Rat) : Rat :=
  match w.anim with
  | none => w.base
  | some a => valA P a T

/-- The variant's step. A push to the current target and aim is a no-op; a reduced-motion push drops the animation
and sets the value; any other push starts a new animation from the last frame's value to $g$, its start read from
the timeline. A frame only records what the engine shows (no script runs).

$$\operatorname{step}_v(w, \mathrm{push}(g, \mathit{rm}, n)) = \begin{cases} w & w.\mathrm{tg} = g \land w.\mathrm{aim} = g \\ w\{\mathrm{tg}, \mathrm{aim}, \mathrm{base}, \mathrm{cur} := g;\ \mathrm{an} := \bot\} & \text{else if } \mathit{rm} \\ w\{\mathrm{tg}, \mathrm{aim} := g;\ \mathrm{an} := (w.\mathrm{cur}, g, \mathrm{sr}(n))\} & \text{otherwise} \end{cases},\qquad \operatorname{step}_v(w, \mathrm{tick}(R)) = w\{\mathrm{cur} := \operatorname{val}_{\mathcal{P}}(w, \mathrm{tl}(R))\}$$

The TS variant's push handler, and the engine's frame. -/
def stepV (P : WaapiPremises) (w : VSt) : Ev → VSt
  | .push g rm n =>
    if w.target = g ∧ w.aim = g then w
    else if rm then { w with target := g, aim := g, anim := none, base := g, cur := g }
    else { w with target := g, aim := g, anim := some ⟨w.cur, g, P.startRead n⟩ }
  | .tick R => { w with cur := valV P w (P.tl R) }

/-- The variant's state after a list of events. $$\forall \mathcal{P}, w, E:\ \operatorname{run}_v(w, E) = \operatorname{foldl}(\operatorname{step}_v, w, E)$$
Replay the events. -/
def runV (P : WaapiPremises) (w : VSt) (es : List Ev) : VSt := es.foldl (stepV P) w

/-- Frame times never go back: every frame time is at least $\ell$ and at least the previous frame time.

$$\operatorname{mono}(\ell, [\,]) = \top,\quad \operatorname{mono}(\ell, \mathrm{push}(\ldots) :: E) = \operatorname{mono}(\ell, E),\quad \operatorname{mono}(\ell, \mathrm{tick}(R) :: E) = (\ell \le R) \land \operatorname{mono}(R, E)$$

rAF timestamps are nondecreasing; push times are free. -/
def monoB : Rat → List Ev → Bool
  | _, [] => true
  | l, .push _ _ _ :: es => monoB l es
  | l, .tick R :: es => decide (l ≤ R) && monoB R es

/-- The simulation invariant between the original $s$ and the variant $w$, with $\ell$ the last frame time.

$$\forall \mathcal{P},\ \forall \ell \in \mathbb{Q},\ \forall s \in \mathrm{St},\ \forall w \in \mathrm{VSt}:\quad \operatorname{Inv}_{\mathcal{P}}(\ell, s, w) \iff w.\mathrm{tg} = s.w \land w.\mathrm{aim} = s.a \land w.\mathrm{cur} = s.r \land \big(s.n \Rightarrow w.\mathrm{an} = (s.i, s.a, \mathrm{sr}(s.o))\big) \land \Big(\lnot s.n \Rightarrow (w.\mathrm{an} = \bot \land w.\mathrm{base} = s.r) \lor \exists f \in \mathbb{Q}:\ w.\mathrm{an} = (f, s.a, \mathrm{sr}(s.o)) \land s.r = s.a \land s.o + 680 \le \ell\Big)$$

A running tween is the running animation; a finished one has filled forwards to its target. -/
def Inv (P : WaapiPremises) (l : Rat) (s : St) (w : VSt) : Prop :=
  w.target = s.target ∧ w.aim = s.t ∧ w.cur = s.value ∧
    (s.pending = true → w.anim = some ⟨s.f, s.t, P.startRead s.start⟩) ∧
    (s.pending = false → (w.anim = none ∧ w.base = s.value) ∨
      ∃ f, w.anim = some ⟨f, s.t, P.startRead s.start⟩ ∧ s.value = s.t ∧ s.start + duration ≤ l)

/-- Both start related. $$\forall \mathcal{P},\ \forall \ell \in \mathbb{Q}:\ \operatorname{Inv}_{\mathcal{P}}(\ell, s_0, w_0)$$
Rest matches rest. -/
theorem inv_init (P : WaapiPremises) (l : Rat) : Inv P l rest initV := by
  unfold Inv rest initV; simp

/-- A push keeps the invariant.

$$\forall \mathcal{P},\ \forall \ell, s, w, g, \mathit{rm}, n:\quad \operatorname{Inv}_{\mathcal{P}}(\ell, s, w) \Rightarrow \operatorname{Inv}_{\mathcal{P}}\big(\ell,\ \operatorname{step}_o(s, \mathrm{push}(g, \mathit{rm}, n)),\ \operatorname{step}_v(w, \mathrm{push}(g, \mathit{rm}, n))\big)$$

The new animation starts where the original's tween starts. -/
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

/-- A frame at $R \ge \ell$ keeps the invariant, with $R$ the new last frame time.

$$\forall \mathcal{P},\ \forall \ell, R, s, w:\quad \operatorname{Inv}_{\mathcal{P}}(\ell, s, w) \land \ell \le R \Rightarrow \operatorname{Inv}_{\mathcal{P}}\big(R,\ \operatorname{step}_o(s, \mathrm{tick}(R)),\ \operatorname{step}_v(w, \mathrm{tick}(R))\big)$$

Each frame shows the same value. -/
theorem inv_tick (P : WaapiPremises) (l R : Rat) (s : St) (w : VSt) (h : Inv P l s w) (hl : l ≤ R) :
    Inv P R (stepO s (.tick R)) (stepV P w (.tick R)) := by
  obtain ⟨ht, ha, hc, hp, hn⟩ := h
  cases hs : s.pending
  · -- no frame requested: the original keeps its value; the animation (if any) has filled forwards
    simp only [stepO, stepV, hs, Bool.false_eq_true, ite_false]
    rcases hn hs with ⟨hnone, hb⟩ | ⟨f, hsome, hv, hd⟩
    · refine ⟨ht, ha, ?_, fun h => by simp [hs] at h, fun _ => Or.inl ⟨hnone, hb⟩⟩
      simp only [valV, hnone]; exact hb
    · refine ⟨ht, ha, ?_, fun h => by simp [hs] at h, fun _ => Or.inr ⟨f, hsome, hv, by grind⟩⟩
      simp only [valV, hsome]
      rw [valA_eq, tween_end _ _ _ (by unfold duration at hd; grind), hv]
  · -- a running tween: the frame and the animation show the same value
    have ha' := hp hs
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

/-- The invariant along any run whose frame times never go back, with the rest of the history still monotone.

$$\forall \mathcal{P},\ \forall E, \ell, s, w, E':\quad \operatorname{Inv}_{\mathcal{P}}(\ell, s, w) \land \operatorname{mono}(\ell, E \mathbin{+\!\!+} E') \Rightarrow \exists \ell' \in \mathbb{Q}:\ \operatorname{Inv}_{\mathcal{P}}\big(\ell', \operatorname{run}_o(s, E), \operatorname{run}_v(w, E)\big) \land \operatorname{mono}(\ell', E')$$

Induction over the events. -/
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

/-- **MT3 `waapi_eq_tween`.** Over every push sequence and every frame time (frames nondecreasing from any bound
$\ell$), the value the variant's animation shows equals the original tween's value, exactly in $\mathbb{Q}$, under the
premises $\mathcal{P}$ (linear interpolation, exact curve, timeline = rAF clock + $c$ for frames and start reads).

$$\forall \mathcal{P},\ \forall E \in \mathrm{Ev}^{*},\ \forall \ell \in \mathbb{Q}:\quad \operatorname{mono}(\ell, E) \Rightarrow \operatorname{run}_v(w_0, E).\mathrm{cur} = \operatorname{run}_o(s_0, E).r$$

The WAAPI animation and the rAF tween agree on every frame. -/
theorem waapi_eq_tween (P : WaapiPremises) (es : List Ev) (l : Rat) (hm : monoB l es = true) :
    (runV P initV es).cur = (runO rest es).value := by
  obtain ⟨_, h, _⟩ := inv_run P es l rest initV [] (inv_init P l) (by simpa using hm)
  exact h.2.2.1

/-- MT3 at a frame: the value the engine computes for the frame at $R$ after the events $E$.

$$\forall \mathcal{P},\ \forall E, R, \ell:\quad \operatorname{mono}(\ell, E \mathbin{+\!\!+} [\mathrm{tick}(R)]) \Rightarrow \operatorname{val}_{\mathcal{P}}\big(\operatorname{run}_v(w_0, E), \mathrm{tl}(R)\big) = \operatorname{run}_o(s_0, E \mathbin{+\!\!+} [\mathrm{tick}(R)]).r$$

The frame at $R$ shows the original's number. -/
theorem waapi_frame_eq (P : WaapiPremises) (es : List Ev) (R l : Rat) (hm : monoB l (es ++ [.tick R]) = true) :
    valV P (runV P initV es) (P.tl R) = (runO rest (es ++ [.tick R])).value := by
  have := waapi_eq_tween P (es ++ [.tick R]) l hm
  simpa [runV, List.foldl_append, stepV] using this

#guard (runV (premisesWk 0) initV [.push 1 false 100, .tick 440]).cur == (runO rest [.push 1 false 100, .tick 440]).value
#guard (runV (premisesWk 7) initV [.push 1 false 100, .tick 300, .push 0 false 350, .tick 500]).cur ==
  (runO rest [.push 1 false 100, .tick 300, .push 0 false 350, .tick 500]).value
#guard (runV (premisesBlink 3) initV [.push 1 false 0, .tick 700, .tick 900, .push 0 true 950, .tick 960]).cur == 0

/-! ## MT4: the flags flip on the same frame, except at an exact tie -/

/-- A discrete keyframe pair `[0: a, c: a, c: b, 1: b]` at eased progress $p$: both engines give $b$ iff $p \ge c$
(R3b, inclusive; Blink `keyframe_effect.cc:719,724`, WebKit the same).

$$\forall c, p \in \mathbb{Q},\ \forall a, b \in \mathbb{B}:\quad \operatorname{flip}(c, a, b, p) = \begin{cases} a & p < c \\ b & \text{otherwise} \end{cases}$$

Before the offset the first value, from the offset on the second. -/
def flipAt (c : Rat) (a b : Bool) (p : Rat) : Bool := if p < c then a else b

/-- The eased progress at which the linear value $f + (t - f)\,p$ reaches $\theta$ (in $\mathbb{Q}$, $x / 0 = 0$).

$$\forall \theta, f, t \in \mathbb{Q}:\quad \kappa(\theta, f, t) = \frac{\theta - f}{t - f}$$

Where the morph crosses the flag's threshold. -/
def kfOffset (θ f t : Rat) : Rat := (θ - f) / (t - f)

/-- The variant's flag for threshold $\theta$ on an animation from $f$ to $t$: a discrete keyframe at offset
$\operatorname{clamp}_{[0,1]}(\kappa)$ from the start's flag to the end's flag.

$$\forall \theta, f, t, p \in \mathbb{Q}:\quad \operatorname{flag}_v(\theta, f, t, p) = \operatorname{flip}\big(\operatorname{clamp}_{[0,1]}(\kappa(\theta, f, t)),\ [f > \theta],\ [t > \theta],\ p\big)$$

The flag the engine applies at eased progress $p$. -/
def flagV (θ f t p : Rat) : Bool := flipAt (clamp01 (kfOffset θ f t)) (decide (f > θ)) (decide (t > θ)) p

/-- The original's flag at eased progress $p$: the strict test on the tween's value.

$$\forall \theta, f, t, p \in \mathbb{Q}:\quad \operatorname{flag}_o(\theta, f, t, p) = [\,f + (t - f)\,p > \theta\,]$$

What the rAF loop computes. -/
def flagO (θ f t p : Rat) : Bool := decide (f + (t - f) * p > θ)

/-- Rising: the value passes $\theta$ exactly when the progress passes the offset.

$$\forall \theta, f, t, x \in \mathbb{Q}:\quad f < t \Rightarrow \big(f + (t - f)\,x > \theta \iff \kappa(\theta, f, t) < x\big)$$

Above the threshold iff past the offset. -/
theorem up_iff (θ f t x : Rat) (hd : f < t) : f + (t - f) * x > θ ↔ kfOffset θ f t < x := by
  unfold kfOffset
  rw [Rat.div_lt_iff (by grind)]
  grind

/-- Falling: the value is above $\theta$ exactly before the offset.

$$\forall \theta, f, t, x \in \mathbb{Q}:\quad t < f \Rightarrow \big(f + (t - f)\,x > \theta \iff x < \kappa(\theta, f, t)\big)$$

Above the threshold iff not yet at the offset. -/
theorem down_iff (θ f t x : Rat) (hd : t < f) : f + (t - f) * x > θ ↔ x < kfOffset θ f t := by
  unfold kfOffset
  have : (θ - f) / (t - f) = (f - θ) / (f - t) := by grind
  rw [this, Rat.lt_div_iff (by grind)]
  grind

/-- A flat animation has offset 0. $$\forall \theta, f \in \mathbb{Q}:\ \kappa(\theta, f, f) = 0$$ Division by zero is 0 in $\mathbb{Q}$. -/
theorem kfOffset_flat (θ f : Rat) : kfOffset θ f f = 0 := by unfold kfOffset; grind

/-- Rising through $\theta$, the offset lies in $[0, 1)$, so the clamp keeps it.

$$\forall \theta, f, t \in \mathbb{Q}:\quad f \le \theta < t \Rightarrow 0 \le \kappa(\theta, f, t) < 1 \land \operatorname{clamp}_{[0,1]}(\kappa(\theta, f, t)) = \kappa(\theta, f, t)$$

A crossing inside the animation. -/
theorem kfOffset_mem (θ f t : Rat) (hf : f ≤ θ) (ht : θ < t) :
    0 ≤ kfOffset θ f t ∧ kfOffset θ f t < 1 ∧ clamp01 (kfOffset θ f t) = kfOffset θ f t := by
  have h0 := up_iff θ f t 0 (by grind)
  have h1 := up_iff θ f t 1 (by grind)
  have : ¬ kfOffset θ f t < 0 := by grind
  refine ⟨by grind, by grind, ?_⟩
  unfold clamp01; grind

/-- **Below the tie** (rising through $\theta$, progress before the offset): both flags are off.

$$\forall \theta, f, t, p \in \mathbb{Q}:\quad f \le \theta < t \land p < \kappa(\theta, f, t) \Rightarrow \operatorname{flag}_v(\theta, f, t, p) = \bot \land \operatorname{flag}_o(\theta, f, t, p) = \bot$$

Strictly before the crossing nobody has flipped. -/
theorem flag_below_tie (θ f t p : Rat) (hf : f ≤ θ) (ht : θ < t) (hp : p < kfOffset θ f t) :
    flagV θ f t p = false ∧ flagO θ f t p = false := by
  have hk := kfOffset_mem θ f t hf ht
  have hu := up_iff θ f t p (by grind)
  unfold flagV flipAt flagO
  rw [hk.2.2]
  refine ⟨by simp [hp]; grind, by simp; grind⟩

/-- **The tie** (rising through $\theta$, progress exactly at the offset): the variant has flipped (R3b, $p \ge c$),
the original has not (the value equals $\theta$ and the test is strict $>$).

$$\forall \theta, f, t, p \in \mathbb{Q}:\quad f \le \theta < t \land p = \kappa(\theta, f, t) \Rightarrow \operatorname{flag}_v(\theta, f, t, p) = \top \land \operatorname{flag}_o(\theta, f, t, p) = \bot$$

The one frame where they differ. -/
theorem flag_tie (θ f t p : Rat) (hf : f ≤ θ) (ht : θ < t) (hp : p = kfOffset θ f t) :
    flagV θ f t p = true ∧ flagO θ f t p = false := by
  have hk := kfOffset_mem θ f t hf ht
  have hu := up_iff θ f t p (by grind)
  unfold flagV flipAt flagO
  rw [hk.2.2]
  refine ⟨by simp; grind, by simp; grind⟩

/-- **Above the tie** (rising through $\theta$, progress past the offset): both flags are on.

$$\forall \theta, f, t, p \in \mathbb{Q}:\quad f \le \theta < t \land \kappa(\theta, f, t) < p \Rightarrow \operatorname{flag}_v(\theta, f, t, p) = \top \land \operatorname{flag}_o(\theta, f, t, p) = \top$$

Strictly after the crossing both have flipped. -/
theorem flag_above_tie (θ f t p : Rat) (hf : f ≤ θ) (ht : θ < t) (hp : kfOffset θ f t < p) :
    flagV θ f t p = true ∧ flagO θ f t p = true := by
  have hk := kfOffset_mem θ f t hf ht
  have hu := up_iff θ f t p (by grind)
  unfold flagV flipAt flagO
  rw [hk.2.2]
  refine ⟨by simp; grind, by simp; grind⟩

/-- **MT4 `flags_same_frame`.** For eased progress $p \in [0,1]$ the variant's discrete-keyframe flag equals the
original's strict test, except at an exact tie: rising through $\theta$ ($f \le \theta < t$) with $p = \kappa$.
Falling and flat animations have no tie (at $p = \kappa$ falling, the value is $\theta$ and both are off).

$$\forall \theta, f, t, p \in \mathbb{Q}:\quad 0 \le p \le 1 \land \lnot\big(f \le \theta \land \theta < t \land p = \kappa(\theta, f, t)\big) \Rightarrow \operatorname{flag}_v(\theta, f, t, p) = \operatorname{flag}_o(\theta, f, t, p)$$

Same flag on every frame but the exact crossing frame of a rising flag. -/
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

/-- At the end of an animation the variant's flag is the target's flag.

$$\forall \theta, f, t \in \mathbb{Q}:\quad \operatorname{flag}_v(\theta, f, t, 1) = [\,t > \theta\,]$$

A finished animation fills forwards to the end keyframe. -/
theorem flagV_one (θ f t : Rat) : flagV θ f t 1 = decide (t > θ) := by
  unfold flagV flipAt
  have := clamp01_mem (kfOffset θ f t)
  have h : ¬ (1 : Rat) < clamp01 (kfOffset θ f t) := by grind
  simp only [h, ite_false]

/-- The threshold test on the ease, without the clamp (for frames of a running tween).

$$\forall \theta, x \in \mathbb{Q}:\quad 0 \le x \le 1 \Rightarrow \big(\operatorname{ease}(x) > \theta \iff (1 - x)^3 < 1 - \theta\big)$$

A flag on the eased progress is a bound on the cube. -/
theorem ease_gt_iff (θ x : Rat) (h0 : 0 ≤ x) (h1 : x ≤ 1) :
    ease x > θ ↔ (1 - x) * (1 - x) * (1 - x) < 1 - θ := by
  have : clamp01 x = x := by unfold clamp01; grind
  unfold ease; rw [this]; grind

#guard flagV (1 / 5) 0 1 (1 / 5) == true && flagO (1 / 5) 0 1 (1 / 5) == false
#guard flagV (1 / 5) 0 1 (1 / 10) == flagO (1 / 5) 0 1 (1 / 10)
#guard flagV (1 / 5) 0 1 (3 / 10) == flagO (1 / 5) 0 1 (3 / 10)
#guard flagV (1 / 5) 1 0 (4 / 5) == flagO (1 / 5) 1 0 (4 / 5)
#guard flagV (23 / 25) (1 / 2) (1 / 2) (1 / 3) == flagO (23 / 25) (1 / 2) (1 / 2) (1 / 3)

/-! ### The four flags of morph.tween -/

/-- The thresholds the original tests the morph value against, strictly: on-dark ($m > \tfrac15$, `NavHitTest.isOnDark`),
expanded ($m > \tfrac{23}{25}$), pointer-none ($\operatorname{fade}(m) < \tfrac1{20} \iff m > \tfrac{209}{400}$) and
active ($m > \tfrac1{1000}$).

$$\Theta = [\tfrac15,\ \tfrac{23}{25},\ \tfrac{209}{400},\ \tfrac1{1000}]$$

One discrete keyframe track per threshold. -/
def thresholds : List Rat := [1 / 5, 23 / 25, 209 / 400, activeCut]

/-- Pointer-none is a strict threshold flag.

$$\forall m \in \mathbb{Q}:\quad \operatorname{pointerNone}(m) = [\,m > \tfrac{209}{400}\,]$$

The fade test is a value test. -/
theorem pointerNone_eq (m : Rat) : pointerNone m = decide (m > 209 / 400) := by
  have := pointerNone_iff m
  cases h : pointerNone m <;> simp_all

/-- The fade the variant computes in CSS, `calc(1 - min(1, var(--morph) / 0.55))`, is the original's fade.

$$\forall m \in \mathbb{Q}:\quad \operatorname{fade}(m) = 1 - \min\!\big(1,\ m / 0.55\big)$$

No script needed for the fade. -/
theorem fade_css (m : Rat) : fade m = 1 - min 1 (m / (55 / 100)) := by
  unfold fade fadeEnd
  have : (55 / 100 : Rat) = 11 / 20 := by grind
  rw [this]

/-- The variant's flag for threshold $\theta$ at timeline time $T$: the reduced-motion base value's flag without an
animation, else the discrete keyframe at the animation's eased progress.

$$\forall \mathcal{P}, w, \theta, T:\quad \operatorname{flag}_{\mathcal{P}}(w, \theta, T) = \begin{cases} [\,w.\mathrm{base} > \theta\,] & w.\mathrm{an} = \bot \\ \operatorname{flag}_v\big(\theta, a.f, a.t, \tau(\operatorname{prog}(a.\sigma, T))\big) & w.\mathrm{an} = a \end{cases}$$

What the engine shows for one flag. -/
def flagW (P : WaapiPremises) (w : VSt) (θ T : Rat) : Bool :=
  match w.anim with
  | none => decide (w.base > θ)
  | some a => flagV θ a.f a.t (P.timing (progress a.st T))

/-- A tie at the frame $R$ for threshold $\theta$, read off the original's state $s$ before that frame: a running
tween rising through $\theta$ whose eased progress at $R$ is exactly the offset.

$$\forall s, \theta, R:\quad \operatorname{tie}(s, \theta, R) \iff s.n \land s.i \le \theta < s.a \land \operatorname{ease}\big((R - s.o)/680\big) = \kappa(\theta, s.i, s.a)$$

The only frames where a flag may differ. -/
def tieB (s : St) (θ R : Rat) : Bool :=
  s.pending && decide (s.f ≤ θ) && decide (θ < s.t) && decide (ease ((R - s.start) / duration) = kfOffset θ s.f s.t)

/-- **MT4 over a run.** On the frame at $R$ after the events $E$ (frames nondecreasing), when that frame is no tie
for $\theta$, the variant's flag equals the original's strict test on its value.

$$\forall \mathcal{P},\ \forall E, \ell, R, \theta:\quad \operatorname{mono}(\ell, E \mathbin{+\!\!+} [\mathrm{tick}(R)]) \land \lnot\operatorname{tie}(\operatorname{run}_o(s_0, E), \theta, R) \Rightarrow \operatorname{flag}_{\mathcal{P}}\big(\operatorname{run}_v(w_0, E), \theta, \mathrm{tl}(R)\big) = \big[\operatorname{run}_o(s_0, E \mathbin{+\!\!+} [\mathrm{tick}(R)]).r > \theta\big]$$

Same flags on every frame but a tie. -/
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

/-! ### The visual theorem -/

/-- What the morph's scene depends on: the value, the target, and the flags over $\Theta$.

$$\mathrm{View} = \mathbb{Q} \times \mathbb{Q} \times \mathbb{B}^{*}$$

The part's whole visible state. -/
structure View where
  /-- the morph value -/
  m : Rat
  /-- the target (the active flag reads it) -/
  target : Rat
  /-- one flag per threshold in $\Theta$ -/
  flags : List Bool
deriving Repr, DecidableEq

/-- The original's view at the frame $R$ after the events $E$.

$$\forall E, R:\quad \operatorname{view}_o(E, R) = \big(s.r,\ s.w,\ [\,[s.r > \theta]\,]_{\theta \in \Theta}\big)\ \text{where}\ s = \operatorname{run}_o(s_0, E \mathbin{+\!\!+} [\mathrm{tick}(R)])$$

Value, target and strict flags after the frame. -/
def viewO (es : List Ev) (R : Rat) : View :=
  let s := runO rest (es ++ [.tick R])
  ⟨s.value, s.target, thresholds.map fun θ => decide (s.value > θ)⟩

/-- The variant's view at the frame $R$ after the events $E$: the engine's animated value and discrete flags.

$$\forall \mathcal{P}, E, R:\quad \operatorname{view}_{\mathcal{P}}(E, R) = \big(\operatorname{val}_{\mathcal{P}}(w, \mathrm{tl}(R)),\ w.\mathrm{tg},\ [\,\operatorname{flag}_{\mathcal{P}}(w, \theta, \mathrm{tl}(R))\,]_{\theta \in \Theta}\big)\ \text{where}\ w = \operatorname{run}_v(w_0, E)$$

What the engine shows on that frame. -/
def viewV (P : WaapiPremises) (es : List Ev) (R : Rat) : View :=
  let w := runV P initV es
  ⟨valV P w (P.tl R), w.target, thresholds.map fun θ => flagW P w θ (P.tl R)⟩

/-- The admissible frames: events $E$, a frame at $R$ and a bound $\ell$ with frames nondecreasing from $\ell$ and no
tie at $R$ for any threshold.

$$\mathrm{Hist} = \big\{(E, R, \ell) \in \mathrm{Ev}^{*} \times \mathbb{Q}^2 \ \big|\ \operatorname{mono}(\ell, E \mathbin{+\!\!+} [\mathrm{tick}(R)]) \land \forall \theta \in \Theta:\ \lnot\operatorname{tie}(\operatorname{run}_o(s_0, E), \theta, R)\big\}$$

Every frame of every tie-free history. -/
def Hist : Type :=
  {x : List Ev × Rat × Rat // monoB x.2.2 (x.1 ++ [.tick x.2.1]) = true ∧
    thresholds.all (fun θ => !tieB (runO rest x.1) θ x.2.1) = true}

/-- The views agree on every admissible frame.

$$\forall \mathcal{P},\ \forall h = (E, R, \ell) \in \mathrm{Hist}:\quad \operatorname{view}_{\mathcal{P}}(E, R) = \operatorname{view}_o(E, R)$$

Same value, target and flags. -/
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

/-- **The visual theorem (class E-s).** For every scene function of the view, every viewport and every environment
(so every width band, both engines' layouts alike), the variant's scene equals the original's on every admissible
frame.

$$\forall \mathcal{P},\ \forall \mathit{vp} : \mathrm{Env} \to \mathrm{Rect},\ \forall S : \mathrm{Env} \times \mathrm{View} \to \mathrm{Scene}:\quad \operatorname{VisSame}_{\mathrm{E}}\Big(\mathit{vp},\ (\mathit{env}, (E, R, \ell)) \mapsto S(\mathit{env}, \operatorname{view}_o(E, R)),\ (\mathit{env}, (E, R, \ell)) \mapsto S(\mathit{env}, \operatorname{view}_{\mathcal{P}}(E, R))\Big)$$

The WAAPI variant looks exactly like the original. -/
theorem waapi_vis (P : WaapiPremises) (vp : Fw.Site.Breakpoints.Env → Rect)
    (S : Fw.Site.Breakpoints.Env → View → Scene) :
    VisSame E vp (fun env (h : Hist) => S env (viewO h.1.1 h.1.2.1)) (fun env h => S env (viewV P h.1.1 h.1.2.1)) :=
  visSame_of_eq vp fun env h => by rw [view_eq P h]

#guard viewV (premisesWk 0) [.push 1 false 100] 440 == viewO [.push 1 false 100] 440
#guard viewV (premisesBlink 5) [.push 1 false 0, .tick 100, .push 0 false 120] 400 ==
  viewO [.push 1 false 0, .tick 100, .push 0 false 120] 400

/-! ## MT-W: the variant drops the script stage and keeps every other stage -/

/-- The work relation of MT-W between a variant frame's work $v$ and the original's $o$ with $k$ callbacks: $v \prec o$,
every stage but script equal, script $0$ against one pass of $k$ units.

$$\forall v, o \in \mathrm{Work},\ \forall k \in \mathbb{N}:\quad \operatorname{drop}(v, o, k) \iff v \prec o \land \big(\forall s \ne \mathrm{script}:\ v.\mathrm{passes}(s) = o.\mathrm{passes}(s) \land v.\mathrm{units}(s) = o.\mathrm{units}(s)\big) \land v.\mathrm{passes}(\mathrm{script}) = 0 \land v.\mathrm{units}(\mathrm{script}) = 0 \land o.\mathrm{passes}(\mathrm{script}) = 1 \land o.\mathrm{units}(\mathrm{script}) = k$$

Script strictly less, style, layout, paint and commit equal. -/
def dropsScript (v o : Work) (k : Nat) : Prop :=
  v.lt o ∧ (∀ s, s ≠ Stage.script → v.passes s = o.passes s ∧ v.units s = o.units s) ∧
    v.passes .script = 0 ∧ v.units .script = 0 ∧ o.passes .script = 1 ∧ o.units .script = k

/-- **MT-W, any engine.** If no change, no compositor stage and no base stage is `script`, a frame of $k > 0$
callbacks writing the nonempty changes $C$ (with $n$ compositor animations) and the same frame without script stand
in the relation $\operatorname{drop}$.

$$\forall \mathcal{E},\ \forall C \in \mathrm{Change}^{*},\ \forall k, n \in \mathbb{N}:\quad 0 < k \land C \ne [\,] \land (\forall c \in C:\ \mathrm{script} \notin \mathcal{E}.\mathrm{stagesOf}(c)) \land \mathrm{script} \notin \mathcal{E}.\mathrm{compStages} \land \mathrm{script} \notin \mathcal{E}.\mathrm{base} \Rightarrow \operatorname{drop}\big(\operatorname{frameWork}_{\mathcal{E}}(0, 0, 0, 0, C, n),\ \operatorname{frameWork}_{\mathcal{E}}(k, 0, 0, 0, C, n),\ k\big)$$

Moving the writes from script to the engine removes exactly the script stage. -/
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

/-- Chromium: an animation with a custom property runs on the main thread, and the trace reports failure bit 13
(`kUnsupportedCSSProperty`).

$$\forall m \in \mathrm{CrMode},\ \forall a \in \mathrm{CrAnim}:\quad (\exists i, \mathit{rs}:\ \mathrm{custom}(i, \mathit{rs}) \in a.\mathrm{props}) \Rightarrow \operatorname{crThread}(m, a) = \mathrm{main} \land 13 \in \operatorname{bits}(m, a)$$

`--morph` cannot run on the compositor. -/
theorem cr_custom_main (m : Chromium.CrMode) (a : Chromium.CrAnim)
    (h : ∃ i rs, Chromium.CrProp.custom i rs ∈ a.props) :
    Chromium.crThread m a = .main ∧ 13 ∈ Chromium.failBits m a := by
  obtain ⟨i, rs, hm⟩ := h
  have hall : a.props.all Chromium.CrProp.eligible = false := by
    rw [List.all_eq_false]; exact ⟨_, hm, by simp [Chromium.CrProp.eligible]⟩
  refine ⟨?_, ?_⟩
  · simp [Chromium.crThread, hall]
  · simp [Chromium.failBits, hall]

/-- No Chromium change touches the script stage.

$$\forall c \in \mathrm{Change}(\mathrm{CrProp}):\quad \mathrm{script} \notin \operatorname{stagesOf}_{\mathrm{cr}}(c)$$

Style writes never run script. -/
theorem cr_no_script (c : Change Chromium.CrProp) : Stage.script ∉ Chromium.crStagesOf c := by
  unfold Chromium.crStagesOf
  generalize Chromium.crLevel c.prop c.layer = L
  have hL : Stage.script ∉ L.stages := by cases L <;> decide
  have hX : Stage.script ∉ c.prop.extra := by
    cases c.prop with
    | scroll r => cases r <;> decide
    | _ => simp [Chromium.CrProp.extra]
  simp only [List.mem_append, not_or]; exact ⟨hL, hX⟩

/-- **MT-W, Chromium (lane).** Main-thread animations $A$ of custom properties, against $k > 0$ callbacks writing the
same changes inline: script drops, every other stage stays.

$$\forall A \in \mathrm{CrAnim}^{*},\ \forall k \in \mathbb{N}:\quad 0 < k \land \mathop{+\!\!+}_{a \in A} \operatorname{changes}(a) \ne [\,] \land \big(\forall a \in A:\ \exists i, \mathit{rs}:\ \mathrm{custom}(i, \mathit{rs}) \in a.\mathrm{props}\big) \Rightarrow \operatorname{drop}\big(\operatorname{frameWork}_{\mathrm{chromium}}(\operatorname{animFrame}(\mathrm{lane}, A)),\ \operatorname{frameWork}_{\mathrm{chromium}}(\operatorname{jsWrite}(k, \mathop{+\!\!+}_{a \in A} \operatorname{changes}(a))),\ k\big)$$

In Chromium the WAAPI frame is the rAF frame minus its script. -/
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

/-- No WebKit diff level touches the script stage.

$$\forall d \in \mathrm{Diff}:\quad \mathrm{script} \notin \operatorname{stages}(d)$$

Style writes never run script. -/
theorem wk_no_script (d : WebKit.Diff) : Stage.script ∉ WebKit.diffStages d := by cases d <;> decide

/-- **MT-W, WebKit (Safari).** An animation with a custom property runs on the main thread (`custom_main`); its frame
writes the changes $C$, against $k > 0$ callbacks writing $C$ inline: script drops, every other stage stays.

$$\forall a \in \mathrm{WkAnim},\ \forall C \in \mathrm{Change}(\mathrm{WkProp})^{*},\ \forall k \in \mathbb{N}:\quad 0 < k \land C \ne [\,] \land \mathrm{custom} \in a.\mathrm{props} \Rightarrow \operatorname{drop}\big(\operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{animFrame}(\mathrm{safari}, a, C)),\ \operatorname{frameWork}_{\mathrm{webkit}}(k, 0, 0, 0, C, 0),\ k\big)$$

In WebKit the WAAPI frame is the rAF frame minus its script. -/
theorem waapi_work_le_webkit (a : WebKit.WkAnim) (cs : List (Change WebKit.WkProp)) (k : Nat) (hk : 0 < k)
    (hne : cs ≠ []) (hc : WebKit.CssProp.custom ∈ a.props) :
    dropsScript (frameWork WebKit.webkit (WebKit.animFrame .safari a cs)) (frameWork WebKit.webkit ⟨k, 0, 0, 0, cs, 0⟩) k := by
  have hv : WebKit.animFrame .safari a cs = ⟨0, 0, 0, 0, cs, 0⟩ := by
    simp [WebKit.animFrame, WebKit.custom_main _ a hc]
  rw [hv]
  exact script_drop _ _ k 0 hk hne (fun c _ h => by
    simp only [WebKit.webkit, WebKit.webkitAt] at h
    exact wk_no_script _ ((WebKit.mem_wkStages_of_ne c (s := .script) (by decide)).1 h)) (by decide) (by decide)

/-- **MT-W `waapi_work_le`**: both engine instances at once (the custom-property rule puts the animation on the main
thread in both, so the WAAPI frame is the rAF frame without its script).

$$\forall A, a, C, k:\quad 0 < k \land C_A \ne [\,] \land \big(\forall a' \in A:\ \exists i, \mathit{rs}:\ \mathrm{custom}(i, \mathit{rs}) \in a'.\mathrm{props}\big) \land C \ne [\,] \land \mathrm{custom} \in a.\mathrm{props} \Rightarrow \operatorname{drop}\big(W^{\mathrm{cr}}_v, W^{\mathrm{cr}}_o, k\big) \land \operatorname{drop}\big(W^{\mathrm{wk}}_v, W^{\mathrm{wk}}_o, k\big)$$
$$\text{where}\ C_A = \mathop{+\!\!+}_{a' \in A} \operatorname{changes}(a'),\ W^{\mathrm{cr}}_v = \operatorname{frameWork}_{\mathrm{chromium}}(\operatorname{animFrame}(\mathrm{lane}, A)),\ W^{\mathrm{cr}}_o = \operatorname{frameWork}_{\mathrm{chromium}}(\operatorname{jsWrite}(k, C_A)),\ W^{\mathrm{wk}}_v = \operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{animFrame}(\mathrm{safari}, a, C)),\ W^{\mathrm{wk}}_o = \operatorname{frameWork}_{\mathrm{webkit}}(k, 0, 0, 0, C, 0)$$

Script strictly less, style, layout, paint and commit equal, in both engines. -/
theorem waapi_work_le (as : List Chromium.CrAnim) (a : WebKit.WkAnim) (cs : List (Change WebKit.WkProp)) (k : Nat)
    (hk : 0 < k) (hne : as.flatMap Chromium.CrAnim.changes ≠ [])
    (hcu : ∀ a' ∈ as, ∃ i rs, Chromium.CrProp.custom i rs ∈ a'.props) (hcs : cs ≠ [])
    (hc : WebKit.CssProp.custom ∈ a.props) :
    dropsScript (frameWork Chromium.chromium (Chromium.animFrame Chromium.lane as))
        (frameWork Chromium.chromium (Chromium.jsWrite k (as.flatMap Chromium.CrAnim.changes))) k ∧
      dropsScript (frameWork WebKit.webkit (WebKit.animFrame .safari a cs))
        (frameWork WebKit.webkit ⟨k, 0, 0, 0, cs, 0⟩) k :=
  ⟨waapi_work_le_chromium as k hk hne hcu, waapi_work_le_webkit a cs k hk hcs hc⟩

/-- Over a tween of $N > 0$ frames the screen says the variant dominates.

$$\forall v, o \in \mathrm{Work},\ \forall k, N \in \mathbb{N}:\quad \operatorname{drop}(v, o, k) \land 0 < N \Rightarrow \operatorname{screen}\big(\operatorname{toRun}([o]^N),\ \operatorname{toRun}([v]^N)\big) = \operatorname{ok}(\mathrm{dominates})$$

Every frame cheaper on script, none dearer. -/
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

/-- One concrete Chromium `--morph` animation (a custom property read by `opacity` on a non-composited box), for the
guards. $$a_{\mathrm{cr}} = (0, [\mathrm{custom}(0, [\mathrm{opacity}])], \mathrm{none}, \top, \mathrm{document})$$ An instance. -/
def crMorph : Chromium.CrAnim := { elem := 0, props := [.custom 0 [.opacity]], layer := .none }

/-- One concrete WebKit `--morph` animation. $$a_{\mathrm{wk}} = \operatorname{clean}([\mathrm{custom}], \mathrm{time})$$ An instance. -/
def wkMorph : WebKit.WkAnim := .clean [.custom] .time

/-- The per-stage prediction of a variant's work $v$ against the original's $o$, first match.

$$\forall v, o, s:\quad \operatorname{pred}(v, o, s) = \begin{cases} \texttt{=o} & v.\mathrm{passes}(s) = o.\mathrm{passes}(s) \land v.\mathrm{units}(s) = o.\mathrm{units}(s) \\ \texttt{<o} & \text{else if } v.\mathrm{passes}(s) \le o.\mathrm{passes}(s) \land v.\mathrm{units}(s) \le o.\mathrm{units}(s) \\ \texttt{any} & \text{otherwise} \end{cases}$$

Equal, below, or unknown. -/
def predW (v o : Work) (s : Stage) : String :=
  if v.passes s = o.passes s ∧ v.units s = o.units s then "=o"
  else if v.passes s ≤ o.passes s ∧ v.units s ≤ o.units s then "<o"
  else "any"

/-- The prediction MT-W gives each stage. $$\forall s:\ \operatorname{pred}_{\mathrm{MT}}(s) = \begin{cases} \texttt{<o} & s = \mathrm{script} \\ \texttt{=o} & \text{otherwise} \end{cases}$$
Script below, the rest equal. -/
def predStage (s : Stage) : String := if s = .script then "<o" else "=o"

/-- The golden predictions follow from MT-W for every instance.

$$\forall v, o, k, s:\quad \operatorname{drop}(v, o, k) \Rightarrow \operatorname{pred}(v, o, s) = \operatorname{pred}_{\mathrm{MT}}(s)$$

The rows are what the theorem says. -/
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

/-! ## MT-R: the registration of the animated properties

`CSS.registerProperty` fixes whether an animated custom property reaches the descendants of the element that animates
it. CSS model, restated from the pinned sources: a registered property with `inherits` and every unregistered custom
property are inherited (Chromium `css/properties/longhands/custom_property.cc:22-23`@f842f52, WebKit
`style/StyleBuilder.cpp:103-106`@862f17d); on a child without its own declaration an inherited property takes the
parent's computed value and a non-inherited one its initial value (WebKit `style/StyleBuilder.cpp:496-505`@862f17d).
Inherited custom values live in the inherited style data (Chromium `style/computed_style.h:3705-3712`@f842f52, WebKit
`StyleInheritedRareData.h:153` against `StyleNonInheritedRareData.h:162`@862f17d), and a change there propagates the
style recalc to the children (Chromium `style/computed_style.cc:472-478`@f842f52, `kInherited` /
`kIndependentInherited`; WebKit `style/StyleChange.cpp:42-43` with `StyleComputedStyle.cpp:296`@862f17d,
`Change::Inherited`). The original writes `--morph` and `--morph-fade` unregistered, so inherited. -/

/-- The value an element at depth $d$ below the animated element $e$ computes for a property whose value on $e$ is $a$
and whose initial value is $i$, when no element below $e$ on the path to it declares the property: $e$ itself has
$a$; a child inherits its parent's value if the property is inherited, else takes $i$.

$$\forall h \in \mathbb{B},\ \forall a, i \in \mathbb{Q}:\quad \operatorname{seen}(h, a, i, 0) = a,\qquad \forall d \in \mathbb{N}:\ \operatorname{seen}(h, a, i, d + 1) = \begin{cases} \operatorname{seen}(h, a, i, d) & h \\ i & \lnot h \end{cases}$$

What a reader $d$ levels down sees. -/
def seenAt (inh : Bool) (a i : Rat) : Nat → Rat
  | 0 => a
  | d + 1 => if inh then seenAt inh a i d else i

/-- An inherited property reaches every depth.

$$\forall a, i \in \mathbb{Q},\ \forall d \in \mathbb{N}:\quad \operatorname{seen}(\top, a, i, d) = a$$

Inheritance carries the animated value down. -/
theorem seenAt_true (a i : Rat) (d : Nat) : seenAt true a i d = a := by
  induction d with
  | zero => rfl
  | succ d ih => simp [seenAt, ih]

/-- A non-inherited property is the initial value on every strict descendant.

$$\forall a, i \in \mathbb{Q},\ \forall d \in \mathbb{N}:\quad \operatorname{seen}(\bot, a, i, d + 1) = i$$

Without inheritance a child never sees the animation. -/
theorem seenAt_false_succ (a i : Rat) (d : Nat) : seenAt false a i (d + 1) = i := rfl

/-- A reader of an animated property: a CSS rule that substitutes `var(prop)` on an element (CSS-module class `sel`)
at depth `depth` below the element the variant animates. The depths are entered by hand and not checked against the
DOM.

$$\mathrm{Reader} = \mathrm{String} \times \mathrm{String} \times \mathbb{N} \ni (\mathit{prop}, \mathit{sel}, \mathit{depth})$$

One place that reads the value. -/
structure Reader where
  /-- the custom property read -/
  prop : String
  /-- the CSS-module class of the reading element -/
  sel : String
  /-- the reading element's depth below the animated element (0: the element itself) -/
  depth : Nat
deriving Repr, DecidableEq

/-- Every reader of the animated properties in the rewrite (`nav.module.css`, `morph.module.css`, and the platform's
inline `--morph-fade`, `fade_css`). The nav animates `--morph`: the `header.nav` itself, `.bar > .logo`,
`.bar > .actions`, `.bar > .actions > .btn.earn`, and the hosted `.panel`, its child. The platform section animates
its own `--morph`, reads it in its inline `--morph-fade`, and reads `--morph-fade` itself (`platform.module.css`).
No CSS reads the two flags.

$$\mathrm{readers} = [(\texttt{--morph}, \texttt{nav}, 0), (\texttt{--morph}, \texttt{logo}, 2), (\texttt{--morph}, \texttt{actions}, 2), (\texttt{--morph}, \texttt{earn}, 3), (\texttt{--morph}, \texttt{panel}, 1), (\texttt{--morph}, \texttt{section}, 0), (\texttt{--morph-fade}, \texttt{section}, 0)]$$

Where the animated properties are read. -/
def readers : List Reader :=
  [⟨"--morph", "nav", 0⟩, ⟨"--morph", "logo", 2⟩, ⟨"--morph", "actions", 2⟩, ⟨"--morph", "earn", 3⟩,
   ⟨"--morph", "panel", 1⟩, ⟨"--morph", "section", 0⟩, ⟨"--morph-fade", "section", 0⟩]

/-- The reader depths of the property $p$, in list order (empty for a property nothing reads).

$$\forall p:\quad \operatorname{depths}(p) = [\,r.\mathit{depth} \mid r \leftarrow \mathrm{readers},\ r.\mathit{prop} = p\,]$$

How deep each reader of $p$ sits. -/
def readersOf (p : String) : List Nat := (readers.filter (·.prop == p)).map (·.depth)

/-- A property needs `inherits` iff one of its readers is a strict descendant (false for no readers).

$$\forall D \in \mathbb{N}^{*}:\quad \operatorname{need}(D) \iff \exists d \in D:\ 0 < d$$

The registration rule. -/
def needsInherit (ds : List Nat) : Bool := ds.any (0 < ·)

#guard needsInherit (readersOf "--morph") && !needsInherit (readersOf "--fw-morph-dark")
#guard !needsInherit [] && !needsInherit [0, 0] && needsInherit [0, 1]

/-- Every reader sees every animated value iff the property is inherited or no reader is a strict descendant.

$$\forall h \in \mathbb{B},\ \forall i \in \mathbb{Q},\ \forall D \in \mathbb{N}^{*}:\quad \big(\forall a \in \mathbb{Q},\ \forall d \in D:\ \operatorname{seen}(h, a, i, d) = a\big) \iff \big(h \lor \lnot\operatorname{need}(D)\big)$$

`inherits` is needed exactly when a descendant reads. -/
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

/-- A `CSS.registerProperty` descriptor.

$$\mathrm{Registration} = \mathrm{String} \times \mathrm{String} \times \mathbb{B} \times \mathrm{String} \ni (\mathit{name}, \mathit{syntax}, \mathit{inherits}, \mathit{initialValue})$$

One registration call. -/
structure Registration where
  /-- the custom property -/
  name : String
  /-- its syntax -/
  syntaxStr : String
  /-- whether it inherits -/
  inherits : Bool
  /-- its initial value -/
  initialValue : String
deriving Repr, DecidableEq

/-- Whether the original has the property $p$ as an inherited custom property: `--morph` and `--morph-fade` are
written there unregistered, so inherited (Chromium `custom_property.cc:22-23`@f842f52, WebKit
`StyleBuilder.cpp:103-106`@862f17d); the flags are classes there, and any other name is absent.

$$\forall p:\quad h_o(p) \iff p \in \{\texttt{--morph}, \texttt{--morph-fade}\}$$

The original's inheritance bit per property. -/
def origInheritsOf (p : String) : Bool := p == "--morph" || p == "--morph-fade"

/-- The registrations of the variant: `--morph` inherited (the nav's descendants and the hosted panel read it),
`--morph-fade` inherited (as in the original, so the same elements recompute; registered so that its computed value
is a number, `1` at rest, as the original's), the two flags not inherited (nothing reads them below the nav). All
`<number>`; initial value `0`, `--morph-fade` `1` (its value at rest).

$$\mathrm{regs} = [(\texttt{--morph}, \texttt{<number>}, \top, \texttt{0}), (\texttt{--morph-fade}, \texttt{<number>}, \top, \texttt{1}), (\texttt{--fw-morph-dark}, \texttt{<number>}, \bot, \texttt{0}), (\texttt{--fw-morph-expanded}, \texttt{<number>}, \bot, \texttt{0})]$$

What `index.tsx` passes to `CSS.registerProperty`. -/
def registrations : List Registration :=
  [⟨"--morph", "<number>", true, "0"⟩, ⟨"--morph-fade", "<number>", true, "1"⟩,
   ⟨"--fw-morph-dark", "<number>", false, "0"⟩, ⟨"--fw-morph-expanded", "<number>", false, "0"⟩]

/-- Each registration inherits exactly when a reader sits below the element that sets it or the original's property
inherits.

$$\forall r \in \mathrm{regs}:\quad r.\mathit{inherits} = \big(\operatorname{need}(\operatorname{depths}(r.\mathit{name})) \lor h_o(r.\mathit{name})\big)$$

No property inherits without a reason, none lacks it with one. -/
theorem registrations_rule :
    ∀ r ∈ registrations, r.inherits = (needsInherit (readersOf r.name) || origInheritsOf r.name) := by decide

/-- **MT-R, visual.** Under the variant's registrations every reader of every registered property sees the animated
value, whatever the value and the initial value; so the view of `waapi_vis` is what each reader renders, the hosted
panel included.

$$\forall r \in \mathrm{regs},\ \forall a, i \in \mathbb{Q},\ \forall d \in \operatorname{depths}(r.\mathit{name}):\quad \operatorname{seen}(r.\mathit{inherits}, a, i, d) = a$$

Every reader sees the animation. -/
theorem registrations_see :
    ∀ r ∈ registrations, ∀ a i : Rat, ∀ d ∈ readersOf r.name, seenAt r.inherits a i d = a := by
  intro r hr a i d hd
  refine (sees_iff r.inherits i (readersOf r.name)).2 ?_ a d hd
  rw [registrations_rule r hr]
  cases needsInherit (readersOf r.name) <;> cases origInheritsOf r.name <;> simp

/-- **MT-R, the finding.** Registered with `inherits` false, `--morph` leaves the hosted panel (depth 1) at its
initial value while the nav animates any other value.

$$\forall a, i \in \mathbb{Q}:\quad a \ne i \Rightarrow (\texttt{--morph}, \texttt{panel}, 1) \in \mathrm{readers} \land \operatorname{seen}(\bot, a, i, 1) \ne a$$

`inherits: false` makes the panel blind. -/
theorem panel_blind_without_inherit (a i : Rat) (h : a ≠ i) :
    (⟨"--morph", "panel", 1⟩ : Reader) ∈ readers ∧ seenAt false a i 1 ≠ a :=
  ⟨by decide, fun e => h (by rw [seenAt_false_succ] at e; exact e.symm)⟩

/-- The variant's inheritance bit of the property $p$: that of its registration, $\bot$ if it has none.

$$\forall p:\quad h_v(p) = \begin{cases} g.\mathit{inherits} & g \text{ the first } r \in \mathrm{regs} \text{ with } r.\mathit{name} = p \\ \bot & \text{no such } r \end{cases}$$

The variant's inheritance bit per property. -/
def regInherits (p : String) : Bool := ((registrations.find? (·.name == p)).map (·.inherits)).getD false

/-- Whether an element at depth $d$ recomputes its style when the animated value changes: the animated element
always, a descendant iff the property is inherited (the inherited-data change of the section note).

$$\forall h \in \mathbb{B},\ \forall d \in \mathbb{N}:\quad \operatorname{recalc}(h, d) \iff d = 0 \lor h$$

Which elements a value change invalidates. -/
def recalcs (inh : Bool) (d : Nat) : Bool := d == 0 || inh

/-- **MT-R, work.** For every property the original has as an inherited custom property (`--morph`, `--morph-fade`),
the variant's registration inherits too, so its per-frame style changes cover exactly the original's elements in
every subtree and every element sees the same value as in the original: `waapi_work_le` applies with one change list
$C$ for both arms. With `inherits` false the variant would change fewer elements than the original on any subtree
with a strict descendant: a smaller style count bought by a wrong picture. The waapi arm also animates `--morph` on the
platform section, where the original writes only `--morph-fade`; both arms already invalidate that section's subtree
every frame through the inherited `--morph-fade` it sets (Chromium `style/computed_style.cc:472-475`@f842f52: a change
to an inherited variable on an element with a `var()` reference gives `kInherited`), so the extra property adds no
element to the recalc set.

$$\Big(\forall p,\ \forall D \in \mathbb{N}^{*},\ \forall a, i \in \mathbb{Q},\ \forall d \in \mathbb{N}:\quad h_o(p) \Rightarrow \operatorname{filter}(\operatorname{recalc}(h_v(p)), D) = \operatorname{filter}(\operatorname{recalc}(h_o(p)), D) \land \operatorname{seen}(h_v(p), a, i, d) = \operatorname{seen}(h_o(p), a, i, d)\Big)$$
$$\land\ \Big(\forall D \in \mathbb{N}^{*}:\quad \operatorname{need}(D) \Rightarrow \operatorname{filter}(\operatorname{recalc}(\bot), D) \ne \operatorname{filter}(\operatorname{recalc}(\top), D)\Big)$$

Same invalidation as the original; the work claim keeps its premise. -/
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

/-- One registration as compact JSON (keys sorted by `Json.mkObj`).

$$\forall r:\ \operatorname{json}(r) = \{\texttt{inherits}, \texttt{initialValue}, \texttt{name}, \texttt{syntax}\} \text{ of } r$$

The wire form. -/
def Registration.json (r : Registration) : String :=
  (Lean.Json.mkObj [("name", .str r.name), ("syntax", .str r.syntaxStr), ("inherits", .bool r.inherits),
    ("initialValue", .str r.initialValue)]).compress

/-- One reader as compact JSON (keys sorted by `Json.mkObj`).

$$\forall r:\ \operatorname{json}(r) = \{\texttt{depth}, \texttt{prop}, \texttt{sel}\} \text{ of } r$$

The wire form. -/
def Reader.json (r : Reader) : String :=
  (Lean.Json.mkObj [("prop", .str r.prop), ("sel", .str r.sel), ("depth", (r.depth : Lean.Json))]).compress

#guard registrations.head?.map Registration.json ==
  some "{\"inherits\":true,\"initialValue\":\"0\",\"name\":\"--morph\",\"syntax\":\"<number>\"}"
#guard readers.head?.map Reader.json == some "{\"depth\":0,\"prop\":\"--morph\",\"sel\":\"nav\"}"

/-! ## Profiles: pushes come only from wheel and touchmove -/

/-- How a measurement profile scrolls (`packages/measure-chromium/profiles/*.json`, `input.mode`). -/
inductive Mode where
  | scroll
  | wheel
  | touch
deriving Repr, DecidableEq

/-- The input mode of a profile id; a profile without `input` scrolls with `scrollTo`. -/
def modeOf : String → Mode
  | "swipe-touch-v1" => .touch
  | "swipe-wheel-v1" => .wheel
  | _ => .scroll

/-- One input a profile sends; `wheel` and `touchmove` carry the push the driver takes from them. -/
inductive Input where
  | scrollTo
  | wheel (g : Rat) (rm : Bool) (n : Rat)
  | touchmove (g : Rat) (rm : Bool) (n : Rat)
  | frame (R : Rat)
deriving Repr, DecidableEq

/-- Whether a profile of mode `m` can send input `x`. -/
def Input.sentBy : Mode → Input → Bool
  | _, .frame _ => true
  | .scroll, .scrollTo => true
  | .wheel, .wheel .. => true
  | .touch, .touchmove .. => true
  | _, _ => false

/-- The events the driver feeds the tween; only `wheel` and `touchmove` push (morph.tween/driver.ts:89-91). -/
def drive : Input → List Ev
  | .scrollTo => []
  | .wheel g rm n => [.push g rm n]
  | .touchmove g rm n => [.push g rm n]
  | .frame R => [.tick R]

/-- Whether a profile mode can push the morph. -/
def pushes (m : Mode) : Bool := m != .scroll

/-- Whether an event list holds no push. -/
def noPushB (es : List Ev) : Bool := es.all fun | .push .. => false | .tick _ => true

/-- Per frame of a run of the original from `s`: whether that frame runs the tween. -/
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

/-- A scroll-mode profile sends no push. -/
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

/-- Without a push the original never runs a tween frame. -/
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

/-- Without a push the waapi arm starts no animation, so it adds no composite-failure bit. -/
theorem anim_noPush (P : WaapiPremises) (w : VSt) (es : List Ev) (hw : w.anim = none) (h : noPushB es = true) :
    (runV P w es).anim = none := by
  induction es generalizing w with
  | nil => exact hw
  | cons e es ih =>
    cases e with
    | push g rm n => simp [noPushB] at h
    | tick R => exact ih _ (by simpa [stepV] using hw) (by simpa [noPushB] using h)

/-- **No push, `=o`.** On a scroll-mode profile both arms fire the same animation frames and the waapi arm starts
no animation. -/
theorem noPush_eqO (P : WaapiPremises) (xs : List Input) (h : ∀ x ∈ xs, Input.sentBy .scroll x = true)
    (cbs : List Nat) :
    Chromium.rafSeries (cbs.zip (tweenFlags rest (xs.flatMap drive))) false =
        Chromium.rafSeries (cbs.zip (tweenFlags rest (xs.flatMap drive))) true ∧
      (runV P initV (xs.flatMap drive)).anim = none := by
  have hn := noPush_scroll xs h
  refine ⟨(Chromium.waapi_raf_eq_iff _).2 fun x hx => ?_, anim_noPush P initV _ rfl hn⟩
  exact tweenFlags_noPush rest _ rfl hn x.2 (List.of_mem_zip hx).2

/-- The original fires one more animation frame callback than the waapi arm per tween frame. -/
theorem raf_sum_eq (fs : List (Nat × Bool)) :
    (Chromium.rafSeries fs true).sum = (Chromium.rafSeries fs false).sum + (fs.filter (·.2)).length := by
  induction fs with
  | nil => rfl
  | cons y ys ih =>
    simp only [Chromium.rafSeries, List.map_cons, List.sum_cons, List.filter_cons] at ih ⊢
    simp at ih ⊢; cases y.2 <;> simp <;> omega

/-- A run with a tween frame costs the original more animation frame callbacks than the waapi arm. -/
theorem raf_sum_lt (fs : List (Nat × Bool)) (h : ∃ x ∈ fs, x.2 = true) :
    (Chromium.rafSeries fs false).sum < (Chromium.rafSeries fs true).sum := by
  obtain ⟨x, hx, hx2⟩ := h
  have : 0 < (fs.filter (·.2)).length := List.length_pos_of_mem (List.mem_filter.2 ⟨hx, by simpa using hx2⟩)
  rw [raf_sum_eq]
  omega

/-- A taken push to a new target with full motion makes the next frame a tween frame. -/
theorem tween_of_push (s : St) (g n R : Rat) (es : List Ev) (hg : s.target ≠ g) :
    tweenFlags s (.push g false n :: .tick R :: es) = true :: tweenFlags (frame (push s g false n) R) es := by
  simp [tweenFlags, push, hg, stepO]

/-- The prediction for stage `s` on a profile of mode `m`: MT-W's when the profile pushes, `=o` otherwise. -/
def predProfile (m : Mode) (s : Stage) : String := if pushes m then predStage s else "=o"

/-- The bit-13 row's prediction (rewrite against waapi): `<o` when the profile pushes, `=o` otherwise. -/
def compPred (m : Mode) : String := if pushes m then "<o" else "=o"

/-- A pushing profile takes MT-W's prediction. -/
theorem predProfile_push (m : Mode) (h : pushes m = true) (s : Stage) : predProfile m s = predStage s := by
  simp [predProfile, h]

/-- A profile without pushes predicts `=o` everywhere. -/
theorem predProfile_noPush (m : Mode) (h : pushes m = false) (s : Stage) :
    predProfile m s = "=o" ∧ compPred m = "=o" := by
  simp [predProfile, compPred, h]

#guard (Stage.all.map (predProfile .scroll)).all (· == "=o")
#guard Stage.all.map (predProfile .touch) == Stage.all.map predStage
#guard compPred .touch == "<o" && compPred .scroll == "=o"

/-! ## Start read on the frame grid (touch arm finding) -/

/-- A start read that equals the push time once and lags it once fits no constant offset, so R5's `start_eq` fails. -/
theorem start_eq_refuted (sr : Rat → Rat) (n₁ n₂ : Rat) (h₁ : sr n₁ = n₁) (h₂ : sr n₂ < n₂) :
    ¬ ∃ c : Rat, ∀ n, sr n = n + c := by
  rintro ⟨c, hc⟩
  rw [hc] at h₁ h₂
  grind

/-- A start that leads the push by less than one frame puts the variant's elapsed time strictly between the original's at the same frame and at the next. -/
theorem lead_within_frame (n δ R p : Rat) (hδ : 0 < δ) (hp : δ < p) :
    R - n < R - (n - δ) ∧ R - (n - δ) < (R + p) - n := by
  constructor <;> grind

/-! ## Golden prediction rows (engine-check schema) -/

/-- One engine-check prediction row (`apps/runner/src/engine-check.ts`), with an explicit base arm.

$$\mathrm{PredRow} = \mathrm{String}^{7} \ni (\mathit{engine}, \mathit{scenario}, \mathit{variant}, \mathit{stage}, \mathit{prediction}, \mathit{countType}, \mathit{base})$$

A line of the golden file. -/
structure PredRow where
  /-- engine id -/
  engine : String
  /-- scenario id -/
  scenario : String
  /-- the variant arm -/
  variant : String
  /-- the model stage -/
  stage : String
  /-- the prediction against the base -/
  prediction : String
  /-- the measured count type -/
  countType : String
  /-- the base arm -/
  base : String
deriving Repr, DecidableEq

/-- The variant arm: the rewrite with the flag `morph.tween:waapi`. $$\mathit{arm}_v = \texttt{rewrite+?fw=morph.tween:waapi}$$ The arm name. -/
def armV : String := "rewrite+?fw=morph.tween:waapi"

/-- The counted stages per engine and their count types (Chromium trace names, WebKit Simulator names).

$$\operatorname{counts}(\texttt{chromium}) = [(\mathrm{script}, \texttt{trace.FireAnimationFrame}), (\mathrm{style}, \texttt{trace.UpdateLayoutTree}), (\mathrm{layout}, \texttt{trace.Layout}), (\mathrm{paint}, \texttt{trace.Paint}), (\mathrm{commit}, \texttt{trace.cc.Commit})]$$
$$\operatorname{counts}(\texttt{webkit}) = [(\mathrm{script}, \texttt{FireAnimationFrame}), (\mathrm{style}, \texttt{RecalculateStyles}), (\mathrm{layout}, \texttt{Layout}), (\mathrm{paint}, \texttt{Paint}), (\mathrm{commit}, \texttt{Composite})]$$
$$\operatorname{counts}(x) = [\,] \text{ for any other } x$$

Which count measures which stage. -/
def countsOf : String → List (Stage × String)
  | "chromium" => [(.script, "trace.FireAnimationFrame"), (.style, "trace.UpdateLayoutTree"), (.layout, "trace.Layout"),
      (.paint, "trace.Paint"), (.commit, "trace.cc.Commit")]
  | "webkit" => [(.script, "FireAnimationFrame"), (.style, "RecalculateStyles"), (.layout, "Layout"),
      (.paint, "Paint"), (.commit, "Composite")]
  | _ => []

/-- The golden rows of profile `sc`: per engine and counted stage `predProfile`, plus Chromium's bit-13 row. -/
def rowsFor (sc : String) : List PredRow :=
  (["chromium", "webkit"].flatMap fun e => (countsOf e).map fun (s, k) =>
    ⟨e, sc, armV, WebKit.stageName s, predProfile (modeOf sc) s, k, "rewrite"⟩) ++
  [⟨"chromium", sc, "rewrite", "comp", compPred (modeOf sc), "trace.Animation.compositeFailedBits", armV⟩]

/-- The golden rows on the touch swipe, the profile that pushes. -/
def goldenRows : List PredRow := rowsFor "swipe-touch-v1"

/-- The golden rows on the scripted swipe, which never pushes. -/
def swipeRows : List PredRow := rowsFor "swipe-v1"

/-- Every scripted-swipe row is `=o`. -/
theorem swipeRows_eqO : ∀ r ∈ swipeRows, r.prediction = "=o" := by decide

/-- One row as compact JSON (keys sorted by `Json.mkObj`).

$$\forall r:\ \operatorname{json}(r) = \{\texttt{base}, \texttt{countType}, \texttt{engine}, \texttt{prediction}, \texttt{scenario}, \texttt{stage}, \texttt{variant}\} \text{ of } r$$

The wire form. -/
def PredRow.json (r : PredRow) : String :=
  (Lean.Json.mkObj [("engine", .str r.engine), ("scenario", .str r.scenario), ("variant", .str r.variant),
    ("stage", .str r.stage), ("prediction", .str r.prediction), ("countType", .str r.countType),
    ("base", .str r.base)]).compress

/-- The contents of `packages/contracts/golden/parts/morph-tween-waapi.jsonl`.

$$\mathrm{goldenJsonl} = \mathop{\Vert}_{r \in \mathrm{rows}} \big(\operatorname{json}(r) \mathbin{+\!\!+} \texttt{\textbackslash n}\big) \mathbin{\Vert} \mathop{\Vert}_{g \in \mathrm{regs}} \big(\operatorname{json}(g) \mathbin{+\!\!+} \texttt{\textbackslash n}\big) \mathbin{\Vert} \mathop{\Vert}_{q \in \mathrm{readers}} \big(\operatorname{json}(q) \mathbin{+\!\!+} \texttt{\textbackslash n}\big)$$

The golden file: the eleven predictions, then the four registrations, then the seven readers. -/
def goldenJsonl : String :=
  String.join (goldenRows.map fun r => r.json ++ "\n") ++ String.join (registrations.map fun r => r.json ++ "\n") ++
    String.join (readers.map fun r => r.json ++ "\n")

#guard goldenJsonl == include_str "../../../packages/contracts/golden/parts/morph-tween-waapi.jsonl"

/-- The contents of `packages/contracts/golden/parts/morph-tween-waapi.swipe-v1.jsonl`. -/
def swipeJsonl : String := String.join (swipeRows.map fun r => r.json ++ "\n")

#guard swipeJsonl == include_str "../../../packages/contracts/golden/parts/morph-tween-waapi.swipe-v1.jsonl"
#guard swipeRows.length == 11
#guard goldenRows.length == 11
#guard (goldenRows.filter fun r => r.prediction == "<o").length == 3
#guard goldenRows.head?.map PredRow.json ==
  some "{\"base\":\"rewrite\",\"countType\":\"trace.FireAnimationFrame\",\"engine\":\"chromium\",\"prediction\":\"<o\",\"scenario\":\"swipe-touch-v1\",\"stage\":\"script\",\"variant\":\"rewrite+?fw=morph.tween:waapi\"}"

/-! ## Under the frame-end pass (`frameWorkE`, ledger n=1)

The WAAPI frame and the rAF frame only write (no layout or style read), so every stage they touch ends dirty and
`frameWorkE` equals `frameWork` (`Fw.Parts.EndFlags.frameWorkE_eq_of_dirty`). The verdict carries over. -/

section EndPass

open Fw.Parts.EndFlags

/-- **MT-W under `frameWorkE`.** For end flags dirty on every touched stage, the WAAPI frame still drops the script
and keeps every other stage equal, in both engines.

$$\forall A, a, C, k,\ \forall e_1, e_2, e_3, e_4:\ \text{hyp.\ of } \texttt{waapi\_work\_le} \land \big(\forall i,\ \forall s \in \operatorname{touched}(F_i):\ e_i(s) = \top\big) \Rightarrow \operatorname{drop}\big(W^{e_1}(F_1), W^{e_2}(F_2), k\big) \land \operatorname{drop}\big(W^{e_3}(F_3), W^{e_4}(F_4), k\big)$$
$$\text{where}\ F_1 = \operatorname{animFrame}_{\mathrm{cr}}(\mathrm{lane}, A),\ F_2 = \operatorname{jsWrite}(k, C_A),\ F_3 = \operatorname{animFrame}_{\mathrm{wk}}(\mathrm{safari}, a, C),\ F_4 = (k, 0, 0, 0, C, 0)$$

The frame-end pass changes nothing on frames without reads. -/
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

end Fw.Parts.MorphTweenOpt

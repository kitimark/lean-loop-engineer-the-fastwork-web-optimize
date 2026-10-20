import Fw.Parts.MorphTween
import Fw.Engine
import Fw.Site.Breakpoints
import Fw.Parts.EndFlags
import Fw.Parts.Nav
import Fw.Parts.MorphPanel
import Fw.Parts.NavHitTest

/-!
# morph.tween, variant `waapi`: curve, value, flags, work (MT1, MT2, MT3, MT4, MT-W)

The WAAPI variant of morph.tween runs the tween as a CSS animation with the timing function
`cubic-bezier(1/3, 1, 2/3, 1)`. This module proves that this curve *is* the original's ease
`1-(1-s)^3` (MT1), and bounds what the engines' numeric solver can change (MT2).
Design: `research/notes/2026/10-18-engine-proof-design.md` §0 and §4.1.

Engine model, restated (not copied) from the pinned sources:

* Chromium `ui/gfx/geometry/cubic_bezier.cc:50-56`@f842f52 and WebKit
  `Source/WebCore/platform/graphics/UnitBezier.h:45-51`@862f17d build the coefficients
  `c = 3p_1`, `b = 3(p_2-p_1) - c`, `a = 1 - c - b` for each axis and evaluate
  `((a t + b) t + c) t` (Horner; `cubic_bezier.h:23-37`@f842f52, `UnitBezier.h:94-108`@862f17d).
* Both solve `X(t) = x` by spline guess, at most 4 Newton steps with exit `|X(t)-x| < min(10^(-7), ε)`,
  then bisection with exit `|X(t)-x| < ε` (`cubic_bezier.cc:181-237`@f842f52,
  `UnitBezier.h:111-160`@862f17d), and return `Y(t)`.

All values `Rat`; no `Float`. The IEEE double side (does `3.0*(1/3)` round to 1.0?) is checked by the
golden test `apps/site/src/parts/morph.tween/curve.golden.test.ts` (gap R8).

MT3 (`waapi_eq_tween`): with linear interpolation (R3), the exact curve (MT1) and a timeline whose clock is the
rAF clock plus one constant `c` (R5; the start time is read from `document.timeline.currentTime`), the WAAPI value at
every frame equals `MorphTween.tween` in `ℚ`, over every push sequence. MT4 (`flags_same_frame`): the four
flags, as discrete keyframes at the eased-progress offset, flip on the same frame as the original's strict
`>` tests, except at an exact tie `p = c` (R3b: the engines flip at `p ≥ c`). Visual (`waapi_vis`): the frame's
view (value, target, flags) and the readers of the written `data-fw-morph` are `VisSame E` for every env; CSS
transitions started by the `is-morphing` flip are outside the view (their start is the base style of the frame before;
section WidthTail). MT-W (`waapi_work_le`): per tween frame the variant drops the script stage and keeps every other
stage, in both engine tables (a custom property animates on the main thread in both). MT-R
(`registrations_see`, `morph_scope_eq`): `--morph` and `--morph-fade` are registered inherited, so every reader below
the nav (the hosted panel included) sees the animated value and the style invalidation scope on the nav equals the
original's. On the platform section the waapi arm restyles the subtree's dependent elements on frames where the
original does not (`waapi_section_finding`); the `waapi-scoped` arm restyles no descendant there (`scoped_below_nil`,
`fade_eq`).
Golden rows (predictions, registrations, readers): `packages/contracts/golden/parts/morph-tween-waapi.jsonl`
(`goldenJsonl`).
-/
namespace Fw.Parts.MorphTweenOpt

open Fw.Parts.MorphTween

/-! ## The cubic Bézier, two forms -/

/-- One coordinate of a cubic Bézier from 0 to 1 with inner control coordinates `a, b` (Bernstein form).

The textbook curve with end points 0 and 1. -/
def bez (a b s : Rat) : Rat := 3 * a * s * (1 - s) * (1 - s) + 3 * b * s * s * (1 - s) + s * s * s

/-- Polynomial coefficients of one axis, as both engines store them.

The three numbers an engine keeps per axis. -/
structure Coeffs where
  /-- coefficient of `t^1` -/
  c : Rat
  /-- coefficient of `t^2` -/
  b : Rat
  /-- coefficient of `t^3` -/
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

/-- The engines' Horner form is the Bézier curve.

The engine's polynomial and the textbook curve agree everywhere. -/
theorem horner_eq_bez (p1 p2 t : Rat) : horner (coeffs p1 p2) t = bez p1 p2 t := by
  simp only [horner, coeffs, bez]
  grind

/-! ## The control points of the variant -/

/-- First control point, x. One third. -/
def p1x : Rat := 1 / 3
/-- First control point, y. One. -/
def p1y : Rat := 1
/-- Second control point, x. Two thirds. -/
def p2x : Rat := 2 / 3
/-- Second control point, y. One. -/
def p2y : Rat := 1

/-- The variant's timing curve, x axis. Time component of `cubic-bezier(1/3,1,2/3,1)`. -/
def curveX (s : Rat) : Rat := bez p1x p2x s

/-- The variant's timing curve, y axis. Progress component of `cubic-bezier(1/3,1,2/3,1)`. -/
def curveY (s : Rat) : Rat := bez p1y p2y s

#guard curveX (1 / 2) == 1 / 2
#guard curveY (1 / 2) == 7 / 8
#guard curveY (1 / 2) == ease (1 / 2)
#guard coeffs p1x p2x == ⟨1, 0, 0⟩
#guard coeffs p1y p2y == ⟨3, -3, 1⟩

/-- The x coefficients are exactly `(1, 0, 0)`, so the engines' x axis is the identity.

The exact-arithmetic side of the fp premise R8. -/
theorem coeffs_x : coeffs p1x p2x = ⟨1, 0, 0⟩ := by
  simp only [coeffs, p1x, p2x, Coeffs.mk.injEq]
  exact ⟨by grind, by grind, by grind⟩

/-- The y coefficients are `(3, -3, 1)`, so the engines evaluate `((t-3)t+3)t`.

The progress polynomial the engines run. -/
theorem coeffs_y : coeffs p1y p2y = ⟨3, -3, 1⟩ := by
  simp only [coeffs, p1y, p2y, Coeffs.mk.injEq]
  exact ⟨by grind, by grind, by grind⟩

/-! ## MT1: the curve is the ease -/

/-- **MT1.** The control points `P_1 = (1/3, 1)`, `P_2 = (2/3, 1)` give `X(s) = s` and
`Y(s) = 1-(1-s)^3` for every rational `s` (not only in `[0,1]`).

Over the rationals the curve is the polynomial `1-(1-s)^3` with time as its own parameter; it equals the original's clamped ease on `[0,1]` (`curveY_eq_ease`). -/
theorem bezier_eq_ease (s : Rat) :
    curveX s = s ∧ curveY s = 1 - (1 - s) * (1 - s) * (1 - s) := by
  simp only [curveX, curveY, bez, p1x, p2x, p1y, p2y]
  constructor <;> grind

/-- **MT1, tied to `MorphTween.ease`.** On the unit interval the curve's y equals the original's ease.

On every progress the animation can reach, the WAAPI curve is the original's ease. -/
theorem curveY_eq_ease (s : Rat) (h0 : 0 ≤ s) (h1 : s ≤ 1) : curveY s = ease s := by
  have hc : clamp01 s = s := by unfold clamp01; grind
  rw [(bezier_eq_ease s).2]
  unfold ease
  rw [hc]

/-- **MT1 at a solver answer.** If the solver returns `t` with `X(t) = x` exactly and `0 ≤ x ≤ 1`, the engine
value is the ease.

An exact solve gives the original's value exactly. -/
theorem solver_exact_zero (t x : Rat) (h : curveX t = x) (hx0 : 0 ≤ x) (hx1 : x ≤ 1) :
    curveY t = ease x := by
  have ht : t = x := by rw [← (bezier_eq_ease t).1]; exact h
  subst ht
  exact curveY_eq_ease t hx0 hx1

/-! ## MT2: the solver's tolerance costs at most `3ε` -/

/-- The y difference factors through the t difference.

The bracket is a mean slope, bounded by 3 when `t, x ∈ [0,1]` (`slope_mem`). -/
theorem curveY_sub (t x : Rat) :
    curveY t - curveY x = (t - x) * ((1 - t) * (1 - t) + (1 - t) * (1 - x) + (1 - x) * (1 - x)) := by
  rw [(bezier_eq_ease t).2, (bezier_eq_ease x).2]
  grind

/-- For `u, v ∈ [0,1]`, the mean slope `u^2 + uv + v^2` lies in `[0, 3]`.

The mean slope of `1-(1-s)^3` between two points of the unit interval is between 0 and 3. -/
theorem slope_mem (u v : Rat) (hu0 : 0 ≤ u) (hu1 : u ≤ 1) (hv0 : 0 ≤ v) (hv1 : v ≤ 1) :
    0 ≤ u * u + u * v + v * v ∧ u * u + u * v + v * v ≤ 3 := by
  have huu : u * u ≤ u * 1 := Rat.mul_le_mul_of_nonneg_left hu1 hu0
  have huv : u * v ≤ u * 1 := Rat.mul_le_mul_of_nonneg_left hv1 hu0
  have hvv : v * v ≤ v * 1 := Rat.mul_le_mul_of_nonneg_left hv1 hv0
  have h1 : 0 ≤ u * u := Rat.mul_nonneg hu0 hu0
  have h2 : 0 ≤ u * v := Rat.mul_nonneg hu0 hv0
  have h3 : 0 ≤ v * v := Rat.mul_nonneg hv0 hv0
  grind

/-- **MT2.** If the solver stops at `t ∈ [0,1]` with `|X(t) - x| < ε` for `x ∈ [0,1]`, the engine value
`Y(t)` is within `3ε` of the original's ease (the bound `|Y'| ≤ 3` on `[0,1]`).

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

The start plus the eased share of the distance. -/
def interpWk (a b p : Rat) : Rat := a + (b - a) * p

/-- Blink's interpolation of two numbers (R3, `interpolable_value.cc:105-115`@f842f52).

The weighted mean of the two ends. -/
def interpBlink (a b p : Rat) : Rat := (1 - p) * a + p * b

/-- In `ℚ` Blink's form equals WebKit's (in doubles they may differ in the last bit; that side is gap R8).

Both engines interpolate a registered number linearly. -/
theorem interpBlink_eq_wk (a b p : Rat) : interpBlink a b p = interpWk a b p := by
  unfold interpBlink interpWk; grind

/-- An unregistered custom property interpolates discretely: it flips at progress `1/2` (R3).

Without `@property` the morph would jump half way. -/
def interpDiscrete (a b p : Rat) : Rat := if p < 1 / 2 then a else b

#guard interpDiscrete 0 1 (1 / 4) == 0 && interpWk 0 1 (1 / 4) == 1 / 4 && interpBlink 0 1 (1 / 4) == 1 / 4

/-- The discrete form is not linear, so the premise `interp_lin` needs the `@property` registration.

An unregistered `--morph` breaks MT3. -/
theorem discrete_not_linear : interpDiscrete 0 1 (1 / 4) ≠ interpWk 0 1 (1 / 4) := by
  unfold interpDiscrete interpWk; grind

/-- **The premises of MT3**, as structure fields (none is an axiom). `c` is the timeline offset: the timeline time
of a moment minus its rAF/`performance.now()` time. It is 0 in both engines (R5 CONFIRMED: Blink
`document_timeline.cc:150-157`, WebKit `DocumentTimeline.cpp:58-60`) and one constant per run under the lane's clock
shim, which fakes `performance.now()` but not `document.timeline`.

Linear interpolation, the exact curve, and one clock offset shared by frames and start reads. -/
structure WaapiPremises where
  /-- the timeline offset `c` -/
  c : Rat
  /-- the engine's number interpolation `ι(a, b, p)` -/
  interp : Rat → Rat → Rat → Rat
  /-- R3, registered `<number>`: linear (`interpBlink_eq_wk`) -/
  interp_lin : ∀ a b p, interp a b p = a + (b - a) * p
  /-- the effect's timing function `τ` -/
  timing : Rat → Rat
  /-- MT1 with an exact solve: `τ = Y` on `[0,1]` (the solver error is MT2, the double side R8) -/
  timing_eq : ∀ x, 0 ≤ x → x ≤ 1 → timing x = curveY x
  /-- the timeline time of the frame whose rAF timestamp is `R` -/
  tl : Rat → Rat
  /-- R5: frames see the timeline at their rAF time plus `c` -/
  tl_eq : ∀ R, tl R = R + c
  /-- the start time the variant reads from `document.timeline.currentTime` at a push whose `performance.now()` is `n` -/
  startRead : Rat → Rat
  /-- R5 in the lead's form: the read is the push time plus the same `c` -/
  start_eq : ∀ n, startRead n = n + c

/-- The premises hold for WebKit's form with any offset `c` (so they are consistent).

One model of the premises. -/
def premisesWk (c : Rat) : WaapiPremises :=
  ⟨c, interpWk, fun _ _ _ => rfl, curveY, fun _ _ _ => rfl, (· + c), fun _ => rfl, (· + c), fun _ => rfl⟩

/-- The premises hold for Blink's form with any offset `c`.

The other model of the premises. -/
def premisesBlink (c : Rat) : WaapiPremises :=
  ⟨c, interpBlink, interpBlink_eq_wk, curveY, fun _ _ _ => rfl, (· + c), fun _ => rfl, (· + c), fun _ => rfl⟩

/-- One WAAPI animation of `--morph`: from, to, start time on the timeline.
Keyframes `f → t` over 680 ms from timeline time `σ`. -/
structure Anim where
  /-- the from keyframe -/
  f : Rat
  /-- the to keyframe -/
  t : Rat
  /-- the start time on the timeline -/
  st : Rat
deriving Repr, DecidableEq

/-- Iteration progress at timeline time `T` with `fill: 'both'`: 0 before the start, 1 after the end.

The share of the 680 ms elapsed, held at the ends. -/
def progress (st T : Rat) : Rat := clamp01 ((T - st) / duration)

/-- The animated value at timeline time `T`: interpolate the keyframes at the eased progress.

What the engine writes into `--morph` on that frame. -/
def valA (P : WaapiPremises) (a : Anim) (T : Rat) : Rat := P.interp a.f a.t (P.timing (progress a.st T))

/-- Clamping twice is clamping once.
The clamp is idempotent. -/
theorem clamp01_idem (x : Rat) : clamp01 (clamp01 x) = clamp01 x := by unfold clamp01; grind

/-- The ease clamps its argument itself.
Pre-clamping changes nothing. -/
theorem ease_clamp (x : Rat) : ease (clamp01 x) = ease x := by unfold ease; rw [clamp01_idem]

/-- The tween's value in closed form: the done branch is the same formula at `ease = 1`.

One formula for the whole tween. -/
theorem tween_value_eq (f t e : Rat) : (tween f t e).value = f + (t - f) * ease (e / duration) := by
  unfold tween
  have hm := clamp01_mem (e / duration)
  dsimp only
  split
  · have h1 : clamp01 (e / duration) = 1 := by grind
    rw [← ease_clamp, h1]; unfold ease clamp01; grind
  · simp only [ease_clamp]

/-- The eased progress of an animation started by a push at `n`, seen by the frame at `R`, is the original's ease.

The offset `c` cancels and the curve is the ease. -/
theorem timing_progress (P : WaapiPremises) (n R : Rat) :
    P.timing (progress (P.startRead n) (P.tl R)) = ease ((R - n) / duration) := by
  unfold progress
  rw [P.tl_eq, P.start_eq]
  have he : R + P.c - (n + P.c) = R - n := by grind
  rw [he]
  have hm := clamp01_mem ((R - n) / duration)
  rw [P.timing_eq _ hm.1 hm.2, curveY_eq_ease _ hm.1 hm.2, ease_clamp]

/-- **The value function, one frame.** An animation from `f` to `t` started by a push at `n` shows, on the frame at
`R`, exactly the original's tween value.

Same push, same frame, same number. -/
theorem valA_eq (P : WaapiPremises) (f t n R : Rat) :
    valA P ⟨f, t, P.startRead n⟩ (P.tl R) = (tween f t (R - n)).value := by
  unfold valA
  rw [timing_progress, P.interp_lin, tween_value_eq]

/-- An input event: a taken push toward `g` (reduced motion `rm`, `performance.now()` `n`), or an animation frame
with rAF timestamp `R`.
What happens to the morph over time. -/
inductive Ev where
  | push (g : Rat) (rm : Bool) (n : Rat)
  | tick (R : Rat)
deriving Repr, DecidableEq

/-- The original's step: a push is `MorphTween.push`; a frame runs the tween iff a frame was requested.

The rAF loop of the original. -/
def stepO (s : St) : Ev → St
  | .push g rm n => push s g rm n
  | .tick R => if s.pending then frame s R else s

/-- The original's state after a list of events.
Replay the events. -/
def runO (s : St) (es : List Ev) : St := es.foldl stepO s

/-- The variant's script state: target, aim, the running animation (none after a reduced-motion jump), the base value
without an animation, and the value the last frame showed.
No per-frame script. -/
structure VSt where
  /-- the target `w.tg` -/
  target : Rat
  /-- where the running animation aims, `w.aim` -/
  aim : Rat
  /-- the running animation `w.an` -/
  anim : Option Anim
  /-- the value without an animation `w.base` -/
  base : Rat
  /-- the value the last frame showed `w.cur` -/
  cur : Rat
deriving Repr, DecidableEq

/-- The variant at rest. Before any push. -/
def initV : VSt := ⟨0, 0, none, 0, 0⟩

/-- The variant's `--morph` at timeline time `T`.
The animation's value, or the base without one. -/
def valV (P : WaapiPremises) (w : VSt) (T : Rat) : Rat :=
  match w.anim with
  | none => w.base
  | some a => valA P a T

/-- The variant's step. A push to the current target and aim is a no-op; a reduced-motion push drops the animation
and sets the value; any other push starts a new animation from the last frame's value to `g`, its start read from
the timeline. A frame only records what the engine shows (no script runs).

The TS variant's push handler, and the engine's frame. -/
def stepV (P : WaapiPremises) (w : VSt) : Ev → VSt
  | .push g rm n =>
    if w.target = g ∧ w.aim = g then w
    else if rm then { w with target := g, aim := g, anim := none, base := g, cur := g }
    else { w with target := g, aim := g, anim := some ⟨w.cur, g, P.startRead n⟩ }
  | .tick R => { w with cur := valV P w (P.tl R) }

/-- The variant's state after a list of events.
Replay the events. -/
def runV (P : WaapiPremises) (w : VSt) (es : List Ev) : VSt := es.foldl (stepV P) w

/-- Frame times never go back: every frame time is at least `ℓ` and at least the previous frame time.

RAF timestamps are nondecreasing; push times are free. -/
def monoB : Rat → List Ev → Bool
  | _, [] => true
  | l, .push _ _ _ :: es => monoB l es
  | l, .tick R :: es => decide (l ≤ R) && monoB R es

/-- The simulation invariant between the original `s` and the variant `w`, with `ℓ` the last frame time.

A running tween is the running animation; a finished one has filled forwards to its target. -/
def Inv (P : WaapiPremises) (l : Rat) (s : St) (w : VSt) : Prop :=
  w.target = s.target ∧ w.aim = s.t ∧ w.cur = s.value ∧
    (s.pending = true → w.anim = some ⟨s.f, s.t, P.startRead s.start⟩) ∧
    (s.pending = false → (w.anim = none ∧ w.base = s.value) ∨
      ∃ f, w.anim = some ⟨f, s.t, P.startRead s.start⟩ ∧ s.value = s.t ∧ s.start + duration ≤ l)

/-- Both start related.
Rest matches rest. -/
theorem inv_init (P : WaapiPremises) (l : Rat) : Inv P l rest initV := by
  unfold Inv rest initV; simp

/-- A push keeps the invariant.

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

/-- A frame at `R ≥ ℓ` keeps the invariant, with `R` the new last frame time.

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
`ℓ`), the value the variant's animation shows equals the original tween's value, exactly in `ℚ`, under the
premises `P` (linear interpolation, exact curve, timeline = rAF clock + `c` for frames and start reads).

The WAAPI animation and the rAF tween agree on every frame. -/
theorem waapi_eq_tween (P : WaapiPremises) (es : List Ev) (l : Rat) (hm : monoB l es = true) :
    (runV P initV es).cur = (runO rest es).value := by
  obtain ⟨_, h, _⟩ := inv_run P es l rest initV [] (inv_init P l) (by simpa using hm)
  exact h.2.2.1

/-- MT3 at a frame: the value the engine computes for the frame at `R` after the events `E`.

The frame at `R` shows the original's number. -/
theorem waapi_frame_eq (P : WaapiPremises) (es : List Ev) (R l : Rat) (hm : monoB l (es ++ [.tick R]) = true) :
    valV P (runV P initV es) (P.tl R) = (runO rest (es ++ [.tick R])).value := by
  have := waapi_eq_tween P (es ++ [.tick R]) l hm
  simpa [runV, List.foldl_append, stepV] using this

#guard (runV (premisesWk 0) initV [.push 1 false 100, .tick 440]).cur == (runO rest [.push 1 false 100, .tick 440]).value
#guard (runV (premisesWk 7) initV [.push 1 false 100, .tick 300, .push 0 false 350, .tick 500]).cur ==
  (runO rest [.push 1 false 100, .tick 300, .push 0 false 350, .tick 500]).value
#guard (runV (premisesBlink 3) initV [.push 1 false 0, .tick 700, .tick 900, .push 0 true 950, .tick 960]).cur == 0

/-! ## MT4: the flags flip on the same frame, except at an exact tie -/

/-- A discrete keyframe pair `[0: a, c: a, c: b, 1: b]` at eased progress `p`: both engines give `b` iff `p ≥ c`
(R3b, inclusive; Blink `keyframe_effect.cc:719,724`, WebKit the same).

Before the offset the first value, from the offset on the second. -/
def flipAt (c : Rat) (a b : Bool) (p : Rat) : Bool := if p < c then a else b

/-- The eased progress at which the linear value `f + (t - f) p` reaches `θ` (in `ℚ`, `x / 0 = 0`).

Where the morph crosses the flag's threshold. -/
def kfOffset (θ f t : Rat) : Rat := (θ - f) / (t - f)

/-- The variant's flag for threshold `θ` on an animation from `f` to `t`: a discrete keyframe at offset
`clamp_([0,1])(κ)` from the start's flag to the end's flag.

The flag the engine applies at eased progress `p`. -/
def flagV (θ f t p : Rat) : Bool := flipAt (clamp01 (kfOffset θ f t)) (decide (f > θ)) (decide (t > θ)) p

/-- The original's flag at eased progress `p`: the strict test on the tween's value.

What the rAF loop computes. -/
def flagO (θ f t p : Rat) : Bool := decide (f + (t - f) * p > θ)

/-- Rising: the value passes `θ` exactly when the progress passes the offset.

Above the threshold iff past the offset. -/
theorem up_iff (θ f t x : Rat) (hd : f < t) : f + (t - f) * x > θ ↔ kfOffset θ f t < x := by
  unfold kfOffset
  rw [Rat.div_lt_iff (by grind)]
  grind

/-- Falling: the value is above `θ` exactly before the offset.

Above the threshold iff not yet at the offset. -/
theorem down_iff (θ f t x : Rat) (hd : t < f) : f + (t - f) * x > θ ↔ x < kfOffset θ f t := by
  unfold kfOffset
  have : (θ - f) / (t - f) = (f - θ) / (f - t) := by grind
  rw [this, Rat.lt_div_iff (by grind)]
  grind

/-- A flat animation has offset 0. Division by zero is 0 in `ℚ`. -/
theorem kfOffset_flat (θ f : Rat) : kfOffset θ f f = 0 := by unfold kfOffset; grind

/-- Rising through `θ`, the offset lies in `[0, 1)`, so the clamp keeps it.

A crossing inside the animation. -/
theorem kfOffset_mem (θ f t : Rat) (hf : f ≤ θ) (ht : θ < t) :
    0 ≤ kfOffset θ f t ∧ kfOffset θ f t < 1 ∧ clamp01 (kfOffset θ f t) = kfOffset θ f t := by
  have h0 := up_iff θ f t 0 (by grind)
  have h1 := up_iff θ f t 1 (by grind)
  have : ¬ kfOffset θ f t < 0 := by grind
  refine ⟨by grind, by grind, ?_⟩
  unfold clamp01; grind

/-- **Below the tie** (rising through `θ`, progress before the offset): both flags are off.

Strictly before the crossing nobody has flipped. -/
theorem flag_below_tie (θ f t p : Rat) (hf : f ≤ θ) (ht : θ < t) (hp : p < kfOffset θ f t) :
    flagV θ f t p = false ∧ flagO θ f t p = false := by
  have hk := kfOffset_mem θ f t hf ht
  have hu := up_iff θ f t p (by grind)
  unfold flagV flipAt flagO
  rw [hk.2.2]
  refine ⟨by simp [hp]; grind, by simp; grind⟩

/-- **The tie** (rising through `θ`, progress exactly at the offset): the variant has flipped (R3b, `p ≥ c`),
the original has not (the value equals `θ` and the test is strict `>`).

The one frame where they differ. -/
theorem flag_tie (θ f t p : Rat) (hf : f ≤ θ) (ht : θ < t) (hp : p = kfOffset θ f t) :
    flagV θ f t p = true ∧ flagO θ f t p = false := by
  have hk := kfOffset_mem θ f t hf ht
  have hu := up_iff θ f t p (by grind)
  unfold flagV flipAt flagO
  rw [hk.2.2]
  refine ⟨by simp; grind, by simp; grind⟩

/-- **Above the tie** (rising through `θ`, progress past the offset): both flags are on.

Strictly after the crossing both have flipped. -/
theorem flag_above_tie (θ f t p : Rat) (hf : f ≤ θ) (ht : θ < t) (hp : kfOffset θ f t < p) :
    flagV θ f t p = true ∧ flagO θ f t p = true := by
  have hk := kfOffset_mem θ f t hf ht
  have hu := up_iff θ f t p (by grind)
  unfold flagV flipAt flagO
  rw [hk.2.2]
  refine ⟨by simp; grind, by simp; grind⟩

/-- **MT4 `flags_same_frame`.** For eased progress `p ∈ [0,1]` the variant's discrete-keyframe flag equals the
original's strict test, except at an exact tie: rising through `θ` (`f ≤ θ < t`) with `p = κ`.
Falling and flat animations have no tie (at `p = κ` falling, the value is `θ` and both are off).

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

A finished animation fills forwards to the end keyframe. -/
theorem flagV_one (θ f t : Rat) : flagV θ f t 1 = decide (t > θ) := by
  unfold flagV flipAt
  have := clamp01_mem (kfOffset θ f t)
  have h : ¬ (1 : Rat) < clamp01 (kfOffset θ f t) := by grind
  simp only [h, ite_false]

/-- The threshold test on the ease, without the clamp (for frames of a running tween).

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

/-- The thresholds the original tests the morph value against, strictly: on-dark (`m > 1/5`, `NavHitTest.isOnDark`),
expanded (`m > 23/25`), pointer-none (`fade(m) < 1/20 ⇔ m > 209/400`) and
active (`m > 1/1000`).

One discrete keyframe track per threshold. -/
def thresholds : List Rat := [1 / 5, 23 / 25, 209 / 400, activeCut]

/-- Pointer-none is a strict threshold flag.

The fade test is a value test. -/
theorem pointerNone_eq (m : Rat) : pointerNone m = decide (m > 209 / 400) := by
  have := pointerNone_iff m
  cases h : pointerNone m <;> simp_all

/-- The fade the variant computes in CSS, `calc(1 - min(1, var(--morph) / 0.55))`, is the original's fade.

No script needed for the fade. -/
theorem fade_css (m : Rat) : fade m = 1 - min 1 (m / (55 / 100)) := by
  unfold fade fadeEnd
  have : (55 / 100 : Rat) = 11 / 20 := by grind
  rw [this]

/-- The variant's flag for threshold `θ` at timeline time `T`: the reduced-motion base value's flag without an
animation, else the discrete keyframe at the animation's eased progress.

What the engine shows for one flag. -/
def flagW (P : WaapiPremises) (w : VSt) (θ T : Rat) : Bool :=
  match w.anim with
  | none => decide (w.base > θ)
  | some a => flagV θ a.f a.t (P.timing (progress a.st T))

/-- A tie at the frame `R` for threshold `θ`, read off the original's state `s` before that frame: a running
tween rising through `θ` whose eased progress at `R` is exactly the offset.

The only frames where a flag may differ. -/
def tieB (s : St) (θ R : Rat) : Bool :=
  s.pending && decide (s.f ≤ θ) && decide (θ < s.t) && decide (ease ((R - s.start) / duration) = kfOffset θ s.f s.t)

/-- **MT4 over a run.** On the frame at `R` after the events `E` (frames nondecreasing), when that frame is no tie
for `θ`, the variant's flag equals the original's strict test on its value.

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

/-- What the morph's scene depends on: the value, the target, and the flags over `Θ`.

The part's whole visible state. -/
structure View where
  /-- the morph value -/
  m : Rat
  /-- the target (the active flag reads it) -/
  target : Rat
  /-- one flag per threshold in `Θ` -/
  flags : List Bool
deriving Repr, DecidableEq

/-- The original's view at the frame `R` after the events `E`.

Value, target and strict flags after the frame. -/
def viewO (es : List Ev) (R : Rat) : View :=
  let s := runO rest (es ++ [.tick R])
  ⟨s.value, s.target, thresholds.map fun θ => decide (s.value > θ)⟩

/-- The variant's view at the frame `R` after the events `E`: the engine's animated value and discrete flags.

What the engine shows on that frame. -/
def viewV (P : WaapiPremises) (es : List Ev) (R : Rat) : View :=
  let w := runV P initV es
  ⟨valV P w (P.tl R), w.target, thresholds.map fun θ => flagW P w θ (P.tl R)⟩

/-- The admissible frames: events `E`, a frame at `R` and a bound `ℓ` with frames nondecreasing from `ℓ` and no
tie at `R` for any threshold.

Every frame of every tie-free history. -/
def Hist : Type :=
  {x : List Ev × Rat × Rat // monoB x.2.2 (x.1 ++ [.tick x.2.1]) = true ∧
    thresholds.all (fun θ => !tieB (runO rest x.1) θ x.2.1) = true}

/-- The views agree on every admissible frame.

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

/-! ### The attribute the readers see -/

/-- How a reader compares the attribute with its threshold: strictly above or strictly below. -/
inductive Cmp where
  | gt
  | lt
deriving Repr, DecidableEq

/-- One reader of `data-fw-morph`: what it writes, its comparison and its threshold. -/
structure AttrReader where
  sel : String
  cmp : Cmp
  θ : Rat
deriving Repr, DecidableEq

/-- The reader's answer for the attribute value `m`. -/
def AttrReader.test (r : AttrReader) (m : Rat) : Bool :=
  match r.cmp with
  | .gt => decide (r.θ < m)
  | .lt => decide (m < r.θ)

/-- Every threshold test on `data-fw-morph` in nav, nav.hitTest and morph.panel. -/
def attrReaders : List AttrReader :=
  [⟨"nav.is-morphing", .gt, 1 / 1000⟩, ⟨"nav.is-on-dark", .gt, 1 / 5⟩, ⟨"nav.earn.tabindex", .gt, 2 / 5⟩,
    ⟨"nav.earn.aria-hidden", .gt, 11 / 20⟩, ⟨"nav.is-expanded", .gt, 23 / 25⟩,
    ⟨"panel.data-start-selling-scene", .gt, 1 / 1000⟩, ⟨"panel.aria-hidden", .lt, 7 / 20⟩,
    ⟨"panel.cta.tabindex", .lt, 11 / 20⟩, ⟨"panel.data-expanded", .gt, 23 / 25⟩]

/-- The readers' answers for the attribute value `m`, in `attrReaders` order. -/
def band (m : Rat) : List Bool := attrReaders.map (·.test m)

/-- The inputs of the nav's classes other than the attribute. -/
structure AttrCtx where
  past : Bool
  ready : Bool
  localeOpen : Bool
  hit : Bool
  stuck : Bool
deriving Repr, DecidableEq

/-- What the readers of `data-fw-morph` write: nav classes, earn button, `is-on-dark`, the four panel flags. -/
structure AttrScene where
  nav : Nav.View
  earn : Nav.Earn
  onDark : Bool
  panel : List Bool
deriving Repr, DecidableEq

/-- The readers' output for context `c` and attribute value `m`. -/
def attrScene (c : AttrCtx) (m : Rat) : AttrScene :=
  let v := Nav.view c.past c.ready c.localeOpen c.hit c.stuck m
  ⟨v, Nav.earn v.heroPill m, NavHitTest.isOnDark c.hit m,
    [MorphPanel.sceneActive m, MorphPanel.ariaHidden m, MorphPanel.ctaTabOff m, MorphPanel.expanded m]⟩

/-- The readers' output read off the band `b` alone. -/
def sceneOfBand (c : AttrCtx) (b : List Bool) : AttrScene :=
  let morphing := b.getD 0 false
  let v : Nav.View := ⟨!c.past && !morphing, c.ready, morphing, b.getD 4 false, c.hit || b.getD 1 false,
    c.localeOpen, c.stuck && !morphing⟩
  ⟨v, ⟨b.getD 2 false || v.heroPill, v.heroPill || b.getD 3 false⟩, c.hit || b.getD 1 false,
    [b.getD 5 false, b.getD 6 false, b.getD 7 false, b.getD 8 false]⟩

theorem attrScene_eq_band (c : AttrCtx) (m : Rat) : attrScene c m = sceneOfBand c (band m) := rfl

/-- Two attribute values in the same band give the same readers' output. -/
theorem attrScene_band (c : AttrCtx) (m m' : Rat) (h : band m = band m') : attrScene c m = attrScene c m' := by
  rw [attrScene_eq_band, attrScene_eq_band, h]

#guard attrScene ⟨true, true, false, false, false⟩ (1 / 2) == attrScene ⟨true, true, false, false, false⟩ (21 / 40)
#guard attrScene ⟨true, true, false, false, false⟩ (1 / 2) != attrScene ⟨true, true, false, false, false⟩ (3 / 5)
#guard band 0 == [false, false, false, false, false, false, true, true, false]
#guard band 1 == [true, true, true, true, true, true, false, false, true]

/-! ### Direction along a push -/

/-- `m` lies strictly past `θ` in the direction from `f` to `t`. -/
def pastS (f t θ m : Rat) : Prop := (f < t ∧ θ < m) ∨ (t < f ∧ m < θ)

instance (f t θ m : Rat) : Decidable (pastS f t θ m) :=
  inferInstanceAs (Decidable ((f < t ∧ θ < m) ∨ (t < f ∧ m < θ)))

/-- `m` has reached `θ` in the direction from `f` to `t`. -/
def reach (f t θ m : Rat) : Prop := (f < t ∧ θ ≤ m) ∨ (t < f ∧ m ≤ θ)

instance (f t θ m : Rat) : Decidable (reach f t θ m) :=
  inferInstanceAs (Decidable ((f < t ∧ θ ≤ m) ∨ (t < f ∧ m ≤ θ)))

/-- `v` lies at or after `u` in the direction from `f` to `t`. -/
def ahd (f t u v : Rat) : Prop := (f < t → u ≤ v) ∧ (t < f → v ≤ u) ∧ (f = t → u = v)

/-- The value of a push from `f` to `t` at eased progress `ease x`. -/
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

/-! ### When the driver writes the attribute -/

/-- The variant's state and the last value written to `data-fw-morph`. -/
structure ASt where
  w : VSt
  attr : Rat
deriving Repr, DecidableEq

/-- Rest, attribute 0. -/
def initA : ASt := ⟨initV, 0⟩

/-- The variant's step: a push writes its start value, a frame writes its value iff `wr` says so. Premise, not proved:
a frame's marker finish events (update animations and send events: `B/core/page/page_animator.cc:292-311`@f842f52,
WebKit `animation/AnimationTimelinesController.cpp:217-232`@862f17d) and frame callbacks (`page_animator.cc:335`,
WebKit `page/Page.cpp:2330`) run before that frame's style and layout (WebKit `Page.cpp:2337`). -/
def stepAttr (P : WaapiPremises) (wr : VSt → Rat → Bool) (x : ASt) : Ev → ASt
  | .push g rm n =>
    ⟨stepV P x.w (.push g rm n), if x.w.target = g ∧ x.w.aim = g then x.attr else if rm then g else x.w.cur⟩
  | .tick R => ⟨stepV P x.w (.tick R), if wr x.w (P.tl R) then valV P x.w (P.tl R) else x.attr⟩

/-- The state after a list of events. -/
def runAttr (P : WaapiPremises) (wr : VSt → Rat → Bool) (x : ASt) (es : List Ev) : ASt := es.foldl (stepAttr P wr) x

theorem runAttr_w (P : WaapiPremises) (wr : VSt → Rat → Bool) :
    ∀ (es : List Ev) (x : ASt), (runAttr P wr x es).w = runV P x.w es
  | [], _ => rfl
  | e :: es, x => by
    have := runAttr_w P wr es (stepAttr P wr x e)
    simp only [runAttr, runV, List.foldl_cons] at *
    rw [this]; cases e <;> rfl

/-- The finish handler: writes on every frame at or after the animation's end. -/
def finishW (w : VSt) (T : Rat) : Bool :=
  match w.anim with
  | none => false
  | some a => decide (a.st + duration ≤ T)

/-- The old driver: the push and the finish write, nothing between. -/
def oldW : VSt → Rat → Bool := finishW

/-- A push from `f` to `t` gets a marker for `θ` iff `θ` is not passed at `f` and reached at `t`. -/
def markerB (f t θ : Rat) : Bool := !decide (pastS f t θ f) && decide (reach f t θ t)

/-- Each marker writes on every frame from its delay on until a frame's value has passed its threshold. -/
def pollW (dl : Rat → Rat → Rat → Rat) (w : VSt) (T : Rat) : Bool :=
  match w.anim with
  | none => false
  | some a => attrReaders.any fun r =>
    markerB a.f a.t r.θ && decide (a.st + dl a.f a.t r.θ ≤ T) && !decide (pastS a.f a.t r.θ w.cur)

/-- The fixed driver: the finish write and the markers. -/
def fixW (dl : Rat → Rat → Rat → Rat) (w : VSt) (T : Rat) : Bool := finishW w T || pollW dl w T

/-- A writer is sound when it writes on every frame whose value changes the band. -/
def WrOk (P : WaapiPremises) (wr : VSt → Rat → Bool) : Prop :=
  ∀ (w : VSt) (a : Anim) (T : Rat), w.anim = some a → ahd a.f a.t a.f w.cur → ahd a.f a.t w.cur (valA P a T) →
    band w.cur ≠ band (valA P a T) → wr w T = true

/-- A delay is sound when it never exceeds the elapsed time at which the push reaches the threshold. -/
def DlSound (dl : Rat → Rat → Rat → Rat) : Prop :=
  ∀ f t θ e, 0 < e → reach f t θ (pathAt f t (e / duration)) → dl f t θ ≤ e

/-- Sound delays make the fixed driver a sound writer. -/
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

/-! ### The attribute stays in the value's band -/

/-- The attribute is in the band of the last frame's value, and every later frame value lies ahead of it. -/
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

/-- With sound marker delays the written attribute is in the band of the original's value. -/
theorem attr_band (P : WaapiPremises) (dl : Rat → Rat → Rat → Rat) (hd : DlSound dl) (es : List Ev) (l : Rat)
    (hm : monoB l es = true) : band (runAttr P (fixW dl) initA es).attr = band (runO rest es).value := by
  obtain ⟨_, hb, _⟩ := ainv_run P (fixW dl) (fixW_ok P dl hd) es l initA (ainv_init P l) hm
  rw [hb, runAttr_w, ← waapi_eq_tween P es l hm]
  rfl

/-! ### Marker delays -/

/-- Bisection for the first eased progress at which the push from `f` to `t` reaches `θ`: `k` halvings of `[lo, hi]`. -/
def bisect (f t θ : Rat) : Nat → Rat → Rat → Rat × Rat
  | 0, lo, hi => (lo, hi)
  | k + 1, lo, hi =>
    if reach f t θ (pathAt f t ((lo + hi) / 2)) then bisect f t θ k lo ((lo + hi) / 2)
    else bisect f t θ k ((lo + hi) / 2) hi

/-- The marker delay in ms: 0 when `θ` is reached at `f`, else 680 times the bisection's lower end. -/
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

/-- The bisection delay is sound. -/
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

/-! ### The old driver -/

/-- The old driver's attribute after a push to 1 at 0 and a frame at 340 ms: still 0 while the original shows 7/8. -/
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

/-! ### Golden rows (`morph-tween-waapi.attr.jsonl`) -/

/-- An exact fraction `{"num","den"}`. -/
def ratJ (q : Rat) : Lean.Json := Lean.Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

/-- The comparison's wire name. -/
def Cmp.name : Cmp → String
  | .gt => "gt"
  | .lt => "lt"

/-- One reader row. -/
def AttrReader.json (r : AttrReader) : String :=
  (Lean.Json.mkObj [("kind", .str "attrReader"), ("sel", .str r.sel), ("cmp", .str r.cmp.name),
    ("theta", ratJ r.θ)]).compress

/-- The distinct reader thresholds, one marker each. -/
def markerThetas : List Rat := (attrReaders.map (·.θ)).eraseDups

/-- The bisection depth of the golden delays. -/
def delayDepth : Nat := 24

/-- One marker row: whether the push from `f` to `t` gets a marker for `θ`, and its delay in ms. -/
def markerJson (f t θ : Rat) : String :=
  (Lean.Json.mkObj [("kind", .str "marker"), ("from", ratJ f), ("to", ratJ t), ("theta", ratJ θ),
    ("marker", .bool (markerB f t θ)),
    ("delay", if markerB f t θ then ratJ (dlLo delayDepth f t θ) else .null)]).compress

/-- The start values of the marker rows. -/
def markerFroms : List Rat := [0, 1 / 10, 1 / 5, 3 / 10, 2 / 5, 1 / 2, 3 / 5, 9 / 10, 1]

/-- The marker rows: every start value, both targets, every threshold. -/
def markerRows (_ : Unit) : List String :=
  markerFroms.flatMap fun f => [0, 1].flatMap fun t => markerThetas.map fun θ => markerJson f t θ

/-- Frames every 17 ms from the `a`-th to the `b`-th. -/
def ticks17 (a b : Nat) : List Ev := (List.range (b + 1 - a)).map fun i => .tick (17 * ((a + i : Nat) : Rat))

/-- The replayed histories: an opening push, one reversed at 300 ms, and one closed after it ends. -/
def attrCases : List (String × List Ev) :=
  [("open", .push 1 false 0 :: ticks17 1 42),
    ("reverse", (.push 1 false 0 :: ticks17 1 17) ++ .push 0 false 300 :: ticks17 18 64),
    ("close", (.push 1 false 0 :: ticks17 1 42) ++ .push 0 false 720 :: ticks17 43 84)]

/-- The premises of the golden replay: WebKit's form, offset 0. -/
def attrP : WaapiPremises := premisesWk 0

/-- A band as a JSON array. -/
def bandJ (m : Rat) : Lean.Json := .arr ((band m).map Lean.Json.bool).toArray

/-- The states after each event of `es` with writer `wr`: the event, the variant with its attribute, the original. -/
def attrTrace (wr : VSt → Rat → Bool) (es : List Ev) : List (Ev × ASt × St) :=
  (es.foldl (fun (acc, x, s) e =>
    let x' := stepAttr attrP wr x e
    let s' := stepO s e
    (acc ++ [(e, x', s')], x', s')) (([] : List (Ev × ASt × St)), initA, rest)).1

/-- One event row of case `c`: a push, or a frame with the original's value, its band and the old driver's band. -/
def attrEvJson (c : String) : Ev × ASt × St → String
  | (.push g _ n, _, _) => (Lean.Json.mkObj [("kind", .str "attrEv"), ("case", .str c), ("ev", .str "push"),
      ("t", ratJ n), ("goal", ratJ g)]).compress
  | (.tick R, x, s) => (Lean.Json.mkObj [("kind", .str "attrEv"), ("case", .str c), ("ev", .str "tick"),
      ("t", ratJ R), ("value", ratJ s.value), ("band", bandJ s.value), ("old", bandJ x.attr)]).compress

/-- The event rows of one case. -/
def attrEvRows (c : String) (es : List Ev) : List String := (attrTrace oldW es).map (attrEvJson c)

/-- Every event of a case leaves the attribute of writer `wr` in the original's band. -/
def bandsAgree (wr : VSt → Rat → Bool) (es : List Ev) : Bool :=
  (attrTrace wr es).all fun (_, x, s) => band x.attr == band s.value

/-- The contents of `packages/contracts/golden/parts/morph-tween-waapi.attr.jsonl`: readers, markers, event rows. -/
def attrJsonl (_ : Unit) : String :=
  String.join (attrReaders.map fun r => r.json ++ "\n") ++ String.join ((markerRows ()).map (· ++ "\n")) ++
    String.join (attrCases.flatMap fun (c, es) => (attrEvRows c es).map (· ++ "\n"))

#guard attrCases.all fun (_, es) => bandsAgree (fixW (dlLo delayDepth)) es && !bandsAgree oldW es
#guard markerThetas == [1 / 1000, 1 / 5, 2 / 5, 11 / 20, 23 / 25, 7 / 20]
#guard (markerRows ()).length == 108

/-- **The visual theorem (class E-s).** With sound marker delays, every scene built from the frame's view and the
attribute's readers equals the original's on every admissible frame, for both arms (shared `fixW`, `attrReaders`).
A transition started by the `is-morphing` flip is not such a scene: it starts from the previous frame's base
(WidthTail). -/
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

/-! ## MT-W: the variant drops the script stage and keeps every other stage -/

/-- The work relation of MT-W between a variant frame's work `v` and the original's `o` with `k` callbacks: `v ≺ o`,
every stage but script equal, script `0` against one pass of `k` units.

Script strictly less, style, layout, paint and commit equal. -/
def dropsScript (v o : Work) (k : Nat) : Prop :=
  v.lt o ∧ (∀ s, s ≠ Stage.script → v.passes s = o.passes s ∧ v.units s = o.units s) ∧
    v.passes .script = 0 ∧ v.units .script = 0 ∧ o.passes .script = 1 ∧ o.units .script = k

/-- **MT-W, any engine.** If no change, no compositor stage and no base stage is `script`, a frame of `k > 0`
callbacks writing the nonempty changes `C` (with `n` compositor animations) and the same frame without script stand
in the relation `drop`.

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

/-- **MT-W, Chromium (lane).** Main-thread animations `A` of custom properties, against `k > 0` callbacks writing the
same changes inline: script drops, every other stage stays.

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

Style writes never run script. -/
theorem wk_no_script (d : WebKit.Diff) : Stage.script ∉ WebKit.diffStages d := by cases d <;> decide

/-- **MT-W, WebKit (Safari).** An animation with a custom property runs on the main thread (`custom_main`); its frame
writes the changes `C`, against `k > 0` callbacks writing `C` inline: script drops, every other stage stays.

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

/-- Over a tween of `N > 0` frames the screen says the variant dominates.

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
guards. An instance. -/
def crMorph : Chromium.CrAnim := { elem := 0, props := [.custom 0 [.opacity]], layer := .none }

/-- One concrete WebKit `--morph` animation. An instance. -/
def wkMorph : WebKit.WkAnim := .clean [.custom] .time

/-- The per-stage prediction of a variant's work `v` against the original's `o`, first match.

Equal, below, or unknown. -/
def predW (v o : Work) (s : Stage) : String :=
  if v.passes s = o.passes s ∧ v.units s = o.units s then "=o"
  else if v.passes s ≤ o.passes s ∧ v.units s ≤ o.units s then "<o"
  else "any"

/-- The prediction MT-W gives each stage.
Script below, the rest equal. -/
def predStage (s : Stage) : String := if s = .script then "<o" else "=o"

/-- The golden predictions follow from MT-W for every instance.

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

/-- The value an element at depth `d` below the animated element `e` computes for a property whose value on `e` is `a`
and whose initial value is `i`, when no element below `e` on the path to it declares the property: `e` itself has
`a`; a child inherits its parent's value if the property is inherited, else takes `i`.

What a reader `d` levels down sees. -/
def seenAt (inh : Bool) (a i : Rat) : Nat → Rat
  | 0 => a
  | d + 1 => if inh then seenAt inh a i d else i

/-- An inherited property reaches every depth.

Inheritance carries the animated value down. -/
theorem seenAt_true (a i : Rat) (d : Nat) : seenAt true a i d = a := by
  induction d with
  | zero => rfl
  | succ d ih => simp [seenAt, ih]

/-- A non-inherited property is the initial value on every strict descendant.

Without inheritance a child never sees the animation. -/
theorem seenAt_false_succ (a i : Rat) (d : Nat) : seenAt false a i (d + 1) = i := rfl

/-- A reader of an animated property: a CSS rule that substitutes `var(prop)` on an element (CSS-module class `sel`)
at depth `depth` below the element the variant animates. The depths are entered by hand and not checked against the
DOM.

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

Where the animated properties are read. -/
def readers : List Reader :=
  [⟨"--morph", "nav", 0⟩, ⟨"--morph", "logo", 2⟩, ⟨"--morph", "actions", 2⟩, ⟨"--morph", "earn", 3⟩,
   ⟨"--morph", "panel", 1⟩, ⟨"--morph", "section", 0⟩, ⟨"--morph-fade", "section", 0⟩]

/-- The reader depths of the property `p`, in list order (empty for a property nothing reads).

How deep each reader of `p` sits. -/
def readersOf (p : String) : List Nat := (readers.filter (·.prop == p)).map (·.depth)

/-- A property needs `inherits` iff one of its readers is a strict descendant (false for no readers).

The registration rule. -/
def needsInherit (ds : List Nat) : Bool := ds.any (0 < ·)

#guard needsInherit (readersOf "--morph") && !needsInherit (readersOf "--fw-morph-dark")
#guard !needsInherit [] && !needsInherit [0, 0] && needsInherit [0, 1]

/-- Every reader sees every animated value iff the property is inherited or no reader is a strict descendant.

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

/-- Whether the original has the property `p` as an inherited custom property: `--morph` and `--morph-fade` are
written there unregistered, so inherited (Chromium `custom_property.cc:22-23`@f842f52, WebKit
`StyleBuilder.cpp:103-106`@862f17d); the flags are classes there, and any other name is absent.

The original's inheritance bit per property. -/
def origInheritsOf (p : String) : Bool := p == "--morph" || p == "--morph-fade"

/-- The registrations of the variant: `--morph` inherited (the nav's descendants and the hosted panel read it),
`--morph-fade` inherited (as in the original, so the same elements recompute; registered so that its computed value
is a number, `1` at rest, as the original's), the two flags not inherited (nothing reads them below the nav). All
`<number>`; initial value `0`, `--morph-fade` `1` (its value at rest).

What `index.tsx` passes to `CSS.registerProperty`. -/
def registrations : List Registration :=
  [⟨"--morph", "<number>", true, "0"⟩, ⟨"--morph-fade", "<number>", true, "1"⟩,
   ⟨"--fw-morph-dark", "<number>", false, "0"⟩, ⟨"--fw-morph-expanded", "<number>", false, "0"⟩]

/-- Each registration inherits exactly when a reader sits below the element that sets it or the original's property
inherits.

No property inherits without a reason, none lacks it with one. -/
theorem registrations_rule :
    ∀ r ∈ registrations, r.inherits = (needsInherit (readersOf r.name) || origInheritsOf r.name) := by decide

/-- **MT-R, visual.** Under the variant's registrations every reader of every registered property sees the animated
value, whatever the value and the initial value; so the view of `waapi_vis` is what each reader renders, the hosted
panel included.

Every reader sees the animation. -/
theorem registrations_see :
    ∀ r ∈ registrations, ∀ a i : Rat, ∀ d ∈ readersOf r.name, seenAt r.inherits a i d = a := by
  intro r hr a i d hd
  refine (sees_iff r.inherits i (readersOf r.name)).2 ?_ a d hd
  rw [registrations_rule r hr]
  cases needsInherit (readersOf r.name) <;> cases origInheritsOf r.name <;> simp

/-- **MT-R, the finding.** Registered with `inherits` false, `--morph` leaves the hosted panel (depth 1) at its
initial value while the nav animates any other value.

`inherits: false` makes the panel blind. -/
theorem panel_blind_without_inherit (a i : Rat) (h : a ≠ i) :
    (⟨"--morph", "panel", 1⟩ : Reader) ∈ readers ∧ seenAt false a i 1 ≠ a :=
  ⟨by decide, fun e => h (by rw [seenAt_false_succ] at e; exact e.symm)⟩

/-- The variant's inheritance bit of the property `p`: that of its registration, `⊥` if it has none.

The variant's inheritance bit per property. -/
def regInherits (p : String) : Bool := ((registrations.find? (·.name == p)).map (·.inherits)).getD false

/-- Whether an element at depth `d` recomputes its style when the animated value changes: the animated element
always, a descendant iff the property is inherited (the inherited-data change of the section note).

Which elements a value change invalidates. -/
def recalcs (inh : Bool) (d : Nat) : Bool := d == 0 || inh

/-- **MT-R, work.** For every property the original has as an inherited custom property (`--morph`, `--morph-fade`),
the variant's registration inherits too, so its per-frame style changes cover exactly the original's elements in
every subtree and every element sees the same value as in the original: `waapi_work_le` applies with one change list
`C` for both arms. With `inherits` false the variant would change fewer elements than the original on any subtree
with a strict descendant: a smaller style count bought by a wrong picture. The waapi arm also animates `--morph` on the
platform section, where the original writes only `--morph-fade`. The original's `--morph-fade` stops changing once
the fade clamps at 0.55, while `--morph` changes to the end of the tween, so there the extra property adds the
section's subtree to the recalc set (`waapi_section_finding`, measured in the `tween-platform-scope` note).

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

The wire form. -/
def Registration.json (r : Registration) : String :=
  (Lean.Json.mkObj [("name", .str r.name), ("syntax", .str r.syntaxStr), ("inherits", .bool r.inherits),
    ("initialValue", .str r.initialValue)]).compress

/-- One reader as compact JSON (keys sorted by `Json.mkObj`).

The wire form. -/
def Reader.json (r : Reader) : String :=
  (Lean.Json.mkObj [("prop", .str r.prop), ("sel", .str r.sel), ("depth", (r.depth : Lean.Json))]).compress

#guard registrations.head?.map Registration.json ==
  some "{\"inherits\":true,\"initialValue\":\"0\",\"name\":\"--morph\",\"syntax\":\"<number>\"}"
#guard readers.head?.map Reader.json == some "{\"depth\":0,\"prop\":\"--morph\",\"sel\":\"nav\"}"

/-! ## MT-R, the scoped arm (`morph.tween:waapi-scoped`) -/

/-- Readers under `waapi-scoped`: the nav's five `--morph` readers, then on the platform section its inline
`--morph-fade` reading `--platform-morph` and `platform.module.css` reading `--morph-fade`, both at depth 0. -/
def readersScoped : List Reader :=
  [⟨"--morph", "nav", 0⟩, ⟨"--morph", "logo", 2⟩, ⟨"--morph", "actions", 2⟩, ⟨"--morph", "earn", 3⟩,
   ⟨"--morph", "panel", 1⟩, ⟨"--platform-morph", "section", 0⟩, ⟨"--morph-fade", "section", 0⟩]

/-- The reader depths of a property under `waapi-scoped`, in list order. -/
def readersOfS (p : String) : List Nat := (readersScoped.filter (·.prop == p)).map (·.depth)

/-- What `index.tsx` passes to `CSS.registerProperty` under `waapi-scoped`. -/
def registrationsScoped : List Registration :=
  [⟨"--morph", "<number>", true, "0"⟩, ⟨"--morph-fade", "<number>", false, "1"⟩,
   ⟨"--fw-morph-dark", "<number>", false, "0"⟩, ⟨"--fw-morph-expanded", "<number>", false, "0"⟩,
   ⟨"--platform-morph", "<number>", false, "0"⟩]

/-- Under `waapi-scoped` a registration inherits exactly when one of its readers is a strict descendant. -/
theorem registrationsScoped_rule :
    ∀ r ∈ registrationsScoped, r.inherits = needsInherit (readersOfS r.name) := by decide

/-- Under `waapi-scoped` every reader of every registered property sees the animated value. -/
theorem registrationsScoped_see :
    ∀ r ∈ registrationsScoped, ∀ a i : Rat, ∀ d ∈ readersOfS r.name, seenAt r.inherits a i d = a := by
  intro r hr a i d hd
  refine (sees_iff r.inherits i (readersOfS r.name)).2 ?_ a d hd
  rw [registrationsScoped_rule r hr]
  cases needsInherit (readersOfS r.name) <;> simp

/-- The inheritance bit of a property under `waapi-scoped`, false without a registration. -/
def regInheritsS (p : String) : Bool := ((registrationsScoped.find? (·.name == p)).map (·.inherits)).getD false

/-- For each property the original has inherited, the scoped arm restyles a sublist of the original's elements and
every reader sees the original's value. -/
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

/-- `--platform-morph` restyles only the section that animates it. -/
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

/-- **MT-R, refuted premise.** Once the fade has clamped (`m, m' ≥ 0.55`), the original's inherited `--morph-fade`
stops changing and restyles no strict descendant of the section, while the waapi arm's inherited `--morph` still
changes and restyles every descendant in `ds` (the elements the engine recalcs on an inherited change: `var()`
references, animations; INFERRED model). -/
theorem waapi_section_finding (m m' : Rat) (ds : List Nat) (hm : fadeEnd ≤ m) (hm' : fadeEnd ≤ m')
    (hne : m ≠ m') :
    frameBelow true (fade m) (fade m') ds = [] ∧ frameBelow true m m' ds = ds.filter (0 < ·) := by
  refine ⟨?_, ?_⟩
  · simp [frameBelow, fade_ends.2 m hm, fade_ends.2 m' hm']
  · simp [frameBelow, hne, recalcs]

/-- On every frame the waapi arm restyles at least the strict descendants the original restyles. -/
theorem orig_below_le_waapi (m m' : Rat) (ds : List Nat) :
    (frameBelow true (fade m) (fade m') ds).Sublist (frameBelow true m m' ds) := by
  unfold frameBelow
  by_cases h : m = m'
  · subst h; simp
  · simp only [h, ↓reduceIte]; split <;> simp

/-- The scoped arm restyles no strict descendant of the section on any frame, so its set is a sublist of both the
original's and the waapi arm's. -/
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

/-- The value of `--platform-morph` on the frame `R` after the events `es`: the platform animation has the nav's
keyframe values, timing and start time, so the engine's one animated value. -/
def platformMorphV (P : WaapiPremises) (es : List Ev) (R : Rat) : Rat := valV P (runV P initV es) (P.tl R)

/-- The scoped arm's inline `--morph-fade`, `calc(1 - min(1, var(--platform-morph) / 0.55))`, evaluated. -/
def fadeScopedEval (x : Rat) : Rat := 1 - min 1 (x / (55 / 100))

/-- On every admissible frame the scoped arm's evaluated fade equals the original's. -/
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

/-- One registration of an arm as compact JSON, with the arm under `arm`. -/
def Registration.jsonArm (arm : String) (r : Registration) : String :=
  (Lean.Json.mkObj [("arm", .str arm), ("name", .str r.name), ("syntax", .str r.syntaxStr),
    ("inherits", .bool r.inherits), ("initialValue", .str r.initialValue)]).compress

/-- One reader of an arm as compact JSON, with the arm under `arm`. -/
def Reader.jsonArm (arm : String) (r : Reader) : String :=
  (Lean.Json.mkObj [("arm", .str arm), ("prop", .str r.prop), ("sel", .str r.sel),
    ("depth", (r.depth : Lean.Json))]).compress

#guard readersScoped.getLast?.map (Reader.jsonArm "waapi-scoped") ==
  some "{\"arm\":\"waapi-scoped\",\"depth\":0,\"prop\":\"--morph-fade\",\"sel\":\"section\"}"

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

/-- The variant arm: the rewrite with the flag `morph.tween:waapi`. The arm name. -/
def armV : String := "rewrite+?fw=morph.tween:waapi"

/-- The counted stages per engine and their count types (Chromium trace names, WebKit Simulator names).

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

The wire form. -/
def PredRow.json (r : PredRow) : String :=
  (Lean.Json.mkObj [("engine", .str r.engine), ("scenario", .str r.scenario), ("variant", .str r.variant),
    ("stage", .str r.stage), ("prediction", .str r.prediction), ("countType", .str r.countType),
    ("base", .str r.base)]).compress

/-- The contents of `packages/contracts/golden/parts/morph-tween-waapi.jsonl`.

The golden file: the eleven predictions, then the four registrations, then the seven readers, then the `waapi-scoped` arm's five registrations and seven readers with `arm`. -/
def goldenJsonl : String :=
  String.join (goldenRows.map fun r => r.json ++ "\n") ++ String.join (registrations.map fun r => r.json ++ "\n") ++
    String.join (readers.map fun r => r.json ++ "\n") ++
    String.join (registrationsScoped.map fun r => r.jsonArm "waapi-scoped" ++ "\n") ++
    String.join (readersScoped.map fun r => r.jsonArm "waapi-scoped" ++ "\n")

#guard goldenJsonl == include_str "../../../packages/contracts/golden/parts/morph-tween-waapi.jsonl"

#guard attrJsonl () == include_str "../../../packages/contracts/golden/parts/morph-tween-waapi.attr.jsonl"

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

/-! ## The nav width tail after a close (`waapi-nav-width-tail`) -/

section WidthTail

/-- The original's morph value `T` ms into a close from 1 to 0. -/
def closeAt (T : Rat) : Rat := 1 - ease (T / duration)

/-- Where a close crosses `activeCut`, so `is-morphing` turns off (JS 12947): `(1 - 612/680)^3 = 1/1000`. -/
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

/-- `is-morphing` is on exactly before `crossMs` on a close. -/
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

/-- **The original's tail.** It writes `--morph` inline every frame, so its width transition starts at `prev`. -/
theorem tail_orig_pos (v : Nav.Vp) (hp : Bool) (prev R : Rat) (hD : Nav.pillW v < Nav.panelW v) (h0 : 0 ≤ prev)
    (hl : prev < crossMs) (hR : crossMs ≤ R) : 0 < tailPx v hp (closeAt prev) (closeAt R) := by
  rw [tailPx_eq]
  have h1 := (morphing_iff prev h0).mpr hl
  have h2 := closeAt_after R hR
  exact Rat.mul_pos (by grind) (by grind)

/-- **No base change, no tail.** An unchanged base value starts no width jump. The driver writes no base on an open
(`waapi.driver.test.ts`, test "a close writes the base --morph ...; an open writes none"). -/
theorem tail_zero_of_base_still (v : Nav.Vp) (hp : Bool) (before after : Rat) (h : before = after) :
    tailPx v hp before after = 0 := by
  subst h; unfold tailPx; grind

/-- **Not a function of the frame.** The original's flip-frame width depends on the frame before (outside
`waapi_vis`). -/
theorem tail_not_view (v : Nav.Vp) (hp : Bool) (hD : Nav.pillW v < Nav.panelW v) :
    tailPx v hp (closeAt 500) (closeAt crossMs) ≠ tailPx v hp (closeAt 600) (closeAt crossMs) := by
  rw [tailPx_eq, tailPx_eq]
  intro h
  have hs := closeAt_strict 500 600 (by decide) (by decide) (by unfold duration; decide)
  have hpos : 0 < Nav.panelW v - Nav.pillW v := by grind
  have := Rat.mul_lt_mul_of_pos_left (show closeAt 600 - closeAt crossMs < closeAt 500 - closeAt crossMs by grind) hpos
  grind

/-! ### The base window -/

/-- How long before its `activeCut` marker a close starts writing the base `--morph`, in ms (`TAIL_WINDOW_MS`). -/
def tailWindow : Rat := 100

/-- A push from `f` to `t` opens a base window iff it closes and gets the `activeCut` marker (`baseWindow`). -/
def baseB (f t : Rat) : Bool := decide (t < f) && markerB f t activeCut

/-- The base window's delay in ms: `G` before the `activeCut` marker's, at least 0 (`baseDelay`). -/
def baseDelay (dl : Rat → Rat → Rat → Rat) (G f t : Rat) : Rat := max 0 (dl f t activeCut - G)

/-- The window writes the base `--morph` on frame `T`: from its delay until the animation ends. -/
def baseW (dl : Rat → Rat → Rat → Rat) (G : Rat) (w : VSt) (T : Rat) : Bool :=
  match w.anim with
  | none => false
  | some a => baseB a.f a.t && decide (a.st + baseDelay dl G a.f a.t ≤ T) && decide (T < a.st + duration)

/-- **The window covers the frame before the flip.** With sound delays, a frame at most `G` before a frame `R` at which
the close has reached `activeCut` is in the window. -/
theorem base_hits (P : WaapiPremises) (dl : Rat → Rat → Rat → Rat) (hd : DlSound dl) (G : Rat) (w : VSt) (a : Anim)
    (hw : w.anim = some a) (hb : baseB a.f a.t = true) (T R : Rat) (hR : reach a.f a.t activeCut (valA P a R))
    (hst : a.st < R) (h0 : a.st ≤ T) (hT : R - G ≤ T) (hend : T < a.st + duration) : baseW dl G w T = true := by
  have hdl := hd a.f a.t activeCut (R - a.st) (by grind) (by rw [← valA_path]; exact hR)
  have hm : max 0 (dl a.f a.t activeCut - G) ≤ T - a.st := by
    rw [Rat.max_def]; split <;> grind
  unfold baseW baseDelay
  simp only [hw, hb, Bool.true_and, Bool.and_eq_true, decide_eq_true_eq]
  exact ⟨by grind, hend⟩

/-- **On a hit the tail is the original's.** The window writes each frame's value as the base, and that value is the
original's on the frame (`waapi_frame_eq`), so the width transition starts from the same base to the same value. -/
theorem tail_eq_of_base (P : WaapiPremises) (v : Nav.Vp) (hp : Bool) (es es' : List Ev) (T R l l' : Rat)
    (h : monoB l (es ++ [.tick T]) = true) (h' : monoB l' (es' ++ [.tick R]) = true) :
    tailPx v hp (valV P (runV P initV es) (P.tl T)) (valV P (runV P initV es') (P.tl R)) =
      tailPx v hp (runO rest (es ++ [.tick T])).value (runO rest (es' ++ [.tick R])).value := by
  rw [waapi_frame_eq P es T l h, waapi_frame_eq P es' R l' h']

/-- **A miss stays below the cut.** If the window opens after the flip, the base is the push's reset `0`, so the jump
is to the flip frame's value `m ≤ activeCut`: at most `(panelW - pillW) · activeCut` and reversed. -/
theorem tail_miss_le (v : Nav.Vp) (hp : Bool) (m : Rat) (hD : Nav.pillW v ≤ Nav.panelW v) (h0 : 0 ≤ m)
    (h1 : m ≤ activeCut) :
    -((Nav.panelW v - Nav.pillW v) * activeCut) ≤ tailPx v hp 0 m ∧ tailPx v hp 0 m ≤ 0 := by
  rw [tailPx_eq]
  have hD' : 0 ≤ Nav.panelW v - Nav.pillW v := by grind
  have := Rat.mul_le_mul_of_nonneg_left h1 hD'
  have := Rat.mul_nonneg hD' h0
  constructor <;> grind

/-! ### Cost: script frames of the window against the saving -/

/-- Frame counts of a replay: frames, script frames of the original, of the fixed driver, and with the base window. -/
structure Cost where
  frames : Nat
  orig : Nat
  fix : Nat
  tail : Nat
deriving Repr, DecidableEq

/-- One event of the count; the finish handler runs once, on the first frame at or after the end (`d` records it). -/
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

/-- The driver's marker delay: 1 ms before the golden delay, at least 0 (`markerDelay`). -/
def dlTs (f t θ : Rat) : Rat := if reach f t θ f then 0 else max 0 (dlLo delayDepth f t θ - 1)

theorem dlTs_sound : DlSound dlTs := by
  intro f t θ e he hr
  have := dlLo_sound delayDepth f t θ e he hr
  unfold dlTs
  split
  · grind
  · rw [Rat.max_def]; split <;> grind

/-- The counts of the events `es` from the original `s` and the variant `w`, window `G`, the driver's delays. -/
def cost (G : Rat) (s : St) (w : VSt) (es : List Ev) : Cost :=
  (es.foldl (costStep dlTs G) (s, w, false, ⟨0, 0, 0, 0⟩)).2.2.2

/-- Both at rest at `1`, an open long finished. -/
def atOne : St × VSt :=
  let es := [Ev.push 1 false (-1000), .tick 0]
  (runO rest es, runV attrP initV es)

/-- A close from `1` pushed at `0`, frames every `g` ms until the first at or after the end. -/
def closeEvs (g : Rat) : List Ev :=
  .push 0 false 0 :: (List.range ((duration / g).ceil.toNat)).map fun k => .tick (g * ((k + 1 : Nat) : Rat))

/-- The counts of a close at frame gap `g` with window `G`. -/
def closeCost (G g : Rat) : Cost := cost G atOne.1 atOne.2 (closeEvs g)

/-- The two outcomes for the tail: modelled in the driver, or a look change. -/
inductive TailArm where
  | model
  | lookChange
deriving DecidableEq, Repr

/-- Model the tail iff the window's extra script frames stay below the frames the fixed driver saves. -/
def tailArm (c : Cost) : TailArm := if c.tail - c.fix < c.orig - c.fix then .model else .lookChange

theorem tailArm_model (c : Cost) (h : c.tail - c.fix < c.orig - c.fix) : tailArm c = .model := by
  unfold tailArm; simp [h]

theorem tailArm_look (c : Cost) (h : c.orig - c.fix ≤ c.tail - c.fix) : tailArm c = .lookChange := by
  unfold tailArm; simp; omega

/-- The display frame gaps the decision is made at: 60 Hz and 120 Hz. -/
def displayGaps : List Rat := [50 / 3, 25 / 3]

/-- The decision: model the tail iff it is cheaper than the saving at every display frame gap. -/
def tailDecision (G : Rat) : TailArm :=
  if displayGaps.all fun g => tailArm (closeCost G g) == .model then .model else .lookChange

/-- The frame gaps of the cost rows: 60 Hz, 120 Hz, and the flip-frame gaps measured on CI (Chromium about 22 ms,
macOS WebKit 45 to 100 ms, Linux WebKit 300 ms and more). -/
def costGaps : List Rat := [50 / 3, 25 / 3, 22, 45, 100, 300]

/-- The arm's wire name. -/
def TailArm.name : TailArm → String
  | .model => "model"
  | .lookChange => "lookChange"

/-- One cost row's counts. -/
def costFields (c : Cost) : List (String × Lean.Json) :=
  [("frames", .num c.frames), ("orig", .num c.orig), ("fix", .num c.fix), ("tail", .num c.tail)]

/-- The contents of `packages/contracts/golden/parts/morph-tween-waapi.tail.jsonl`: the window, its delay per push,
script frames per replayed case, and the cost of a close per frame gap. -/
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

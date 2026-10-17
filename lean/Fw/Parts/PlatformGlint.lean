import Fw.Parts.PlatformSweep
/-!
# platform.glint: the SMIL glint on the two secure-network dashes (P5 port, `faithful`)

Restated (not copied) from `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`, read independently of the TS part:

* 12166-12172: `keyTimes` $0;0.2;0.4;0.6;0.8;1$ and the `values` of `x1` and `x2` per side;
* 12150-12154 (the template of the `<animate>` pair): `dur 5s`, `repeatCount indefinite`, `begin indefinite`;
* 12186-12212: the visibility state: an observer with thresholds $0, 0.35, 0.6$ marks the stage visible at ratio
  $\ge 0.35$; a change of visibility or of `prefers-reduced-motion` clears the play flag and the timer, and sets a
  1000 ms timer only when visible and not reduced; the timer sets the play flag and then calls `beginElement()` on every
  `<animate>` (the animation clock restarts there);
* 12269-12275: initial `x1`/`x2` attributes (left $-200, -80$; right $200, 320$).

SMIL `calcMode` is `linear` (the default), so values are interpolated between key times. All values `Rat`.
-/
namespace Fw.Parts.PlatformGlint
open Fw.Parts.PlatformSweep (frac frac_mem frac_add_one)

/-! ## The animation -/

/-- Length of one SMIL cycle in ms (`dur="5s"`). $$D = 5000$$ -/
def dur : Rat := 5000

/-- Delay between becoming visible and the first `beginElement` (JS `1e3`). $$\Delta = 1000$$ ms. -/
def startDelay : Rat := 1000

/-- Visibility ratio at which the stage counts as visible (JS 0.35). $$\rho = 0.35 = \tfrac{7}{20}$$ -/
def minRatio : Rat := 7 / 20

/-- Linear mix. $$\operatorname{lerp}(a, b, w) = a + (b - a)\,w$$ -/
def lerp (a b w : Rat) : Rat := a + (b - a) * w

/-- Linear interpolation over six equally spaced key times $0, \tfrac15, \dots, 1$ (`keyTimes="0;0.2;...;1"`).

$$f(u) = \operatorname{lerp}\big(a_k, a_{k+1}, 5u - k\big)\ \text{ for } u \in \big[\tfrac k5, \tfrac{k+1}5\big]$$ -/
def interp (a0 a1 a2 a3 a4 a5 : Rat) (u : Rat) : Rat :=
  if u < 1 / 5 then lerp a0 a1 (5 * u)
  else if u < 2 / 5 then lerp a1 a2 (5 * u - 1)
  else if u < 3 / 5 then lerp a2 a3 (5 * u - 2)
  else if u < 4 / 5 then lerp a3 a4 (5 * u - 3)
  else lerp a4 a5 (5 * u - 4)

/-- Which dash. $$\mathit{side} \in \{\text{left}, \text{right}\}$$ -/
inductive Side | left | right
deriving Repr, DecidableEq

/-- `x1` at cycle fraction $u$. Left: $-200, 200, 200, 200, -200, -200$; right: $-200, -200, 200, -200, -200, -200$.

$$x_1(\mathit{side}, u) = \operatorname{interp}(a_0, \dots, a_5; u)$$ -/
def x1At : Side → Rat → Rat
  | .left, u => interp (-200) 200 200 200 (-200) (-200) u
  | .right, u => interp (-200) (-200) 200 (-200) (-200) (-200) u

/-- `x2` at cycle fraction $u$. Left: $-80, 320, 320, 320, -80, -80$; right: $-80, -80, 320, -80, -80, -80$.

$$x_2(\mathit{side}, u) = \operatorname{interp}(b_0, \dots, b_5; u)$$ -/
def x2At : Side → Rat → Rat
  | .left, u => interp (-80) 320 320 320 (-80) (-80) u
  | .right, u => interp (-80) (-80) 320 (-80) (-80) (-80) u

/-- Cycle fraction after $e$ ms of animation. $$u(e) = \operatorname{frac}(e / 5000)$$ -/
def cycle (e : Rat) : Rat := frac (e / dur)

/-- The gradient end points (x1, x2) of a side $e$ ms after the animation began.

$$g(\mathit{side}, e) = (x_1(\mathit{side}, u(e)),\ x_2(\mathit{side}, u(e)))$$ -/
def sample (s : Side) (e : Rat) : Rat × Rat := (x1At s (cycle e), x2At s (cycle e))

/-- The attributes before the first `beginElement`. Left $(-200, -80)$, right $(200, 320)$.

$$\mathit{rest}(\text{left}) = (-200, -80),\quad \mathit{rest}(\text{right}) = (200, 320)$$ -/
def rest : Side → Rat × Rat
  | .left => (-200, -80)
  | .right => (200, 320)

#guard sample .left 0 == (-200, -80)
#guard sample .left 1000 == (200, 320)
#guard sample .left 500 == (0, 120)
#guard sample .right 2000 == (200, 320)
#guard sample .right 5000 == (-200, -80)

/-- The interpolation of six values stays between their min and max. $$\forall u \in [0,1):\ \min a_k \le f(u) \le \max a_k$$ Here for the glint ranges. -/
theorem interp_between (a0 a1 a2 a3 a4 a5 lo hi u : Rat) (h0 : 0 ≤ u) (h1 : u < 1)
    (l0 : lo ≤ a0) (l1 : lo ≤ a1) (l2 : lo ≤ a2) (l3 : lo ≤ a3) (l4 : lo ≤ a4) (l5 : lo ≤ a5)
    (g0 : a0 ≤ hi) (g1 : a1 ≤ hi) (g2 : a2 ≤ hi) (g3 : a3 ≤ hi) (g4 : a4 ≤ hi) (g5 : a5 ≤ hi) :
    lo ≤ interp a0 a1 a2 a3 a4 a5 u ∧ interp a0 a1 a2 a3 a4 a5 u ≤ hi := by
  unfold interp lerp
  have seg : ∀ (p q w : Rat), lo ≤ p → lo ≤ q → p ≤ hi → q ≤ hi → 0 ≤ w → w ≤ 1 →
      lo ≤ p + (q - p) * w ∧ p + (q - p) * w ≤ hi := by
    intro p q w hp hq hp' hq' hw hw'
    by_cases hpq : p ≤ q
    · have m1 := Rat.mul_nonneg (show 0 ≤ q - p by grind) hw
      have m2 := Rat.mul_le_mul_of_nonneg_left hw' (show 0 ≤ q - p by grind)
      grind
    · have m1 := Rat.mul_nonneg (show 0 ≤ p - q by grind) hw
      have m2 := Rat.mul_le_mul_of_nonneg_left hw' (show 0 ≤ p - q by grind)
      grind
  split <;> rename_i c1
  · exact seg _ _ _ l0 l1 g0 g1 (by grind) (by grind)
  split <;> rename_i c2
  · exact seg _ _ _ l1 l2 g1 g2 (by grind) (by grind)
  split <;> rename_i c3
  · exact seg _ _ _ l2 l3 g2 g3 (by grind) (by grind)
  split <;> rename_i c4
  · exact seg _ _ _ l3 l4 g3 g4 (by grind) (by grind)
  · exact seg _ _ _ l4 l5 g4 g5 (by grind) (by grind)

/-- The cycle fraction is in $[0, 1)$. $$0 \le u(e) < 1$$ -/
theorem cycle_mem (e : Rat) : 0 ≤ cycle e ∧ cycle e < 1 := frac_mem _

/-- The glint is 5 s periodic. $$\operatorname{sample}(s, e + 5000) = \operatorname{sample}(s, e)$$ -/
theorem sample_periodic (s : Side) (e : Rat) : sample s (e + dur) = sample s e := by
  have : cycle (e + dur) = cycle e := by
    unfold cycle
    have h : (e + dur) / dur = e / dur + 1 := by unfold dur; grind
    rw [h, frac_add_one]
  unfold sample; rw [this]

/-- Both end points stay inside $[-200, 320]$. $$\forall e:\ -200 \le x_1, x_2 \le 320$$ The highlight never leaves the dash's gradient range. -/
theorem sample_range (s : Side) (e : Rat) :
    -200 ≤ (sample s e).1 ∧ (sample s e).1 ≤ 320 ∧ -200 ≤ (sample s e).2 ∧ (sample s e).2 ≤ 320 := by
  have hc := cycle_mem e
  unfold sample
  cases s <;> simp only [x1At, x2At] <;>
  · refine ⟨?_, ?_, ?_, ?_⟩ <;>
    first
    | exact (interp_between _ _ _ _ _ _ (-200) 320 _ hc.1 hc.2 (by grind) (by grind) (by grind) (by grind) (by grind) (by grind) (by grind) (by grind) (by grind) (by grind) (by grind) (by grind)).1
    | exact (interp_between _ _ _ _ _ _ (-200) 320 _ hc.1 hc.2 (by grind) (by grind) (by grind) (by grind) (by grind) (by grind) (by grind) (by grind) (by grind) (by grind) (by grind) (by grind)).2

/-! ## The play state -/

/-- State of the stage: visible, reduced motion, playing, the pending timer's due time, and when the animation began.

$$s = (h, g, v, \tau, t_0)$$ -/
structure St where
  h : Bool
  g : Bool
  v : Bool
  timer : Option Rat
  t0 : Option Rat
deriving Repr, DecidableEq

/-- State at mount, before the observer reports: hidden, reduced motion read, nothing playing. $$s_0 = (\bot, g, \bot, \emptyset, \emptyset)$$ -/
def init (reduced : Bool) : St := ⟨false, reduced, false, none, none⟩

/-- Clear the play flag and the timer; arm a new 1000 ms timer only when visible and not reduced (JS `i`, 12197-12199).

$$\operatorname{reset}(s, n) = s\{v := \bot,\ t_0 := \emptyset,\ \tau := (n + 1000 \text{ if } h \land \lnot g \text{ else } \emptyset)\}$$ -/
def reset (s : St) (now : Rat) : St :=
  { s with v := false, t0 := none, timer := if s.h && !s.g then some (now + startDelay) else none }

/-- Events the stage receives.

$$e \in \{\mathit{ratio}(r),\ \mathit{reduced}(b),\ \mathit{fire}\}$$ -/
inductive Ev
  /-- The observer's ratio crossed a threshold; carries the ratio. -/
  | ratio (r : Rat)
  /-- `prefers-reduced-motion` changed. -/
  | reduced (b : Bool)
  /-- The timer elapsed. -/
  | fire
deriving Repr

/-- Next state (JS 12186-12212).

$$\delta(s, \mathit{ratio}(r), n) = \begin{cases} s & (r \ge 0.35) = h \\ \operatorname{reset}(s\{h := r \ge 0.35\}, n) & \text{otherwise} \end{cases}$$
$$\delta(s, \mathit{reduced}(b), n) = \operatorname{reset}(s\{g := b\}, n)$$
$$\delta(s, \mathit{fire}, n) = \begin{cases} s\{v := \top,\ \tau := \emptyset,\ t_0 := n\} & \tau = \operatorname{some}(d),\ d \le n \\ s & \text{otherwise} \end{cases}$$ -/
def step (s : St) (now : Rat) : Ev → St
  | .ratio r =>
    let b := decide (minRatio ≤ r)
    if b == s.h then s else reset { s with h := b } now
  | .reduced b => reset { s with g := b } now
  | .fire =>
    match s.timer with
    | some d => if d ≤ now then { s with v := true, timer := none, t0 := some now } else s
    | none => s

/-- The invariant: playing or about to play only while visible and not reduced.

$$I(s) = \big(v \Rightarrow h \land \lnot g\big) \land \big(\tau \ne \emptyset \Rightarrow h \land \lnot g\big)$$ -/
def Inv (s : St) : Prop :=
  (s.v = true → s.h = true ∧ s.g = false) ∧ (s.timer.isSome = true → s.h = true ∧ s.g = false)

/-- The start state satisfies the invariant. $$I(s_0)$$ -/
theorem inv_init (r : Bool) : Inv (init r) := by
  unfold Inv init; simp

/-- Every step keeps the invariant.

$$I(s) \Rightarrow I(\delta(s, e, n))$$

So the glint plays only while the stage is visible and the visitor accepts motion. -/
theorem inv_step (s : St) (now : Rat) (e : Ev) (hs : Inv s) : Inv (step s now e) := by
  have rs : ∀ s' : St, Inv (reset s' now) := by
    intro s'
    cases hh : s'.h <;> cases hg : s'.g <;> simp [Inv, reset, hh, hg]
  cases e with
  | ratio r =>
    unfold step
    simp only []
    split
    · exact hs
    · exact rs _
  | reduced b => exact rs _
  | fire =>
    unfold step
    obtain ⟨hv, ht⟩ := hs
    cases hT : s.timer with
    | none => simpa [Inv, hT] using And.intro hv ht
    | some d =>
      simp only []
      split
      · have := ht (by simp [hT])
        unfold Inv
        simp [this]
      · unfold Inv
        exact ⟨hv, ht⟩

/-- Reduced motion never plays. $$I(s) \land g \Rightarrow \lnot v$$ -/
theorem reduced_never_plays (s : St) (hs : Inv s) (hg : s.g = true) : s.v = false := by
  obtain ⟨hv, _⟩ := hs
  cases h : s.v
  · rfl
  · have := hv h; grind

/-- Becoming visible (not reduced) arms the timer at $n + 1000$, and nothing plays yet.

$$\lnot h \land \lnot g \land r \ge 0.35 \Rightarrow \tau' = \operatorname{some}(n + 1000) \land \lnot v'$$ -/
theorem visible_arms (s : St) (now r : Rat) (hh : s.h = false) (hg : s.g = false) (hr : minRatio ≤ r) :
    (step s now (.ratio r)).timer = some (now + startDelay) ∧ (step s now (.ratio r)).v = false := by
  unfold step reset
  have : decide (minRatio ≤ r) = true := by simpa using hr
  simp [this, hh, hg]

/-- The timer fires only after its due time. $$\tau = \operatorname{some}(d) \land n \ge d \Rightarrow v' \land t_0' = \operatorname{some}(n)$$ -/
theorem fire_plays (s : St) (now d : Rat) (hT : s.timer = some d) (hd : d ≤ now) :
    (step s now .fire).v = true ∧ (step s now .fire).t0 = some now := by
  unfold step
  simp [hT, hd]

/-- The gradient end points to draw at time $n$: the sample once began, else the rest attributes.

$$\operatorname{view}(s, \mathit{side}, n) = \begin{cases} \operatorname{sample}(\mathit{side}, n - t_0) & t_0 \ne \emptyset \\ \mathit{rest}(\mathit{side}) & \text{otherwise} \end{cases}$$ -/
def view (s : St) (side : Side) (now : Rat) : Rat × Rat :=
  match s.t0 with
  | some a => sample side (now - a)
  | none => rest side

end Fw.Parts.PlatformGlint

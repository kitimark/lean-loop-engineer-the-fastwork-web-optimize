import Fw.Parts.MorphTween
/-!
# commission: the shrink card, the title underline trigger and the scene gate (P4 port, `faithful`)

Restated (not copied) from the original snapshot, read independently of the TS part:

* `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`
  * 3061-3075 (`C`, `w`, `T`, `E`): the two scroll bands. The enter band maps the card's top from $0.06\,h$ to $0.42\,h$
    ($h$ = inner height) onto $[0, 1]$; the exit band maps the section's bottom from $0.85\,h$ down to $0.35\,h$ onto $[0, 1]$;
    the smooth step $t^2(3 - 2t)$ shapes both;
  * 3092-3135 (`a`, the per-frame body): the target pair $(m, h')$, the follower $(n, r)$ (the enter value jumps up at once and
    eases down at $0.22$ per frame; the exit value eases both ways at $0.22$), snaps within $8 \cdot 10^{-4}$, the CSS custom
    properties, the `entering` / `shrinking` classes, the runway height, and another frame while not settled;
  * 3098-3110: reduced motion makes the targets steps at $0.5$ and the gain $1$;
  * 3125-3135: the underline observer: first time the heading is at least $0.45$ visible it enters (reduced motion: idle) and
    switches to idle 900 ms later, then the observer disconnects;
  * `dE` (2735-2782, scene scheduler): a card is *active* while its rect is within one viewport above and two below.
* `snapshot/.../assets/2.gBuqKVzi.css` 1-60, 916-1210: `--commission-shrink-scale: calc(1 - 0.083333 * max(...))`, radius
  $32\,\mathrm{px} \cdot \max(\cdot)$.

All values `Rat`; no `Float`.
-/
namespace Fw.Parts.Commission
open Fw.Parts.MorphTween (clamp01 clamp01_mem)

/-! ## Constants -/

/-- Enter band: card top, fractions of the viewport height (JS 3067). $$[a_0, a_1] = [0.06, 0.42]$$ -/
def enterLo : Rat := 6 / 100
/-- See `enterLo`. $$a_1 = 0.42$$ -/
def enterHi : Rat := 42 / 100
/-- Exit band: section bottom, fractions of the viewport height (JS 3072). $$[b_0, b_1] = [0.35, 0.85]$$ -/
def exitLo : Rat := 35 / 100
/-- See `exitLo`. $$b_1 = 0.85$$ -/
def exitHi : Rat := 85 / 100
/-- Follower gain per frame (JS 3115). $$g = 0.22$$ -/
def gain : Rat := 22 / 100
/-- Settle threshold (JS 3116, 3125). $$\varepsilon = 8 \cdot 10^{-4}$$ -/
def eps : Rat := 8 / 10000
/-- Shrink depth in the card's scale (CSS line 5). $$\kappa = 0.083333$$ -/
def depth : Rat := 83333 / 1000000
/-- Corner radius at full shrink, px (CSS line 6). $$\rho = 32$$ -/
def radius : Rat := 32
/-- Runway height, fraction of the viewport (JS 3121). $$0.06$$ -/
def runway : Rat := 6 / 100
/-- `entering` needs the card top above this fraction of the viewport (JS 3119). $$0.995$$ -/
def enterTopCut : Rat := 995 / 1000
/-- `entering` / `shrinking` need the band value above this (JS 3119-3120). $$0.04$$ -/
def classCut : Rat := 4 / 100
/-- Underline observer ratio (JS 3130). $$0.45$$ -/
def ulRatio : Rat := 45 / 100

/-! ## The bands -/

/-- Absolute value. $$|x| = \max(x, -x)$$ -/
def absR (x : Rat) : Rat := max x (-x)

/-- Smooth step (JS 3063). $$\operatorname{smooth}(x) = t^2 (3 - 2t),\quad t = \operatorname{clamp}(x)$$ Eases in and out. -/
def smooth (x : Rat) : Rat := clamp01 x * clamp01 x * (3 - 2 * clamp01 x)

#guard smooth 0 == 0
#guard smooth 1 == 1
#guard smooth (1 / 2) == 1 / 2
#guard smooth (-3) == 0
#guard smooth 7 == 1

/-- The smooth step stays in $[0, 1]$.

$$\forall x:\ 0 \le \operatorname{smooth}(x) \le 1$$

The card never over- or under-shoots. -/
theorem smooth_mem (x : Rat) : 0 ≤ smooth x ∧ smooth x ≤ 1 := by
  have h := clamp01_mem x
  unfold smooth
  generalize clamp01 x = t at *
  have h1 : 0 ≤ 3 - 2 * t := by grind
  have h2 : 0 ≤ t * t := Rat.mul_nonneg h.1 h.1
  have h3 := Rat.mul_nonneg h2 h1
  have h4 : t * t ≤ t := by
    have := Rat.mul_le_mul_of_nonneg_left h.2 h.1
    grind
  have h5 : t * t * (3 - 2 * t) ≤ 1 := by
    -- 1 - t^2 (3 - 2t) = (1 - t)^2 (1 + 2t)
    have e : 1 - t * t * (3 - 2 * t) = (1 - t) * (1 - t) * (1 + 2 * t) := by grind
    have : 0 ≤ (1 - t) * (1 - t) * (1 + 2 * t) :=
      Rat.mul_nonneg (Rat.mul_nonneg (by grind) (by grind)) (by grind)
    grind
  exact ⟨h3, h5⟩

/-- The enter value for a card whose top is `top` px in a viewport of height `h` (JS 3066-3069, `T`).

$$T(\mathit{top}, h) = \begin{cases} 1 & \mathit{top} \ge 0.42\,h \\ 0 & \mathit{top} \le 0.06\,h \\ \dfrac{\mathit{top} - 0.06\,h}{0.36\,h} & \text{between} \end{cases}$$

It is 1 (card fully shrunk) while the card is low on the screen and 0 once its top has reached 6 % of the height. -/
def enterRaw (top h : Rat) : Rat :=
  if enterHi * h ≤ top then 1 else if top ≤ enterLo * h then 0 else clamp01 ((top - enterLo * h) / ((enterHi - enterLo) * h))

/-- The exit value for a section whose bottom is `bottom` px (JS 3070-3075, `E`).

$$E(\mathit{bottom}, h) = \begin{cases} 0 & \mathit{bottom} \ge 0.85\,h \\ 1 & \mathit{bottom} \le 0.35\,h \\ \dfrac{0.85\,h - \mathit{bottom}}{0.5\,h} & \text{between} \end{cases}$$

How far the section has scrolled up and out. -/
def exitRaw (bottom h : Rat) : Rat :=
  if exitHi * h ≤ bottom then 0 else if bottom ≤ exitLo * h then 1 else clamp01 ((exitHi * h - bottom) / ((exitHi - exitLo) * h))

#guard enterRaw 1000 1000 == 1
#guard enterRaw 420 1000 == 1
#guard enterRaw 60 1000 == 0
#guard enterRaw 240 1000 == 1 / 2
#guard exitRaw 850 1000 == 0
#guard exitRaw 350 1000 == 1
#guard exitRaw 600 1000 == 1 / 2

/-- Both raw values are in $[0, 1]$, for every viewport height $h$.

$$\forall \mathit{top}, \mathit{bottom}, h \in \mathbb{Q}:\ 0 \le T(\mathit{top}, h) \le 1 \wedge 0 \le E(\mathit{bottom}, h) \le 1$$

The bands are fractions. -/
theorem raw_mem (top bottom h : Rat) : 0 ≤ enterRaw top h ∧ enterRaw top h ≤ 1 ∧ 0 ≤ exitRaw bottom h ∧ exitRaw bottom h ≤ 1 := by
  have a := clamp01_mem ((top - enterLo * h) / ((enterHi - enterLo) * h))
  have b := clamp01_mem ((exitHi * h - bottom) / ((exitHi - exitLo) * h))
  unfold enterRaw exitRaw
  split <;> split <;> grind

/-- What the follower chases: the smooth step of the raw value, or a step at one half under reduced motion (JS 3099-3100).

$$\mathrm{target}(x, \mathit{rm}) = \begin{cases} [x \ge \tfrac12] & \mathit{rm} \\ \operatorname{smooth}(x) & \text{otherwise} \end{cases}$$ -/
def target (rm : Bool) (x : Rat) : Rat :=
  if rm then (if 1 / 2 ≤ x then 1 else 0) else smooth x

/-- A target is in $[0, 1]$. $$\forall x, \mathit{rm}:\ 0 \le \mathrm{target}(x, \mathit{rm}) \le 1$$ -/
theorem target_mem (rm : Bool) (x : Rat) : 0 ≤ target rm x ∧ target rm x ≤ 1 := by
  unfold target
  cases rm
  · simpa using smooth_mem x
  · simp only [ite_true]; split <;> grind

/-! ## The follower -/

/-- The follower pair: the enter value and the exit value as last written (JS 3092: `n = 1, r = 0`).

$$P = (n, r) \in \mathbb{Q}^2$$ -/
structure Pair where
  n : Rat
  r : Rat
deriving Repr, BEq, DecidableEq

/-- The pair before the first frame. $$(n, r) = (1, 0)$$ The card starts shrunk. -/
def pair0 : Pair := ⟨1, 0⟩

/-- Gain of a frame. $$g(\mathit{rm}) = \begin{cases} 1 & \mathit{rm} \\ 0.22 & \text{otherwise} \end{cases}$$ -/
def gainOf (rm : Bool) : Rat := if rm then 1 else gain

/-- What one frame writes and asks for.

$$F = (n', r', \mathit{entering}, \mathit{shrinking}, \mathit{runway}, \mathit{more})$$ -/
structure Frame where
  n : Rat
  r : Rat
  entering : Bool
  shrinking : Bool
  runway : Option Rat
  more : Bool
deriving Repr, BEq, DecidableEq

/-- One frame of the per-frame body (JS 3092-3123).

$$\begin{aligned}
m &= \mathrm{target}(T(\mathit{top}, h)),\quad q = \mathrm{target}(E(\mathit{bottom}, h)),\quad g = g(\mathit{rm})\\
n_1 &= \begin{cases} m & m > n \\ n + (m - n)\,g & \text{otherwise}\end{cases},\quad r_1 = r + (q - r)\,g,\quad
n' = \begin{cases} m & |m - n_1| < \varepsilon \\ n_1 & \text{else}\end{cases},\quad r' = \begin{cases} q & |q - r_1| < \varepsilon \\ r_1 & \text{else}\end{cases}\\
\mathit{entering} &= \mathit{top} < 0.995\,h \wedge T > 0.04,\quad \mathit{shrinking} = E > 0.04,\\
\mathit{runway} &= \begin{cases} \bot & \mathit{compact} \vee \mathit{rm} \\ 0.06\,h & \text{otherwise}\end{cases},\quad
\mathit{more} = |m - n'| \ge \varepsilon \vee |q - r'| \ge \varepsilon
\end{aligned}$$

with $T, E$ the raw bands. The CSS then reads $\max(n', r')$ (`--commission-shrink`) and $n'$ (`--commission-enter-shrink`). -/
def frame (s : Pair) (top bottom h : Rat) (rm compact : Bool) : Frame :=
  let f := enterRaw top h
  let p := exitRaw bottom h
  let m := target rm f
  let q := target rm p
  let g := gainOf rm
  let n1 := if s.n < m then m else s.n + (m - s.n) * g
  let r1 := s.r + (q - s.r) * g
  let n2 := if absR (m - n1) < eps then m else n1
  let r2 := if absR (q - r1) < eps then q else r1
  ⟨n2, r2, decide (top < enterTopCut * h ∧ classCut < f), decide (classCut < p),
   if compact || rm then none else some (runway * h), decide (eps ≤ absR (m - n2) ∨ eps ≤ absR (q - r2))⟩

/-- The `--commission-shrink` value. $$\max(n', r')$$ -/
def Frame.shrink (f : Frame) : Rat := max f.n f.r

/-- The card scale from the shrink (CSS line 5). $$\mathrm{scale} = 1 - 0.083333\,\max(n', r')$$ -/
def Frame.scale (f : Frame) : Rat := 1 - depth * f.shrink

/-- The card radius in px from the shrink (CSS line 17-19). $$\mathrm{radius} = 32 \cdot \max(n', r')$$ -/
def Frame.radiusPx (f : Frame) : Rat := radius * f.shrink

#guard (frame pair0 5000 6000 1000 false false).n == 1
#guard (frame pair0 5000 6000 1000 false false).r == 0
#guard (frame pair0 5000 6000 1000 false false).more == false
#guard (frame pair0 5000 6000 1000 false false).runway == some 60
#guard (frame pair0 5000 6000 1000 false true).runway == none
#guard (frame pair0 0 1000 1000 false false).n == 78 / 100
#guard (frame ⟨1, 0⟩ 0 1000 1000 true false).n == 0

/-- The absolute value of zero is below the settle threshold. $$|0| < \varepsilon$$ -/
theorem abs_zero_lt : absR 0 < eps := by unfold absR eps; decide +kernel

/-- A settled pair is a fixed point.

$$\forall \mathit{top}, \mathit{bottom}, h, \mathit{rm}, c:\quad n = m \wedge r = q \Rightarrow n' = n \wedge r' = r \wedge \mathit{more} = \bot$$

The loop stops when nothing moves (the original stops requesting frames). -/
theorem frame_settled (top bottom h : Rat) (rm c : Bool)
    (s : Pair) (hn : s.n = target rm (enterRaw top h)) (hr : s.r = target rm (exitRaw bottom h)) :
    (frame s top bottom h rm c).n = s.n ∧ (frame s top bottom h rm c).r = s.r ∧ (frame s top bottom h rm c).more = false := by
  unfold frame
  simp only []
  rw [← hn, ← hr]
  generalize s.n = n at *
  generalize s.r = r at *
  have h1 : ¬ (n < n) := by grind
  have h2 : n + (n - n) * gainOf rm = n := by grind
  have h3 : r + (r - r) * gainOf rm = r := by grind
  have h4 : n - n = 0 := by grind
  have h5 : r - r = 0 := by grind
  have h6 := abs_zero_lt
  simp only [h1, ite_false, h4, h5, Rat.zero_mul, Rat.add_zero, h6, ite_true, true_and]
  simp only [decide_eq_false_iff_not]
  grind

/-- Under reduced motion the follower lands on the target in one frame.

$$\mathit{rm} \Rightarrow n' = m \wedge r' = q \wedge \mathit{more} = \bot$$

The gain is 1 (JS 3115). -/
theorem frame_reduced (s : Pair) (top bottom h : Rat) (c : Bool) :
    (frame s top bottom h true c).n = target true (enterRaw top h) ∧
    (frame s top bottom h true c).r = target true (exitRaw bottom h) ∧ (frame s top bottom h true c).more = false := by
  unfold frame gainOf
  simp only [ite_true]
  generalize target true (enterRaw top h) = m
  generalize target true (exitRaw bottom h) = q
  have h1 : (if s.n < m then m else s.n + (m - s.n) * 1) = m := by split <;> grind
  have h2 : s.r + (q - s.r) * 1 = q := by grind
  have h4 : m - m = 0 := by grind
  have h5 : q - q = 0 := by grind
  have := abs_zero_lt
  simp only [h1, h2, h4, h5, this, ite_true, true_and]
  simp only [decide_eq_false_iff_not]
  grind

/-- The exit follower approaches its target at the gain: the remaining distance is $(1-g)$ of the old one, until the snap.

$$\mathit{rm} = \bot,\ |q - r_1| \ge \varepsilon \Rightarrow r' - q = 0.78\,(r - q)$$

Geometric, never overshooting. -/
theorem frame_r_contracts (s : Pair) (top bottom h : Rat) (c : Bool)
    (hs : eps ≤ absR (target false (exitRaw bottom h) - (s.r + (target false (exitRaw bottom h) - s.r) * gain))) :
    (frame s top bottom h false c).r - target false (exitRaw bottom h) = (78 / 100) * (s.r - target false (exitRaw bottom h)) := by
  unfold frame gainOf
  have e : gain = 22 / 100 := rfl
  have hn : ¬ (absR (target false (exitRaw bottom h) - (s.r + (target false (exitRaw bottom h) - s.r) * gain)) < eps) := by grind
  simp only [Bool.false_eq_true, ite_false, hn]
  rw [e]
  grind

/-! ## The compact switch and the title -/

/-- The original's `A()` (JS 3085-3090): compact below this width, on small devices, or on touch up to 1200.

$$\mathrm{compact}(w, d, t) = (w \le 1000) \vee (d \le 500) \vee (t \wedge w \le 1200)$$

with $w$ the width, $d$ the device width and $t$ = (`hover: none` and `pointer: coarse`). -/
def compact (w d : Rat) (touch : Bool) : Bool := decide (w ≤ 1000 ∨ d ≤ 500 ∨ (touch = true ∧ w ≤ 1200))

#guard compact 1000 1920 false
#guard !compact 1001 1920 false
#guard compact 1001 500 false
#guard !compact 1001 501 false
#guard compact 1200 1920 true
#guard !compact 1201 1920 true

/-- The title is "wrapped" when compact and its text spans more than one line box (JS 3077-3084).

$$\mathrm{wrapped}(c, k) = c \wedge k > 1$$ -/
def titleWrapped (c : Bool) (rects : Nat) : Bool := c && decide (1 < rects)

#guard titleWrapped true 2
#guard !titleWrapped true 1
#guard !titleWrapped false 3

/-! ## The underline -/

/-- The underline's phase (JS 3085: `x`).

$$\mathrm{Ul} = \{\mathrm{hidden}, \mathrm{enter}, \mathrm{idle}\}$$ -/
inductive Ul where
  | hidden | enter | idle
deriving Repr, BEq, DecidableEq

/-- The observer fires the underline when the heading is intersecting at ratio at least $0.45$ (JS 3130).

$$\mathrm{fire}(i, \rho) = i \wedge \rho \ge 0.45$$ -/
def ulFire (isInt : Bool) (ratio : Rat) : Bool := isInt && decide (ulRatio ≤ ratio)

/-- What firing does: `enter` (idle at once under reduced motion). $$\mathrm{start}(\mathit{rm}) = \begin{cases} \mathrm{idle} & \mathit{rm} \\ \mathrm{enter} & \text{else}\end{cases}$$ -/
def ulStart (rm : Bool) : Ul := if rm then .idle else .enter

/-- The 900 ms timer (JS 3131). $$\mathrm{timer}(\mathrm{enter}) = \mathrm{idle}$$ and every other phase stays. -/
def ulTimer : Ul → Ul
  | .enter => .idle
  | u => u

/-- The delay of that timer in ms (JS 3131). $$900$$ -/
def ulDelay : Nat := 900

#guard !ulFire true (44 / 100)
#guard ulFire true (45 / 100)
#guard !ulFire false 1

/-- Firing leaves the hidden phase. $$\forall \mathit{rm}:\ \mathrm{start}(\mathit{rm}) \ne \mathrm{hidden}$$ -/
theorem ulStart_ne (rm : Bool) : ulStart rm ≠ .hidden := by cases rm <;> simp [ulStart]

/-- The timer settles on idle. $$\forall \mathit{rm}:\ \mathrm{timer}(\mathrm{start}(\mathit{rm})) = \mathrm{idle}$$ -/
theorem ulTimer_start (rm : Bool) : ulTimer (ulStart rm) = .idle := by cases rm <;> rfl

/-- Idle is stable. $$\mathrm{timer}(\mathrm{idle}) = \mathrm{idle}$$ -/
theorem ulTimer_idle : ulTimer .idle = .idle := rfl

/-! ## The scene gate -/

/-- A card is *active* while its rect reaches from one viewport above to two below (JS 2723-2726, `lE`).

$$\mathrm{active}(\mathit{top}, \mathit{bottom}, h) = (\mathit{bottom} \ge -h) \wedge (\mathit{top} \le 2h)$$

Off-screen cards pause their animations. -/
def sceneActive (top bottom h : Rat) : Bool := decide (-h ≤ bottom ∧ top ≤ 2 * h)

#guard sceneActive 0 800 800
#guard sceneActive 1600 2400 800
#guard !sceneActive 1601 2400 800
#guard sceneActive (-900) (-800) 800
#guard !sceneActive (-900) (-801) 800

end Fw.Parts.Commission

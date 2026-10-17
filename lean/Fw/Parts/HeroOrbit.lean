/-!
# hero.orbit: the load "ring splash" of the ten desktop cards (P1, `faithful`)

Restated (not copied) from the original snapshot, read independently of the TS part:

* `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`
  * 4016-4020: design canvas $1512 \times 779$ (centre height $d = 389.5$), spin $-14^\circ$ (rewind), $140^\circ$ (surge),
    rewind share $0.48$, peak blur $5.5$ px;
  * 4036-4045 (`E`): the four phases of the splash clock, by elapsed ms $e$ (idle before 900, rewind then surge up to
    1380, after);
  * 4046-4057 (`O`): the ring angle; 4058-4066 (`j`): the ring radius (248 px, pulled in to 188 and out again);
    4067-4075 (`N`): the motion blur;
  * 4076-4091 (`F`): the start offset of a card on the ring; 4092-4094 (`I`): the scatter vector on exit;
  * 4110-4120 (`L`): the inline variables of a card: delay $8 + 28k$ ms, start scale $76/w$;
  * 4138-4229: the splash itself: a rAF loop writes the start offsets of every card and `--ring-motion-blur`; the
    cards switch to the expanded canvas at $e \ge 1164$; a timer ends it at $1820$ ms (and at once under reduced motion
    or at width $\le 600$);
  * CSS `2.gBuqKVzi.css` 1969-1999 (keyframes: `--entered` is 0 until 68% of 1.7 s, then 1; `ring-appear` 0.12 s) and
    2010-2035 (the edge push below 1280 px).

Times and angles are `Rat` (angles in degrees). The one place that needs a trigonometric function (`F`, the position on
the ring) uses `Float` and is checked by golden vectors only (no theorem about it).
-/
namespace Fw.Parts.HeroOrbit

/-! ## Constants -/

/-- Design canvas width in px (JS 4016). $$W = 1512$$ The stage is laid out at this width. -/
def canvasW : Rat := 1512

/-- Design canvas height in px (JS 4016). $$H = 779$$ The stage is laid out at this height. -/
def canvasH : Rat := 779

/-- Rewind share of the 480 ms move (JS 4019). $$\rho = 0.48 = \tfrac{12}{25}$$ How much of it is the rewind. -/
def rewindShare : Rat := 12 / 25

/-- Peak motion blur in px (JS 4020). $$\beta = 5.5 = \tfrac{11}{2}$$ The blur at the turning point. -/
def peakBlur : Rat := 11 / 2

/-- Ring rotation speed in degrees per ms (JS 4047: one turn per 32 s).

$$\omega = \tfrac{360}{32000} = \tfrac{9}{800}\ ^\circ/\mathrm{ms}$$

The ring turns slowly all the time. -/
def omega : Rat := 9 / 800

/-- The rewind turn in degrees (JS 4017). $$p = -14$$ How far the ring goes back. -/
def rewindDeg : Rat := -14

/-- The surge turn in degrees (JS 4018). $$m = 140$$ How far the ring jumps ahead. -/
def surgeDeg : Rat := 140

/-- When the move starts, ms (JS 4037). $$s = 900$$ The ring only idles before this. -/
def moveStart : Rat := 900

/-- When the move ends, ms (JS 4038, 4052). $$q = 1380 = 900 + 480$$ After this the ring spins fast. -/
def moveEnd : Rat := 1380

/-- Radius at rest in px (JS 4083). $$r_0 = 248$$ The ring's radius when it is not moving. -/
def restRadius : Rat := 248

/-- Radius at the end of the rewind in px (JS 4089). $$r_1 = 188 = 248 - 60$$ The pulled-in ring. -/
def pulledRadius : Rat := 188

/-- Delay of the first card in ms (JS 4121). $$a = 8$$ The lowest `--orbit-enter-delay`. -/
def delayBase : Rat := 8

/-- Delay step per `enterDelay` unit in ms (JS 4121). $$b = 28$$ Added per unit. -/
def delayStep : Rat := 28

/-- The card entrance animation's duration in ms (CSS `card-from-ring` 1.7 s). $$D = 1700$$ -/
def cardDur : Rat := 1700

/-- Where `--entered` leaves 0 inside the entrance, as a share (CSS keyframe `0%, 68%`).

$$\kappa = 0.68 = \tfrac{17}{25}$$

Up to here the card is still at the start offset. -/
def enteredFrom : Rat := 17 / 25

/-- The expand moment in ms (JS 4155).

$$x = 1164$$

From here the cards use the real canvas width. -/
def expandAt : Rat := 1164

/-- The splash end timer in ms (JS 4229). $$T = 1820$$ When `is-splash-done` is set. -/
def splashEnd : Rat := 1820

/-- The design width below which the expanded cards are pulled in (JS 4078, CSS 2027). $$1280$$ -/
def pullBelow : Rat := 1280

/-- The share of the missing width that pulls a card in (JS 4079, CSS 2027). $$\gamma = 0.35 = \tfrac{7}{20}$$ -/
def pullShare : Rat := 7 / 20

/-- Start scale numerator: a card starts as a 76 px wide chip (JS 4119). $$c = 76$$ -/
def chip : Rat := 76

/-! ## The splash clock -/

/-- The four phases of the move. $$\mathrm{idle} \prec \mathrm{rewind} \prec \mathrm{surge} \prec \mathrm{after}$$ -/
inductive Phase
  | idle | rewind | surge | after
deriving Repr, DecidableEq

/-- A phase with its progress inside it. $$(\mathit{phase}, t)\quad t \in [0, 1]$$ -/
structure Ph where
  phase : Phase
  t : Rat
deriving Repr, DecidableEq

/-- The phase at elapsed ms $e$ (JS 4036-4045).

$$\operatorname{phase}(e) = \begin{cases} (\mathrm{idle}, 0) & e < 900 \\ (\mathrm{after}, 1) & e \ge 1380 \\ (\mathrm{rewind}, u/\rho) & u < \rho \\ (\mathrm{surge}, (u - \rho)/(1 - \rho)) & \text{otherwise} \end{cases},\quad u = \tfrac{e - 900}{480}$$

Which part of the move the splash is in. -/
def phase (e : Rat) : Ph :=
  if e < moveStart then ⟨.idle, 0⟩
  else if moveEnd ≤ e then ⟨.after, 1⟩
  else
    let u := (e - moveStart) / 480
    if u < rewindShare then ⟨.rewind, u / rewindShare⟩ else ⟨.surge, (u - rewindShare) / (13 / 25)⟩

#guard phase 0 == ⟨.idle, 0⟩
#guard phase 900 == ⟨.rewind, 0⟩
#guard phase 1130.4 == ⟨.surge, 0⟩
#guard phase 1380 == ⟨.after, 1⟩

/-- Rewind easing. $$e_5(t) = 1 - (1 - t)^5$$ Fast first, slow last. -/
def ease5 (t : Rat) : Rat := 1 - (1 - t) * (1 - t) * (1 - t) * (1 - t) * (1 - t)

/-- Surge easing. $$e_3(t) = 1 - (1 - t)^3$$ Fast first, slow last. -/
def ease3 (t : Rat) : Rat := 1 - (1 - t) * (1 - t) * (1 - t)

/-- The ring angle in degrees at elapsed ms $e$ (JS 4046-4057).

$$\theta(e) = \begin{cases} \omega e & \text{idle} \\ \omega e + p\,e_5(t) & \text{rewind} \\ \omega e + p\,(1 - t^2) + m\,e_3(t) & \text{surge} \\ 1380\,\omega + m + 22\,\omega\,(e - 1380) & \text{after} \end{cases}$$

The slow spin, the small step back, the jump forward, then a fast spin (22 times the idle speed). -/
def angleDeg (e : Rat) : Rat :=
  let n := e * omega
  match phase e with
  | ⟨.idle, _⟩ => n
  | ⟨.rewind, t⟩ => n + rewindDeg * ease5 t
  | ⟨.surge, t⟩ => n + rewindDeg * (1 - t * t) + surgeDeg * ease3 t
  | ⟨.after, _⟩ => moveEnd * omega + surgeDeg + (e - moveEnd) * omega * 22

/-- The ring radius in px (JS 4058-4066).

$$r(e) = \begin{cases} 248 & \text{idle, after} \\ 248 - 60\,e_5(t) & \text{rewind} \\ 188 + 60\,e_3(t) & \text{surge} \end{cases}$$

In by 60 px, then out again. -/
def radius (e : Rat) : Rat :=
  match phase e with
  | ⟨.idle, _⟩ => restRadius
  | ⟨.after, _⟩ => restRadius
  | ⟨.rewind, t⟩ => restRadius - 60 * ease5 t
  | ⟨.surge, t⟩ => pulledRadius + 60 * ease3 t

/-- The motion blur in px (JS 4067-4075).

$$b(e) = \begin{cases} 0 & \text{idle, after} \\ \beta\,e_5(t) & \text{rewind} \\ \beta\,(1 - t)^2 & \text{surge} \end{cases}$$

Zero at rest, peak at the turn. -/
def blur (e : Rat) : Rat :=
  match phase e with
  | ⟨.idle, _⟩ => 0
  | ⟨.after, _⟩ => 0
  | ⟨.rewind, t⟩ => peakBlur * ease5 t
  | ⟨.surge, t⟩ => peakBlur * ((1 - t) * (1 - t))

#guard angleDeg 0 == 0
#guard radius 900 == 248
#guard radius 1130.4 == 188
#guard blur 1130.4 == 11 / 2
#guard blur 1380 == 0

/-- The ease polynomials are 0 at 0 and 1 at 1. $$e_5(0) = e_3(0) = 0,\quad e_5(1) = e_3(1) = 1$$ -/
theorem ease_ends : ease5 0 = 0 ∧ ease3 0 = 0 ∧ ease5 1 = 1 ∧ ease3 1 = 1 := by
  refine ⟨?_, ?_, ?_, ?_⟩ <;> decide +kernel

/-- Idle ends where the rewind starts: the angle is continuous at 900 ms.

$$\theta(900) = 900\,\omega = \tfrac{81}{8}$$

No jump when the move starts. -/
theorem angle_cont_start : angleDeg 900 = 900 * omega := by decide +kernel

/-- The rewind ends where the surge starts: the angle is continuous at 1130.4 ms.

$$\lim_{t \to 1^-} \bigl(\omega e + p\,e_5(t)\bigr) = \omega e + p = \theta(e)\big|_{e = 1130.4},\quad \text{surge}(0) = \omega e + p$$

No jump at the turn. -/
theorem angle_cont_turn : angleDeg (11304 / 10) = (11304 / 10) * omega + rewindDeg := by decide +kernel

/-- The surge ends where the fast spin starts: the angle is continuous at 1380 ms.

$$\lim_{t \to 1^-}\bigl(\omega e + p\,(1 - t^2) + m\,e_3(t)\bigr) = 1380\,\omega + m = \theta(1380)$$

No jump when the move ends (the value at 1380 is the fast spin's start). -/
theorem angle_cont_end : angleDeg 1380 = 1380 * omega + surgeDeg := by decide +kernel

/-- The radius is continuous at the three joins.

$$r(900) = 248,\quad r(1130.4) = 188,\quad r(1380) = 248$$

The ring is never torn. -/
theorem radius_joins : radius 900 = 248 ∧ radius (11304 / 10) = 188 ∧ radius 1380 = 248 := by
  refine ⟨?_, ?_, ?_⟩ <;> decide +kernel

/-- The blur is zero at both ends of the move and peaks at the turn.

$$b(900) = 0,\quad b(1130.4) = \beta,\quad b(1380) = 0$$

The blur is a bump. -/
theorem blur_joins : blur 900 = 0 ∧ blur (11304 / 10) = peakBlur ∧ blur 1380 = 0 := by
  refine ⟨?_, ?_, ?_⟩ <;> decide +kernel

/-- Outside the move the ring has its rest radius and no blur.

$$e < 900 \lor e \ge 1380 \;\Rightarrow\; r(e) = 248 \land b(e) = 0$$

At load and after the move nothing is drawn but the ring. -/
theorem rest_outside (e : Rat) (h : e < 900 ∨ 1380 ≤ e) : radius e = restRadius ∧ blur e = 0 := by
  unfold radius blur phase moveStart moveEnd
  rcases h with h | h
  · simp [h]
  · have : ¬ e < 900 := by grind
    simp [this, h]

/-- The ease polynomials stay in the unit interval on it.

$$0 \le t \le 1 \;\Rightarrow\; 0 \le e_3(t) \le 1 \;\land\; 0 \le e_5(t) \le 1$$ -/
theorem ease3_mem (t : Rat) (h0 : 0 ≤ t) (h1 : t ≤ 1) : 0 ≤ ease3 t ∧ ease3 t ≤ 1 := by
  unfold ease3
  have hu0 : 0 ≤ 1 - t := by grind
  have hu1 : 1 - t ≤ 1 := by grind
  have h2' : 0 ≤ (1 - t) * (1 - t) := Rat.mul_nonneg hu0 hu0
  have h2 : (1 - t) * (1 - t) ≤ 1 := by
    have := Rat.mul_le_mul_of_nonneg_left hu1 hu0
    grind
  have h3' : 0 ≤ (1 - t) * (1 - t) * (1 - t) := Rat.mul_nonneg h2' hu0
  have h3 : (1 - t) * (1 - t) * (1 - t) ≤ 1 := by
    have := Rat.mul_le_mul_of_nonneg_left hu1 h2'
    grind
  grind

/-- The phase progress lies in the unit interval.

$$\forall e:\quad 0 \le t(e) \le 1$$

Whatever the time, the progress inside a phase is a share. -/
theorem phase_t_mem (e : Rat) : 0 ≤ (phase e).t ∧ (phase e).t ≤ 1 := by
  unfold phase moveStart moveEnd rewindShare
  by_cases h1 : e < 900
  · simp only [h1, ite_true]; constructor <;> decide +kernel
  · by_cases h2 : 1380 ≤ e
    · simp only [h1, h2, ite_true, ite_false]; constructor <;> decide +kernel
    · by_cases h3 : (e - 900) / 480 < 12 / 25
      · simp only [h1, h2, h3, ite_true, ite_false]
        constructor <;> grind
      · simp only [h1, h2, h3, ite_true, ite_false]
        constructor <;> grind

/-- The blur of a phase value.

$$b(\mathit{ph}) = \begin{cases} \beta\,e_5(t) & \text{rewind} \\ \beta\,(1-t)^2 & \text{surge} \\ 0 & \text{otherwise} \end{cases}$$

The same formula as `blur`, on the phase. -/
def blurOf (ph : Ph) : Rat :=
  match ph with
  | ⟨.rewind, t⟩ => peakBlur * ease5 t
  | ⟨.surge, t⟩ => peakBlur * ((1 - t) * (1 - t))
  | _ => 0

/-- `blur` is `blurOf` of the phase. $$b(e) = b(\operatorname{phase}(e))$$ Only the phase matters. -/
theorem blur_eq (e : Rat) : blur e = blurOf (phase e) := by
  unfold blur blurOf
  cases phase e with
  | mk p t => cases p <;> rfl

/-- The blur never exceeds its peak while the move runs.

$$\forall e:\quad 0 \le b(e) \le \beta$$

The blur is bounded by 5.5 px. -/
theorem blur_mem (e : Rat) : 0 ≤ blur e ∧ blur e ≤ peakBlur := by
  rw [blur_eq]
  have hp : (0 : Rat) ≤ peakBlur := by decide +kernel
  have h := phase_t_mem e
  cases hq : phase e with
  | mk p t =>
    rw [hq] at h
    simp only at h
    have hu0 : 0 ≤ 1 - t := by grind
    have hu1 : 1 - t ≤ 1 := by grind
    have a2 : 0 ≤ (1 - t) * (1 - t) := Rat.mul_nonneg hu0 hu0
    have b2 : (1 - t) * (1 - t) ≤ 1 := by have := Rat.mul_le_mul_of_nonneg_left hu1 hu0; grind
    have a3 : 0 ≤ (1 - t) * (1 - t) * (1 - t) := Rat.mul_nonneg a2 hu0
    have b3 : (1 - t) * (1 - t) * (1 - t) ≤ 1 := by have := Rat.mul_le_mul_of_nonneg_left hu1 a2; grind
    have a4 : 0 ≤ (1 - t) * (1 - t) * (1 - t) * (1 - t) := Rat.mul_nonneg a3 hu0
    have b4 : (1 - t) * (1 - t) * (1 - t) * (1 - t) ≤ 1 := by have := Rat.mul_le_mul_of_nonneg_left hu1 a3; grind
    have a5 : 0 ≤ (1 - t) * (1 - t) * (1 - t) * (1 - t) * (1 - t) := Rat.mul_nonneg a4 hu0
    have b5 : (1 - t) * (1 - t) * (1 - t) * (1 - t) * (1 - t) ≤ 1 := by have := Rat.mul_le_mul_of_nonneg_left hu1 a4; grind
    have e0 : 0 ≤ ease5 t := by unfold ease5; grind
    have e1 : ease5 t ≤ 1 := by unfold ease5; grind
    cases p
    · simp only [blurOf]; exact ⟨Std.le_refl _, hp⟩
    · simp only [blurOf]
      exact ⟨Rat.mul_nonneg hp e0, by have := Rat.mul_le_mul_of_nonneg_left e1 hp; grind⟩
    · simp only [blurOf]
      exact ⟨Rat.mul_nonneg hp a2, by have := Rat.mul_le_mul_of_nonneg_left b2 hp; grind⟩
    · simp only [blurOf]; exact ⟨Std.le_refl _, hp⟩

/-! ## The entrance and its timer -/

/-- A card's `--orbit-enter-delay` in ms (JS 4121).

$$\delta(k) = 8 + 28\,k$$

Cards with a bigger `enterDelay` start later. -/
def enterDelay (k : Nat) : Rat := delayBase + delayStep * k

/-- The largest `enterDelay` unit among the ten pieces (data: 0 to 4). $$k_{\max} = 4$$ -/
def maxUnit : Nat := 4

/-- The splash timer is the last card's end: delay plus the entrance duration.

$$\delta(4) + D = 120 + 1700 = 1820 = T$$

The timer fires exactly when the slowest card finishes. -/
theorem splash_end_eq : enterDelay maxUnit + cardDur = splashEnd := by decide +kernel

/-- The expand moment is when the first card leaves the start offset.

$$\delta(0) + \kappa D = 8 + 1156 = 1164 = x$$

The cards take the real canvas width exactly when the first one begins to move in. -/
theorem expand_eq : enterDelay 0 + enteredFrom * cardDur = expandAt := by decide +kernel

/-- The move (1380 ms) ends before the splash timer. $$1380 < 1820$$ The ring has finished moving when the splash ends. -/
theorem move_before_end : moveEnd < splashEnd := by decide +kernel

/-- The expand moment lies inside the move. $$900 < 1164 < 1380$$ -/
theorem expand_in_move : moveStart < expandAt ∧ expandAt < moveEnd := by
  refine ⟨?_, ?_⟩ <;> decide +kernel

/-- A card's start scale is below 1 for every card at least 76 px wide.

$$w > 76 \;\Rightarrow\; 0 < \tfrac{76}{w} < 1$$

A card always grows into place. -/
theorem ring_scale_lt_one (w : Rat) (h : 76 < w) : 0 < chip / w ∧ chip / w < 1 := by
  unfold chip
  have hw : 0 < w := by grind
  constructor
  · have e : (76 : Rat) / w * w = 76 := Rat.div_mul_cancel (by grind)
    generalize (76 : Rat) / w = q at *
    by_cases hq : 0 < q
    · exact hq
    · have := Rat.mul_le_mul_of_nonneg_right (show q ≤ 0 by grind) (show 0 ≤ w by grind)
      grind
  · rw [Rat.div_lt_iff hw]; grind

/-! ## Edge push below 1280 px -/

/-- The pull-in of the side cards in px at a stage or viewport width $w$ (JS 4078, CSS 2027).

$$\operatorname{push}(w) = \max\bigl(0,\ (1280 - w)\cdot 0.35\bigr)$$

Narrow screens pull the side cards towards the centre. -/
def push (w : Rat) : Rat := max 0 ((pullBelow - w) * pullShare)

/-- No pull at 1280 px and above. $$w \ge 1280 \;\Rightarrow\; \operatorname{push}(w) = 0$$ -/
theorem push_zero (w : Rat) (h : pullBelow ≤ w) : push w = 0 := by
  unfold push pullShare
  have : (pullBelow - w) * (7 / 20) ≤ 0 := by unfold pullBelow at h ⊢; grind
  grind

/-- The pull grows as the screen narrows. $$w_1 \le w_2 \;\Rightarrow\; \operatorname{push}(w_2) \le \operatorname{push}(w_1)$$ -/
theorem push_antitone (w1 w2 : Rat) (h : w1 ≤ w2) : push w2 ≤ push w1 := by
  unfold push pullShare pullBelow
  grind

/-- The pull at the 601 px floor of the band. $$\operatorname{push}(601) = 237.65$$ (the largest value the CSS band reaches) -/
theorem push_at_floor : push 601 = 4753 / 20 := by decide +kernel

/-- A card's left edge in px in the band $601 \le w \le 1511$ (CSS 2010-2025).

$$\ell = \begin{cases} L - \operatorname{push}(w) & \text{left side} \\ w - R + \operatorname{push}(w) - \text{width} \ \text{(from the right)} & \text{right side} \end{cases}$$

Here the right side is `right: R - push` (the box is placed from the right edge), so its left edge is $w - (R - \operatorname{push}(w)) - \text{width}$. -/
def leftEdge (isLeft : Bool) (leftPx rightPx width vw : Rat) : Rat :=
  if isLeft then leftPx - push vw else vw - (rightPx - push vw) - width

/-- At a full-size screen (1512) a right card sits at its design left. With $R = W - L - \text{width}$:

$$\operatorname{leftEdge}(\text{right}, L, W - L - w, w, W) = L$$

(`--orbit-right-px` is the design right gap, JS 4113.) -/
theorem leftEdge_right_at_canvas (L w : Rat) : leftEdge false L (canvasW - L - w) w canvasW = L := by
  unfold leftEdge push pullBelow pullShare canvasW
  have : max (0 : Rat) ((1280 - 1512) * (7 / 20)) = 0 := by decide +kernel
  rw [this]; grind

/-! ## Scatter -/

/-- The horizontal scatter on exit in vw (JS 4092-4094).

$$\operatorname{sx}(\ell) = \begin{cases} -48 & \ell < 756 \\ 48 & \text{otherwise} \end{cases},\quad \ell = \text{left px},\ 756 = 1512/2$$

Cards on the left fly left, cards on the right fly right. -/
def scatterX (leftPx : Rat) : Rat := if leftPx / canvasW * 100 < 50 then -48 else 48

/-- The vertical scatter on exit in vh (JS 4093).

$$\operatorname{sy}(\ell, \tau) = \begin{cases} -22 & \tau < 25 \\ 32 & \tau > 55 \\ 10 & \text{left half, otherwise} \\ -8 & \text{right half, otherwise} \end{cases},\quad \tau = \tfrac{\text{top px}}{779}\cdot 100$$

Cards near the top rise, cards near the bottom fall. -/
def scatterY (leftPx topPx : Rat) : Rat :=
  let t := topPx / canvasH * 100
  if t < 25 then -22 else if 55 < t then 32 else if leftPx / canvasW * 100 < 50 then 10 else -8

/-- The scatter is left-right antisymmetric in x. $$\operatorname{sx}(\ell) \in \{-48, 48\}$$ -/
theorem scatterX_cases (l : Rat) : scatterX l = -48 ∨ scatterX l = 48 := by
  unfold scatterX; split <;> simp

/-! ## The ten pieces (data restated from JS 3322-3463) and the order on the ring -/

/-- One hero card piece: left px, top px, width, height, rest rotation (degrees), `enterDelay` unit, float flag.

$$(\ell, \tau, w, h, \varphi, k, f)$$ -/
structure Piece where
  id : String
  left : Rat
  top : Rat
  width : Rat
  height : Rat
  rotate : Rat
  unit : Nat
  float : Bool
deriving Repr

/-- The ten pieces in source order. $$\text{pieces}$$ -/
def pieces : List Piece := [
  ⟨"chapavich", -27, 716/10, 195, 243, 305/100, 1, false⟩,
  ⟨"buttercup", 11551/10, -66, 193, 240, 4, 0, false⟩,
  ⟨"leobeer", 1281/10, -54, 193, 240, 4, 0, false⟩,
  ⟨"slayalldeep", 1972/10, 2117/10, 203, 252, -2, 2, false⟩,
  ⟨"bold", -109/10, 3466/10, 238, 297, 4, 3, true⟩,
  ⟨"weng", 807/10, 5256/10, 258, 322, 305/100, 4, false⟩,
  ⟨"pakincht", 11544/10, 6062/10, 214, 266, 381/100, 4, false⟩,
  ⟨"peter", 13051/10, 50, 193, 240, 4, 1, false⟩,
  ⟨"mod", 13469/10, 5075/10, 190, 235, -4, 3, false⟩,
  ⟨"nam", 1273, 265, 230, 287, -518/100, 2, true⟩]

/-- Ten pieces. $$|\text{pieces}| = 10$$ -/
theorem pieces_len : pieces.length = 10 := by decide +kernel

/-- The largest `enterDelay` unit in the data is `maxUnit`. $$\max_i k_i = 4$$ -/
theorem pieces_max_unit : (pieces.map (·.unit)).foldl max 0 = maxUnit := by decide +kernel

/-- Every card is wider than the 76 px chip, so its start scale is below 1. $$\forall i:\ 76 < w_i$$ -/
theorem pieces_wider_than_chip : pieces.all (fun p => decide (chip < p.width)) = true := by decide +kernel

/-- The deck slots for phones (JS 3464-3468): slot, piece id, rotation in degrees.

$$[(a, \text{leobeer}, -2),\ (b, \text{bold}, 4),\ (d, \text{weng}, 2),\ (e, \text{mod}, -4)]$$ -/
def deckSlots : List (String × String × Rat) :=
  [("is-a", "leobeer", -2), ("is-b", "bold", 4), ("is-d", "weng", 2), ("is-e", "mod", -4)]

/-! ## Position on the ring (Float; golden vectors only) -/

/-- A rational as a `Float`. $$q \mapsto \mathrm{num}/\mathrm{den}$$ -/
def toF (q : Rat) : Float := Float.ofInt q.num / Float.ofNat q.den

/-- JS `Math.round` for a `Float`: half rounds up. $$\operatorname{round}(x) = \lfloor x + \tfrac12 \rfloor$$ -/
def jsRound (x : Float) : Int := (Float.floor (x + 0.5)).toInt64.toInt

/-- The pi constant used for degrees and radians. $$\pi$$ -/
def piF : Float := 3.141592653589793

/-- The place of a card on the ring (JS 4076-4091, `F`): the offset $(x, y)$ in px from its resting box to its slot
on the ring, and the start rotation in tenths of a degree.

$$\begin{aligned}
s &= -\tfrac{\pi}{2} + \tfrac{\mathrm{idx}}{10}\,2\pi + r, & c &= \tfrac n2 + \rho\cos s,\quad l = \tfrac{779}{2} + \rho\sin s,\\
f &= \ell,\quad m = [a \wedge n < 1280]\max(0, 0.35\,(1280 - n)), & h_x &= \begin{cases} f - m + w/2 & a,\ \ell < 756 \\ n - (1512 - f - w - m) - w/2 & a,\ \ell \ge 756 \\ f + w/2 & \lnot a \end{cases},\\
g &= \tau + h/2, & \vartheta &= \operatorname{atan2}(\tfrac{779}{2} - l,\ \tfrac n2 - c)\tfrac{180}{\pi}
\end{aligned}$$

and the result is $(\operatorname{round}(c - h_x),\ \operatorname{round}(l - g),\ \operatorname{round}(10(\vartheta - 90)))$. The inputs are the piece (left, top,
width, height in px), the ring index, the stage width $n$, the ring angle $r$ in radians, the radius $\rho$ and the
expanded flag $a$. Where each card starts on the ring. -/
def place (left top width height : Rat) (idx : Nat) (n r rho : Float) (a : Bool) : Int × Int × Int :=
  let u := 1512.0
  let d := 779.0 / 2.0
  let lp := toF left / u * 100.0
  let tp := toF top / 779.0 * 100.0
  let o := n / 2.0
  let s := -piF / 2.0 + (Float.ofNat idx / 10.0) * piF * 2.0 + r
  let c := o + rho * Float.cos s
  let l := d + rho * Float.sin s
  let f := (lp / 100.0) * u
  let p := u - f - toF width
  let m := if a && n < 1280.0 then (let v := (1280.0 - n) * 0.35; if v > 0.0 then v else 0.0) else 0.0
  let hx := if a then (if lp < 50.0 then f - m + toF width / 2.0 else n - (p - m) - toF width / 2.0) else f + toF width / 2.0
  let g := (tp / 100.0) * 779.0 + toF height / 2.0
  let th := Float.atan2 (d - l) (o - c) * 180.0 / piF
  (jsRound (c - hx), jsRound (l - g), jsRound ((th - 90.0) * 10.0))

/-- The rank of each piece on the ring (JS 4097-4099): sorted by the angle of the piece centre about the canvas
centre, ascending.

$$T(i) = \bigl|\{\,j : \operatorname{atan2}(y_j - \tfrac{779}{2},\ x_j - \tfrac{1512}{2}) < \operatorname{atan2}(y_i - \tfrac{779}{2},\ x_i - \tfrac{1512}{2})\,\}\bigr|,\quad (x_i, y_i) = (\ell_i + \tfrac{w_i}{2},\ \tau_i + \tfrac{h_i}{2})$$

(Ties do not occur in the data.) Each card's slot number. -/
def ringIndex : List Nat :=
  let ang : Piece → Float := fun p =>
    Float.atan2 ((toF p.top / 779.0 * 100.0 / 100.0) * 779.0 + toF p.height / 2.0 - 779.0 / 2.0)
      ((toF p.left / 1512.0 * 100.0 / 100.0) * 1512.0 + toF p.width / 2.0 - 1512.0 / 2.0)
  pieces.map fun p => (pieces.filter fun q => ang q < ang p).length

end Fw.Parts.HeroOrbit

/-!
# platform.sweep: the 4 s gradient sweep over the four row-title words (P5 port, `faithful`)

Restated (not copied) from the original snapshot, read independently of the TS part:

* `snapshot/site-pretty/_app/immutable/assets/2.gBuqKVzi.css`
  * 5802-5805: `@keyframes` from `background-position: 100%` to `0%`;
  * 11081-11103 (`@media (prefers-reduced-motion: no-preference)`, the last word on the four titles): `background-image:
    linear-gradient(90deg, #fff 0 33.33%, #82bcff 40%, #2483ff 45%, #ff66f4 50%, #ff3029 55%, #fe7b02 60%, #fff 66.67% 100%)`,
    `background-size: 300% 100%`, `background-clip: text`, `animation: 4s linear infinite`.
    Under reduced motion the words are plain white.

All values `Rat`. No `Float`. This is the exact "original" that an optimized sweep is compared against.
-/
namespace Fw.Parts.PlatformSweep

/-! ## The clock -/

/-- Period of the sweep in ms (CSS `4s linear infinite`). $$T = 4000$$ How long one pass takes. -/
def period : Rat := 4000

/-- Fractional part. $$\operatorname{frac}(x) = x - \lfloor x \rfloor$$ The position inside a cycle. -/
def frac (x : Rat) : Rat := x - (x.floor : Rat)

/-- The fractional part lies in $[0, 1)$. $$\forall x:\ 0 \le \operatorname{frac}(x) < 1$$ Whatever the input. -/
theorem frac_mem (x : Rat) : 0 ≤ frac x ∧ frac x < 1 := by
  have h1 := Rat.floor_le x
  have h2 := Rat.lt_floor_add_one x
  unfold frac
  push_cast at h2
  grind

/-- One more whole cycle changes nothing. $$\forall x:\ \operatorname{frac}(x + 1) = \operatorname{frac}(x)$$ The cycle repeats. -/
theorem frac_add_one (x : Rat) : frac (x + 1) = frac x := by
  unfold frac
  rw [Rat.floor_add_one]
  push_cast
  grind

/-- Position in the cycle of a CSS animation. $$\varphi(t) = \operatorname{frac}(t / T)$$ The cycle fraction at time $t$ ms. -/
def phase (t : Rat) : Rat := frac (t / period)

/-- Moving by one period leaves the phase alone. $$\varphi(t + 4000) = \varphi(t)$$ The sweep is 4 s periodic. -/
theorem phase_periodic (t : Rat) : phase (t + period) = phase t := by
  unfold phase
  have : (t + period) / period = t / period + 1 := by unfold period; grind
  rw [this, frac_add_one]

/-- `background-position` as a fraction ($1 = 100\%$) at time $t$.

$$p(t) = 1 - \varphi(t),\qquad p(t) \in (0, 1]$$

Starts at 100 % and falls linearly to 0 % over 4 s, then jumps back. -/
def pos (t : Rat) : Rat := 1 - phase t

/-- The position stays in $(0, 1]$. $$\forall t:\ 0 < p(t) \le 1$$ It never leaves the keyframe range. -/
theorem pos_mem (t : Rat) : 0 < pos t ∧ pos t ≤ 1 := by
  have := frac_mem (t / period)
  unfold pos phase
  grind

/-- The sweep starts at 100 %. $$p(0) = 1$$ -/
theorem pos_zero : pos 0 = 1 := by decide +kernel

/-- Halfway through a pass the position is 50 %. $$p(2000) = \tfrac12$$ -/
theorem pos_half : pos 2000 = 1 / 2 := by decide +kernel

/-- The sweep is 4 s periodic. $$p(t + 4000) = p(t)$$ -/
theorem pos_periodic (t : Rat) : pos (t + period) = pos t := by
  unfold pos; rw [phase_periodic]

/-! ## The gradient -/

/-- Colour as three channel levels. $$c = (r, g, b) \in \mathbb{Q}^3$$ 0..255 each. -/
abbrev Rgb := Rat × Rat × Rat

/-- White. $$w = (255, 255, 255)$$ -/
def white : Rgb := (255, 255, 255)

/-- The six coloured stops, in order (the words' colours). $$c_1 = \#82bcff,\ c_2 = \#2483ff,\ c_3 = \#ff66f4,\ c_4 = \#ff3029,\ c_5 = \#fe7b02$$ -/
def c1 : Rgb := (130, 188, 255)
/-- $\#2483ff$. $$c_2 = (36, 131, 255)$$ -/
def c2 : Rgb := (36, 131, 255)
/-- $\#ff66f4$. $$c_3 = (255, 102, 244)$$ -/
def c3 : Rgb := (255, 102, 244)
/-- $\#ff3029$. $$c_4 = (255, 48, 41)$$ -/
def c4 : Rgb := (255, 48, 41)
/-- $\#fe7b02$. $$c_5 = (254, 123, 2)$$ -/
def c5 : Rgb := (254, 123, 2)

/-- Stop positions of the gradient as fractions of the 300 % image. $$s = (0,\ 0.3333,\ 0.40,\ 0.45,\ 0.50,\ 0.55,\ 0.60,\ 0.6667,\ 1)$$ The percentages of the CSS. -/
def stops : List Rat := [0, 3333 / 10000, 2 / 5, 9 / 20, 1 / 2, 11 / 20, 3 / 5, 6667 / 10000, 1]

/-- Linear mix of two colours. $$\operatorname{mix}(a, b, w) = a + (b - a)\,w$$ Per channel. -/
def mix (a b : Rgb) (w : Rat) : Rgb :=
  (a.1 + (b.1 - a.1) * w, a.2.1 + (b.2.1 - a.2.1) * w, a.2.2 + (b.2.2 - a.2.2) * w)

/-- One segment of the gradient between stops $u_0 < u_1$. $$\operatorname{seg}(u; u_0, u_1, a, b) = \operatorname{mix}\big(a, b, \tfrac{u - u_0}{u_1 - u_0}\big)$$ -/
def seg (u u0 u1 : Rat) (a b : Rgb) : Rgb := mix a b ((u - u0) / (u1 - u0))

/-- The gradient colour at image coordinate $u \in [0, 1]$ (hard white up to $33.33\%$, the colour run, then white again).

$$\operatorname{color}(u) = \begin{cases} w & u \le 0.3333 \\ \operatorname{seg}(w, c_1) & u \le 0.40 \\ \operatorname{seg}(c_1, c_2) & u \le 0.45 \\ \operatorname{seg}(c_2, c_3) & u \le 0.50 \\ \operatorname{seg}(c_3, c_4) & u \le 0.55 \\ \operatorname{seg}(c_4, c_5) & u \le 0.60 \\ \operatorname{seg}(c_5, w) & u \le 0.6667 \\ w & \text{otherwise} \end{cases}$$ -/
def color (u : Rat) : Rgb :=
  if u ≤ 3333 / 10000 then white
  else if u ≤ 2 / 5 then seg u (3333 / 10000) (2 / 5) white c1
  else if u ≤ 9 / 20 then seg u (2 / 5) (9 / 20) c1 c2
  else if u ≤ 1 / 2 then seg u (9 / 20) (1 / 2) c2 c3
  else if u ≤ 11 / 20 then seg u (1 / 2) (11 / 20) c3 c4
  else if u ≤ 3 / 5 then seg u (11 / 20) (3 / 5) c4 c5
  else if u ≤ 6667 / 10000 then seg u (3 / 5) (6667 / 10000) c5 white
  else white

/-- Image coordinate seen at element coordinate $v \in [0,1]$ when the position fraction is $p$ and the image is 300 % wide.

$$u(v, p) = \frac{v + 2p}{3}$$

The offset is $(W - 3W)\,p = -2Wp$, so a point $vW$ of the element shows image pixel $vW + 2Wp$ of $3W$. -/
def imageU (v p : Rat) : Rat := (v + 2 * p) / 3

/-- The colour a word shows at element fraction $v$ at time $t$. $$\operatorname{shown}(v, t) = \operatorname{color}(u(v, p(t)))$$ -/
def shown (v t : Rat) : Rgb := color (imageU v (pos t))

/-- The window at position 0 shows only the first third of the image: every channel is within 1 level of white.

$$\forall v \in [0,1],\ \text{channel } k:\quad \operatorname{color}(u(v, 0))_k \ge 254$$

The $0.3333$ stop sits $3.3 \cdot 10^{-5}$ short of $1/3$, so the right edge is not exactly white but is invisible; the pass ends white. -/
theorem end_nearly_white (v : Rat) (h0 : 0 ≤ v) (h1 : v ≤ 1) :
    254 ≤ (color (imageU v 0)).1 ∧ 254 ≤ (color (imageU v 0)).2.1 ∧ 254 ≤ (color (imageU v 0)).2.2 := by
  have hu : imageU v 0 ≤ 1 / 3 := by unfold imageU; grind
  have hu0 : 0 ≤ imageU v 0 := by unfold imageU; grind
  unfold color
  by_cases h : imageU v 0 ≤ 3333 / 10000
  · simp only [h, ite_true]; unfold white; refine ⟨?_, ?_, ?_⟩ <;> grind
  · have n2 : imageU v 0 ≤ 2 / 5 := by grind
    simp only [h, n2, ite_true, ite_false]
    unfold seg mix c1 white
    generalize imageU v 0 = u at *
    refine ⟨?_, ?_, ?_⟩ <;> grind

/-- At the start (position 100 %) the window is the last third of the image: every channel is within 1 level of white.

$$\forall v \in [0,1],\ \text{channel } k:\quad \operatorname{color}(u(v, 1))_k \ge 254$$

The $0.6667$ stop sits $3.3 \cdot 10^{-5}$ past $2/3$, so the left edge is not exactly white but is invisible; the pass starts white. -/
theorem start_nearly_white (v : Rat) (h0 : 0 ≤ v) (h1 : v ≤ 1) :
    254 ≤ (color (imageU v 1)).1 ∧ 254 ≤ (color (imageU v 1)).2.1 ∧ 254 ≤ (color (imageU v 1)).2.2 := by
  have hu : 2 / 3 ≤ imageU v 1 := by unfold imageU; grind
  have hu1 : imageU v 1 ≤ 1 := by unfold imageU; grind
  unfold color
  have n1 : ¬ imageU v 1 ≤ 3333 / 10000 := by grind
  have n2 : ¬ imageU v 1 ≤ 2 / 5 := by grind
  have n3 : ¬ imageU v 1 ≤ 9 / 20 := by grind
  have n4 : ¬ imageU v 1 ≤ 1 / 2 := by grind
  have n5 : ¬ imageU v 1 ≤ 11 / 20 := by grind
  have n6 : ¬ imageU v 1 ≤ 3 / 5 := by grind
  simp only [n1, n2, n3, n4, n5, n6, ite_false]
  by_cases h : imageU v 1 ≤ 6667 / 10000
  · simp only [h, ite_true]
    unfold seg mix c5 white
    generalize imageU v 1 = u at *
    refine ⟨?_, ?_, ?_⟩ <;> grind
  · simp only [h, ite_false]
    unfold white
    grind

/-- The effect applies only when the visitor has not asked for reduced motion. $$\operatorname{active}(\mathit{reduce}) = \lnot\,\mathit{reduce}$$ -/
def active (reduce : Bool) : Bool := !reduce

end Fw.Parts.PlatformSweep

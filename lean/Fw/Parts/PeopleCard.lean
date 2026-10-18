/-!
# people.card: the white People card's reveal and shrink (`faithful`)

Restated (not copied) from `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`, read independently of the TS part:

* 11275-11284 (`C`, `w`, `T`): the clamp $\mathrm{clamp}(x) = \min(1, \max(0, x))$, the smoothstep
  $w(x) = c^2 (3 - 2c)$ with $c = \mathrm{clamp}(x)$, and the *coverage* of the card by the viewport: with the card's
  bottom edge $z$ and the viewport height $h$, $T = 0$ if $h \le 0$ or $z \ge 0.85\,h$, $T = 1$ if $z \le 0.35\,h$, else
  $T = (0.85\,h - z) / (0.5\,h)$;
* 11300-11324 (`l`): per frame, the *reveal* `is-visible` is `reduced ∨ p ≥ 0.72` with
  $p = \min(r, \max(0, -\mathit{top})) / r$ and $r = \max(1, \mathit{height} - h)$ of the hero track (true when there is
  no hero track); the target shrink is $\mathrm{smooth}(T)$ (reduced motion: $[T \ge 0.5]$); the value moves
  $o \leftarrow o + (\mathit{target} - o)\,k$ with $k = 0.22$ ($k = 1$ under reduced motion) and snaps to the target
  within $0.0008$; the class `is-future-shrinking` is $T > 0.04$; another frame is requested while the value has not
  reached the target. The value is written as `--future-shrink` on the section;
* 11325-11330: the Pain section is dark iff the viewport is wider than 860 px or the heading block's top is at or above
  $0.5$ px (it is dark at once on wide viewports);
* CSS `assets/2.gBuqKVzi.css` 2358-2418, 3384-3387, 3586-3591: scale $1 - 0.083333\,s$, radius $32\,s$ px
  (24 px at width at most 640 px), both reset to scale 1 and radius 0 at the 860 combo; reveal transitions 0.7 s
  (opacity), 1.6 s (blur), 0.9 s (lift).

All values `Rat` (rects are fractional). No `Float`.
-/
namespace Fw.Parts.PeopleCard

/-! ## Constants -/

/-- Lerp rate per frame (JS 11313). $$k = 0.22 = \tfrac{11}{50}$$ -/
def rate : Rat := 11 / 50

/-- Snap distance (JS 11314). $$\varepsilon = 0.0008 = \tfrac{1}{1250}$$ -/
def snap : Rat := 1 / 1250

/-- Reveal threshold on the hero track progress (JS 11305). $$\rho = 0.72 = \tfrac{18}{25}$$ -/
def revealAt : Rat := 18 / 25

/-- The card counts as shrinking above this coverage (JS 11317). $$\sigma = 0.04 = \tfrac{1}{25}$$ -/
def shrinkingAbove : Rat := 1 / 25

/-- Coverage is 0 when the bottom is at or below this fraction of the viewport (JS 11282). $$\beta = 0.85 = \tfrac{17}{20}$$ -/
def coverTop : Rat := 17 / 20

/-- Coverage is 1 when the bottom is at or above this fraction (JS 11283). $$\alpha = 0.35 = \tfrac{7}{20}$$ -/
def coverFull : Rat := 7 / 20

/-- Scale loss at full shrink (CSS 2361). $$\lambda = 0.083333 = \tfrac{83333}{1000000}$$ -/
def scaleLoss : Rat := 83333 / 1000000

/-- Radius at full shrink in px (CSS 2362); 24 at width at most 640 px (CSS 3588). $$R = 32$$ -/
def radiusPx : Rat := 32

/-- The Pain section turns dark at this heading top (px) on narrow viewports (JS 11327). $$0.5$$ -/
def darkTop : Rat := 1 / 2

/-! ## Curves -/

/-- Clamp to the unit interval (JS 11275). $$\operatorname{clamp}(x) = \min(1, \max(0, x))$$ -/
def clamp01 (x : Rat) : Rat := min 1 (max 0 x)

/-- The clamp lies in $[0,1]$. $$\forall x:\ 0 \le \operatorname{clamp}(x) \le 1$$ -/
theorem clamp01_mem (x : Rat) : 0 ≤ clamp01 x ∧ clamp01 x ≤ 1 := by unfold clamp01; grind

/-- Smoothstep of the clamped input (JS 11278).

$$w(x) = c^2 (3 - 2c),\quad c = \operatorname{clamp}(x)$$ -/
def smooth (x : Rat) : Rat := clamp01 x * clamp01 x * (3 - 2 * clamp01 x)

#guard smooth 0 == 0
#guard smooth 1 == 1
#guard smooth (1/2) == 1/2
#guard smooth 2 == 1
#guard smooth (-3) == 0

/-- **Smoothstep stays in $[0,1]$.** $$\forall x:\ 0 \le w(x) \le 1$$ The shrink never overshoots. -/
theorem smooth_mem (x : Rat) : 0 ≤ smooth x ∧ smooth x ≤ 1 := by
  have h := clamp01_mem x
  unfold smooth
  generalize clamp01 x = c at *
  obtain ⟨h0, h1⟩ := h
  have hc : 0 ≤ c * c := Rat.mul_nonneg h0 h0
  have hd : 0 ≤ 3 - 2 * c := by grind
  constructor
  · exact Rat.mul_nonneg hc hd
  · have h2 : c * c ≤ c := by
      have := Rat.mul_le_mul_of_nonneg_left h1 h0
      grind
    have h3 : c * c * (3 - 2 * c) ≤ 1 := by
      have e : 1 - c * c * (3 - 2 * c) = (1 - c) * (1 - c) * (1 + 2 * c) := by grind
      have : 0 ≤ (1 - c) * (1 - c) * (1 + 2 * c) :=
        Rat.mul_nonneg (Rat.mul_nonneg (by grind) (by grind)) (by grind)
      grind
    exact h3

/-- **Smoothstep is monotone.** $$x \le y \Rightarrow w(x) \le w(y)$$ A card further up never shrinks less. -/
theorem smooth_mono (x y : Rat) (h : x ≤ y) : smooth x ≤ smooth y := by
  have hc : clamp01 x ≤ clamp01 y := by unfold clamp01; grind
  have hx := clamp01_mem x
  have hy := clamp01_mem y
  unfold smooth
  generalize clamp01 x = a at *
  generalize clamp01 y = b at *
  have e : b * b * (3 - 2 * b) - a * a * (3 - 2 * a) = (b - a) * (3 * (b + a) - 2 * (b * b + a * b + a * a)) := by grind
  have h1 : 0 ≤ 3 * (b + a) - 2 * (b * b + a * b + a * a) := by
    have p1 : b * b ≤ b := by have := Rat.mul_le_mul_of_nonneg_left hy.2 hy.1; grind
    have p2 : a * b ≤ a := by have := Rat.mul_le_mul_of_nonneg_left hy.2 hx.1; grind
    have p3 : a * a ≤ a := by have := Rat.mul_le_mul_of_nonneg_left hx.2 hx.1; grind
    grind
  have h2 : 0 ≤ (b - a) * (3 * (b + a) - 2 * (b * b + a * b + a * a)) := Rat.mul_nonneg (by grind) h1
  grind

/-- Coverage of the card by the viewport (JS 11279-11284).

$$T(z, h) = \begin{cases} 0 & h \le 0 \lor z \ge 0.85\,h \\ 1 & z \le 0.35\,h \\ \dfrac{0.85\,h - z}{0.5\,h} & \text{otherwise} \end{cases}$$ -/
def coverage (bottom vh : Rat) : Rat :=
  if vh ≤ 0 then 0
  else if coverTop * vh ≤ bottom then 0
  else if bottom ≤ coverFull * vh then 1
  else clamp01 ((coverTop * vh - bottom) / (coverTop * vh - coverFull * vh))

#guard coverage 900 900 == 0
#guard coverage 765 900 == 0
#guard coverage 315 900 == 1
#guard coverage 540 900 == 1/2
#guard coverage 100 0 == 0

/-- **Coverage lies in $[0,1]$.** $$\forall z, h:\ 0 \le T(z,h) \le 1$$ -/
theorem coverage_mem (z h : Rat) : 0 ≤ coverage z h ∧ coverage z h ≤ 1 := by
  unfold coverage
  split
  · grind
  · split
    · grind
    · split
      · grind
      · exact clamp01_mem _

/-- **No coverage below the fold.** $$h > 0 \land z \ge 0.85\,h \Rightarrow T(z, h) = 0$$ A card whose bottom is in the
lowest 15 % of the viewport (or below it) is not shrunk. -/
theorem coverage_zero (z h : Rat) (hh : 0 < h) (hz : 17 / 20 * h ≤ z) : coverage z h = 0 := by
  unfold coverage coverTop
  have : ¬ h ≤ 0 := by grind
  simp only [this, ite_false, hz, ite_true]

/-- **Full coverage near the top.** $$h > 0 \land z \le 0.35\,h \Rightarrow T(z, h) = 1$$ -/
theorem coverage_one (z h : Rat) (hh : 0 < h) (hz : z ≤ 7 / 20 * h) : coverage z h = 1 := by
  unfold coverage coverTop coverFull
  have h1 : ¬ h ≤ 0 := by grind
  have h2 : ¬ 17 / 20 * h ≤ z := by grind
  simp only [h1, h2, ite_false, hz, ite_true]


/-! ## The frame -/

/-- Target shrink for a coverage $t$ (JS 11308).

$$\mathrm{target}(t) = \begin{cases} [t \ge 0.5] & \mathit{rm} \\ w(t) & \text{otherwise} \end{cases}$$ -/
def target (reduced : Bool) (t : Rat) : Rat := if reduced then (if 1 / 2 ≤ t then 1 else 0) else smooth t

/-- One lerp step (JS 11309-11310).

$$o' = \begin{cases} n & |n - (o + (n - o)k)| < \varepsilon \\ o + (n - o)\,k & \text{otherwise}\end{cases},\quad k = \begin{cases}1 & \mathit{rm}\\ 0.22 & \text{otherwise}\end{cases}$$ -/
def lerpK (k o n : Rat) : Rat :=
  if max (n - (o + (n - o) * k)) ((o + (n - o) * k) - n) < snap then n else o + (n - o) * k

/-- The step with the frame's rate: $1$ under reduced motion, $0.22$ otherwise. $$\mathrm{lerp}(\mathit{rm}, o, n) = \mathrm{lerp}_{k}(o, n)$$ -/
def lerp (reduced : Bool) (o n : Rat) : Rat := lerpK (if reduced then 1 else rate) o n

/-- Another frame is requested iff the value is still off the target by the snap distance (JS 11312).

$$\mathrm{pending}(n, o) = [\,|n - o| \ge 0.0008\,]$$ -/
def pending (n o : Rat) : Bool := decide (snap ≤ max (n - o) (o - n))

#guard lerp false 0 1 == 11/50
#guard lerp true 0 1 == 1
#guard lerp false 1 1 == 1
#guard lerp false (1249/1250) 1 == 1
#guard pending 1 (11/50) == true
#guard pending 1 1 == false

/-- **The step moves toward the target without crossing it.**

$$\min(o, n) \le o' \le \max(o, n)$$

The shrink never overshoots (any rate in $[0,1]$). -/
theorem lerp_between (reduced : Bool) (o n : Rat) : min o n ≤ lerp reduced o n ∧ lerp reduced o n ≤ max o n := by
  have key : ∀ k : Rat, 0 ≤ k → k ≤ 1 → min o n ≤ lerpK k o n ∧ lerpK k o n ≤ max o n := by
    intro k hk0 hk1
    unfold lerpK
    have h1 : 0 ≤ (n - o) * k ∨ (n - o) * k ≤ 0 := by grind
    have e1 : (o ≤ n → o ≤ o + (n - o) * k ∧ o + (n - o) * k ≤ n) := by
      intro h
      have a := Rat.mul_le_mul_of_nonneg_left hk0 (show 0 ≤ n - o by grind)
      have b := Rat.mul_le_mul_of_nonneg_left hk1 (show 0 ≤ n - o by grind)
      grind
    have e2 : (n ≤ o → n ≤ o + (n - o) * k ∧ o + (n - o) * k ≤ o) := by
      intro h
      have a := Rat.mul_le_mul_of_nonneg_left hk0 (show 0 ≤ o - n by grind)
      have b := Rat.mul_le_mul_of_nonneg_left hk1 (show 0 ≤ o - n by grind)
      grind
    split <;> grind
  unfold lerp rate
  split
  · exact key 1 (by grind) (by grind)
  · exact key (11 / 50) (by grind) (by grind)

/-- **Reduced motion jumps.** $$\mathrm{lerp}(\top, o, n) = n$$ -/
theorem lerp_reduced (o n : Rat) : lerp true o n = n := by
  unfold lerp lerpK
  have : o + (n - o) * 1 = n := by grind
  simp only [ite_true, this]
  split <;> rfl

/-- **Contraction.** Away from the snap, one step keeps $78\,\%$ of the distance.

$$\forall o, n \in \mathbb{Q}:\ \lnot\bigl(|n - (o + 0.22\,(n - o))| < \varepsilon\bigr) \Rightarrow n - \mathrm{lerp}(\bot, o, n) = 0.78\,(n - o)$$ -/
theorem lerp_contracts (o n : Rat) (h : ¬ (max (n - (o + (n - o) * rate)) ((o + (n - o) * rate) - n) < snap)) :
    n - lerp false o n = (39 / 50) * (n - o) := by
  unfold lerp lerpK
  simp only [Bool.false_eq_true, ite_false]
  simp only [h, ite_false]
  unfold rate
  grind

/-- A fixed point: at the target the value stays and no frame is pending.
$$\mathrm{lerp}(\bot, n, n) = n,\quad \lnot\mathrm{pending}(n, n)$$ -/
theorem lerp_fixed (n : Rat) : lerp false n n = n ∧ pending n n = false := by
  unfold lerp lerpK pending snap
  simp only [Bool.false_eq_true, ite_false]
  constructor
  · have : n + (n - n) * rate = n := by grind
    simp only [this]
    split <;> rfl
  · simp only [decide_eq_false_iff_not]
    grind

/-- Class `is-future-shrinking` (JS 11317). $$t > 0.04$$ -/
def shrinking (t : Rat) : Bool := decide (shrinkingAbove < t)

/-- The reveal flag from the hero track rect (JS 11300-11306).

$$p = \frac{\min(r, \max(0, -\mathit{top}))}{r},\ r = \max(1, H - h);\quad \mathrm{reveal} = \mathit{rm} \lor p \ge 0.72$$ -/
def revealed (reduced : Bool) (top height vh : Rat) : Bool :=
  let r := max 1 (height - vh)
  reduced || decide (revealAt ≤ min r (max 0 (-top)) / r)

#guard revealed false 0 1800 900 == false
#guard revealed false (-648) 1800 900 == true
#guard revealed false (-647) 1800 900 == false
#guard revealed true 0 1800 900 == true

/-- **Reveal is monotone while scrolling down.** If the track is revealed at `top`, it stays revealed at any `top'` above it.

$$\mathit{top}' \le \mathit{top} \Rightarrow \mathrm{revealed}(\mathit{top}) \Rightarrow \mathrm{revealed}(\mathit{top}')$$ -/
theorem revealed_mono (rm : Bool) (top top' height vh : Rat) (h : top' ≤ top) :
    revealed rm top height vh = true → revealed rm top' height vh = true := by
  unfold revealed revealAt
  simp only [Bool.or_eq_true, decide_eq_true_eq]
  intro hh
  rcases hh with hh | hh
  · exact Or.inl hh
  · right
    have hr : 0 < max 1 (height - vh) := by grind
    generalize max 1 (height - vh) = r at *
    have hi : 0 ≤ r⁻¹ := Std.le_of_lt (Rat.inv_pos.2 hr)
    have hm : min r (max 0 (-top)) ≤ min r (max 0 (-top')) := by grind
    rw [Rat.div_def] at hh ⊢
    have := Rat.mul_le_mul_of_nonneg_right hm hi
    grind

/-- Scale of the card at shrink $s$ (CSS 2361). $$\mathrm{scale}(s) = 1 - \lambda s$$ -/
def scale (s : Rat) : Rat := 1 - scaleLoss * s

/-- **Scale is between $1 - \lambda$ and $1$.** $$0 \le s \le 1 \Rightarrow 0.916667 \le \mathrm{scale}(s) \le 1$$ -/
theorem scale_range (s : Rat) (h0 : 0 ≤ s) (h1 : s ≤ 1) : 916667 / 1000000 ≤ scale s ∧ scale s ≤ 1 := by
  unfold scale scaleLoss
  grind

/-- Radius of the card in px at shrink $s$ and width-dependent maximum $R$ (CSS 2362). $$\rho(s) = R\,s$$ -/
def radius (maxPx s : Rat) : Rat := maxPx * s

/-- The Pain section is dark (JS 11325-11330).

$$\mathrm{dark} = \lnot\mathit{narrow} \lor \mathit{top} \le 0.5$$ -/
def painDark (narrow : Bool) (headerTop : Rat) : Bool := !narrow || decide (headerTop ≤ darkTop)

#guard painDark false 900 == true
#guard painDark true 900 == false
#guard painDark true 0.5 == true
#guard painDark true 0.51 == false

end Fw.Parts.PeopleCard

/-!
# people.deck: the profile showcase's scroll-driven deck (`faithful`)

Restated (not copied) from `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`, read independently of the TS part
(the profile widgets inside a panel are content, not motion, and are not modelled here):

* 10753-10762 (`ie`, `ae`): the clamp and the ease-in-out cubic
  $\mathrm{ae}(x) = 4c^3$ for $c < \tfrac12$, $1 - (2 - 2c)^3/2$ otherwise, with $c = \mathrm{clamp}(x)$;
* 10767-10770 (`le`): the scroll ranges for $n$ professions and viewport height $h$: the *shrink range*
  $1.45\,h$, the *profession range* $(n-1) \cdot 0.34\,h$ and their sum;
* 10771-10784 (`W`): on the scroll-driven path (not reduced motion, not the 860 combo, width at least 861 px) the
  showcase section is as tall as its sticky child plus the total range;
* 10786-10796 (`ue`, `de`, `fe`): the fit scale $\min(1.22,\ \max(1, w_v - 112) / w)$ and the horizontal offset
  that centres the shell on the deck at scale $s$ with transform origin $o\,\%$;
* 10797-10809 (`pe`): the profession shown for a progress $k \in [0,1]$ with hysteresis;
* 10810-10835 (`ge`): clicking a tab scrolls to
  $\lceil y_s - 48 + \mathit{shrink} + \tfrac{i}{n-1}\,\mathit{prof} \rceil$ with $y_s$ the showcase top in page coordinates;
* 10896-10966 (`f`): the frame: progress $y = \min(\mathit{total},\ \max(0,\ 48 - \mathit{top}))$; while
  $y < \mathit{shrink}$ the targets are scale $b + (1-b)\,e$, offset $\Delta\,(1-e)$, origin $50 + 50\,e$ with
  $e = \mathrm{ae}(y/\mathit{shrink})$ and the rail is out; afterwards scale 1, offset 0, origin 100, the rail in and
  $k = \mathrm{clamp}((y - \mathit{shrink})/\mathit{prof})$; each value moves $v \leftarrow v + (t - v)\,0.2$ and snaps to
  its target within $0.0008$ (scale), $0.4$ (offset), $0.15$ (origin); another frame is requested until all three snapped;
* 10921-10948 (`be`): on the touch layout the active profession is the shell whose centre is nearest to the deck's
  scroll centre.

All values `Rat`. No `Float`. JS `Math.round(x)` is $\lfloor x + \tfrac12 \rfloor$.
-/
namespace Fw.Parts.PeopleDeck

/-! ## Constants -/

/-- Fit scale cap (JS 10749). $$a = 1.22 = \tfrac{61}{50}$$ -/
def maxFit : Rat := 61 / 50

/-- Lerp rate per frame (JS 10750). $$k = 0.2 = \tfrac15$$ -/
def rate : Rat := 1 / 5

/-- Snap distance of the scale (JS 10751). $$\varepsilon_s = 0.0008 = \tfrac{1}{1250}$$ -/
def snapScale : Rat := 1 / 1250

/-- Snap distance of the offset in px (JS 10752). $$\varepsilon_x = 0.4 = \tfrac25$$ -/
def snapOffset : Rat := 2 / 5

/-- Snap distance of the origin in percent (JS 10961). $$\varepsilon_o = 0.15 = \tfrac{3}{20}$$ -/
def snapOrigin : Rat := 3 / 20

/-- Sticky top in px (JS 10815, 10905; CSS 3253). $$48$$ -/
def stickyTop : Rat := 48

/-- Shrink range in viewport heights (JS 10768). $$1.45 = \tfrac{29}{20}$$ -/
def shrinkVh : Rat := 29 / 20

/-- Scroll per profession step in viewport heights (JS 10769). $$0.34 = \tfrac{17}{50}$$ -/
def stepVh : Rat := 17 / 50

/-- Hysteresis bias of the profession pick (JS 10799). $$0.35 = \tfrac{7}{20}$$ -/
def bias : Rat := 7 / 20

/-- Width taken by the tab rail plus gap, in px (JS 10924, CSS 3010, 2996). $$264 - 16 = 248$$ -/
def railPx : Rat := 248

/-- Side margin used by the fit scale in px (JS 10787). $$112$$ -/
def sidePx : Rat := 112

/-! ## Curves -/

/-- Clamp to the unit interval (JS 10753). $$\operatorname{clamp}(x) = \min(1, \max(0, x))$$ -/
def clamp01 (x : Rat) : Rat := min 1 (max 0 x)

/-- Ease-in-out cubic (JS 10756).

$$\operatorname{ae}(x) = \begin{cases} 4c^3 & c < \tfrac12 \\ 1 - \dfrac{(2 - 2c)^3}{2} & \text{otherwise}\end{cases},\quad c = \operatorname{clamp}(x)$$ -/
def aeC (c : Rat) : Rat :=
  if c < 1 / 2 then 4 * c * c * c else 1 - (2 - 2 * c) * (2 - 2 * c) * (2 - 2 * c) / 2

/-- The ease of the clamped input. $$\operatorname{ae}(x) = \operatorname{ae}_c(\operatorname{clamp}(x))$$ -/
def ae (x : Rat) : Rat := aeC (clamp01 x)

#guard ae 0 == 0
#guard ae 1 == 1
#guard ae (1/2) == 1/2
#guard ae (1/4) == 1/16
#guard ae (3/4) == 15/16
#guard ae 5 == 1
#guard ae (-5) == 0

/-- Cubes are monotone on the non-negatives. $$0 \le a \le b \Rightarrow a^3 \le b^3$$ -/
theorem cube_mono (a b : Rat) (h0 : 0 ≤ a) (h : a ≤ b) : a * a * a ≤ b * b * b := by
  have h1 : a * a ≤ b * b := by
    have := Rat.mul_le_mul_of_nonneg_left h h0
    have := Rat.mul_le_mul_of_nonneg_right h (show 0 ≤ b by grind)
    grind
  have h2 : 0 ≤ a * a := Rat.mul_nonneg h0 h0
  have := Rat.mul_le_mul_of_nonneg_right h1 h0
  have := Rat.mul_le_mul_of_nonneg_left h (show 0 ≤ b * b by exact Rat.mul_nonneg (by grind) (by grind))
  grind

/-- The second branch is $1 - 4(1-c)^3$. $$1 - \tfrac{(2-2c)^3}{2} = 1 - 4(1-c)^3$$ -/
theorem ae_second (c : Rat) : 1 - (2 - 2 * c) * (2 - 2 * c) * (2 - 2 * c) / 2 = 1 - 4 * ((1 - c) * (1 - c) * (1 - c)) := by
  grind

/-- **The ease stays in $[0,1]$.** $$\forall x:\ 0 \le \operatorname{ae}(x) \le 1$$ -/
theorem ae_mem (x : Rat) : 0 ≤ ae x ∧ ae x ≤ 1 := by
  have h : 0 ≤ clamp01 x ∧ clamp01 x ≤ 1 := by unfold clamp01; grind
  unfold ae aeC
  generalize clamp01 x = c at *
  obtain ⟨h0, h1⟩ := h
  rw [ae_second]
  split
  · have c3 := cube_mono c (1 / 2) h0 (by grind)
    have c0 : 0 ≤ c * c * c := Rat.mul_nonneg (Rat.mul_nonneg h0 h0) h0
    grind
  · have c0 : 0 ≤ (1 - c) * (1 - c) * (1 - c) :=
      Rat.mul_nonneg (Rat.mul_nonneg (by grind) (by grind)) (by grind)
    have c3 := cube_mono (1 - c) (1 / 2) (by grind) (by grind)
    grind

/-- **The ease is monotone.** $$x \le y \Rightarrow \operatorname{ae}(x) \le \operatorname{ae}(y)$$ -/
theorem ae_mono (x y : Rat) (h : x ≤ y) : ae x ≤ ae y := by
  have hc : clamp01 x ≤ clamp01 y := by unfold clamp01; grind
  have hx : 0 ≤ clamp01 x ∧ clamp01 x ≤ 1 := by unfold clamp01; grind
  have hy : 0 ≤ clamp01 y ∧ clamp01 y ≤ 1 := by unfold clamp01; grind
  unfold ae aeC
  generalize clamp01 x = a at *
  generalize clamp01 y = b at *
  rw [ae_second, ae_second]
  by_cases ha : a < 1 / 2 <;> by_cases hb : b < 1 / 2
  · simp only [ha, hb, ite_true]
    have := cube_mono a b hx.1 hc
    grind
  · simp only [ha, hb, ite_true, ite_false]
    have h1 := cube_mono a (1 / 2) hx.1 (by grind)
    have h2 := cube_mono (1 - b) (1 / 2) (by grind) (by grind)
    grind
  · grind
  · simp only [ha, hb, ite_false]
    have := cube_mono (1 - b) (1 - a) (by grind) (by grind)
    grind

/-- **Ease endpoints.** $$\operatorname{ae}(0) = 0,\quad \operatorname{ae}(1) = 1$$ -/
theorem ae_ends : ae 0 = 0 ∧ ae 1 = 1 := by
  have e0 : clamp01 0 = 0 := by unfold clamp01; grind
  have e1 : clamp01 1 = 1 := by unfold clamp01; grind
  unfold ae aeC
  rw [e0, e1]
  simp only [show ¬ ((1 : Rat) < 1 / 2) by grind, show (0 : Rat) < 1 / 2 by grind, ite_true, ite_false]
  grind

/-! ## Geometry -/

/-- Scroll ranges (JS 10767-10770) for viewport height $h$ and $n$ professions:
(shrink, profession, total).

$$(1.45\,h,\ (n-1)\,0.34\,h,\ 1.45\,h + (n-1)\,0.34\,h)$$ -/
def ranges (vh : Rat) (n : Nat) : Rat × Rat × Rat :=
  let s := shrinkVh * vh
  let p := ((n - 1 : Nat) : Rat) * stepVh * vh
  (s, p, s + p)

/-- **Six professions scroll $3.15\,h$ in total.**

$$1.45\,h + 5 \cdot 0.34\,h = 3.15\,h = \tfrac{63}{20}\,h$$

This is the extra height the shell fit measured (`3.15svh`) for the showcase on wide viewports. -/
theorem total_six (vh : Rat) : (ranges vh 6).2.2 = 63 / 20 * vh := by
  unfold ranges shrinkVh stepVh
  have h5 : ((6 - 1 : Nat) : Rat) = 5 := by decide
  rw [h5]
  grind

/-- Page-coordinate scroll progress through the ranges (JS 10905). $$y = \min(T,\ \max(0,\ 48 - \mathit{top}))$$ -/
def progress (top total : Rat) : Rat := min total (max 0 (stickyTop - top))

/-- Fit scale of the shell (JS 10786-10789, applied to `max(1, deckWidth - 248)`).

$$b = \min\!\Big(1.22,\ \frac{\max(1,\ w_v - 112)}{w}\Big),\quad w = \max(1,\ w_d - 248)$$ -/
def fit (vw deckW : Rat) : Rat :=
  let w := max 1 (deckW - railPx)
  min maxFit (max 1 (vw - sidePx) / w)

/-- Horizontal position of the shell centre at scale $s$ and origin $o\,\%$ (JS 10791).

$$\mathrm{de}(l, w, s, o) = l + \tfrac{o}{100}\,w\,(1 - s) + \tfrac{w\,s}{2}$$ -/
def de (left width s o : Rat) : Rat := left + (o / 100) * width * (1 - s) + width * s / 2

/-- **At origin 50 % the shell centre does not depend on the scale.** $$\mathrm{de}(l, w, s, 50) = l + \tfrac{w}{2}$$
So the offset that centres the shell is the same for every fit scale. -/
theorem de_half (l w s : Rat) : de l w s 50 = l + w / 2 := by
  unfold de
  grind

/-- At origin 100 % the shell's right edge stays put. $$\mathrm{de}(l, w, s, 100) = l + w - \tfrac{w s}{2}$$ -/
theorem de_full (l w s : Rat) : de l w s 100 = l + w - w * s / 2 := by
  unfold de
  grind

/-- Offset that centres the shell in the deck (JS 10790-10796).

$$\mathrm{fe}(s, o) = \tfrac{W}{2} - \mathrm{de}(l, w, s, o)$$ with $W$ the deck's client width. -/
def fe (deckW left width s o : Rat) : Rat := deckW / 2 - de left width s o

/-! ## Frame -/

/-- The three animated values and the rail flag. $$(s, x, o, \rho)$$ Scale, offset (px), origin (%), rail in. -/
structure Target where
  scale : Rat
  offset : Rat
  origin : Rat
  railIn : Bool
  k : Rat
deriving Repr, BEq, DecidableEq

/-- Targets for the progress $y$ (JS 10896-10918).

$$\mathrm{tgt}(y) = \begin{cases} (b + (1-b)e,\ \Delta(1-e),\ 50 + 50e,\ \bot,\ 0) & y < S,\ e = \operatorname{ae}(y/S) \\ (1,\ 0,\ 100,\ \top,\ \operatorname{clamp}((y-S)/P)) & \text{otherwise (}k = 0\text{ if }P \le 0)\end{cases}$$ -/
def tgt (y shrink prof fitScale delta : Rat) : Target :=
  if y < shrink then
    let e := ae (y / shrink)
    ⟨fitScale + (1 - fitScale) * e, delta * (1 - e), 50 + 50 * e, false, 0⟩
  else ⟨1, 0, 100, true, if prof ≤ 0 then 0 else clamp01 ((y - shrink) / prof)⟩

/-- **The two regimes meet.** At the end of the shrink range the first branch has reached the second one's values.

$$S > 0 \Rightarrow \mathrm{scale},\ \mathrm{offset},\ \mathrm{origin}\text{ of } \mathrm{tgt}\text{ near the end} \to (1, 0, 100)$$

(stated exactly: with $e = 1$ the first branch is $(1, 0, 100)$). -/
theorem shrink_end (fitScale delta : Rat) :
    (fitScale + (1 - fitScale) * ae 1, delta * (1 - ae 1), 50 + 50 * ae 1) = (1, 0, 100) := by
  rw [ae_ends.2]
  grind

/-- At the very start the shell sits at the fit scale, centred, origin 50 %.

$$S > 0 \Rightarrow \mathrm{tgt}(0) = (b, \Delta, 50, \bot, 0)$$ -/
theorem tgt_start (shrink prof fitScale delta : Rat) (h : 0 < shrink) :
    tgt 0 shrink prof fitScale delta = ⟨fitScale, delta, 50, false, 0⟩ := by
  unfold tgt
  simp only [h, ite_true]
  have : ae (0 / shrink) = 0 := by
    have : (0 : Rat) / shrink = 0 := by grind
    rw [this]; exact ae_ends.1
  rw [this]
  simp only [Target.mk.injEq]
  grind

/-- One value's lerp step with snap (JS 10950-10956).

$$v' = \begin{cases} t & |t - (v + (t - v)\,0.2)| < \varepsilon \\ v + (t - v)\,0.2 & \text{otherwise}\end{cases}$$ -/
def step (snap v t : Rat) : Rat :=
  if max (t - (v + (t - v) * rate)) ((v + (t - v) * rate) - t) < snap then t else v + (t - v) * rate

/-- Has a value settled on its target? (JS 10953-10955, after the step) $$|t - v| < \varepsilon$$ -/
def settled (snap v t : Rat) : Bool := decide (max (t - v) (v - t) < snap)

#guard step snapScale 1 1 == 1
#guard step snapScale (61/50) 1 == 61/50 - (22/100) / 5
#guard settled snapOffset 0 0 == true
#guard settled snapOffset 1 0 == false

/-- **A step never crosses its target.** $$\min(v, t) \le v' \le \max(v, t)$$ -/
theorem step_between (snap v t : Rat) : min v t ≤ step snap v t ∧ step snap v t ≤ max v t := by
  unfold step rate
  have a1 : v ≤ t → v ≤ v + (t - v) * (1 / 5) ∧ v + (t - v) * (1 / 5) ≤ t := by intro h; grind
  have a2 : t ≤ v → t ≤ v + (t - v) * (1 / 5) ∧ v + (t - v) * (1 / 5) ≤ v := by intro h; grind
  split <;> grind

/-- **A fixed point.** A value at its target stays there and is settled (for a positive snap).
$$\varepsilon > 0 \Rightarrow \mathrm{step}(t, t) = t \land \mathrm{settled}(t, t)$$ -/
theorem step_fixed (snap t : Rat) (h : 0 < snap) : step snap t t = t ∧ settled snap t t = true := by
  unfold step settled
  have e : t + (t - t) * rate = t := by grind
  constructor
  · simp only [e]; split <;> rfl
  · simp only [decide_eq_true_eq]; grind

/-! ## Profession pick -/

/-- JS `Math.round`. $$\operatorname{rnd}(x) = \lfloor x + \tfrac12 \rfloor$$ -/
def rnd (x : Rat) : Int := (x + 1 / 2).floor

/-- Characterisation of the rounding. $$\operatorname{rnd}(x) = m \iff m - \tfrac12 \le x < m + \tfrac12$$ -/
theorem rnd_eq_iff (x : Rat) (m : Int) : rnd x = m ↔ ((m : Rat) - 1 / 2 ≤ x ∧ x < (m : Rat) + 1 / 2) := by
  unfold rnd
  constructor
  · intro h
    have h1 : m ≤ (x + 1 / 2).floor := by grind
    have h2 : (x + 1 / 2).floor < m + 1 := by grind
    rw [Rat.le_floor_iff] at h1
    rw [Rat.floor_lt_iff] at h2
    have : ((m + 1 : Int) : Rat) = (m : Rat) + 1 := by grind
    grind
  · intro ⟨h1, h2⟩
    have a : m ≤ (x + 1 / 2).floor := by rw [Rat.le_floor_iff]; grind
    have b : (x + 1 / 2).floor < m + 1 := by
      rw [Rat.floor_lt_iff]
      have : ((m + 1 : Int) : Rat) = (m : Rat) + 1 := by grind
      grind
    grind

/-- Lower bound of the rounding. $$m \le \operatorname{rnd}(x) \iff m - \tfrac12 \le x$$ -/
theorem le_rnd_iff (x : Rat) (m : Int) : m ≤ rnd x ↔ (m : Rat) - 1 / 2 ≤ x := by
  unfold rnd
  rw [Rat.le_floor_iff]
  grind

/-- Upper bound of the rounding. $$\operatorname{rnd}(x) < m \iff x < m - \tfrac12$$ -/
theorem rnd_lt_iff (x : Rat) (m : Int) : rnd x < m ↔ x < (m : Rat) - 1 / 2 := by
  unfold rnd
  rw [Rat.floor_lt_iff]
  grind

/-- Profession index for progress $k$ with $c$ professions and current index $q$ (JS 10799-10808).

$$\mathrm{pe}(k, q) = \begin{cases} 0 & c \le 1 \\ q & \operatorname{rnd}(k(c-1)) = q \\ \operatorname{clamp}_{[0,c-1]}\big(\operatorname{rnd}(k(c-1) + \beta)\big) & \text{otherwise}\end{cases},\quad \beta = \begin{cases} -0.35 & \operatorname{rnd}(k(c-1)) > q \\ +0.35 & \text{otherwise}\end{cases}$$

The bias pulls the pick back toward the current profession (hysteresis). -/
def pe (cnt : Nat) (k : Rat) (cur : Int) : Int :=
  if cnt ≤ 1 then 0
  else
    let n := k * ((cnt - 1 : Nat) : Rat)
    let r := rnd n
    if r = cur then cur
    else
      let b : Rat := if cur < r then -bias else bias
      min ((cnt - 1 : Nat) : Int) (max 0 (rnd (n + b)))

#guard pe 6 0 0 == 0
#guard pe 6 1 0 == 5
#guard pe 6 (1/5) 0 == 1
#guard pe 6 (16/100) 0 == 0
#guard pe 6 (17/100) 0 == 1
#guard pe 6 (1/5) 1 == 1

/-- **Hysteresis band.** While the raw position $n = k(c-1)$ stays in $[q - 0.85,\ q + 0.85)$ the pick stays $q$.

$$c \ge 2,\ 0 \le q < c,\ q - \tfrac{17}{20} \le n < q + \tfrac{17}{20} \Rightarrow \mathrm{pe}(k, q) = q$$

The tabs do not flicker when the scroll sits between two professions: to move one step the position must pass
$0.85$, not $0.5$, from the current one. -/
theorem pe_hold (cnt : Nat) (k : Rat) (cur : Int) (hc : 2 ≤ cnt) (h0 : 0 ≤ cur) (h1 : cur < (cnt : Int))
    (hlo : (cur : Rat) - 17 / 20 ≤ k * ((cnt - 1 : Nat) : Rat)) (hhi : k * ((cnt - 1 : Nat) : Rat) < (cur : Rat) + 17 / 20) :
    pe cnt k cur = cur := by
  unfold pe
  have hn : ¬ cnt ≤ 1 := by grind
  simp only [hn, ite_false]
  generalize k * ((cnt - 1 : Nat) : Rat) = n at *
  have hrng : min ((cnt - 1 : Nat) : Int) (max 0 cur) = cur := by grind
  by_cases hr : rnd n = cur
  · simp only [hr, ite_true]
  · simp only [hr, ite_false]
    rcases Int.lt_or_gt_of_ne (Ne.symm hr) with hlt | hgt
    · -- cur < rnd n: the position is above the current pick, the bias pulls it back
      have hc1 : cur + 1 ≤ rnd n := by grind
      have hge : ((cur + 1 : Int) : Rat) - 1 / 2 ≤ n := (le_rnd_iff n (cur + 1)).1 hc1
      have h2 : ((cur + 1 : Int) : Rat) = (cur : Rat) + 1 := by grind
      have : rnd (n + -bias) = cur := by
        rw [rnd_eq_iff]; unfold bias; grind
      simp only [hlt, ite_true, this]
      exact hrng
    · -- rnd n < cur
      have hlt : rnd n < cur := hgt
      have hle : ¬ cur < rnd n := by grind
      have hlt' : n < (cur : Rat) - 1 / 2 := (rnd_lt_iff n cur).1 hlt
      have : rnd (n + bias) = cur := by
        rw [rnd_eq_iff]; unfold bias; grind
      simp only [hle, ite_false, this]
      exact hrng

/-! ## Tab click target -/

/-- Scroll position a tab click aims at (JS 10826-10829).

$$\mathrm{goto}(i) = \Big\lceil y_s - 48 + S + \tfrac{i}{c-1}\,P \Big\rceil$$ -/
def gotoTop (showcaseY shrink prof : Rat) (cnt idx : Nat) : Int :=
  let f : Rat := if cnt ≤ 1 then 0 else (idx : Rat) / ((cnt - 1 : Nat) : Rat)
  (showcaseY - stickyTop + shrink + f * prof).ceil

/-- **The last tab lands at the end of the ranges.** $$\mathrm{goto}(c-1) = \lceil y_s - 48 + S + P \rceil$$ -/
theorem goto_last (y s p : Rat) (cnt : Nat) (h : 2 ≤ cnt) :
    gotoTop y s p cnt (cnt - 1) = (y - stickyTop + s + p).ceil := by
  unfold gotoTop
  have hn : ¬ cnt ≤ 1 := by grind
  simp only [hn, ite_false]
  have hz : ((cnt - 1 : Nat) : Rat) ≠ 0 := by
    intro hh
    have : ((cnt - 1 : Nat) : Rat) = ((0 : Nat) : Rat) := by simpa using hh
    have := Rat.natCast_inj.1 this
    grind
  have : ((cnt - 1 : Nat) : Rat) / ((cnt - 1 : Nat) : Rat) = 1 := by
    rw [Rat.div_def]; exact Rat.mul_inv_cancel _ hz
  rw [this]
  congr 1
  grind

/-- The first tab lands where the shrink range ends. $$\mathrm{goto}(0) = \lceil y_s - 48 + S \rceil$$ -/
theorem goto_first (y s p : Rat) (cnt : Nat) :
    gotoTop y s p cnt 0 = (y - stickyTop + s).ceil := by
  unfold gotoTop
  have e : (if cnt ≤ 1 then (0 : Rat) else ((0 : Nat) : Rat) / ((cnt - 1 : Nat) : Rat)) = 0 := by
    split
    · rfl
    · rw [Rat.div_def]; grind
  simp only [e]
  congr 1
  grind

/-! ## Touch layout: nearest shell -/

/-- Index of the centre nearest to the target; the first of equals wins (JS 10924-10934, strict `<`).

$$\mathrm{nearest}(t, [c_0, \dots]) = \arg\min_i |c_i - t|$$ -/
def nearestFrom (target : Rat) : List Rat → Nat → Nat → Rat → Nat
  | [], _, best, _ => best
  | c :: cs, i, best, bd =>
    let d := max (c - target) (target - c)
    if d < bd then nearestFrom target cs (i + 1) i d else nearestFrom target cs (i + 1) best bd

/-- `nearest` over a list, starting with the first element. $$\mathrm{nearest}(t, [c_0, c_1, \dots])$$ -/
def nearest (target : Rat) : List Rat → Nat
  | [] => 0
  | c :: cs => nearestFrom target cs 1 0 (max (c - target) (target - c))

#guard nearest 100 [0, 90, 210] == 1
#guard nearest 150 [0, 100, 200] == 1
#guard nearest 0 [] == 0

/-- **Debounce.** The scroll handler reads again after this many ms of quiet (JS 10938). $$150$$ -/
def debounceMs : Nat := 150

end Fw.Parts.PeopleDeck

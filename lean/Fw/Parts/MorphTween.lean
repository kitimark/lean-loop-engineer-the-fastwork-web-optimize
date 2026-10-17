/-!
# morph.tween: the 680 ms scroll-jacked tween of `--morph` (M2 port, `faithful`)

Restated (not copied) from the original snapshot, read independently of the TS part:

* `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`
  * 12683-12690: constant $0.55$ (fade end) and the clamp $\min(1,\max(0,x))$; the ease $1-(1-\mathrm{clamp}\,x)^3$;
  * 12691-12693: direction of a push: $|d| < 1$ gives none, else $d > 0$ gives up (1), $d \le 0$ gives down (0);
  * 12694-12698: the tween, $i = \mathrm{clamp}(\mathit{elapsed}/680)$, done iff $i \ge 1$, value $= \mathit{to}$
    when done else $\mathit{from} + (\mathit{to} - \mathit{from})\,\mathrm{ease}(i)$;
  * 12699-12701: the fade $1 - \min(1, m/0.55)$;
  * 13020-13029 (`S`): `--morph-fade` on the platform, `pointer-events: none` iff fade $< 0.05$;
  * 13030-13032 (`C`): active iff target $> 0.001$ or value $> 0.001$;
  * 13033-13035 (`T`): per frame value from the tween, next frame requested unless done;
  * 13036-13053 (`E`): a push to a new target restarts the tween from the current value, with the full 680 ms;
    under reduced motion the value jumps;
  * 13065-13072 (`O`, `k`): a push is taken when the tween is active, or it points down (delta $> 0$) and the platform
    box is at least $0.45$ of the visual viewport tall with its bottom at most 8 px below it.

All values `Rat` (rects and times can be fractional). No `Float`.
-/
namespace Fw.Parts.MorphTween

/-! ## Constants -/

/-- Tween duration in ms (JS 12694 default). $$D = 680$$ How long a push takes to run. -/
def duration : Rat := 680

/-- The platform fades out over the first 0.55 of the morph (JS 12683). $$\varphi = 0.55 = \tfrac{11}{20}$$ Where the fade reaches 0. -/
def fadeEnd : Rat := 11 / 20

/-- Below this opacity the platform stops taking pointer events (JS 13026). $$\theta = 0.05 = \tfrac{1}{20}$$ The cut. -/
def pointerCut : Rat := 1 / 20

/-- The morph counts as active above this value (JS 13030). $$\varepsilon = 0.001 = \tfrac{1}{1000}$$ The cut. -/
def activeCut : Rat := 1 / 1000

/-- Fraction of the visual viewport the platform box must fill (JS 13068). $$\rho = 0.45 = \tfrac{9}{20}$$ The ratio. -/
def fillRatio : Rat := 9 / 20

/-- Slack in px below the viewport for the platform bottom (JS 13068). $$\sigma = 8$$ The slack. -/
def bottomSlack : Rat := 8

/-- A push smaller than this (px) is ignored (JS 12691). $$\delta = 1$$ The dead zone. -/
def deadzone : Rat := 1

/-! ## The curve -/

/-- Clamp to the unit interval (JS 12685). $$\operatorname{clamp}(x) = \min(1, \max(0, x))$$ Held between 0 and 1. -/
def clamp01 (x : Rat) : Rat := min 1 (max 0 x)

/-- Ease-out cubic (JS 12688).

$$\operatorname{ease}(x) = 1 - (1 - \operatorname{clamp}(x))^3$$

Fast first, slow last. -/
def ease (x : Rat) : Rat := 1 - (1 - clamp01 x) * (1 - clamp01 x) * (1 - clamp01 x)

#guard ease 0 == 0
#guard ease 1 == 1
#guard ease (1/2) == 7/8
#guard ease 2 == 1
#guard ease (-1) == 0

/-- The clamp lies in the unit interval. $$\forall x:\ 0 \le \operatorname{clamp}(x) \le 1$$ Whatever the input. -/
theorem clamp01_mem (x : Rat) : 0 ≤ clamp01 x ∧ clamp01 x ≤ 1 := by unfold clamp01; grind

/-- The ease stays in the unit interval.

$$\forall x \in \mathbb{Q}:\quad 0 \le \operatorname{ease}(x) \le 1$$

The tween never overshoots. -/
theorem ease_mem (x : Rat) : 0 ≤ ease x ∧ ease x ≤ 1 := by
  have h := clamp01_mem x
  unfold ease
  generalize clamp01 x = c at *
  have hu0 : 0 ≤ 1 - c := by grind
  have hu1 : 1 - c ≤ 1 := by grind
  have h2 : (1 - c) * (1 - c) ≤ 1 := by
    have := Rat.mul_le_mul_of_nonneg_left hu1 hu0
    grind
  have h2' : 0 ≤ (1 - c) * (1 - c) := Rat.mul_nonneg hu0 hu0
  have h3 : (1 - c) * (1 - c) * (1 - c) ≤ 1 := by
    have := Rat.mul_le_mul_of_nonneg_left hu1 h2'
    grind
  have h3' : 0 ≤ (1 - c) * (1 - c) * (1 - c) := Rat.mul_nonneg h2' hu0
  grind

/-- The ease is monotone.

$$\forall x \le y:\quad \operatorname{ease}(x) \le \operatorname{ease}(y)$$

Time never runs the curve backwards. -/
theorem ease_mono (x y : Rat) (hxy : x ≤ y) : ease x ≤ ease y := by
  have hc : clamp01 x ≤ clamp01 y := by unfold clamp01; grind
  have hx := clamp01_mem x
  have hy := clamp01_mem y
  unfold ease
  generalize clamp01 x = a at *
  generalize clamp01 y = b at *
  have ha : 0 ≤ 1 - b := by grind
  have hab : 1 - b ≤ 1 - a := by grind
  have h2 : (1 - b) * (1 - b) ≤ (1 - a) * (1 - a) := by
    have h1 := Rat.mul_le_mul_of_nonneg_left hab ha
    have h2 := Rat.mul_le_mul_of_nonneg_right hab (show 0 ≤ 1 - a by grind)
    grind
  have h2' : 0 ≤ (1 - b) * (1 - b) := Rat.mul_nonneg ha ha
  have h3 : (1 - b) * (1 - b) * (1 - b) ≤ (1 - a) * (1 - a) * (1 - a) := by
    have h1 := Rat.mul_le_mul_of_nonneg_left hab h2'
    have h2 := Rat.mul_le_mul_of_nonneg_right h2 (show 0 ≤ 1 - a by grind)
    grind
  grind

/-- Result of one tween sample: the value and whether the tween has ended. $$(v, \mathit{done})$$ A sample. -/
structure Sample where
  value : Rat
  done : Bool
deriving Repr, BEq, DecidableEq

/-- One sample of the tween (JS 12694-12698).

$$\operatorname{tween}(f, t, e) = \begin{cases} (t, \top) & \operatorname{clamp}(e/680) \ge 1 \\ (f + (t - f)\,\operatorname{ease}(e/680),\ \bot) & \text{otherwise} \end{cases}$$

Where the morph is `elapsed` ms after a push that started at `from` and aims at `to`. -/
def tween (f t elapsed : Rat) : Sample :=
  let i := clamp01 (elapsed / duration)
  if 1 ≤ i then ⟨t, true⟩ else ⟨f + (t - f) * ease i, false⟩

#guard tween 0 1 0 == ⟨0, false⟩
#guard tween 0 1 680 == ⟨1, true⟩
#guard tween 0 1 340 == ⟨7/8, false⟩
#guard tween 1 0 340 == ⟨1/8, false⟩
#guard tween (3/10) 1 9999 == ⟨1, true⟩
#guard tween (3/10) 1 (-5) == ⟨3/10, false⟩

/-- Division by the duration is multiplication by its inverse. $$e/680 = e \cdot \tfrac{1}{680}$$ Lets the linear solver see it. -/
theorem div_dur (e : Rat) : e / duration = e * (1 / 680) := by unfold duration; grind

/-- A tween is done exactly when 680 ms have passed.

$$\operatorname{done}(\operatorname{tween}(f, t, e)) = \top \iff e \ge 680$$

The duration is the 680 ms of the original and nothing else ends it. -/
theorem tween_done_iff (f t e : Rat) : (tween f t e).done = true ↔ 680 ≤ e := by
  have key : 1 ≤ clamp01 (e / duration) ↔ 680 ≤ e := by
    unfold clamp01
    rw [div_dur]
    grind
  unfold tween
  by_cases h : 1 ≤ clamp01 (e / duration)
  · simp only [h, ite_true]; grind
  · simp only [h, ite_false]; grind

/-- At the end of its time the tween sits on the target.

$$e \ge 680 \Rightarrow \operatorname{tween}(f, t, e).\mathrm{value} = t$$

No residue is left at the end. -/
theorem tween_end (f t e : Rat) (h : 680 ≤ e) : (tween f t e).value = t := by
  have key : 1 ≤ clamp01 (e / duration) := by
    unfold clamp01
    rw [div_dur]
    grind
  unfold tween
  simp only [key, ite_true]

/-- At the start the tween sits on the start value.

$$e \le 0 \Rightarrow \operatorname{tween}(f, t, e).\mathrm{value} = f$$

A retarget does not jump: the new tween begins at the value the old one had reached. -/
theorem tween_start (f t e : Rat) (h : e ≤ 0) : (tween f t e).value = f := by
  have hc : clamp01 (e / duration) = 0 := by
    unfold clamp01
    rw [div_dur]
    grind
  have hn : ¬ ((1:Rat) ≤ 0) := by decide
  have he : ease 0 = 0 := by decide +kernel
  unfold tween
  simp only [hc, hn, ite_false, he]
  grind

/-- The value stays between the two ends.

$$\min(f, t) \le \operatorname{tween}(f, t, e).\mathrm{value} \le \max(f, t)$$

The morph never leaves the range of the push, so a 0..1 push stays in $[0, 1]$. -/
theorem tween_between (f t e : Rat) :
    min f t ≤ (tween f t e).value ∧ (tween f t e).value ≤ max f t := by
  have hm := ease_mem (clamp01 (e / duration))
  unfold tween
  by_cases hc : 1 ≤ clamp01 (e / duration)
  · simp only [hc, ite_true]; grind
  · simp only [hc, ite_false]
    generalize ease (clamp01 (e / duration)) = k at *
    by_cases hs : f ≤ t
    · have := Rat.mul_nonneg (show 0 ≤ t - f by grind) hm.1
      have := Rat.mul_le_mul_of_nonneg_left hm.2 (show 0 ≤ t - f by grind)
      grind
    · have := Rat.mul_nonneg (show 0 ≤ f - t by grind) hm.1
      have := Rat.mul_le_mul_of_nonneg_left hm.2 (show 0 ≤ f - t by grind)
      grind

/-! ## Pushes -/

/-- Direction of a push (JS 12691-12693).

$$\operatorname{dir}(d) = \begin{cases} \bot & |d| < 1 \\ 1 & d > 0 \\ 0 & d \le 0 \end{cases}$$

`none` is no push, `some 1` open, `some 0` close. -/
def dir (d : Rat) : Option Rat :=
  if (if 0 ≤ d then d else -d) < deadzone then none else some (if 0 < d then 1 else 0)

#guard dir (1/2) == none
#guard dir (-99/100) == none
#guard dir 1 == some 1
#guard dir (-1) == some 0
#guard dir 120 == some 1

/-- Pushes in the dead zone are ignored. $$-1 < d < 1 \Rightarrow \operatorname{dir}(d) = \bot$$ Small wheel and touch deltas do nothing. -/
theorem dir_deadzone (d : Rat) (h1 : -1 < d) (h2 : d < 1) : dir d = none := by
  unfold dir deadzone
  split <;> simp_all <;> grind

/-- A taken push aims at 0 or 1. $$\operatorname{dir}(d) = \operatorname{some}(g) \Rightarrow g = 0 \lor g = 1$$ The target is always an end. -/
theorem dir_target (d g : Rat) (h : dir d = some g) : g = 0 ∨ g = 1 := by
  unfold dir at h
  by_cases hl : (if 0 ≤ d then d else -d) < deadzone
  · simp [hl] at h
  · simp only [hl, ite_false, Option.some.injEq] at h
    by_cases hp : 0 < d
    · simp only [hp, ite_true] at h; grind
    · simp only [hp, ite_false] at h; grind

/-- Platform box test (JS 13065-13068).

$$\operatorname{armed}(h, b, v) = h \ge 0.45\,v \land b \le v + 8$$

The platform fills enough of the visual viewport and ends within 8 px of its bottom. -/
def armed (rectHeight rectBottom viewportHeight : Rat) : Bool :=
  decide (rectHeight ≥ viewportHeight * fillRatio) && decide (rectBottom ≤ viewportHeight + bottomSlack)

/-- Whether a push is taken (JS 13069).

$$\operatorname{taken}(\mathit{act}, d, \mathit{arm}) = \mathit{act} \lor (d > 0 \land \mathit{arm})$$

Once the morph is running both directions are taken; at rest only a downward push, and only when armed. -/
def taken (active : Bool) (delta : Rat) (arm : Bool) : Bool := active || (decide (0 < delta) && arm)

#guard armed 360 800 800 == true
#guard armed (3599/10) 800 800 == false
#guard armed 800 808 800 == true
#guard armed 800 (1617/2) 800 == false
#guard taken false (-5) true == false
#guard taken false 5 false == false
#guard taken false 5 true == true
#guard taken true (-5) false == true

/-- At rest an upward push is never taken. $$\neg\mathit{act},\ d \le 0 \Rightarrow \operatorname{taken}(\mathit{act}, d, \mathit{arm}) = \bot$$ Only downward pushes open the morph. -/
theorem taken_rest_up (d : Rat) (arm : Bool) (h : d ≤ 0) : taken false d arm = false := by
  unfold taken
  have : ¬ (0 < d) := by grind
  simp [this]

/-- Active test (JS 13030). $$\operatorname{active}(w, r) = w > 0.001 \lor r > 0.001$$ `w` is the target, `r` the value. -/
def active (target value : Rat) : Bool := decide (target > activeCut) || decide (value > activeCut)

/-! ## The platform fade -/

/-- `--morph-fade` (JS 12699-12701). $$\operatorname{fade}(m) = 1 - \min(1, m/0.55)$$ 1 at rest, 0 from 0.55 on. -/
def fade (m : Rat) : Rat := 1 - min 1 (m / fadeEnd)

/-- The platform takes no pointer events once the fade is below 0.05 (JS 13026). $$\operatorname{fade}(m) < 0.05$$ The cut. -/
def pointerNone (m : Rat) : Bool := decide (fade m < pointerCut)

#guard fade 0 == 1
#guard fade (11/40) == 1/2
#guard fade (11/20) == 0
#guard fade 1 == 0
#guard pointerNone (209/400) == false
#guard pointerNone (2091/4000) == true
#guard pointerNone 0 == false

/-- The fade is 1 at rest and 0 from 0.55 on.

$$\operatorname{fade}(0) = 1,\qquad m \ge 0.55 \Rightarrow \operatorname{fade}(m) = 0$$

The platform is fully visible before the morph and fully gone by 0.55. -/
theorem fade_ends : fade 0 = 1 ∧ ∀ m, fadeEnd ≤ m → fade m = 0 := by
  constructor
  · unfold fade; rw [show (0:Rat) / fadeEnd = 0 by unfold fadeEnd; grind]; grind
  · intro m h
    unfold fade
    have hdiv : m / fadeEnd = m * (20 / 11) := by unfold fadeEnd; grind
    have : 1 ≤ m / fadeEnd := by rw [hdiv]; unfold fadeEnd at h; grind
    grind

/-- **Pointer cut-over.** The platform stops taking pointer events exactly above $m = 0.5225$ (for $m \ge 0$).

$$m \ge 0 \Rightarrow \big(\operatorname{pointerNone}(m) = \top \iff m > 0.95 \cdot 0.55 = \tfrac{209}{400}\big)$$

The cut is strict, so $m = 0.5225$ still takes pointer events. -/
theorem pointerNone_iff (m : Rat) : pointerNone m = true ↔ 209 / 400 < m := by
  have hk : m / fadeEnd = m * (20 / 11) := by unfold fadeEnd; grind
  unfold pointerNone fade pointerCut
  simp only [decide_eq_true_eq]
  rw [hk]
  by_cases h1 : 1 ≤ m * (20 / 11)
  · have : min 1 (m * (20 / 11)) = 1 := by grind
    rw [this]; grind
  · have : min 1 (m * (20 / 11)) = m * (20 / 11) := by grind
    rw [this]; grind

/-! ## The state machine -/

/-- Tween state: value $r$, target $w$, from $i$, to $a$, start time $o$ (ms), a frame requested. -/
structure St where
  value : Rat
  target : Rat
  f : Rat
  t : Rat
  start : Rat
  pending : Bool
deriving Repr, BEq, DecidableEq

/-- Rest: everything 0, nothing pending. $$s_0 = (0,0,0,0,0,\bot)$$ The state before any push. -/
def rest : St := ⟨0, 0, 0, 0, 0, false⟩

/-- Is the morph running (JS 13030). $$\operatorname{active}(s.w, s.r)$$ Target or value above the cut. -/
def St.isActive (s : St) : Bool := active s.target s.value

/-- A taken push toward `g ∈ {0,1}` at time `now` (JS 13036-13053).

$$\operatorname{push}(s, g, \mathit{rm}, t) = \begin{cases} s & s.w = g \land s.a = g \\ (g, g, s.i, g, s.o, \bot) & \mathit{rm} \\ (s.r, g, s.r, g, t, \top) & \text{otherwise} \end{cases}$$

Same target while already heading there changes nothing; reduced motion jumps; otherwise the tween restarts from the
current value with the full 680 ms. -/
def push (s : St) (g : Rat) (reduced : Bool) (now : Rat) : St :=
  if s.target = g ∧ s.t = g then s
  else if reduced then { s with value := g, target := g, t := g, pending := false }
  else { s with target := g, f := s.value, t := g, start := now, pending := true }

/-- One animation frame at time `now` (JS 13033-13035).

$$\operatorname{frame}(s, t) = s\{r := \operatorname{tween}(s.i, s.a, t - s.o).\mathrm{value},\ n := \lnot\operatorname{tween}(\ldots).\mathrm{done}\}$$

The value follows the curve; a next frame is wanted until the tween is done. -/
def frame (s : St) (now : Rat) : St :=
  let z := tween s.f s.t (now - s.start)
  { s with value := z.value, pending := !z.done }

#guard (push rest 1 false 100).pending == true
#guard (frame (push rest 1 false 100) 100).value == 0
#guard (frame (push rest 1 false 100) 440).value == 7/8
#guard (frame (push rest 1 false 100) 780).value == 1
#guard (frame (push rest 1 false 100) 780).pending == false
#guard (push rest 1 true 100).value == 1
#guard push (push rest 1 true 100) 1 true 200 == push rest 1 true 100

/-- A retarget starts where the morph is, so the value is continuous across it.

$$\neg(s.w = g \land s.a = g) \Rightarrow \operatorname{frame}(\operatorname{push}(s, g, \bot, t), t).r = s.r$$

Reversing mid-flight does not jump. -/
theorem push_continuous (s : St) (g now : Rat) (h : ¬ (s.target = g ∧ s.t = g)) :
    (frame (push s g false now) now).value = s.value := by
  unfold push frame
  simp only [h, ite_false, Bool.false_eq_true]
  exact tween_start _ _ _ (by grind)

/-- A running tween keeps its value in the range of its ends.

$$\min(s.i, s.a) \le \operatorname{frame}(s, t).r \le \max(s.i, s.a)$$

Every frame's value lies between where the push started and where it aims. -/
theorem frame_between (s : St) (now : Rat) :
    min s.f s.t ≤ (frame s now).value ∧ (frame s now).value ≤ max s.f s.t :=
  tween_between _ _ _

end Fw.Parts.MorphTween

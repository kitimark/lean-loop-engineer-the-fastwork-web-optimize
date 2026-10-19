import Fw.Engine.Core
/-!
# people.carousel: the avatar carousel of the community pill (`faithful`)

Restated (not copied) from `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`, read independently of the TS part:

* 11263-11275 and 11289-11322: the loop. While the section is active (the engine's visibility signal) it waits
  $800$ ms (`f(800)`), then, if still active, shows the swap template for $220$ ms (`f(220)`), then, if still active,
  advances the index $x \leftarrow (x+1) \bmod n$ and hides the swap template; if it lost the activity in the 220 ms it
  hides the template without advancing, and if it lost it in the first 800 ms it waits for the activity again.
  Under reduced motion the loop never runs;
* 11330-11356 and 11415-11447: the rest template shows the 4 avatars $E(0..3)$; the swap template shows 5 avatars
  $E(0..4)$, the first with class `is-exit` and the last with `is-enter`; $E(k) = \mathit{avatars}[(x+k) \bmod n]$
  with $n = 6$ avatars (the six professions in showcase order);
* CSS `assets/2.gBuqKVzi.css` 2866-2915: the carousel box is $104 \times 32$ px, `overflow: hidden`, each avatar is
  `flex: 0 0 32px` with `margin-right: -8px` except the last child; `avatars-exit` (0.22 s) takes the width from 32 to 0
  and the margin from $-8$ to $0$; `avatars-pop` (0.22 s) takes opacity and scale to 1.

Times are whole milliseconds (`Nat`); nothing here is a float.
-/
namespace Fw.Parts.PeopleCarousel

/-! ## Constants -/

/-- Wait before a swap in ms (JS 11291 `f(800)`). $$R = 800$$ How long the row rests. -/
def restMs : Nat := 800

/-- Duration of the swap template in ms (JS 11295 `f(220)`, CSS `0.22s`). $$S = 220$$ How long the swap shows. -/
def swapMs : Nat := 220

/-- One full cycle in ms. $$P = R + S = 1020$$ From one index step to the next while the section stays active. -/
def periodMs : Nat := restMs + swapMs

/-- Number of avatars in the ring (the six professions). $$n = 6$$ The ring size. -/
def ringSize : Nat := 6

/-- Avatars shown at rest. $$m = 4$$ The window size. -/
def shown : Nat := 4

/-- Avatar diameter in px (CSS 2884). $$d = 32$$ The slot width. -/
def avatarPx : Nat := 32

/-- Overlap between neighbours in px (CSS 2888, `margin-right: -8px`). $$o = 8$$ The negative margin. -/
def overlapPx : Nat := 8

/-- The cycle is 1020 ms. $$P = 1020$$ -/
theorem period_eq : periodMs = 1020 := by decide

/-! ## Layout -/

/-- Width in px of a row of $k \ge 1$ avatars with the overlap.

$$W(k) = k\,d - (k-1)\,o$$

The row of the last child has no negative margin. -/
def rowPx (k : Nat) : Nat := k * avatarPx - (k - 1) * overlapPx

/-- **The box fits the rest row exactly.**

$$W(4) = 4 \cdot 32 - 3 \cdot 8 = 104$$

The carousel box is 104 px wide, so the rest row fills it without a gap. -/
theorem rest_row_fills_box : rowPx shown = 104 := by decide

/-- During the swap the row is wider than the box, so the entering avatar is clipped.

$$W(5) = 128 > 104$$

`overflow: hidden` hides the extra 24 px until the exit avatar has collapsed. -/
theorem swap_row_overflows : rowPx (shown + 1) = 128 ∧ 104 < rowPx (shown + 1) := by decide

/-- **Layout continuity.** When the exit avatar has collapsed (width 0, margin 0) the remaining four avatars have the
rest width.

$$4\,d - 3\,o = W(4) = 104$$

The next rest frame has the same layout as the last swap frame. -/
theorem swap_end_is_rest : 4 * avatarPx - 3 * overlapPx = rowPx shown := by decide

/-! ## The ring -/

/-- Index of the avatar at slot $k$ when the head is $x$.

$$E_x(k) = (x + k) \bmod n$$ -/
def slot (x k : Nat) : Nat := (x + k) % ringSize

/-- The rest window. $$\mathrm{rest}(x) = [E_x(0), E_x(1), E_x(2), E_x(3)]$$ -/
def restWindow (x : Nat) : List Nat := (List.range shown).map (slot x)

/-- The swap window (the exit avatar first, the enter avatar last).
$$\mathrm{swap}(x) = [E_x(0), \dots, E_x(4)]$$ -/
def swapWindow (x : Nat) : List Nat := (List.range (shown + 1)).map (slot x)

/-- The slot only depends on the head modulo the ring size. $$\forall x, k:\ E_{x \bmod n}(k) = E_x(k)$$ -/
theorem slot_mod (x k : Nat) : slot (x % ringSize) k = slot x k := by
  simp only [slot, ringSize]; omega

/-- Swap windows only depend on the head modulo the ring size. $$\mathrm{swap}(x \bmod n) = \mathrm{swap}(x)$$ -/
theorem swapWindow_mod (x : Nat) : swapWindow (x % ringSize) = swapWindow x := by
  have : slot (x % ringSize) = slot x := funext (slot_mod x)
  simp only [swapWindow, this]

/-- Rest windows only depend on the head modulo the ring size. $$\mathrm{rest}(x \bmod n) = \mathrm{rest}(x)$$ -/
theorem restWindow_mod (x : Nat) : restWindow (x % ringSize) = restWindow x := by
  have : slot (x % ringSize) = slot x := funext (slot_mod x)
  simp only [restWindow, this]

/-- **The swap lands on the next rest window.** Dropping the exit avatar from the swap window gives the rest window
of the next index.

$$\forall x:\ \mathrm{drop}_1(\mathrm{swap}(x)) = \mathrm{rest}((x+1) \bmod n)$$

What the user sees at the end of the 220 ms is exactly the rest row one step later. -/
theorem swap_drop_is_next_rest (x : Nat) : (swapWindow x).drop 1 = restWindow ((x + 1) % ringSize) := by
  have h : ∀ y : Fin ringSize, (swapWindow y).drop 1 = restWindow ((y + 1) % ringSize) := by decide
  have := h ⟨x % ringSize, Nat.mod_lt _ (by decide)⟩
  simp only [swapWindow_mod] at this
  rw [this]
  have e : (x % ringSize + 1) % ringSize = (x + 1) % ringSize := by simp only [ringSize]; omega
  rw [e]

/-- **The five slots of a swap are distinct.** With six avatars no face appears twice in the swap row.

$$\forall x:\ \text{the entries of } \mathrm{swap}(x) \text{ are pairwise different}$$

So the entering avatar is never one already on screen. -/
theorem swap_window_nodup (x : Nat) : (swapWindow x).Nodup := by
  have h : ∀ y : Fin ringSize, (swapWindow y).Nodup := by decide
  have := h ⟨x % ringSize, Nat.mod_lt _ (by decide)⟩
  simpa [swapWindow_mod] using this

/-! ## The loop as a state machine -/

/-- Loop state: the head index and whether the swap template shows.
$$s = (x, w) \in \mathbb{N} \times \{\top, \bot\}$$ -/
structure State where
  x : Nat
  swapping : Bool
deriving Repr, BEq, DecidableEq

/-- Start state. $$s_0 = (0, \bot)$$ The index is 0 and the rest template shows. -/
def start : State := ⟨0, false⟩

/-- What the loop does when the 800 ms rest timer ends (JS 11291-11296).

$$\mathrm{afterRest}(s, a) = \begin{cases} (x, \top) & a \\ s & \lnot a \end{cases}$$

If the section is active the swap template shows (and a 220 ms timer starts); otherwise nothing changes and the loop
waits for the activity again. -/
def afterRest (s : State) (active : Bool) : State := if active then { s with swapping := true } else s

/-- What the loop does when the 220 ms swap timer ends (JS 11297-11302).

$$\mathrm{afterSwap}(s, a) = \begin{cases} ((x+1) \bmod n, \bot) & a \\ (x, \bot) & \lnot a \end{cases}$$

If still active the index advances; either way the swap template is hidden. -/
def afterSwap (s : State) (active : Bool) : State :=
  if active then ⟨(s.x + 1) % ringSize, false⟩ else { s with swapping := false }

/-- One uninterrupted cycle (active throughout). $$\mathrm{cycle}(s) = \mathrm{afterSwap}(\mathrm{afterRest}(s, \top), \top)$$ -/
def cycle (s : State) : State := afterSwap (afterRest s true) true

/-- Cycles from the start. $$\mathrm{run}_0 = s_0,\quad \mathrm{run}_{k+1} = \mathrm{cycle}(\mathrm{run}_k)$$ -/
def run : Nat → State
  | 0 => start
  | k + 1 => cycle (run k)

/-- **Closed form of an uninterrupted run.**

$$\mathrm{run}_k = (k \bmod n,\ \bot)$$

After $k$ cycles ($1020\,k$ ms of continuous activity plus the 800 ms start wait) the head is $k \bmod 6$. -/
theorem run_closed (k : Nat) : run k = ⟨k % ringSize, false⟩ := by
  induction k with
  | zero => rfl
  | succ k ih =>
    simp only [run, ih, cycle, afterSwap, afterRest, ite_true]
    simp [Nat.add_mod, ringSize]

/-- **The ring returns after $n$ cycles.**

$$\mathrm{run}_{n} = s_0$$

The carousel is periodic with period $n \cdot 1020 = 6120$ ms. -/
theorem run_period : run ringSize = start := by decide

/-- **Index at a time.** For the continuously active loop, the head $t$ ms after the 800 ms start wait has elapsed
(when the first cycle begins) and the swap flag.

$$x(t) = \lfloor t / 1020 \rfloor \bmod n,\qquad w(t) = \big[\,800 \le t \bmod 1020\,\big]$$

The state at any instant is a function of time alone. -/
def stateAt (t : Nat) : State := ⟨(t / periodMs) % ringSize, restMs ≤ t % periodMs⟩

/-- At each cycle boundary the closed form agrees with the loop.

$$\mathrm{stateAt}(1020\,k) = \mathrm{run}_k$$ -/
theorem stateAt_boundary (k : Nat) : stateAt (periodMs * k) = run k := by
  rw [run_closed]
  have h1 : periodMs * k / periodMs = k := Nat.mul_div_cancel_left _ (by decide)
  have h2 : periodMs * k % periodMs = 0 := Nat.mul_mod_right _ _
  simp [stateAt, h1, h2, restMs]

/-- **The swap window is 220 ms of every 1020.**

$$w(t) \iff t \bmod 1020 \in [800, 1020)$$

The swap template shows for exactly the last $S$ ms of each cycle. -/
theorem swap_phase (t : Nat) : (stateAt t).swapping = true ↔ restMs ≤ t % periodMs := by
  simp [stateAt]

/-- A lost activity during the rest wait never advances the index.
$$\mathrm{afterRest}(s, \bot) = s$$ -/
theorem afterRest_inactive (s : State) : afterRest s false = s := rfl

/-- A lost activity during the swap never advances the index and hides the swap template.
$$\mathrm{afterSwap}(s, \bot) = (x, \bot)$$ -/
theorem afterSwap_inactive (s : State) : afterSwap s false = ⟨s.x, false⟩ := rfl

/-- The index always stays inside the ring.
$$\forall s,\ a:\ x \lt n \Rightarrow \mathrm{afterSwap}(s, a).x \lt n$$ -/
theorem afterSwap_lt (s : State) (a : Bool) (h : s.x < ringSize) : (afterSwap s a).x < ringSize := by
  unfold afterSwap
  cases a <;> simp [h]
  exact Nat.mod_lt _ (by decide)

/-! ## Swapping one change of a frame (work only, ledger n=19)

Both st6 parts replace one main-thread change of a frame by a change with fewer stages, keeping the other changes
`xs`, and may add $m$ compositor animations. The frames below are stated over any engine `E` of `Fw.Engine.Core`; the
premises on `E` are hypotheses. -/

section Swap

open Fw.Engine (Stage Change FrameIn Engine Work frameWork touched stageUnits forcedPasses coverB frame_le_of_cover)

/-- A frame with no script, forced passes or hit tests, the change list $c :: \mathit{xs}$ and $a$ compositor
animations. $$F(c, \mathit{xs}, a) = (0, 0, 0, 0, c :: \mathit{xs}, a)$$ -/
def frameWith {P : Type} (c : Change P) (xs : List (Change P)) (a : Nat) : FrameIn P := ⟨0, 0, 0, 0, c :: xs, a⟩

/-- **Main-thread work does not grow.** If every stage of $c$ is a stage of $d$, then on every stage outside the
compositor-animation stages, the frame with $c$ and $a + m$ animations has at most the passes and units of the frame
with $d$ and $a$ animations.

$$\forall E,\ \forall c, d,\ \forall \mathit{xs},\ \forall a, m \in \mathbb{N}:\ E.\mathrm{stagesOf}(c) \subseteq E.\mathrm{stagesOf}(d) \Rightarrow \forall s \notin E.\mathrm{compStages}:\ W_E(F(c, \mathit{xs}, a + m)).\mathrm{passes}(s) \le W_E(F(d, \mathit{xs}, a)).\mathrm{passes}(s) \land W_E(F(c, \mathit{xs}, a + m)).\mathrm{units}(s) \le W_E(F(d, \mathit{xs}, a)).\mathrm{units}(s)$$

Added compositor animations cost nothing on the main-thread stages. -/
theorem swap_main_le {P M : Type} (E : Engine P M) (c d : Change P) (xs : List (Change P)) (a m : Nat)
    (hcov : ∀ s ∈ E.stagesOf c, s ∈ E.stagesOf d) (s : Stage) (hs : s ∉ E.compStages) :
    (frameWork E (frameWith c xs (a + m))).passes s ≤ (frameWork E (frameWith d xs a)).passes s ∧
      (frameWork E (frameWith c xs (a + m))).units s ≤ (frameWork E (frameWith d xs a)).units s := by
  have key : s ∈ touched E (frameWith c xs (a + m)) → s ∈ touched E (frameWith d xs a) := by
    simp only [touched, frameWith, FrameIn.updates, List.mem_append, List.flatMap_cons]
    intro h
    rcases h with (((h | h) | h) | h) | h
    · exact Or.inl (Or.inl (Or.inl (Or.inl (hcov s h))))
    · exact Or.inl (Or.inl (Or.inl (Or.inr h)))
    · exfalso
      by_cases ha : 0 < a + m <;> simp [ha] at h
      exact hs h
    · exact Or.inl (Or.inr (by simpa using h))
    · exact Or.inr h
  have hf : ∀ (e : Change P) (b : Nat), forcedPasses (frameWith e xs b) s = 0 := by
    intro e b; cases s <;> rfl
  constructor
  · simp only [frameWork, hf]
    by_cases h1 : s ∈ touched E (frameWith c xs (a + m))
    · simp [h1, key h1]
    · simp [h1]
  · simp only [frameWork, stageUnits, frameWith, List.countP_cons, hs, ite_false, ite_self, Nat.add_zero]
    by_cases hc : s ∈ E.stagesOf c
    · simp [hc, hcov s hc]
    · by_cases hd : s ∈ E.stagesOf d <;> simp [hc, hd] <;> omega

/-- **Layout units fall by one.** If `layout` is a stage of $d$ but neither of $c$ nor a compositor-animation stage,
the frame with $c$ has one layout unit fewer.

$$\forall E,\ \forall c, d,\ \forall \mathit{xs},\ \forall a, m \in \mathbb{N}:\ \mathrm{layout} \in E.\mathrm{stagesOf}(d) \land \mathrm{layout} \notin E.\mathrm{stagesOf}(c) \land \mathrm{layout} \notin E.\mathrm{compStages} \Rightarrow W_E(F(c, \mathit{xs}, a + m)).\mathrm{units}(\mathrm{layout}) + 1 = W_E(F(d, \mathit{xs}, a)).\mathrm{units}(\mathrm{layout})$$

The swapped change no longer dirties layout. -/
theorem swap_layout_units {P M : Type} (E : Engine P M) (c d : Change P) (xs : List (Change P)) (a m : Nat)
    (hd : Stage.layout ∈ E.stagesOf d) (hc : Stage.layout ∉ E.stagesOf c) (hcs : Stage.layout ∉ E.compStages) :
    (frameWork E (frameWith c xs (a + m))).units .layout + 1 = (frameWork E (frameWith d xs a)).units .layout := by
  simp only [frameWork, stageUnits, frameWith, List.countP_cons, hd, hc, hcs, decide_true, decide_false, ite_false]
  simp

/-- **Without added animations the swap is strictly below.** If every stage of $c$ is a stage of $d$, and `layout`
is a stage of $d$ but neither of $c$ nor a compositor-animation stage, the frame with $c$ is $\prec$ the frame with
$d$ (same other changes, same animations).

$$\forall E,\ \forall c, d,\ \forall \mathit{xs},\ \forall a \in \mathbb{N}:\ E.\mathrm{stagesOf}(c) \subseteq E.\mathrm{stagesOf}(d) \land \mathrm{layout} \in E.\mathrm{stagesOf}(d) \land \mathrm{layout} \notin E.\mathrm{stagesOf}(c) \land \mathrm{layout} \notin E.\mathrm{compStages} \Rightarrow W_E(F(c, \mathit{xs}, a)) \prec W_E(F(d, \mathit{xs}, a))$$

This is the bridge for the 0.999 rest: $d$ is the presence-flip change, $c$ the change that stops short of it. -/
theorem swap_lt {P M : Type} (E : Engine P M) (c d : Change P) (xs : List (Change P)) (a : Nat)
    (hcov : ∀ s ∈ E.stagesOf c, s ∈ E.stagesOf d) (hd : Stage.layout ∈ E.stagesOf d)
    (hc : Stage.layout ∉ E.stagesOf c) (hcs : Stage.layout ∉ E.compStages) :
    (frameWork E (frameWith c xs a)).lt (frameWork E (frameWith d xs a)) := by
  refine ⟨frame_le_of_cover E (d :: xs) [] (by simp [frameWith]) ?_ (Nat.le_refl _) (Nat.le_refl _)
    (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _), Or.inl ⟨.layout, Or.inr ?_⟩⟩
  · have hr : ∀ l : List (Change P), coverB E l l = true := by
      intro l
      induction l with
      | nil => rfl
      | cons x l ih => simp [coverB, ih]
    simp only [frameWith, coverB, hr, Bool.and_true, List.all_eq_true, decide_eq_true_eq]
    exact hcov
  · have := swap_layout_units E c d xs a 0 hd hc hcs
    simp only [Nat.add_zero] at this
    omega

/-- **Added animations make it a trade.** If $m > 0$ animations are added and some compositor-animation stage is not
a stage of $d$, the frame with $c$ is not $\preceq$ the frame with $d$: it has $m$ more units there.

$$\forall E,\ \forall c, d,\ \forall \mathit{xs},\ \forall a, m \in \mathbb{N},\ \forall s \in \mathrm{Stage}:\ 0 < m \land s \in E.\mathrm{compStages} \land s \notin E.\mathrm{stagesOf}(d) \Rightarrow \lnot\big(W_E(F(c, \mathit{xs}, a + m)) \preceq W_E(F(d, \mathit{xs}, a))\big)$$

The st6 slide adds the followers' translate animations, so it is a trade under Core's order. -/
theorem swap_not_le {P M : Type} (E : Engine P M) (c d : Change P) (xs : List (Change P)) (a m : Nat) (s : Stage)
    (hm : 0 < m) (hs : s ∈ E.compStages) (hd : s ∉ E.stagesOf d) :
    ¬ (frameWork E (frameWith c xs (a + m))).le (frameWork E (frameWith d xs a)) := by
  intro h
  have h1 := (h.1 s).2
  simp only [frameWork, stageUnits, frameWith, List.countP_cons, hs, hd, ite_true, decide_false] at h1
  split at h1 <;> simp at h1 <;> omega

end Swap

/-! ## st6 rest at opacity 0.999 and `scale(1)` (ledger n=19, KD#8)

Restated from v1 `fixes/rotator-st6/README.md` (st5: the five slots stay mounted; st6: every slot rests at
`transform: scale(1); opacity: 0.999`, `avatars-exit` starts and `avatars-pop` ends at 0.999) and CSS 2866-2915
(`avatars-exit` from opacity 1, `scale(1)` to 0, `scale(.35)`; `avatars-pop` from 0, `scale(.35)` to 1, `scale(1)`;
both `forwards`). A slot's look is its opacity, whether it has a transform, and whether an animation holds it.

The flip rules: WebKit asks for layout when `opacity.isOpaque()` or `hasTransform()` changes (StyleDifference.cpp
208-215, CONFIRMED at 862f17d); Chromium makes a stacking context for opacity below 1 (HasNonInitialOpacity, CONFIRMED
at f842f52), a transform (INFERRED) or a current opacity/transform animation (computed_style.h 2070-2076), and a
stacking flip calls SetNeedsFullLayout (computed_style.cc 779-784). Easings `cubic-bezier(.16,1,.3,1)` and
`(.33,1,.68,1)` have control ordinates in $[0, 1]$, so the progress $p$ stays in $[0, 1]$. -/

/-- A slot's look: opacity, transform present, animation current. $$\ell = (\alpha, \tau, \kappa) \in \mathbb{Q} \times \{\top,\bot\}^2$$ -/
structure Look where
  opacity : Rat
  transform : Bool
  anim : Bool
deriving DecidableEq

/-- The st5 rest look (the original's rest): opaque, no transform, no animation. $$\ell_5 = (1, \bot, \bot)$$ -/
def st5Rest : Look := ⟨1, false, false⟩

/-- The st6 rest look. $$\ell_6 = (\tfrac{999}{1000}, \top, \bot)$$ -/
def st6Rest : Look := ⟨999 / 1000, true, false⟩

/-- WebKit's layout flip between two looks: opaqueness or transform presence differs.

$$\mathrm{wk}(\ell, \ell') \iff [\alpha < 1] \ne [\alpha' < 1] \ \lor\ \tau \ne \tau'$$ -/
def wkFlip (l l' : Look) : Bool := (decide (l.opacity < 1) != decide (l'.opacity < 1)) || (l.transform != l'.transform)

/-- Chromium's stacking context of a look. $$\mathrm{sc}(\ell) \iff \alpha < 1 \lor \tau \lor \kappa$$ -/
def crSC (l : Look) : Bool := decide (l.opacity < 1) || l.transform || l.anim

/-- Chromium's full-layout flip: the stacking context differs. $$\mathrm{cr}(\ell, \ell') \iff \mathrm{sc}(\ell) \ne \mathrm{sc}(\ell')$$ -/
def crFlip (l l' : Look) : Bool := crSC l != crSC l'

/-- The animated look at progress $p$ of keyframes from opacity $x$ to $y$ (transform present, animation current).

$$\mathrm{at}(x, y, p) = \big((1 - p)\,x + p\,y,\ \top,\ \top\big)$$ -/
def animAt (x y p : Rat) : Look := ⟨(1 - p) * x + p * y, true, true⟩

/-- **No flip between the st6 rest and any animated look below opacity 1.** For every look with opacity below 1 and a
transform, neither engine's flip fires from or to the st6 rest.

$$\forall \ell:\ \alpha < 1 \land \tau \Rightarrow \lnot\mathrm{wk}(\ell_6, \ell) \land \lnot\mathrm{wk}(\ell, \ell_6) \land \lnot\mathrm{cr}(\ell_6, \ell) \land \lnot\mathrm{cr}(\ell, \ell_6)$$

Entering or leaving a slide never asks for layout. -/
theorem st6_no_flip (l : Look) (ho : l.opacity < 1) (ht : l.transform = true) :
    wkFlip st6Rest l = false ∧ wkFlip l st6Rest = false ∧ crFlip st6Rest l = false ∧ crFlip l st6Rest = false := by
  have h6 : (999 / 1000 : Rat) < 1 := by grind
  simp [wkFlip, crFlip, crSC, st6Rest, ho, ht, h6]

/-- **The st6 keyframes stay below opacity 1.** Between two opacities at most $\tfrac{999}{1000}$ (either direction),
every progress $p \in [0, 1]$ gives opacity at most $\tfrac{999}{1000}$, so below 1.

$$\forall x, y, p \in \mathbb{Q}:\ x \le \tfrac{999}{1000} \land y \le \tfrac{999}{1000} \land 0 \le p \land p \le 1 \Rightarrow \mathrm{at}(x, y, p).\alpha \le \tfrac{999}{1000} \land \mathrm{at}(x, y, p).\alpha < 1$$ -/
theorem st6_anim_lt_one (x y p : Rat) (hx : x ≤ 999 / 1000) (hy : y ≤ 999 / 1000)
    (hp0 : 0 ≤ p) (hp1 : p ≤ 1) : (animAt x y p).opacity ≤ 999 / 1000 ∧ (animAt x y p).opacity < 1 := by
  simp only [animAt]
  have h1 : (1 - p) * x ≤ (1 - p) * (999 / 1000) := Rat.mul_le_mul_of_nonneg_left hx (by grind)
  have h2 : p * y ≤ p * (999 / 1000) := Rat.mul_le_mul_of_nonneg_left hy hp0
  constructor <;> grind

/-- **The st6 slide never flips.** For the st6 pop (from $0$ to $\tfrac{999}{1000}$) and exit (from
$\tfrac{999}{1000}$ to $0$) at any progress $p \in [0, 1]$, neither engine's flip fires from or to the rest look.

$$\forall p \in \mathbb{Q}:\ 0 \le p \le 1 \Rightarrow \forall \ell \in \{\mathrm{at}(0, \tfrac{999}{1000}, p),\ \mathrm{at}(\tfrac{999}{1000}, 0, p)\}:\ \lnot\mathrm{wk}(\ell_6, \ell) \land \lnot\mathrm{wk}(\ell, \ell_6) \land \lnot\mathrm{cr}(\ell_6, \ell) \land \lnot\mathrm{cr}(\ell, \ell_6)$$ -/
theorem st6_slide_no_flip (p : Rat) (hp0 : 0 ≤ p) (hp1 : p ≤ 1) :
    (wkFlip st6Rest (animAt 0 (999 / 1000) p) = false ∧ wkFlip (animAt 0 (999 / 1000) p) st6Rest = false ∧
      crFlip st6Rest (animAt 0 (999 / 1000) p) = false ∧ crFlip (animAt 0 (999 / 1000) p) st6Rest = false) ∧
    (wkFlip st6Rest (animAt (999 / 1000) 0 p) = false ∧ wkFlip (animAt (999 / 1000) 0 p) st6Rest = false ∧
      crFlip st6Rest (animAt (999 / 1000) 0 p) = false ∧ crFlip (animAt (999 / 1000) 0 p) st6Rest = false) :=
  ⟨st6_no_flip _ (st6_anim_lt_one 0 _ p (by grind) (by grind) hp0 hp1).2 rfl,
    st6_no_flip _ (st6_anim_lt_one _ 0 p (by grind) (by grind) hp0 hp1).2 rfl⟩

/-- **The st5 rest flips at every slide edge.** For every look with a transform, both engines' flips fire from and to
the st5 rest.

$$\forall \ell:\ \tau \Rightarrow \mathrm{wk}(\ell_5, \ell) \land \mathrm{wk}(\ell, \ell_5) \land \mathrm{cr}(\ell_5, \ell) \land \mathrm{cr}(\ell, \ell_5)$$

So a slide's start and end each ask for layout in both engines without the 0.999 rest. -/
theorem st5_flip (l : Look) (ht : l.transform = true) :
    wkFlip st5Rest l = true ∧ wkFlip l st5Rest = true ∧ crFlip st5Rest l = true ∧ crFlip l st5Rest = true := by
  simp [wkFlip, crFlip, crSC, st5Rest, ht]

#guard wkFlip st5Rest (animAt 0 1 1)
#guard !wkFlip st6Rest (animAt 0 (999 / 1000) 1)
#guard !crFlip st6Rest (animAt (999 / 1000) 0 0)
#guard wkFlip ⟨1, true, false⟩ ⟨9 / 10, true, false⟩
#guard !crFlip ⟨1, true, false⟩ ⟨9 / 10, true, false⟩
#guard crFlip ⟨1, false, false⟩ ⟨9 / 10, false, false⟩

/-! ## st6 slide geometry: the followers' shift (ledger n=19)

`avatars-exit` takes the leaver's width (and flex-basis) from 32 px to 0 and its margin from $-8$ to 0 px. The
followers sit after the leaver's margin box, so they shift left by what it gives up. st6 keeps the leaver's box and
moves the followers by a translate of $-24p$ px; in exact arithmetic the shift is the same at every progress $p$ when
both use the same progress. -/

/-- The leaver's margin-box advance at progress $p$: width plus margin.

$$a(p) = \big((1-p)\cdot 32 + p \cdot 0\big) + \big((1-p)\cdot(-8) + p\cdot 0\big)$$ -/
def leaverAdvance (p : Rat) : Rat := ((1 - p) * 32 + p * 0) + ((1 - p) * (-8) + p * 0)

/-- **The followers' shift is the translate.** At every progress the followers have moved left by $24p$ px, the
st6 translate.

$$\forall p \in \mathbb{Q}:\ a(0) - a(p) = 24\,p$$

Exact in arithmetic; pixels still differ (device-pixel snapping against compositor resampling, class L). -/
theorem follower_shift (p : Rat) : leaverAdvance 0 - leaverAdvance p = 24 * p := by
  unfold leaverAdvance
  grind

#guard leaverAdvance 0 == 24
#guard leaverAdvance 1 == 0
#guard leaverAdvance 0 - leaverAdvance (1 / 2) == 12

end Fw.Parts.PeopleCarousel

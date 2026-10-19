import Lean.Data.Json
import Fw.Parts.HiddenPause
import Fw.Parts.HeroExit
/-!
# hero.countdown `hidden-pause`: hold the face writes while the hero clock paints nothing

The hero clock sits in `.copy` (opacity `calc(var(--copy-in) * var(--exit-opacity))`, `opacity: var(--exit-opacity)`
at `width<=600px`; `apps/site/src/parts/hero/hero.module.css`), inside the sticky stage that hero.exit writes
`--exit-opacity` on, inside the 200vh track. The spring keeps integrating; the gate holds the face `transform` writes
while the clock is hidden and writes the latest value per face when it shows again.

Hidden is `exitOpacity = 0` (the zone past $T + n$) or the track more than one viewport away. The pointer-off sentinel
($e < 1/20$) is not a hidden condition: at $e = 1/25$ the copy still paints (`sentinel_not_hidden`).
-/
namespace Fw.Parts.HeroCountdownHidden

open Fw.Engine
open Fw.Parts.HiddenPause (Tmpl inst Hidden HiddenOrStill hiddenPause_visSame inside meets_of_inside cdFrame
  skipWrites unhideFrame cr_countdown_style wk_countdown_style unhide_le)
open Fw.Parts.HeroExit (exitOpacity exitOpacityAt exitRange exitClamp exitFrame pointerOff copyOpacity
  exitRange_pos div_mul_pos exitOpacity_before exitOpacity_after exitOpacity_linear)

/-! ## 1. The exit branch: the clamp reaches exactly 0 -/

/-- **The exit opacity is exactly 0 on one closed zone.**

$$\forall t, h, v \in \mathbb{Q}:\ \operatorname{exitOpacity}(t, h, v) = 0 \iff \max(1, h - v) \le -t$$

The hero is fully transparent exactly once the track top has moved at least the whole exit range above the viewport. -/
theorem exitOpacity_eq_zero_iff (t h v : Rat) : exitOpacity t h v = 0 ↔ exitRange h v ≤ -t := by
  constructor
  · intro h0
    refine Classical.byContradiction fun hlt => ?_
    have hlt' : -t < exitRange h v := by grind
    by_cases ht : 0 ≤ t
    · rw [exitOpacity_before t h v ht] at h0; exact absurd h0 (by decide)
    · have hl := exitOpacity_linear t h v (by grind) (by grind)
      rw [h0] at hl
      grind
  · exact exitOpacity_after t h v

/-- **The zone in scroll terms.** For a track whose top sits at document offset $T$, the exit opacity at scroll $y$
is 0 exactly from $y = T + n$ on, with $n = \max(1, h - v)$ (for the 200vh track, $n = \max(1, v)$).

$$\forall T, h, v, y \in \mathbb{Q}:\ \operatorname{exitOpacityAt}(T, h, v, y) = 0 \iff T + \max(1, h - v) \le y$$

The clock is hidden by the exit from one scroll position on, one exit range below the track top. -/
theorem exitZeroAt_iff (T h v y : Rat) : exitOpacityAt T h v y = 0 ↔ T + exitRange h v ≤ y := by
  unfold exitOpacityAt
  rw [exitOpacity_eq_zero_iff]
  grind

/-- **The frame's written opacity is 0 exactly in the zone, and never under reduced motion.**

$$\forall r \in \mathbb{B},\ \forall t, h, v \in \mathbb{Q}:\ \operatorname{exitFrame}(r, t, h, v).\mathrm{opacity} = 0 \iff r = \bot \land \max(1, h - v) \le -t$$

Reduced motion writes 1, so only the scrolled-out zone without reduced motion writes 0. -/
theorem exitFrame_zero_iff (r : Bool) (t h v : Rat) :
    (exitFrame r t h v).opacity = 0 ↔ r = false ∧ exitRange h v ≤ -t := by
  cases r
  · simp only [exitFrame, Bool.false_eq_true, ↓reduceIte, true_and]
    exact exitOpacity_eq_zero_iff t h v
  · simp only [exitFrame, ↓reduceIte, Bool.true_eq_false, false_and, iff_false]
    decide

/-- **The sentinel does not decide.** There is a track geometry where pointer events are off (the sentinel fires)
while the exit opacity is $1/25 \ne 0$, so the copy still paints.

$$\exists t, h, v \in \mathbb{Q}:\ \operatorname{pointerOff}(\operatorname{exitOpacity}(t, h, v)) = \top \land \operatorname{exitOpacity}(t, h, v) \ne 0$$

Witness $t = -768$, $h = 1600$, $v = 800$: the exit opacity is $1/25$, below the $1/20$ sentinel and above 0. -/
theorem sentinel_not_hidden :
    ∃ t h v : Rat, pointerOff (exitOpacity t h v) = true ∧ exitOpacity t h v ≠ 0 :=
  ⟨-768, 1600, 800, by decide +kernel, by decide +kernel⟩

/-- **Off the top implies the exit zone.** Without reduced motion, a track of height $h \ge 1$ whose bottom is at or
above the viewport top ($t + h \le 0$) and a viewport height $v \ge 0$ give exit opacity 0.

$$\forall t, h, v \in \mathbb{Q}:\ 1 \le h \land 0 \le v \land t + h \le 0 \Rightarrow \operatorname{exitOpacity}(t, h, v) = 0$$

A track scrolled fully above the viewport is already in the exit zone. -/
theorem exitZero_of_above (t h v : Rat) (h1 : 1 ≤ h) (hv : 0 ≤ v) (ht : t + h ≤ 0) : exitOpacity t h v = 0 :=
  (exitOpacity_eq_zero_iff t h v).mpr (by unfold exitRange; grind)

/-! ## 2. The offscreen branch: the track more than one viewport away -/

/-- The viewport grown by its own height above and below (IntersectionObserver `rootMargin: 100% 0px`).

$$\forall \mathit{vp} \in \mathrm{Rect}:\ \operatorname{grow}(\mathit{vp}) = (\mathit{vp}.x,\ \mathit{vp}.y - \mathit{vp}.h,\ \mathit{vp}.w,\ 3\,\mathit{vp}.h)$$

The observer's root: one viewport height of margin on top and bottom. -/
def grow (vp : Rect) : Rect := ⟨vp.x, vp.y - vp.h, vp.w, 3 * vp.h⟩

/-- A rect that meets the viewport meets the grown viewport.

$$\forall \mathit{vp}, R \in \mathrm{Rect}:\ \operatorname{meets}(\mathit{vp}, R) \Rightarrow \operatorname{meets}(\operatorname{grow}(\mathit{vp}), R)$$

The grown root contains the viewport, so anything near enough to paint is reported near. -/
theorem meets_grow (vp R : Rect) (h : vp.meets R = true) : (grow vp).meets R = true := by
  simp only [Rect.meets, grow, Bool.and_eq_true, decide_eq_true_eq] at h ⊢
  grind

/-- **The offscreen decision**: the track does not meet the grown viewport.

$$\forall \mathit{vp}, R \in \mathrm{Rect}:\ \operatorname{farOff}(\mathit{vp}, R) = \lnot\operatorname{meets}(\operatorname{grow}(\mathit{vp}), R)$$

True when the track is more than one viewport height above or below the viewport (or has no area). -/
def farOff (vp R : Rect) : Bool := !(grow vp).meets R

/-! ## 3. The gate decision -/

/-- The stage's effective `--exit-opacity`: the written value, or the CSS default 1 before the first write.

$$\forall x \in \mathbb{Q}_\bot:\ \operatorname{exitVal}(x) = \begin{cases} e & x = e \\ 1 & x = \bot \end{cases}$$

What the copy's opacity multiplies by. -/
def exitVal (ex : Option Rat) : Rat := ex.getD 1

/-- **The gate's hidden decision**: the written exit opacity is exactly 0, or the track is far off.

$$\forall x \in \mathbb{Q}_\bot,\ \forall \mathit{vp}, R \in \mathrm{Rect}:\ \operatorname{gateHidden}(x, \mathit{vp}, R) = \big(x = 0\big) \lor \operatorname{farOff}(\mathit{vp}, R)$$

Hold the face writes while the copy is transparent or the track is more than a viewport away; a missing write never
hides. -/
def gateHidden (ex : Option Rat) (vp R : Rect) : Bool := decide (ex = some 0) || farOff vp R

/-- **The decision, both branches.**

$$\forall x \in \mathbb{Q}_\bot,\ \forall \mathit{vp}, R \in \mathrm{Rect}:\ \operatorname{gateHidden}(x, \mathit{vp}, R) \iff x = 0 \lor \lnot\operatorname{meets}(\operatorname{grow}(\mathit{vp}), R)$$

The gate is closed exactly when one of the two hidden conditions holds. -/
theorem hidden_iff (ex : Option Rat) (vp R : Rect) :
    gateHidden ex vp R = true ↔ ex = some 0 ∨ (grow vp).meets R = false := by
  simp [gateHidden, farOff]

/-- **Exit branch.** With the track near, the gate is closed on the frame's written opacity exactly in the exit zone
without reduced motion.

$$\forall r \in \mathbb{B},\ \forall t, h, v \in \mathbb{Q},\ \forall \mathit{vp}, R \in \mathrm{Rect}:\ \operatorname{meets}(\operatorname{grow}(\mathit{vp}), R) \Rightarrow \Big(\operatorname{gateHidden}(\operatorname{exitFrame}(r, t, h, v).\mathrm{opacity}, \mathit{vp}, R) \iff r = \bot \land \max(1, h - v) \le -t\Big)$$

Near the viewport, only the scrolled-out zone closes the gate. -/
theorem hidden_iff_exit (r : Bool) (t h v : Rat) (vp R : Rect) (hn : (grow vp).meets R = true) :
    gateHidden (some (exitFrame r t h v).opacity) vp R = true ↔ r = false ∧ exitRange h v ≤ -t := by
  rw [hidden_iff, ← exitFrame_zero_iff, hn]
  simp

/-- **Offscreen branch.** With a written opacity that is not 0 (or none written), the gate is closed exactly when the
track does not meet the grown viewport.

$$\forall x \in \mathbb{Q}_\bot,\ \forall \mathit{vp}, R \in \mathrm{Rect}:\ x \ne 0 \Rightarrow \Big(\operatorname{gateHidden}(x, \mathit{vp}, R) \iff \lnot\operatorname{meets}(\operatorname{grow}(\mathit{vp}), R)\Big)$$

While the copy has positive opacity, only distance closes the gate. -/
theorem hidden_iff_far (ex : Option Rat) (vp R : Rect) (hx : ex ≠ some 0) :
    gateHidden ex vp R = true ↔ (grow vp).meets R = false := by
  rw [hidden_iff]
  simp [hx]

#guard gateHidden (some 0) ⟨0, 0, 1280, 800⟩ ⟨0, 0, 1280, 1600⟩
#guard !gateHidden (some (1/25)) ⟨0, 0, 1280, 800⟩ ⟨0, -768, 1280, 1600⟩
#guard !gateHidden none ⟨0, 0, 1280, 800⟩ ⟨0, 0, 1280, 1600⟩
#guard gateHidden (some 1) ⟨0, 0, 1280, 800⟩ ⟨0, -2600, 1280, 1600⟩
#guard !gateHidden (some 1) ⟨0, 0, 1280, 800⟩ ⟨0, -2400, 1280, 1601⟩
#guard gateHidden (some 1) ⟨0, 0, 1280, 800⟩ ⟨0, 1600, 1280, 100⟩

/-! ## 4. The clock's scene is empty while the gate is closed -/

/-- Every box of the clock sits in the copy: its effective opacity is the copy's opacity times a factor.

$$\forall c \in \mathbb{Q},\ \forall x \in \mathbb{Q}_\bot,\ \forall T \in \mathrm{Tmpl}(A):\ \operatorname{ClockUnder}(c, x, T) \iff \forall (i, f) \in T\ \exists k : A \to \mathbb{Q}\ \forall a \in A:\ f(a).\mathrm{alpha} = \operatorname{copyOpacity}(c, \operatorname{exitVal}(x)) \cdot k(a)$$

Each clock box carries the copy's opacity as a factor. -/
def ClockUnder {A : Type} (copyIn : Rat) (ex : Option Rat) (tm : Tmpl A) : Prop :=
  ∀ e ∈ tm, ∃ k : A → Rat, ∀ a, (e.2 a).alpha = copyOpacity copyIn (exitVal ex) * k a

/-- Every box of the clock keeps its transformed ink inside the track rect, for every face value.

$$\forall R \in \mathrm{Rect},\ \forall T \in \mathrm{Tmpl}(A):\ \operatorname{ClockIn}(R, T) \iff \forall (i, f) \in T\ \forall a \in A:\ \operatorname{inside}(\operatorname{bbox}(f(a).\mathrm{xf}, f(a).\mathrm{ink}), R)$$

The clock never leaves the track. -/
def ClockIn {A : Type} (R : Rect) (tm : Tmpl A) : Prop :=
  ∀ e ∈ tm, ∀ a, inside ((e.2 a).xf.bbox (e.2 a).ink) R

private theorem visible_nil {A : Type} (vp : Rect) (a : A) :
    ∀ tm : Tmpl A, (∀ e ∈ tm, Hidden vp e.2) → visible vp (inst tm a) = []
  | [], _ => rfl
  | e :: tm, h => by
    have ih := visible_nil vp a tm (fun x hx => h x (List.mem_cons_of_mem _ hx))
    simp only [visible, inst, List.map_cons, List.filter_cons] at ih ⊢
    simp [h e List.mem_cons_self a, ih]

/-- **Exit branch, scene.** With the written exit opacity 0, every clock box is dropped in every viewport.

$$\forall c \in \mathbb{Q},\ \forall T \in \mathrm{Tmpl}(A),\ \forall \mathit{vp} \in \mathrm{Rect},\ \forall a \in A:\ \operatorname{ClockUnder}(c, 0, T) \Rightarrow \operatorname{visible}_{\mathit{vp}}(\operatorname{inst}(T, a)) = [\,]$$

A transparent copy shows no clock, whatever the faces hold. -/
theorem scene_empty_of_exit {A : Type} (copyIn : Rat) (tm : Tmpl A) (vp : Rect) (a : A)
    (hU : ClockUnder copyIn (some 0) tm) : visible vp (inst tm a) = [] := by
  refine visible_nil vp a tm fun e he b => ?_
  obtain ⟨k, hk⟩ := hU e he
  have : (e.2 b).alpha ≤ 0 := by
    rw [hk b]; simp [copyOpacity, exitVal]
  simp [BoxVis.drop, this]

/-- **Offscreen branch, scene.** With the clock inside a track that does not meet the grown viewport, every clock box
is dropped.

$$\forall R \in \mathrm{Rect},\ \forall T \in \mathrm{Tmpl}(A),\ \forall \mathit{vp} \in \mathrm{Rect},\ \forall a \in A:\ \operatorname{ClockIn}(R, T) \land \lnot\operatorname{meets}(\operatorname{grow}(\mathit{vp}), R) \Rightarrow \operatorname{visible}_{\mathit{vp}}(\operatorname{inst}(T, a)) = [\,]$$

A clock in a far track shows nothing, whatever the faces hold. -/
theorem scene_empty_of_far {A : Type} (R : Rect) (tm : Tmpl A) (vp : Rect) (a : A) (hIn : ClockIn R tm)
    (hR : (grow vp).meets R = false) : visible vp (inst tm a) = [] := by
  refine visible_nil vp a tm fun e he b => ?_
  have hm : vp.meets R = false := by
    cases h : vp.meets R
    · rfl
    · rw [meets_grow vp R h] at hR; exact absurd hR (by decide)
  have hb : vp.meets ((e.2 b).xf.bbox (e.2 b).ink) = false := by
    cases h : vp.meets ((e.2 b).xf.bbox (e.2 b).ink)
    · rfl
    · rw [meets_of_inside vp _ R h (hIn e he b)] at hm; exact absurd hm (by decide)
  simp [BoxVis.drop, hb]

/-- **Closed gate, empty scene.** Whenever the decision holds, the clock's visible scene is empty.

$$\forall c \in \mathbb{Q},\ \forall x \in \mathbb{Q}_\bot,\ \forall \mathit{vp}, R \in \mathrm{Rect},\ \forall T \in \mathrm{Tmpl}(A):\ \operatorname{gateHidden}(x, \mathit{vp}, R) \land \operatorname{ClockUnder}(c, x, T) \land \operatorname{ClockIn}(R, T) \Rightarrow \operatorname{HiddenOrStill}_{\mathit{vp}}(T) \land \forall a \in A:\ \operatorname{visible}_{\mathit{vp}}(\operatorname{inst}(T, a)) = [\,]$$

Every clock box is dropped for every face value while the gate is closed. -/
theorem hidden_scene_empty {A : Type} (copyIn : Rat) (ex : Option Rat) (vp R : Rect) (tm : Tmpl A)
    (hg : gateHidden ex vp R = true) (hU : ClockUnder copyIn ex tm) (hIn : ClockIn R tm) :
    HiddenOrStill vp tm ∧ ∀ a, visible vp (inst tm a) = [] := by
  rcases (hidden_iff ex vp R).mp hg with hx | hf
  · subst hx
    refine ⟨fun e he => Or.inr fun b => ?_, fun a => scene_empty_of_exit copyIn tm vp a hU⟩
    obtain ⟨k, hk⟩ := hU e he
    have : (e.2 b).alpha ≤ 0 := by
      rw [hk b]; simp [copyOpacity, exitVal]
    simp [BoxVis.drop, this]
  · refine ⟨fun e he => Or.inr fun b => ?_, fun a => scene_empty_of_far R tm vp a hIn hf⟩
    have h1 := scene_empty_of_far R [e] vp b (fun x hx => by simp at hx; rw [hx]; exact hIn e he) hf
    simp only [visible, inst, List.map_cons, List.map_nil, List.filter_cons, List.filter_nil] at h1
    cases hd : (e.2 b).drop vp
    · simp [hd] at h1
    · rfl

/-! ## 5. The write gate (`createWriteGate`) -/

/-- One event the clock's faces see: a face write, or a gate signal.

$$\mathrm{Ev}(K, V) = \operatorname{write}(k, v) \mid \operatorname{hide}(b),\quad k \in K,\ v \in V,\ b \in \mathbb{B}$$ -/
inductive Ev (K V : Type) where
  | write (k : K) (v : V)
  | hide (b : Bool)

/-- The write gate's state: whether it is closed, the held latest value per face, and the faces as shown.

$$\mathrm{Gate}(K, V) = \mathbb{B} \times (K \to V_\bot) \times (K \to V)$$ -/
structure Gate (K V : Type) where
  hidden : Bool
  pend : K → Option V
  shown : K → V

variable {K V : Type} [DecidableEq K]

/-- Point update of a face map.

$$\forall f : K \to V,\ \forall k \in K,\ \forall v \in V:\ \operatorname{upd}(f, k, v)(j) = \begin{cases} v & j = k \\ f(j) & j \ne k \end{cases}$$ -/
def upd (f : K → V) (k : K) (v : V) : K → V := fun j => if j = k then v else f j

/-- The faithful clock: every write lands, signals do nothing.

$$\forall D : K \to V:\ \operatorname{fStep}(D, \operatorname{write}(k, v)) = \operatorname{upd}(D, k, v),\quad \operatorname{fStep}(D, \operatorname{hide}(b)) = D$$ -/
def fStep (D : K → V) : Ev K V → (K → V)
  | .write k v => upd D k v
  | .hide _ => D

/-- **The gate step** (`createWriteGate`, `apps/site/src/parts/engine.scene/logic.ts`): an open gate writes through, a
closed one holds the latest value per face; a signal equal to the state does nothing; closing only sets the flag;
opening writes every held value and clears them.

$$\operatorname{gStep}(g, \operatorname{write}(k, v)) = \begin{cases} g[\mathrm{pend} := \operatorname{upd}(g.\mathrm{pend}, k, v)] & g.\mathrm{hidden} \\ g[\mathrm{shown} := \operatorname{upd}(g.\mathrm{shown}, k, v)] & \lnot g.\mathrm{hidden} \end{cases}$$
$$\operatorname{gStep}(g, \operatorname{hide}(b)) = \begin{cases} g & b = g.\mathrm{hidden} \\ g[\mathrm{hidden} := \top] & b \ne g.\mathrm{hidden} \land b \\ (\bot,\ k \mapsto \bot,\ k \mapsto g.\mathrm{pend}(k) \mathbin{?\!?} g.\mathrm{shown}(k)) & b \ne g.\mathrm{hidden} \land \lnot b \end{cases}$$

Writes pass while open; on opening, every held face gets its latest value. -/
def gStep (g : Gate K V) : Ev K V → Gate K V
  | .write k v => if g.hidden then { g with pend := upd g.pend k (some v) } else { g with shown := upd g.shown k v }
  | .hide b =>
    if b = g.hidden then g
    else if b then { g with hidden := true }
    else ⟨false, fun _ => none, fun j => (g.pend j).getD (g.shown j)⟩

/-- The open gate with nothing held, showing $D$.

$$\forall D : K \to V:\ \operatorname{gInit}(D) = (\bot,\ k \mapsto \bot,\ D)$$ -/
def gInit (D : K → V) : Gate K V := ⟨false, fun _ => none, D⟩

/-- The gate's invariant against the faithful faces $D$: open, it shows $D$ and holds nothing; closed, each face's held
value (or, if none, its shown value) is $D$'s.

$$\forall g,\ \forall D:\ \operatorname{Inv}(g, D) \iff \begin{cases} \forall k:\ g.\mathrm{pend}(k) \mathbin{?\!?} g.\mathrm{shown}(k) = D(k) & g.\mathrm{hidden} \\ g.\mathrm{shown} = D \land \forall k:\ g.\mathrm{pend}(k) = \bot & \lnot g.\mathrm{hidden} \end{cases}$$ -/
def Inv (g : Gate K V) (D : K → V) : Prop :=
  if g.hidden then ∀ k, (g.pend k).getD (g.shown k) = D k else g.shown = D ∧ ∀ k, g.pend k = none

/-- **The first open frame rewrites every face to the faithful value.** Opening a closed gate whose invariant holds
shows exactly the faithful faces.

$$\forall g,\ \forall D:\ g.\mathrm{hidden} \land \operatorname{Inv}(g, D) \Rightarrow \operatorname{gStep}(g, \operatorname{hide}(\bot)).\mathrm{shown} = D \land \lnot\operatorname{gStep}(g, \operatorname{hide}(\bot)).\mathrm{hidden}$$

On unhide, the held latest values make the clock equal to the original's. -/
theorem first_visible_rewrites (g : Gate K V) (D : K → V) (hh : g.hidden = true) (hi : Inv g D) :
    (gStep g (.hide false)).shown = D ∧ (gStep g (.hide false)).hidden = false := by
  simp only [Inv, hh, ↓reduceIte] at hi
  simp only [gStep, hh, Bool.false_eq_true, ↓reduceIte]
  exact ⟨funext hi, trivial⟩

/-- **A closed gate shows nothing new.** A write while closed leaves the shown faces unchanged (the skipped DOM write).

$$\forall g,\ \forall k, v:\ g.\mathrm{hidden} \Rightarrow \operatorname{gStep}(g, \operatorname{write}(k, v)).\mathrm{shown} = g.\mathrm{shown}$$

Held writes never reach the DOM. -/
theorem closed_write_skipped (g : Gate K V) (k : K) (v : V) (hh : g.hidden = true) :
    (gStep g (.write k v)).shown = g.shown := by
  simp [gStep, hh]

/-- One step keeps the invariant.

$$\forall g, D, \epsilon:\ \operatorname{Inv}(g, D) \Rightarrow \operatorname{Inv}(\operatorname{gStep}(g, \epsilon), \operatorname{fStep}(D, \epsilon))$$ -/
theorem inv_step (g : Gate K V) (D : K → V) (ev : Ev K V) (hi : Inv g D) : Inv (gStep g ev) (fStep D ev) := by
  cases ev with
  | write k v =>
    cases hh : g.hidden
    · simp only [Inv, hh, Bool.false_eq_true, ↓reduceIte] at hi
      simp only [Inv, gStep, fStep, hh, Bool.false_eq_true, ↓reduceIte]
      exact ⟨by rw [hi.1], hi.2⟩
    · simp only [Inv, hh, ↓reduceIte] at hi
      simp only [Inv, gStep, fStep, hh, ↓reduceIte]
      intro j
      by_cases hj : j = k
      · simp [upd, hj]
      · simp [upd, hj, hi j]
  | hide b =>
    cases hh : g.hidden <;> cases b
    · simpa [gStep, fStep, hh] using hi
    · simp only [Inv, hh, Bool.false_eq_true, ↓reduceIte] at hi
      simp only [Inv, gStep, fStep, hh, ↓reduceIte, Bool.true_eq_false]
      intro j; simp [hi.2 j, hi.1]
    · have := first_visible_rewrites g D hh hi
      simp only [Inv, fStep, this.2, Bool.false_eq_true, ↓reduceIte]
      exact ⟨this.1, fun _ => by simp [gStep, hh]⟩
    · simpa [gStep, fStep, hh] using hi

/-- Replaying events from a state keeps the invariant.

$$\forall g, D,\ \forall \epsilon_1 \dots \epsilon_n:\ \operatorname{Inv}(g, D) \Rightarrow \operatorname{Inv}(\operatorname{foldl}(\operatorname{gStep}, g, [\epsilon_i]), \operatorname{foldl}(\operatorname{fStep}, D, [\epsilon_i]))$$ -/
theorem inv_run : ∀ (evs : List (Ev K V)) (g : Gate K V) (D : K → V), Inv g D →
    Inv (evs.foldl gStep g) (evs.foldl fStep D)
  | [], _, _, hi => hi
  | ev :: evs, g, D, hi => inv_run evs _ _ (inv_step g D ev hi)

/-- **Open gate, faithful faces.** After any event list from the open initial gate, whenever the gate is open the
shown faces equal the faithful faces.

$$\forall D_0,\ \forall \epsilon_1 \dots \epsilon_n:\ \lnot\operatorname{foldl}(\operatorname{gStep}, \operatorname{gInit}(D_0), [\epsilon_i]).\mathrm{hidden} \Rightarrow \operatorname{foldl}(\operatorname{gStep}, \operatorname{gInit}(D_0), [\epsilon_i]).\mathrm{shown} = \operatorname{foldl}(\operatorname{fStep}, D_0, [\epsilon_i])$$

Whenever the clock is shown, it shows the original's faces. -/
theorem gate_sync (D0 : K → V) (evs : List (Ev K V)) (ho : (evs.foldl gStep (gInit D0)).hidden = false) :
    (evs.foldl gStep (gInit D0)).shown = evs.foldl fStep D0 := by
  have hi := inv_run evs (gInit D0) D0 (by simp [Inv, gInit])
  simp only [Inv, ho, Bool.false_eq_true, ↓reduceIte] at hi
  exact hi.1

#guard ((([.hide true, .write 1 7, .write 1 8, .hide false] : List (Ev Nat Nat)).foldl gStep (gInit fun _ => 0)).shown 1) == 8
#guard ((([.hide true, .write 1 7] : List (Ev Nat Nat)).foldl gStep (gInit fun _ => 0)).shown 1) == 0
#guard ((([.write 2 5, .hide false] : List (Ev Nat Nat)).foldl gStep (gInit fun _ => 0)).shown 2) == 5

/-! ## 6. Vision: the variant's clock looks like the original's at every instant -/

/-- **visSame (class E).** For every environment and paint instant $t$ with events $\epsilon(\mathit{env}, t)$ so
far: if each clock box sits in the copy at the written exit value and inside the track, and the gate is closed at a
paint only when the decision holds there, the variant's clock (shown faces) and the original's (all writes landed)
give the same visible scene.

$$\forall \mathit{vp} : \mathrm{Env} \to \mathrm{Rect},\ \forall T : \mathrm{Env} \to \mathcal{T} \to \mathrm{Tmpl}(K \to V),\ \forall D_0,\ \forall \epsilon : \mathrm{Env} \to \mathcal{T} \to \mathrm{Ev}(K, V)^{*},\ \forall c : \mathrm{Env} \to \mathcal{T} \to \mathbb{Q},\ \forall x : \mathrm{Env} \to \mathcal{T} \to \mathbb{Q}_\bot,\ \forall R : \mathrm{Env} \to \mathcal{T} \to \mathrm{Rect}:$$
$$\Big(\forall \mathit{env}, t:\ \operatorname{ClockUnder}(c, x, T)(\mathit{env}, t)\Big) \land \Big(\forall \mathit{env}, t:\ \operatorname{ClockIn}(R, T)(\mathit{env}, t)\Big) \land \Big(\forall \mathit{env}, t:\ G(\mathit{env}, t).\mathrm{hidden} \Rightarrow \operatorname{gateHidden}(x(\mathit{env}, t), \mathit{vp}(\mathit{env}), R(\mathit{env}, t))\Big)$$
$$\Rightarrow \operatorname{VisSame}_{\mathrm{E}}\big(\mathit{vp},\ (\mathit{env}, t) \mapsto \operatorname{inst}(T, \operatorname{foldl}(\operatorname{fStep}, D_0, \epsilon(\mathit{env}, t))),\ (\mathit{env}, t) \mapsto \operatorname{inst}(T, G(\mathit{env}, t).\mathrm{shown})\big)$$
$$\text{where } G(\mathit{env}, t) = \operatorname{foldl}(\operatorname{gStep}, \operatorname{gInit}(D_0), \epsilon(\mathit{env}, t))$$

Holding the face writes only while the copy is transparent or the track is far gives the original's picture at every
width and every instant. -/
theorem visSame {Env T : Type} (vp : Env → Rect) (tm : Env → T → Tmpl (K → V)) (D0 : K → V)
    (evs : Env → T → List (Ev K V)) (copyIn : Env → T → Rat) (ex : Env → T → Option Rat) (R : Env → T → Rect)
    (hU : ∀ env t, ClockUnder (copyIn env t) (ex env t) (tm env t)) (hIn : ∀ env t, ClockIn (R env t) (tm env t))
    (hSig : ∀ env t, ((evs env t).foldl gStep (gInit D0)).hidden = true → gateHidden (ex env t) (vp env) (R env t) = true) :
    VisSame E vp (fun env t => inst (tm env t) ((evs env t).foldl fStep D0))
      (fun env t => inst (tm env t) ((evs env t).foldl gStep (gInit D0)).shown) :=
  hiddenPause_visSame vp tm (fun env t => (evs env t).foldl fStep D0)
    (fun env t => ((evs env t).foldl gStep (gInit D0)).shown)
    (fun env t => ((evs env t).foldl gStep (gInit D0)).hidden = true)
    (fun env t h => (hidden_scene_empty (copyIn env t) (ex env t) (vp env) (R env t) (tm env t) (hSig env t h)
      (hU env t) (hIn env t)).1)
    (fun env t h => gate_sync D0 (evs env t) (by simpa using h))

/-! ## 7. Work: a closed frame drops the style pass, the reopening frame is `≤` -/

open Fw.Engine.Chromium Fw.Engine.WebKit in
/-- **Work, both engines.** For $d > 0$ springing digits in any layer state: a closed frame (callbacks kept, face writes
held) is strictly below the original's frame in the Chromium lane and in WebKit, and the reopening frame (any subset
of the face writes) costs at most the original's frame in every engine.

$$\forall d \in \mathbb{N},\ \forall l:\ 0 < d \Rightarrow W^{\mathrm{cr}}(\operatorname{skipWrites}(\operatorname{cdFrame}(\mathrm{css}(\mathrm{transform}), d, l))) \prec W^{\mathrm{cr}}(\operatorname{cdFrame}(\mathrm{css}(\mathrm{transform}), d, l)) \land W^{\mathrm{wk}}(\operatorname{skipWrites}(\operatorname{cdFrame}(\mathrm{transform}, d, l))) \prec W^{\mathrm{wk}}(\operatorname{cdFrame}(\mathrm{transform}, d, l))$$
$$\forall E,\ \forall p, d, l,\ \forall q:\ W^{E}(\operatorname{unhide}(p, d, l, q)) \preceq W^{E}(\operatorname{cdFrame}(p, d, l))$$

The hidden clock saves the style pass per springing frame in both engines and its re-sync never costs more than an
original frame (`cr_countdown_style`, `wk_countdown_style`, `unhide_le`). -/
theorem hidden_work (d : Nat) (l : LayerState) (hd : 0 < d) :
    (frameWork chromium (skipWrites (cdFrame (.css .transform) d l))).lt
        (frameWork chromium (cdFrame (.css .transform) d l)) ∧
      (frameWork webkit (skipWrites (cdFrame WkProp.transform d l))).lt
        (frameWork webkit (cdFrame WkProp.transform d l)) ∧
      ∀ {P M : Type} (E : Engine P M) (p : P) (keep : Change P → Bool),
        (frameWork E (unhideFrame p d l keep)).le (frameWork E (cdFrame p d l)) :=
  ⟨(cr_countdown_style d l hd).2.2, (wk_countdown_style d l hd).2.2, fun E p keep => unhide_le E p d l keep⟩

/-! ## 8. Golden rows: gate open or closed per zone -/

/-- One zone: name, reduced motion, track top, track height and viewport height (viewport $(0, 0, 1280, v)$, track
$(0, t, 1280, h)$), and whether hero.exit has written yet.

$$\mathrm{Zone} = \mathrm{String} \times \mathbb{B} \times \mathbb{Q} \times \mathbb{Q} \times \mathbb{Q} \times \mathbb{B}$$ -/
abbrev Zone := String × Bool × Rat × Rat × Rat × Bool

/-- The zones the golden covers ($v = 800$; the 200vh track has $h = 1600$; under reduced motion the track is `auto`
and $h = 900$ stands for its content height).

$$\mathrm{zones} = [\texttt{unwritten}, \texttt{below-top}, \texttt{rest}, \texttt{fade}, \texttt{pointer-off}, \texttt{edge}, \texttt{past}, \texttt{far-above}, \texttt{reduced-past}, \texttt{reduced-near}, \texttt{reduced-far}, \texttt{far-below}, \texttt{short-track}],\quad |\mathrm{zones}| = 13$$ -/
def zones : List Zone :=
  [("unwritten", false, 0, 1600, 800, false), ("below-top", false, 100, 1600, 800, true),
   ("rest", false, 0, 1600, 800, true), ("fade", false, -400, 1600, 800, true),
   ("pointer-off", false, -768, 1600, 800, true), ("edge", false, -800, 1600, 800, true),
   ("past", false, -1200, 1600, 800, true), ("far-above", false, -2600, 1600, 800, true),
   ("reduced-past", true, -1200, 900, 800, true), ("reduced-near", true, -1600, 900, 800, true),
   ("reduced-far", true, -1800, 900, 800, true), ("far-below", false, 1600, 1600, 800, true),
   ("short-track", false, -1, 100, 800, true)]

/-- The written exit value of a zone: hero.exit's frame opacity, or none before its first write.

$$\operatorname{written}(n, r, t, h, v, w) = \begin{cases} \operatorname{exitFrame}(r, t, h, v).\mathrm{opacity} & w \\ \bot & \lnot w \end{cases}$$ -/
def written (z : Zone) : Option Rat :=
  let (_, r, t, h, v, w) := z
  if w then some (exitFrame r t h v).opacity else none

/-- The decision of a zone.

$$\operatorname{zoneHidden}(z) = \operatorname{gateHidden}(\operatorname{written}(z), (0, 0, 1280, v), (0, t, 1280, h))$$ -/
def zoneHidden (z : Zone) : Bool :=
  let (_, _, t, h, v, _) := z
  gateHidden (written z) ⟨0, 0, 1280, v⟩ ⟨0, t, 1280, h⟩

/-- A rational as the wire object `{"num", "den"}`.

$$\forall q \in \mathbb{Q}:\ \operatorname{ratWire}(q) = \{\texttt{num}: q.\mathrm{num},\ \texttt{den}: q.\mathrm{den}\}$$ -/
def ratWire (q : Rat) : Lean.Json := Lean.Json.mkObj [("num", toString q.num), ("den", toString q.den)]

/-- One golden row: the zone's inputs, the written exit value (`null` if none), the sentinel, the far flag and the
decision.

$$\operatorname{row}(z) = \{\mathrm{zone}, \mathrm{reduced}, \mathrm{trackTop}, \mathrm{trackHeight}, \mathrm{vh}, \mathrm{exit}: \operatorname{written}(z), \mathrm{pointerOff}: \operatorname{pointerOff}(\operatorname{exitVal}(\operatorname{written}(z))), \mathrm{far}: \operatorname{farOff}, \mathrm{hidden}: \operatorname{zoneHidden}(z)\}$$ -/
def row (z : Zone) : Lean.Json :=
  let (n, r, t, h, v, _) := z
  Lean.Json.mkObj
    [("zone", n), ("reduced", r), ("trackTop", ratWire t), ("trackHeight", ratWire h), ("vh", ratWire v),
     ("exit", match written z with | some e => ratWire e | none => Lean.Json.null),
     ("pointerOff", pointerOff (exitVal (written z))), ("far", farOff ⟨0, 0, 1280, v⟩ ⟨0, t, 1280, h⟩),
     ("hidden", zoneHidden z)]

/-- The contents of `packages/contracts/golden/parts/hero.countdown.hidden.jsonl`: one compact row per zone.

$$\mathrm{goldenText} = \mathop{\Vert}_{z \in \mathrm{zones}} \big(\operatorname{json}(\operatorname{row}(z)) \mathbin{+\!\!+} \texttt{\textbackslash n}\big)$$ -/
def goldenText : String := String.join (zones.map fun z => (row z).compress ++ "\n")

#guard (zones.map zoneHidden) ==
  [false, false, false, false, false, true, true, true, false, false, true, true, true]
#guard (zones.map fun z => pointerOff (exitVal (written z))) ==
  [false, false, false, false, true, true, true, true, false, false, false, false, true]

/-- Print the golden, or with `--check <file>` compare it byte for byte (exit 1 on a difference).

$$\forall f:\ \operatorname{run}(\texttt{--check}\ f) = 0 \iff \operatorname{bytes}(f) = \mathrm{goldenText}$$ -/
def run (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    let cur ← IO.FS.readFile path
    if cur == goldenText then
      IO.eprintln s!"countdown hidden golden: {path} is up to date ({zones.length} lines)"
      return 0
    IO.eprintln s!"countdown hidden golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print goldenText
    return 0

end Fw.Parts.HeroCountdownHidden

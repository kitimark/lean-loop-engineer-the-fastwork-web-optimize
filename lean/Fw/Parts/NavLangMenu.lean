import Fw.Parts.Nav
/-!
# nav.langMenu: the language switch menu (M2 port, `faithful`)

Restated (not copied) from the original snapshot, read independently of the TS part:

* `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`
  * 12750-12790: state `d` in `closed | open | closing`; `h = (d = open)`, `g = (d ≠ closed)`; `y` sets `closing` and
    (re)arms a 140 ms timer to `closed`; `x` clears the timer and sets `open`; `S` closes only when `open`; `C` toggles
    on `h`; `w(lang)`: a different language is chosen (an analytics event and the locale change), then `S`;
  * 12771-12776: `onOpenChange(g)` after every state change (the nav's `is-locale-open`);
  * 12777-12790: while `open`, a `mousedown` outside the wrapper or `Escape` calls `y`; the listeners are removed
    otherwise;
  * 12803-12842: the menu is rendered while `g`; the wrapper has class `is-open` iff `g`; the menu has `is-open` iff
    `h` and `is-closing` iff `d = closing`; the options are links `/`, `/th/`, `/id/` (plain click is intercepted).
* `assets/2.gBuqKVzi.css` 11106-11295: the switch (48 px, 36 px at `width<=640px`), the menu (opacity 0 and
  `translateY(-6px) scale(0.96)` at rest, in 0.18 s `cubic-bezier(0.22, 1, 0.36, 1)`, out 0.14 s
  `cubic-bezier(0.4, 0, 0.2, 1)`, keyframes 11209-11228, none under reduced motion), the chevron turning 180 degrees.

All values `Rat`. No `Float`.
-/
namespace Fw.Parts.NavLangMenu
open Fw.Parts.Nav

/-! ## The state machine -/

/-- The menu phase (JS 12750 `d`). $$p \in \{\mathrm{closed}, \mathrm{open}, \mathrm{closing}\}$$ -/
inductive Phase
  | closed
  | open_
  | closing
deriving Repr, BEq, DecidableEq

/-- Events the menu reacts to (JS 12757-12776, 12777-12790).

$$\mathrm{toggle}$$ the switch click (`C`); $$\mathrm{select}$$ an option click (`S` after the locale change);
$$\mathrm{outside}$$ a mousedown outside the wrapper or `Escape`, delivered only while the document listeners are
attached, i.e. while open; $$\mathrm{timer}$$ the 140 ms close timer. -/
inductive Ev
  | toggle
  | select
  | outside
  | timer
deriving Repr, BEq, DecidableEq

/-- What a step does to the close timer (JS 12752, 12758-12764). $$\{\mathrm{keep}, \mathrm{clear}, \mathrm{rearm}\}$$ -/
inductive Timer
  | keep
  | clear
  | rearm
deriving Repr, BEq, DecidableEq

/-- The result of a step. $$(p', \tau)$$ The new phase and the timer action. -/
structure Out where
  phase : Phase
  timer : Timer
deriving Repr, BEq, DecidableEq

/-- Close (`y`, JS 12757-12763). $$p' = \mathrm{closing},\ \tau = \mathrm{rearm}$$ Start the 140 ms exit. -/
def close : Out := ⟨.closing, .rearm⟩

/-- Open (`x`, JS 12764-12767). $$p' = \mathrm{open},\ \tau = \mathrm{clear}$$ Cancel a pending exit and show. -/
def openIt : Out := ⟨.open_, .clear⟩

/-- One step of the machine.

$$\begin{aligned}
\operatorname{step}(p, \mathrm{toggle}) &= \begin{cases} \mathrm{close} & p = \mathrm{open}\\ \mathrm{open} & \text{otherwise}\end{cases}\\
\operatorname{step}(p, \mathrm{select}) = \operatorname{step}(p, \mathrm{outside}) &= \begin{cases} \mathrm{close} & p = \mathrm{open}\\ (p, \mathrm{keep}) & \text{otherwise}\end{cases}\\
\operatorname{step}(p, \mathrm{timer}) &= \begin{cases} (\mathrm{closed}, \mathrm{keep}) & p = \mathrm{closing}\\ (p, \mathrm{keep}) & \text{otherwise}\end{cases}
\end{aligned}$$

Toggling while closing re-opens. -/
def step (p : Phase) : Ev → Out
  | .toggle => if p == .open_ then close else openIt
  | .select => if p == .open_ then close else ⟨p, .keep⟩
  | .outside => if p == .open_ then close else ⟨p, .keep⟩
  | .timer => if p == .closing then ⟨.closed, .keep⟩ else ⟨p, .keep⟩

/-- The menu has the `is-open` class (JS 12754). $$h = [p = \mathrm{open}]$$ -/
def isOpen (p : Phase) : Bool := p == .open_

/-- The menu is rendered and the wrapper has `is-open` (JS 12755). $$g = [p \ne \mathrm{closed}]$$ -/
def mounted (p : Phase) : Bool := p != .closed

/-- The menu has the `is-closing` class (JS 12834). $$[p = \mathrm{closing}]$$ -/
def isClosing (p : Phase) : Bool := p == .closing

/-- Document listeners (mousedown, keydown) are attached (JS 12777). $$[p = \mathrm{open}]$$ -/
def listening (p : Phase) : Bool := p == .open_

/-- The nav's `is-locale-open`, set from `onOpenChange` (JS 12771). $$\mathit{locale} = g$$ -/
def navLocaleOpen (p : Phase) : Bool := mounted p

#guard (step .closed .toggle).phase == .open_
#guard (step .open_ .toggle).phase == .closing
#guard (step .closing .toggle).phase == .open_
#guard (step .closing .timer).phase == .closed
#guard (step .open_ .timer).phase == .open_
#guard (step .closed .outside).phase == .closed

/-- Toggling the switch.

$$\operatorname{step}(\mathrm{closed}, \mathrm{toggle}) = \mathrm{open},\quad \operatorname{step}(\mathrm{open}, \mathrm{toggle}) = \mathrm{closing},\quad \operatorname{step}(\mathrm{closing}, \mathrm{toggle}) = \mathrm{open}$$ -/
theorem toggle_cycle :
    (step .closed .toggle).phase = .open_ ∧ (step .open_ .toggle).phase = .closing ∧
      (step .closing .toggle).phase = .open_ := by
  refine ⟨by decide, by decide, by decide⟩

/-- Closed is only reached through the timer.

$$\operatorname{step}(p, e).\mathrm{phase} = \mathrm{closed} \Rightarrow p = \mathrm{closed} \lor (p = \mathrm{closing} \land e = \mathrm{timer})$$

The exit animation always runs: nothing hides the menu in one step. -/
theorem closed_only_by_timer (p : Phase) (e : Ev) (h : (step p e).phase = .closed) :
    p = .closed ∨ (p = .closing ∧ e = .timer) := by
  cases p <;> cases e <;> revert h <;> decide

/-- A closing menu is still mounted.

$$p = \mathrm{closing} \Rightarrow g = \top \land h = \bot$$

The leave animation has an element to play on. -/
theorem closing_mounted (p : Phase) (h : p = .closing) : mounted p = true ∧ isOpen p = false := by
  subst h; decide

/-- Open implies mounted and listening.

$$h \Rightarrow g \land \text{listening}$$ -/
theorem open_mounted (p : Phase) (h : isOpen p = true) : mounted p = true ∧ listening p = true := by
  cases p <;> revert h <;> decide

/-- Any open menu ends closed after an outside click and the timer.

$$\operatorname{step}(\operatorname{step}(\mathrm{open}, \mathrm{outside}).\mathrm{phase}, \mathrm{timer}).\mathrm{phase} = \mathrm{closed}$$ -/
theorem outside_then_timer : (step (step .open_ .outside).phase .timer).phase = .closed := by decide

/-- Select and outside do nothing to a menu that is not open (the listeners are detached, the options absent).

$$p \ne \mathrm{open} \Rightarrow \operatorname{step}(p, \mathrm{select}) = (p, \mathrm{keep})$$ -/
theorem select_idle (p : Phase) (h : p ≠ .open_) : step p .select = ⟨p, .keep⟩ := by
  cases p <;> first | exact absurd rfl h | decide

/-- Every step that leaves the phase open clears the timer; every step into closing re-arms it.

$$\operatorname{phase}' = \mathrm{open} \Rightarrow \tau \in \{\mathrm{clear}, \mathrm{keep}\},\quad \operatorname{phase}' = \mathrm{closing} \land p = \mathrm{open} \Rightarrow \tau = \mathrm{rearm}$$ -/
theorem timer_discipline (p : Phase) (e : Ev) :
    ((step p e).phase = .open_ → (step p e).timer = .clear ∨ (step p e).timer = .keep) ∧
      (p = .open_ → (step p e).phase = .closing → (step p e).timer = .rearm) := by
  cases p <;> cases e <;> decide

/-! ## Timing and keyframes -/

/-- Close timer in ms (JS 12763). $$140$$ -/
def closeMs : Nat := 140

/-- Open animation in ms (CSS 11204). $$180$$ -/
def inMs : Nat := 180

/-- Close animation in ms (CSS 11207). $$140$$ (equal to the timer, so the unmount follows the last frame). -/
def outMs : Nat := 140

/-- The open animation's curve, `cubic-bezier(0.22, 1, 0.36, 1)` (CSS 11182). $$(x_1, y_1, x_2, y_2) = (0.22, 1, 0.36, 1)$$ -/
def easeIn : Bezier := ⟨11 / 50, 1, 9 / 25, 1⟩

/-- The close animation's curve, `cubic-bezier(0.4, 0, 0.2, 1)` (CSS 11207). $$(x_1, y_1, x_2, y_2) = (0.4, 0, 0.2, 1)$$ -/
def easeOutCurve : Bezier := easeStd

/-- A menu pose. $$(\text{opacity},\ \text{translateY px},\ \text{scale})$$ -/
structure Pose where
  opacity : Rat
  y : Rat
  scale : Rat
deriving Repr, BEq, DecidableEq

/-- The pose in the open animation at eased progress $e$ (CSS 11209-11218).

$$\operatorname{in}(e) = (e,\ -6(1 - e),\ 0.96 + 0.04\,e)$$ -/
def poseIn (e : Rat) : Pose := ⟨e, -6 * (1 - e), 24 / 25 + e / 25⟩

/-- The pose in the close animation at eased progress $e$ (CSS 11219-11228).

$$\operatorname{out}(e) = (1 - e,\ -4e,\ 1 - 0.02\,e)$$ -/
def poseOut (e : Rat) : Pose := ⟨1 - e, -4 * e, 1 - e / 50⟩

/-- The rest pose of the menu (CSS 11190-11195). $$(0,\ -6,\ 0.96)$$ Equal to the start of the open animation. -/
def poseRest : Pose := ⟨0, -6, 24 / 25⟩

/-- The shown pose. $$(1, 0, 1)$$ -/
def poseShown : Pose := ⟨1, 0, 1⟩

/-- The open animation runs from the rest pose to the shown pose.

$$\operatorname{in}(0) = (0, -6, 0.96),\quad \operatorname{in}(1) = (1, 0, 1)$$ -/
theorem poseIn_ends : poseIn 0 = poseRest ∧ poseIn 1 = poseShown := by decide +kernel

/-- The close animation runs from the shown pose to its end pose.

$$\operatorname{out}(0) = (1, 0, 1),\quad \operatorname{out}(1) = (0, -4, 0.98)$$ -/
theorem poseOut_ends : poseOut 0 = poseShown ∧ poseOut 1 = ⟨0, -4, 49 / 50⟩ := by decide +kernel

/-- Opacity stays in the unit interval on the unit interval of progress.

$$0 \le e \le 1 \Rightarrow 0 \le \operatorname{in}(e).\mathrm{opacity} \le 1 \land 0 \le \operatorname{out}(e).\mathrm{opacity} \le 1$$ -/
theorem opacity_mem (e : Rat) (h0 : 0 ≤ e) (h1 : e ≤ 1) :
    (0 ≤ (poseIn e).opacity ∧ (poseIn e).opacity ≤ 1) ∧ (0 ≤ (poseOut e).opacity ∧ (poseOut e).opacity ≤ 1) := by
  unfold poseIn poseOut; refine ⟨⟨by grind, by grind⟩, ⟨by grind, by grind⟩⟩

/-- The chevron turns 180 degrees iff the menu is mounted (CSS 11177-11180). $$\theta = 180\,[p \ne \mathrm{closed}]$$ -/
def chevronDeg (p : Phase) : Nat := if mounted p then 180 else 0

end Fw.Parts.NavLangMenu

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

/-- The menu phase (JS 12750 `d`). -/
inductive Phase
  | closed
  | open_
  | closing
deriving Repr, BEq, DecidableEq

/-- Events the menu reacts to (JS 12757-12776, 12777-12790).

The switch click (`C`).
A mousedown outside the wrapper or `Escape`, delivered only while the document listeners are
attached, i.e. The 140 ms close timer. -/
inductive Ev
  | toggle
  | select
  | outside
  | timer
deriving Repr, BEq, DecidableEq

/-- What a step does to the close timer (JS 12752, 12758-12764). -/
inductive Timer
  | keep
  | clear
  | rearm
deriving Repr, BEq, DecidableEq

/-- The result of a step. The new phase and the timer action. -/
structure Out where
  phase : Phase
  timer : Timer
deriving Repr, BEq, DecidableEq

/-- Close (`y`, JS 12757-12763). Start the 140 ms exit. -/
def close : Out := ⟨.closing, .rearm⟩

/-- Open (`x`, JS 12764-12767). Cancel a pending exit and show. -/
def openIt : Out := ⟨.open_, .clear⟩

/-- One step of the machine.

Toggling while closing re-opens. -/
def step (p : Phase) : Ev → Out
  | .toggle => if p == .open_ then close else openIt
  | .select => if p == .open_ then close else ⟨p, .keep⟩
  | .outside => if p == .open_ then close else ⟨p, .keep⟩
  | .timer => if p == .closing then ⟨.closed, .keep⟩ else ⟨p, .keep⟩

/-- The menu has the `is-open` class (JS 12754). -/
def isOpen (p : Phase) : Bool := p == .open_

/-- The menu is rendered and the wrapper has `is-open` (JS 12755). -/
def mounted (p : Phase) : Bool := p != .closed

/-- The menu has the `is-closing` class (JS 12834). -/
def isClosing (p : Phase) : Bool := p == .closing

/-- Document listeners (mousedown, keydown) are attached (JS 12777). -/
def listening (p : Phase) : Bool := p == .open_

/-- The nav's `is-locale-open`, set from `onOpenChange` (JS 12771). -/
def navLocaleOpen (p : Phase) : Bool := mounted p

#guard (step .closed .toggle).phase == .open_
#guard (step .open_ .toggle).phase == .closing
#guard (step .closing .toggle).phase == .open_
#guard (step .closing .timer).phase == .closed
#guard (step .open_ .timer).phase == .open_
#guard (step .closed .outside).phase == .closed

/-- Toggling the switch. -/
theorem toggle_cycle :
    (step .closed .toggle).phase = .open_ ∧ (step .open_ .toggle).phase = .closing ∧
      (step .closing .toggle).phase = .open_ := by
  refine ⟨by decide, by decide, by decide⟩

/-- Closed is only reached through the timer.

The exit animation always runs: nothing hides the menu in one step. -/
theorem closed_only_by_timer (p : Phase) (e : Ev) (h : (step p e).phase = .closed) :
    p = .closed ∨ (p = .closing ∧ e = .timer) := by
  cases p <;> cases e <;> revert h <;> decide

/-- A closing menu is still mounted.

The leave animation has an element to play on. -/
theorem closing_mounted (p : Phase) (h : p = .closing) : mounted p = true ∧ isOpen p = false := by
  subst h; decide

/-- Open implies mounted and listening. -/
theorem open_mounted (p : Phase) (h : isOpen p = true) : mounted p = true ∧ listening p = true := by
  cases p <;> revert h <;> decide

/-- Any open menu ends closed after an outside click and the timer. -/
theorem outside_then_timer : (step (step .open_ .outside).phase .timer).phase = .closed := by decide

/-- Select and outside do nothing to a menu that is not open (the listeners are detached, the options absent). -/
theorem select_idle (p : Phase) (h : p ≠ .open_) : step p .select = ⟨p, .keep⟩ := by
  cases p <;> first | exact absurd rfl h | decide

/-- Every step that leaves the phase open clears the timer; every step into closing re-arms it. -/
theorem timer_discipline (p : Phase) (e : Ev) :
    ((step p e).phase = .open_ → (step p e).timer = .clear ∨ (step p e).timer = .keep) ∧
      (p = .open_ → (step p e).phase = .closing → (step p e).timer = .rearm) := by
  cases p <;> cases e <;> decide

/-! ## Timing and keyframes -/

/-- Close timer in ms (JS 12763). -/
def closeMs : Nat := 140

/-- Open animation in ms (CSS 11204). -/
def inMs : Nat := 180

/-- Close animation in ms (CSS 11207). (equal to the timer, so the unmount follows the last frame). -/
def outMs : Nat := 140

/-- The open animation's curve, `cubic-bezier(0.22, 1, 0.36, 1)` (CSS 11182). -/
def easeIn : Bezier := ⟨11 / 50, 1, 9 / 25, 1⟩

/-- The close animation's curve, `cubic-bezier(0.4, 0, 0.2, 1)` (CSS 11207). -/
def easeOutCurve : Bezier := easeStd

/-- A menu pose. -/
structure Pose where
  opacity : Rat
  y : Rat
  scale : Rat
deriving Repr, BEq, DecidableEq

/-- The pose in the open animation at eased progress `e` (CSS 11209-11218). -/
def poseIn (e : Rat) : Pose := ⟨e, -6 * (1 - e), 24 / 25 + e / 25⟩

/-- The pose in the close animation at eased progress `e` (CSS 11219-11228). -/
def poseOut (e : Rat) : Pose := ⟨1 - e, -4 * e, 1 - e / 50⟩

/-- The rest pose of the menu (CSS 11190-11195). Equal to the start of the open animation. -/
def poseRest : Pose := ⟨0, -6, 24 / 25⟩

/-- The shown pose. -/
def poseShown : Pose := ⟨1, 0, 1⟩

/-- The open animation runs from the rest pose to the shown pose. -/
theorem poseIn_ends : poseIn 0 = poseRest ∧ poseIn 1 = poseShown := by decide +kernel

/-- The close animation runs from the shown pose to its end pose. -/
theorem poseOut_ends : poseOut 0 = poseShown ∧ poseOut 1 = ⟨0, -4, 49 / 50⟩ := by decide +kernel

/-- Opacity stays in the unit interval on the unit interval of progress. -/
theorem opacity_mem (e : Rat) (h0 : 0 ≤ e) (h1 : e ≤ 1) :
    (0 ≤ (poseIn e).opacity ∧ (poseIn e).opacity ≤ 1) ∧ (0 ≤ (poseOut e).opacity ∧ (poseOut e).opacity ≤ 1) := by
  unfold poseIn poseOut; refine ⟨⟨by grind, by grind⟩, ⟨by grind, by grind⟩⟩

/-- The chevron turns 180 degrees iff the menu is mounted (CSS 11177-11180). -/
def chevronDeg (p : Phase) : Nat := if mounted p then 180 else 0

end Fw.Parts.NavLangMenu

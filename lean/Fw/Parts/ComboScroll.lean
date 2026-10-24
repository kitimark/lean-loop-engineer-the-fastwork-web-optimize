import Fw.Parts.MorphEnd

/-! The end-of-page morph with a touch the page cannot hold (task `combo-scroll-fight`).

`Fw.Parts.MorphEnd` decides, for each event, whether the move is prevented and what the per-frame pin writer writes.
It takes a prevented move for a held page. A move holds the page only when the browser lets the prevention stand
(`TouchEvent.cancelable`): once a touch has scrolled natively, or while a momentum scroll runs, later `touchmove`s are not
cancelable, `preventDefault` does nothing, and a pin write per frame then fights the finger. With
`morph.end.release` a close move is not prevented (the page scrolls with the finger), so a reopen in the same touch is
such a move.

The wrapper `wstep` keeps the inner `step` and adds one bit, `held`: the last move was prevented and cancelable. The
frame writer writes only while `held`, and a move that brings `held` back re-pins at the scroll position it reads.
It acts only when `morph.end.release` is on (`wstep_off`), so the original and the clamp and flip bricks are untouched.
Plain words: `research/notes/2026/10-2x-combo-scroll-fight.md`. -/
namespace Fw.Parts.ComboScroll

open Fw.Parts.MorphEnd
open Fw.Parts.MorphTween (taken dir)

/-- The reducer state plus whether the script may hold the page: the last move was prevented and cancelable. -/
structure W where
  s : S
  held : Bool
deriving Repr, BEq, DecidableEq

def W.init (y : Rat) : W := ⟨MorphEnd.init y, true⟩

def _root_.Fw.Parts.MorphEnd.Ev.isMove : Ev → Bool
  | .touchmove _ _ | .wheel _ _ => true
  | _ => false

/-- The scroll position a move reads in its handler. -/
def _root_.Fw.Parts.MorphEnd.Ev.readY : Ev → Option Rat
  | .touchmove _ r => some r.scrollY
  | .wheel _ r => some r.scrollY
  | _ => none

/-- A move holds the page when the step prevents it and the browser lets that stand. -/
def holds (o : Out) (c : Bool) : Bool := o.prevent && c

/-- Holding again after a spell without a hold re-pins where the page is now; the old pin is a stale anchor. -/
def rehold (e : Ev) (k held : Bool) (s : S) : S :=
  match e.readY with
  | some y => if k && !held then { s with pin := y } else s
  | none => s

/-- One event, with the cancelable bit of the browser event (true for a frame, a start and a tick: unused). -/
def wstep (h : Hooks) (w : W) (e : Ev) (c : Bool) : W × Out :=
  let r := step h w.s e
  if h.release then
    if e.isMove then (⟨rehold e (holds r.2 c) w.held r.1, holds r.2 c⟩, r.2)
    else (⟨r.1, w.held⟩, if w.held then r.2 else { r.2 with write := none })
  else (⟨r.1, w.held⟩, r.2)

def wfinal (h : Hooks) : W → List (Ev × Bool) → W
  | w, [] => w
  | w, (e, c) :: t => wfinal h (wstep h w e c).1 t

def wtrace (h : Hooks) : W → List (Ev × Bool) → List (Ev × Out)
  | _, [] => []
  | w, (e, c) :: t => (e, (wstep h w e c).2) :: wtrace h (wstep h w e c).1 t

/-- Same state up to the pin: the part the open and close decisions read. -/
def _root_.Fw.Parts.MorphEnd.S.sameCore (a b : S) : Prop :=
  a.tw = b.tw ∧ a.touchY = b.touchY ∧ a.ctr = b.ctr ∧ a.fresh = b.fresh ∧ a.rel = b.rel

theorem sameCore_refl (a : S) : a.sameCore a := ⟨rfl, rfl, rfl, rfl, rfl⟩

theorem sameCore_symm {a b : S} (h : a.sameCore b) : b.sameCore a :=
  ⟨h.1.symm, h.2.1.symm, h.2.2.1.symm, h.2.2.2.1.symm, h.2.2.2.2.symm⟩

theorem sameCore_trans {a b c : S} (h : a.sameCore b) (h' : b.sameCore c) : a.sameCore c :=
  ⟨h.1.trans h'.1, h.2.1.trans h'.2.1, h.2.2.1.trans h'.2.2.1, h.2.2.2.1.trans h'.2.2.2.1, h.2.2.2.2.trans h'.2.2.2.2⟩

/-! ## The wrapper changes the writer and the pin, nothing else -/

theorem wstep_off (h : Hooks) (hr : h.release = false) (w : W) (e : Ev) (c : Bool) :
    wstep h w e c = (⟨(step h w.s e).1, w.held⟩, (step h w.s e).2) := by
  simp [wstep, hr]

theorem rehold_core (e : Ev) (k held : Bool) (s : S) : (rehold e k held s).sameCore s := by
  unfold rehold
  split
  · split <;> exact sameCore_refl _
  · exact sameCore_refl _

theorem wstep_core (h : Hooks) (w : W) (e : Ev) (c : Bool) : (wstep h w e c).1.s.sameCore (step h w.s e).1 := by
  unfold wstep
  split
  · split
    · exact rehold_core _ _ _ _
    · exact sameCore_refl _
  · exact sameCore_refl _

theorem wstep_prevent (h : Hooks) (w : W) (e : Ev) (c : Bool) : (wstep h w e c).2.prevent = (step h w.s e).2.prevent := by
  unfold wstep
  split <;> (try split) <;> (try (by_cases hh : w.held = true <;> simp [hh]))

theorem wstep_goal (h : Hooks) (w : W) (e : Ev) (c : Bool) : (wstep h w e c).2.goal = (step h w.s e).2.goal := by
  unfold wstep
  split <;> (try split) <;> (try (by_cases hh : w.held = true <;> simp [hh]))

theorem wstep_flip (h : Hooks) (w : W) (e : Ev) (c : Bool) : (wstep h w e c).2.flip = (step h w.s e).2.flip := by
  unfold wstep
  split <;> (try split) <;> (try (by_cases hh : w.held = true <;> simp [hh]))

/-- The wrapper only removes writes. -/
theorem wstep_write_sub (h : Hooks) (w : W) (e : Ev) (c : Bool) (x : Rat)
    (hw : (wstep h w e c).2.write = some x) : (step h w.s e).2.write = some x := by
  unfold wstep at hw
  split at hw
  · split at hw
    · exact hw
    · split at hw <;> simp_all
  · exact hw

/-- Writes happen on frames only: the held bit gates the one writer. -/
theorem fix_write_held (h : Hooks) (hr : h.release = true) (w : W) (e : Ev) (c : Bool) (x : Rat)
    (hw : (wstep h w e c).2.write = some x) : w.held = true ∨ e.isMove = true := by
  unfold wstep at hw
  simp only [hr, ite_true] at hw
  by_cases hm : e.isMove = true
  · exact Or.inr hm
  · left
    simp only [hm, Bool.false_eq_true, ite_false] at hw
    by_cases hh : w.held = true
    · exact hh
    · simp [hh] at hw

/-! ## The fix: no script write against a native scroll -/

theorem wstep_held_move (h : Hooks) (hr : h.release = true) (w : W) (e : Ev) (c : Bool) (he : e.isMove = true) :
    (wstep h w e c).1.held = holds (step h w.s e).2 c := by
  simp [wstep, hr, he]

theorem wstep_held_frame (h : Hooks) (w : W) (e : Ev) (c : Bool) (he : e.isMove = false) :
    (wstep h w e c).1.held = w.held := by
  unfold wstep; split <;> (try split) <;> simp_all

theorem wstep_frame_state (h : Hooks) (w : W) (e : Ev) (c : Bool) (he : e.isFrame = true) :
    (wstep h w e c).1 = w := by
  have hm : e.isMove = false := by cases e <;> simp_all [Ev.isFrame, Ev.isMove]
  have hs := step_frame h w.s e he
  unfold wstep
  split <;> (try split) <;> simp_all

/-- A move that is not held (not prevented, or not cancelable) is followed by no write until the next move. -/
theorem native_quiet (h : Hooks) (hr : h.release = true) (w : W) (e : Ev) (c : Bool) (he : e.isMove = true)
    (hn : holds (step h w.s e).2 c = false) (t : List (Ev × Bool)) (hf : ∀ p ∈ t, p.1.isFrame = true) :
    ∀ q ∈ wtrace h (wstep h w e c).1 t, q.2.write = none := by
  have hheld : (wstep h w e c).1.held = false := by rw [wstep_held_move h hr w e c he, hn]
  generalize (wstep h w e c).1 = w' at hheld
  induction t generalizing w' with
  | nil => simp [wtrace]
  | cons p t ih =>
    obtain ⟨e', c'⟩ := p
    have hfe : e'.isFrame = true := hf (e', c') (by simp)
    have hm : e'.isMove = false := by cases e' <;> simp_all [Ev.isFrame, Ev.isMove]
    have hst := wstep_frame_state h w' e' c' hfe
    intro q hq
    simp only [wtrace, List.mem_cons] at hq
    rcases hq with rfl | hq
    · unfold wstep
      simp [hr, hm, hheld]
    · rw [hst] at hq
      exact ih (fun p hp => hf p (List.mem_cons_of_mem _ hp)) w' hheld q hq

/-- The move that brings `held` back re-pins at the scroll position it read. -/
theorem rehold_pin (h : Hooks) (hr : h.release = true) (w : W) (e : Ev) (c : Bool) (y : Rat)
    (hy : e.readY = some y) (hk : holds (step h w.s e).2 c = true) (hw : w.held = false) :
    (wstep h w e c).1.s.pin = y ∧ (wstep h w e c).1.held = true := by
  have he : e.isMove = true := by cases e <;> simp_all [Ev.readY, Ev.isMove]
  refine ⟨?_, by rw [wstep_held_move h hr w e c he, hk]⟩
  simp [wstep, hr, he, rehold, hy, hk, hw]

/-- A held page keeps its pin through a move that holds again: the writer's target is never re-captured while held. -/
theorem held_keeps_pin (h : Hooks) (hr : h.release = true) (w : W) (e : Ev) (c : Bool)
    (hk : holds (step h w.s e).2 c = true) (hw : w.held = true) : (wstep h w e c).1.s = (step h w.s e).1 := by
  by_cases he : e.isMove = true
  · simp [wstep, hr, he, rehold, hk, hw]
    cases e.readY <;> simp
  · simp [wstep, hr, he]

/-! ## Equal to the inner reducer whenever the page can hold every move -/

/-- Every move of the trace is prevented and cancelable (the case of the original page: all moves held). -/
def AllHold (h : Hooks) : S → List (Ev × Bool) → Prop
  | _, [] => True
  | s, (e, c) :: t => (e.isMove = true → holds (step h s e).2 c = true) ∧ AllHold h (step h s e).1 t

theorem wrap_all_hold (h : Hooks) (w : W) (t : List (Ev × Bool)) (hw : w.held = true) (ha : AllHold h w.s t) :
    wtrace h w t = trace h w.s (t.map (·.1)) ∧ (wfinal h w t).s = final h w.s (t.map (·.1)) ∧ (wfinal h w t).held = true := by
  induction t generalizing w with
  | nil => exact ⟨rfl, rfl, hw⟩
  | cons p t ih =>
    obtain ⟨e, c⟩ := p
    obtain ⟨hmv, ha'⟩ := ha
    by_cases hr : h.release = true
    · have hstate : wstep h w e c = (⟨(step h w.s e).1, true⟩, (step h w.s e).2) := by
        by_cases he : e.isMove = true
        · have hk := hmv he
          simp only [wstep, hr, he, ite_true, hk, hw, rehold]
          cases e.readY <;> simp
        · simp [wstep, hr, he, hw]
      obtain ⟨i1, i2, i3⟩ := ih (wstep h w e c).1 (by rw [hstate]) (by rw [hstate]; exact ha')
      rw [hstate] at i1 i2 i3
      simp only [List.map, trace, wtrace, wfinal, final, hstate]
      exact ⟨by rw [i1], i2, i3⟩
    · have hr' : h.release = false := by simpa using hr
      have hstate := wstep_off h hr' w e c
      have ha'' : AllHold h (wstep h w e c).1.s t := by rw [hstate]; exact ha'
      obtain ⟨i1, i2, i3⟩ := ih (wstep h w e c).1 (by rw [hstate]; exact hw) ha''
      simp only [List.map, trace, wtrace, wfinal, final, hstate] at *
      exact ⟨by rw [i1], i2, i3⟩

theorem faithful_w (h : Hooks) (hr : h.release = false) (w : W) (t : List (Ev × Bool)) (hw : w.held = true) :
    wtrace h w t = trace h w.s (t.map (·.1)) ∧ (wfinal h w t).s = final h w.s (t.map (·.1)) := by
  induction t generalizing w with
  | nil => exact ⟨rfl, rfl⟩
  | cons p t ih =>
    obtain ⟨e, c⟩ := p
    have hstate := wstep_off h hr w e c
    obtain ⟨i1, i2⟩ := ih (wstep h w e c).1 (by rw [hstate]; exact hw)
    simp only [List.map, trace, wtrace, wfinal, final, hstate] at *
    exact ⟨by rw [i1], i2⟩

/-! ## The bricks keep their theorems -/

theorem moveStep_pin (h : Hooks) (ta : MorphTween.St) (ty pa pb ca : Rat) (fa ra : Bool) (d : Rat) (r : Read) :
    (moveStep h ⟨ta, ty, pa, ca, fa, ra⟩ d r).1.sameCore (moveStep h ⟨ta, ty, pb, ca, fa, ra⟩ d r).1 ∧
      (moveStep h ⟨ta, ty, pa, ca, fa, ra⟩ d r).2.prevent = (moveStep h ⟨ta, ty, pb, ca, fa, ra⟩ d r).2.prevent ∧
      (moveStep h ⟨ta, ty, pa, ca, fa, ra⟩ d r).2.goal = (moveStep h ⟨ta, ty, pb, ca, fa, ra⟩ d r).2.goal ∧
      (moveStep h ⟨ta, ty, pa, ca, fa, ra⟩ d r).2.flip = (moveStep h ⟨ta, ty, pb, ca, fa, ra⟩ d r).2.flip := by
  unfold moveStep
  by_cases ht : taken ta.isActive d r.arm = true
  · simp only [ht, ite_true]
    cases hd : dir d with
    | none => simp [kept, S.sameCore, pinAfter, free, ctrAfter]
    | some g =>
      by_cases hb : blocked h ⟨ta, ty, pa, ca, fa, ra⟩ d g = true
      · have hb' : blocked h ⟨ta, ty, pb, ca, fa, ra⟩ d g = true := by simpa [blocked, ctrAfter] using hb
        simp [hb, hb', kept, S.sameCore, pinAfter, free, ctrAfter]
      · have hb' : blocked h ⟨ta, ty, pb, ca, fa, ra⟩ d g = false := by
          simpa [blocked, ctrAfter] using hb
        simp [hb, hb', applied, S.sameCore, pinAfter, free]
  · simp [ht, S.sameCore, ctrAfter]

theorem step_core_pin (h : Hooks) (a b : S) (hc : a.sameCore b) (e : Ev) :
    (step h a e).1.sameCore (step h b e).1 ∧ (step h a e).2.prevent = (step h b e).2.prevent ∧
      (step h a e).2.goal = (step h b e).2.goal ∧ (step h a e).2.flip = (step h b e).2.flip := by
  obtain ⟨ta, ya, pa, ca, fa, ra⟩ := a
  obtain ⟨tb, yb, pb, cb, fb, rb⟩ := b
  obtain ⟨h1, h2, h3, h4, h5⟩ := hc
  simp only at h1 h2 h3 h4 h5
  subst h1 h2 h3 h4 h5
  cases e with
  | touchstart y => simp [step, S.sameCore]
  | touchmove y r => simpa only [step] using moveStep_pin h ta (y.getD ya) pa pb ca fa ra (ya - y.getD ya) r
  | wheel d r => simpa only [step] using moveStep_pin h ta ya pa pb ca fa ra d r
  | scroll y m => simp [step, S.sameCore, frameOut]
  | resize y m => simp [step, S.sameCore, frameOut]
  | tick now => cases hp : ta.pending <;> simp [step, S.sameCore, hp]

/-- The decisions of the bricks (prevent, goal, flip) and the state they read are those of the inner reducer, event by event,
from any inner state that agrees up to the pin. -/
theorem wtrace_decisions (h : Hooks) (w : W) (s : S) (hs : w.s.sameCore s) (t : List (Ev × Bool)) :
    (wtrace h w t).map (fun p => (p.1, p.2.prevent, p.2.goal, p.2.flip)) =
      (trace h s (t.map (·.1))).map (fun p => (p.1, p.2.prevent, p.2.goal, p.2.flip)) ∧
    (wfinal h w t).s.sameCore (final h s (t.map (·.1))) := by
  induction t generalizing w s with
  | nil => exact ⟨rfl, hs⟩
  | cons p t ih =>
    obtain ⟨e, c⟩ := p
    have hc := wstep_core h w e c
    obtain ⟨j1, j2, j3, j4⟩ := step_core_pin h _ _ hs e
    obtain ⟨i1, i2⟩ := ih (wstep h w e c).1 (step h s e).1 (sameCore_trans hc j1)
    refine ⟨?_, i2⟩
    simp only [List.map, trace, wtrace, wstep_prevent, wstep_goal, wstep_flip, j2, j3, j4]
    rw [i1]

/-! ### Brick A, B and C through the wrapper -/

theorem wclamp_le (c : Cfg) (hc : c.clamp = true) (w : W) (e : Ev) (b : Bool) (x : Rat)
    (hw : (wstep c.hooks w e b).2.write = some x) : ∃ y m, (e = .scroll y m ∨ e = .resize y m) ∧ x ≤ m :=
  clamp_le c hc w.s e x (wstep_write_sub _ _ _ _ _ hw)

theorem wrelease_close_free (c : Cfg) (hc : c.release = true) (w : W) (e : Ev) (b : Bool)
    (hg : (wstep c.hooks w e b).2.goal = some 0) : (wstep c.hooks w e b).2.prevent = false := by
  rw [wstep_goal] at hg
  rw [wstep_prevent]
  exact release_close_free c hc w.s e hg

theorem wrelease_starts (h : Hooks) (w : W) (e : Ev) (b : Bool) (hg : (wstep h w e b).2.goal = some 0) :
    (wstep h w e b).1.s.rel = true := by
  rw [wstep_goal] at hg
  rw [(wstep_core h w e b).2.2.2.2]
  exact release_starts h w.s e hg

theorem wrelease_rel (h : Hooks) (w : W) (e : Ev) (b : Bool) (hr : w.s.rel = true) (hg : (wstep h w e b).2.goal ≠ some 1) :
    (wstep h w e b).1.s.rel = true := by
  rw [wstep_goal] at hg
  rw [(wstep_core h w e b).2.2.2.2]
  exact release_rel h w.s e hr hg

/-- After a close starts there is no write until a push to open, with the wrapper in place. -/
theorem wrelease_quiet (c : Cfg) (hc : c.release = true) (w : W) (t : List (Ev × Bool)) (hr : w.s.rel = true)
    (hno : ∀ p ∈ wtrace c.hooks w t, p.2.goal ≠ some 1) : ∀ p ∈ wtrace c.hooks w t, p.2.write = none := by
  induction t generalizing w with
  | nil => simp [wtrace]
  | cons q t ih =>
    obtain ⟨e, b⟩ := q
    have hg : (wstep c.hooks w e b).2.goal ≠ some 1 := hno (e, (wstep c.hooks w e b).2) (by simp [wtrace])
    have hr' := wrelease_rel c.hooks w e b hr hg
    have hw : (wstep c.hooks w e b).2.write = none := by
      cases hwe : (wstep c.hooks w e b).2.write with
      | none => rfl
      | some x =>
        have hsub := wstep_write_sub _ _ _ _ _ hwe
        have hq := release_quiet c hc w.s [e] hr (by
          intro p hp
          simp only [trace, List.mem_cons, List.not_mem_nil, or_false] at hp
          subst hp
          rwa [← wstep_goal c.hooks w e b])
        have hz := hq (e, (step c.hooks w.s e).2) (by simp [trace])
        rw [hz] at hsub
        cases hsub
    intro p hp
    simp only [wtrace, List.mem_cons] at hp
    rcases hp with rfl | hp
    · exact hw
    · exact ih _ hr' (fun q hq => hno q (by simp only [wtrace, List.mem_cons]; exact Or.inr hq)) p hp

/-! ### Event cadence: `engine.scroll:unthrottle` and any other frame rate -/

theorem cadence_w (h : Hooks) (w : W) (t : List (Ev × Bool)) :
    wfinal h w t = wfinal h w (t.filter (!·.1.isFrame)) := by
  induction t generalizing w with
  | nil => rfl
  | cons p t ih =>
    obtain ⟨e, c⟩ := p
    by_cases he : e.isFrame = true
    · simp only [wfinal, List.filter, he, Bool.not_true]; rw [wstep_frame_state h w e c he]; exact ih w
    · simp only [wfinal, List.filter, he, Bool.not_false]; exact ih _

/-! ### One writer per frame

A frame event carries one `Option` write, from the one `frameOut`; the page registers one pin callback per frame in
`morph.tween`. `morph.mount` has its own re-pin callback, which never writes in the app because it is built without an
`isActive` (`apps/site/src/App.tsx`), so `morph.tween` is the only writer (CONFIRMED by reading; the site test pins it). -/

theorem one_write_per_frame (h : Hooks) (w : W) (e : Ev) (c : Bool) (x y : Rat)
    (h1 : (wstep h w e c).2.write = some x) (h2 : (wstep h w e c).2.write = some y) : x = y := by
  rw [h1] at h2; exact Option.some.inj h2

/-! ## The user's trace

Open at the page end (finger up), close in the same touch (finger down, not prevented under `release`), and reopen
(finger up) in a move the browser will not let the page cancel. The inner reducer then pins the page at the scroll
position of the reopen and writes it on every frame against the finger; the wrapper writes nothing. -/

def rd (y now : Rat) : Read := ⟨y, true, now, false⟩

def userTrace : List (Ev × Bool) :=
  [(.touchstart (some 700), true), (.touchmove (some 690) (rd 5188 0), true), (.tick 700, true),
   (.touchmove (some 900) (rd 5188 700), true), (.touchmove (some 850) (rd 4900 800), false),
   (.scroll 4950 5188, true), (.scroll 4880 5188, true)]

def userCfg : Cfg := ⟨true, true, true⟩

def writesOf (l : List (Ev × Out)) : List (Option Rat) := l.map (·.2.write)

#guard writesOf (trace userCfg.hooks (init 5188) (userTrace.map (·.1))) ==
  [none, none, none, none, none, some 4900, some 4900]
#guard writesOf (wtrace userCfg.hooks (W.init 5188) userTrace) == [none, none, none, none, none, none, none]
#guard (wfinal userCfg.hooks (W.init 5188) userTrace).held == false
#guard (trace Cfg.faithful.hooks (init 5188) (userTrace.map (·.1))).map (·.2.prevent) ==
  [false, true, false, true, true, false, false]
#guard (wtrace userCfg.hooks (W.init 5188) userTrace).map (·.2.prevent) ==
  [false, true, false, false, true, false, false]

/-- The same trace with the reopen in a move the page can cancel is held and pinned where the page was. -/
def heldTrace : List (Ev × Bool) :=
  [(.touchstart (some 700), true), (.touchmove (some 690) (rd 5188 0), true), (.tick 700, true),
   (.touchmove (some 900) (rd 5188 700), true), (.touchstart (some 500), true), (.touchmove (some 450) (rd 4900 800), true),
   (.scroll 4950 5188, true)]

#guard writesOf (wtrace userCfg.hooks (W.init 5188) heldTrace) == [none, none, none, none, none, none, some 4900]
#guard writesOf (wtrace userCfg.hooks (W.init 5188) heldTrace) == writesOf (trace userCfg.hooks (init 5188) (heldTrace.map (·.1)))

end Fw.Parts.ComboScroll

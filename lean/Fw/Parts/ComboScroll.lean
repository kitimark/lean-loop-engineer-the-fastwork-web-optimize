import Fw.Parts.MorphEnd
import Fw.Parts.MorphMountArmLate

namespace Fw.Parts.ComboScroll

open Fw.Parts.MorphEnd
open Fw.Parts.MorphTween (taken dir)

structure W where
  s : S
  held : Bool
deriving Repr, BEq, DecidableEq

def W.init (y : Rat) : W := ⟨MorphEnd.init y, true⟩

def _root_.Fw.Parts.MorphEnd.Ev.isMove : Ev → Bool
  | .touchmove _ _ | .wheel _ _ => true
  | _ => false

def _root_.Fw.Parts.MorphEnd.Ev.readY : Ev → Option Rat
  | .touchmove _ r => some r.scrollY
  | .wheel _ r => some r.scrollY
  | _ => none

structure Dlv where
  cancelable : Bool
  passive : Bool
  other : Bool
deriving Repr, BEq, DecidableEq

/-- `Event.defaultPrevented` after the handler: DOM "set the canceled flag" needs cancelable and no passive listener running. -/
def Dlv.prevented (d : Dlv) (o : Out) : Bool := d.other || (o.prevent && d.cancelable && !d.passive)

def Dlv.std : Dlv := ⟨true, false, false⟩

def Dlv.ofArm (blk cancelable : Bool) : Dlv := ⟨cancelable, !blk, false⟩

def holds (o : Out) (c : Dlv) : Bool := c.prevented o

theorem holds_std (o : Out) : holds o Dlv.std = o.prevent := by
  simp [holds, Dlv.prevented, Dlv.std]

theorem holds_passive (o : Out) (c : Dlv) (hp : c.passive = true) (ho : c.other = false) : holds o c = false := by
  simp [holds, Dlv.prevented, hp, ho]

theorem holds_uncancelable (o : Out) (c : Dlv) (hc : c.cancelable = false) (ho : c.other = false) : holds o c = false := by
  simp [holds, Dlv.prevented, hc, ho]

theorem holds_blocking (o : Out) (c : Dlv) (hc : c.cancelable = true) (hp : c.passive = false) (ho : c.other = false) :
    holds o c = o.prevent := by
  simp [holds, Dlv.prevented, hc, hp, ho]

theorem holds_other (o : Out) (c : Dlv) (ho : c.other = true) : holds o c = true := by
  simp [holds, Dlv.prevented, ho]

theorem old_rule_differs : ∃ (o : Out) (c : Dlv), (o.prevent && c.cancelable) = true ∧ holds o c = false :=
  ⟨⟨true, none, false, none⟩, ⟨true, true, false⟩, by decide⟩

def rehold (e : Ev) (k held : Bool) (s : S) : S :=
  match e.readY with
  | some y => if k && !held then { s with pin := y } else s
  | none => s

def wstep (h : Hooks) (w : W) (e : Ev) (c : Dlv) : W × Out :=
  let r := step h w.s e
  if h.release then
    if e.isMove then (⟨rehold e (holds r.2 c) w.held r.1, holds r.2 c⟩, r.2)
    else (⟨r.1, w.held⟩, if w.held then r.2 else { r.2 with write := none })
  else (⟨r.1, w.held⟩, r.2)

def wfinal (h : Hooks) : W → List (Ev × Dlv) → W
  | w, [] => w
  | w, (e, c) :: t => wfinal h (wstep h w e c).1 t

def wtrace (h : Hooks) : W → List (Ev × Dlv) → List (Ev × Out)
  | _, [] => []
  | w, (e, c) :: t => (e, (wstep h w e c).2) :: wtrace h (wstep h w e c).1 t

def _root_.Fw.Parts.MorphEnd.S.sameCore (a b : S) : Prop :=
  a.tw = b.tw ∧ a.touchY = b.touchY ∧ a.ctr = b.ctr ∧ a.fresh = b.fresh ∧ a.rel = b.rel

theorem sameCore_refl (a : S) : a.sameCore a := ⟨rfl, rfl, rfl, rfl, rfl⟩

theorem sameCore_symm {a b : S} (h : a.sameCore b) : b.sameCore a :=
  ⟨h.1.symm, h.2.1.symm, h.2.2.1.symm, h.2.2.2.1.symm, h.2.2.2.2.symm⟩

theorem sameCore_trans {a b c : S} (h : a.sameCore b) (h' : b.sameCore c) : a.sameCore c :=
  ⟨h.1.trans h'.1, h.2.1.trans h'.2.1, h.2.2.1.trans h'.2.2.1, h.2.2.2.1.trans h'.2.2.2.1, h.2.2.2.2.trans h'.2.2.2.2⟩

theorem wstep_off (h : Hooks) (hr : h.release = false) (w : W) (e : Ev) (c : Dlv) :
    wstep h w e c = (⟨(step h w.s e).1, w.held⟩, (step h w.s e).2) := by
  simp [wstep, hr]

theorem rehold_core (e : Ev) (k held : Bool) (s : S) : (rehold e k held s).sameCore s := by
  unfold rehold
  split
  · split <;> exact sameCore_refl _
  · exact sameCore_refl _

theorem wstep_core (h : Hooks) (w : W) (e : Ev) (c : Dlv) : (wstep h w e c).1.s.sameCore (step h w.s e).1 := by
  unfold wstep
  split
  · split
    · exact rehold_core _ _ _ _
    · exact sameCore_refl _
  · exact sameCore_refl _

theorem wstep_prevent (h : Hooks) (w : W) (e : Ev) (c : Dlv) : (wstep h w e c).2.prevent = (step h w.s e).2.prevent := by
  unfold wstep
  split <;> (try split) <;> (try (by_cases hh : w.held = true <;> simp [hh]))

theorem wstep_goal (h : Hooks) (w : W) (e : Ev) (c : Dlv) : (wstep h w e c).2.goal = (step h w.s e).2.goal := by
  unfold wstep
  split <;> (try split) <;> (try (by_cases hh : w.held = true <;> simp [hh]))

theorem wstep_flip (h : Hooks) (w : W) (e : Ev) (c : Dlv) : (wstep h w e c).2.flip = (step h w.s e).2.flip := by
  unfold wstep
  split <;> (try split) <;> (try (by_cases hh : w.held = true <;> simp [hh]))

theorem wstep_write_sub (h : Hooks) (w : W) (e : Ev) (c : Dlv) (x : Rat)
    (hw : (wstep h w e c).2.write = some x) : (step h w.s e).2.write = some x := by
  unfold wstep at hw
  split at hw
  · split at hw
    · exact hw
    · split at hw <;> simp_all
  · exact hw

theorem fix_write_held (h : Hooks) (hr : h.release = true) (w : W) (e : Ev) (c : Dlv) (x : Rat)
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

theorem wstep_held_move (h : Hooks) (hr : h.release = true) (w : W) (e : Ev) (c : Dlv) (he : e.isMove = true) :
    (wstep h w e c).1.held = holds (step h w.s e).2 c := by
  simp [wstep, hr, he]

theorem wstep_held_frame (h : Hooks) (w : W) (e : Ev) (c : Dlv) (he : e.isMove = false) :
    (wstep h w e c).1.held = w.held := by
  unfold wstep; split <;> (try split) <;> simp_all

theorem wstep_frame_state (h : Hooks) (w : W) (e : Ev) (c : Dlv) (he : e.isFrame = true) :
    (wstep h w e c).1 = w := by
  have hm : e.isMove = false := by cases e <;> simp_all [Ev.isFrame, Ev.isMove]
  have hs := step_frame h w.s e he
  unfold wstep
  split <;> (try split) <;> simp_all

theorem native_quiet (h : Hooks) (hr : h.release = true) (w : W) (e : Ev) (c : Dlv) (he : e.isMove = true)
    (hn : holds (step h w.s e).2 c = false) (t : List (Ev × Dlv)) (hf : ∀ p ∈ t, p.1.isFrame = true) :
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

theorem rehold_pin (h : Hooks) (hr : h.release = true) (w : W) (e : Ev) (c : Dlv) (y : Rat)
    (hy : e.readY = some y) (hk : holds (step h w.s e).2 c = true) (hw : w.held = false) :
    (wstep h w e c).1.s.pin = y ∧ (wstep h w e c).1.held = true := by
  have he : e.isMove = true := by cases e <;> simp_all [Ev.readY, Ev.isMove]
  refine ⟨?_, by rw [wstep_held_move h hr w e c he, hk]⟩
  simp [wstep, hr, he, rehold, hy, hk, hw]

theorem held_keeps_pin (h : Hooks) (hr : h.release = true) (w : W) (e : Ev) (c : Dlv)
    (hk : holds (step h w.s e).2 c = true) (hw : w.held = true) : (wstep h w e c).1.s = (step h w.s e).1 := by
  by_cases he : e.isMove = true
  · simp [wstep, hr, he, rehold, hk, hw]
    cases e.readY <;> simp
  · simp [wstep, hr, he]

def AllHold (h : Hooks) : S → List (Ev × Dlv) → Prop
  | _, [] => True
  | s, (e, c) :: t => (e.isMove = true → holds (step h s e).2 c = true) ∧ AllHold h (step h s e).1 t

theorem wrap_all_hold (h : Hooks) (w : W) (t : List (Ev × Dlv)) (hw : w.held = true) (ha : AllHold h w.s t) :
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

theorem faithful_w (h : Hooks) (hr : h.release = false) (w : W) (t : List (Ev × Dlv)) (hw : w.held = true) :
    wtrace h w t = trace h w.s (t.map (·.1)) ∧ (wfinal h w t).s = final h w.s (t.map (·.1)) := by
  induction t generalizing w with
  | nil => exact ⟨rfl, rfl⟩
  | cons p t ih =>
    obtain ⟨e, c⟩ := p
    have hstate := wstep_off h hr w e c
    obtain ⟨i1, i2⟩ := ih (wstep h w e c).1 (by rw [hstate]; exact hw)
    simp only [List.map, trace, wtrace, wfinal, final, hstate] at *
    exact ⟨by rw [i1], i2⟩

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

theorem wtrace_decisions (h : Hooks) (w : W) (s : S) (hs : w.s.sameCore s) (t : List (Ev × Dlv)) :
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

theorem wclamp_le (c : Cfg) (hc : c.clamp = true) (w : W) (e : Ev) (b : Dlv) (x : Rat)
    (hw : (wstep c.hooks w e b).2.write = some x) : ∃ y m, (e = .scroll y m ∨ e = .resize y m) ∧ x ≤ m :=
  clamp_le c hc w.s e x (wstep_write_sub _ _ _ _ _ hw)

theorem wrelease_close_free (c : Cfg) (hc : c.release = true) (w : W) (e : Ev) (b : Dlv)
    (hg : (wstep c.hooks w e b).2.goal = some 0) : (wstep c.hooks w e b).2.prevent = false := by
  rw [wstep_goal] at hg
  rw [wstep_prevent]
  exact release_close_free c hc w.s e hg

theorem wrelease_starts (h : Hooks) (w : W) (e : Ev) (b : Dlv) (hg : (wstep h w e b).2.goal = some 0) :
    (wstep h w e b).1.s.rel = true := by
  rw [wstep_goal] at hg
  rw [(wstep_core h w e b).2.2.2.2]
  exact release_starts h w.s e hg

theorem wrelease_rel (h : Hooks) (w : W) (e : Ev) (b : Dlv) (hr : w.s.rel = true) (hg : (wstep h w e b).2.goal ≠ some 1) :
    (wstep h w e b).1.s.rel = true := by
  rw [wstep_goal] at hg
  rw [(wstep_core h w e b).2.2.2.2]
  exact release_rel h w.s e hr hg

theorem wrelease_quiet (c : Cfg) (hc : c.release = true) (w : W) (t : List (Ev × Dlv)) (hr : w.s.rel = true)
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

theorem cadence_w (h : Hooks) (w : W) (t : List (Ev × Dlv)) :
    wfinal h w t = wfinal h w (t.filter (!·.1.isFrame)) := by
  induction t generalizing w with
  | nil => rfl
  | cons p t ih =>
    obtain ⟨e, c⟩ := p
    by_cases he : e.isFrame = true
    · simp only [wfinal, List.filter, he, Bool.not_true]; rw [wstep_frame_state h w e c he]; exact ih w
    · simp only [wfinal, List.filter, he, Bool.not_false]; exact ih _

theorem holds_arm (blk cancelable : Bool) (o : Out) :
    holds o (Dlv.ofArm blk cancelable) = holds (MorphMountArmLate.honorOut blk o) ⟨cancelable, false, false⟩ := by
  cases blk <;> cases cancelable <;> simp [holds, Dlv.prevented, Dlv.ofArm, MorphMountArmLate.honorOut]

theorem arm_late_holds (blk cancelable : Bool) (o : Out) (h : o.prevent = true → blk = true) :
    holds o (Dlv.ofArm blk cancelable) = holds o ⟨cancelable, false, false⟩ := by
  rw [holds_arm, MorphMountArmLate.honorOut_of blk o h]

theorem arm_passive_unheld (cancelable : Bool) (o : Out) : holds o (Dlv.ofArm false cancelable) = false :=
  holds_passive o _ rfl rfl

theorem arm_passive_quiet (h : Hooks) (hr : h.release = true) (w : W) (e : Ev) (cancelable : Bool) (he : e.isMove = true)
    (t : List (Ev × Dlv)) (hf : ∀ p ∈ t, p.1.isFrame = true) :
    ∀ q ∈ wtrace h (wstep h w e (Dlv.ofArm false cancelable)).1 t, q.2.write = none :=
  native_quiet h hr w e _ he (arm_passive_unheld cancelable _) t hf

theorem passive_quiet (h : Hooks) (hr : h.release = true) (w : W) (e : Ev) (c : Dlv) (he : e.isMove = true)
    (hp : c.passive = true) (ho : c.other = false) (t : List (Ev × Dlv)) (hf : ∀ p ∈ t, p.1.isFrame = true) :
    ∀ q ∈ wtrace h (wstep h w e c).1 t, q.2.write = none :=
  native_quiet h hr w e c he (holds_passive _ c hp ho) t hf

theorem one_write_per_frame (h : Hooks) (w : W) (e : Ev) (c : Dlv) (x y : Rat)
    (h1 : (wstep h w e c).2.write = some x) (h2 : (wstep h w e c).2.write = some y) : x = y := by
  rw [h1] at h2; exact Option.some.inj h2

def rd (y now : Rat) : Read := ⟨y, true, now, false⟩

def ok : Dlv := Dlv.std

def nc : Dlv := ⟨false, false, false⟩

def ps : Dlv := ⟨true, true, false⟩

def userTrace : List (Ev × Dlv) :=
  [(.touchstart (some 700), ok), (.touchmove (some 690) (rd 5188 0), ok), (.tick 700, ok),
   (.touchmove (some 900) (rd 5188 700), ok), (.touchmove (some 850) (rd 4900 800), nc),
   (.scroll 4950 5188, ok), (.scroll 4880 5188, ok)]

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

def heldTrace : List (Ev × Dlv) :=
  [(.touchstart (some 700), ok), (.touchmove (some 690) (rd 5188 0), ok), (.tick 700, ok),
   (.touchmove (some 900) (rd 5188 700), ok), (.touchstart (some 500), ok), (.touchmove (some 450) (rd 4900 800), ok),
   (.scroll 4950 5188, ok)]

#guard writesOf (wtrace userCfg.hooks (W.init 5188) heldTrace) == [none, none, none, none, none, none, some 4900]
#guard writesOf (wtrace userCfg.hooks (W.init 5188) heldTrace) == writesOf (trace userCfg.hooks (init 5188) (heldTrace.map (·.1)))

def passiveTrace : List (Ev × Dlv) :=
  [(.touchstart (some 700), ok), (.touchmove (some 690) (rd 5188 0), ok), (.tick 700, ok),
   (.touchmove (some 900) (rd 5188 700), ok), (.touchmove (some 850) (rd 4900 800), ps),
   (.scroll 4950 5188, ok), (.scroll 4880 5188, ok)]

#guard writesOf (wtrace userCfg.hooks (W.init 5188) passiveTrace) == [none, none, none, none, none, none, none]
#guard writesOf (trace userCfg.hooks (init 5188) (passiveTrace.map (·.1))) == [none, none, none, none, none, some 4900, some 4900]
#guard (wfinal userCfg.hooks (W.init 5188) passiveTrace).held == false
#guard (wtrace userCfg.hooks (W.init 5188) passiveTrace).map (·.2.prevent) == [false, true, false, false, true, false, false]

def otherTrace : List (Ev × Dlv) :=
  [(.touchstart (some 700), ok), (.touchmove (some 690) (rd 5188 0), ok), (.tick 700, ok),
   (.touchmove (some 900) (rd 5188 700), ok), (.touchmove (some 850) (rd 4900 800), ⟨true, true, true⟩),
   (.scroll 4950 5188, ok)]

#guard (wfinal userCfg.hooks (W.init 5188) otherTrace).held == true

end Fw.Parts.ComboScroll

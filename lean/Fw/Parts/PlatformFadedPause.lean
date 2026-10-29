import Fw.Parts.MorphTween
import Fw.Parts.PlatformScene
import Fw.Parts.PlatformSweep
import Fw.Parts.PlatformSweepPause
import Fw.Parts.PlatformGlintPause
/-! # `platform:faded-pause`: pause the section's animations while its morph fade is 0 -/
namespace Fw.Parts.PlatformFadedPause
open Fw.Parts.MorphTween (fade fadeEnd)
open Fw.Parts.PlatformSweepPause (Step)

def zero (m : Rat) : Bool := decide (fade m = 0)

theorem fade_nonneg (m : Rat) : 0 ≤ fade m := by
  unfold fade
  have : min 1 (m / fadeEnd) ≤ 1 := by grind
  grind

theorem fade_pos_iff (m : Rat) : 0 < fade m ↔ m < fadeEnd := by
  have hdiv : m / fadeEnd = m * (20 / 11) := by unfold fadeEnd; grind
  unfold fade
  rw [hdiv]
  unfold fadeEnd
  by_cases h1 : 1 ≤ m * (20 / 11)
  · have : min 1 (m * (20 / 11)) = 1 := by grind
    rw [this]; grind
  · have : min 1 (m * (20 / 11)) = m * (20 / 11) := by grind
    rw [this]; grind

theorem zero_iff (m : Rat) : zero m = true ↔ fadeEnd ≤ m := by
  have h1 := fade_nonneg m
  have h2 := fade_pos_iff m
  simp only [zero, decide_eq_true_eq]
  grind

theorem pos_of_lt (m : Rat) (h : m < fadeEnd) : 0 < fade m := (fade_pos_iff m).2 h

def stepOf (d m : Rat) : Step := (d, decide (0 < fade m), zero m)

theorem stepOf_ok (d m : Rat) : Fw.Parts.PlatformSweepPause.Ok (stepOf d m) := by
  intro h
  have hz : fade m = 0 := by simpa [stepOf, zero] using h
  simp [stepOf, hz]

def over (a src dst : Rat) : Rat := dst + a * (src - dst)

def render (a src : Rat) (escaped : Option Rat) (dst : Rat) : Rat :=
  match escaped with
  | none => over a src dst
  | some e => e

theorem faded_same_pixels (m src src' dst : Rat) (hz : zero m = true) :
    render (fade m) src none dst = render (fade m) src' none dst ∧ render (fade m) src none dst = dst := by
  have h : fade m = 0 := by simpa [zero] using hz
  simp [render, over, h]
  grind [over]

theorem frame_same (o : Rat) (pre : List Step) (m d : Rat) (hphase : zero m = false) :
    (Fw.Parts.PlatformSweepPause.seek (Fw.Parts.PlatformSweepPause.run (Fw.Parts.PlatformSweepPause.init o) pre) (stepOf d m)).loc
      = Fw.Parts.PlatformSweepPause.orig o pre := by
  apply Fw.Parts.PlatformSweepPause.visible_same o pre _ (stepOf_ok d m)
  have h1 : zero m = false := hphase
  have : fade m ≠ 0 := by simpa [zero] using h1
  have : 0 < fade m := by have := fade_nonneg m; grind
  simp [stepOf, this]

open Fw.Parts.PlatformSweepPause in
def runCss (o : Rat) (tr : List (Rat × Rat)) : St := run (init o) (tr.map fun x => stepOf x.1 x.2)

def origCss (o : Rat) (tr : List (Rat × Rat)) : Rat :=
  Fw.Parts.PlatformSweepPause.orig o (tr.map fun x => stepOf x.1 x.2)

theorem visible_phase (o : Rat) (tr : List (Rat × Rat)) (m d : Rat) (hv : zero m = false) :
    Fw.Parts.PlatformSweep.phase
        (Fw.Parts.PlatformSweepPause.seek (runCss o tr) (stepOf d m)).loc
      = Fw.Parts.PlatformSweep.phase (origCss o tr) := by
  rw [runCss, origCss, frame_same o _ m d hv]

theorem faded_no_tick (d m : Rat) (hz : zero m = true) :
    Fw.Parts.PlatformSweepPause.ticks (stepOf d m) = 0 := by
  simp [Fw.Parts.PlatformSweepPause.ticks, stepOf, hz]

theorem visible_ticks (d m : Rat) (hv : zero m = false) : Fw.Parts.PlatformSweepPause.ticks (stepOf d m) = 1 := by
  simp [Fw.Parts.PlatformSweepPause.ticks, stepOf, hv]

theorem faded_run (s : Fw.Parts.PlatformSweepPause.St) (tr : List (Rat × Rat)) (h : ∀ x ∈ tr, zero x.2 = true) :
    (Fw.Parts.PlatformSweepPause.run s (tr.map fun x => stepOf x.1 x.2)).loc = s.loc := by
  apply Fw.Parts.PlatformSweepPause.reported_run
  intro f hf
  obtain ⟨x, hx, rfl⟩ := List.mem_map.1 hf
  simp [stepOf, h x hx]

open Fw.Parts.PlatformGlintPause in
def obsOf (t m : Rat) : Obs := if zero m then .hide t else .reveal t

open Fw.Parts.PlatformGlintPause in
theorem glint_phase (b : Rat) (evs : List (Rat × Rat)) :
    Same b (evs.foldl (fun p x => P.step p (obsOf x.1 x.2)) ⟨Cont.start b, -b⟩) := by
  have key : ∀ (p : P), Same b p → Same b (evs.foldl (fun p x => P.step p (obsOf x.1 x.2)) p) := by
    induction evs with
    | nil => intro p h; exact h
    | cons x xs ih => intro p h; exact ih _ (same_step b p _ h)
  exact key _ (same_start b)

open Fw.Parts.PlatformScene (attr pauses)

def scene (active faded : Bool) : String := attr (active && !faded)

theorem scene_pauses (a f : Bool) : pauses (scene a f) = (!a || f) := by
  cases a <;> cases f <;> decide

theorem scene_offscreen (f : Bool) : pauses (scene false f) = true := by cases f <;> decide

theorem scene_faded (a : Bool) : pauses (scene a true) = true := by cases a <;> decide

theorem scene_neither (a : Bool) : scene a false = attr a := by cases a <;> rfl

theorem escape_shows (m src e dst : Rat) : render (fade m) src (some e) dst = e := rfl

theorem invisible_iff (m dst : Rat) (esc : Option Rat) (hz : zero m = true) :
    (∀ src, render (fade m) src esc dst = dst) ↔ esc = none ∨ esc = some dst := by
  cases esc with
  | none => simpa using fun src => (faded_same_pixels m src src dst hz).2
  | some e => simp [render]

inductive Ev where
  | tick (d : Rat)
  | obs (active : Bool)
  | fade (zero : Bool)
deriving DecidableEq, Repr

structure OrigClk where
  t : Rat
  cur : Rat
  active : Bool
deriving DecidableEq, Repr

def OrigClk.step (o : OrigClk) : Ev → OrigClk
  | .tick d => { o with t := o.t + d, cur := if o.active then o.cur + d else o.cur }
  | .obs a => { o with active := a }
  | .fade _ => o

structure FlagClk where
  t : Rat
  cur : Rat
  active : Bool
  faded : Bool
  saved : Option Rat
deriving DecidableEq, Repr

def FlagClk.runs (s : FlagClk) : Bool := s.active && !s.faded

def FlagClk.restore (s : FlagClk) : FlagClk :=
  if s.runs then
    match s.saved with
    | some st => { s with cur := s.t - st, saved := none }
    | none => s
  else s

def FlagClk.save (dur : Rat) (s : FlagClk) : Option Rat :=
  if s.runs && decide (s.cur < dur) then some (s.t - s.cur) else none

def FlagClk.step (dur : Rat) (s : FlagClk) : Ev → FlagClk
  | .tick d => { s with t := s.t + d, cur := if s.runs then s.cur + d else s.cur }
  | .obs a => FlagClk.restore { s with active := a }
  | .fade z =>
    if z == s.faded then s
    else FlagClk.restore { s with faded := z, saved := if z then s.save dur else s.saved }

def allowed (s : FlagClk) : Ev → Bool
  | .tick d => decide (0 ≤ d)
  | .obs a => a || !s.faded
  | .fade z => !z || s.faded || s.active

def Allowed (dur : Rat) : FlagClk → List Ev → Prop
  | _, [] => True
  | s, e :: es => allowed s e = true ∧ Allowed dur (s.step dur e) es

def Same (dur a b : Rat) : Prop := a = b ∨ (dur ≤ a ∧ dur ≤ b)

def shown (dur c : Rat) : Rat := min c dur

def Inv (dur : Rat) (o : OrigClk) (s : FlagClk) : Prop :=
  s.t = o.t ∧ s.active = o.active ∧ (s.faded = true → s.active = true) ∧
  (s.faded = false → Same dur s.cur o.cur ∧ s.saved = none) ∧
  (s.faded = true → (∃ st, s.saved = some st ∧ o.t - st = o.cur) ∨ (s.saved = none ∧ dur ≤ s.cur ∧ dur ≤ o.cur))

theorem start_inv (dur : Rat) : Inv dur ⟨0, 0, true⟩ ⟨0, 0, true, false, none⟩ := by
  simp [Inv, Same]

theorem step_inv (dur : Rat) (o : OrigClk) (s : FlagClk) (e : Ev) (hI : Inv dur o s) (ha : allowed s e = true) :
    Inv dur (o.step e) (s.step dur e) := by
  obtain ⟨ht, hact, hfa, hun, hfd⟩ := hI
  rcases s with ⟨t, cur, active, faded, saved⟩
  rcases o with ⟨ot, ocur, oactive⟩
  simp only at ht hact hfa hun hfd
  subst ht hact
  cases e with
  | tick d =>
    have hd : 0 ≤ d := by simpa [allowed] using ha
    cases faded <;> cases active <;>
      simp_all [Inv, OrigClk.step, FlagClk.step, FlagClk.runs, Same] <;> grind
  | obs a =>
    cases faded <;> cases active <;> cases a <;>
      simp_all [Inv, OrigClk.step, FlagClk.step, FlagClk.restore, FlagClk.runs, allowed]
  | fade z =>
    cases faded <;> cases z <;> cases active <;>
      simp_all [Inv, OrigClk.step, FlagClk.step, FlagClk.restore, FlagClk.runs, FlagClk.save, allowed, Same] <;>
      first
        | (rcases hfd with ⟨st, rfl, h⟩ | ⟨rfl, h1, h2⟩ <;> simp_all <;> grind)
        | (by_cases hc : cur < dur <;> simp_all <;> grind)
        | grind

theorem run_inv (dur : Rat) (o : OrigClk) (s : FlagClk) (evs : List Ev) (hI : Inv dur o s) (hA : Allowed dur s evs) :
    Inv dur (evs.foldl OrigClk.step o) (evs.foldl (FlagClk.step dur) s) := by
  induction evs generalizing o s with
  | nil => exact hI
  | cons e es ih => exact ih _ _ (step_inv dur o s e hI hA.1) hA.2

theorem shown_eq (dur a b : Rat) (h : Same dur a b) : shown dur a = shown dur b := by
  rcases h with rfl | ⟨h1, h2⟩
  · rfl
  · unfold shown
    grind

theorem resume_phase (dur : Rat) (evs : List Ev) (hA : Allowed dur ⟨0, 0, true, false, none⟩ evs)
    (hv : (evs.foldl (FlagClk.step dur) ⟨0, 0, true, false, none⟩).faded = false) :
    shown dur (evs.foldl (FlagClk.step dur) ⟨0, 0, true, false, none⟩).cur
      = shown dur (evs.foldl OrigClk.step ⟨0, 0, true⟩).cur :=
  shown_eq dur _ _ ((run_inv dur _ _ evs (start_inv dur) hA).2.2.2.1 hv).1

theorem settled_skipped (dur : Rat) (s : FlagClk) (h : dur ≤ s.cur) : s.save dur = none := by
  have : ¬ s.cur < dur := by grind
  simp [FlagClk.save, this]

theorem restore_skips (s : FlagClk) (h : s.saved = none) : s.restore = s := by
  unfold FlagClk.restore
  split <;> simp_all

structure Writer where
  active : Bool
  faded : Bool
  attr : Option String
  writes : Nat
deriving DecidableEq, Repr

def Writer.write (w : Writer) : Writer := { w with attr := some (scene w.active w.faded), writes := w.writes + 1 }

def Writer.setActive (w : Writer) (a : Bool) : Writer := Writer.write { w with active := a }

def Writer.setFaded (w : Writer) (f : Bool) : Writer := if f == w.faded then w else Writer.write { w with faded := f }

def Writer.Ok (w : Writer) : Prop := w.attr = none ∨ w.attr = some (scene w.active w.faded)

theorem setActive_ok (w : Writer) (a : Bool) : (w.setActive a).Ok := Or.inr rfl

theorem setFaded_ok (w : Writer) (f : Bool) (h : w.Ok) : (w.setFaded f).Ok := by
  unfold Writer.setFaded
  split
  · exact h
  · exact Or.inr rfl

theorem writer_or (w : Writer) (h : w.Ok) (v : String) (hv : w.attr = some v) : pauses v = (!w.active || w.faded) := by
  rcases h with h | h
  · simp [h] at hv
  · rw [h] at hv
    cases hv
    exact scene_pauses _ _

theorem setFaded_same (w : Writer) (f : Bool) (h : f = w.faded) : w.setFaded f = w := by
  simp [Writer.setFaded, h]

theorem setFaded_idem (w : Writer) (f : Bool) : (w.setFaded f).setFaded f = w.setFaded f := by
  unfold Writer.setFaded
  split <;> simp_all [Writer.write]

theorem setActive_idem (w : Writer) (a : Bool) :
    ((w.setActive a).setActive a).attr = (w.setActive a).attr ∧
      ((w.setActive a).setActive a).active = (w.setActive a).active ∧
      ((w.setActive a).setActive a).faded = (w.setActive a).faded := by
  simp [Writer.setActive, Writer.write]

theorem writer_order_free (w : Writer) (a f : Bool) :
    ((w.setActive a).setFaded f).attr = some (scene a f) ∧ ((w.setFaded f).setActive a).attr = some (scene a f) := by
  unfold Writer.setFaded
  constructor <;> split <;> simp_all [Writer.setActive, Writer.write]

theorem setFaded_writes (w : Writer) (f : Bool) :
    (w.setFaded f).writes = w.writes + (if f == w.faded then 0 else 1) := by
  unfold Writer.setFaded
  split <;> simp_all [Writer.write]

#guard ((([Ev.fade true, .tick 5, .fade false] : List Ev).foldl (FlagClk.step 10) ⟨0, 0, true, false, none⟩).cur,
  (([Ev.fade true, .tick 5, .fade false] : List Ev).foldl OrigClk.step ⟨0, 0, true⟩).cur) == ((5 : Rat), (5 : Rat))
#guard ((([Ev.tick 12, .fade true, .tick 5, .fade false] : List Ev).foldl (FlagClk.step 10) ⟨0, 0, true, false, none⟩).cur,
  (([Ev.tick 12, .fade true, .tick 5, .fade false] : List Ev).foldl OrigClk.step ⟨0, 0, true⟩).cur) == ((12 : Rat), (17 : Rat))
#guard ((([Ev.fade true, .obs false, .tick 5, .obs true, .fade false] : List Ev).foldl (FlagClk.step 10)
  ⟨0, 0, true, false, none⟩).cur, (([Ev.fade true, .obs false, .tick 5, .obs true, .fade false] : List Ev).foldl
  OrigClk.step ⟨0, 0, true⟩).cur) == ((5 : Rat), (0 : Rat))
#guard !allowed ⟨0, 0, true, true, some 0⟩ (.obs false)
#guard !allowed ⟨0, 0, false, false, none⟩ (.fade true)
#guard allowed ⟨0, 0, false, true, none⟩ (.fade false)
#guard (((⟨true, false, none, 0⟩ : Writer).setFaded true).setFaded true).writes == 1
#guard (((⟨true, false, none, 0⟩ : Writer).setActive false).setFaded true).attr == some "paused"
#guard (((⟨true, false, none, 0⟩ : Writer).setFaded true).setFaded false).attr == some "active"

#guard scene true false == "active"
#guard scene true true == "paused"
#guard scene false false == "paused"
#guard scene false true == "paused"
#guard zero (11/20) && !zero (1/2)

end Fw.Parts.PlatformFadedPause

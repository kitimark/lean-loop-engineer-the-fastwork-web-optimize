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

#guard scene true false == "active"
#guard scene true true == "paused"
#guard scene false false == "paused"
#guard scene false true == "paused"
#guard zero (11/20) && !zero (1/2)

end Fw.Parts.PlatformFadedPause

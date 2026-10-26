import Fw.Parts.MorphTween
import Fw.Parts.PlatformScene
import Fw.Parts.PlatformSweep
import Fw.Parts.PlatformSweepPause
import Fw.Parts.PlatformGlintPause
/-!
# `platform:faded-pause`: pause the section's animations while its morph fade is 0

The section's opacity is `fade m` (`--morph-fade`). From `m = 0.55` on the fade is 0 and the section's whole subtree is
composited to nothing, but the engine still records and rasters it. The variant sets `data-fw-scene=paused` (the
existing CSS rule pauses CSS animations and drops `will-change`) and pauses the dash SVG clocks while the fade is 0,
and seeks both back to the uninterrupted phase when the fade rises above 0.

Three claims are proved here:
* `faded_same_pixels`: at fade 0 no pixel of the subtree reaches the page, whatever phase it holds;
* `visible_phase`, `glint_phase`: whenever the fade is above 0 the CSS clock and the SMIL clock read the faithful phase;
* `scene_*`: the one `data-fw-scene` writer ORs the observer's pause and the faded pause, one theorem per branch.
-/
namespace Fw.Parts.PlatformFadedPause
open Fw.Parts.MorphTween (fade fadeEnd)
open Fw.Parts.PlatformSweepPause (Step)

/-! ## The fade is 0 exactly from `fadeEnd` on -/

/-- The pause condition: the section's fade is 0. -/
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

/-- Below `fadeEnd` the fade is above 0 (the section is visible). -/
theorem pos_of_lt (m : Rat) (h : m < fadeEnd) : 0 < fade m := (fade_pos_iff m).2 h

/-- The reporter frame for a morph value: visible iff the fade is above 0, reported iff it is 0. -/
def stepOf (d m : Rat) : Step := (d, decide (0 < fade m), zero m)

/-- The model's `Ok`: a reported frame is not visible. -/
theorem stepOf_ok (d m : Rat) : Fw.Parts.PlatformSweepPause.Ok (stepOf d m) := by
  intro h
  have hz : fade m = 0 := by simpa [stepOf, zero] using h
  simp [stepOf, hz]

/-! ## No pixel at fade 0 -/

/-- One channel of a group composite: `dst` below, group colour `src`, group opacity `a`. -/
def over (a src dst : Rat) : Rat := dst + a * (src - dst)

/-- What the page shows for the section: the group colour through the group's opacity, unless a descendant escapes the
group (top layer, backdrop) and paints `e` over the result. The census test pins `escaped = none`. -/
def render (a src : Rat) (escaped : Option Rat) (dst : Rat) : Rat :=
  match escaped with
  | none => over a src dst
  | some e => e

/-- At fade 0 the page pixel is the backdrop, for every phase of the subtree and every colour it holds. -/
theorem faded_same_pixels (m src src' dst : Rat) (hz : zero m = true) :
    render (fade m) src none dst = render (fade m) src' none dst ∧ render (fade m) src none dst = dst := by
  have h : fade m = 0 := by simpa [zero] using hz
  simp [render, over, h]
  grind [over]

/-- A frame is the same as the faithful one: either nothing shows (fade 0, any phase), or the phase is the faithful one. -/
theorem frame_same (o : Rat) (pre : List Step) (m d : Rat) (hphase : zero m = false) :
    (Fw.Parts.PlatformSweepPause.seek (Fw.Parts.PlatformSweepPause.run (Fw.Parts.PlatformSweepPause.init o) pre) (stepOf d m)).loc
      = Fw.Parts.PlatformSweepPause.orig o pre := by
  apply Fw.Parts.PlatformSweepPause.visible_same o pre _ (stepOf_ok d m)
  have h1 : zero m = false := hphase
  have : fade m ≠ 0 := by simpa [zero] using h1
  have : 0 < fade m := by have := fade_nonneg m; grind
  simp [stepOf, this]

/-! ## Resume phase -/

open Fw.Parts.PlatformSweepPause in
/-- The CSS clock after a trace of `(length, morph value)` frames, with the faded pause as the reporter. -/
def runCss (o : Rat) (tr : List (Rat × Rat)) : St := run (init o) (tr.map fun x => stepOf x.1 x.2)

/-- The uninterrupted phase after the same frames. -/
def origCss (o : Rat) (tr : List (Rat × Rat)) : Rat :=
  Fw.Parts.PlatformSweepPause.orig o (tr.map fun x => stepOf x.1 x.2)

/-- Every frame with fade above 0 reads the faithful CSS phase, after any history of faded pauses (`frame_same`
restated on the trace; the sweep's `visible_phase` gives the wrapped phase and position too). -/
theorem visible_phase (o : Rat) (tr : List (Rat × Rat)) (m d : Rat) (hv : zero m = false) :
    Fw.Parts.PlatformSweep.phase
        (Fw.Parts.PlatformSweepPause.seek (runCss o tr) (stepOf d m)).loc
      = Fw.Parts.PlatformSweep.phase (origCss o tr) := by
  rw [runCss, origCss, frame_same o _ m d hv]

/-- At fade 0 the faded frames do not tick the CSS animations; the faithful arm ticks once per frame. -/
theorem faded_no_tick (d m : Rat) (hz : zero m = true) :
    Fw.Parts.PlatformSweepPause.ticks (stepOf d m) = 0 := by
  simp [Fw.Parts.PlatformSweepPause.ticks, stepOf, hz]

theorem visible_ticks (d m : Rat) (hv : zero m = false) : Fw.Parts.PlatformSweepPause.ticks (stepOf d m) = 1 := by
  simp [Fw.Parts.PlatformSweepPause.ticks, stepOf, hv]

/-- A run of faded frames leaves the CSS clock where it was (the seek on the first visible frame restores it). -/
theorem faded_run (s : Fw.Parts.PlatformSweepPause.St) (tr : List (Rat × Rat)) (h : ∀ x ∈ tr, zero x.2 = true) :
    (Fw.Parts.PlatformSweepPause.run s (tr.map fun x => stepOf x.1 x.2)).loc = s.loc := by
  apply Fw.Parts.PlatformSweepPause.reported_run
  intro f hf
  obtain ⟨x, hx, rfl⟩ := List.mem_map.1 hf
  simp [stepOf, h x hx]

open Fw.Parts.PlatformGlintPause in
/-- The SMIL observation for a morph value at time `t`: hide at fade 0, reveal otherwise. -/
def obsOf (t m : Rat) : Obs := if zero m then .hide t else .reveal t

open Fw.Parts.PlatformGlintPause in
/-- The dash svgs' clock: after any run of fade changes the clock the glint pause drives still reads the uninterrupted
time whenever it is running (`same_run`, with the faded reporter). -/
theorem glint_phase (b : Rat) (evs : List (Rat × Rat)) :
    Same b (evs.foldl (fun p x => P.step p (obsOf x.1 x.2)) ⟨Cont.start b, -b⟩) := by
  have key : ∀ (p : P), Same b p → Same b (evs.foldl (fun p x => P.step p (obsOf x.1 x.2)) p) := by
    induction evs with
    | nil => intro p h; exact h
    | cons x xs ih => intro p h; exact ih _ (same_step b p _ h)
  exact key _ (same_start b)

/-! ## One writer for `data-fw-scene` -/

open Fw.Parts.PlatformScene (attr pauses)

/-- The writer's value: paused when the observer says offscreen or the section is faded. -/
def scene (active faded : Bool) : String := attr (active && !faded)

theorem scene_pauses (a f : Bool) : pauses (scene a f) = (!a || f) := by
  cases a <;> cases f <;> decide

/-- Observer branch: an inactive section is paused whatever the fade. -/
theorem scene_offscreen (f : Bool) : pauses (scene false f) = true := by cases f <;> decide

/-- Faded branch: a faded section is paused whatever the observer says. -/
theorem scene_faded (a : Bool) : pauses (scene a true) = true := by cases a <;> decide

/-- Neither branch: with the fade above 0 the value is the faithful observer value. -/
theorem scene_neither (a : Bool) : scene a false = attr a := by cases a <;> rfl

#guard scene true false == "active"
#guard scene true true == "paused"
#guard scene false false == "paused"
#guard scene false true == "paused"
#guard zero (11/20) && !zero (1/2)

end Fw.Parts.PlatformFadedPause

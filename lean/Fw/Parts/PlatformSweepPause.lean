import Fw.Parts.PlatformSweep
/-!
# `platform.sweep:offscreen-pause`: the sweep stops ticking while its element is offscreen, and shows the same phase

An observer reports whether each sweep element is offscreen. While it is, the variant pauses the animation (no tick of the
animation each frame). When the element returns, the variant seeks the animation to the document timeline's time (plus
the animation's fixed start offset), so the phase is the one an uninterrupted animation shows. Same pattern as
`HiddenPausePlatform` (seek on resume), with a simpler clock: the document timeline runs always.

Premises about the engine, not proved here:
* `Ok`: an element the observer reports offscreen is offscreen (no false positive on a frame).
* `Lag` (named premise): the observer reports an element after the frame it leaves, so only that first offscreen frame
  can still tick.
-/
namespace Fw.Parts.PlatformSweepPause
open Fw.Parts.PlatformSweep (phase pos)

/-- One frame: its length in ms, whether the element intersects the viewport (`vis`) and whether the observer reports it
offscreen (`rep`, which pauses the animation).

A frame is a duration, a visibility flag and a report flag. -/
abbrev Step := Rat × Bool × Bool

/-- A frame the observer can report: an element it reports offscreen is not visible.

Reporting `rep` implies `vis = false`. -/
def Ok (f : Step) : Prop := f.2.2 = true → f.2.1 = false

/-- The variant's state: the animation's current time, the document timeline's time, whether it is paused, and the
animation's start offset (fixed).

Local time is what the animation shows; the clock always runs. -/
structure St where
  loc : Rat
  clk : Rat
  paused : Bool
  off : Rat
deriving Repr

/-- The start state: timeline at 0, the animation at its offset, running.

An element mounted with the page. -/
def init (o : Rat) : St := ⟨o, 0, false, o⟩

/-- The observer callbacks at a frame's start: a report pauses; the first frame without one after a pause seeks the
animation to the timeline's time plus its offset; otherwise nothing changes.

A pause keeps the animation's time; a resume jumps it to the uninterrupted time. -/
def seek (s : St) (f : Step) : St :=
  if f.2.2 then { s with paused := true }
  else if s.paused then { s with paused := false, loc := s.clk + s.off } else s

/-- The frame's time passes: the timeline always advances; the animation only when not reported offscreen.

An animation tick is a frame where the animation moves. -/
def tick (s : St) (f : Step) : St :=
  { s with clk := s.clk + f.1, loc := if f.2.2 then s.loc else s.loc + f.1 }

/-- One variant frame: callbacks, then the frame's time.

The observer runs before the frame's time passes. -/
def step (s : St) (f : Step) : St := tick (seek s f) f

/-- The variant after a frame list.

The empty list leaves the state as it is. -/
def run (s : St) (tr : List Step) : St := tr.foldl step s

/-- The animation ticks on a frame: it moves exactly when the frame is not reported offscreen.

Counts the cost the variant removes. -/
def ticks (f : Step) : Nat := if f.2.2 then 0 else 1

/-- The original's animation time after the frames: the start offset plus the elapsed timeline time.

The original never pauses. -/
def orig (o : Rat) (tr : List Step) : Rat := o + (tr.map (·.1)).sum

#guard (run (init 100) [(16, true, false), (16, false, false), (16, false, true), (16, false, true), (16, true, false)]).loc
  == orig 100 [(16, true, false), (16, false, false), (16, false, true), (16, false, true), (16, true, false)]
#guard (seek ⟨7, 50, true, 3⟩ (16, true, false)).loc == 53
#guard (seek ⟨7, 50, false, 3⟩ (16, true, false)).loc == 7
#guard ticks (16, false, true) == 0 && ticks (16, true, false) == 1

/-- The invariant: the clock is the elapsed time, and a running animation is at the original's time.

`c` is the elapsed timeline time. -/
def Inv (s : St) (c : Rat) : Prop := s.clk = c ∧ (s.paused = false → s.loc = c + s.off)

/-- The start state satisfies the invariant.

The animation begins at its offset. -/
theorem init_inv (o : Rat) : Inv (init o) 0 := by
  simp [Inv, init]
  grind

/-- After the callbacks of an unreported frame, the animation is at the original's time.

A resume seeks; a running animation already is. -/
theorem seek_shown (s : St) (c : Rat) (f : Step) (hI : Inv s c) (hh : f.2.2 = false) :
    (seek s f).loc = c + s.off := by
  obtain ⟨h0, h1⟩ := hI
  unfold seek
  rw [hh]
  cases hs : s.paused
  · simpa using h1 hs
  · simp [h0]

/-- One frame keeps the invariant, and the offset is never changed.

Each frame advances the clock and a running animation by the same amount. -/
theorem step_inv (s : St) (c : Rat) (f : Step) (hI : Inv s c) : Inv (step s f) (c + f.1) ∧ (step s f).off = s.off := by
  obtain ⟨h0, h1⟩ := hI
  obtain ⟨d, v, r⟩ := f
  unfold step seek tick Inv
  cases r <;> cases hs : s.paused <;> simp_all <;> grind

/-- The invariant holds after any frame list.

Variant and original stay in sync over the whole trace. -/
theorem run_inv (s : St) (c : Rat) (tr : List Step) (hI : Inv s c) :
    Inv (run s tr) (c + (tr.map (·.1)).sum) ∧ (run s tr).off = s.off := by
  induction tr generalizing s c with
  | nil =>
    have : c + ((([] : List Step).map (·.1)).sum) = c := by simp; grind
    rw [this]; exact ⟨hI, rfl⟩
  | cons f tr ih =>
    obtain ⟨h1, h2⟩ := step_inv s c f hI
    obtain ⟨h3, h4⟩ := ih (step s f) (c + f.1) h1
    refine ⟨?_, by simpa [run, h2] using h4⟩
    have : c + ((f :: tr).map (·.1)).sum = c + f.1 + (tr.map (·.1)).sum := by simp only [List.map_cons, List.sum_cons]; grind
    rw [this]
    exact h3

/-- **Same phase on every visible frame.** After the callbacks of any frame that is not reported offscreen (in particular
every visible frame of an `Ok` trace), the variant's animation time is the original's, for any frames before it.

Whatever happened before, the frame shows the uninterrupted time. -/
theorem shown_same (o : Rat) (pre : List Step) (f : Step) (hh : f.2.2 = false) :
    (seek (run (init o) pre) f).loc = orig o pre := by
  obtain ⟨hI, hoff⟩ := run_inv (init o) 0 pre (init_inv o)
  rw [seek_shown _ _ f hI hh, hoff]
  simp [orig, init]; grind

/-- A visible frame of an `Ok` trace is not reported, so it shows the original's time.

The `Ok` premise turns `vis` into the report flag. -/
theorem visible_same (o : Rat) (pre : List Step) (f : Step) (hok : Ok f) (hv : f.2.1 = true) :
    (seek (run (init o) pre) f).loc = orig o pre := by
  apply shown_same
  cases h : f.2.2
  · rfl
  · have := hok h; simp_all

/-- The phase shown on a visible frame equals the uninterrupted phase, and so does the background position.

The look (`pos`) is a function of the phase. -/
theorem visible_phase (o : Rat) (pre : List Step) (f : Step) (hok : Ok f) (hv : f.2.1 = true) :
    phase (seek (run (init o) pre) f).loc = phase (orig o pre) ∧
    pos (seek (run (init o) pre) f).loc = pos (orig o pre) := by
  rw [visible_same o pre f hok hv]; exact ⟨rfl, rfl⟩

/-- **No tick offscreen.** A frame reported offscreen leaves the animation's time unchanged and counts no tick.

The animation is paused: only the timeline moves. -/
theorem reported_no_tick (s : St) (f : Step) (hr : f.2.2 = true) : (step s f).loc = s.loc ∧ ticks f = 0 := by
  simp [step, seek, tick, hr, ticks]

/-- Reported frames in a row leave the animation's time unchanged.

The whole offscreen stretch costs no animation tick. -/
theorem reported_run (s : St) (tr : List Step) (h : ∀ f ∈ tr, f.2.2 = true) : (run s tr).loc = s.loc := by
  induction tr generalizing s with
  | nil => rfl
  | cons f tr ih =>
    have := (reported_no_tick s f (h f (by simp))).1
    simpa [run, this] using ih (step s f) (fun g hg => h g (by simp [hg]))

/-- The premise `Lag`: after a frame offscreen, the next frame offscreen is reported.

The observer reports an element after the frame it leaves (named premise about the engine). -/
def Lag (p f : Step) : Prop := p.2.1 = false → f.2.1 = false → f.2.2 = true

/-- Ticks over a frame list.

The total number of frames where the animation moves. -/
def totalTicks (tr : List Step) : Nat := (tr.map ticks).sum

/-- The premise on a list: each frame is `Lag`-related to its predecessor.

A list `g :: rest` where consecutive frames satisfy `Lag`. -/
def LagList : Step → List Step → Prop
  | _, [] => True
  | p, f :: tr => Lag p f ∧ LagList f tr

/-- **An offscreen stretch ticks at most once.** For frames all offscreen with the observer's `Lag`, only the first can
tick; every later frame is reported and counts none.

This is the leaving frame: it is the only one the observer has not yet reported. -/
theorem offscreen_ticks_le_one (g : Step) (rest : List Step) (hv : g.2.1 = false ∧ ∀ f ∈ rest, f.2.1 = false)
    (hl : LagList g rest) : totalTicks (g :: rest) ≤ 1 := by
  have key : ∀ (p : Step) (tr : List Step), p.2.1 = false → (∀ f ∈ tr, f.2.1 = false) → LagList p tr →
      totalTicks tr = 0 := by
    intro p tr
    induction tr generalizing p with
    | nil => intros; rfl
    | cons f tr ih =>
      intro hp hf hl
      have hr : f.2.2 = true := hl.1 hp (hf f (by simp))
      have := ih f (hf f (by simp)) (fun g hg => hf g (by simp [hg])) hl.2
      simp [totalTicks, ticks, hr] at this ⊢
      exact this
  have := key g rest hv.1 hv.2 hl
  simp only [totalTicks, List.map_cons, List.sum_cons] at this ⊢
  have h0 : ticks g ≤ 1 := by unfold ticks; split <;> omega
  omega

/-- The variant never ticks more than the original, frame by frame.

The original ticks every frame. -/
theorem ticks_le_original (f : Step) : ticks f ≤ 1 := by unfold ticks; split <;> omega

end Fw.Parts.PlatformSweepPause

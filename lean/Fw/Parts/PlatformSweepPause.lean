import Fw.Parts.PlatformSweep
/-!
# `platform.sweep:offscreen-pause`: the sweep stops ticking while its element is offscreen, and shows the same phase

Named premise `Running` (TS guard, not proved about the engine): `seek` pauses only an animation that is running with a start
time. A play still pending (`playState` running, `startTime` null) has no saved start time to restore, so the watcher leaves it running;
`shown_same` and `Ok` are stated for the animations the watcher does pause.
-/
namespace Fw.Parts.PlatformSweepPause
open Fw.Parts.PlatformSweep (phase pos)

/-- A frame: length in ms, visible, reported offscreen. -/
abbrev Step := Rat × Bool × Bool

def Ok (f : Step) : Prop := f.2.2 = true → f.2.1 = false

structure St where
  loc : Rat
  clk : Rat
  paused : Bool
  off : Rat
deriving Repr

def init (o : Rat) : St := ⟨o, 0, false, o⟩

def seek (s : St) (f : Step) : St :=
  if f.2.2 then { s with paused := true }
  else if s.paused then { s with paused := false, loc := s.clk + s.off } else s

def tick (s : St) (f : Step) : St :=
  { s with clk := s.clk + f.1, loc := if f.2.2 then s.loc else s.loc + f.1 }

def step (s : St) (f : Step) : St := tick (seek s f) f

def run (s : St) (tr : List Step) : St := tr.foldl step s

def ticks (f : Step) : Nat := if f.2.2 then 0 else 1

def orig (o : Rat) (tr : List Step) : Rat := o + (tr.map (·.1)).sum

#guard (run (init 100) [(16, true, false), (16, false, false), (16, false, true), (16, false, true), (16, true, false)]).loc
  == orig 100 [(16, true, false), (16, false, false), (16, false, true), (16, false, true), (16, true, false)]
#guard (seek ⟨7, 50, true, 3⟩ (16, true, false)).loc == 53
#guard (seek ⟨7, 50, false, 3⟩ (16, true, false)).loc == 7
#guard ticks (16, false, true) == 0 && ticks (16, true, false) == 1

def Inv (s : St) (c : Rat) : Prop := s.clk = c ∧ (s.paused = false → s.loc = c + s.off)

theorem init_inv (o : Rat) : Inv (init o) 0 := by
  simp [Inv, init]
  grind

theorem seek_shown (s : St) (c : Rat) (f : Step) (hI : Inv s c) (hh : f.2.2 = false) :
    (seek s f).loc = c + s.off := by
  obtain ⟨h0, h1⟩ := hI
  unfold seek
  rw [hh]
  cases hs : s.paused
  · simpa using h1 hs
  · simp [h0]

theorem step_inv (s : St) (c : Rat) (f : Step) (hI : Inv s c) : Inv (step s f) (c + f.1) ∧ (step s f).off = s.off := by
  obtain ⟨h0, h1⟩ := hI
  obtain ⟨d, v, r⟩ := f
  unfold step seek tick Inv
  cases r <;> cases hs : s.paused <;> simp_all <;> grind

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

theorem shown_same (o : Rat) (pre : List Step) (f : Step) (hh : f.2.2 = false) :
    (seek (run (init o) pre) f).loc = orig o pre := by
  obtain ⟨hI, hoff⟩ := run_inv (init o) 0 pre (init_inv o)
  rw [seek_shown _ _ f hI hh, hoff]
  simp [orig, init]; grind

theorem visible_same (o : Rat) (pre : List Step) (f : Step) (hok : Ok f) (hv : f.2.1 = true) :
    (seek (run (init o) pre) f).loc = orig o pre := by
  apply shown_same
  cases h : f.2.2
  · rfl
  · have := hok h; simp_all

theorem visible_phase (o : Rat) (pre : List Step) (f : Step) (hok : Ok f) (hv : f.2.1 = true) :
    phase (seek (run (init o) pre) f).loc = phase (orig o pre) ∧
    pos (seek (run (init o) pre) f).loc = pos (orig o pre) := by
  rw [visible_same o pre f hok hv]; exact ⟨rfl, rfl⟩

theorem reported_no_tick (s : St) (f : Step) (hr : f.2.2 = true) : (step s f).loc = s.loc ∧ ticks f = 0 := by
  simp [step, seek, tick, hr, ticks]

theorem reported_run (s : St) (tr : List Step) (h : ∀ f ∈ tr, f.2.2 = true) : (run s tr).loc = s.loc := by
  induction tr generalizing s with
  | nil => rfl
  | cons f tr ih =>
    have := (reported_no_tick s f (h f (by simp))).1
    simpa [run, this] using ih (step s f) (fun g hg => h g (by simp [hg]))

def Lag (p f : Step) : Prop := p.2.1 = false → f.2.1 = false → f.2.2 = true

def totalTicks (tr : List Step) : Nat := (tr.map ticks).sum

def LagList : Step → List Step → Prop
  | _, [] => True
  | p, f :: tr => Lag p f ∧ LagList f tr

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

theorem ticks_le_original (f : Step) : ticks f ≤ 1 := by unfold ticks; split <;> omega

end Fw.Parts.PlatformSweepPause

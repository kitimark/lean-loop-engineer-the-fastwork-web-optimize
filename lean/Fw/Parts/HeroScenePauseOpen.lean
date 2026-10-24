import Fw.Gate.Trajectory
/-!
# hero scene pause: the open@1 coverage of the recorded trajectory runs

The probe now judges open@1 against the original's first frame (`Fw.Gate.Trajectory.byMFirst`). This module
replays the three recorded `?fw=hero:scene-pause` runs (Chromium, 390 px, path morph) through that rule.
-/
namespace Fw.Parts.HeroScenePauseOpen
open Fw.Gate.Trajectory

/-- One recorded run: reps (of 5) with an open@1 sample in the original, faithful and candidate arms. -/
structure OpenRun where
  run : String
  original : Nat
  faithful : Nat
  candidate : Nat
  deriving DecidableEq, Repr

/-- The three flagged runs of `research/notes/2026/10-20-hero-pause-rule.md` (MEASURED). -/
def recorded : List OpenRun :=
  [⟨"39548822269", 0, 2, 0⟩, ⟨"39553952680", 0, 1, 0⟩, ⟨"39556935431", 0, 0, 0⟩]

/-- The run's lane under the current rule: the candidate and the faithful arm, each against the original. -/
def laneNow (r : OpenRun) : Lane :=
  openLane (passesWith 5 r.original) (passesWith 5 r.candidate) (passesWith 5 r.faithful)

#guard recorded.map laneNow == [.clean, .clean, .clean]
#guard firstCover 5 0 5 == .late

/-- The original's own open@1 sample is missing in every rep, so the candidate's missing one is late, never a fail. -/
theorem recorded_open_late : ∀ r ∈ recorded,
    openAt (passesWith 5 r.original) (passesWith 5 r.candidate) = .skip .firstLate := by decide +kernel

theorem recorded_clean : ∀ r ∈ recorded, laneNow r = .clean := by decide +kernel

/-- A candidate with no open@1 sample is red only when the original has one in at least 4 of 5 reps. -/
theorem red_needs_original : ∀ k, k < 6 → (firstCover 5 k 5 = .missing ↔ 4 ≤ k) := by decide +kernel

end Fw.Parts.HeroScenePauseOpen

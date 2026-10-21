/-! Fw.Gate.Frames: when a frame strip is usable for a visual review (task earn-look-review-webkit). -/

namespace Fw.Gate.Frames

/-- Fewest shots an arm needs in one push for its strip to show the motion. -/
def minShots : Nat := 10

/-- A strip is usable iff both arms have at least `minShots` shots in that push. -/
def usable (faithful flag : Nat) : Bool := minShots ≤ faithful && minShots ≤ flag

theorem usable_iff (f g : Nat) : usable f g = true ↔ minShots ≤ min f g := by
  simp [usable, Nat.le_min]

theorem usable_of_both (f g : Nat) (hf : minShots ≤ f) (hg : minShots ≤ g) : usable f g = true := by
  simp [usable, hf, hg]

theorem not_usable_faithful (f g : Nat) (h : f < minShots) : usable f g = false := by
  simp [usable, Nat.not_le.mpr h]

theorem not_usable_flag (f g : Nat) (h : g < minShots) : usable f g = false := by
  simp [usable, Nat.not_le.mpr h]

theorem usable_comm (f g : Nat) : usable f g = usable g f := by
  simp [usable, Bool.and_comm]

#guard usable 35 36 && usable 10 10 && usable 17 19
#guard !usable 1 4 && !usable 9 10 && !usable 10 9 && !usable 2 7

end Fw.Gate.Frames

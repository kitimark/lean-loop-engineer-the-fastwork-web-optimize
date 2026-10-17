import Fw
open Fw

/-- G1 (verification run): legacy >34 ms count minus tick≥5 count = frames in (34000, 37499]. -/
theorem G1 (xs : List Nat) :
    Frames.countAbove 34000 xs - (xs.filter (5 ≤ Frames.tick ·)).length
      = (xs.filter (fun x => 34000 < x ∧ x ≤ 37499)).length := by
  induction xs with
  | nil => simp [Frames.countAbove]
  | cons x xs ih =>
    have hk := Frames.tick_ge5_iff x
    have hle : (xs.filter (5 ≤ Frames.tick ·)).length ≤ Frames.countAbove 34000 xs := by
      rw [Frames.tick5_eq_countAbove]; exact Frames.countAbove_antitone (by omega) xs
    simp only [Frames.countAbove] at hle ih ⊢
    rw [List.filter_cons, List.filter_cons, List.filter_cons]
    split <;> split <;> split <;> simp_all [List.length_cons] <;> omega

open Fw.Verdict in
theorem better_sound_higher {ctl var : List Int} (h : verdict .higher ctl var = .better) :
    ∀ y ∈ var, ∀ x ∈ ctl, x < y := by
  rw [verdict_higher_eq_lower_neg] at h
  intro y hy x hx
  have := better_sound h (-y) (List.mem_map.mpr ⟨y, hy, rfl⟩) (-x) (List.mem_map.mpr ⟨x, hx, rfl⟩)
  omega

#print axioms G1
#print axioms better_sound_higher

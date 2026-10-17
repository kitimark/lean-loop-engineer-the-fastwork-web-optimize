/-!
# Frame-time units (protocol v2 §3.2)

Frame intervals are integer microseconds (Nat), never `Float`: `Float` has only a partial logical
model in Lean, so the decided core stays in `Nat`/`Int` and the shell converts at the boundary.
Chrome's rAF runs at 120 Hz, one tick = 1000/120 ms = 25/3 ms.
-/
namespace Fw.Frames

-- All times below are `Nat` microseconds (a type alias would hide them from `omega`).

/-- Chrome tick, round half up: `k = round(dt / 8.333 ms)` computed exactly in integers. -/
def tick (dt : Nat) : Nat := (dt * 240 + 1000000) / 2000000

/-- ">34" in tick form (k ≥ 5) is exactly `dt ≥ 37.5 ms`. -/
theorem tick_ge5_iff (dt : Nat) : 5 ≤ tick dt ↔ 37500 ≤ dt := by
  unfold tick; constructor <;> intro h <;> omega

/-- ">50" in tick form (k ≥ 7) is exactly `dt ≥ 54.167 ms` (54167 µs). -/
theorem tick_ge7_iff (dt : Nat) : 7 ≤ tick dt ↔ 54167 ≤ dt := by
  unfold tick; constructor <;> intro h <;> omega

/-- A longer frame never gets a smaller tick. -/
theorem tick_mono {a b : Nat} (h : a ≤ b) : tick a ≤ tick b := by
  unfold tick; exact Nat.div_le_div_right (by omega)

/-- Frames strictly above a threshold (µs). -/
def countAbove (t : Nat) (xs : List Nat) : Nat := (xs.filter (fun x => decide (t < x))).length

/-- Raising the threshold never raises the count: gt54 ≤ gt50 ≤ gt46 for every run. -/
theorem countAbove_antitone {t t' : Nat} (h : t ≤ t') (xs : List Nat) :
    countAbove t' xs ≤ countAbove t xs := by
  induction xs with
  | nil => simp [countAbove]
  | cons x xs ih =>
    simp only [countAbove, List.filter_cons] at *
    by_cases h1 : t' < x
    · have h2 : t < x := by omega
      simp [h1, h2]; omega
    · by_cases h2 : t < x
      · simp [h1, h2]; omega
      · simp [h1, h2]; omega

/-- The legacy ms form ">34" (dt > 34 ms) and the tick form (k ≥ 5) differ exactly on the frames in
(34, 37.5) ms: "tick-sensitivity" in Chrome is a +3.5 ms twin, nothing more. -/
theorem tick5_eq_countAbove (xs : List Nat) :
    (xs.filter (fun x => decide (5 ≤ tick x))).length = countAbove 37499 xs := by
  unfold countAbove
  congr 1
  apply List.filter_congr
  intro x _
  simp only [decide_eq_decide]
  rw [tick_ge5_iff]; omega

end Fw.Frames

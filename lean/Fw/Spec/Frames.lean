/-!
# Frame-time units (protocol v2 §3.2)

Frame intervals are integer microseconds (Nat), never `Float`: `Float` has only a partial logical
model in Lean, so the decided core stays in `Nat`/`Int` and the shell converts at the boundary.
Chrome's rAF runs at 120 Hz, one tick = 1000/120 ms = 25/3 ms.
-/
namespace Fw.Frames

-- All times below are `Nat` microseconds (a type alias would hide them from `omega`).

/-- Chrome tick: the number of 120 Hz ticks in a frame of `dt` µs, rounded to the nearest tick
with halves rounded up, computed exactly in integers.

Edge: `tick(4166) = 0`, `tick(4167) = 1`, `tick(37499) = 4`,
`tick(37500) = 5`, `tick(54166) = 6`, `tick(54167) = 7`.
-/
def tick (dt : Nat) : Nat := (dt * 240 + 1000000) / 2000000

#guard tick 0 == 0 && tick 4166 == 0 && tick 4167 == 1
#guard tick 37499 == 4 && tick 37500 == 5
#guard tick 54166 == 6 && tick 54167 == 7

/-- A frame is at least 5 ticks long exactly when it lasts at least 37.5 ms (the ≥ 5-tick bucket
(≥ 37.5 ms; see `countAbove34_sub_tick5`)).
-/
theorem tick_ge5_iff (dt : Nat) : 5 ≤ tick dt ↔ 37500 ≤ dt := by
  unfold tick; constructor <;> intro h <;> omega

/-- A frame is at least 7 ticks long exactly when it lasts at least 54 167 µs (54.1667 ms rounded
up to a whole µs; the ">50" bucket in tick form).
-/
theorem tick_ge7_iff (dt : Nat) : 7 ≤ tick dt ↔ 54167 ≤ dt := by
  unfold tick; constructor <;> intro h <;> omega

/-- A longer frame never gets a smaller tick. -/
theorem tick_mono {a b : Nat} (h : a ≤ b) : tick a ≤ tick b := by
  unfold tick; exact Nat.div_le_div_right (by omega)

/-- The wire form of a tick: the number of ticks of a display running at `hz` Hz in a frame of
`dtNs` integer nanoseconds (the unit times cross the TS ↔ Lean boundary in), rounded to the
nearest tick with halves rounded up, computed exactly in integers.

Edge: `tickAt(0, d) = 0` for every `d` (a 0 Hz display has no ticks).
-/
def tickAt (hz dtNs : Nat) : Nat := (2 * hz * dtNs + 1000000000) / 2000000000

#guard tickAt 120 37499000 == 4 && tickAt 120 37500000 == 5
#guard tickAt 60 24999999 == 1 && tickAt 60 25000000 == 2 && tickAt 0 99999999999 == 0

/-- At 120 Hz the nanosecond tick agrees with the microsecond `tick` on every whole number of
microseconds.
-/
theorem tickAt_120_us (dt : Nat) : tickAt 120 (dt * 1000) = tick dt := by
  unfold tickAt tick; omega

/-- A longer frame never gets a smaller tick, at any rate. -/
theorem tickAt_mono (hz : Nat) {a b : Nat} (h : a ≤ b) : tickAt hz a ≤ tickAt hz b := by
  unfold tickAt
  exact Nat.div_le_div_right (Nat.add_le_add_right (Nat.mul_le_mul_left _ h) _)

/-- On the iPhone's 60 Hz page rendering, a frame counts as at least 2 ticks (one missed vsync)
exactly when it lasts at least 25 ms.
-/
theorem tickAt60_ge2_iff (dtNs : Nat) : 2 ≤ tickAt 60 dtNs ↔ 25000000 ≤ dtNs := by
  unfold tickAt; constructor <;> intro h <;> omega

/-- The number of frames strictly longer than `t` µs, repeats counted.

Edge: `countAbove(t, []) = 0`; a frame equal to `t` is not counted.
-/
def countAbove (t : Nat) (xs : List Nat) : Nat := (xs.filter (fun x => decide (t < x))).length

#guard countAbove 0 [] == 0
#guard countAbove 10 [11, 11, 10, 5] == 2

/-- Raising the threshold never raises the count (e.g. with thresholds 54 000 ≥ 50 000 ≥ 46 000 µs,
gt54 ≤ gt50 ≤ gt46 on every run).
-/
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

/-- Counting frames of at least 5 ticks is the same as counting frames strictly above 37 499 µs,
i.e. of at least 37.5 ms (how this relates to the legacy ">34 ms" count is
`countAbove34_sub_tick5`).
-/
theorem tick5_eq_countAbove (xs : List Nat) :
    (xs.filter (fun x => decide (5 ≤ tick x))).length = countAbove 37499 xs := by
  unfold countAbove
  congr 1
  apply List.filter_congr
  intro x _
  simp only [decide_eq_decide]
  rw [tick_ge5_iff]; omega

/-- The legacy ms count ">34" (frames longer than 34 000 µs) exceeds the tick count (frames of at
least 5 ticks) by exactly the frames in `(34 000, 37 499]` µs: "tick-sensitivity" in Chrome is a
+3.5 ms twin, nothing more (gap G1 of the Lean-to-math note).

Here `∸` is truncated subtraction on `ℕ`; it never truncates in this equation, because
`5 ≤ tick(x)` implies `x ≥ 37 500 > 34 000`.
-/
theorem countAbove34_sub_tick5 (xs : List Nat) :
    countAbove 34000 xs - (xs.filter (5 ≤ tick ·)).length
      = (xs.filter (fun x => 34000 < x ∧ x ≤ 37499)).length := by
  induction xs with
  | nil => simp [countAbove]
  | cons x xs ih =>
    have hk := tick_ge5_iff x
    have hle : (xs.filter (5 ≤ tick ·)).length ≤ countAbove 34000 xs := by
      rw [tick5_eq_countAbove]; exact countAbove_antitone (by omega) xs
    simp only [countAbove] at hle ih ⊢
    rw [List.filter_cons, List.filter_cons, List.filter_cons]
    split <;> split <;> split <;> simp_all [List.length_cons] <;> omega

end Fw.Frames

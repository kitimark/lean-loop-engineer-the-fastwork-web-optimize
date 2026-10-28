import Fw.Parts.MorphGeomRect
import Fw.Parts.MorphGeomAnim
namespace Fw.Parts.MorphGeom
open Fw.Parts.MorphTween (fade pointerNone ease duration)

def overStep : Nat := 12

def absDiff (x y : Nat) : Nat := (x - y) + (y - x)

def pixelOver (a b : Nat × Nat × Nat) : Bool :=
  decide (overStep < absDiff a.1 b.1 ∨ overStep < absDiff a.2.1 b.2.1 ∨ overStep < absDiff a.2.2 b.2.2)

theorem pixelOver_red (a b : Nat × Nat × Nat) (h : overStep < absDiff a.1 b.1) : pixelOver a b = true := by
  simp [pixelOver, h]

theorem pixelOver_green (a b : Nat × Nat × Nat) (h : overStep < absDiff a.2.1 b.2.1) : pixelOver a b = true := by
  simp [pixelOver, h]

theorem pixelOver_blue (a b : Nat × Nat × Nat) (h : overStep < absDiff a.2.2 b.2.2) : pixelOver a b = true := by
  simp [pixelOver, h]

theorem pixelOver_none (a b : Nat × Nat × Nat) (hr : absDiff a.1 b.1 ≤ overStep) (hg : absDiff a.2.1 b.2.1 ≤ overStep)
    (hb : absDiff a.2.2 b.2.2 ≤ overStep) : pixelOver a b = false := by
  simp only [pixelOver, decide_eq_false_iff_not]
  omega

theorem pixelOver_self (a : Nat × Nat × Nat) : pixelOver a a = false := by
  simp [pixelOver, absDiff, overStep]

theorem pixelOver_symm (a b : Nat × Nat × Nat) : pixelOver a b = pixelOver b a := by
  simp only [pixelOver, absDiff]
  congr 1
  apply propext
  omega

def pxLo (x : Rat) : Nat := (max 0 x.floor).toNat

def pxHi (size : Nat) (x w : Rat) : Nat := min size (max 0 (x + w).ceil).toNat

theorem px_range_iff (size i : Nat) (x w : Rat) :
    (pxLo x ≤ i ∧ i < pxHi size x w) ↔ (i < size ∧ x < (i : Rat) + 1 ∧ (i : Rat) < x + w) := by
  have e1 : x.floor ≤ (i : Int) ↔ x < (i : Rat) + 1 := by
    have := @Rat.floor_lt_iff x ((i : Int) + 1)
    have h2 : x.floor ≤ (i : Int) ↔ x.floor < (i : Int) + 1 := by omega
    rw [h2, this]
    simp [Rat.intCast_add, Rat.intCast_natCast]
  have e2 : (i : Int) < (x + w).ceil ↔ (i : Rat) < x + w := by
    have := @Rat.lt_ceil_iff (x + w) (i : Int)
    simpa [Rat.intCast_natCast] using this
  unfold pxLo pxHi
  rw [← e1, ← e2]
  omega

theorem px_range_len (size : Nat) (x w : Rat) : pxHi size x w ≤ size := by
  unfold pxHi
  omega

def inBox (W H : Nat) (x y w h : Rat) (i j : Nat) : Bool :=
  decide ((pxLo x ≤ i ∧ i < pxHi W x w) ∧ (pxLo y ≤ j ∧ j < pxHi H y h))

theorem inBox_iff (W H : Nat) (x y w h : Rat) (i j : Nat) :
    inBox W H x y w h i j = true ↔
      ((i < W ∧ x < (i : Rat) + 1 ∧ (i : Rat) < x + w) ∧ (j < H ∧ y < (j : Rat) + 1 ∧ (j : Rat) < y + h)) := by
  simp only [inBox, decide_eq_true_eq]
  rw [px_range_iff, px_range_iff]

def share (over n : Nat) : Rat := if n = 0 then 0 else (over : Rat) / n

theorem share_nonneg (over n : Nat) : 0 ≤ share over n := by
  unfold share
  split
  · exact Rat.le_refl
  · rename_i hn
    have hpos : (0 : Rat) < n := by exact_mod_cast Nat.pos_of_ne_zero hn
    have ho : (0 : Rat) ≤ over := by exact_mod_cast Nat.zero_le _
    refine Rat.not_lt.mp fun hc => ?_
    have := (Rat.div_lt_iff hpos).mp hc
    grind

theorem share_le_one (over n : Nat) (h : over ≤ n) : share over n ≤ 1 := by
  unfold share
  split
  · decide
  · rename_i hn
    have hpos : (0 : Rat) < n := by exact_mod_cast Nat.pos_of_ne_zero hn
    have hle : (over : Rat) ≤ n := by exact_mod_cast h
    refine Rat.not_lt.mp fun hc => ?_
    have := (Rat.lt_div_iff hpos).mp hc
    grind

theorem share_empty (over : Nat) : share over 0 = 0 := by simp [share]

def gridMs : Rat := 1000

inductive TrackKind
  | grid
  | time
deriving DecidableEq

def trackKind (dur : Rat) : Option TrackKind :=
  if dur = gridMs then some .grid else if dur = timeEnd then some .time else none

def trackValue : TrackKind → Rat → Rat
  | .grid, t => t / gridMs
  | .time, t => ease (t / duration)

def mTol : Rat := 1 / 500

def within (v m : Rat) : Bool := decide (v - m ≤ mTol ∧ m - v ≤ mTol)

theorem within_far (v m : Rat) (h : mTol < v - m ∨ mTol < m - v) : within v m = false := by
  unfold within
  rw [decide_eq_false_iff_not]
  rcases h with h | h
  · exact fun ⟨h1, _⟩ => absurd h (Rat.not_lt.mpr h1)
  · exact fun ⟨_, h2⟩ => absurd h (Rat.not_lt.mpr h2)

def trackAt (dur t m : Rat) : Bool :=
  match trackKind dur with
  | none => false
  | some k => within (trackValue k t) m

theorem trackAt_grid (t m : Rat) : trackAt gridMs t m = within (t / gridMs) m := by
  simp [trackAt, trackKind, trackValue]

theorem trackAt_time (t m : Rat) : trackAt timeEnd t m = within (ease (t / duration)) m := by
  have hne : ¬ timeEnd = gridMs := by decide +kernel
  simp [trackAt, trackKind, hne, trackValue]

theorem trackAt_other (dur t m : Rat) (h1 : dur ≠ gridMs) (h2 : dur ≠ timeEnd) : trackAt dur t m = false := by
  simp [trackAt, trackKind, h1, h2]

def tracksOk (m : Rat) (n : Nat) : Bool := if m = 0 then decide (n = 0) else decide (0 < n)

theorem tracksOk_rest (n : Nat) : tracksOk 0 n = true ↔ n = 0 := by simp [tracksOk]

theorem tracksOk_off (m : Rat) (n : Nat) (h : m ≠ 0) : tracksOk m n = true ↔ 0 < n := by simp [tracksOk, h]

def timedSettled (m : Rat) (flip goal : Bool) (n : Nat) : Bool :=
  if m = 0 then !flip && !goal && decide (n = 0)
  else if m = 1 then flip && goal && decide (n = 0)
  else false

theorem timedSettled_rest (flip goal : Bool) (n : Nat) :
    timedSettled 0 flip goal n = true ↔ (flip = false ∧ goal = false ∧ n = 0) := by
  simp [timedSettled, and_assoc]

theorem timedSettled_open (flip goal : Bool) (n : Nat) :
    timedSettled 1 flip goal n = true ↔ (flip = true ∧ goal = true ∧ n = 0) := by
  have : ¬ ((1 : Rat) = 0) := by decide +kernel
  simp [timedSettled, this, and_assoc]

theorem timedSettled_mid (m : Rat) (h0 : m ≠ 0) (h1 : m ≠ 1) (flip goal : Bool) (n : Nat) :
    timedSettled m flip goal n = false := by
  simp [timedSettled, h0, h1]

def scrollTol : Rat := 1 / 100

def scrollEq (a b : Rat) : Bool := decide (a - b ≤ scrollTol ∧ b - a ≤ scrollTol)

theorem scrollEq_self (a : Rat) : scrollEq a a = true := by
  have h0 : (0 : Rat) ≤ scrollTol := by decide +kernel
  simp [scrollEq, Rat.sub_self, h0]

theorem scrollEq_far (a b : Rat) (h : scrollTol < a - b) : scrollEq a b = false := by
  simp only [scrollEq, decide_eq_false_iff_not]
  intro ⟨h1, _⟩
  exact absurd h (Rat.not_lt.mpr h1)

def fadeTol : Rat := 1 / 100

def fadeShows (o m : Rat) : Bool := decide (o - fade m ≤ fadeTol ∧ fade m - o ≤ fadeTol)

theorem fadeShows_exact (m : Rat) : fadeShows (fade m) m = true := by
  have h0 : (0 : Rat) ≤ fadeTol := by decide +kernel
  simp [fadeShows, Rat.sub_self, h0]

theorem fadeShows_gone (m : Rat) (h : (11 : Rat) / 20 ≤ m) : fadeShows 0 m = true := by
  have hp : (0 : Rat) < 11 / 20 := by decide +kernel
  have h0 : (0 : Rat) ≤ fadeTol := by decide +kernel
  have h1 : (1 : Rat) ≤ m / (11 / 20) := by
    refine Rat.not_lt.mp fun hc => ?_
    have := (Rat.div_lt_iff hp).mp hc
    grind
  have hf : fade m = 0 := by
    unfold fade Fw.Parts.MorphTween.fadeEnd
    have : min 1 (m / (11 / 20)) = 1 := by simp [Min.min, h1]
    rw [this]
    exact Rat.sub_self
  simp [fadeShows, hf, Rat.sub_self, h0]

end Fw.Parts.MorphGeom

import Fw.Parts.PlatformGlintPause
/-!
# platform.glint:hold-freeze

The faithful glint animates `x1` and `x2` of each dash with one repeating `<animate>` each (`dur 5s`, six key times).
Both engines schedule a tick on every frame for an active `<animate>` whose duration is finite, even when its value does
not change (WebKit `SVGSMILElement.cpp:1074-1088` and Chromium `svg_smil_element.cc:1285-1301`: `calculateNextProgressTime`
returns `elapsed + animationFrameDelay` / `presentation_time` for an active non-`<set>`; for a `<set>` or a frozen or
inactive element the next time is the interval end, the begin, or unresolved).

The variant has one piece per attribute and key-time segment: a `<set>` where the two key values are equal (the value
holds), a ramp `<animate>` of one segment where they differ. The pieces of an attribute begin one segment apart and tile
the cycle, so exactly one is active at every instant after the begin, and an active non-`<set>` animation exists only
during a ramp. This file proves: the hold segments (premise), that the piece value equals the faithful value at every
elapsed time (`hold_eq_faithful`), the active-animation counts (the work claim), and that the equality survives
the pause and resume-seek of `PlatformGlintPause` (`hold_resume_eq`). Times in ms.
-/
namespace Fw.Parts.PlatformGlintHold
open Fw.Parts.PlatformGlint
open Fw.Parts.PlatformSweep (frac frac_mem)
open Fw.Parts.PlatformGlintPause (P Same Obs Cont)

/-- The animated attribute. -/
inductive Attr | x1 | x2
deriving Repr, DecidableEq

/-- The six `values` of an attribute and side (same numbers as `x1At`, `x2At` of `PlatformGlint`). -/
def vals : Attr → Side → List Rat
  | .x1, .left => [-200, 200, 200, 200, -200, -200]
  | .x1, .right => [-200, -200, 200, -200, -200, -200]
  | .x2, .left => [-80, 320, 320, 320, -80, -80]
  | .x2, .right => [-80, -80, 320, -80, -80, -80]

/-- Value at the start of segment `k`. -/
def segFrom (a : Attr) (s : Side) (k : Nat) : Rat := (vals a s).getD k 0

/-- Value at the end of segment `k`. -/
def segTo (a : Attr) (s : Side) (k : Nat) : Rat := (vals a s).getD (k + 1) 0

/-- A piece is a `<set>` or a ramp `<animate>`. -/
inductive Kind | set | ramp
deriving Repr, DecidableEq

/-- Kind of segment `k`: a `<set>` where the value holds. -/
def kindOf (a : Attr) (s : Side) (k : Nat) : Kind := if segFrom a s k == segTo a s k then .set else .ramp

/-- Value of a piece `w` of the way through its segment (`w` in `[0, 1)`). -/
def pieceVal (a : Attr) (s : Side) (k : Nat) (w : Rat) : Rat :=
  match kindOf a s k with
  | .set => segTo a s k
  | .ramp => lerp (segFrom a s k) (segTo a s k) w

/-- Segment index of cycle fraction `u`. -/
def segOf (u : Rat) : Nat :=
  if u < 1 / 5 then 0 else if u < 2 / 5 then 1 else if u < 3 / 5 then 2 else if u < 4 / 5 then 3 else 4

/-- Value of the one active piece of attribute `a` `e` ms after the begin. -/
def holdAt (a : Attr) (s : Side) (e : Rat) : Rat :=
  pieceVal a s (segOf (cycle e)) (5 * cycle e - segOf (cycle e))

/-- The pair of attributes. -/
def holdSample (s : Side) (e : Rat) : Rat × Rat := (holdAt .x1 s e, holdAt .x2 s e)

#guard holdSample .left 500 == (0, 120)
#guard holdSample .left 2000 == (200, 320)
#guard holdSample .right 0 == (-200, -80)
#guard holdSample .right 1500 == (0, 120)

/-! ## Premise: three of five segments hold -/

/-- Segment `k` holds on both attributes. -/
def holds (s : Side) (k : Nat) : Bool := kindOf .x1 s k == .set && kindOf .x2 s k == .set

/-- The two attributes hold in the same segments, so a hold segment has no ramp at all. -/
theorem hold_same_segments (s : Side) : ∀ k, k < 5 → kindOf .x1 s k = kindOf .x2 s k := by
  intro k hk
  have h : k = 0 ∨ k = 1 ∨ k = 2 ∨ k = 3 ∨ k = 4 := by omega
  rcases h with h | h | h | h | h <;> subst h <;> cases s <;> decide

/-- **hold_premise.** Three of the five segments hold on each side, decided over the key values. -/
theorem hold_premise (s : Side) : ((List.range 5).filter (holds s)).length = 3 := by
  cases s <;> decide

/-- Left holds in segments 1, 2 and 4. -/
theorem hold_segments_left : (List.range 5).filter (holds .left) = [1, 2, 4] := by decide

/-- Right holds in segments 0, 3 and 4. -/
theorem hold_segments_right : (List.range 5).filter (holds .right) = [0, 3, 4] := by decide

/-! ## The value equals the faithful value -/

/-- The linear mix of segment `k`. -/
def segLerp (a : Attr) (s : Side) (k : Nat) (w : Rat) : Rat := lerp (segFrom a s k) (segTo a s k) w

/-- A `<set>` piece carries the segment's constant, which is its mix at every `w`. -/
theorem pieceVal_eq (a : Attr) (s : Side) (k : Nat) (w : Rat) : pieceVal a s k w = segLerp a s k w := by
  unfold pieceVal segLerp
  by_cases h : segFrom a s k = segTo a s k
  · have hk : kindOf a s k = .set := by simp [kindOf, h]
    rw [hk]
    simp only [lerp]
    grind
  · have hk : kindOf a s k = .ramp := by simp [kindOf, h]
    rw [hk]

theorem segOf_0 (u : Rat) (h : u < 1 / 5) : segOf u = 0 := by simp [segOf, h]
theorem segOf_1 (u : Rat) (h0 : ¬u < 1 / 5) (h : u < 2 / 5) : segOf u = 1 := by simp [segOf, h0, h]
theorem segOf_2 (u : Rat) (h0 : ¬u < 1 / 5) (h1 : ¬u < 2 / 5) (h : u < 3 / 5) : segOf u = 2 := by
  simp [segOf, h0, h1, h]
theorem segOf_3 (u : Rat) (h0 : ¬u < 1 / 5) (h1 : ¬u < 2 / 5) (h2 : ¬u < 3 / 5) (h : u < 4 / 5) : segOf u = 3 := by
  simp [segOf, h0, h1, h2, h]
theorem segOf_4 (u : Rat) (h0 : ¬u < 1 / 5) (h1 : ¬u < 2 / 5) (h2 : ¬u < 3 / 5) (h3 : ¬u < 4 / 5) : segOf u = 4 := by
  simp [segOf, h0, h1, h2, h3]

/-- The faithful `x1` is the mix of the segment `segOf u`. -/
theorem x1At_seg (s : Side) (u : Rat) : x1At s u = segLerp .x1 s (segOf u) (5 * u - segOf u) := by
  unfold x1At interp
  by_cases h0 : u < 1 / 5
  · rw [segOf_0 u h0]; cases s <;> simp [segLerp, segFrom, segTo, vals, lerp, h0] <;> grind
  by_cases h1 : u < 2 / 5
  · rw [segOf_1 u h0 h1]; cases s <;> simp [segLerp, segFrom, segTo, vals, lerp, h0, h1]
  by_cases h2 : u < 3 / 5
  · rw [segOf_2 u h0 h1 h2]; cases s <;> simp [segLerp, segFrom, segTo, vals, lerp, h0, h1, h2]
  by_cases h3 : u < 4 / 5
  · rw [segOf_3 u h0 h1 h2 h3]; cases s <;> simp [segLerp, segFrom, segTo, vals, lerp, h0, h1, h2, h3]
  · rw [segOf_4 u h0 h1 h2 h3]; cases s <;> simp [segLerp, segFrom, segTo, vals, lerp, h0, h1, h2, h3]

/-- The faithful `x2` is the mix of the segment `segOf u`. -/
theorem x2At_seg (s : Side) (u : Rat) : x2At s u = segLerp .x2 s (segOf u) (5 * u - segOf u) := by
  unfold x2At interp
  by_cases h0 : u < 1 / 5
  · rw [segOf_0 u h0]; cases s <;> simp [segLerp, segFrom, segTo, vals, lerp, h0] <;> grind
  by_cases h1 : u < 2 / 5
  · rw [segOf_1 u h0 h1]; cases s <;> simp [segLerp, segFrom, segTo, vals, lerp, h0, h1]
  by_cases h2 : u < 3 / 5
  · rw [segOf_2 u h0 h1 h2]; cases s <;> simp [segLerp, segFrom, segTo, vals, lerp, h0, h1, h2]
  by_cases h3 : u < 4 / 5
  · rw [segOf_3 u h0 h1 h2 h3]; cases s <;> simp [segLerp, segFrom, segTo, vals, lerp, h0, h1, h2, h3]
  · rw [segOf_4 u h0 h1 h2 h3]; cases s <;> simp [segLerp, segFrom, segTo, vals, lerp, h0, h1, h2, h3]

/-- **hold_eq_faithful.** At every elapsed time, in particular every `t ≥ begin`, both attributes of both sides carry the
value of the faithful animation. -/
theorem hold_eq_faithful (s : Side) (e : Rat) : holdSample s e = sample s e := by
  unfold holdSample holdAt sample
  rw [pieceVal_eq, pieceVal_eq, x1At_seg, x2At_seg]

/-! ## The pieces tile the timeline

The piece of segment `k` in cycle `n` is active on `[5000 n + 1000 k, 5000 n + 1000 k + 1000)`, where the begin is the
clock origin plus `n` cycles plus `k` segments. -/

/-- Begin of the piece of segment `k` in cycle `n` (ms after the origin). -/
def beginAt (k n : Nat) : Rat := 5000 * n + 1000 * k

/-- The piece of segment `k` in cycle `n` is active at `e`. -/
def activeIn (k n : Nat) (e : Rat) : Prop := beginAt k n ≤ e ∧ e < beginAt k n + 1000

/-- At most one piece is active at an instant. -/
theorem active_unique (e : Rat) (k n k' n' : Nat) (hk : k < 5) (hk' : k' < 5)
    (h : activeIn k n e) (h' : activeIn k' n' e) : k = k' ∧ n = n' := by
  unfold activeIn beginAt at h h'
  have a : ((5 * n + k : Nat) : Rat) < ((5 * n' + k' : Nat) : Rat) + 1 := by push_cast; grind
  have b : ((5 * n' + k' : Nat) : Rat) < ((5 * n + k : Nat) : Rat) + 1 := by push_cast; grind
  have a' : 5 * n + k < 5 * n' + k' + 1 := by
    have := Rat.natCast_lt_natCast.mp (show ((5 * n + k : Nat) : Rat) < ((5 * n' + k' + 1 : Nat) : Rat) by push_cast; grind)
    exact this
  have b' : 5 * n' + k' < 5 * n + k + 1 := by
    have := Rat.natCast_lt_natCast.mp (show ((5 * n' + k' : Nat) : Rat) < ((5 * n + k + 1 : Nat) : Rat) by push_cast; grind)
    exact this
  omega

/-- From the begin on, some piece is active. -/
theorem active_exists (e : Rat) (he : 0 ≤ e) : ∃ k n, k < 5 ∧ activeIn k n e := by
  have h0 : (0 : Int) ≤ (e / 1000).floor := Rat.le_floor_iff.mpr (by simp; grind)
  have hl := Rat.floor_le (e / 1000)
  have hu := Rat.lt_floor_add_one (e / 1000)
  refine ⟨((e / 1000).floor.toNat) % 5, ((e / 1000).floor.toNat) / 5, Nat.mod_lt _ (by decide), ?_⟩
  have hm : (((e / 1000).floor.toNat : Nat) : Int) = (e / 1000).floor := Int.toNat_of_nonneg h0
  have hsum : 5 * ((e / 1000).floor.toNat / 5) + (e / 1000).floor.toNat % 5 = (e / 1000).floor.toNat := by omega
  have hc : (((e / 1000).floor.toNat : Nat) : Rat) = (((e / 1000).floor : Int) : Rat) := by
    rw [← Rat.intCast_natCast, hm]
  have hs : ((5 * ((e / 1000).floor.toNat / 5) + (e / 1000).floor.toNat % 5 : Nat) : Rat) = (((e / 1000).floor.toNat : Nat) : Rat) := by
    rw [hsum]
  unfold activeIn beginAt
  push_cast at hs hu hl ⊢
  grind

/-- The active piece of segment `k` is the one `holdAt` reads: `segOf (cycle e) = k`. -/
theorem active_seg (e : Rat) (k n : Nat) (hk : k < 5) (h : activeIn k n e) : segOf (cycle e) = k := by
  unfold activeIn beginAt at h
  have hf : (e / dur).floor = (n : Int) := by
    apply Int.le_antisymm
    · have : (e / dur).floor < (n : Int) + 1 := by
        by_cases hc : (e / dur).floor < (n : Int) + 1
        · exact hc
        · exfalso
          have h2 := (Rat.le_floor_iff (x := (n : Int) + 1) (a := e / dur)).mp (Int.not_lt.mp hc)
          simp only [dur] at h2
          push_cast at h2
          have hk5 : (k : Rat) + 1 ≤ 5 := by exact_mod_cast hk
          grind
      omega
    · have hn : ((n : Int) : Rat) = (n : Rat) := Rat.intCast_natCast n
      exact Rat.le_floor_iff.mpr (by simp only [dur]; rw [hn]; grind)
  have hu : cycle e = e / dur - n := by
    unfold cycle frac; rw [hf]; simp only [Rat.intCast_natCast]
  rw [hu]
  have h5 : e / dur = e / 5000 := rfl
  rw [h5]
  have : k = 0 ∨ k = 1 ∨ k = 2 ∨ k = 3 ∨ k = 4 := by omega
  rcases this with rfl | rfl | rfl | rfl | rfl <;> simp at h
  · exact segOf_0 _ (by grind)
  · exact segOf_1 _ (by grind) (by grind)
  · exact segOf_2 _ (by grind) (by grind) (by grind)
  · exact segOf_3 _ (by grind) (by grind) (by grind) (by grind)
  · exact segOf_4 _ (by grind) (by grind) (by grind) (by grind)

/-- With `fill="freeze"` an ended piece still contributes, but the active piece began later than every piece that
began at or before `e`, so it has the highest priority (both engines order contributing animations of an attribute by
begin time, WebKit `SMILTimeContainer.cpp:229-243`). -/
theorem active_latest (e : Rat) (k n : Nat) (h : activeIn k n e) (k' n' : Nat) (hb : beginAt k' n' ≤ e) : beginAt k' n' ≤ beginAt k n := by
  unfold activeIn beginAt at h
  unfold beginAt at hb ⊢
  have a : ((5 * n' + k' : Nat) : Rat) < ((5 * n + k : Nat) : Rat) + 1 := by push_cast; grind
  have a' : 5 * n' + k' < 5 * n + k + 1 :=
    Rat.natCast_lt_natCast.mp (show ((5 * n' + k' : Nat) : Rat) < ((5 * n + k + 1 : Nat) : Rat) by push_cast; grind)
  have : 5 * n' + k' ≤ 5 * n + k := by omega
  have c : ((5 * n' + k' : Nat) : Rat) ≤ ((5 * n + k : Nat) : Rat) := by exact_mod_cast this
  push_cast at c
  grind

/-! ## The work claim

Both engines tick an active non-`<set>` every frame and nothing else (`calculateNextProgressTime`). The faithful pair has
two such animations active at every instant after the begin. The pieces have one per ramp segment and attribute. -/

/-- Active non-`<set>` animations of one dash `e` ms after the begin: the active ramp pieces. -/
def ticking (s : Side) (e : Rat) : Nat :=
  (if kindOf .x1 s (segOf (cycle e)) == .ramp then 1 else 0) + (if kindOf .x2 s (segOf (cycle e)) == .ramp then 1 else 0)

/-- Active non-`<set>` animations of the faithful pair: two repeating `<animate>` at every instant after the begin. -/
def faithfulTicking : Nat := 2

/-- In a hold segment no non-`<set>` animation is active: zero against two. -/
theorem ticking_hold (s : Side) (e : Rat) (h : holds s (segOf (cycle e)) = true) : ticking s e = 0 := by
  unfold holds at h
  unfold ticking
  simp only [Bool.and_eq_true, beq_iff_eq] at h
  simp [h.1, h.2]

/-- In a ramp segment both attributes ramp: two against two, so the variant never ticks more than the faithful pair. -/
theorem ticking_ramp (s : Side) (e : Rat) (h : segOf (cycle e) < 5)
    (hr : holds s (segOf (cycle e)) = false) : ticking s e = faithfulTicking := by
  have hk := hold_same_segments s (segOf (cycle e)) h
  unfold holds at hr
  unfold ticking faithfulTicking
  rw [← hk] at hr ⊢
  cases hx : kindOf .x1 s (segOf (cycle e)) <;> simp_all

/-- The variant never ticks more than the faithful pair. -/
theorem ticking_le (s : Side) (e : Rat) : ticking s e ≤ faithfulTicking := by
  unfold ticking faithfulTicking
  split <;> split <;> simp

/-- Hold segments cover three fifths of every cycle, on each side. -/
theorem hold_share (s : Side) : (((List.range 5).filter (holds s)).length : Rat) / 5 = 3 / 5 := by
  rw [hold_premise]; rfl

/-! ## Pause and resume

`PlatformGlintPause` pauses the container and, on resume, seeks it to `t + off`, which reads the uninterrupted
clock (`Same`). The piece value depends on the container's elapsed time alone, so the equality survives. -/

/-- After any pause or resume sequence, a running container that began at `b` has piece values equal to the faithful
values at `s - b`. -/
theorem hold_resume_eq (b : Rat) (p : P) (hp : Same b p) (os : List Obs) (side : Side) (s : Rat)
    (hrun : (os.foldl P.step p).c.paused = false) :
    holdSample side ((os.foldl P.step p).c.elapsed s) = sample side (s - b) := by
  have hs := Fw.Parts.PlatformGlintPause.same_run b p hp os
  rw [hs.2 hrun s, hold_eq_faithful]

end Fw.Parts.PlatformGlintHold

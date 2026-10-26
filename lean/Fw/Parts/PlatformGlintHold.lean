import Fw.Parts.PlatformGlintPause
/-! # platform.glint:hold-freeze
One `<set>` or ramp `<animate>` piece per attribute and key-time segment, equal to the faithful glint at every time (ms). -/
namespace Fw.Parts.PlatformGlintHold
open Fw.Parts.PlatformGlint
open Fw.Parts.PlatformSweep (frac frac_mem)
open Fw.Parts.PlatformGlintPause (P Same Obs Cont)

inductive Attr | x1 | x2
deriving Repr, DecidableEq

def vals : Attr → Side → List Rat
  | .x1, .left => [-200, 200, 200, 200, -200, -200]
  | .x1, .right => [-200, -200, 200, -200, -200, -200]
  | .x2, .left => [-80, 320, 320, 320, -80, -80]
  | .x2, .right => [-80, -80, 320, -80, -80, -80]

def segFrom (a : Attr) (s : Side) (k : Nat) : Rat := (vals a s).getD k 0

def segTo (a : Attr) (s : Side) (k : Nat) : Rat := (vals a s).getD (k + 1) 0

inductive Kind | set | ramp
deriving Repr, DecidableEq

def kindOf (a : Attr) (s : Side) (k : Nat) : Kind := if segFrom a s k == segTo a s k then .set else .ramp

def pieceVal (a : Attr) (s : Side) (k : Nat) (w : Rat) : Rat :=
  match kindOf a s k with
  | .set => segTo a s k
  | .ramp => lerp (segFrom a s k) (segTo a s k) w

def segOf (u : Rat) : Nat :=
  if u < 1 / 5 then 0 else if u < 2 / 5 then 1 else if u < 3 / 5 then 2 else if u < 4 / 5 then 3 else 4

def holdAt (a : Attr) (s : Side) (e : Rat) : Rat :=
  pieceVal a s (segOf (cycle e)) (5 * cycle e - segOf (cycle e))

def holdSample (s : Side) (e : Rat) : Rat × Rat := (holdAt .x1 s e, holdAt .x2 s e)

#guard holdSample .left 500 == (0, 120)
#guard holdSample .left 2000 == (200, 320)
#guard holdSample .right 0 == (-200, -80)
#guard holdSample .right 1500 == (0, 120)

def holds (s : Side) (k : Nat) : Bool := kindOf .x1 s k == .set && kindOf .x2 s k == .set

theorem hold_same_segments (s : Side) : ∀ k, k < 5 → kindOf .x1 s k = kindOf .x2 s k := by
  intro k hk
  have h : k = 0 ∨ k = 1 ∨ k = 2 ∨ k = 3 ∨ k = 4 := by omega
  rcases h with h | h | h | h | h <;> subst h <;> cases s <;> decide

theorem hold_premise (s : Side) : ((List.range 5).filter (holds s)).length = 3 := by
  cases s <;> decide

theorem hold_segments_left : (List.range 5).filter (holds .left) = [1, 2, 4] := by decide

theorem hold_segments_right : (List.range 5).filter (holds .right) = [0, 3, 4] := by decide

def segLerp (a : Attr) (s : Side) (k : Nat) (w : Rat) : Rat := lerp (segFrom a s k) (segTo a s k) w

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

theorem hold_eq_faithful (s : Side) (e : Rat) : holdSample s e = sample s e := by
  unfold holdSample holdAt sample
  rw [pieceVal_eq, pieceVal_eq, x1At_seg, x2At_seg]

def beginAt (k n : Nat) : Rat := 5000 * n + 1000 * k

def activeIn (k n : Nat) (e : Rat) : Prop := beginAt k n ≤ e ∧ e < beginAt k n + 1000

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

def ticking (s : Side) (e : Rat) : Nat :=
  (if kindOf .x1 s (segOf (cycle e)) == .ramp then 1 else 0) + (if kindOf .x2 s (segOf (cycle e)) == .ramp then 1 else 0)

def faithfulTicking : Nat := 2

theorem ticking_hold (s : Side) (e : Rat) (h : holds s (segOf (cycle e)) = true) : ticking s e = 0 := by
  unfold holds at h
  unfold ticking
  simp only [Bool.and_eq_true, beq_iff_eq] at h
  simp [h.1, h.2]

theorem ticking_ramp (s : Side) (e : Rat) (h : segOf (cycle e) < 5)
    (hr : holds s (segOf (cycle e)) = false) : ticking s e = faithfulTicking := by
  have hk := hold_same_segments s (segOf (cycle e)) h
  unfold holds at hr
  unfold ticking faithfulTicking
  rw [← hk] at hr ⊢
  cases hx : kindOf .x1 s (segOf (cycle e)) <;> simp_all

theorem ticking_le (s : Side) (e : Rat) : ticking s e ≤ faithfulTicking := by
  unfold ticking faithfulTicking
  split <;> split <;> simp

theorem hold_share (s : Side) : (((List.range 5).filter (holds s)).length : Rat) / 5 = 3 / 5 := by
  rw [hold_premise]; rfl

theorem hold_resume_eq (b : Rat) (p : P) (hp : Same b p) (os : List Obs) (side : Side) (s : Rat)
    (hrun : (os.foldl P.step p).c.paused = false) :
    holdSample side ((os.foldl P.step p).c.elapsed s) = sample side (s - b) := by
  have hs := Fw.Parts.PlatformGlintPause.same_run b p hp os
  rw [hs.2 hrun s, hold_eq_faithful]

end Fw.Parts.PlatformGlintHold

import Fw.Oracle.Core
/-! The paired comparison of an expanded arm against its own run without the files, the exact sign test, and the adopt
rule of research/notes/2026/10-2x-jev-file-context.md. -/
namespace Fw.Oracle.Expand
open Fw.Oracle

/-- One row of one arm: right without the files (`base`) and right with them (`arm`). -/
structure Pair where
  id : String
  base : Bool
  arm : Bool
deriving Repr, DecidableEq

/-- The rows that flipped into correct. -/
def gains (ps : List Pair) : List String := (ps.filter fun p => !p.base && p.arm).map (·.id)

/-- The rows that flipped out of correct. -/
def losses (ps : List Pair) : List String := (ps.filter fun p => p.base && !p.arm).map (·.id)

def net (ps : List Pair) : Int := (gains ps).length - (losses ps).length

/-- Row `n` of Pascal's triangle. -/
def pascal : Nat → List Nat
  | 0 => [1]
  | n + 1 => let r := pascal n; List.zipWith (· + ·) (0 :: r) (r ++ [0])

def binom (n k : Nat) : Nat := (pascal n).getD k 0

#guard (List.range 6).map (binom 5) == [1, 5, 10, 10, 5, 1]
#guard binom 3 7 == 0

/-- The two-sided exact sign test of `a` flips one way and `b` the other: twice the binomial tail at one half up to the
smaller count, at most 1. -/
def signP (a b : Nat) : Rat :=
  let n := a + b
  let tail := ((List.range (min a b + 1)).map (binom n)).sum
  min 1 (2 * (tail : Rat) / ((2 ^ n : Nat) : Rat))

theorem signP_symm (a b : Nat) : signP a b = signP b a := by
  unfold signP
  rw [Nat.add_comm a b, Nat.min_comm a b]

theorem signP_le_one (a b : Nat) : signP a b ≤ 1 := by
  unfold signP
  rw [Rat.min_def]
  split
  · exact Rat.le_refl
  · rename_i h
    exact Rat.le_of_lt (Rat.not_le.mp h)

#guard signP 0 0 == 1
#guard signP 4 0 == 1 / 8
#guard signP 6 1 == 1 / 8
#guard signP 3 3 == 1

/-- One arm's pairs. -/
structure ArmPairs where
  arm : String
  pairs : List Pair
deriving Repr, DecidableEq

/-- The least net gain every arm needs. -/
def minNet : Int := 4

/-- Why the expansion is not adopted. -/
inductive Why where
  | noArm
  | netLow (arm : String) (net : Int)
  | gainOnDropped (arm id : String)
  | untraced (arm id : String)
deriving Repr, DecidableEq

/-- Every reason against adopting: no arm, an arm under `minNet`, a gain on a row where a file was dropped for a
vocabulary word, a gain no hand read traced to a fact the row lacks. -/
def reasons (arms : List ArmPairs) (dropped traced : List String) : List Why :=
  (if arms.isEmpty then [Why.noArm] else []) ++
    arms.flatMap fun a =>
      (if net a.pairs < minNet then [Why.netLow a.arm (net a.pairs)] else []) ++
        ((gains a.pairs).filter dropped.contains).map (Why.gainOnDropped a.arm) ++
        ((gains a.pairs).filter fun i => !traced.contains i).map (Why.untraced a.arm)

/-- Adopt the expansion only when nothing speaks against it. -/
def adopt (arms : List ArmPairs) (dropped traced : List String) : Bool := (reasons arms dropped traced).isEmpty

theorem adopt_iff (arms : List ArmPairs) (dropped traced : List String) :
    adopt arms dropped traced = true ↔ arms ≠ [] ∧ ∀ a ∈ arms, minNet ≤ net a.pairs ∧
      ∀ i ∈ gains a.pairs, i ∉ dropped ∧ i ∈ traced := by
  simp only [adopt, reasons, List.isEmpty_iff, List.append_eq_nil_iff, List.flatMap_eq_nil_iff, List.map_eq_nil_iff,
    List.filter_eq_nil_iff, List.contains_iff_mem, Bool.not_eq_true']
  constructor
  · rintro ⟨h0, h⟩
    refine ⟨fun he => by simp [he] at h0, fun a ha => ?_⟩
    obtain ⟨⟨hn, hd⟩, ht⟩ := h a ha
    refine ⟨?_, fun i hi => ⟨fun hm => hd i hi (by simpa using hm), ?_⟩⟩
    · by_cases hl : net a.pairs < minNet
      · simp [hl] at hn
      · exact Int.not_lt.mp hl
    · have := ht i hi
      simpa using this
  · rintro ⟨h0, h⟩
    refine ⟨by simp [h0], fun a ha => ?_⟩
    obtain ⟨hn, hg⟩ := h a ha
    refine ⟨⟨by simp [Int.not_lt.mpr hn], fun i hi hm => (hg i hi).1 (by simpa using hm)⟩, fun i hi => ?_⟩
    simpa using (hg i hi).2

theorem reject_noArm (dropped traced : List String) : adopt [] dropped traced = false := by
  simp [adopt, reasons]

theorem reject_netLow {arms : List ArmPairs} {dropped traced : List String} {a : ArmPairs} (ha : a ∈ arms)
    (h : net a.pairs < minNet) : adopt arms dropped traced = false := by
  cases hb : adopt arms dropped traced
  · rfl
  · exact absurd (((adopt_iff _ _ _).mp hb).2 a ha).1 (Int.not_le.mpr h)

theorem reject_dropped {arms : List ArmPairs} {dropped traced : List String} {a : ArmPairs} {i : String}
    (ha : a ∈ arms) (hi : i ∈ gains a.pairs) (hd : i ∈ dropped) : adopt arms dropped traced = false := by
  cases hb : adopt arms dropped traced
  · rfl
  · exact absurd hd ((((adopt_iff _ _ _).mp hb).2 a ha).2 i hi).1

theorem reject_untraced {arms : List ArmPairs} {dropped traced : List String} {a : ArmPairs} {i : String}
    (ha : a ∈ arms) (hi : i ∈ gains a.pairs) (ht : i ∉ traced) : adopt arms dropped traced = false := by
  cases hb : adopt arms dropped traced
  · rfl
  · exact absurd ((((adopt_iff _ _ _).mp hb).2 a ha).2 i hi).2 ht

/-! ## Renormalised replies -/

/-- The reply's probabilities divided by their sum (unchanged when the sum is 0). -/
def renorm (r : Raw) : Raw :=
  let s := (r.probs.map (·.2)).sum
  if s = 0 then r else { r with probs := r.probs.map fun (k, v) => (k, v / s) }

theorem sum_map_div (s : Rat) : ∀ l : List (String × Rat),
    ((l.map fun (kv : String × Rat) => (kv.1, kv.2 / s)).map (·.2)).sum = (l.map (·.2)).sum * s⁻¹
  | [] => by simp
  | x :: l => by
    have ih := sum_map_div s l
    simp only [List.map_cons, List.sum_cons, Rat.div_def] at ih ⊢
    rw [ih, Rat.add_mul]

theorem renorm_sum (r : Raw) (h : (r.probs.map (·.2)).sum ≠ 0) : ((renorm r).probs.map (·.2)).sum = 1 := by
  simp only [renorm, h, ↓reduceIte]
  rw [sum_map_div]
  exact Rat.mul_inv_cancel _ h

end Fw.Oracle.Expand

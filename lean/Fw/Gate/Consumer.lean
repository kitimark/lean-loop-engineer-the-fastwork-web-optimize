import Lean.Data.Json
import Fw.Parts.HeroExitScrollOffset

namespace Fw.Gate.Consumer

open Lean (Json)

/-- Whether element `i` has a box in an arm, from that arm's `getClientRects().length > 0` bits; a missing element has none. -/
def box (bs : List Bool) (i : Nat) : Bool := bs.getD i false

/-- The consumer rule: an element is compared when at least one arm gives it a box. -/
def comparedAt (bo bc : List Bool) (i : Nat) : Bool := box bo i || box bc i

/-- The indices of `n` positions the probe compares. -/
def keptIdx (n : Nat) (bo bc : List Bool) : List Nat := (List.range n).filter (comparedAt bo bc)

/-- What an element puts on screen: nothing without a box, else a function of its computed value. -/
def paint (hasBox : Bool) (v : Nat) : Option Nat := if hasBox then some v else none

theorem compared_of_orig {bo bc : List Bool} {i : Nat} (h : box bo i = true) : comparedAt bo bc i = true := by
  simp [comparedAt, h]

theorem compared_of_cand {bo bc : List Bool} {i : Nat} (h : box bc i = true) : comparedAt bo bc i = true := by
  simp [comparedAt, h]

theorem not_compared_iff {bo bc : List Bool} {i : Nat} :
    comparedAt bo bc i = false ↔ box bo i = false ∧ box bc i = false := by
  simp [comparedAt]

theorem mem_keptIdx_iff {n : Nat} {bo bc : List Bool} {i : Nat} :
    i ∈ keptIdx n bo bc ↔ i < n ∧ comparedAt bo bc i = true := by
  simp [keptIdx]

theorem rendered_orig_kept {n : Nat} {bo bc : List Bool} {i : Nat} (hi : i < n) (h : box bo i = true) :
    i ∈ keptIdx n bo bc :=
  mem_keptIdx_iff.2 ⟨hi, compared_of_orig h⟩

theorem rendered_cand_kept {n : Nat} {bo bc : List Bool} {i : Nat} (hi : i < n) (h : box bc i = true) :
    i ∈ keptIdx n bo bc :=
  mem_keptIdx_iff.2 ⟨hi, compared_of_cand h⟩

theorem dropped_no_box {n : Nat} {bo bc : List Bool} {i : Nat} (hi : i < n) (h : i ∉ keptIdx n bo bc) :
    box bo i = false ∧ box bc i = false := by
  apply not_compared_iff.1
  cases hc : comparedAt bo bc i
  · rfl
  · exact absurd (mem_keptIdx_iff.2 ⟨hi, hc⟩) h

theorem keptIdx_length_le (n : Nat) (bo bc : List Bool) : (keptIdx n bo bc).length ≤ n := by
  have := List.length_filter_le (comparedAt bo bc) (List.range n)
  simpa [keptIdx] using this

theorem keptIdx_all {n : Nat} {bo bc : List Bool} (h : ∀ i < n, box bo i = true) : keptIdx n bo bc = List.range n := by
  unfold keptIdx
  apply List.filter_eq_self.2
  intro i hi
  exact compared_of_orig (h i (List.mem_range.1 hi))

theorem keptIdx_none {n : Nat} {bo bc : List Bool} (h : ∀ i < n, box bo i = false ∧ box bc i = false) :
    keptIdx n bo bc = [] := by
  unfold keptIdx
  apply List.filter_eq_nil_iff.2
  intro i hi
  simp [comparedAt, (h i (List.mem_range.1 hi)).1, (h i (List.mem_range.1 hi)).2]

theorem paint_box (v : Nat) : paint true v = some v := rfl

theorem paint_box_inj {v w : Nat} (h : paint true v = paint true w) : v = w := by
  simpa [paint] using h

theorem skip_hides_nothing {bo bc : List Bool} {i : Nat} (h : comparedAt bo bc i = false) (vo vc : Nat) :
    paint (box bo i) vo = paint (box bc i) vc := by
  obtain ⟨ho, hc⟩ := not_compared_iff.1 h
  simp [paint, ho, hc]

theorem skipped_iff_both_paint_nothing {bo bc : List Bool} {i : Nat} :
    comparedAt bo bc i = false ↔ ∀ v, paint (box bo i) v = none ∧ paint (box bc i) v = none := by
  constructor
  · intro h v
    obtain ⟨ho, hc⟩ := not_compared_iff.1 h
    simp [paint, ho, hc]
  · intro h
    apply not_compared_iff.2
    have h0 := h 0
    constructor
    · cases hb : box bo i
      · rfl
      · simp [paint, hb] at h0
    · cases hb : box bc i
      · rfl
      · simp [paint, hb] at h0

open Fw.Parts.HeroExitScrollOffset in
/-- The painted counts of run 40156078840 read as the box bits of one element. -/
def boxesOfCell (u : NewUnit) : List Bool × List Bool := ([decide (0 < u.paintedOrig)], [decide (0 < u.paintedCand)])

open Fw.Parts.HeroExitScrollOffset in
theorem measured_skipped : ∀ u ∈ units, comparedAt (boxesOfCell u).1 (boxesOfCell u).2 0 = false := by decide

/-- One golden case: positions `n`, the box bits of each arm, the kept indices. -/
structure Case where
  name : String
  n : Nat
  bo : List Bool
  bc : List Bool

def cases : List Case := [
  ⟨"all rendered", 4, [true, true, true, true], [true, true, true, true]⟩,
  ⟨"none rendered", 4, [false, false, false, false], [false, false, false, false]⟩,
  ⟨"orig only", 3, [true, false, true], [false, false, false]⟩,
  ⟨"cand only", 3, [false, false, false], [false, true, false]⟩,
  ⟨"mixed", 5, [true, false, false, true, false], [true, false, true, false, false]⟩,
  ⟨"cand shorter, orig rendered", 3, [true, true, true], [true]⟩,
  ⟨"cand shorter, orig hidden", 3, [false, false, false], [false]⟩,
  ⟨"no readings", 2, [], []⟩]

#guard (cases.map fun c => keptIdx c.n c.bo c.bc) ==
  [[0, 1, 2, 3], [], [0, 2], [1], [0, 2, 3], [0, 1, 2], [], []]

def numJ (i : Nat) : Json := .num i

def caseLine (c : Case) : String :=
  (Json.mkObj [("fn", .str "keep"),
    ("in", Json.mkObj [("name", .str c.name), ("n", .num c.n), ("boxOrig", .arr (c.bo.map .bool).toArray),
      ("boxCand", .arr (c.bc.map .bool).toArray)]),
    ("out", Json.mkObj [("kept", .arr ((keptIdx c.n c.bo c.bc).map numJ).toArray)])]).compress

def goldenLines (_ : Unit := ()) : List String := cases.map caseLine

def path : String := "../packages/contracts/golden/gate/consumer.jsonl"

def text (_ : Unit := ()) : String := String.join (goldenLines.map (· ++ "\n"))

def gen (args : List String) : IO Unit := do
  if args.contains "--check" then
    let disk ← IO.FS.readFile path
    if disk != text then
      throw (IO.userError s!"consumer: {path} is stale; regenerate with Fw.Gate.Consumer.gen []")
    IO.println s!"consumer: {path} equals the Lean output, {goldenLines.length} lines"
  else
    IO.FS.writeFile path text

end Fw.Gate.Consumer

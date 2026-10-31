import Lean
namespace Fw.Ops.LandDry
open Lean

/-- The four phases of `fw land --dry`, in the order the land reports a refusal. -/
inductive Phase
  | reads
  | lints
  | ledger
  | loc
deriving Repr, DecidableEq

/-- The order that names the refusal: the first failing phase in this list. -/
def order : List Phase := [.reads, .lints, .ledger, .loc]

/-- Pass or fail of each phase. -/
structure Res where
  reads : Bool
  lints : Bool
  ledger : Bool
  loc : Bool
deriving Repr, DecidableEq

def Res.pass (r : Res) : Phase → Bool
  | .reads => r.reads
  | .lints => r.lints
  | .ledger => r.ledger
  | .loc => r.loc

/-- The old protocol: each phase runs only when every earlier one passed; the first failure ends the dry land. -/
def seqVerdict (r : Res) : Option Phase :=
  if !r.reads then some .reads else if !r.lints then some .lints else if !r.ledger then some .ledger
  else if !r.loc then some .loc else none

/-- The phases the old protocol ran. -/
def seqRan (r : Res) : List Phase :=
  if !r.reads then [.reads] else if !r.lints then [.reads, .lints] else if !r.ledger then [.reads, .lints, .ledger]
  else order

/-- The new protocol runs every phase's checks, then names the first failing phase of `order`. -/
def parVerdict (r : Res) : Option Phase := order.find? fun p => !r.pass p

/-- The phases the new protocol runs. -/
def parRan : List Phase := order

/-- **Same verdict.** For the same phase results the new protocol names the same refusal as the old one. -/
theorem par_eq_seq (r : Res) : parVerdict r = seqVerdict r := by
  cases r with
  | mk a b c d => cases a <;> cases b <;> cases c <;> cases d <;> rfl

/-- **No check dropped.** Every phase the old protocol ran, the new one runs. -/
theorem seqRan_sub_parRan (r : Res) : ∀ p ∈ seqRan r, p ∈ parRan := by
  intro p hp
  cases p <;> simp [parRan, order]

/-- The dry land is ok exactly when all four phases pass. -/
theorem par_none_iff (r : Res) : parVerdict r = none ↔ r.reads = true ∧ r.lints = true ∧ r.ledger = true ∧ r.loc = true := by
  rw [par_eq_seq]
  cases r with
  | mk a b c d => cases a <;> cases b <;> cases c <;> cases d <;> simp [seqVerdict]

/-- A failing reads phase is always the refusal named, whatever the later phases did. -/
theorem par_reads_first (r : Res) (h : r.reads = false) : parVerdict r = some .reads := by
  rw [par_eq_seq]; simp [seqVerdict, h]

/-- A failing lints phase is named when reads passed, whatever ledger and local did. -/
theorem par_lints_second (r : Res) (h0 : r.reads = true) (h : r.lints = false) : parVerdict r = some .lints := by
  rw [par_eq_seq]; simp [seqVerdict, h0, h]

/-- A failing ledger phase is named when reads and lints passed, whatever local did. -/
theorem par_ledger_third (r : Res) (h0 : r.reads = true) (h1 : r.lints = true) (h : r.ledger = false) :
    parVerdict r = some .ledger := by
  rw [par_eq_seq]; simp [seqVerdict, h0, h1, h]

/-- A failing local phase is named only when the three earlier phases passed. -/
theorem par_loc_last (r : Res) (h0 : r.reads = true) (h1 : r.lints = true) (h2 : r.ledger = true) (h : r.loc = false) :
    parVerdict r = some .loc := by
  rw [par_eq_seq]; simp [seqVerdict, h0, h1, h2, h]

/-- The waves of checks: the phases of one wave start together; the next wave starts when the wave before it has finished.
The lake build of the lints and the fwcore build of the local tests share one build tree, so with both they never overlap. -/
def waves (lakeLint needsBuild : Bool) : List (List Phase) :=
  if lakeLint && needsBuild then [[.reads, .lints], [.loc]] else [[.reads, .lints, .loc]]

/-- Every phase that holds checks is in exactly one wave. -/
theorem waves_cover (a b : Bool) (p : Phase) (h : p = .reads ∨ p = .lints ∨ p = .loc) :
    (waves a b).flatten.count p = 1 := by
  rcases h with rfl | rfl | rfl <;> cases a <;> cases b <;> decide

/-- The ledger-note check is not a wave: it is a short read of the merge tree, run after the waves. -/
theorem waves_no_ledger (a b : Bool) : Phase.ledger ∉ (waves a b).flatten := by
  cases a <;> cases b <;> decide

/-- With both builds, the lake lints and the local tests never start together. -/
theorem waves_build_serial : waves true true = [[.reads, .lints], [.loc]] := rfl

/-- Without a build conflict, one wave holds all three. -/
theorem waves_free (a b : Bool) (h : (a && b) = false) : waves a b = [[.reads, .lints, .loc]] := by
  simp [waves, h]

/-- The lake pass record is written only when the reads and the lints both passed and the lake lint ran. -/
def recordLake (r : Res) (lakeRan : Bool) : Bool := r.reads && r.lints && lakeRan

theorem recordLake_needs_reads (r : Res) (l : Bool) (h : recordLake r l = true) : r.reads = true := by
  simp [recordLake] at h; exact h.1.1

theorem recordLake_needs_lints (r : Res) (l : Bool) (h : recordLake r l = true) : r.lints = true := by
  simp [recordLake] at h; exact h.1.2

#guard waves true true == [[.reads, .lints], [.loc]]
#guard waves true false == [[.reads, .lints, .loc]]
#guard parVerdict ⟨true, false, false, false⟩ == some .lints

structure Row where
  r : Res
  lakeLint : Bool
  needsBuild : Bool
deriving Repr

def phaseName : Phase → String
  | .reads => "reads"
  | .lints => "lints"
  | .ledger => "ledger"
  | .loc => "local"

def optName : Option Phase → Json
  | none => Json.null
  | some p => Json.str (phaseName p)

def namesJson (l : List Phase) : Json := Json.arr (l.map (Json.str ∘ phaseName)).toArray

def rowJson (w : Row) : Json :=
  Json.mkObj [("ledger", w.r.ledger), ("lakeLint", w.lakeLint), ("lints", w.r.lints), ("local", w.r.loc),
    ("needsBuild", w.needsBuild), ("ranOld", namesJson (seqRan w.r)),
    ("reads", w.r.reads), ("verdict", optName (parVerdict w.r)),
    ("waves", Json.arr ((waves w.lakeLint w.needsBuild).map namesJson).toArray)]

def rows : List Row :=
  let ok : Res := ⟨true, true, true, true⟩
  [⟨ok, true, true⟩, ⟨ok, true, false⟩, ⟨ok, false, true⟩, ⟨ok, false, false⟩,
   ⟨{ ok with reads := false }, true, false⟩,
   ⟨{ ok with lints := false }, true, true⟩,
   ⟨{ ok with ledger := false }, false, false⟩,
   ⟨{ ok with loc := false }, false, true⟩,
   ⟨⟨false, false, false, false⟩, true, true⟩,
   ⟨⟨true, false, true, false⟩, false, false⟩,
   ⟨⟨true, true, false, false⟩, true, false⟩]

def jsonl (_ : Unit) : String := String.join (rows.map fun r => (rowJson r).compress ++ "\n")

end Fw.Ops.LandDry

import Lean
namespace Fw.Ops.LandDry
open Lean

inductive Phase
  | reads
  | lints
  | ledger
  | loc
deriving Repr, DecidableEq

def order : List Phase := [.reads, .lints, .ledger, .loc]

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

def seqVerdict (r : Res) : Option Phase :=
  if !r.reads then some .reads else if !r.lints then some .lints else if !r.ledger then some .ledger
  else if !r.loc then some .loc else none

def seqRan (r : Res) : List Phase :=
  if !r.reads then [.reads] else if !r.lints then [.reads, .lints] else if !r.ledger then [.reads, .lints, .ledger]
  else order

def parVerdict (r : Res) : Option Phase := order.find? fun p => !r.pass p

def parRan : List Phase := order

theorem par_eq_seq (r : Res) : parVerdict r = seqVerdict r := by
  cases r with
  | mk a b c d => cases a <;> cases b <;> cases c <;> cases d <;> rfl

theorem seqRan_sub_parRan (r : Res) : ∀ p ∈ seqRan r, p ∈ parRan := by
  intro p hp
  cases p <;> simp [parRan, order]

theorem par_none_iff (r : Res) : parVerdict r = none ↔ r.reads = true ∧ r.lints = true ∧ r.ledger = true ∧ r.loc = true := by
  rw [par_eq_seq]
  cases r with
  | mk a b c d => cases a <;> cases b <;> cases c <;> cases d <;> simp [seqVerdict]

theorem par_reads_first (r : Res) (h : r.reads = false) : parVerdict r = some .reads := by
  rw [par_eq_seq]; simp [seqVerdict, h]

theorem par_lints_second (r : Res) (h0 : r.reads = true) (h : r.lints = false) : parVerdict r = some .lints := by
  rw [par_eq_seq]; simp [seqVerdict, h0, h]

theorem par_ledger_third (r : Res) (h0 : r.reads = true) (h1 : r.lints = true) (h : r.ledger = false) :
    parVerdict r = some .ledger := by
  rw [par_eq_seq]; simp [seqVerdict, h0, h1, h]

theorem par_loc_last (r : Res) (h0 : r.reads = true) (h1 : r.lints = true) (h2 : r.ledger = true) (h : r.loc = false) :
    parVerdict r = some .loc := by
  rw [par_eq_seq]; simp [seqVerdict, h0, h1, h2, h]

def waves : List (List Phase) := [[.reads, .lints, .loc]]

theorem waves_cover (p : Phase) (h : p = .reads ∨ p = .lints ∨ p = .loc) : waves.flatten.count p = 1 := by
  rcases h with rfl | rfl | rfl <;> decide

theorem waves_no_ledger : Phase.ledger ∉ waves.flatten := by decide

theorem waves_single : waves.length = 1 := rfl

inductive Kind
  | install
  | lakeLint
  | fwcoreBuild
  | coreUser
  | other
deriving Repr, DecidableEq

def Kind.buildsLake : Kind → Bool
  | .lakeLint => true
  | .fwcoreBuild => true
  | _ => false

def kindDep : Kind → Kind → Bool
  | .install, _ => false
  | _, .install => true
  | .fwcoreBuild, .lakeLint => true
  | .coreUser, .fwcoreBuild => true
  | .coreUser, .lakeLint => true
  | _, _ => false

def edge (ks : List Kind) (i j : Nat) : Bool :=
  match ks[i]?, ks[j]? with
  | some a, some b => i != j && (kindDep a b || (a.buildsLake && a == b && j < i))
  | _, _ => false

def deps (ks : List Kind) : List (List Nat) :=
  (List.range ks.length).map fun i => (List.range ks.length).filter (edge ks i)

theorem mem_deps (ks : List Kind) (i j : Nat) :
    j ∈ (deps ks).getD i [] ↔ i < ks.length ∧ j < ks.length ∧ edge ks i j = true := by
  by_cases hi : i < ks.length
  · simp [deps, List.getD_eq_getElem?_getD, hi]
  · simp [deps, List.getD_eq_getElem?_getD, hi]

theorem lake_serial (ks : List Kind) (i j : Nat) (ha : i < ks.length) (hb : j < ks.length) (hne : i ≠ j)
    (hi : (ks[i]'ha).buildsLake = true) (hj : (ks[j]'hb).buildsLake = true) :
    j ∈ (deps ks).getD i [] ∨ i ∈ (deps ks).getD j [] := by
  rw [mem_deps, mem_deps]
  have ei : ks[i]? = some ks[i] := List.getElem?_eq_getElem ha
  have ej : ks[j]? = some ks[j] := List.getElem?_eq_getElem hb
  simp only [edge, ei, ej, ha, hb, true_and]
  revert hi hj
  generalize ks[i] = a; generalize ks[j] = b
  have hne' : j ≠ i := fun h => hne h.symm
  rcases Nat.lt_or_gt_of_ne hne with h | h <;>
  cases a <;> cases b <;> simp [Kind.buildsLake, kindDep, hne, hne', h] <;> omega

theorem core_after_builds (ks : List Kind) (i j : Nat) (ha : i < ks.length) (hb : j < ks.length)
    (hi : ks[i]'ha = .coreUser) (hj : (ks[j]'hb).buildsLake = true) :
    j ∈ (deps ks).getD i [] := by
  rw [mem_deps]
  refine ⟨ha, hb, ?_⟩
  have ei : ks[i]? = some ks[i] := List.getElem?_eq_getElem ha
  have ej : ks[j]? = some ks[j] := List.getElem?_eq_getElem hb
  have hne : i ≠ j := by
    intro h; subst h; rw [hi] at hj; simp [Kind.buildsLake] at hj
  simp only [edge, ei, ej, hi]
  revert hj
  generalize ks[j] = b
  cases b <;> simp [Kind.buildsLake, kindDep, hne]

theorem install_first (ks : List Kind) (i j : Nat) (ha : i < ks.length) (hb : j < ks.length)
    (hj : ks[j]'hb = .install) (hi : ks[i]'ha ≠ .install) : j ∈ (deps ks).getD i [] := by
  rw [mem_deps]
  refine ⟨ha, hb, ?_⟩
  have ei : ks[i]? = some ks[i] := List.getElem?_eq_getElem ha
  have ej : ks[j]? = some ks[j] := List.getElem?_eq_getElem hb
  have hne : i ≠ j := by intro h; subst h; exact hi hj
  simp only [edge, ei, ej, hj]
  revert hi
  generalize ks[i] = a
  cases a <;> simp [kindDep, hne]

def Kind.rank : Kind → Nat
  | .install => 0
  | .lakeLint => 1
  | .fwcoreBuild => 2
  | .coreUser => 3
  | .other => 1

theorem kindDep_rank (a b : Kind) (h : kindDep a b = true) : b.rank < a.rank := by
  cases a <;> cases b <;> simp_all [kindDep, Kind.rank]

def recordLake (r : Res) (lakeRan : Bool) : Bool := r.reads && r.lints && lakeRan

theorem recordLake_needs_reads (r : Res) (l : Bool) (h : recordLake r l = true) : r.reads = true := by
  simp [recordLake] at h; exact h.1.1

theorem recordLake_needs_lints (r : Res) (l : Bool) (h : recordLake r l = true) : r.lints = true := by
  simp [recordLake] at h; exact h.1.2

#guard waves == [[.reads, .lints, .loc]]
#guard parVerdict ⟨true, false, true, true⟩ == some .lints
#guard deps [.install, .lakeLint, .fwcoreBuild, .fwcoreBuild, .coreUser, .other] ==
  [[], [0], [0, 1], [0, 1, 2], [0, 1, 2, 3], [0]]
#guard deps [.fwcoreBuild, .fwcoreBuild] == [[], [0]]
#guard deps [.other, .lakeLint] == [[], []]

structure Row where
  r : Res
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
  Json.mkObj [("ledger", w.r.ledger), ("lints", w.r.lints), ("local", w.r.loc),
    ("ranOld", namesJson (seqRan w.r)),
    ("reads", w.r.reads), ("verdict", optName (parVerdict w.r)),
    ("waves", Json.arr (waves.map namesJson).toArray)]

def rows : List Row :=
  let ok : Res := ⟨true, true, true, true⟩
  [⟨ok⟩, ⟨{ ok with reads := false }⟩,
   ⟨{ ok with lints := false }⟩,
   ⟨{ ok with ledger := false }⟩,
   ⟨{ ok with loc := false }⟩,
   ⟨⟨false, false, false, false⟩⟩,
   ⟨⟨true, false, true, false⟩⟩,
   ⟨⟨true, true, false, false⟩⟩]

def kindName : Kind → String
  | .install => "install"
  | .lakeLint => "lakeLint"
  | .fwcoreBuild => "fwcoreBuild"
  | .coreUser => "coreUser"
  | .other => "other"

def depsRowJson (ks : List Kind) : Json :=
  Json.mkObj [("deps", Json.arr ((deps ks).map fun d => Json.arr (d.map fun n => toJson n).toArray).toArray),
    ("kinds", Json.arr (ks.map (Json.str ∘ kindName)).toArray)]

def depsRows : List (List Kind) :=
  [[], [.other], [.install, .other],
   [.install, .coreUser, .other, .lakeLint, .fwcoreBuild, .other, .coreUser, .coreUser, .coreUser],
   [.coreUser, .fwcoreBuild, .lakeLint, .install, .other],
   [.install, .lakeLint, .coreUser], [.lakeLint, .coreUser], [.fwcoreBuild, .lakeLint],
   [.lakeLint, .lakeLint, .fwcoreBuild], [.fwcoreBuild, .fwcoreBuild],
   [.install, .install, .other], [.other, .other, .coreUser],
   [.install, .lakeLint, .fwcoreBuild, .fwcoreBuild, .coreUser, .other]]

def depsJsonl (_ : Unit) : String := String.join (depsRows.map fun ks => (depsRowJson ks).compress ++ "\n")

def jsonl (_ : Unit) : String := String.join (rows.map fun r => (rowJson r).compress ++ "\n")

end Fw.Ops.LandDry

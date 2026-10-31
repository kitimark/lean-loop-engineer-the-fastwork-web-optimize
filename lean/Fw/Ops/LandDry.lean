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
One wave holds the reads, lints and local phases. Which checks inside the wave wait for which is the decision of `deps`
below: two `lake build` runs in one `lean/.lake` never overlap, because `lake_slot` (`Fw.Sched.LakeSlot`) holds two
slots and Lake takes no lock on the build directory (`Lake/Util/Lock.lean:17-20`). -/
def waves : List (List Phase) := [[.reads, .lints, .loc]]

/-- Every phase that holds checks is in exactly one wave. -/
theorem waves_cover (p : Phase) (h : p = .reads ∨ p = .lints ∨ p = .loc) : waves.flatten.count p = 1 := by
  rcases h with rfl | rfl | rfl <;> decide

/-- The ledger-note check is not a wave: it is a short read of the merge tree, run after the wave. -/
theorem waves_no_ledger : Phase.ledger ∉ waves.flatten := by decide

/-- The old protocol ran its checks in three steps; the new one starts them together, so no wave is later than the first. -/
theorem waves_single : waves.length = 1 := rfl

/-- What a check is, by its command line (identity, not inference): the install, the lake lint (`lake build` and the axiom
check), the fwcore build script, a test that runs the `fwcore` binary, or anything else. -/
inductive Kind
  | install
  | lakeLint
  | fwcoreBuild
  | coreUser
  | other
deriving Repr, DecidableEq

/-- The kinds that run `lake build` in the worktree's `lean/.lake` (the fwcore build script ends in `lake build`). -/
def Kind.buildsLake : Kind → Bool
  | .lakeLint => true
  | .fwcoreBuild => true
  | _ => false

/-- Kind `a` must wait for kind `b`: every check waits for the install; the fwcore build waits for the lake lint; a
`fwcore` user waits for the fwcore build and, directly, for the lake lint (the build step can be absent while the lint runs). -/
def kindDep : Kind → Kind → Bool
  | .install, _ => false
  | _, .install => true
  | .fwcoreBuild, .lakeLint => true
  | .coreUser, .fwcoreBuild => true
  | .coreUser, .lakeLint => true
  | _, _ => false

/-- Check `i` waits for check `j`: the kind rule, plus an index order between two checks that both build the lake
(a plan that holds two lake lints still runs them one after the other). -/
def edge (ks : List Kind) (i j : Nat) : Bool :=
  match ks[i]?, ks[j]? with
  | some a, some b => i != j && (kindDep a b || (a.buildsLake && a == b && j < i))
  | _, _ => false

/-- For each check of the list, the indices it waits for. -/
def deps (ks : List Kind) : List (List Nat) :=
  (List.range ks.length).map fun i => (List.range ks.length).filter (edge ks i)

theorem mem_deps (ks : List Kind) (i j : Nat) :
    j ∈ (deps ks).getD i [] ↔ i < ks.length ∧ j < ks.length ∧ edge ks i j = true := by
  by_cases hi : i < ks.length
  · simp [deps, List.getD_eq_getElem?_getD, hi]
  · simp [deps, List.getD_eq_getElem?_getD, hi]

/-- **Lake builds are serial.** Two different checks that both build the lake are ordered: one waits for the other. So two
`lake build` processes never share one `lean/.lake`. -/
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

/-- **A `fwcore` user runs after every lake build.** Every check that runs the `fwcore` binary waits for every lake lint and
every fwcore build of the list, so none runs while a `lake build` can still relink `lean/.lake/build/bin/fwcore`. -/
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

/-- Every check waits for the install, and the install waits for nothing. -/
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

/-- The order of the kinds in which a wait points downward. -/
def Kind.rank : Kind → Nat
  | .install => 0
  | .lakeLint => 1
  | .fwcoreBuild => 2
  | .coreUser => 3
  | .other => 1

/-- **No cycle between kinds.** A kind waits only for a kind of lower rank, so the kind rule never deadlocks the pool. -/
theorem kindDep_rank (a b : Kind) (h : kindDep a b = true) : b.rank < a.rank := by
  cases a <;> cases b <;> simp_all [kindDep, Kind.rank]

/-- The lake pass record is written only when the reads and the lints both passed and the lake lint ran. -/
def recordLake (r : Res) (lakeRan : Bool) : Bool := r.reads && r.lints && lakeRan

theorem recordLake_needs_reads (r : Res) (l : Bool) (h : recordLake r l = true) : r.reads = true := by
  simp [recordLake] at h; exact h.1.1

theorem recordLake_needs_lints (r : Res) (l : Bool) (h : recordLake r l = true) : r.lints = true := by
  simp [recordLake] at h; exact h.1.2

#guard waves == [[.reads, .lints, .loc]]
#guard parVerdict ⟨true, false, true, true⟩ == some .lints

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

/-- The kind lists of the golden: the exact check set of the measured change (task `dry-land-waves`), the same set in
other orders, a list with two lake lints, and lists without the build step. -/
def depsRows : List (List Kind) :=
  [[], [.other], [.install, .other],
   [.install, .coreUser, .other, .lakeLint, .fwcoreBuild, .other, .coreUser, .coreUser, .coreUser],
   [.coreUser, .fwcoreBuild, .lakeLint, .install, .other],
   [.install, .lakeLint, .coreUser], [.lakeLint, .coreUser], [.fwcoreBuild, .lakeLint],
   [.lakeLint, .lakeLint, .fwcoreBuild], [.fwcoreBuild, .fwcoreBuild],
   [.install, .install, .other], [.other, .other, .coreUser]]

def depsJsonl (_ : Unit) : String := String.join (depsRows.map fun ks => (depsRowJson ks).compress ++ "\n")

def jsonl (_ : Unit) : String := String.join (rows.map fun r => (rowJson r).compress ++ "\n")

end Fw.Ops.LandDry

import Fw.Ops.Cache
import Fw.Ops.LakeJobsGen
import Fw.Ci.Trigger
/-!
# Who saves the Lake artifact cache (task `site-build-cache`)

The rules over every CI job that runs `.github/actions/setup-lean`: exactly one job saves the Lake cache
(`save: 'true'`), the `lean` job of `lean.yml`, and every job's Lake targets are covered by the writer's targets.
`ok_complete` proves (with `Fw.Ops.Cache.cache_complete`) that then, on the writer's source tree, no job rebuilds a
module; `one_writer` and `table_complete` apply that to the real jobs.

The rows are not copied by hand: `scripts/ci-paths.mjs --write` reads them from the workflows (each job's `save:` and
the `lake build` / `lake exe` / `lake test` invocations its `run:` blocks reach) into the generated module
`Fw.Ops.LakeJobsGen`, and `scripts/ci-paths.mjs --check` (a land check) fails when that module is stale. A new
setup-lean job therefore needs no hand edit; the Lean build fails only when a row breaks a rule, with the message of
`violations`. Premise this module cannot check: the scanner reads every Lake target a job builds.
-/
namespace Fw.Ops.LakeCache
open Lean Fw.Ops.Cache

/-- A CI job that restores the Lake cache: workflow file, job id, saves or only restores, the Lake targets it builds. -/
structure LakeJob where
  file : String
  job : String
  saves : Bool
  targets : List String
deriving Repr, DecidableEq

/-- The job that must be the one writer: workflow `lean.yml`, job `lean` (it runs `lake build` and
`lean/scripts/check.sh`, so it builds every default target and `fwtest`). -/
def isWriter (j : LakeJob) : Bool := j.file == "lean.yml" && j.job == "lean"

/-- The writer row of a job list: the first job that `isWriter` accepts, if any. -/
def writerOf (js : List LakeJob) : Option LakeJob := js.find? isWriter

/-- Import facts the coverage rule may use, as (module, Lake target whose root imports it), generated with the rows. -/
def importFacts : List (String × String) := Fw.Ops.LakeJobsGen.importFacts

/-- The targets of `j` the writer `w` does not cover: those that are no writer target and that no import fact puts
in the cone of a writer target. -/
def uncovered (w j : LakeJob) : List String :=
  j.targets.filter fun t => !(w.targets.contains t || importFacts.any fun f => f.1 == t && w.targets.contains f.2)

/-- `w` covers `j`: every target of `j` is a writer target, or a module that an import fact puts in the cone of a
writer target. -/
def coveredBy (w j : LakeJob) : Bool :=
  j.targets.all fun t => w.targets.contains t || importFacts.any fun f => f.1 == t && w.targets.contains f.2

/-- **The rules.** A writer row exists, the jobs that save are exactly `[w]`, and every job builds at least one
target the scanner read and is covered by `w`. -/
def ok (js : List LakeJob) : Bool :=
  match writerOf js with
  | none => false
  | some w => js.filter (·.saves) == [w] && js.all fun j => !j.targets.isEmpty && coveredBy w j

/-- A job as `file/job`. -/
def name (j : LakeJob) : String := j.file ++ "/" ++ j.job

/-- What breaks the rules, one message per broken rule and job (diagnostics for the build log; `ok` decides). -/
def violations (js : List LakeJob) : List String :=
  match writerOf js with
  | none => ["no job lean.yml/lean uses setup-lean: the Lake cache has no writer"]
  | some w =>
    let savers := js.filter (·.saves)
    (if savers == [w] then [] else
      [s!"the jobs that pass save: 'true' to setup-lean are {savers.map name}; exactly [lean.yml/lean] must"]) ++
    js.filterMap (fun j => if j.targets.isEmpty then some s!"{name j}: uses setup-lean but builds no Lake target the scanner reads (scripts/ci-paths.mjs)" else none) ++
    js.filterMap fun j =>
      let u := uncovered w j
      if u.isEmpty then none else some s!"{name j}: builds {u}, which lean.yml/lean (the cache writer) does not build"

/-- The table: one job per generated row. -/
def jobs : List LakeJob := Fw.Ops.LakeJobsGen.rows.map fun (f, j, s, t) => ⟨f, j, s, t⟩

-- A readable build error when a workflow breaks a rule (the theorems below would only say `decide` failed).
#eval show IO Unit from do
  let v := violations jobs
  unless v.isEmpty do
    throw <| IO.userError ("Lake cache rules broken by the workflows (Fw.Ops.LakeCache):\n  " ++ "\n  ".intercalate v)

#guard ok jobs == (violations jobs).isEmpty
#guard (jobs.map fun j => (j.file, j.job)).eraseDups.length == jobs.length
-- the rules reject: a second saver, no writer, an empty job, an uncovered target
#guard ok [⟨"lean.yml", "lean", true, ["Fw"]⟩, ⟨"x.yml", "y", false, ["Fw"]⟩] == true
#guard ok [⟨"lean.yml", "lean", true, ["Fw"]⟩, ⟨"x.yml", "y", true, ["Fw"]⟩] == false
#guard ok [⟨"lean.yml", "lean", false, ["Fw"]⟩] == false
#guard ok [⟨"x.yml", "y", true, ["Fw"]⟩] == false
#guard ok [] == false
#guard ok [⟨"lean.yml", "lean", true, ["Fw"]⟩, ⟨"x.yml", "y", false, []⟩] == false
#guard ok [⟨"lean.yml", "lean", true, ["Fw"]⟩, ⟨"x.yml", "y", false, ["Fw.Gate.Scope"]⟩] == false
#guard (violations [⟨"lean.yml", "lean", true, ["Fw"]⟩, ⟨"x.yml", "y", true, ["Fw"]⟩]).length == 1
#guard coveredBy ⟨"lean.yml", "lean", true, ["fwtest"]⟩ ⟨"x.yml", "y", false, ["FwTest.Mutants.Kill"]⟩ ==
  importFacts.contains ("FwTest.Mutants.Kill", "fwtest")

/-- A covered job's targets are all in the writer's cone, for every import graph in which the import facts hold. -/
theorem covered_inCone (deps : String → List String) (hf : ∀ f ∈ importFacts, InCone deps [f.2] f.1)
    (w j : LakeJob) (hc : coveredBy w j = true) : ∀ t ∈ j.targets, InCone deps w.targets t := by
  intro t ht
  have h := List.all_eq_true.mp hc t ht
  simp only [Bool.or_eq_true, List.contains_iff_mem, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] at h
  rcases h with hw | ⟨f, hfm, hft, hfw⟩
  · exact InCone.root hw
  · subst hft
    exact inCone_mono deps w.targets [f.2] (fun x hx => by simp at hx; subst hx; exact hfw) (hf f hfm)

/-- **One writer, for every job list that keeps the rules.** If `ok(J)`, the writer row exists and
the jobs that save are exactly it. -/
theorem ok_one_writer (js : List LakeJob) (h : ok js = true) :
    ∃ w, writerOf js = some w ∧ js.filter (·.saves) = [w] := by
  unfold ok at h
  cases hw : writerOf js with
  | none => simp [hw] at h
  | some w =>
    simp only [hw, Bool.and_eq_true, beq_iff_eq] at h
    exact ⟨w, rfl, h.1⟩

/-- **Every job is covered, for every job list that keeps the rules.** -/
theorem ok_covered (js : List LakeJob) (h : ok js = true) (w : LakeJob) (hw : writerOf js = some w) :
    ∀ j ∈ js, j.targets ≠ [] ∧ coveredBy w j = true := by
  intro j hj
  unfold ok at h
  simp only [hw, Bool.and_eq_true, List.all_eq_true, Bool.not_eq_true', List.isEmpty_eq_false_iff] at h
  exact h.2 j hj

/-- **Cache completeness, for every job list that keeps the rules.** On the writer's source tree, whatever entry
the writer restored, the entry it saves holds every module any job needs: no job rebuilds a module (given the
import facts). -/
theorem ok_complete {H : Type} (js : List LakeJob) (h : ok js = true) (w : LakeJob) (hw : writerOf js = some w)
    (deps : String → List String) (hash : String → H) (C : Entry H)
    (hf : ∀ f ∈ importFacts, InCone deps [f.2] f.1) :
    ∀ j ∈ js, ∀ m, ¬ Rebuilds deps hash (afterBuild deps hash C w.targets) j.targets m :=
  fun j hj m => cache_complete deps hash C w.targets j.targets
    (covered_inCone deps hf w j (ok_covered js h w hw j hj).2) m

/-- The generated table keeps the rules. -/
theorem jobs_ok : ok jobs = true := by decide

/-- **One writer.** In the table read from the workflows, the writer row exists and the jobs that save the Lake
cache are exactly it. -/
theorem one_writer : ∃ w, writerOf jobs = some w ∧ jobs.filter (·.saves) = [w] := ok_one_writer jobs jobs_ok

/-- **The table is complete.** For the jobs read from the workflows: on the writer's source tree, whatever entry the
writer restored, the entry it saves holds every module any job needs (given the import facts). -/
theorem table_complete {H : Type} (w : LakeJob) (hw : writerOf jobs = some w) (deps : String → List String)
    (hash : String → H) (C : Entry H) (hf : ∀ f ∈ importFacts, InCone deps [f.2] f.1) :
    ∀ j ∈ jobs, ∀ m, ¬ Rebuilds deps hash (afterBuild deps hash C w.targets) j.targets m :=
  ok_complete jobs jobs_ok w hw deps hash C hf

/-- The Lake cache writers of the generated job table are the `.lake-cache` rows of `Fw.Ci.Trigger.cacheWriters`. -/
theorem lake_writers : (jobs.filter (·.saves)).map (fun j => (j.file, j.job, ".lake-cache")) =
    Fw.Ci.Trigger.cacheWriters.filter (·.2.2 == ".lake-cache") := by
  decide

structure CacheFile where
  artifact : Bool
  links : Nat
deriving Repr, DecidableEq

def CacheFile.cases : List CacheFile := [⟨false, 1⟩, ⟨true, 1⟩, ⟨true, 2⟩, ⟨true, 7⟩]

def keeps (f : CacheFile) : Bool := !(f.artifact && f.links == 1)

theorem keeps_outputs (n : Nat) : keeps ⟨false, n⟩ = true := by simp [keeps]

theorem keeps_linked (n : Nat) (h : 2 ≤ n) : keeps ⟨true, n⟩ = true := by
  have : (n == 1) = false := by simp; omega
  simp [keeps, this]

theorem prunes_unlinked : keeps ⟨true, 1⟩ = false := by decide

structure RestoreLeg where
  run : Nat
  job : Nat
  hit : Bool
  filesChanged : Nat
  builtLines : Nat
  jobs : Nat
  setupS : Nat
deriving Repr, DecidableEq

inductive LegVerdict | ok | rebuilt | miss
deriving Repr, DecidableEq

def LegVerdict.name : LegVerdict → String
  | .ok => "ok" | .rebuilt => "rebuilt" | .miss => "miss"

def revertLines : Nat := 200

def verdict (l : RestoreLeg) : LegVerdict :=
  if !l.hit then .miss else if revertLines ≤ l.builtLines then .rebuilt else .ok

theorem verdict_miss (l : RestoreLeg) (h : l.hit = false) : verdict l = .miss := by simp [verdict, h]

theorem verdict_rebuilt (l : RestoreLeg) (h : l.hit = true) (n : revertLines ≤ l.builtLines) :
    verdict l = .rebuilt := by simp [verdict, h, n]

theorem verdict_ok (l : RestoreLeg) (h : l.hit = true) (n : l.builtLines < revertLines) : verdict l = .ok := by
  have : ¬ revertLines ≤ l.builtLines := by omega
  simp [verdict, h, this]

def legs : List RestoreLeg := [
  ⟨40010696608, 120610140089, true, 2, 48, 849, 19⟩, ⟨40010826449, 120610621304, true, 2, 48, 849, 24⟩,
  ⟨40011143247, 120611676101, true, 1, 51, 849, 19⟩,
  ⟨40011600530, 120613238438, true, 3, 44, 826, 18⟩, ⟨40011600530, 120613238475, true, 3, 43, 826, 17⟩,
  ⟨40011600530, 120613238494, true, 3, 43, 826, 18⟩, ⟨40011600530, 120613238669, true, 3, 43, 826, 20⟩,
  ⟨40011600530, 120613238767, true, 3, 43, 826, 20⟩, ⟨40011600647, 120613247310, true, 3, 44, 849, 18⟩,
  ⟨40012913395, 120617723600, true, 3, 44, 849, 18⟩]

theorem legs_ok : legs.all (fun l => verdict l == .ok) = true := by decide

theorem legs_built_max : legs.all (fun l => l.builtLines < revertLines) = true := by decide

structure GateRow where
  run : Nat
  waitS : Nat
  legBuildS : Nat
  ownS : Nat
  gapS : Nat
deriving Repr, DecidableEq

def GateRow.savedS (r : GateRow) : Nat := r.legBuildS - r.ownS

def GateRow.pays (r : GateRow) : Bool := r.waitS < r.savedS

def gateRows : List GateRow := [⟨39995255573, 62, 63, 12, 36⟩, ⟨39997746052, 123, 72, 12, 91⟩]

theorem no_gate_pays : gateRows.all (fun r => !r.pays) = true := by decide

theorem gate_unpaid (r : GateRow) (h : r.legBuildS ≤ r.waitS) : r.pays = false := by
  have : r.savedS ≤ r.waitS := by unfold GateRow.savedS; omega
  simp only [GateRow.pays, decide_eq_false_iff_not]; omega

structure ExeFacts where
  blobB : Nat
  rateBps : Nat
  relinkMs : Nat
deriving Repr, DecidableEq

def ExeFacts.gainMs (e : ExeFacts) : Nat := e.relinkMs - e.blobB * 1000 / e.rateBps

def minGainMs : Nat := 1000

def ExeFacts.keep (e : ExeFacts) : Bool := minGainMs ≤ e.gainMs

theorem exe_pruned (e : ExeFacts) (h : e.relinkMs < minGainMs) : e.keep = false := by
  have : e.gainMs ≤ e.relinkMs := Nat.sub_le _ _
  simp only [ExeFacts.keep, decide_eq_false_iff_not]; unfold minGainMs at *; omega

def exeFacts : ExeFacts := ⟨34117988, 100000000, 683⟩

theorem exe_measured : exeFacts.keep = false := by decide

def goldenLines : List Json :=
  (CacheFile.cases.map fun (f : CacheFile) => Json.mkObj [("kind", "prune"), ("artifact", toJson f.artifact),
      ("links", toJson f.links), ("keeps", toJson (keeps f))]) ++
  (legs.map fun l => Json.mkObj [("kind", "leg"), ("run", toJson l.run), ("job", toJson l.job), ("hit", toJson l.hit),
      ("filesChanged", toJson l.filesChanged), ("builtLines", toJson l.builtLines), ("jobs", toJson l.jobs),
      ("setupS", toJson l.setupS), ("verdict", Json.str (verdict l).name)]) ++
  (gateRows.map fun r => Json.mkObj [("kind", "gate"), ("run", toJson r.run), ("waitS", toJson r.waitS),
      ("legBuildS", toJson r.legBuildS), ("ownS", toJson r.ownS), ("gapS", toJson r.gapS),
      ("savedS", toJson r.savedS), ("pays", toJson r.pays)]) ++
  [Json.mkObj [("kind", "exe"), ("blobB", toJson exeFacts.blobB), ("rateBps", toJson exeFacts.rateBps),
      ("relinkMs", toJson exeFacts.relinkMs), ("gainMs", toJson exeFacts.gainMs), ("keep", toJson exeFacts.keep)]]

def goldenText : String := "\n".intercalate (goldenLines.map Json.compress) ++ "\n"

def gen (args : List String) : IO Unit := do
  let path := "../packages/contracts/golden/ops/lake-cache.jsonl"
  if args.contains "--check" then
    let disk ← IO.FS.readFile path
    if disk != goldenText then throw (IO.userError s!"lake-cache: {path} is stale; regenerate with Fw.Ops.LakeCache.gen []")
    IO.println s!"lake-cache: {path} equals the Lean output, {goldenLines.length} lines"
  else
    IO.FS.writeFile path goldenText


end Fw.Ops.LakeCache

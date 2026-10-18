import Fw.Ops.Cache
import Fw.Ops.LakeJobsGen
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

/-- A CI job that restores the Lake cache: workflow file, job id, saves or only restores, the Lake targets it builds.
$$j = (\mathit{file},\ \mathit{job},\ \mathit{saves} \in \mathbb{B},\ T_j)$$ -/
structure LakeJob where
  file : String
  job : String
  saves : Bool
  targets : List String
deriving Repr, DecidableEq

/-- The job that must be the one writer: workflow `lean.yml`, job `lean` (it runs `lake build` and
`lean/scripts/check.sh`, so it builds every default target and `fwtest`).
$$\operatorname{isW}(j) \iff j.\mathit{file} = \texttt{lean.yml} \land j.\mathit{job} = \texttt{lean}$$ -/
def isWriter (j : LakeJob) : Bool := j.file == "lean.yml" && j.job == "lean"

/-- The writer row of a job list: the first job that `isWriter` accepts, if any.
$$\operatorname{wr}(J) = \begin{cases} \mathrm{some}\ j_i & i = \min\{\, i \mid \operatorname{isW}(j_i) \,\} \\ \mathrm{none} & \text{no } j \in J \text{ has } \operatorname{isW}(j) \end{cases}$$ -/
def writerOf (js : List LakeJob) : Option LakeJob := js.find? isWriter

/-- Import facts the coverage rule may use, as (module, Lake target whose root imports it), generated with the rows.
$$F = \mathtt{LakeJobsGen.importFacts}$$ -/
def importFacts : List (String × String) := Fw.Ops.LakeJobsGen.importFacts

/-- The targets of `j` the writer `w` does not cover: those that are no writer target and that no import fact puts
in the cone of a writer target.
$$\operatorname{unc}(w, j) = [\, t \in T_j \mid t \notin T_w \land \lnot \exists (t, r) \in F:\ r \in T_w \,]$$ -/
def uncovered (w j : LakeJob) : List String :=
  j.targets.filter fun t => !(w.targets.contains t || importFacts.any fun f => f.1 == t && w.targets.contains f.2)

/-- `w` covers `j`: every target of `j` is a writer target, or a module that an import fact puts in the cone of a
writer target.
$$\operatorname{cov}(w, j) \iff \forall t \in T_j:\ t \in T_w \lor \exists (t, r) \in F:\ r \in T_w$$ -/
def coveredBy (w j : LakeJob) : Bool :=
  j.targets.all fun t => w.targets.contains t || importFacts.any fun f => f.1 == t && w.targets.contains f.2

/-- **The rules.** A writer row exists, the jobs that save are exactly `[w]`, and every job builds at least one
target the scanner read and is covered by `w`.
$$\operatorname{ok}(J) \iff \exists w:\ \operatorname{wr}(J) = \mathrm{some}\ w \land [\, j \in J : j.\mathit{saves} \,] = [w] \land \forall j \in J:\ T_j \ne [\,] \land \operatorname{cov}(w, j)$$ -/
def ok (js : List LakeJob) : Bool :=
  match writerOf js with
  | none => false
  | some w => js.filter (·.saves) == [w] && js.all fun j => !j.targets.isEmpty && coveredBy w j

/-- A job as `file/job`. $$\operatorname{name}(j) = j.\mathit{file} \mathbin{+\!\!+} \texttt{/} \mathbin{+\!\!+} j.\mathit{job}$$ -/
def name (j : LakeJob) : String := j.file ++ "/" ++ j.job

/-- What breaks the rules, one message per broken rule and job (diagnostics for the build log; `ok` decides).
$$\operatorname{viol}(J) = \begin{cases} [\text{no writer row}] & \operatorname{wr}(J) = \mathrm{none} \\ [\text{savers} \ne [w] \text{ if so}] \mathbin{+\!\!+} [\, \text{empty}(j) \mid j \in J,\ T_j = [\,] \,] \mathbin{+\!\!+} [\, \text{unc}(j) \mid j \in J,\ \operatorname{unc}(w, j) \ne [\,] \,] & \operatorname{wr}(J) = \mathrm{some}\ w \end{cases}$$ -/
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

/-- The table: one job per generated row.
$$J = [\, (f, j, s, T) \mid (f, j, s, T) \in \mathtt{LakeJobsGen.rows} \,]$$ -/
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

/-- A covered job's targets are all in the writer's cone, for every import graph in which the import facts hold.
$$\forall \mathit{deps}:\ (\forall (m, r) \in F:\ m \in \operatorname{cl}([r])) \Rightarrow \forall w, j:\ \operatorname{cov}(w, j) \Rightarrow \forall t \in T_j:\ t \in \operatorname{cl}(T_w)$$ -/
theorem covered_inCone (deps : String → List String) (hf : ∀ f ∈ importFacts, InCone deps [f.2] f.1)
    (w j : LakeJob) (hc : coveredBy w j = true) : ∀ t ∈ j.targets, InCone deps w.targets t := by
  intro t ht
  have h := List.all_eq_true.mp hc t ht
  simp only [Bool.or_eq_true, List.contains_iff_mem, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] at h
  rcases h with hw | ⟨f, hfm, hft, hfw⟩
  · exact InCone.root hw
  · subst hft
    exact inCone_mono deps w.targets [f.2] (fun x hx => by simp at hx; subst hx; exact hfw) (hf f hfm)

/-- **One writer, for every job list that keeps the rules.** If $\operatorname{ok}(J)$, the writer row exists and
the jobs that save are exactly it.
$$\forall J:\ \operatorname{ok}(J) \Rightarrow \exists w:\ \operatorname{wr}(J) = \mathrm{some}\ w \land [\, j \in J : j.\mathit{saves} \,] = [w]$$ -/
theorem ok_one_writer (js : List LakeJob) (h : ok js = true) :
    ∃ w, writerOf js = some w ∧ js.filter (·.saves) = [w] := by
  unfold ok at h
  cases hw : writerOf js with
  | none => simp [hw] at h
  | some w =>
    simp only [hw, Bool.and_eq_true, beq_iff_eq] at h
    exact ⟨w, rfl, h.1⟩

/-- **Every job is covered, for every job list that keeps the rules.**
$$\forall J, w:\ \operatorname{ok}(J) \land \operatorname{wr}(J) = \mathrm{some}\ w \Rightarrow \forall j \in J:\ T_j \ne [\,] \land \operatorname{cov}(w, j)$$ -/
theorem ok_covered (js : List LakeJob) (h : ok js = true) (w : LakeJob) (hw : writerOf js = some w) :
    ∀ j ∈ js, j.targets ≠ [] ∧ coveredBy w j = true := by
  intro j hj
  unfold ok at h
  simp only [hw, Bool.and_eq_true, List.all_eq_true, Bool.not_eq_true', List.isEmpty_eq_false_iff] at h
  exact h.2 j hj

/-- **Cache completeness, for every job list that keeps the rules.** On the writer's source tree, whatever entry
the writer restored, the entry it saves holds every module any job needs: no job rebuilds a module (given the
import facts).
$$\forall J, w, \mathit{deps}, h, C:\ \operatorname{ok}(J) \land \operatorname{wr}(J) = \mathrm{some}\ w \land (\forall (m, r) \in F:\ m \in \operatorname{cl}([r])) \Rightarrow \forall j \in J,\ \forall m:\ m \notin \operatorname{rb}(T_j, \operatorname{after}(T_w, C))$$ -/
theorem ok_complete {H : Type} (js : List LakeJob) (h : ok js = true) (w : LakeJob) (hw : writerOf js = some w)
    (deps : String → List String) (hash : String → H) (C : Entry H)
    (hf : ∀ f ∈ importFacts, InCone deps [f.2] f.1) :
    ∀ j ∈ js, ∀ m, ¬ Rebuilds deps hash (afterBuild deps hash C w.targets) j.targets m :=
  fun j hj m => cache_complete deps hash C w.targets j.targets
    (covered_inCone deps hf w j (ok_covered js h w hw j hj).2) m

/-- The generated table keeps the rules. $$\operatorname{ok}(J)$$ -/
theorem jobs_ok : ok jobs = true := by decide

/-- **One writer.** In the table read from the workflows, the writer row exists and the jobs that save the Lake
cache are exactly it.
$$\exists w:\ \operatorname{wr}(J) = \mathrm{some}\ w \land [\, j \in J : j.\mathit{saves} \,] = [w]$$ -/
theorem one_writer : ∃ w, writerOf jobs = some w ∧ jobs.filter (·.saves) = [w] := ok_one_writer jobs jobs_ok

/-- **The table is complete.** For the jobs read from the workflows: on the writer's source tree, whatever entry the
writer restored, the entry it saves holds every module any job needs (given the import facts).
$$\forall w, \mathit{deps}, h, C:\ \operatorname{wr}(J) = \mathrm{some}\ w \land (\forall (m, r) \in F:\ m \in \operatorname{cl}([r])) \Rightarrow \forall j \in J,\ \forall m:\ m \notin \operatorname{rb}(T_j, \operatorname{after}(T_w, C))$$ -/
theorem table_complete {H : Type} (w : LakeJob) (hw : writerOf jobs = some w) (deps : String → List String)
    (hash : String → H) (C : Entry H) (hf : ∀ f ∈ importFacts, InCone deps [f.2] f.1) :
    ∀ j ∈ jobs, ∀ m, ¬ Rebuilds deps hash (afterBuild deps hash C w.targets) j.targets m :=
  ok_complete jobs jobs_ok w hw deps hash C hf

end Fw.Ops.LakeCache

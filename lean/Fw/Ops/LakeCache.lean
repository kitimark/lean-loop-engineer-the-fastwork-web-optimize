import Lean.Data.Json
import Fw.Ops.Cache
/-!
# Who saves the Lake artifact cache (task `site-build-cache`)

The table of every CI job that runs `.github/actions/setup-lean`: its workflow file, its job id, whether it saves
the Lake cache (`save: 'true'`) and the Lake targets it builds. Exactly one job saves: the `lean` job of
`lean.yml`, which builds every default target and `fwtest`. `table_complete` proves (with `Fw.Ops.Cache.cache_complete`)
that on the writer's source tree no other job rebuilds a module.

Generated from this file: `packages/contracts/golden/ops/lake-cache.jsonl`. `scripts/ci-paths.mjs --check` (a land
check) fails when a workflow job that uses `setup-lean` is missing from the table, or when its `save:` differs.
The job's targets are read from the workflow by hand (its `lake build ...` and `pnpm ... build` steps); that is the
premise this module cannot check.
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

/-- `lake build` with no argument: the default targets of `lean/lakefile.toml`.
$$T_{\mathrm{def}} = [\mathrm{Fw},\ \mathrm{fwcore},\ \mathrm{mathview},\ \mathrm{breakgen},\ \mathrm{sweepsgen},\ \mathrm{partsgolden}]$$ -/
def defaults : List String := ["Fw", "fwcore", "mathview", "breakgen", "sweepsgen", "partsgolden"]

/-- The one writer: `lean.yml` job `lean` runs `lake build` and `lean/scripts/check.sh` (`lake build fwtest`).
$$w = (\texttt{lean.yml},\ \texttt{lean},\ \top,\ T_{\mathrm{def}} \mathbin{+\!\!+} [\mathrm{fwtest}])$$ -/
def writer : LakeJob := ⟨"lean.yml", "lean", true, defaults ++ ["fwtest"]⟩

/-- Every job that uses `setup-lean`, the writer first. A site job runs `pnpm --filter @fw/site build`, whose first
step is `lake exe breakgen --check` (apps/site/scripts/check-breakpoints.mjs), so its only target is `breakgen`.
$$J = \text{the 14 rows below, in order: } [\,w,\ (\texttt{lean.yml}, \texttt{mathview-differential}, \bot, T_{\mathrm{def}}),\ (\texttt{breakpoint-gate.yml}, \texttt{site}, \bot, [\mathrm{breakgen}]),\ \ldots\,]$$ -/
def jobs : List LakeJob := [
  writer,
  ⟨"lean.yml", "mathview-differential", false, defaults⟩,
  ⟨"breakpoint-gate.yml", "site", false, ["breakgen"]⟩,
  ⟨"breakpoint-gate.yml", "merge", false, ["fwcore"]⟩,
  ⟨"chromium-counts.yml", "fwcore", false, ["fwcore"]⟩,
  ⟨"chromium-counts.yml", "site", false, ["breakgen"]⟩,
  ⟨"difftest.yml", "fwcore", false, ["fwcore"]⟩,
  ⟨"gate-gaps.yml", "site", false, ["breakgen"]⟩,
  ⟨"gate-gaps.yml", "judge", false, ["fwcore"]⟩,
  ⟨"mutants.yml", "shard", false, ["Fw", "FwTest.Mutants.Kill", "fwtest", "fwcore"]⟩,
  ⟨"snapshot-extract.yml", "site", false, ["breakgen"]⟩,
  ⟨"visual-diff.yml", "site", false, ["breakgen"]⟩,
  ⟨"wktr.yml", "fwcore", false, ["fwcore"]⟩,
  ⟨"wktr-fixtures.yml", "fwcore", false, ["fwcore"]⟩]

/-- Import facts the table relies on, as (module, root that imports it): `FwTestMain.lean` imports
`FwTest.Mutants.Kill`, so it is in the cone of `fwtest`.
$$F = [(\mathrm{FwTest.Mutants.Kill},\ \mathrm{fwtest})]$$ -/
def importFacts : List (String × String) := [("FwTest.Mutants.Kill", "fwtest")]

/-- A job's targets are covered by the writer: each is a writer target, or a module that an import fact puts in the
cone of a writer target.
$$\operatorname{cov}(j) \iff \forall t \in T_j:\ t \in T_w \lor \exists (t, r) \in F:\ r \in T_w$$ -/
def covered (j : LakeJob) : Bool :=
  j.targets.all fun t => writer.targets.contains t || importFacts.any fun f => f.1 == t && writer.targets.contains f.2

#guard jobs.filter (·.saves) == [writer]
#guard jobs.all covered
#guard (jobs.map fun j => (j.file, j.job)).eraseDups.length == jobs.length
#guard covered ⟨"x.yml", "y", false, ["Fw.Gate.Scope"]⟩ == false

/-- **One writer.** Exactly one job of the table saves the Lake cache, and it is `writer`.
$$[\, j \in J : j.\mathit{saves} \,] = [w]$$ -/
theorem one_writer : jobs.filter (·.saves) = [writer] := by decide

/-- Every job of the table is covered by the writer.
$$\forall j \in J:\ \operatorname{cov}(j)$$ -/
theorem all_covered : ∀ j ∈ jobs, covered j = true := by decide

/-- A covered job's targets are all in the writer's cone, for every import graph in which the import facts hold.
$$\forall \mathit{deps}:\ (\forall (m, r) \in F:\ m \in \operatorname{cl}([r])) \Rightarrow \forall j:\ \operatorname{cov}(j) \Rightarrow \forall t \in T_j:\ t \in \operatorname{cl}(T_w)$$ -/
theorem covered_inCone (deps : String → List String) (hf : ∀ f ∈ importFacts, InCone deps [f.2] f.1)
    (j : LakeJob) (hc : covered j = true) : ∀ t ∈ j.targets, InCone deps writer.targets t := by
  intro t ht
  have h := List.all_eq_true.mp hc t ht
  simp only [Bool.or_eq_true, List.contains_iff_mem, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] at h
  rcases h with hw | ⟨f, hfm, hft, hfw⟩
  · exact InCone.root hw
  · subst hft
    exact inCone_mono deps writer.targets [f.2] (fun x hx => by simp at hx; subst hx; exact hfw) (hf f hfm)

/-- **The table is complete.** On the writer's source tree, whatever entry the writer restored, the entry it saves
holds every module any job of the table needs: no job rebuilds a module (given the import facts).
$$\forall \mathit{deps}, h, C:\ (\forall (m, r) \in F:\ m \in \operatorname{cl}([r])) \Rightarrow \forall j \in J,\ \forall m:\ m \notin \operatorname{rb}(T_j, \operatorname{after}(T_w, C))$$ -/
theorem table_complete {H : Type} (deps : String → List String) (hash : String → H) (C : Entry H)
    (hf : ∀ f ∈ importFacts, InCone deps [f.2] f.1) :
    ∀ j ∈ jobs, ∀ m, ¬ Rebuilds deps hash (afterBuild deps hash C writer.targets) j.targets m :=
  fun j hj m => cache_complete deps hash C writer.targets j.targets
    (covered_inCone deps hf j (all_covered j hj)) m

/-! ## Golden (`packages/contracts/golden/ops/lake-cache.jsonl`) -/

/-- One golden line per job.
$$\operatorname{line}(j) = \{\texttt{kind}: \texttt{job},\ \mathit{file},\ \mathit{job},\ \mathit{saves},\ T_j,\ \operatorname{cov}(j)\}$$ -/
def jobLine (j : LakeJob) : Json :=
  Json.mkObj [("kind", "job"), ("file", .str j.file), ("job", .str j.job), ("saves", .bool j.saves),
    ("targets", .arr (j.targets.map Json.str).toArray), ("covered", .bool (covered j))]

/-- The text of the golden file: one JSON object per job, in table order.
$$\operatorname{goldenText} = \textstyle\bigoplus_{j \in J} (\mathrm{compress}(\operatorname{line}(j)) \mathbin{+\!\!+} \text{newline})$$ -/
def goldenText : String := String.join (jobs.map fun j => (jobLine j).compress ++ "\n")

/-- Compare (or write) the golden file; returns the number of stale files. A missing or unreadable file reads as the
empty string, so it counts as stale.
$$\operatorname{runGolden}(\mathit{write}) = \begin{cases} 0 & \mathit{write} \ (\text{after writing goldenText}) \\ 0 & \lnot\mathit{write} \land \operatorname{read}(p) = \operatorname{goldenText} \\ 1 & \lnot\mathit{write} \land \operatorname{read}(p) \ne \operatorname{goldenText} \end{cases},\quad \operatorname{read}(p) = \text{""} \text{ if } p \text{ is missing}$$ -/
def runGolden (root : System.FilePath) (write : Bool) : IO Nat := do
  let dir := root / ".." / "packages" / "contracts" / "golden" / "ops"
  let p := dir / "lake-cache.jsonl"
  if write then
    IO.FS.createDirAll dir
    IO.FS.writeFile p goldenText
    IO.println s!"lake cache golden: written {jobs.length} jobs"
    return 0
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur != goldenText then
    IO.println s!"lake cache golden: {p} is stale (regenerate: cd lean && lake test -- --write-lake-cache-golden)"
    return 1
  IO.println s!"lake cache golden: {jobs.length} jobs ok"
  return 0

end Fw.Ops.LakeCache

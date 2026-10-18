/-!
# The CI jobs that use setup-lean (generated, do not edit)

Written by `node scripts/ci-paths.mjs --write` from `.github/workflows/*.yml` and the scripts their `run:` blocks call;
`node scripts/ci-paths.mjs --check` fails when this file differs from what the workflows give. The rules and proofs over
these rows are in `Fw.Ops.LakeCache`.
-/
namespace Fw.Ops.LakeJobsGen

/-- Every CI job that uses `.github/actions/setup-lean`, as (workflow file, job id, passes `save: 'true'`, Lake targets
it builds), workflow files sorted by name, jobs in file order.
$$R = [\,(\texttt{breakpoint-gate.yml},\ \texttt{site},\ \bot,\ [\texttt{breakgen}]),\ (\texttt{breakpoint-gate.yml},\ \texttt{merge},\ \bot,\ [\texttt{fwcore}]),\ (\texttt{chromium-counts.yml},\ \texttt{fwcore},\ \bot,\ [\texttt{fwcore}]),\ (\texttt{chromium-counts.yml},\ \texttt{site},\ \bot,\ [\texttt{breakgen}]),\ (\texttt{difftest.yml},\ \texttt{fwcore},\ \bot,\ [\texttt{fwcore}]),\ (\texttt{gate-gaps.yml},\ \texttt{site},\ \bot,\ [\texttt{breakgen}]),\ (\texttt{gate-gaps.yml},\ \texttt{judge},\ \bot,\ [\texttt{fwcore}]),\ (\texttt{lean.yml},\ \texttt{lean},\ \top,\ [\texttt{Fw},\ \texttt{fwcore},\ \texttt{mathview},\ \texttt{breakgen},\ \texttt{sweepsgen},\ \texttt{partsgolden},\ \texttt{fwtest}]),\ (\texttt{lean.yml},\ \texttt{mathview-differential},\ \bot,\ [\texttt{Fw},\ \texttt{fwcore},\ \texttt{mathview},\ \texttt{breakgen},\ \texttt{sweepsgen},\ \texttt{partsgolden}]),\ (\texttt{mutants.yml},\ \texttt{shard},\ \bot,\ [\texttt{Fw},\ \texttt{FwTest.Mutants.Kill},\ \texttt{fwtest},\ \texttt{fwcore},\ \texttt{mathview},\ \texttt{breakgen},\ \texttt{sweepsgen},\ \texttt{partsgolden}]),\ (\texttt{snapshot-extract.yml},\ \texttt{site},\ \bot,\ [\texttt{breakgen}]),\ (\texttt{visual-diff.yml},\ \texttt{site},\ \bot,\ [\texttt{breakgen}]),\ (\texttt{webkit-sim.yml},\ \texttt{site},\ \bot,\ [\texttt{breakgen}]),\ (\texttt{webkit-sim.yml},\ \texttt{fwcore},\ \bot,\ [\texttt{fwcore}]),\ (\texttt{wktr-fixtures.yml},\ \texttt{fwcore},\ \bot,\ [\texttt{fwcore}]),\ (\texttt{wktr.yml},\ \texttt{fwcore},\ \bot,\ [\texttt{fwcore}])\,]$$ -/
def rows : List (String × String × Bool × List String) := [
  ("breakpoint-gate.yml", "site", false, ["breakgen"]),
  ("breakpoint-gate.yml", "merge", false, ["fwcore"]),
  ("chromium-counts.yml", "fwcore", false, ["fwcore"]),
  ("chromium-counts.yml", "site", false, ["breakgen"]),
  ("difftest.yml", "fwcore", false, ["fwcore"]),
  ("gate-gaps.yml", "site", false, ["breakgen"]),
  ("gate-gaps.yml", "judge", false, ["fwcore"]),
  ("lean.yml", "lean", true, ["Fw", "fwcore", "mathview", "breakgen", "sweepsgen", "partsgolden", "fwtest"]),
  ("lean.yml", "mathview-differential", false, ["Fw", "fwcore", "mathview", "breakgen", "sweepsgen", "partsgolden"]),
  ("mutants.yml", "shard", false, ["Fw", "FwTest.Mutants.Kill", "fwtest", "fwcore", "mathview", "breakgen", "sweepsgen", "partsgolden"]),
  ("snapshot-extract.yml", "site", false, ["breakgen"]),
  ("visual-diff.yml", "site", false, ["breakgen"]),
  ("webkit-sim.yml", "site", false, ["breakgen"]),
  ("webkit-sim.yml", "fwcore", false, ["fwcore"]),
  ("wktr-fixtures.yml", "fwcore", false, ["fwcore"]),
  ("wktr.yml", "fwcore", false, ["fwcore"])]

/-- Import facts (module, Lake target): a job target that is a module, not a target name, and a target whose root module
imports it (or whose library glob holds it), read from the `import` lines under `lean/`.
$$F = [\,(\texttt{FwTest.Mutants.Kill},\ \texttt{fwtest})\,]$$ -/
def importFacts : List (String × String) := [("FwTest.Mutants.Kill", "fwtest")]

end Fw.Ops.LakeJobsGen

import Lean.Data.Json
import Fw.Console.Land
/-!
# The writes closure of a task: the files its new golden, Lean module or workflow also changes
Incident `inc-graph-writes-closure`; a path is missing exactly when `Fw.Console.Land.landScope` refuses it.
-/

namespace Fw.Plan.WritesClosure
open Fw.Ops.PathCheck Fw.Console.Land

/-- What a written path adds when it is new. -/
inductive Kind | golden | script | module | workflow | other
deriving DecidableEq, Repr

/-- The wire name of a kind. -/
def Kind.name : Kind → String
  | .golden => "golden" | .script => "script" | .module => "module" | .workflow => "workflow"
  | .other => "other"

def goldenDir : String := "packages/contracts/golden/"
def ciGoldenDir : String := "packages/contracts/golden/ci/"

def lastSeg (w : String) : String := ((w.splitOn "/").getLast?).getD ""

def wild (s : String) : Bool := s == "*" || s == "**"

def leanFile (w : String) : Bool := (lastSeg w).endsWith ".lean" || wild (lastSeg w)

def ymlFile (w : String) : Bool :=
  (lastSeg w).endsWith ".yml" || (lastSeg w).endsWith ".yaml" || wild (lastSeg w)

/-- The kind of a write path or glob, from its directory and file name. -/
def kindOf (w : String) : Kind :=
  if w.startsWith ciGoldenDir then .other
  else if w.startsWith goldenDir then .golden
  else if w.startsWith "lean/scripts/" && leanFile w then .script
  else if w.startsWith "lean/Fw/" && leanFile w then .module
  else if w.startsWith ".github/workflows/" && ymlFile w then .workflow
  else .other

def checkSh : String := "lean/scripts/check.sh"
def triggerLean : String := "lean/Fw/Ci/Trigger.lean"
def triggersGolden : String := "packages/contracts/golden/ci/triggers.jsonl"
def fwRoot : String := "lean/Fw.lean"

/-- A golden check: its `check.sh` job line, the `lean.yml` input row and the regenerated trigger golden. -/
def goldenCheck : List String := [checkSh, triggerLean, triggersGolden]

/-- The CI tables every workflow file has a row in, with their goldens. -/
def ciTables : List String :=
  [triggerLean, "lean/Fw/Ci/Intent.lean", "lean/Fw/Ci/Overflow.lean", "lean/Fw/Ci/Pool/Caps.lean", triggersGolden,
    "packages/contracts/golden/ci/intent.jsonl", "packages/contracts/golden/ci/pool-caps.jsonl"]

/-- The paths a new artefact of a kind implies. -/
def implied : Kind → List String
  | .golden | .script => goldenCheck
  | .module => [fwRoot]
  | .workflow => ciTables
  | .other => []

/-- Whether a write adds a file: `new` matches no tracked file, `existing` is a plain path that does, `open` is a
glob that does and may add more. -/
inductive Fresh | new | existing | «open»
deriving DecidableEq, Repr

/-- The wire name of a freshness. -/
def Fresh.name : Fresh → String
  | .new => "new" | .existing => "existing" | .open => "open"

def isGlob (w : String) : Bool := w.toList.contains '*'

/-- The freshness of write `w` against the tracked files, matched as the land matches a path. -/
def freshOf (tracked : List String) (w : String) : Fresh :=
  if tracked.any (inScope (parseScope [w])) then (if isGlob w then .open else .existing) else .new

/-- The implied paths of the writes of freshness `f`, each once. -/
def needs (tracked writes : List String) (f : Fresh) : List String :=
  ((writes.filter (freshOf tracked · == f)).flatMap (implied ∘ kindOf)).eraseDups

/-- The closure of the new artefacts. -/
def required (tracked writes : List String) : List String := needs tracked writes .new

/-- The closure a glob would need if it adds a file, without the paths already required. -/
def mayNeed (tracked writes : List String) : List String :=
  (needs tracked writes .open).filter (!(required tracked writes).contains ·)

/-- A work-graph row as the closure reads it; `done` is a row with evidence or cut. -/
structure Task where
  id : String
  owner : String
  stream : String
  writes : List String
  done : Bool
deriving Repr

/-- The scope `fw land` gives the task. -/
def scopeOf (t : Task) : List String := landScope t.writes [t.id, t.owner] [] t.id t.stream

/-- The required paths the land would refuse. -/
def missing (tracked : List String) (t : Task) : List String :=
  if t.done then [] else violations (scopeOf t) (required tracked t.writes)

/-- The paths an open glob would need that the land would refuse. -/
def missingOpen (tracked : List String) (t : Task) : List String :=
  if t.done then [] else violations (scopeOf t) (mayNeed tracked t.writes)

/-- The first write of freshness `f` that implies `p`. -/
def source (tracked writes : List String) (f : Fresh) (p : String) : String :=
  ((writes.filter (freshOf tracked · == f)).find? fun w => (implied (kindOf w)).contains p).getD ""

/-- A lint finding, as `Fw.Plan.Lint.Finding`. -/
structure Finding where
  task : String
  code : String
  severity : String
  detail : String
deriving Repr, BEq

/-- `writesClosure` errors for missing paths, then `writesClosureOpen` warnings. -/
def findings (tracked : List String) (t : Task) : List Finding :=
  (missing tracked t).map (fun p =>
      ⟨t.id, "writesClosure", "error", p ++ " for " ++ source tracked t.writes .new p⟩) ++
    (missingOpen tracked t).map (fun p =>
      ⟨t.id, "writesClosureOpen", "warn", p ++ " for " ++ source tracked t.writes .open p⟩)

/-! ## Kinds -/

theorem kindOf_golden_iff (w : String) :
    kindOf w = .golden ↔ w.startsWith ciGoldenDir = false ∧ w.startsWith goldenDir = true := by
  unfold kindOf; repeat' split
  all_goals simp_all

theorem kindOf_script_iff (w : String) :
    kindOf w = .script ↔ w.startsWith goldenDir = false ∧ w.startsWith ciGoldenDir = false ∧
      w.startsWith "lean/scripts/" = true ∧ leanFile w = true := by
  unfold kindOf; repeat' split
  all_goals simp_all

theorem kindOf_module_iff (w : String) :
    kindOf w = .module ↔ w.startsWith goldenDir = false ∧ w.startsWith ciGoldenDir = false ∧
      (w.startsWith "lean/scripts/" && leanFile w) = false ∧ w.startsWith "lean/Fw/" = true ∧ leanFile w = true := by
  unfold kindOf; repeat' split
  all_goals simp_all

theorem kindOf_workflow_iff (w : String) :
    kindOf w = .workflow ↔ w.startsWith goldenDir = false ∧ w.startsWith ciGoldenDir = false ∧
      (w.startsWith "lean/scripts/" && leanFile w) = false ∧ (w.startsWith "lean/Fw/" && leanFile w) = false ∧
      w.startsWith ".github/workflows/" = true ∧ ymlFile w = true := by
  unfold kindOf; repeat' split
  all_goals simp_all

/-- A CI golden is never a golden of its own: it is a closure target. -/
theorem kindOf_ci (w : String) (h : w.startsWith ciGoldenDir = true) : kindOf w = .other := by
  simp [kindOf, h]

theorem implied_eq_nil_iff (k : Kind) : implied k = [] ↔ k = .other := by
  cases k <;> simp [implied, goldenCheck, ciTables]

/-- A new module needs only the library root: `lean.yml` already reads `lean/**`, and `check.sh` runs no line per
module. -/
theorem implied_module : implied .module = [fwRoot] := rfl

theorem implied_golden : implied .golden = [checkSh, triggerLean, triggersGolden] := rfl

theorem implied_script : implied .script = implied .golden := rfl

/-! ## Freshness -/

theorem freshOf_new_iff (tr : List String) (w : String) :
    freshOf tr w = .new ↔ ∀ f ∈ tr, inScope (parseScope [w]) f = false := by
  unfold freshOf; repeat' split
  all_goals simp_all

theorem freshOf_existing_iff (tr : List String) (w : String) :
    freshOf tr w = .existing ↔ (∃ f ∈ tr, inScope (parseScope [w]) f = true) ∧ isGlob w = false := by
  unfold freshOf; repeat' split
  all_goals simp_all

theorem freshOf_open_iff (tr : List String) (w : String) :
    freshOf tr w = .open ↔ (∃ f ∈ tr, inScope (parseScope [w]) f = true) ∧ isGlob w = true := by
  unfold freshOf; repeat' split
  all_goals simp_all

/-! ## The closure -/

theorem mem_needs (tr ws : List String) (f : Fresh) (p : String) :
    p ∈ needs tr ws f ↔ ∃ w ∈ ws, freshOf tr w = f ∧ p ∈ implied (kindOf w) := by
  simp [needs, List.mem_eraseDups, and_assoc]

theorem mem_required (tr ws : List String) (p : String) :
    p ∈ required tr ws ↔ ∃ w ∈ ws, freshOf tr w = .new ∧ p ∈ implied (kindOf w) :=
  mem_needs tr ws .new p

/-- **No new golden, script, module or workflow: nothing is required.** -/
theorem required_eq_nil_iff (tr ws : List String) :
    required tr ws = [] ↔ ∀ w ∈ ws, freshOf tr w = .new → kindOf w = .other := by
  constructor
  · intro h w hw hn
    rw [← implied_eq_nil_iff]
    refine List.eq_nil_iff_forall_not_mem.mpr fun p hp => ?_
    have := (mem_required tr ws p).mpr ⟨w, hw, hn, hp⟩
    simp [h] at this
  · intro h
    refine List.eq_nil_iff_forall_not_mem.mpr fun p hp => ?_
    obtain ⟨w, hw, hn, hp⟩ := (mem_required tr ws p).mp hp
    simp [(implied_eq_nil_iff _).mpr (h w hw hn)] at hp

theorem required_of_new (tr ws : List String) (w : String) (hw : w ∈ ws) (hn : freshOf tr w = .new) :
    ∀ p ∈ implied (kindOf w), p ∈ required tr ws :=
  fun p hp => (mem_required tr ws p).mpr ⟨w, hw, hn, hp⟩

theorem required_golden (tr ws : List String) (w : String) (hw : w ∈ ws) (hn : freshOf tr w = .new)
    (hk : kindOf w = .golden) : ∀ p ∈ goldenCheck, p ∈ required tr ws := by
  have := required_of_new tr ws w hw hn; rw [hk] at this; exact this

theorem required_script (tr ws : List String) (w : String) (hw : w ∈ ws) (hn : freshOf tr w = .new)
    (hk : kindOf w = .script) : ∀ p ∈ goldenCheck, p ∈ required tr ws := by
  have := required_of_new tr ws w hw hn; rw [hk] at this; exact this

theorem required_module (tr ws : List String) (w : String) (hw : w ∈ ws) (hn : freshOf tr w = .new)
    (hk : kindOf w = .module) : fwRoot ∈ required tr ws := by
  have := required_of_new tr ws w hw hn; rw [hk] at this; exact this _ (by simp [implied])

theorem required_workflow (tr ws : List String) (w : String) (hw : w ∈ ws) (hn : freshOf tr w = .new)
    (hk : kindOf w = .workflow) : ∀ p ∈ ciTables, p ∈ required tr ws := by
  have := required_of_new tr ws w hw hn; rw [hk] at this; exact this

theorem mem_mayNeed (tr ws : List String) (p : String) :
    p ∈ mayNeed tr ws ↔ (∃ w ∈ ws, freshOf tr w = .open ∧ p ∈ implied (kindOf w)) ∧ p ∉ required tr ws := by
  simp [mayNeed, mem_needs]

/-! ## Agreement with `fw land` -/

/-- A missing path is a required path the land's scope does not admit. -/
theorem mem_missing_iff (tr : List String) (t : Task) (hd : t.done = false) (p : String) :
    p ∈ missing tr t ↔ p ∈ required tr t.writes ∧ inScope (parseScope (scopeOf t)) p = false := by
  simp [missing, hd, mem_violations]

theorem mem_missingOpen_iff (tr : List String) (t : Task) (hd : t.done = false) (p : String) :
    p ∈ missingOpen tr t ↔ p ∈ mayNeed tr t.writes ∧ inScope (parseScope (scopeOf t)) p = false := by
  simp [missingOpen, hd, mem_violations]

/-- **The lint passes exactly when a land that changes the whole closure passes its scope check.** -/
theorem missing_nil_iff_land_ok (tr : List String) (t : Task) (hd : t.done = false) (hw : t.writes ≠ []) :
    missing tr t = [] ↔
      landVerdict t.writes [t.id, t.owner] [] (required tr t.writes) t.id t.stream = .ok := by
  cases hv : violations (scopeOf t) (required tr t.writes) <;>
    simp_all [landVerdict, missing, scopeOf, List.isEmpty_iff]

/-- A missing path refuses the land of any branch that changes it. -/
theorem missing_refused (tr : List String) (t : Task) (hd : t.done = false) (p : String)
    (h : p ∈ missing tr t) : p ∈ violations (scopeOf t) [p] := by
  rw [mem_violations]; exact ⟨by simp, ((mem_missing_iff tr t hd p).mp h).2⟩

/-- One scope request answers both lists: the glue asks fwcore once per task. -/
theorem one_call (tr : List String) (t : Task) (hd : t.done = false) :
    violations (scopeOf t) (required tr t.writes ++ mayNeed tr t.writes) = missing tr t ++ missingOpen tr t := by
  simp [violations, missing, missingOpen, hd, List.filter_append]

theorem done_silent (tr : List String) (t : Task) (hd : t.done = true) : findings tr t = [] := by
  simp [findings, missing, missingOpen, hd]

/-- **An error finding exists exactly when a required path is missing.** -/
theorem error_iff (tr : List String) (t : Task) :
    (∃ f ∈ findings tr t, f.severity = "error") ↔ missing tr t ≠ [] := by
  constructor
  · rintro ⟨f, hf, hs⟩
    simp only [findings, List.mem_append, List.mem_map] at hf
    rcases hf with ⟨p, hp, rfl⟩ | ⟨p, _, rfl⟩
    · exact List.ne_nil_of_mem hp
    · simp at hs
  · intro h
    obtain ⟨p, hp⟩ := List.exists_mem_of_ne_nil _ h
    exact ⟨_, List.mem_append_left _ (List.mem_map_of_mem hp), rfl⟩

/-! ## The recorded cases: graph r322 to r334 -/

/-- A replayed work-graph row: the graph commit it is read from, the tracked files its writes matched there, and the
paths the next graph commit added to the row. -/
structure Case where
  name : String
  graph : String
  task : Task
  tracked : List String
  added : List String

def fontPre : List String :=
  ["packages/measure-chromium/**", "lean/Fw/Measure/Profile.lean", "packages/contracts/golden/measure/**",
    "research/notes/2026/10-2x-counts-font-fidelity.md", "docs/team/handoffs/counts-font-fidelity.md"]

def fontTables : List String :=
  ["apps/runner/src/land.ts", "lean/Fw/Ci/Intent.lean", "lean/Fw/Ci/Overflow.lean", "lean/Fw/Ci/Pool/Caps.lean",
    "lean/Fw/Ci/Trigger.lean", "scripts/ci-paths.test.mjs", "packages/contracts/golden/ci/**",
    "lean/Fw/Ops/LakeJobsGen.lean"]

def fontPost : List String := fontPre ++ [".github/workflows/font-fidelity.yml"] ++ fontTables

def fontTracked : List String :=
  ["lean/Fw/Measure/Profile.lean", "packages/contracts/golden/measure/profile.jsonl", "lean/Fw/Ci/Intent.lean",
    "lean/Fw/Ci/Overflow.lean", "lean/Fw/Ci/Pool/Caps.lean", "lean/Fw/Ci/Trigger.lean",
    "packages/contracts/golden/ci/triggers.jsonl", "lean/Fw/Ops/LakeJobsGen.lean", "lean/Fw/Faithful/Measured.lean"]

def footPre : List String :=
  ["apps/site/scripts/part-footprint.mjs", "apps/site/scripts/part-footprint*.test.mjs",
    "lean/Fw/Parts/FootprintData.lean", "lean/Fw/Parts/FootprintRows.lean",
    "packages/contracts/golden/parts/footprint*.json", "docs/team/handoffs/footprint-classname-operands.md"]

def footR323 : List String :=
  footPre ++ ["apps/site/package.json", "lean/Fw/Parts/ClassPos.lean", "lean/Fw.lean", "lean/scripts/ClassPosGolden.lean",
    "packages/contracts/golden/parts/footprint*.jsonl"]

def footLater : List String :=
  ["lean/scripts/check.sh", "lean/Fw/Ci/Trigger.lean", "packages/contracts/golden/ci/triggers.jsonl"]

def footTracked : List String :=
  ["lean/Fw/Parts/FootprintData.lean", "lean/Fw/Parts/FootprintRows.lean",
    "packages/contracts/golden/parts/footprint.gen.json", "lean/scripts/check.sh", "lean/Fw/Ci/Trigger.lean",
    "packages/contracts/golden/ci/triggers.jsonl", "lean/Fw.lean"]

def morphPre : List String :=
  ["lean/Fw/Measure/WkCost.lean", "lean/scripts/*WkCost*.lean", "packages/contracts/golden/measure/wkcost*.jsonl",
    "packages/measure-webkit/src/lag/morphcost.mjs", "packages/measure-webkit/src/lag/cli.mjs",
    "packages/measure-webkit/test/lag-morphcost.test.mjs", "results/morph-idle-none/**",
    "docs/team/handoffs/morph-cost-sums-golden.md"]

def morphAdded : List String :=
  ["lean/Fw/Ci/Trigger.lean", "packages/contracts/golden/ci/triggers.jsonl", "lean/scripts/check.sh",
    "lean/scripts/WkCostSums.lean"]

def morphTracked : List String :=
  ["lean/Fw/Measure/WkCost.lean", "lean/scripts/WkCostGolden.lean", "packages/contracts/golden/measure/wkcost.jsonl",
    "lean/Fw/Ci/Trigger.lean", "packages/contracts/golden/ci/triggers.jsonl", "lean/scripts/check.sh"]

def probePre : List String :=
  ["lean/Fw/Gate/Trajectory.lean", "lean/scripts/TrajectoryGolden.lean",
    "packages/contracts/golden/gate/trajectory*.jsonl", "packages/gate-breakpoints/src/trajectory/reduce.mjs",
    "packages/gate-breakpoints/src/trajectory/run.mjs", "packages/gate-breakpoints/test/trajectory*.test.mjs",
    "docs/team/handoffs/hero-probe-original.md"]

def probeTracked : List String :=
  ["lean/Fw/Gate/Trajectory.lean", "lean/scripts/TrajectoryGolden.lean", "packages/contracts/golden/gate/trajectory.jsonl"]

def pixPre : List String :=
  ["research/notes/2026/10-2x-hero-exit-threaded-pix.md", "results/hero-exit-threaded-pix/**",
    "docs/team/handoffs/hero-exit-threaded-pix.md"]

def pixAdded : List String :=
  [".github/workflows/path-pix.yml", "lean/Fw/Gate/PathPix.lean", "packages/contracts/golden/gate/path-pix.jsonl",
    "packages/measure-webkit/src/pathpix*.mjs", "packages/measure-webkit/test/pathpix*.test.mjs",
    "packages/measure-chromium/src/pathpix*.mjs", "packages/measure-chromium/test/pathpix*.test.mjs"]

def pixTracked : List String :=
  [".github/workflows/path-pix.yml", "lean/Fw/Gate/PathPix.lean", "packages/contracts/golden/gate/path-pix.jsonl"]

def selfWrites : List String :=
  ["lean/Fw/Plan/WritesClosure.lean", "lean/Fw.lean", "lean/scripts/WritesClosureGolden.lean", "lean/scripts/check.sh",
    "lean/Fw/Ci/Trigger.lean", "packages/contracts/golden/ci/triggers.jsonl",
    "packages/contracts/golden/plan/writes-closure.jsonl", "apps/runner/src/plan*.ts", "apps/runner/test/plan*.test.ts",
    "docs/team/handoffs/graph-writes-closure.md"]

def selfTracked : List String :=
  ["lean/Fw.lean", "lean/scripts/check.sh", "lean/Fw/Ci/Trigger.lean", "packages/contracts/golden/ci/triggers.jsonl",
    "apps/runner/src/plan.ts", "apps/runner/test/plan.test.ts"]

def mk (id owner stream : String) (writes : List String) : Task := ⟨id, owner, stream, writes, false⟩

/-- The rows of graph r322 to r334, each as it stood before and after its widening. -/
def cases : List Case := [
  ⟨"r322 before: counts-font-fidelity", "31bf66d51^", mk "counts-font-fidelity" "measure-engineer" "measure" fontPre,
    fontTracked, [".github/workflows/font-fidelity.yml"] ++ fontTables⟩,
  ⟨"r322 workflow named, tables not", "31bf66d51^",
    mk "counts-font-fidelity" "measure-engineer" "measure" (fontPre ++ [".github/workflows/font-fidelity.yml"]),
    fontTracked, fontTables⟩,
  ⟨"r322 after", "31bf66d51", mk "counts-font-fidelity" "measure-engineer" "measure" fontPost, fontTracked, []⟩,
  ⟨"r323 before: footprint-classname-operands", "132cfa8e1^",
    mk "footprint-classname-operands" "part-builder" "parts" footPre, footTracked,
    footR323.drop footPre.length ++ footLater⟩,
  ⟨"r323 after, r325 before", "132cfa8e1", mk "footprint-classname-operands" "part-builder" "parts" footR323,
    footTracked, footLater⟩,
  ⟨"r325 after", "6d61219e9",
    mk "footprint-classname-operands" "part-builder" "parts" (footR323 ++ footLater), footTracked, []⟩,
  ⟨"r328 before: morph-cost-sums-golden", "890278714^", mk "morph-cost-sums-golden" "measure-engineer" "measure" morphPre,
    morphTracked, morphAdded⟩,
  ⟨"r328 after", "890278714", mk "morph-cost-sums-golden" "measure-engineer" "measure" (morphPre ++ morphAdded),
    morphTracked, []⟩,
  ⟨"r330 before: counts-font-fidelity", "b3f6f21bd^", mk "counts-font-fidelity" "measure-engineer" "measure" fontPost,
    fontTracked, ["lean/Fw/Faithful/Measured.lean", "results/faithful/**", "packages/measure-chromium/test/faithful.test.mjs"]⟩,
  ⟨"r331 before: hero-probe-original", "1baf5a8a5^", mk "hero-probe-original" "measure-engineer" "gate" probePre,
    probeTracked, ["docs/team/tools/trajectory-probe.md"]⟩,
  ⟨"r334 before: hero-exit-threaded-pix", "f3248e954^", mk "hero-exit-threaded-pix" "measure-engineer" "measure" pixPre,
    [], pixAdded⟩,
  ⟨"r334 after", "f3248e954", mk "hero-exit-threaded-pix" "measure-engineer" "measure" (pixPre ++ pixAdded),
    pixTracked, []⟩,
  ⟨"graph-writes-closure", "f3248e954", mk "graph-writes-closure" "lean-prover" "tooling" selfWrites, selfTracked, []⟩,
  ⟨"a new module alone", "-", mk "x" "o" "tooling" ["lean/Fw/X/New.lean"], [], []⟩,
  ⟨"no artefact", "-", mk "x" "o" "tooling" ["apps/runner/src/x.ts", "docs/team/tools/x.md"], [], []⟩,
  ⟨"a done row", "-", { mk "x" "o" "tooling" [".github/workflows/new.yml"] with done := true }, [], []⟩]

/-- The (code, path) pairs a case's findings name. -/
def named (c : Case) : List (String × String) :=
  (findings c.tracked c.task).map fun f => (f.code, (f.detail.splitOn " for ").headD "")

def err (p : String) : String × String := ("writesClosure", p)
def warn (p : String) : String × String := ("writesClosureOpen", p)

#guard (cases.map named) == [
  [warn triggerLean],
  [err triggerLean, err "lean/Fw/Ci/Intent.lean", err "lean/Fw/Ci/Overflow.lean", err "lean/Fw/Ci/Pool/Caps.lean"],
  [],
  [warn triggerLean],
  [err triggerLean],
  [],
  [warn triggerLean],
  [],
  [],
  [warn triggerLean],
  [],
  [],
  [],
  [],
  [],
  []]

-- Each error names a path a later graph commit added to the row.
#guard cases.all fun c => (named c).all fun (code, p) => code != "writesClosure" || c.added.contains p

#guard kindOf "packages/contracts/golden/parts/footprint*.jsonl" == .golden
#guard kindOf "packages/contracts/golden/ci/**" == .other
#guard kindOf "lean/scripts/*WkCost*.lean" == .script
#guard kindOf "lean/scripts/check.sh" == .other
#guard kindOf "lean/Fw/Plan/WritesClosure.lean" == .module
#guard kindOf "lean/Fw/**" == .module
#guard kindOf ".github/workflows/font-fidelity.yml" == .workflow
#guard kindOf "docs/team/tools/trajectory-probe.md" == .other
#guard freshOf ["lean/scripts/WkCostGolden.lean"] "lean/scripts/*WkCost*.lean" == .open
#guard freshOf ["lean/scripts/WkCostGolden.lean"] "lean/scripts/WkCostSums.lean" == .new
#guard freshOf ["lean/Fw/Ci/Trigger.lean"] "lean/Fw/Ci/Trigger.lean" == .existing
#guard freshOf [] "packages/contracts/golden/parts/footprint*.jsonl" == .new

/-! ## Golden -/

open Lean (Json)

def strs (xs : List String) : Json := .arr (xs.toArray.map Json.str)

def pathRow (tracked : List String) (w : String) : Json :=
  Json.mkObj [("type", "path"), ("write", w), ("tracked", strs tracked), ("kind", (kindOf w).name),
    ("fresh", (freshOf tracked w).name), ("implied", strs (implied (kindOf w)))]

def caseRow (c : Case) : Json :=
  let t := c.task
  Json.mkObj [("type", "case"), ("name", c.name), ("graph", c.graph), ("id", t.id), ("owner", t.owner),
    ("stream", t.stream), ("done", t.done), ("writes", strs t.writes), ("tracked", strs c.tracked),
    ("required", strs (required c.tracked t.writes)), ("mayNeed", strs (mayNeed c.tracked t.writes)),
    ("violations", strs (missing c.tracked t ++ missingOpen c.tracked t)),
    ("findings", .arr ((findings c.tracked t).toArray.map fun f =>
      Json.mkObj [("task", f.task), ("code", f.code), ("severity", f.severity), ("detail", f.detail)])),
    ("added", strs c.added)]

def pathVectors : List (List String × String) := [
  ([], "packages/contracts/golden/plan/writes-closure.jsonl"), ([], "packages/contracts/golden/**"),
  ([], "packages/contracts/golden/ci/triggers.jsonl"), ([], "packages/contracts/golden/ci/**"),
  ([], "lean/scripts/X.lean"), ([], "lean/scripts/**"), ([], "lean/scripts/check.sh"), ([], "lean/scripts/x.mjs"),
  ([], "lean/Fw/A/B.lean"), ([], "lean/Fw/**"), ([], "lean/Fw/A/*"), ([], "lean/FwTestMain.lean"),
  ([], ".github/workflows/a.yml"), ([], ".github/workflows/a.yaml"), ([], ".github/workflows/*"),
  ([], ".github/scripts/a.mjs"), ([], "!packages/contracts/golden/a.jsonl"), ([], "docs/team/tools/x.md"),
  (["lean/scripts/WkCostGolden.lean"], "lean/scripts/*WkCost*.lean"),
  (["lean/scripts/WkCostGolden.lean"], "lean/scripts/WkCostSums.lean"),
  (["lean/Fw/Ci/Trigger.lean"], "lean/Fw/Ci/Trigger.lean"), (["lean/Fw/Ci/Trigger.lean"], "lean/Fw/Ci"),
  (["lean/Fw/Ci/Trigger.lean"], "lean/Fw/**"), (["lean/Fw/Ci/Trigger.lean"], "lean/Fw/Ci/T*.lean"),
  (["a/b/c.json"], "a/**/c.json"), (["a/b/c.json"], "a/*/d.json")]

def goldenText : String :=
  String.join ((pathVectors.map fun (tr, w) => (pathRow tr w).compress ++ "\n") ++
    cases.map fun c => (caseRow c).compress ++ "\n")

def goldenPath : String := "../packages/contracts/golden/plan/writes-closure.jsonl"

/-- Writes the golden; `--check` compares it instead and fails when it is stale. -/
def run (args : List String) : IO UInt32 := do
  if args.contains "--check" then
    let cur ← try IO.FS.readFile goldenPath catch _ => pure ""
    if cur != goldenText then
      IO.println s!"writes-closure golden: {goldenPath} is stale (regenerate: cd lean && lake env lean --run scripts/WritesClosureGolden.lean)"
      return 1
    IO.println s!"writes-closure golden: {cases.length} cases, up to date"
    return 0
  IO.FS.writeFile goldenPath goldenText
  IO.println s!"writes-closure golden: {cases.length} cases written"
  return 0

end Fw.Plan.WritesClosure

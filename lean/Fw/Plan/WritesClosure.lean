import Lean.Data.Json
import Fw.Console.Land

namespace Fw.Plan.WritesClosure
open Fw.Ops.PathCheck Fw.Console.Land

inductive Kind | module | workflow | other
deriving DecidableEq, Repr

def Kind.name : Kind → String
  | .module => "module" | .workflow => "workflow" | .other => "other"

def lastSeg (w : String) : String := ((w.splitOn "/").getLast?).getD ""

def wild (s : String) : Bool := s == "*" || s == "**"

def leanFile (w : String) : Bool := (lastSeg w).endsWith ".lean" || wild (lastSeg w)

def ymlFile (w : String) : Bool :=
  (lastSeg w).endsWith ".yml" || (lastSeg w).endsWith ".yaml" || wild (lastSeg w)

def kindOf (w : String) : Kind :=
  if w.startsWith "lean/Fw/" && leanFile w then .module
  else if w.startsWith ".github/workflows/" && ymlFile w then .workflow
  else .other

def checkSh : String := "lean/scripts/check.sh"
def triggerLean : String := "lean/Fw/Ci/Trigger.lean"
def triggersGolden : String := "packages/contracts/golden/ci/triggers.jsonl"
def fwRoot : String := "lean/Fw.lean"

def triggerFix : List String := [triggerLean, triggersGolden]

def wfTables : List String :=
  triggerFix ++ ["lean/Fw/Ci/Intent.lean", "packages/contracts/golden/ci/intent.jsonl", "lean/Fw/Ci/Overflow.lean"]

def implied : Kind → List String
  | .module => [fwRoot]
  | .workflow => wfTables
  | .other => []

inductive Fresh | new | existing | «open»
deriving DecidableEq, Repr

def Fresh.name : Fresh → String
  | .new => "new" | .existing => "existing" | .open => "open"

def isGlob (w : String) : Bool := w.toList.contains '*'

def freshOf (tracked : List String) (w : String) : Fresh :=
  if tracked.any (inScope (parseScope [w])) then (if isGlob w then .open else .existing) else .new

def needs (tracked writes : List String) (f : Fresh) : List String :=
  ((writes.filter (freshOf tracked · == f)).flatMap (implied ∘ kindOf)).eraseDups

/-- A literal `../<path>` read of a `lean/scripts/*.sh` the lean.yml row lacks: a `leanInputProblems` refusal. -/
structure Gap where
  script : String
  path : String
deriving Repr, BEq, DecidableEq

def names (writes : List String) (p : String) : Bool := inScope (parseScope writes) p

def owned (writes : List String) (gaps : List Gap) : List Gap :=
  gaps.filter fun g => names writes g.path || names writes g.script

def readNeeds (writes : List String) (gaps : List Gap) : List String :=
  if (owned writes gaps).isEmpty then [] else triggerFix

def required (tracked writes : List String) (gaps : List Gap) : List String :=
  (needs tracked writes .new ++ readNeeds writes gaps).eraseDups

def mayNeed (tracked writes : List String) (gaps : List Gap) : List String :=
  (needs tracked writes .open).filter (!(required tracked writes gaps).contains ·)

structure Task where
  id : String
  owner : String
  stream : String
  writes : List String
  done : Bool
deriving Repr

def scopeOf (t : Task) : List String := landScope t.writes [t.id, t.owner] [] t.id t.stream

def missing (tracked : List String) (gaps : List Gap) (t : Task) : List String :=
  if t.done then [] else violations (scopeOf t) (required tracked t.writes gaps)

def missingOpen (tracked : List String) (gaps : List Gap) (t : Task) : List String :=
  if t.done then [] else violations (scopeOf t) (mayNeed tracked t.writes gaps)

def source (tracked writes : List String) (gaps : List Gap) (f : Fresh) (p : String) : String :=
  match (writes.filter (freshOf tracked · == f)).find? fun w => (implied (kindOf w)).contains p with
  | some w => w
  | none => if f == .new then ((owned writes gaps).head?.map fun g => "../" ++ g.path ++ " in " ++ g.script).getD ""
      else ""

structure Finding where
  task : String
  code : String
  severity : String
  detail : String
deriving Repr, BEq

def findings (tracked : List String) (gaps : List Gap) (t : Task) : List Finding :=
  (missing tracked gaps t).map (fun p =>
      ⟨t.id, "writesClosure", "error", p ++ " for " ++ source tracked t.writes gaps .new p⟩) ++
    (missingOpen tracked gaps t).map (fun p =>
      ⟨t.id, "writesClosureOpen", "warn", p ++ " for " ++ source tracked t.writes gaps .open p⟩)

theorem kindOf_module_iff (w : String) :
    kindOf w = .module ↔ w.startsWith "lean/Fw/" = true ∧ leanFile w = true := by
  unfold kindOf; repeat' split
  all_goals simp_all

theorem kindOf_workflow_iff (w : String) :
    kindOf w = .workflow ↔ (w.startsWith "lean/Fw/" && leanFile w) = false ∧
      w.startsWith ".github/workflows/" = true ∧ ymlFile w = true := by
  unfold kindOf; repeat' split
  all_goals simp_all

theorem implied_eq_nil_iff (k : Kind) : implied k = [] ↔ k = .other := by
  cases k <;> simp [implied, wfTables, triggerFix]

theorem implied_module : implied .module = [fwRoot] := rfl

theorem implied_workflow : implied .workflow = wfTables := rfl

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

theorem mem_needs (tr ws : List String) (f : Fresh) (p : String) :
    p ∈ needs tr ws f ↔ ∃ w ∈ ws, freshOf tr w = f ∧ p ∈ implied (kindOf w) := by
  simp [needs, List.mem_eraseDups, and_assoc]

theorem mem_owned (ws : List String) (gs : List Gap) (g : Gap) :
    g ∈ owned ws gs ↔ g ∈ gs ∧ (names ws g.path = true ∨ names ws g.script = true) := by
  simp [owned]

theorem mem_readNeeds (ws : List String) (gs : List Gap) (p : String) :
    p ∈ readNeeds ws gs ↔ owned ws gs ≠ [] ∧ p ∈ triggerFix := by
  unfold readNeeds; split <;> simp_all [List.isEmpty_iff]

theorem mem_required (tr ws : List String) (gs : List Gap) (p : String) :
    p ∈ required tr ws gs ↔
      (∃ w ∈ ws, freshOf tr w = .new ∧ p ∈ implied (kindOf w)) ∨ (owned ws gs ≠ [] ∧ p ∈ triggerFix) := by
  simp only [required, List.mem_eraseDups, List.mem_append, mem_needs, mem_readNeeds]

theorem mem_required_no_gaps (tr ws : List String) (p : String) :
    p ∈ required tr ws [] ↔ ∃ w ∈ ws, freshOf tr w = .new ∧ p ∈ implied (kindOf w) := by
  rw [mem_required]; simp [owned]

theorem trigger_required_iff (tr ws : List String) (gs : List Gap) :
    triggerLean ∈ required tr ws gs ↔
      (∃ w ∈ ws, freshOf tr w = .new ∧ kindOf w = .workflow) ∨ owned ws gs ≠ [] := by
  rw [mem_required]
  constructor
  · rintro (⟨w, hw, hn, hp⟩ | ⟨h, _⟩)
    · refine .inl ⟨w, hw, hn, ?_⟩
      cases hk : kindOf w <;> simp_all [implied, fwRoot, triggerLean]
    · exact .inr h
  · rintro (⟨w, hw, hn, hk⟩ | h)
    · exact .inl ⟨w, hw, hn, by simp [hk, implied, wfTables, triggerFix]⟩
    · exact .inr ⟨h, by simp [triggerFix]⟩

theorem trigger_only_by_read (tr ws : List String) (gs : List Gap)
    (hw : ∀ w ∈ ws, freshOf tr w = .new → kindOf w ≠ .workflow) :
    triggerLean ∈ required tr ws gs ↔ ∃ g ∈ gs, names ws g.path = true ∨ names ws g.script = true := by
  rw [trigger_required_iff]
  constructor
  · rintro (⟨w, h1, h2, h3⟩ | h)
    · exact absurd h3 (hw w h1 h2)
    · obtain ⟨g, hg⟩ := List.exists_mem_of_ne_nil _ h
      exact ⟨g, ((mem_owned ws gs g).mp hg).1, ((mem_owned ws gs g).mp hg).2⟩
  · rintro ⟨g, hg, hn⟩
    exact .inr (List.ne_nil_of_mem ((mem_owned ws gs g).mpr ⟨hg, hn⟩))

theorem required_eq_nil_iff (tr ws : List String) (gs : List Gap) :
    required tr ws gs = [] ↔ (∀ w ∈ ws, freshOf tr w = .new → kindOf w = .other) ∧ owned ws gs = [] := by
  constructor
  · intro h
    refine ⟨fun w hw hn => ?_, ?_⟩
    · rw [← implied_eq_nil_iff]
      refine List.eq_nil_iff_forall_not_mem.mpr fun p hp => ?_
      have := (mem_required tr ws gs p).mpr (.inl ⟨w, hw, hn, hp⟩)
      simp [h] at this
    · refine Classical.byContradiction fun ho => ?_
      have := (mem_required tr ws gs triggerLean).mpr (.inr ⟨ho, by simp [triggerFix]⟩)
      simp [h] at this
  · rintro ⟨h, ho⟩
    refine List.eq_nil_iff_forall_not_mem.mpr fun p hp => ?_
    rcases (mem_required tr ws gs p).mp hp with ⟨w, hw, hn, hp⟩ | ⟨hne, _⟩
    · simp [(implied_eq_nil_iff _).mpr (h w hw hn)] at hp
    · exact hne ho

theorem required_of_new (tr ws : List String) (gs : List Gap) (w : String) (hw : w ∈ ws)
    (hn : freshOf tr w = .new) : ∀ p ∈ implied (kindOf w), p ∈ required tr ws gs :=
  fun p hp => (mem_required tr ws gs p).mpr (.inl ⟨w, hw, hn, hp⟩)

theorem required_module (tr ws : List String) (gs : List Gap) (w : String) (hw : w ∈ ws)
    (hn : freshOf tr w = .new) (hk : kindOf w = .module) : fwRoot ∈ required tr ws gs := by
  have := required_of_new tr ws gs w hw hn; rw [hk] at this; exact this _ (by simp [implied])

theorem required_workflow (tr ws : List String) (gs : List Gap) (w : String) (hw : w ∈ ws)
    (hn : freshOf tr w = .new) (hk : kindOf w = .workflow) : ∀ p ∈ wfTables, p ∈ required tr ws gs := by
  have := required_of_new tr ws gs w hw hn; rw [hk] at this; exact this

theorem required_of_gap (tr ws : List String) (gs : List Gap) (g : Gap) (hg : g ∈ gs)
    (hn : names ws g.path = true ∨ names ws g.script = true) : ∀ p ∈ triggerFix, p ∈ required tr ws gs :=
  fun p hp => (mem_required tr ws gs p).mpr
    (.inr ⟨List.ne_nil_of_mem ((mem_owned ws gs g).mpr ⟨hg, hn⟩), hp⟩)

theorem mem_mayNeed (tr ws : List String) (gs : List Gap) (p : String) :
    p ∈ mayNeed tr ws gs ↔ (∃ w ∈ ws, freshOf tr w = .open ∧ p ∈ implied (kindOf w)) ∧ p ∉ required tr ws gs := by
  simp [mayNeed, mem_needs]

theorem mem_missing_iff (tr : List String) (gs : List Gap) (t : Task) (hd : t.done = false) (p : String) :
    p ∈ missing tr gs t ↔ p ∈ required tr t.writes gs ∧ inScope (parseScope (scopeOf t)) p = false := by
  simp [missing, hd, mem_violations]

theorem mem_missingOpen_iff (tr : List String) (gs : List Gap) (t : Task) (hd : t.done = false) (p : String) :
    p ∈ missingOpen tr gs t ↔ p ∈ mayNeed tr t.writes gs ∧ inScope (parseScope (scopeOf t)) p = false := by
  simp [missingOpen, hd, mem_violations]

theorem missing_nil_iff_land_ok (tr : List String) (gs : List Gap) (t : Task) (hd : t.done = false)
    (hw : t.writes ≠ []) :
    missing tr gs t = [] ↔
      landVerdict t.writes [t.id, t.owner] [] (required tr t.writes gs) t.id t.stream = .ok := by
  cases hv : violations (scopeOf t) (required tr t.writes gs) <;>
    simp_all [landVerdict, missing, scopeOf, List.isEmpty_iff]

theorem missing_refused (tr : List String) (gs : List Gap) (t : Task) (hd : t.done = false) (p : String)
    (h : p ∈ missing tr gs t) : p ∈ violations (scopeOf t) [p] := by
  rw [mem_violations]; exact ⟨by simp, ((mem_missing_iff tr gs t hd p).mp h).2⟩

theorem one_call (tr : List String) (gs : List Gap) (t : Task) (hd : t.done = false) :
    violations (scopeOf t) (required tr t.writes gs ++ mayNeed tr t.writes gs) =
      missing tr gs t ++ missingOpen tr gs t := by
  simp [violations, missing, missingOpen, hd, List.filter_append]

theorem done_silent (tr : List String) (gs : List Gap) (t : Task) (hd : t.done = true) :
    findings tr gs t = [] := by
  simp [findings, missing, missingOpen, hd]

theorem error_iff (tr : List String) (gs : List Gap) (t : Task) :
    (∃ f ∈ findings tr gs t, f.severity = "error") ↔ missing tr gs t ≠ [] := by
  constructor
  · rintro ⟨f, hf, hs⟩
    simp only [findings, List.mem_append, List.mem_map] at hf
    rcases hf with ⟨p, hp, rfl⟩ | ⟨p, _, rfl⟩
    · exact List.ne_nil_of_mem hp
    · simp at hs
  · intro h
    obtain ⟨p, hp⟩ := List.exists_mem_of_ne_nil _ h
    exact ⟨_, List.mem_append_left _ (List.mem_map_of_mem hp), rfl⟩

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

structure Case where
  name : String
  graph : String
  tree : String
  task : Task
  tracked : List String
  gaps : List Gap
  added : List String

def classposGap : Gap := ⟨checkSh, "packages/contracts/golden/parts/footprint.classpos.jsonl"⟩

def sumsGap : Gap := ⟨checkSh, "packages/contracts/golden/measure/wkcost-sums.jsonl"⟩

def otherGap : Gap := ⟨checkSh, "packages/x/y.jsonl"⟩

def cases : List Case := [
  ⟨"r322 before: counts-font-fidelity", "31bf66d51^", "31bf66d51^",
    mk "counts-font-fidelity" "measure-engineer" "measure" fontPre, fontTracked, [],
    [".github/workflows/font-fidelity.yml"] ++ fontTables⟩,
  ⟨"r322 workflow named, tables not", "31bf66d51^", "31bf66d51^",
    mk "counts-font-fidelity" "measure-engineer" "measure" (fontPre ++ [".github/workflows/font-fidelity.yml"]),
    fontTracked, [], fontTables⟩,
  ⟨"r322 after", "31bf66d51", "31bf66d51", mk "counts-font-fidelity" "measure-engineer" "measure" fontPost,
    fontTracked, [], []⟩,
  ⟨"r323 before: footprint-classname-operands", "132cfa8e1^", "132cfa8e1^",
    mk "footprint-classname-operands" "part-builder" "parts" footPre, footTracked, [],
    footR323.drop footPre.length ++ footLater⟩,
  ⟨"r323 after", "132cfa8e1", "132cfa8e1", mk "footprint-classname-operands" "part-builder" "parts" footR323,
    footTracked, [], footLater⟩,
  ⟨"r325 before", "6d61219e9^", "f4743ef8a",
    mk "footprint-classname-operands" "part-builder" "parts" (footR323 ++ [checkSh]), footTracked, [classposGap],
    triggerFix⟩,
  ⟨"r325 after", "6d61219e9", "f4743ef8a",
    mk "footprint-classname-operands" "part-builder" "parts" (footR323 ++ footLater), footTracked, [classposGap], []⟩,
  ⟨"r328 before: morph-cost-sums-golden", "890278714^", "890278714^",
    mk "morph-cost-sums-golden" "measure-engineer" "measure" morphPre, morphTracked, [], morphAdded⟩,
  ⟨"r328 build branch", "890278714^", "5599b944d",
    mk "morph-cost-sums-golden" "measure-engineer" "measure" morphPre, morphTracked, [sumsGap], morphAdded⟩,
  ⟨"r328 after", "890278714", "5599b944d",
    mk "morph-cost-sums-golden" "measure-engineer" "measure" (morphPre ++ morphAdded), morphTracked, [sumsGap], []⟩,
  ⟨"r330 before: counts-font-fidelity", "b3f6f21bd^", "b3f6f21bd^",
    mk "counts-font-fidelity" "measure-engineer" "measure" fontPost, fontTracked, [],
    ["lean/Fw/Faithful/Measured.lean", "results/faithful/**", "packages/measure-chromium/test/faithful.test.mjs"]⟩,
  ⟨"r331 before: hero-probe-original", "1baf5a8a5^", "1baf5a8a5^",
    mk "hero-probe-original" "measure-engineer" "gate" probePre, probeTracked, [], ["docs/team/tools/trajectory-probe.md"]⟩,
  ⟨"r334 before: hero-exit-threaded-pix", "f3248e954^", "f3248e954^",
    mk "hero-exit-threaded-pix" "measure-engineer" "measure" pixPre, [], [], pixAdded⟩,
  ⟨"r334 after", "f3248e954", "f3248e954",
    mk "hero-exit-threaded-pix" "measure-engineer" "measure" (pixPre ++ pixAdded), pixTracked, [], []⟩,
  ⟨"graph-writes-closure", "f3248e954", "f3248e954",
    mk "graph-writes-closure" "lean-prover" "tooling" selfWrites, selfTracked, [], []⟩,
  ⟨"a new module alone", "-", "-", mk "x" "o" "tooling" ["lean/Fw/X/New.lean"], [], [], [fwRoot]⟩,
  ⟨"a new workflow alone", "-", "-", mk "x" "o" "tooling" [".github/workflows/new.yml"], [], [], wfTables⟩,
  ⟨"a gap in a script the row writes", "-", "-", mk "x" "o" "tooling" [checkSh], [], [otherGap], triggerFix⟩,
  ⟨"a gap of another row", "-", "-", mk "x" "o" "tooling" ["apps/runner/src/x.ts"], [], [otherGap], []⟩,
  ⟨"no artefact", "-", "-", mk "x" "o" "tooling" ["apps/runner/src/x.ts", "docs/team/tools/x.md"], [], [], []⟩,
  ⟨"a done row", "-", "-", { mk "x" "o" "tooling" [".github/workflows/new.yml"] with done := true }, [], [], []⟩]

def named (c : Case) : List (String × String) :=
  (findings c.tracked c.gaps c.task).map fun f => (f.code, (f.detail.splitOn " for ").headD "")

def err (p : String) : String × String := ("writesClosure", p)
def warn (p : String) : String × String := ("writesClosureOpen", p)

#guard (cases.map named) == [
  [],
  [err triggerLean, err "lean/Fw/Ci/Intent.lean", err "lean/Fw/Ci/Overflow.lean"],
  [],
  [],
  [],
  [err triggerLean],
  [],
  [],
  [err triggerLean],
  [],
  [],
  [],
  [],
  [],
  [],
  [],
  [err triggerLean, err "lean/Fw/Ci/Intent.lean", err "lean/Fw/Ci/Overflow.lean"],
  [err triggerLean],
  [],
  [],
  []]

#guard cases.all fun c => (named c).all fun (code, p) => code != "writesClosure" || c.added.contains p

def admitted (c : Case) (p : String) : Bool := inScope (parseScope (scopeOf c.task)) p

def covers (c : Case) (table : List String) : Bool :=
  (c.added.filter table.contains).all fun p => admitted c p || (named c).contains (err p)

def newOf (c : Case) (k : Kind) : Bool :=
  c.task.writes.any fun w => freshOf c.tracked w == .new && kindOf w == k

#guard cases.all fun c => c.task.done || !newOf c .workflow || covers c wfTables
#guard cases.all fun c => c.task.done || !newOf c .module || covers c [fwRoot]
#guard cases.all fun c => c.task.done || (owned c.task.writes c.gaps).isEmpty || covers c triggerFix
#guard cases.all fun c => newOf c .workflow || !(named c).contains (err triggerLean) || !(owned c.task.writes c.gaps).isEmpty

#guard kindOf "packages/contracts/golden/parts/footprint*.jsonl" == .other
#guard kindOf "lean/scripts/*WkCost*.lean" == .other
#guard kindOf "lean/scripts/check.sh" == .other
#guard kindOf "lean/Fw/Plan/WritesClosure.lean" == .module
#guard kindOf "lean/Fw/**" == .module
#guard kindOf ".github/workflows/font-fidelity.yml" == .workflow
#guard kindOf "docs/team/tools/trajectory-probe.md" == .other
#guard freshOf ["lean/scripts/WkCostGolden.lean"] "lean/scripts/*WkCost*.lean" == .open
#guard freshOf ["lean/scripts/WkCostGolden.lean"] "lean/scripts/WkCostSums.lean" == .new
#guard freshOf ["lean/Fw/Ci/Trigger.lean"] "lean/Fw/Ci/Trigger.lean" == .existing
#guard freshOf [] "packages/contracts/golden/parts/footprint*.jsonl" == .new
#guard owned ["packages/contracts/golden/parts/footprint*.jsonl"] [classposGap] == [classposGap]
#guard owned [checkSh] [otherGap] == [otherGap]
#guard owned ["packages/contracts/golden/parts/footprint*.json"] [classposGap] == []
#guard required [] ["packages/contracts/golden/measure/new.jsonl"] [] == []

open Lean (Json)

def strs (xs : List String) : Json := .arr (xs.toArray.map Json.str)

def gapJson (g : Gap) : Json := Json.mkObj [("script", g.script), ("path", g.path)]

def pathRow (tracked : List String) (w : String) : Json :=
  Json.mkObj [("type", "path"), ("write", w), ("tracked", strs tracked), ("kind", (kindOf w).name),
    ("fresh", (freshOf tracked w).name), ("implied", strs (implied (kindOf w)))]

def caseRow (c : Case) : Json :=
  let t := c.task
  Json.mkObj [("type", "case"), ("name", c.name), ("graph", c.graph), ("tree", c.tree), ("id", t.id),
    ("owner", t.owner), ("stream", t.stream), ("done", t.done), ("writes", strs t.writes), ("tracked", strs c.tracked),
    ("gaps", .arr (c.gaps.toArray.map gapJson)), ("owned", .arr ((owned t.writes c.gaps).toArray.map gapJson)),
    ("required", strs (required c.tracked t.writes c.gaps)), ("mayNeed", strs (mayNeed c.tracked t.writes c.gaps)),
    ("violations", strs (missing c.tracked c.gaps t ++ missingOpen c.tracked c.gaps t)),
    ("findings", .arr ((findings c.tracked c.gaps t).toArray.map fun f =>
      Json.mkObj [("task", f.task), ("code", f.code), ("severity", f.severity), ("detail", f.detail)])),
    ("added", strs c.added)]

def pathVectors : List (List String × String) := [
  ([], "packages/contracts/golden/plan/writes-closure.jsonl"), ([], "packages/contracts/golden/**"),
  ([], "packages/contracts/golden/ci/triggers.jsonl"), ([], "lean/scripts/X.lean"), ([], "lean/scripts/check.sh"),
  ([], "lean/Fw/A/B.lean"), ([], "lean/Fw/**"), ([], "lean/Fw/A/*"), ([], "lean/Fw/A/b.md"), ([], "lean/FwTestMain.lean"),
  ([], ".github/workflows/a.yml"), ([], ".github/workflows/a.yaml"), ([], ".github/workflows/*"),
  ([], ".github/workflows/a.md"), ([], ".github/scripts/a.mjs"), ([], "!lean/Fw/A.lean"), ([], "docs/team/tools/x.md"),
  (["lean/scripts/WkCostGolden.lean"], "lean/scripts/*WkCost*.lean"),
  (["lean/scripts/WkCostGolden.lean"], "lean/scripts/WkCostSums.lean"),
  (["lean/Fw/Ci/Trigger.lean"], "lean/Fw/Ci/Trigger.lean"), (["lean/Fw/Ci/Trigger.lean"], "lean/Fw/Ci"),
  (["lean/Fw/Ci/Trigger.lean"], "lean/Fw/**"), (["lean/Fw/Ci/Trigger.lean"], "lean/Fw/Ci/T*.lean"),
  (["a/b/c.json"], "a/**/c.json"), (["a/b/c.json"], "a/*/d.json")]

def goldenText (_ : Unit) : String :=
  String.join ((pathVectors.map fun (tr, w) => (pathRow tr w).compress ++ "\n") ++
    cases.map fun c => (caseRow c).compress ++ "\n")

def goldenPath : String := "../packages/contracts/golden/plan/writes-closure.jsonl"

def run (args : List String) : IO UInt32 := do
  if args.contains "--check" then
    let cur ← try IO.FS.readFile goldenPath catch _ => pure ""
    if cur != goldenText () then
      IO.println s!"writes-closure golden: {goldenPath} is stale (regenerate: cd lean && lake env lean --run scripts/WritesClosureGolden.lean)"
      return 1
    IO.println s!"writes-closure golden: {cases.length} cases, up to date"
    return 0
  IO.FS.writeFile goldenPath (goldenText ())
  IO.println s!"writes-closure golden: {cases.length} cases written"
  return 0

end Fw.Plan.WritesClosure

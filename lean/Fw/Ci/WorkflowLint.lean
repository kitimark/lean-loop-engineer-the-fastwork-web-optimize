import Lean.Data.Json
import Fw.Console.LandSpeed

/-!
Selection and verdict of the `workflow-lint` land check (`actionlint` on the workflow files).
-/
namespace Fw.Ci.WorkflowLint

open Lean (Json)
open Fw.Console.LandSpeed (Decl selectChecks mem_selectChecks)

def checkId : String := "workflow-lint"

def reads : List String := [".github/workflows/*.yml", ".github/workflows/*.yaml", "scripts/check-workflows.sh"]

def decls : List Decl := [⟨checkId, reads⟩]

def select (changed : List String) : List String := selectChecks decls changed

theorem select_iff (changed : List String) :
    checkId ∈ select changed ↔ Fw.Console.LandSpeed.selected reads changed = true := by
  unfold select
  rw [mem_selectChecks]
  simp [decls]

open Fw.Ops.PathCheck (segs segMatch globMatch matchesPath inScope parseScope inScope_iff)

set_option maxRecDepth 4096 in
theorem parse_reads : parseScope reads =
    ⟨[[".github", "workflows", "*.yml"], [".github", "workflows", "*.yaml"], ["scripts", "check-workflows.sh"]], []⟩ := by
  have hi : reads.filter (!·.startsWith "!") = reads := by
    simp (config := {decide := true}) [reads]
  have he : reads.filter (·.startsWith "!") = [] := by
    simp (config := {decide := true}) [reads]
  rw [parseScope, hi, he]
  simp only [List.map_nil, reads, List.map_cons, Fw.Ops.PathCheck.Scope.mk.injEq, List.cons.injEq, and_true]
  and_intros <;> simp (config := {decide := true}) [segs, String.splitOn, String.splitOnAux]

theorem select_of_inScope (changed : List String) (x : String) (hx : x ∈ changed)
    (hin : inScope (parseScope reads) x = true) : checkId ∈ select changed :=
  (select_iff changed).2 (Fw.Console.LandSpeed.selected_of_mem reads changed x hx hin)

theorem yml_selects (changed : List String) (x n : String) (hx : x ∈ changed)
    (hs : segs x = [".github", "workflows", n]) (hr : ".." ∉ segs x) (hn : segMatch "*.yml".toList n.toList = true) :
    checkId ∈ select changed := by
  refine select_of_inScope changed x hx ?_
  rw [inScope_iff, parse_reads]
  refine ⟨by simp [hs], hr, ⟨[".github", "workflows", "*.yml"], by simp, ?_⟩, by simp⟩
  simp only [matchesPath, List.any_eq_true, List.mem_range, hs]
  refine ⟨2, by simp, ?_⟩
  simpa [globMatch, segMatch] using hn

theorem yaml_selects (changed : List String) (x n : String) (hx : x ∈ changed)
    (hs : segs x = [".github", "workflows", n]) (hr : ".." ∉ segs x) (hn : segMatch "*.yaml".toList n.toList = true) :
    checkId ∈ select changed := by
  refine select_of_inScope changed x hx ?_
  rw [inScope_iff, parse_reads]
  refine ⟨by simp [hs], hr, ⟨[".github", "workflows", "*.yaml"], by simp, ?_⟩, by simp⟩
  simp only [matchesPath, List.any_eq_true, List.mem_range, hs]
  refine ⟨2, by simp, ?_⟩
  simpa [globMatch, segMatch] using hn

theorem script_selects (changed : List String) (x : String) (hx : x ∈ changed)
    (hs : segs x = ["scripts", "check-workflows.sh"]) : checkId ∈ select changed := by
  refine select_of_inScope changed x hx ?_
  rw [inScope_iff, parse_reads, hs]
  refine ⟨by simp, by simp (config := {decide := true}), ⟨["scripts", "check-workflows.sh"], by simp, ?_⟩, by simp⟩
  exact Fw.Ops.PathCheck.matchesPath_lit _ (by simp) (by simp (config := {decide := true}))

#guard select [".github/workflows/trajectory-probe.yml"] == [checkId]
#guard select [".github/workflows/x.yaml"] == [checkId]
#guard select ["scripts/check-workflows.sh"] == [checkId]
#guard select ["docs/team/tools/land.md", ".github/scripts/changed-inputs.mjs", "apps/runner/src/land.ts"] == []
#guard select [".github/workflows/sub/x.txt"] == []
#guard select [] == []

structure Finding where
  kind : String
  file : String
  message : String
deriving Repr, DecidableEq

def errorKinds : List String := ["syntax-check", "expression"]

def isError (f : Finding) : Bool := errorKinds.contains f.kind

def accepted : List (String × String) := [(".github/workflows/webkit-sim.yml", "string should not be empty")]

def isAccepted (f : Finding) : Bool := accepted.contains (f.file, f.message)

def shown (fs : List Finding) : List Finding := fs.filter (!isAccepted ·)

inductive Verdict where
  | pass
  | warn
  | fail
  | refused
deriving DecidableEq, Repr

def Verdict.name : Verdict → String
  | .pass => "pass" | .warn => "warn" | .fail => "fail" | .refused => "refused"

def Verdict.exit : Verdict → Nat
  | .pass => 0 | .warn => 0 | .fail => 1 | .refused => 3

def verdict (installed : Bool) (fs : List Finding) : Verdict :=
  if !installed then .refused
  else if (shown fs).any isError then .fail
  else if (shown fs).isEmpty then .pass
  else .warn

theorem missing_refuses (fs : List Finding) : verdict false fs = .refused := by
  simp [verdict]

theorem error_fails (fs : List Finding) (f : Finding) (hf : f ∈ fs) (he : isError f = true) (ha : isAccepted f = false) :
    verdict true fs = .fail := by
  have h : (shown fs).any isError = true :=
    List.any_eq_true.2 ⟨f, List.mem_filter.2 ⟨hf, by simp [ha]⟩, he⟩
  simp [verdict, h]

theorem warnings_never_fail (fs : List Finding) (h : ∀ f ∈ fs, isError f = false) : (verdict true fs).exit = 0 := by
  have h' : (shown fs).any isError = false := by
    simp only [List.any_eq_false]
    intro f hf
    simpa using h f (List.mem_filter.1 hf).1
  unfold verdict
  simp only [h', Bool.not_true, Bool.false_eq_true, ↓reduceIte]
  split <;> rfl

theorem clean_passes : verdict true [] = .pass := by decide

theorem shellcheck_warns (file msg : String) (h : isAccepted ⟨"shellcheck", file, msg⟩ = false) :
    verdict true [⟨"shellcheck", file, msg⟩] = .warn := by
  simp [verdict, shown, isError, errorKinds, h]

theorem refused_not_ok : Verdict.refused.exit ≠ 0 := by decide

theorem dup_key_fails :
    verdict true [⟨"syntax-check", ".github/workflows/trajectory-probe.yml", "key \"SEARCH\" is duplicated in \"env\" section"⟩] = .fail := by
  decide

theorem accepted_passes :
    verdict true [⟨"syntax-check", ".github/workflows/webkit-sim.yml", "string should not be empty"⟩] = .pass := by
  decide

theorem accepted_is_file_scoped :
    verdict true [⟨"syntax-check", ".github/workflows/other.yml", "string should not be empty"⟩] = .fail := by
  decide

private def fjson (f : Finding) : Json := Json.mkObj [("kind", f.kind), ("file", f.file), ("message", f.message)]

private def strs (xs : List String) : Json := Json.arr (xs.map Json.str).toArray

private def selLine (name : String) (changed : List String) : Json :=
  Json.mkObj [("kind", "select"), ("name", name), ("request", Json.mkObj [("changed", strs changed), ("reads", strs reads)]),
    ("response", Json.mkObj [("select", strs (select changed))])]

private def verLine (name : String) (installed : Bool) (fs : List Finding) : Json :=
  Json.mkObj [("kind", "verdict"), ("name", name),
    ("request", Json.mkObj [("installed", installed), ("findings", Json.arr (fs.map fjson).toArray)]),
    ("response", Json.mkObj [("verdict", (verdict installed fs).name), ("exit", (verdict installed fs).exit)])]

private def dup : Finding := ⟨"syntax-check", ".github/workflows/trajectory-probe.yml", "key \"SEARCH\" is duplicated in \"env\" section"⟩
private def expr : Finding := ⟨"expression", ".github/workflows/x.yml", "property \"foo\" is not defined in object type"⟩
private def shell : Finding := ⟨"shellcheck", ".github/workflows/chromium-counts.yml", "shellcheck reported issue in this script: SC2086"⟩
private def empt : Finding := ⟨"syntax-check", ".github/workflows/webkit-sim.yml", "string should not be empty"⟩

def goldenText : String := String.join ((
  [selLine "yml workflow selects" [".github/workflows/trajectory-probe.yml"],
   selLine "yaml workflow selects" [".github/workflows/x.yaml"],
   selLine "own script selects" ["scripts/check-workflows.sh"],
   selLine "workflow among others selects" ["docs/x.md", ".github/workflows/lean.yml"],
   selLine "github script does not" [".github/scripts/changed-inputs.mjs"],
   selLine "nested file does not" [".github/workflows/sub/x.txt"],
   selLine "docs do not" ["docs/team/tools/land.md"],
   selLine "nothing changed" [],
   verLine "actionlint missing refuses" false [],
   verLine "actionlint missing refuses with only warnings" false [shell],
   verLine "duplicated env key fails (inc-workflow-dup-key)" true [dup],
   verLine "expression error fails" true [expr],
   verLine "shellcheck only warns" true [shell],
   verLine "no findings pass" true [],
   verLine "accepted webkit-sim finding passes" true [empt],
   verLine "accepted finding does not hide a duplicate key" true [empt, dup],
   verLine "same message in another file fails" true [{ empt with file := ".github/workflows/other.yml" }]]).map fun c => c.compress ++ "\n")

end Fw.Ci.WorkflowLint

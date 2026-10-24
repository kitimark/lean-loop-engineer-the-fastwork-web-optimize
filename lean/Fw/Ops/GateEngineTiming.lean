import Lean
/-! # Gate-engine step timing and cache save rule on land legs -/
namespace Fw.Ops.GateEngineTiming
open Lean

structure Sample where
  run : Nat
  job : Nat
  engine : String
  totalS : Nat
  aptS : Nat
  fetchS : Nat
  postS : Nat
  hit : Bool
  key : String
deriving Repr, DecidableEq

def baseTotalS (engine : String) : Nat := if engine == "webkit" then 33 else 23

def basePostS : Nat := 4

def marginS : Nat := 10

inductive StepClass | ok | aptVariance | other
deriving Repr, DecidableEq

def StepClass.name : StepClass → String
  | .ok => "ok" | .aptVariance => "aptVariance" | .other => "other"

def Sample.restS (s : Sample) : Nat := s.totalS - s.aptS

def stepClass (s : Sample) : StepClass :=
  if s.totalS < baseTotalS s.engine + marginS then .ok
  else if s.restS < marginS then .aptVariance else .other

inductive PostClass | ok | fixableSave
deriving Repr, DecidableEq

def PostClass.name : PostClass → String
  | .ok => "ok" | .fixableSave => "fixableSave"

def postClass (s : Sample) : PostClass :=
  if basePostS + marginS ≤ s.postS && !s.hit then .fixableSave else .ok

def shouldSave (ref : String) : Bool := !("ci/land-".toList.isPrefixOf ref.toList)

theorem main_saves : shouldSave "main" = true := by decide

theorem land_no_save : shouldSave "ci/land-timing-x-1234567" = false := by decide

theorem land_prefix_no_save (rest : String) : shouldSave ("ci/land-" ++ rest) = false := by
  simp [shouldSave, String.toList_append]

def refCases : List String :=
  ["main", "ci/land-timing-poller-snapshot-727ac77", "ci/gate-fix", "ci/landing", "ci/land-", "feature/land-x"]

def samples : List Sample := [
  ⟨40024272661, 120656499722, "webkit", 66, 60, 11, 6, false, "969c76e"⟩,
  ⟨40031018930, 120679099577, "webkit", 87, 82, 34, 9, false, "969c76e"⟩,
  ⟨40026269429, 120663290040, "webkit", 70, 65, 43, 43, false, "969c76e"⟩,
  ⟨40028997665, 120672380897, "webkit", 33, 28, 8, 8, false, "969c76e"⟩,
  ⟨40037942688, 120701995647, "webkit", 53, 48, 27, 7, false, "969c76e"⟩,
  ⟨40024272661, 120656499820, "chromium", 42, 37, 6, 5, false, "1a85621"⟩,
  ⟨40028997665, 120672380862, "chromium", 23, 19, 4, 4, false, "1a85621"⟩]

theorem all_miss : samples.all (fun s => !s.hit) = true := by decide

theorem key_stable : (samples.filter (·.engine == "webkit")).all (·.key == "969c76e") = true ∧
    (samples.filter (·.engine == "chromium")).all (·.key == "1a85621") = true := by decide

theorem alerted_webkit :
    (samples.take 3).map stepClass = [.aptVariance, .aptVariance, .aptVariance] ∧
    (samples.take 3).map postClass = [.ok, .ok, .fixableSave] := by decide

theorem alerted_chromium : (samples.drop 5).map stepClass = [.aptVariance, .ok] := by decide

theorem no_other : samples.all (fun s => stepClass s != .other) = true := by decide

theorem fixed_land_has_no_save : ∀ rest, shouldSave ("ci/land-" ++ rest) = false := land_prefix_no_save

def goldenLines : List Json :=
  (samples.map fun s => Json.mkObj [("kind", "sample"), ("run", toJson s.run), ("job", toJson s.job),
      ("engine", Json.str s.engine), ("totalS", toJson s.totalS), ("aptS", toJson s.aptS),
      ("fetchS", toJson s.fetchS), ("postS", toJson s.postS), ("hit", toJson s.hit), ("key", Json.str s.key),
      ("step", Json.str (stepClass s).name), ("post", Json.str (postClass s).name)]) ++
  (refCases.map fun r => Json.mkObj [("kind", "ref"), ("ref", Json.str r), ("save", toJson (shouldSave r))])

def goldenText : String := "\n".intercalate (goldenLines.map Json.compress) ++ "\n"

/-- Regenerate the golden, or check it with `--check`. -/
def gen (args : List String) : IO Unit := do
  let path := "../packages/contracts/golden/ops/gate-engine-timing.jsonl"
  if args.contains "--check" then
    let disk ← IO.FS.readFile path
    if disk != goldenText then
      throw (IO.userError s!"gate-engine-timing: {path} is stale; regenerate with Fw.Ops.GateEngineTiming.gen []")
    IO.println s!"gate-engine-timing: {path} equals the Lean output, {goldenLines.length} lines"
  else
    IO.FS.writeFile path goldenText

end Fw.Ops.GateEngineTiming

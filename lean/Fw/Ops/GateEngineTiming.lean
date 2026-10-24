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
  ⟨40028997665, 120672380862, "chromium", 23, 19, 4, 4, false, "1a85621"⟩,
  ⟨40047376675, 120732159815, "webkit", 39, 33, 5, 0, true, "969c76e"⟩,
  ⟨40047376675, 120732159810, "chromium", 19, 13, 1, 0, true, "1a85621"⟩]

theorem miss_before_restore : (samples.take 7).all (fun s => !s.hit) = true := by decide

theorem restored_legs_fast : (samples.drop 7).all (fun s => s.hit && s.postS ≤ 1 && stepClass s == .ok
    && postClass s == .ok) = true := by decide

theorem key_stable : (samples.filter (·.engine == "webkit")).all (·.key == "969c76e") = true ∧
    (samples.filter (·.engine == "chromium")).all (·.key == "1a85621") = true := by decide

theorem alerted_webkit :
    (samples.take 3).map stepClass = [.aptVariance, .aptVariance, .aptVariance] ∧
    (samples.take 3).map postClass = [.ok, .ok, .fixableSave] := by decide

theorem alerted_chromium : ((samples.drop 5).take 2).map stepClass = [.aptVariance, .ok] := by decide

theorem no_other : samples.all (fun s => stepClass s != .other) = true := by decide

theorem fixed_land_has_no_save : ∀ rest, shouldSave ("ci/land-" ++ rest) = false := land_prefix_no_save


def evictDays : Nat := 7

def evicted (idleDays : Nat) : Bool := evictDays ≤ idleDays

def seedsMain (engineRan holds : Bool) : Bool := holds || engineRan

def mainHolds (holds : Bool) (idleDays : Nat) : Bool := holds && !evicted idleDays

def needsReseed (holds : Bool) (idleDays : Nat) : Bool := !mainHolds holds idleDays

inductive RestoreClass
  | restored | firstSave | missingRestore | keyMiss
deriving Repr, DecidableEq

def RestoreClass.name : RestoreClass → String
  | .restored => "restored" | .firstSave => "firstSave"
  | .missingRestore => "missingRestore" | .keyMiss => "keyMiss"

def restoreClass (ref : String) (hit holds : Bool) : RestoreClass :=
  if hit then .restored
  else if shouldSave ref then .firstSave
  else if holds then .keyMiss else .missingRestore

theorem restoreClass_hit (ref : String) (holds : Bool) : restoreClass ref true holds = .restored := by
  simp [restoreClass]

theorem restoreClass_first (ref : String) (holds : Bool) (h : shouldSave ref = true) :
    restoreClass ref false holds = .firstSave := by
  simp [restoreClass, h]

theorem restoreClass_missing (rest : String) :
    restoreClass ("ci/land-" ++ rest) false false = .missingRestore := by
  simp [restoreClass, land_prefix_no_save]

theorem restoreClass_keyMiss (rest : String) :
    restoreClass ("ci/land-" ++ rest) false true = .keyMiss := by
  simp [restoreClass, land_prefix_no_save]

theorem skipped_keeps (holds : Bool) : seedsMain false holds = holds := by simp [seedsMain]

theorem ran_seeds (holds : Bool) : seedsMain true holds = true := by simp [seedsMain]

theorem unseeded_stays : seedsMain false false = false := by decide

theorem evicted_reseed (holds : Bool) : needsReseed holds evictDays = true := by
  simp [needsReseed, mainHolds, evicted]

theorem fresh_no_reseed : needsReseed true 6 = false := by decide

theorem unseeded_reseed (d : Nat) : needsReseed false d = true := by simp [needsReseed, mainHolds]

theorem weekly_restore_keeps (gap : Nat) (h : gap < evictDays) : needsReseed true gap = false := by
  simp [needsReseed, mainHolds, evicted]; omega

structure Leg where
  run : Nat
  engine : String
  ref : String
  hit : Bool
  holds : Bool
deriving Repr, DecidableEq

def legs : List Leg := [
  ⟨40024272661, "webkit", "ci/land-hero-copy-floor-followups-cd65384", false, false⟩,
  ⟨40031018930, "webkit", "ci/land-polish-wtname-wire-b1145f3", false, false⟩,
  ⟨40037942688, "webkit", "ci/land-gc-landed-identity-1c3a381", false, false⟩,
  ⟨40045796969, "webkit", "main", false, false⟩,
  ⟨40045796969, "chromium", "main", false, false⟩,
  ⟨40047376675, "webkit", "ci/land-gc-live-agent-cwd-b081d56", true, true⟩,
  ⟨40047376675, "chromium", "ci/land-gc-live-agent-cwd-b081d56", true, true⟩]

theorem legs_classes : legs.map (fun l => restoreClass l.ref l.hit l.holds) =
    [.missingRestore, .missingRestore, .missingRestore, .firstSave, .firstSave, .restored, .restored] := by decide

def restoreCases : List (String × Bool × Bool) :=
  ["main", "ci/land-x-1234567"].flatMap fun r => [false, true].flatMap fun h => [false, true].map fun m => (r, h, m)

theorem restoreCases_classes : restoreCases.map (fun c => (restoreClass c.1 c.2.1 c.2.2).name) =
    ["firstSave", "firstSave", "restored", "restored", "missingRestore", "keyMiss", "restored", "restored"] := by decide

def goldenLines : List Json :=
  (samples.map fun s => Json.mkObj [("kind", "sample"), ("run", toJson s.run), ("job", toJson s.job),
      ("engine", Json.str s.engine), ("totalS", toJson s.totalS), ("aptS", toJson s.aptS),
      ("fetchS", toJson s.fetchS), ("postS", toJson s.postS), ("hit", toJson s.hit), ("key", Json.str s.key),
      ("step", Json.str (stepClass s).name), ("post", Json.str (postClass s).name)]) ++
  (refCases.map fun r => Json.mkObj [("kind", "ref"), ("ref", Json.str r), ("save", toJson (shouldSave r))]) ++
  (legs.map fun l => Json.mkObj [("kind", "leg"), ("run", toJson l.run), ("engine", Json.str l.engine),
      ("ref", Json.str l.ref), ("hit", toJson l.hit), ("mainHolds", toJson l.holds),
      ("class", Json.str (restoreClass l.ref l.hit l.holds).name)]) ++
  (restoreCases.map fun (r, h, m) => Json.mkObj [("kind", "restoreCase"), ("ref", Json.str r), ("hit", toJson h),
      ("mainHolds", toJson m), ("class", Json.str (restoreClass r h m).name)]) ++
  ([(true, false), (false, false), (false, true), (true, true)].map fun (e, h) => Json.mkObj [("kind", "seed"),
      ("engineRan", toJson e), ("holds", toJson h), ("after", toJson (seedsMain e h))]) ++
  ([0, 6, 7, 8].flatMap fun d => [false, true].map fun h => Json.mkObj [("kind", "evict"), ("idleDays", toJson d),
      ("holds", toJson h), ("needsReseed", toJson (needsReseed h d))])

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

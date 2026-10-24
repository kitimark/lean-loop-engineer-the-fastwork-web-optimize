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


/-! ## Restore and seeding (task `gate-engine-cache-followups`)

A branch restores its own caches and `main`'s (docs.github.com, dependency caching, "Restrictions for accessing a
cache"). A `ci/land-*` leg saves nothing, so it hits only when `main` holds the entry for its key. `main` gets the entry
only from a push whose `engine` job ran, and GitHub evicts an entry unused for 7 days. -/

/-- An entry unused for this many days is evicted (docs.github.com, "Usage limits and eviction policy"). -/
def evictDays : Nat := 7

/-- The entry is gone after `idleDays` days without a restore. -/
def evicted (idleDays : Nat) : Bool := evictDays ≤ idleDays

/-- `main` holds the entry after a `main` push: it held it, or the push ran the `engine` job (a skipped job saves
nothing). -/
def seedsMain (engineRan holds : Bool) : Bool := holds || engineRan

/-- `main` still holds the entry after `idleDays` days without a restore. -/
def mainHolds (holds : Bool) (idleDays : Nat) : Bool := holds && !evicted idleDays

/-- The entry must be seeded again: `main` holds none, or it was evicted. -/
def needsReseed (holds : Bool) (idleDays : Nat) : Bool := !mainHolds holds idleDays

/-- What a gate-engine cache restore did on a leg that ran on `ref`, with `main` holding the entry or not. -/
inductive RestoreClass
  | restored | firstSave | missingRestore | keyMiss
deriving Repr, DecidableEq

def RestoreClass.name : RestoreClass → String
  | .restored => "restored" | .firstSave => "firstSave"
  | .missingRestore => "missingRestore" | .keyMiss => "keyMiss"

/-- `restored`: the restore hit. `firstSave`: a miss on a ref that saves, so this leg seeds its own ref.
`missingRestore`: a miss on a ref that saves nothing while `main` holds no entry (the entry was never seeded or was
evicted). `keyMiss`: a miss although `main` holds the entry, so the key differs. -/
def restoreClass (ref : String) (hit holds : Bool) : RestoreClass :=
  if hit then .restored
  else if shouldSave ref then .firstSave
  else if holds then .keyMiss else .missingRestore

/-- A hit is `restored` whatever the ref. -/
theorem restoreClass_hit (ref : String) (holds : Bool) : restoreClass ref true holds = .restored := by
  simp [restoreClass]

/-- A miss on a saving ref is `firstSave`. -/
theorem restoreClass_first (ref : String) (holds : Bool) (h : shouldSave ref = true) :
    restoreClass ref false holds = .firstSave := by
  simp [restoreClass, h]

/-- A miss on a land leg with nothing on `main` is `missingRestore`. -/
theorem restoreClass_missing (rest : String) :
    restoreClass ("ci/land-" ++ rest) false false = .missingRestore := by
  simp [restoreClass, land_prefix_no_save]

/-- A miss on a land leg with the entry on `main` is `keyMiss`. -/
theorem restoreClass_keyMiss (rest : String) :
    restoreClass ("ci/land-" ++ rest) false true = .keyMiss := by
  simp [restoreClass, land_prefix_no_save]

/-- A skipped `engine` job seeds nothing: `main` holds the entry exactly as before. -/
theorem skipped_keeps (holds : Bool) : seedsMain false holds = holds := by simp [seedsMain]

/-- A `main` push that ran `engine` seeds the entry. -/
theorem ran_seeds (holds : Bool) : seedsMain true holds = true := by simp [seedsMain]

/-- Never seeded stays unseeded until an `engine` run: the state the land legs of 2026-10-23 were in. -/
theorem unseeded_stays : seedsMain false false = false := by decide

/-- An entry idle 7 days is evicted, so it needs a reseed. -/
theorem evicted_reseed (holds : Bool) : needsReseed holds evictDays = true := by
  simp [needsReseed, mainHolds, evicted]

/-- An entry idle 6 days is still there, so a seeded `main` needs no reseed. -/
theorem fresh_no_reseed : needsReseed true 6 = false := by decide

/-- Nothing seeded needs a reseed at any age. -/
theorem unseeded_reseed (d : Nat) : needsReseed false d = true := by simp [needsReseed, mainHolds]

/-- One land leg per week keeps the entry alive: a restore resets the idle days, so the entry is evicted only when
the gap between two restores reaches `evictDays`. -/
theorem weekly_restore_keeps (gap : Nat) (h : gap < evictDays) : needsReseed true gap = false := by
  simp [needsReseed, mainHolds, evicted]; omega

/-- A leg of a run: where it ran, whether the restore hit, and whether `main` held the entry then. -/
structure Leg where
  run : Nat
  engine : String
  ref : String
  hit : Bool
  holds : Bool
deriving Repr, DecidableEq

/-- Legs read from runs: three land legs before the seeding (all `missingRestore`) and the `main` push that seeded
(`firstSave`, run 40045796969, cache entries on `refs/heads/main` listed by `gh cache list`). -/
def legs : List Leg := [
  ⟨40024272661, "webkit", "ci/land-hero-copy-floor-followups-cd65384", false, false⟩,
  ⟨40031018930, "webkit", "ci/land-polish-wtname-wire-b1145f3", false, false⟩,
  ⟨40037942688, "webkit", "ci/land-gc-landed-identity-1c3a381", false, false⟩,
  ⟨40045796969, "webkit", "main", false, false⟩,
  ⟨40045796969, "chromium", "main", false, false⟩]

theorem legs_classes : legs.map (fun l => restoreClass l.ref l.hit l.holds) =
    [.missingRestore, .missingRestore, .missingRestore, .firstSave, .firstSave] := by decide

/-- Every combination of a saving ref, a land ref, a hit and the `main` state, one row each. -/
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

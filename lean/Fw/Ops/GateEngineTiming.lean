import Lean
/-!
# Where the gate-engine step spends its time on land legs (task `ci-gate-engine-webkit-slow`)

The composite action `.github/actions/gate-engine` installs the browser one land leg needs. `timing.slow` alerts
named the webkit leg (66 s, 87 s, 70 s against 33 s) and its Post step (43 s against 5 s). Each row below is a
MEASURED sample read from the job log of an existing land run: the step time, the time of its apt sub-step
(`playwright-core install-deps`), the seconds apt reports for its fetches, the time of the Post step, and whether
the cache restores hit. `classify` decides each sample on its own. The note
`research/notes/2026/10-2x-ci-gate-engine-webkit-slow.md` has the sources.
-/
namespace Fw.Ops.GateEngineTiming
open Lean

/-- One engine leg of a land run, read from its job log (seconds). `hit` is true when the apt and browser restores
both hit; `key` is the first 7 characters of the browser cache key. -/
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

/-- The fastest measured step per engine on these runs: the baseline a sample is compared with. -/
def baseTotalS (engine : String) : Nat := if engine == "webkit" then 33 else 23

/-- The smallest Post step measured on these runs. -/
def basePostS : Nat := 4

/-- A sample is slow when it exceeds its baseline by this many seconds. -/
def marginS : Nat := 10

/-- Where a slow gate-engine step spends its excess. `aptVariance`: the apt sub-step carries it (mirror fetch and
apt/dpkg work on the runner; no cache key reaches this time). `other`: the part outside apt is slow too. -/
inductive StepClass | ok | aptVariance | other
deriving Repr, DecidableEq

def StepClass.name : StepClass → String
  | .ok => "ok" | .aptVariance => "aptVariance" | .other => "other"

/-- The part of the step outside the apt sub-step (keys, restores, browser install). -/
def Sample.restS (s : Sample) : Nat := s.totalS - s.aptS

/-- The step class: slow means `baseTotalS + marginS ≤ totalS`; then the excess is apt variance when the part
outside apt stays under the margin on its own. -/
def stepClass (s : Sample) : StepClass :=
  if s.totalS < baseTotalS s.engine + marginS then .ok
  else if s.restS < marginS then .aptVariance else .other

inductive PostClass | ok | fixableSave
deriving Repr, DecidableEq

def PostClass.name : PostClass → String
  | .ok => "ok" | .fixableSave => "fixableSave"

/-- The Post step class: a Post step over the margin on a missed key is the cache save of an entry no later land leg
can read (see `shouldSave`), a fixable cost. -/
def postClass (s : Sample) : PostClass :=
  if basePostS + marginS ≤ s.postS && !s.hit then .fixableSave else .ok

/-- Whether a ref saves the gate-engine caches. A land leg runs on a fresh `ci/land-<task>-<sha>` branch; GitHub
lets a branch read only its own caches and those of the default branch, so an entry saved there is never read. -/
def shouldSave (ref : String) : Bool := !("ci/land-".toList.isPrefixOf ref.toList)

theorem main_saves : shouldSave "main" = true := by decide

theorem land_no_save : shouldSave "ci/land-timing-x-1234567" = false := by decide

theorem land_prefix_no_save (rest : String) : shouldSave ("ci/land-" ++ rest) = false := by
  simp [shouldSave, String.toList_append]

/-- The refs of the golden rows and what each decides. -/
def refCases : List String :=
  ["main", "ci/land-timing-poller-snapshot-727ac77", "ci/gate-fix", "ci/landing", "ci/land-", "feature/land-x"]

/-- The measured samples (job logs of land runs, 2026-10-23). -/
def samples : List Sample := [
  ⟨40024272661, 120656499722, "webkit", 66, 60, 11, 6, false, "969c76e"⟩,
  ⟨40031018930, 120679099577, "webkit", 87, 82, 34, 9, false, "969c76e"⟩,
  ⟨40026269429, 120663290040, "webkit", 70, 65, 43, 43, false, "969c76e"⟩,
  ⟨40028997665, 120672380897, "webkit", 33, 28, 8, 8, false, "969c76e"⟩,
  ⟨40037942688, 120701995647, "webkit", 53, 48, 27, 7, false, "969c76e"⟩,
  ⟨40024272661, 120656499820, "chromium", 42, 37, 6, 5, false, "1a85621"⟩,
  ⟨40028997665, 120672380862, "chromium", 23, 19, 4, 4, false, "1a85621"⟩]

/-- Every sample missed: no land leg reads what an earlier land leg saved. -/
theorem all_miss : samples.all (fun s => !s.hit) = true := by decide

/-- No key churn: within an engine the cache key is one string across runs. -/
theorem key_stable : (samples.filter (·.engine == "webkit")).all (·.key == "969c76e") = true ∧
    (samples.filter (·.engine == "chromium")).all (·.key == "1a85621") = true := by decide

/-- The three alerted webkit samples are apt variance, and the Post step of the third is a fixable save. -/
theorem alerted_webkit :
    (samples.take 3).map stepClass = [.aptVariance, .aptVariance, .aptVariance] ∧
    (samples.take 3).map postClass = [.ok, .ok, .fixableSave] := by decide

/-- The chromium alert is apt variance too. -/
theorem alerted_chromium : (samples.drop 5).map stepClass = [.aptVariance, .ok] := by decide

/-- A step never classed `other` on these rows: every slow sample's excess sits in the apt sub-step. -/
theorem no_other : samples.all (fun s => stepClass s != .other) = true := by decide

/-- After the fix a land ref saves nothing, so its Post step has no save to wait on. -/
theorem fixed_land_has_no_save : ∀ rest, shouldSave ("ci/land-" ++ rest) = false := land_prefix_no_save

def goldenLines : List Json :=
  (samples.map fun s => Json.mkObj [("kind", "sample"), ("run", toJson s.run), ("job", toJson s.job),
      ("engine", Json.str s.engine), ("totalS", toJson s.totalS), ("aptS", toJson s.aptS),
      ("fetchS", toJson s.fetchS), ("postS", toJson s.postS), ("hit", toJson s.hit), ("key", Json.str s.key),
      ("step", Json.str (stepClass s).name), ("post", Json.str (postClass s).name)]) ++
  (refCases.map fun r => Json.mkObj [("kind", "ref"), ("ref", Json.str r), ("save", toJson (shouldSave r))])

def goldenText : String := "\n".intercalate (goldenLines.map Json.compress) ++ "\n"

/-- Regenerate the golden (`gen []`) or check it (`gen ["--check"]`); run from `lean/`. -/
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

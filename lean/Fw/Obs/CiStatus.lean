import Lean.Data.Json
import Fw.Obs.GhStatus
open Lean (Json toJson)
/-!
# CircleCI platform status: may the land router send a Linux Arm job to CircleCI?

The console reads the public CircleCI status page (`https://status.circleci.com/api/v2/summary.json`, an Atlassian
Statuspage: `GET /api/v2/summary.json` returns "a status indicator, component statuses, unresolved incidents"; a
component is "one of operational, degraded_performance, partial_outage, or major_outage" plus `under_maintenance`;
https://status.circleci.com/api, read 2026-10-21; no token). The page sends `cache-control: max-age=10` and documents
no rate limit; the poller reads it at most once per `pollMs`. This module decides from one reading, like
`Fw.Obs.GhStatus` does for GitHub. Nothing here reads a clock: the caller passes `now`.

Components that carry a Linux Arm job (Arm jobs run on the Docker and Machine executors): `Docker Jobs`,
`Machine Jobs`, `Pipelines & Workflows` (a job starts only through a workflow) and `CircleCI API` (the router
triggers through it). A macOS job rests on `macOS Jobs`, `Pipelines & Workflows` and `CircleCI API`. The page has no
Arm-only component (INFERRED from the 2026-10-20 component list); the Arm verdict therefore shares the Docker and
Machine states.

Rules (proved below): `verdictOf_degraded` (a degraded component degrades the verdict), `verdictOf_healthy_iff`
(healthy exactly when every component is operational), `verdictOf_unknown_keeps` and `verdictOf_unknown_fresh` (an
unreadable component keeps a degraded verdict and otherwise leaves it unknown), `usable_iff` (the router input is
true exactly for a healthy, fresh reading), `arm_ignores_macos` (a macOS outage never blocks an Arm job).
-/
namespace Fw.Obs.CiStatus

open Fw.Obs

/-- Milliseconds between two reads of the status page: never faster (gh rate-limit hygiene: polls at least 120 s). -/
def pollMs : Nat := 120000

/-- A reading older than this is stale (three polls); a stale reading is not usable. -/
def maxAgeMs : Nat := 360000

/-- The age limit lies at or above one poll, so a reading from the last poll is always fresh. -/
theorem poll_le_maxAge : pollMs ≤ maxAgeMs := by decide

/-- The verdict about one lane: `healthy` (every component read and operational), `degraded` (a component is not
operational), `unknown` (no component is degraded but one could not be read, and the last verdict was not degraded).
-/
inductive Verdict where
  | healthy | degraded | unknown
deriving DecidableEq, Repr

/-- The wire name of a verdict. -/
def Verdict.name : Verdict → String
  | .healthy => "healthy" | .degraded => "degraded" | .unknown => "unknown"

/-- The verdict of a wire name; a name outside the three is `unknown`. -/
def Verdict.ofName : String → Verdict
  | "healthy" => .healthy | "degraded" => .degraded | _ => .unknown

/-- A name decodes to its verdict. -/
theorem Verdict.ofName_name (v : Verdict) : Verdict.ofName v.name = v := by
  cases v <;> rfl

/-- A component that is read and not operational (the four non-operational statuses count, as in `ghOpenB`). -/
def badB (c : GhComp) : Bool := c != .operational && c != .unknown

/-- **The verdict over the components of a lane**: degraded when one is read and not operational; else, when one is
unreadable, the previous verdict if it was degraded and `unknown` otherwise; else healthy.
-/
def verdictOf (prev : Verdict) (cs : List GhComp) : Verdict :=
  if cs.any badB then .degraded
  else if cs.any (· == .unknown) then (if prev == .degraded then .degraded else .unknown)
  else .healthy

/-- A read, non-operational component degrades the verdict, whatever the others and the previous verdict are. -/
theorem verdictOf_degraded (prev : Verdict) (cs : List GhComp) (c : GhComp) (hc : c ∈ cs)
    (h1 : c ≠ .operational) (h2 : c ≠ .unknown) : verdictOf prev cs = .degraded := by
  have : cs.any badB = true := List.any_eq_true.2 ⟨c, hc, by cases c <;> simp_all [badB]⟩
  simp [verdictOf, this]

/-- The verdict is healthy exactly when every component is operational (so also when the previous verdict was degraded). -/
theorem verdictOf_healthy_iff (prev : Verdict) (cs : List GhComp) :
    verdictOf prev cs = .healthy ↔ ∀ c ∈ cs, c = .operational := by
  constructor
  · intro h c hc
    unfold verdictOf at h
    by_cases h1 : cs.any badB = true
    · simp [h1] at h
    by_cases h2 : cs.any (· == .unknown) = true
    · simp [h1, h2] at h
      split at h <;> cases h
    · have h1' : cs.any badB = false := by simpa using h1
      have h2' : cs.any (· == .unknown) = false := by
        cases hh : cs.any (· == .unknown)
        · rfl
        · exact absurd hh h2
      have a := List.any_eq_false.1 h1' c hc
      have b := List.any_eq_false.1 h2' c hc
      cases c <;> simp_all [badB]
  · intro h
    have h1 : cs.any badB = false := List.any_eq_false.2 fun c hc => by simp [h c hc, badB]
    have h2 : cs.any (· == .unknown) = false := List.any_eq_false.2 fun c hc => by simp [h c hc]
    simp [verdictOf, h1, h2]

/-- An unreadable component with no degraded one keeps a degraded verdict (a failed fetch does not clear it). -/
theorem verdictOf_unknown_keeps (cs : List GhComp) (hb : cs.any badB = false) (hu : cs.any (· == .unknown) = true) :
    verdictOf .degraded cs = .degraded := by
  simp [verdictOf, hb, hu]

/-- An unreadable component with no degraded one, after a verdict that was not degraded, leaves the verdict unknown. -/
theorem verdictOf_unknown_fresh (prev : Verdict) (hp : prev ≠ .degraded) (cs : List GhComp)
    (hb : cs.any badB = false) (hu : cs.any (· == .unknown) = true) : verdictOf prev cs = .unknown := by
  cases prev <;> simp_all [verdictOf]

/-- One reading of the status page: the states of the components that matter, the previous verdicts of the two lanes,
the time of the last successful read (ms; `none` before the first), and the time of the decision.
-/
structure Reading where
  docker    : GhComp := .unknown
  machine   : GhComp := .unknown
  pipelines : GhComp := .unknown
  api       : GhComp := .unknown
  macos     : GhComp := .unknown
  prevArm   : Verdict := .unknown
  prevMac   : Verdict := .unknown
  readAt    : Option Nat := none
  now       : Nat := 0
deriving DecidableEq, Repr

/-- The components a Linux Arm job rests on. -/
def Reading.armComps (r : Reading) : List GhComp := [r.docker, r.machine, r.pipelines, r.api]

/-- The components a macOS job rests on. -/
def Reading.macComps (r : Reading) : List GhComp := [r.macos, r.pipelines, r.api]

/-- The Linux Arm verdict. -/
def Reading.arm (r : Reading) : Verdict := verdictOf r.prevArm r.armComps

/-- The macOS verdict. -/
def Reading.mac (r : Reading) : Verdict := verdictOf r.prevMac r.macComps

/-- The macOS state does not enter the Arm verdict: an Arm job never waits for a macOS outage. -/
theorem arm_ignores_macos (r : Reading) (s : GhComp) : { r with macos := s }.arm = r.arm := rfl

/-- The Docker state does not enter the macOS verdict (the lanes share only `pipelines` and `api`). -/
theorem mac_ignores_docker (r : Reading) (s : GhComp) : { r with docker := s }.mac = r.mac := rfl

/-- A reading is fresh when it was read (`readAt` is set) and is at most `maxAgeMs` old (a time after `now` has age 0). -/
def fresh (readAt : Option Nat) (now : Nat) : Bool :=
  match readAt with
  | none => false
  | some t => decide (now - t ≤ maxAgeMs)

/-- A reading never made is not fresh. -/
theorem fresh_none (now : Nat) : fresh none now = false := rfl

/-- A reading older than the limit is not fresh. -/
theorem fresh_old (t now : Nat) (h : t + maxAgeMs < now) : fresh (some t) now = false := by
  simp only [fresh, decide_eq_false_iff_not]
  unfold maxAgeMs at *
  omega

/-- A reading at most one limit old is fresh. -/
theorem fresh_recent (t now : Nat) (h : now ≤ t + maxAgeMs) : fresh (some t) now = true := by
  simp only [fresh, decide_eq_true_eq]
  unfold maxAgeMs at *
  omega

/-- **The router input**: the lane can take a job when its verdict is healthy and the reading is fresh. -/
def usable (v : Verdict) (readAt : Option Nat) (now : Nat) : Bool := v == .healthy && fresh readAt now

/-- The input is true exactly for a healthy verdict on a fresh reading. -/
theorem usable_iff (v : Verdict) (readAt : Option Nat) (now : Nat) :
    usable v readAt now = true ↔ v = .healthy ∧ fresh readAt now = true := by
  simp [usable]

/-- A degraded or unknown verdict is never usable. -/
theorem usable_not_healthy (v : Verdict) (hv : v ≠ .healthy) (readAt : Option Nat) (now : Nat) :
    usable v readAt now = false := by
  cases v <;> simp_all [usable]

/-- A stale reading is never usable, however healthy it looked. -/
theorem usable_stale (v : Verdict) (readAt : Option Nat) (now : Nat) (h : fresh readAt now = false) :
    usable v readAt now = false := by
  simp [usable, h]

/-- The Arm lane's router input for a reading. -/
def Reading.armUsable (r : Reading) : Bool := usable r.arm r.readAt r.now

/-- The macOS lane's router input for a reading. -/
def Reading.macUsable (r : Reading) : Bool := usable r.mac r.readAt r.now

/-! ## Golden vectors (`packages/contracts/golden/obs/ci-status.jsonl`, checked by `apps/console-api/test/ci-status.test.ts`) -/

/-- Golden cases: name and reading. -/
def cases : List (String × Reading) :=
  let ok : Reading := { docker := .operational, machine := .operational, pipelines := .operational,
                        api := .operational, macos := .operational, prevArm := .healthy, prevMac := .healthy,
                        readAt := some 1000000, now := 1060000 }
  [("all operational: both lanes healthy and usable", ok),
   ("macOS degraded (2026-10-20 incident shape): Arm stays usable, macOS is not", { ok with macos := .degradedPerf }),
   ("Docker Jobs degraded: Arm degraded", { ok with docker := .degradedPerf }),
   ("Machine Jobs partial outage: Arm degraded", { ok with machine := .partialOutage }),
   ("Pipelines major outage: both lanes degraded", { ok with pipelines := .majorOutage }),
   ("API under maintenance: both lanes degraded", { ok with api := .maintenance }),
   ("Docker unreadable after healthy: Arm unknown, not usable", { ok with docker := .unknown }),
   ("Docker unreadable after degraded: Arm stays degraded", { ok with docker := .unknown, prevArm := .degraded }),
   ("a degraded component wins over an unreadable one", { ok with docker := .unknown, machine := .partialOutage }),
   ("recovery: all operational after degraded is healthy", { ok with prevArm := .degraded, prevMac := .degraded }),
   ("never read: unknown, not fresh", ({ readAt := none, now := 5 } : Reading)),
   ("stale reading: healthy but older than the limit, not usable", { ok with now := 1000000 + maxAgeMs + 1 }),
   ("exactly at the age limit: fresh", { ok with now := 1000000 + maxAgeMs }),
   ("reading from the future: age 0, fresh", { ok with readAt := some 2000000 })]

/-- The JSON of a reading. -/
def readingJson (r : Reading) : Json :=
  Json.mkObj [("docker", .str r.docker.name), ("machine", .str r.machine.name), ("pipelines", .str r.pipelines.name),
    ("api", .str r.api.name), ("macos", .str r.macos.name), ("prevArm", .str r.prevArm.name),
    ("prevMac", .str r.prevMac.name), ("readAt", match r.readAt with | none => Json.null | some t => toJson t),
    ("now", toJson r.now)]

/-- The decision of a reading, as JSON. -/
def decisionJson (r : Reading) : Json :=
  Json.mkObj [("arm", Json.mkObj [("verdict", .str r.arm.name), ("usable", toJson r.armUsable)]),
    ("macos", Json.mkObj [("verdict", .str r.mac.name), ("usable", toJson r.macUsable)]),
    ("fresh", toJson (fresh r.readAt r.now))]

/-- The text of the golden file: the constants line, then one line per case. -/
def goldenText : String :=
  (Json.mkObj [("name", .str "constants"), ("kind", .str "consts"), ("pollMs", toJson pollMs),
    ("maxAgeMs", toJson maxAgeMs)]).compress ++ "\n" ++
  String.join (cases.map fun (name, r) =>
    (Json.mkObj [("name", .str name), ("kind", .str "reading"), ("request", readingJson r),
      ("response", decisionJson r)]).compress ++ "\n")

/-- The golden file, relative to `lean/`. -/
def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "obs" / "ci-status.jsonl"

/-- Compare (or with `write`, write) the golden file; returns the number of failures. -/
def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let p := root / goldenPath
  if write then
    IO.FS.writeFile p goldenText
    IO.println s!"ci-status golden: {cases.length} cases, written"
    return 0
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur != goldenText then
    IO.println s!"ci-status golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/ObsGolden.lean)"
    return 1
  IO.println s!"ci-status golden: {cases.length} cases, 0 failures"
  return 0

#guard (cases.map fun (_, r) => r.arm.name) == ["healthy", "healthy", "degraded", "degraded", "degraded", "degraded",
  "unknown", "degraded", "degraded", "healthy", "unknown", "healthy", "healthy", "healthy"]
#guard (cases.map fun (_, r) => r.armUsable) == [true, true, false, false, false, false, false, false, false, true,
  false, false, true, true]
#guard (cases.map fun (_, r) => r.macUsable) == [true, false, true, true, false, false, true, true, true, true,
  false, false, true, true]

end Fw.Obs.CiStatus

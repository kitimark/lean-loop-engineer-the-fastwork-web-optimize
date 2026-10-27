import Lean.Data.Json
import Fw.Ci.Wire

/-! Write (or with `--check`, verify) `packages/contracts/golden/ci/overflow.jsonl`: one line per case,
`{"op", "name", "request", "response"}`, the reply of the ops `ci.overflow`, `ci.overflowCombine` and `ci.overflowSettle` (`Fw.Wire.Ci`, rule in
`Fw.Ci.Overflow`). Consumer: `apps/runner/test/land-overflow.test.ts`, which reads the same ops from fwcore and compares.
Run from `lean/`: `lake env lean --run scripts/OverflowGolden.lean [--check]`. -/

open Lean

/-- The facts of a calm moment: five legs, nothing running on GitHub, CircleCI healthy and read 60 s ago, nothing spent. -/
def base : List (String × Json) := [
  ("legs", .arr (#["check-sh", "suites-a", "suites-b", "chromium", "playwright-webkit"].map Json.str)),
  ("ghActive", .arr #[]), ("ghActions", "operational"), ("ghPrev", false), ("ccArm", "healthy"), ("ccReadAt", 1000000),
  ("now", 1060000), ("spent", 0), ("storage", 0), ("keys", 1), ("checkout", Json.null), ("forceFull", false)]

/-- The calm facts with some fields replaced. -/
def mk (over : List (String × Json)) : Json :=
  Json.mkObj (base.filter (fun kv => !over.any (·.1 == kv.1)) ++ over)

def names (l : List String) : Json := .arr (l.map Json.str).toArray

def overflowCases : List (String × Json) := [
  ("calm: every leg stays on GitHub", mk []),
  ("a full GitHub (gate-gaps runs 29 jobs): every leg goes to CircleCI", mk [("ghActive", names ["gate-gaps"])]),
  ("17 slots used, 3 free: three legs stay, two overflow", mk [("ghActive", names ["engine-premises", "land", "wktr-fixtures"])]),
  ("the slot count is unknown: GitHub first", mk [("ghActive", .null), ("ccArm", "degraded")]),
  ("a workflow with no width row counts four", mk [("ghActive", names ["no-such-workflow"])]),
  ("four unlisted workflows count 16: 4 free, four legs stay", mk [("ghActive", names ["no-such-workflow", "no-such-workflow", "no-such-workflow", "no-such-workflow"])]),
  ("the land workflow alone (5 slots): all legs stay", mk [("ghActive", names ["land"])]),
  ("twenty slots used: none free", mk [("ghActive", names ["engine-premises", "snapshot-extract", "sim-speed", "lean"])]),
  ("nineteen used, one free: one leg stays", mk [("ghActive", names ["engine-premises", "snapshot-extract", "sim-speed"])]),
  ("more runs than slots (26): none free", mk [("ghActive", names ["breakpoint-gate", "engine-premises", "snapshot-extract", "wktr"])]),
  ("one chromium-counts run (up to 2 x 10 matrix jobs) fills GitHub", mk [("ghActive", names ["chromium-counts"])]),
  ("one visual-diff run (up to 2 x 16 shards) fills GitHub", mk [("ghActive", names ["visual-diff"])]),
  ("one breakpoint-gate run (12 jobs): 8 free, all legs stay", mk [("ghActive", names ["breakpoint-gate"])]),
  ("the test flag marks GitHub full", mk [("forceFull", true)]),
  ("Actions degraded: every leg to CircleCI", mk [("ghActions", "partial_outage")]),
  ("Actions status unreadable, last decision degraded", mk [("ghActions", "unknown"), ("ghPrev", true)]),
  ("Actions status unreadable, last decision clear", mk [("ghActions", "unknown"), ("ghPrev", false)]),
  ("Actions under maintenance", mk [("ghActions", "under_maintenance")]),
  ("GitHub full, CircleCI degraded: stay on GitHub", mk [("forceFull", true), ("ccArm", "degraded")]),
  ("GitHub full, CircleCI status unknown: stay on GitHub", mk [("forceFull", true), ("ccArm", "unknown")]),
  ("GitHub full, CircleCI status stale: stay on GitHub", mk [("forceFull", true), ("ccReadAt", 600000)]),
  ("GitHub full, CircleCI status at the age limit: overflow", mk [("forceFull", true), ("ccReadAt", 700000)]),
  ("GitHub full, CircleCI status never read: stay on GitHub", mk [("forceFull", true), ("ccReadAt", .null)]),
  ("GitHub full, credits spent to the reserve: stay on GitHub", mk [("forceFull", true), ("spent", 330000)]),
  ("GitHub full, credits just fit", mk [("forceFull", true), ("spent", 319000)]),
  ("GitHub full, storage 1001 (over the old stop): overflow, the overage is in the budget", mk [("forceFull", true), ("storage", 1001)]),
  ("GitHub full, storage plus the own save at the allowance: overflow", mk [("forceFull", true), ("storage", 1765)]),
  ("GitHub full, credits fit only without storage: stay on GitHub", mk [("forceFull", true), ("spent", 319550), ("storage", 3765)]),
  ("GitHub full, the same spend with storage at the allowance: overflow", mk [("forceFull", true), ("spent", 319550), ("storage", 1765)]),
  ("GitHub full, storage overage alone past the pool: stay on GitHub", mk [("forceFull", true), ("storage", 1000000)]),
  ("2026-10-21 21:21:46, ledger totals at retention (650), Actions degraded, slots full: every leg to CircleCI",
    mk [("ghActive", names ["webkit-sim", "webkit-sim", "visual-diff", "path-pix"]), ("ghActions", "degraded_performance"),
      ("ccReadAt", (1792592446000 : Nat)), ("now", (1792592506000 : Nat)), ("spent", (819 : Nat)),
      ("storage", (Fw.Ci.Provider.storageNow [Fw.Ci.Provider.ledger20261021] 1792592506000 : Nat))]),
  ("the same land at the old 30-day reading (1297): every leg to CircleCI",
    mk [("ghActive", names ["webkit-sim", "webkit-sim", "visual-diff", "path-pix"]), ("ghActions", "degraded_performance"),
      ("ccReadAt", (1792592446000 : Nat)), ("now", (1792592506000 : Nat)), ("spent", (819 : Nat)), ("storage", (1297 : Nat))]),
  ("GitHub full, no checkout key: stay on GitHub", mk [("forceFull", true), ("keys", 0)]),
  ("GitHub full, key list unreadable and no clone result: stay on GitHub", mk [("forceFull", true), ("keys", .null)]),
  ("GitHub full, key list unreadable but the clone worked: overflow", mk [("forceFull", true), ("keys", .null), ("checkout", true)]),
  ("GitHub full, key list unreadable and the clone failed: stay on GitHub", mk [("forceFull", true), ("keys", .null), ("checkout", false)]),
  ("one leg, GitHub full", mk [("legs", names ["check-sh"]), ("forceFull", true)]),
  ("no leg", mk [("legs", names []), ("forceFull", true)]),
  ("an unknown leg is an error", mk [("legs", names ["no-such-leg"])])]

def combineCases : List (String × List String) := [
  ("no verdict", []),
  ("one accept", ["accept"]),
  ("two accepts", ["accept", "accept"]),
  ("accept and wait", ["accept", "wait"]),
  ("accept and refuse", ["accept", "refuse"]),
  ("wait and local", ["wait", "local"]),
  ("local and refuse", ["local", "refuse"]),
  ("try and accept", ["try", "accept"]),
  ("wait and try", ["wait", "try"])]

/-- The settle cases: `gh` and `cc` as the plan gave them, and whether CircleCI started. -/
def settleCases : List (String × List String × List String × Bool) := [
  ("CircleCI started: nothing changes", ["check-sh", "suites-a", "suites-b"], ["chromium", "playwright-webkit"], true),
  ("CircleCI failed to start: its legs re-dispatch on GitHub", ["check-sh", "suites-a", "suites-b"], ["chromium", "playwright-webkit"], false),
  ("CircleCI failed to start and GitHub had no leg: all legs re-dispatch", [], ["check-sh", "suites-a", "suites-b", "chromium", "playwright-webkit"], false),
  ("no leg on CircleCI: nothing to re-dispatch", ["check-sh", "suites-a", "suites-b", "chromium", "playwright-webkit"], [], false),
  ("a start that did not fail leaves a CircleCI-only plan alone", [], ["check-sh", "suites-a", "suites-b", "chromium", "playwright-webkit"], true)]

def line (op name : String) (request response : Json) : String :=
  (Json.mkObj [("op", .str op), ("name", .str name), ("request", request), ("response", response)]).compress ++ "\n"

def reply (op : String) (req : Json) : Json :=
  match Fw.Wire.Ci.handle op req with
  | some (.ok f) => Json.mkObj f
  | some (.error e) => Json.mkObj [("error", .str e)]
  | none => Json.mkObj [("error", .str "unknown op")]

def text : String :=
  String.join (overflowCases.map fun (n, r) => line "ci.overflow" n r (reply "ci.overflow" r))
    ++ String.join (combineCases.map fun (n, ks) =>
      let r := Json.mkObj [("kinds", names ks)]
      line "ci.overflowCombine" n r (reply "ci.overflowCombine" r))
    ++ String.join (settleCases.map fun (n, gh, cc, st) =>
      let r := Json.mkObj [("gh", names gh), ("cc", names cc), ("ccStarted", .bool st)]
      line "ci.overflowSettle" n r (reply "ci.overflowSettle" r))

def main (args : List String) : IO UInt32 := do
  let p : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ci" / "overflow.jsonl"
  let n := (text.splitOn "\n").length - 1
  if args.contains "--check" then
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != text then
      IO.println s!"overflow golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/OverflowGolden.lean)"
      return 1
    IO.println s!"overflow golden: {n} lines, up to date"
    return 0
  IO.FS.writeFile p text
  IO.println s!"overflow golden: {n} lines written"
  return 0

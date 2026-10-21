import Lean.Data.Json
import Fw.Ci.Pool.FallbackWire

/-! Write (`--check`: verify) `packages/contracts/golden/ci/pool-fallback.jsonl`, rows `{op, name, request, response}` of
`ci.poolRoute` and `ci.poolConsts`; consumer `apps/runner/test/ci-pool.test.ts`. -/

open Lean

def sha : String := "0123456789abcdef0123456789abcdef01234567"
def cfgD : String := "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"

/-- A request for `lane` with the fields of `over` added or replaced. -/
def rq (lane : String) (rep : Nat := 0) (over : List (String × Json) := []) : Json :=
  let base : List (String × Json) := [("sha", sha), ("lane", lane), ("cfg", cfgD), ("rep", rep),
    ("engine", "wktrIosSim"), ("image", "macos-26")]
  Json.mkObj (base.filter (fun kv => !over.any (·.1 == kv.1)) ++ over)

/-- A slot state. -/
def st (mac total : Nat) (rem : Json := .arr #[]) (over : List (String × Json) := []) : Json :=
  Json.mkObj ([("ghMacBusy", toJson mac), ("ghTotalBusy", toJson total), ("ghRemainingS", rem),
    ("circleCreditsLeft", (30000 : Nat))] ++ over)

def nums (l : List Nat) : Json := .arr (l.map toJson).toArray

/-- Fallback allowlists: wktr on CircleCI, wktr-fixtures on Bitrise, trajectory-probe on Linux WPE. -/
def demo : Json := Json.mkObj [("circleMacAllow", .arr #["wktr"]), ("circleCaps", Json.mkObj [("wktr", (5 : Nat))]),
  ("bitriseOn", true), ("bitriseAllow", .arr #["wktr-fixtures"]), ("wpeTolerant", .arr #["trajectory-probe"])]

def route (cfg : String) (over : Option Json) (s : Json) (reqs : List Json) : Json :=
  Json.mkObj ([("cfg", (cfg : Json))] ++ (match over with | some o => [("over", o)] | none => []) ++
    [("state", s), ("reqs", .arr reqs.toArray)])

def routeCases : List (String × Json) := [
  ("a free slot: GitHub", route "phase1" none (st 0 0) [rq "wktr"]),
  ("six requests, five slots, nothing known about remaining time: five run, one waits",
    route "phase1" none (st 0 0 .null) ((List.range 6).map (rq "wktr" ·))),
  ("six requests, five slots, a slot frees in 300 s: six run on GitHub, the sixth queued",
    route "phase1" none (st 0 0 (nums [300])) ((List.range 6).map (rq "wktr" ·))),
  ("slots full, the next frees in 1199 s: GitHub", route "phase1" none (st 5 5 (nums [1199, 3000])) [rq "wktr"]),
  ("slots full, the next frees in 1200 s: wait", route "phase1" none (st 5 5 (nums [1200])) [rq "wktr"]),
  ("slots full, remaining time unknown: wait", route "phase1" none (st 5 5 .null) [rq "wktr"]),
  ("total jobs at 20, macOS free: wait", route "phase1" none (st 0 20 (nums [10])) [rq "wktr"]),
  ("GitHub degraded: wait", route "phase1" none (st 0 0 (over := [("ghDegraded", true)])) [rq "wktr"]),
  ("a newer push is the tip: stale", route "phase1" none (st 0 0) [rq "wktr" 0 [("current", false)]]),
  ("held 2 h: notRun", route "phase1" none (st 5 5 .null) [rq "wktr" 0 [("ageS", (7200 : Nat))]]),
  ("held 7199 s: wait", route "phase1" none (st 5 5 .null) [rq "wktr" 0 [("ageS", (7199 : Nat))]]),
  ("enterprise: 50 macOS slots", route "enterprise" none (st 49 49 .null) [rq "wktr", rq "wktr" 1]),
  ("CircleCI for an allowlisted lane, charged at the 8 min timeout",
    route "phase1" (some demo) (st 5 5 .null) [rq "wktr", rq "wktr" 1]),
  ("CircleCI credits short: wait",
    route "phase1" (some demo) (st 5 5 .null [("circleCreditsLeft", (1599 : Nat))]) [rq "wktr"]),
  ("Bitrise for an allowlisted lane", route "phase1" (some demo) (st 5 5 .null) [rq "wktr-fixtures"]),
  ("Bitrise off: wait",
    route "phase1" (some (Json.mkObj [("bitriseAllow", .arr #["wktr-fixtures"])])) (st 5 5 .null) [rq "wktr-fixtures"]),
  ("a WPE-tolerant lane on Linux", route "phase1" (some demo) (st 5 5 .null) [rq "trajectory-probe"]),
  ("gate-gaps never leaves GitHub macOS",
    route "phase1" (some (Json.mkObj [("wpeTolerant", .arr #["gate-gaps"])])) (st 5 5 .null) [rq "gate-gaps"]),
  ("an explicit cap", route "phase1" none (st 0 0) [rq "webkit-sim" 0 [("capMin", (30 : Nat))]]),
  ("an unknown lane without capMin is an error", route "phase1" none (st 0 0) [rq "webkit-sim"]),
  ("an invalid key is an error", route "phase1" none (st 0 0) [rq "wktr" 0 [("sha", "0123")]])]

def line (op name : String) (request response : Json) : String :=
  (Json.mkObj [("op", .str op), ("name", .str name), ("request", request), ("response", response)]).compress ++ "\n"

def reply (op : String) (req : Json) : Json :=
  match Fw.Wire.CiPool.handle op req with
  | some (.ok f) => Json.mkObj f
  | some (.error e) => Json.mkObj [("error", .str e)]
  | none => Json.mkObj [("error", .str "unknown op")]

def text : String :=
  String.join (routeCases.map fun (n, r) => line "ci.poolRoute" n r (reply "ci.poolRoute" r))
    ++ String.join ([("phase1", "phase1"), ("enterprise", "enterprise")].map fun (n, c) =>
      let r := Json.mkObj [("cfg", (c : Json))]
      line "ci.poolConsts" n r (reply "ci.poolConsts" r))

def main (args : List String) : IO UInt32 := do
  let p : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ci" / "pool-fallback.jsonl"
  let n := (text.splitOn "\n").length - 1
  if args.contains "--check" then
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != text then
      IO.println s!"pool-fallback golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/PoolFallbackGolden.lean)"
      return 1
    IO.println s!"pool-fallback golden: {n} lines, up to date"
    return 0
  IO.FS.writeFile p text
  IO.println s!"pool-fallback golden: {n} lines written"
  return 0

import Lean.Data.Json
import Fw.Ci.PoolTierWire

open Lean

def sha : String := "0123456789abcdef0123456789abcdef01234567"
def cfgD : String := "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"

def rq (rep : Nat := 0) (over : List (String × Json) := []) : Json :=
  let base : List (String × Json) := [("sha", sha), ("lane", "webkit-sim"), ("cfg", cfgD), ("rep", rep),
    ("engine", "iosSimSafari"), ("image", "xcode-27"), ("capMin", (40 : Nat))]
  Json.mkObj (base.filter (fun kv => !over.any (·.1 == kv.1)) ++ over)

def st (mac cmUsed ccSpent : Nat) (over : List (String × Json) := []) : Json :=
  Json.mkObj ([("ghMacBusy", toJson mac), ("ghTotalBusy", toJson mac), ("ghRemainingS", .null), ("cmUsed", toJson cmUsed),
    ("ccSpent", toJson ccSpent), ("ccStorage", (30 : Nat))] ++ over)

def tier (s : Json) (reqs : List Json) (over : Option Json := none) : Json :=
  Json.mkObj ((match over with | some o => [("over", o)] | none => []) ++ [("state", s), ("reqs", .arr reqs.toArray)])

def reps (n : Nat) : List Json := (List.range n).map (rq ·)

def tierCases : List (String × Json) := [
  ("seven requests, all idle: GitHub 5, Codemagic 1, CircleCI 1", tier (st 0 46 3575) (reps 7)),
  ("eight requests: the eighth waits", tier (st 0 46 3575) (reps 8)),
  ("GitHub full: Codemagic first", tier (st 5 46 3575) [rq]),
  ("GitHub full, Codemagic busy: CircleCI", tier (st 5 46 3575 [("cmBusy", (1 : Nat))]) [rq]),
  ("Codemagic at 361 used: one more 40 min build passes the 400 min line, CircleCI takes it", tier (st 5 361 3575) [rq]),
  ("Codemagic at 360 used: exactly the line, Codemagic", tier (st 5 360 3575) [rq]),
  ("CircleCI at 15401 spent: 8600 more passes the reserve line, wait", tier (st 5 46 15401 [("cmBusy", (1 : Nat))]) [rq]),
  ("CircleCI at 15400 spent: exactly the reserve line, CircleCI", tier (st 5 46 15400 [("cmBusy", (1 : Nat))]) [rq]),
  ("CircleCI storage 1297, within the allowance: CircleCI", tier (st 5 46 3575 [("cmBusy", (1 : Nat)), ("ccStorage", (1297 : Nat))]) [rq]),
  ("CircleCI at 15400 spent, storage at the allowance: CircleCI", tier (st 5 46 15400 [("cmBusy", (1 : Nat)), ("ccStorage", (2000 : Nat))]) [rq]),
  ("CircleCI at 15400 spent, storage 2001: the overage credit passes the reserve line, wait", tier (st 5 46 15400 [("cmBusy", (1 : Nat)), ("ccStorage", (2001 : Nat))]) [rq]),
  ("a slot frees in 300 s: GitHub queue before Codemagic", tier (st 5 46 3575 [("ghRemainingS", .arr #[(300 : Nat)])]) [rq]),
  ("GitHub degraded: Codemagic", tier (st 0 46 3575 [("ghDegraded", true)]) [rq]),
  ("a request over the Codemagic cap goes to CircleCI", tier (st 5 46 3575) [rq 0 [("capMin", (41 : Nat))]]),
  ("gate-gaps never leaves GitHub", tier (st 5 46 3575) [rq 0 [("lane", "gate-gaps")]]),
  ("a lane outside both allowlists waits", tier (st 5 46 3575) [rq 0 [("lane", "wktr")]]),
  ("a newer push is the tip: stale", tier (st 5 46 3575) [rq 0 [("current", false)]]),
  ("Codemagic off", tier (st 5 46 3575) [rq] (some (Json.mkObj [("cmOn", false)]))),
  ("Bitrise off by default: never", tier (st 5 46 3575 [("cmBusy", (1 : Nat)), ("circleBusy", (1 : Nat))]) [rq]
    (some (Json.mkObj [("bitriseAllow", .arr #["webkit-sim"])])))]

def line (op name : String) (request response : Json) : String :=
  (Json.mkObj [("op", .str op), ("name", .str name), ("request", request), ("response", response)]).compress ++ "\n"

def reply (op : String) (req : Json) : Json :=
  match Fw.Wire.CiPoolTier.handle op req with
  | some (.ok f) => Json.mkObj f
  | some (.error e) => Json.mkObj [("error", .str e)]
  | none => Json.mkObj [("error", .str "unknown op")]

def text : String :=
  String.join (tierCases.map fun (n, r) => line "ci.poolTier" n r (reply "ci.poolTier" r))
    ++ line "ci.poolTierConsts" "pool7" (Json.mkObj []) (reply "ci.poolTierConsts" (Json.mkObj []))

def main (args : List String) : IO UInt32 := do
  let p : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ci" / "pool-tier.jsonl"
  let n := (text.splitOn "\n").length - 1
  if args.contains "--check" then
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != text then
      IO.println s!"pool-tier golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/PoolGolden.lean)"
      return 1
    IO.println s!"pool-tier golden: {n} lines, up to date"
    return 0
  IO.FS.writeFile p text
  IO.println s!"pool-tier golden: {n} lines written"
  return 0

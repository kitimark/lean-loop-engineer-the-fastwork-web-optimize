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
  ("rewrite lane, GitHub full: Codemagic builds the site itself", tier (st 5 46 3575) [rq 0 [("lane", "webkit-sim-rewrite")]]),
  ("GitHub degraded: Codemagic", tier (st 0 46 3575 [("ghDegraded", true)]) [rq]),
  ("a request over the Codemagic cap goes to CircleCI", tier (st 5 46 3575) [rq 0 [("capMin", (41 : Nat))]]),
  ("gate-gaps never leaves GitHub", tier (st 5 46 3575) [rq 0 [("lane", "gate-gaps")]]),
  ("a lane outside both allowlists waits", tier (st 5 46 3575) [rq 0 [("lane", "wktr")]]),
  ("a newer push is the tip: stale", tier (st 5 46 3575) [rq 0 [("current", false)]]),
  ("Codemagic off", tier (st 5 46 3575) [rq] (some (Json.mkObj [("cmOn", false)]))),
  ("Bitrise off by default: never", tier (st 5 46 3575 [("cmBusy", (1 : Nat)), ("circleBusy", (1 : Nat))]) [rq]
    (some (Json.mkObj [("bitriseAllow", .arr #["webkit-sim"])])))]

def cellCases : List (String × Json) := [
  ("original: routable, no digest needed", Json.mkObj [("target", "original")]),
  ("rewrite, equal digests: filed", Json.mkObj [("target", "rewrite"), ("ghDigest", "ab12"), ("cmDigest", "ab12")]),
  ("rewrite, different digests: refused", Json.mkObj [("target", "rewrite"), ("ghDigest", "ab12"), ("cmDigest", "cd34")]),
  ("rewrite, no Codemagic digest: refused", Json.mkObj [("target", "rewrite"), ("ghDigest", "ab12")]),
  ("rewrite, no GitHub digest: refused", Json.mkObj [("target", "rewrite"), ("cmDigest", "ab12")]),
  ("rewrite, empty digests: refused", Json.mkObj [("target", "rewrite"), ("ghDigest", ""), ("cmDigest", "")]),
  ("both: not routable", Json.mkObj [("target", "both")])]

def hwj (c m : Nat) : List (String × Json) := [("cpus", toJson c), ("memsize", toJson m)]

def pk (m x r : String) (c : Nat := 3) (mem : Nat := 7516192768) : Json :=
  Json.mkObj ([("macosBuild", Json.str m), ("xcodeBuild", Json.str x), ("runtimeBuild", Json.str r)] ++ hwj c mem)

def ghK : Json := pk "26A434" "27A9275" "24A434"
def cmK : Json := pk "26A434" "27A9275" "24A434" 8 12884901888

def mergedCases : List (String × Json) := [
  ("round-2 pair: macOS and Xcode differ, refused",
    Json.mkObj [("ref", ghK), ("cell", pk "26A428" "27A266a" "24A434")]),
  ("pinned pair, same hardware: all components equal, merged",
    Json.mkObj [("ref", ghK), ("cell", ghK)]),
  ("measured pair: toolchain equal, 3 vs 8 cpus, refused",
    Json.mkObj [("ref", ghK), ("cell", cmK)]),
  ("memory differs, refused",
    Json.mkObj [("ref", ghK), ("cell", pk "26A434" "27A9275" "24A434" 3 12884901888)]),
  ("memory not read, refused",
    Json.mkObj [("ref", ghK), ("cell", pk "26A434" "27A9275" "24A434" 3 0)]),
  ("missing runtime: refused",
    Json.mkObj [("ref", ghK), ("cell", pk "26A434" "27A9275" "")]),
  ("runtime differs: refused",
    Json.mkObj [("ref", ghK), ("cell", pk "26A434" "27A9275" "24A94425")]),
  ("both sides empty: refused",
    Json.mkObj [("ref", pk "" "" "" 0 0), ("cell", pk "" "" "" 0 0)])]

def ob (g c : String) (gk : Json := ghK) (ck : Json := cmK) : Json :=
  Json.mkObj [("gh", g), ("cm", c), ("ghKey", gk), ("cmKey", ck)]

def rw (n : String) (obs : List Json) : Json := Json.mkObj [("row", n), ("obs", .arr obs.toArray)]

def rowsReq (ref cell : Json) (rows : List Json) (used : Nat := 166) : Json :=
  Json.mkObj [("ref", ref), ("cell", cell), ("used", toJson used), ("rows", .arr rows.toArray)]

def rowsCases : List (String × Json) := [
  ("3 pairs agree, other hardware: paired, class is the weakest seen",
    rowsReq ghK cmK [rw "scroll|Layout|total" [ob "stable" "stable", ob "stable" "stable", ob "deterministic" "deterministic"],
      rw "census|layerCount|per state" [ob "deterministic" "deterministic", ob "deterministic" "deterministic", ob "deterministic" "deterministic"]]),
  ("only 2 pairs: refused", rowsReq ghK cmK [rw "scroll|Layout|total" [ob "stable" "stable", ob "stable" "stable"]]),
  ("no pairs: refused", rowsReq ghK cmK [rw "scroll|Layout|total" []]),
  ("one pair disagrees: that row refused, the next row decided on its own",
    rowsReq ghK cmK [rw "scroll|Composite|total" [ob "stable" "deterministic", ob "stable" "stable", ob "stable" "stable"],
      rw "scroll|Paint|total" [ob "stable" "stable", ob "stable" "stable", ob "stable" "stable"]]),
  ("a pair measured other hardware than the cell now: refused",
    rowsReq ghK cmK [rw "scroll|Paint|total" [ob "stable" "stable", ob "stable" "stable", ob "stable" "stable" ghK ghK]]),
  ("keys equal: direct, no pairs needed", rowsReq ghK ghK [rw "scroll|Paint|total" []]),
  ("quarantined on both sides in every pair: paired as quarantined",
    rowsReq ghK cmK [rw "scroll|Paint|total" [ob "quarantined" "quarantined", ob "quarantined" "quarantined", ob "quarantined" "quarantined"]]),
  ("budget short: 281 minutes used, 2 pairs reachable", rowsReq ghK cmK [] 281),
  ("budget gone: 361 minutes used, 0 pairs reachable", rowsReq ghK cmK [] 361),
  ("unknown class word: error", rowsReq ghK cmK [rw "x" [ob "flaky" "stable"]])]

def qd (rep : Nat) (age : Nat) (over : List (String × Json) := []) (cells : Nat := 1) : Json :=
  (rq rep over).mergeObj (Json.mkObj [("queuedS", toJson age), ("runCells", toJson cells)])

def rerouteCases : List (String × Json) := [
  ("GitHub full, one job queued 300 s: Codemagic takes it", Json.mkObj [("state", st 5 166 3575), ("queued", .arr #[qd 0 300])]),
  ("queued 299 s: stays on GitHub", Json.mkObj [("state", st 5 166 3575), ("queued", .arr #[qd 0 299])]),
  ("GitHub has a free slot: stays", Json.mkObj [("state", st 4 166 3575), ("queued", .arr #[qd 0 900])]),
  ("two aged jobs, one Codemagic slot: first moves, second stays", Json.mkObj [("state", st 5 166 3575), ("queued", .arr #[qd 0 400, qd 1 400])]),
  ("Codemagic at 361 used: stays", Json.mkObj [("state", st 5 361 3575), ("queued", .arr #[qd 0 400])]),
  ("Codemagic busy: stays", Json.mkObj [("state", st 5 166 3575 [("cmBusy", (1 : Nat))]), ("queued", .arr #[qd 0 400])]),
  ("gate-gaps never leaves GitHub", Json.mkObj [("state", st 5 166 3575), ("queued", .arr #[qd 0 900 [("lane", "gate-gaps")]])]),
  ("the run has another unfinished cell: stays, cancelling would lose it", Json.mkObj [("state", st 5 166 3575), ("queued", .arr #[qd 0 900 [] 2])]),
  ("a newer push is the tip: stays", Json.mkObj [("state", st 5 166 3575), ("queued", .arr #[qd 0 900 [("current", false)]])])]

def line (op name : String) (request response : Json) : String :=
  (Json.mkObj [("op", .str op), ("name", .str name), ("request", request), ("response", response)]).compress ++ "\n"

def reply (op : String) (req : Json) : Json :=
  match Fw.Wire.CiPoolTier.handle op req with
  | some (.ok f) => Json.mkObj f
  | some (.error e) => Json.mkObj [("error", .str e)]
  | none => Json.mkObj [("error", .str "unknown op")]

def text : String :=
  String.join (tierCases.map fun (n, r) => line "ci.poolTier" n r (reply "ci.poolTier" r))
    ++ String.join (cellCases.map fun (n, r) => line "ci.poolCell" n r (reply "ci.poolCell" r))
    ++ String.join (mergedCases.map fun (n, r) => line "ci.cellMerged" n r (reply "ci.cellMerged" r))
    ++ String.join (rowsCases.map fun (n, r) => line "ci.poolRows" n r (reply "ci.poolRows" r))
    ++ String.join (rerouteCases.map fun (n, r) => line "ci.reroute" n r (reply "ci.reroute" r))
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

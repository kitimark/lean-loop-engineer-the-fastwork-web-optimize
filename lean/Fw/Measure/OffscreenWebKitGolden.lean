import Lean.Data.Json
import Fw.Measure.OffscreenWebKit

namespace Fw.Measure.OffscreenWebKitGolden
open Fw.Measure.OffscreenWebKit Fw.Measure.Offscreen Lean

def mk (endY : Nat) (over : List (Nat × Nat)) (bump : Nat := 0) (vm : Nat := 1) : Pass :=
  let ys := (List.range 15).map (fun i => 4500 + 50 * i) ++ [endY]
  { vm, ys, rows := ys.mapIdx fun i _ => (List.range 12).map fun k =>
      (over.lookup k).getD (k + 1) + (if k == 2 && i == 0 then bump else 0) }

def three (over : List (Nat × Nat)) (bumps : List Nat := [0, 1, 2]) : List Pass :=
  [mk 5231 over (bumps.getD 0 0) 1, mk 5231 over (bumps.getD 1 0) 2, mk 5267 over (bumps.getD 2 0) 3]

def onVms (vms : List Nat) (over : List (Nat × Nat)) : List Pass :=
  vms.mapIdx fun i vm => mk (if i % 2 == 0 then 5231 else 5267) over i vm

def passJson (p : Pass) : Json :=
  Json.mkObj [("vm", toJson p.vm), ("ys", toJson p.ys), ("rows", toJson p.rows)]

def passesJson (ps : List Pass) : Json := Json.arr (ps.toArray.map passJson)

def verdictName : Verdict → String
  | .gain => "gain"
  | .noGain => "noGain"
  | .noData => "noData"

def verdictCases (_ : Unit := ()) : List (String × Nat × Nat × List Pass × List Pass) := [
  ("flag far below on Paint", 4500, 5200, three [(2, 40)], three [(2, 4)]),
  ("equal arms", 4500, 5200, three [(2, 40)], three [(2, 40)]),
  ("Paint down but Layout up", 4500, 5200, three [(2, 40)], three [(2, 4), (1, 9)]),
  ("ObserverCallback up only", 4500, 5200, three [], three [(7, 9)]),
  ("jitter overlaps the base", 4500, 5200, three [] [0, 2, 4], three [] [1, 3, 5]),
  ("window reaching the end: step sets differ", 4500, 5300, three [(2, 40)], three [(2, 4)]),
  ("one pass short", 4500, 5200, (three [(2, 40)]).take 2, three [(2, 4)]),
  ("empty window", 6000, 6100, three [(2, 40)], three [(2, 4)]),
  ("unshaped pass", 4500, 5200, three [(2, 40)], (three [(2, 4)]).take 2 ++ [{ mk 5231 [] 0 3 with rows := [[1]] }]),
  ("first zone only", 4500, 4950, three [(2, 40)], three [(2, 4)]),
  ("flag four passes from two VMs", 4500, 5200, three [(2, 40)], onVms [1, 1, 2, 2] [(2, 4)]),
  ("base four passes from two VMs", 4500, 5200, onVms [1, 1, 2, 2] [(2, 40)], three [(2, 4)]),
  ("three passes on one VM", 4500, 5200, three [(2, 40)], onVms [1, 1, 1] [(2, 4)]),
  ("six passes from three VMs", 4500, 5200, onVms [1, 1, 2, 2, 3, 3] [(2, 40)], onVms [4, 4, 5, 5, 6, 6] [(2, 4)]),
  ("two VMs, equal arms", 4500, 5200, three [(2, 40)], onVms [1, 1, 2, 2] [(2, 40)])]

def shifted : List Pass :=
  let p := mk 5231 [(2, 4)]
  [{ p with vm := 1 }, { p with vm := 2 }, { p with vm := 3, ys := p.ys.map (· + 25) }]

def goldenLines (_ : Unit := ()) : List String :=
  let consts := (Json.mkObj [("op", "constants"), ("keys", toJson wkKeys), ("endCut", toJson endCut), ("minRuns", toJson minRuns), ("minVms", toJson minVms),
    ("slack", toJson slack),
    ("zones", Json.arr (zones.toArray.map fun z => Json.mkObj [("name", z.name), ("lo", toJson z.lo), ("hi", toJson z.hi)]))]).compress
  let ws := [(4500, 4950), (5000, 5200), (0, 5200), (4500, 5300)].map fun (lo, hi) =>
    let p := mk 5267 [] 3
    (Json.mkObj [("op", "window"), ("lo", toJson lo), ("hi", toJson hi), ("pass", passJson p),
      ("steps", toJson (windowSteps lo hi p)),
      ("vec", Json.mkObj [("n", toJson (windowVec lo hi p).n),
        ("vals", Json.mkObj ((windowVec lo hi p).vals.map fun (k, x) => (k, toJson x)))])]).compress
  let vs := verdictCases.map fun (name, lo, hi, b, f) =>
    (Json.mkObj [("op", "verdict"), ("case", Json.str name), ("lo", toJson lo), ("hi", toJson hi), ("base", passesJson b),
      ("flag", passesJson f), ("sameSteps", .bool (sameSteps lo hi (b ++ f))),
      ("vms", toJson [vmCount b, vmCount f]), ("undecided", .bool (undecided b f)),
      ("passVerdict", Json.str (verdictName (passVerdict lo hi b f))),
      ("verdict", Json.str (verdictName (verdict lo hi b f)))]).compress
  let sh := (Json.mkObj [("op", "verdict"), ("case", "same count, different steps"), ("lo", toJson 4500), ("hi", toJson 5200),
    ("base", passesJson (three [(2, 40)])), ("flag", passesJson shifted),
    ("sameSteps", .bool (sameSteps 4500 5200 (three [(2, 40)] ++ shifted))),
    ("vms", toJson [vmCount (three [(2, 40)]), vmCount shifted]), ("undecided", .bool (undecided (three [(2, 40)]) shifted)),
    ("passVerdict", Json.str (verdictName (passVerdict 4500 5200 (three [(2, 40)]) shifted))),
    ("verdict", Json.str (verdictName (verdict 4500 5200 (three [(2, 40)]) shifted)))]).compress
  let zs := [("Paint down, every zone gains", three [(2, 40)], three [(2, 4)]),
    ("jitter only: no zone gains", three [] [0, 2, 4], three [] [1, 3, 5]),
    ("pass ending at 5231 or 5267 stays comparable", [mk 5231 [] 0 1, mk 5231 [] 0 2, mk 5267 [] 0 3],
      [mk 5231 [(3, 0)] 0 1, mk 5267 [(3, 0)] 0 2, mk 5231 [(3, 0)] 0 3]),
    ("Paint down on two flag VMs: every zone undecided", three [(2, 40)], onVms [1, 1, 2, 2] [(2, 4)])].map fun (name, b, f) =>
    (Json.mkObj [("op", "zones"), ("case", Json.str name), ("base", passesJson b), ("flag", passesJson f),
      ("vms", toJson [vmCount b, vmCount f]), ("undecided", .bool (undecided b f)),
      ("zones", Json.arr ((zoneVerdicts b f).toArray.map fun (z, v) =>
        Json.mkObj [("zone", Json.str z), ("verdict", Json.str (verdictName v))]))]).compress
  [consts] ++ ws ++ vs ++ [sh] ++ zs

def goldenText (_ : Unit := ()) : String := String.intercalate "" (goldenLines.map (· ++ "\n"))

def check (path : System.FilePath) : IO Unit := do
  let cur ← IO.FS.readFile path
  unless cur == goldenText do throw (IO.userError s!"offscreen-webkit golden: {path} differs from the generated bytes")
  IO.println s!"offscreen-webkit golden: {path} is up to date ({goldenLines.length} lines)"

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "measure" / "offscreen-webkit.jsonl"

def checkRepo : IO Unit := check goldenPath

def write (path : System.FilePath) : IO Unit := IO.FS.writeFile path goldenText

#guard (verdict 4500 5200 (three [(2, 40)]) (three [(2, 4)])) == .gain
#guard (verdict 4500 5200 (three [(2, 40)]) (three [(2, 40)])) == .noGain
#guard (verdict 4500 5300 (three [(2, 40)]) (three [(2, 4)])) == .noData
#guard (verdict 4500 5200 (three [(2, 40)]) shifted) == .noData
#guard (verdict 4500 5200 (three [(2, 4)]) (three [(2, 40)])) == .noGain
#guard (zoneVerdicts (three [(2, 40)]) (three [(2, 4)])).map (·.2) == [.gain, .gain, .gain, .gain]
#guard (passVerdict 4500 5200 (three [(2, 40)]) (onVms [1, 1, 2, 2] [(2, 4)])) == .gain
#guard (verdict 4500 5200 (three [(2, 40)]) (onVms [1, 1, 2, 2] [(2, 4)])) == .noData
#guard undecided (three [(2, 40)]) (onVms [1, 1, 2, 2] [(2, 4)])
#guard undecided (onVms [1, 1, 1] [(2, 40)]) (three [(2, 4)])
#guard !undecided (three [(2, 40)]) (onVms [4, 4, 5, 5, 6, 6] [(2, 4)])
#guard vmCount (onVms [1, 1, 2, 2, 3, 3] []) == 3
#guard (verdict 4500 5200 (onVms [1, 1, 2, 2, 3, 3] [(2, 40)]) (onVms [4, 4, 5, 5, 6, 6] [(2, 4)])) == .gain
#guard (zoneVerdicts (three [(2, 40)]) (onVms [1, 1, 2, 2] [(2, 4)])).map (·.2) == [.noData, .noData, .noData, .noData]

end Fw.Measure.OffscreenWebKitGolden

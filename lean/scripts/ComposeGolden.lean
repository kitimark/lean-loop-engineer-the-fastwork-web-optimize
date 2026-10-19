import Fw.Measure.Wire
open Lean Fw.Wire.Measure

def goldenPath : String := "../packages/engine-check/golden/compose.jsonl"

def zoneJ (id : String) (i : Nat) (sums : List (String × Int)) : Json :=
  Json.mkObj [("id", .str id), ("frames", toJson (1 : Nat)), ("scrolledPx", toJson (0 : Int)),
    ("firstFrame", toJson i), ("lastFrame", toJson i), ("sums", Json.mkObj (sums.map fun (k, v) => (k, toJson v)))]

def runJ (vs : List (String × String)) (z0 z1 : List (String × Int)) : Json :=
  Json.mkObj [("variants", Json.mkObj (vs.map fun (k, v) => (k, .str v))),
    ("zones", .arr #[zoneJ "y00000" 0 z0, zoneJ "y00500" 1 z1])]

def baseSide (fire : Int) : Json :=
  let z1 : List (String × Int) := [("trace.Layout.dirtyObjects", 10), ("census.layers", 5), ("trace.Layout", 4)]
  let vs := [("a", "faithful"), ("b", "faithful")]
  .arr #[runJ vs [("trace.Layout.dirtyObjects", 10), ("census.layers", 5), ("trace.Layout", 4),
            ("trace.FireAnimationFrame", fire)] z1,
         runJ vs [("trace.Layout.dirtyObjects", 10), ("census.layers", 5), ("trace.Layout", 4),
            ("trace.FireAnimationFrame", 4)] z1]

def armSide (vs : List (String × String)) (d0 d1 layers0 layout : Int) : Json :=
  let r := runJ vs [("trace.Layout.dirtyObjects", d0), ("census.layers", layers0), ("trace.Layout", layout),
      ("trace.FireAnimationFrame", 4)]
    [("trace.Layout.dirtyObjects", d1), ("census.layers", 5), ("trace.Layout", layout)]
  .arr #[r, r]

def cmpJ (id baseId : String) (base arm : Json) : Json :=
  Json.mkObj [("id", .str id), ("baseId", .str baseId), ("base", base), ("arm", arm)]

def clsJ (c : String) (k t : Nat) : Json := Json.mkObj [("class", .str c), ("k", toJson k), ("t", toJson t)]

def classesJ : Json := Json.mkObj [
  ("trace.Layout.dirtyObjects", clsJ "deterministic" 0 0), ("trace.FireAnimationFrame", clsJ "deterministic" 0 0),
  ("census.layers", clsJ "stable" 2 3), ("trace.Layout", clsJ "deterministic" 0 0),
  ("trace.FunctionCall", clsJ "quarantined" 0 0)]

def requests : List Json :=
  let comb := armSide [("a", "x"), ("b", "y")] 5 4 9 2
  let sa := armSide [("a", "x"), ("b", "faithful")] 7 9 6 3
  let sb := armSide [("a", "faithful"), ("b", "y")] 8 10 7 3
  [Json.mkObj [("classes", classesJ), ("combined", cmpJ "C" "B" (baseSide 3) comb),
     ("singles", .arr #[cmpJ "A" "B" (baseSide 3) sa, cmpJ "Bs" "B" (baseSide 3) sb])],
   Json.mkObj [("classes", classesJ), ("combined", cmpJ "C" "B" (baseSide 4) comb),
     ("singles", .arr #[cmpJ "A" "B" (baseSide 4) sa, cmpJ "Bs" "B2" (baseSide 4) sb,
       cmpJ "Bu" "B" (baseSide 4) (.arr #[runJ [("b", "y")] [] [], runJ [("a", "x"), ("b", "y")] [] []])])],
   Json.mkObj [("classes", classesJ), ("combined", cmpJ "C" "B" (baseSide 4) (.arr #[])), ("singles", .arr #[])]]

def line (req : Json) : Json :=
  let reply := match opCompose req with
    | .ok r => Json.mkObj r
    | .error e => Json.mkObj [("error", .str e)]
  Json.mkObj [("request", req), ("reply", reply)]

def main (args : List String) : IO UInt32 := do
  let text := String.join (requests.map fun r => (line r).compress ++ "\n")
  if !args.contains "--check" then
    IO.FS.writeFile goldenPath text
    IO.println s!"compose golden: {requests.length} lines written"
    return 0
  let cur ← try IO.FS.readFile goldenPath catch _ => pure ""
  if cur != text then
    IO.println s!"compose golden: {goldenPath} is stale (regenerate: cd lean && lake env lean --run scripts/ComposeGolden.lean)"
    return 1
  IO.println s!"compose golden: {requests.length} lines, up to date"
  return 0

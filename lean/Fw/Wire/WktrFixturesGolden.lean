import Fw.Measure.WktrLayout
import Lean.Data.Json
/-!
# Golden vectors of the WKTR fixture lane (task `wktr-fixture-speed`)

`packages/contracts/golden/measure/wktr.fixtures.jsonl`, one JSON object per line, `kind` says which:

* `cells`: the 13 cells.
* `layout`: the phases and lanes of `Fw.Measure.WktrLayout.layout` for the premise test (`mode` probe, widths 1, 2, 3) and for
  production (`mode` auto, the table `heldTable`, request 3). `packages/measure-wktr/fixtures/lanes.mjs` reads these lines.
* `maxParallel`: the job parallelism for 1 to 4 jobs (`.github/workflows/wktr-fixtures.yml` plan job reads the line).
* `expect`: the assertions (`expects`); `expectCase`: positive and negative observations with the verdict of `Expect.ok`;
  `classesEqualCase`: pairs of class tables with the verdict of `classesEqual`. `packages/measure-wktr/fixtures/premise.mjs`
  is tested against them.

```
cd lean && lake env lean --run scripts/WktrFixturesGolden.lean           # write the file
cd lean && lake env lean --run scripts/WktrFixturesGolden.lean --check   # fail if it is stale
```
-/
namespace Fw.Wire.WktrFixtures.Golden
open Lean Fw.Measure Fw.Measure.WktrLayout

def cellJson (c : Cell) : Json :=
  Json.mkObj [("fixture", Json.str c.fixture), ("frames", (c.frames : Json)), ("variant", Json.str c.variant.name)]

def phaseJson (p : Phase) : Json :=
  Json.mkObj [("variant", Json.str p.variant.name), ("width", (p.lanes.length : Json)),
    ("lanes", Json.arr (p.lanes.map fun l => Json.arr (l.map cellJson).toArray).toArray)]

def layoutLine (mode : String) (req : Nat) (held : Held) : Json :=
  Json.mkObj [("kind", Json.str "layout"), ("mode", Json.str mode), ("req", (req : Json)),
    ("phases", Json.arr ((layout held req).map phaseJson).toArray)]

def kindName : Kind → String
  | .det => "deterministic"
  | .stable => "stable"
  | .quar => "quarantined"

def expectJson (e : Expect) : Json :=
  Json.mkObj [("arm", Json.str s!"{e.fixture}-f{e.frames}"), ("variant", Json.str e.variant.name), ("type", Json.str e.type),
    ("class", Json.str (kindName e.kind)), ("lo", (e.lo : Json)), ("hi", (e.hi : Json))]

/-- A positive observation (every pass at the middle of the band), and three negative ones: the other class, a pass below the
band, a pass above it. -/
def expectCases (e : Expect) : List Json :=
  let u := 1000
  let mid := (e.lo + e.hi) / 2
  let other : Kind := match e.kind with | .det => .quar | _ => .det
  let obs (name : String) (k : Kind) (sums : List (Nat × Nat)) : Json :=
    Json.mkObj [("kind", Json.str "expectCase"), ("name", Json.str name), ("expect", expectJson e),
      ("observedClass", Json.str (kindName k)),
      ("sums", Json.arr (sums.map fun (a, b) => Json.arr #[(a : Json), (b : Json)]).toArray),
      ("ok", Json.bool (e.ok k sums))]
  [ obs "inBand" e.kind [(mid, u), (mid, u)],
    obs "wrongClass" other [(mid, u)],
    obs "lowEdge" e.kind [(mid, u), (if e.lo = 0 then 0 else e.lo - 1, u)],
    obs "above" e.kind [(e.hi + 1, u)] ]

def classJson (c : Class) : Json :=
  match c with
  | .deterministic => Json.mkObj [("class", Json.str "deterministic"), ("k", (0 : Json)), ("t", (0 : Json))]
  | .stable k t => Json.mkObj [("class", Json.str "stable"), ("k", (k : Json)), ("t", (t : Json))]
  | .quarantined => Json.mkObj [("class", Json.str "quarantined"), ("k", (0 : Json)), ("t", (0 : Json))]

def tableJson (t : List (CountType × Class)) : Json := Json.mkObj (t.map fun (n, c) => (n, classJson c))

def classesCases : List Json :=
  let det := Class.deterministic
  let cases : List (String × List (CountType × Class) × List (CountType × Class)) :=
    [ ("same", [("styleRecalcs", det), ("layoutUpdates", .stable 2 3)], [("layoutUpdates", .stable 2 3), ("styleRecalcs", det)]),
      ("stableMoved", [("layoutUpdates", .stable 2 3)], [("layoutUpdates", .stable 3 3)]),
      ("detToStable", [("styleRecalcs", det)], [("styleRecalcs", .stable 1 1)]),
      ("quarantinedBoth", [("a", .quarantined)], [("a", .quarantined)]),
      ("extraType", [("a", det)], [("a", det), ("b", det)]),
      ("empty", [], []) ]
  cases.map fun (n, a, b) =>
    Json.mkObj [("kind", Json.str "classesEqualCase"), ("name", Json.str n), ("a", tableJson a), ("b", tableJson b),
      ("equal", Json.bool (classesEqual a b))]

/-- The lines of the file. -/
def cases : List Json :=
  [Json.mkObj [("kind", Json.str "cells"), ("cells", Json.arr (cells.map cellJson).toArray)]] ++
  ([1, 2, 3].map fun k => layoutLine "probe" k probeTable) ++
  [layoutLine "auto" 3 heldTable] ++
  (([1, 2, 3, 4] : List Nat).map fun (n : Nat) =>
    Json.mkObj [("kind", Json.str "maxParallel"), ("jobs", (n : Json)), ("slots", (macSlots : Json)),
      ("others", Json.arr (otherLanes.map fun (x : Nat) => (x : Json)).toArray),
      ("maxParallel", (maxParallel macSlots otherLanes n : Json))]) ++
  expects.map (fun e => Json.mkObj (("kind", Json.str "expect") :: (match expectJson e with | .obj m => m.toList | _ => []))) ++
  expects.flatMap expectCases ++ classesCases

def text : String := String.join (cases.map fun j => j.compress ++ "\n")

def dir : System.FilePath := ".." / "packages" / "contracts" / "golden" / "measure"

/-- Compare (or write) the file; returns the number of stale files. -/
def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let d := root / dir
  let p := d / "wktr.fixtures.jsonl"
  if write then
    IO.FS.createDirAll d
    IO.FS.writeFile p text
    IO.println s!"wktr-fixtures golden: {cases.length} lines written"
    return 0
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur != text then
    IO.println s!"wktr-fixtures golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/WktrFixturesGolden.lean)"
    return 1
  IO.println s!"wktr-fixtures golden: {cases.length} lines, 0 stale"
  return 0

end Fw.Wire.WktrFixtures.Golden

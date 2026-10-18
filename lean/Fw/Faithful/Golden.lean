import Fw.Wire
/-!
# Golden vectors of `faithful.verdict`

`packages/contracts/golden/faithful/faithful.verdict.jsonl`: one line per case, `{"name", "request", "response"}`,
generated from Lean, never by hand (same format as the `measure.*` goldens):

```
cd lean && lake env lean --run scripts/FaithfulGolden.lean           # write the file
cd lean && lake env lean --run scripts/FaithfulGolden.lean --check   # fail if it is stale
```

The TS consumer `packages/measure-chromium/src/faithful.mjs` sends every request to `fwcore`
(`packages/measure-chromium/test/faithful.test.mjs`).
-/
namespace Fw.Wire.Faithful.Golden
open Lean

/-- A class-table entry. -/
def cls (c : String) (k t : Nat) : Json :=
  Json.mkObj [("class", .str c), ("k", toJson k), ("t", toJson t)]

/-- The class table of the cases: `det` and `exactDet` deterministic, `st` stable (k 2, t 3), `q` quarantined. -/
def table : Json := Json.mkObj [
  ("trace.cc.Draw", cls "deterministic" 0 0), ("trace.Layout", cls "deterministic" 0 0),
  ("trace.Paint", cls "deterministic" 0 0), ("n0.events", cls "deterministic" 0 0),
  ("trace.FunctionCall", cls "deterministic" 0 0), ("trace.UpdateLayer", cls "stable" 2 3),
  ("trace.cc.Activate", cls "stable" 2 3), ("trace.PrePaint", cls "quarantined" 9 9)]

/-- A zone `{id, frames, scrolledPx, types}` with cells `(type, lo, hi, base)`. -/
def zone (id : String) (frames : Nat) (px : Int) (cells : List (String × Int × Int × Int)) : Json :=
  Json.mkObj [("id", .str id), ("frames", toJson frames), ("scrolledPx", toJson px),
    ("types", Json.mkObj (cells.map fun (ty, lo, hi, b) =>
      (ty, Json.mkObj [("lo", toJson lo), ("hi", toJson hi), ("base", toJson b)])))]

/-- A request with A's zones, R's zones and optionally the zone ids to judge. -/
def req (a r : List Json) (zones : Option (List String) := none) : Json :=
  Json.mkObj ([("classes", table), ("a", .arr a.toArray), ("r", .arr r.toArray)] ++
    (match zones with | some zs => [("zones", .arr (zs.map Json.str).toArray)] | none => []))

/-- A's cells of the base zone. -/
def aCells : List (String × Int × Int × Int) :=
  [("trace.cc.Draw", 50, 50, 50), ("trace.Layout", 100, 100, 100), ("trace.Paint", 1000, 1000, 1000),
   ("n0.events", 0, 0, 0), ("trace.FunctionCall", 40, 40, 40), ("trace.UpdateLayer", 10, 12, 11),
   ("trace.cc.Activate", 20, 22, 21), ("trace.PrePaint", 7, 9, 8)]

/-- A's three zones with cells `cs` in each. -/
def aZones (cs : List (String × Int × Int × Int)) : List Json :=
  [zone "y04000" 50 500 cs, zone "y04500" 14 136 cs, zone "tail" 30 0 cs]

/-- R's cells: `edit` replaces the base of type `ty`. -/
def rCells (edits : List (String × Int)) : List (String × Int × Int × Int) :=
  aCells.map fun (ty, _, _, b) =>
    match edits.find? (·.1 == ty) with
    | some (_, v) => (ty, v, v, v)
    | none => (ty, b, b, b)

/-- The cases. -/
def cases : List (String × Json) := [
  ("R equals A in all three zones: pass", req (aZones aCells) (aZones (rCells []))),
  ("an exact-family cell one off: its zone fails and names the type",
    req (aZones aCells) [zone "y04000" 50 500 (rCells [("trace.cc.Draw", 51)]), zone "y04500" 14 136 (rCells []),
      zone "tail" 30 0 (rCells [])]),
  ("pct5 inside max(2, 5 %) of 100: 105 passes, 106 fails",
    req (aZones aCells) [zone "y04000" 50 500 (rCells [("trace.Layout", 105)]),
      zone "y04500" 14 136 (rCells [("trace.Layout", 106)]), zone "tail" 30 0 (rCells [])]),
  ("pct10 inside 10 % of 1000: 1100 passes, 1101 fails",
    req (aZones aCells) [zone "y04000" 50 500 (rCells [("trace.Paint", 1100)]),
      zone "y04500" 14 136 (rCells [("trace.Paint", 1101)]), zone "tail" 30 0 (rCells [])]),
  ("a sheet mutation in R: the zero family fails",
    req (aZones aCells) [zone "y04000" 50 500 (rCells []), zone "y04500" 14 136 (rCells [("n0.events", 1)]),
      zone "tail" 30 0 (rCells [])]),
  ("a stable exact-family type gets 2t = 6 on top of A's envelope [20, 22]: 28 passes, 29 fails",
    req (aZones aCells) [zone "y04000" 50 500 (rCells [("trace.cc.Activate", 28)]),
      zone "y04500" 14 136 (rCells [("trace.cc.Activate", 29)]), zone "tail" 30 0 (rCells [])]),
  ("a quarantined type and an unbanded type never gate",
    req (aZones aCells) [zone "y04000" 50 500 (rCells [("trace.PrePaint", 900), ("trace.FunctionCall", 900)]),
      zone "y04500" 14 136 (rCells []), zone "tail" 30 0 (rCells [])]),
  ("a type only R has (unlisted in A's table) is skipped",
    req (aZones aCells) [zone "y04000" 50 500 (rCells [] ++ [("trace.New", 5, 5, 5)]),
      zone "y04500" 14 136 (rCells []), zone "tail" 30 0 (rCells [])]),
  ("a type only A has reads 0 in R: an exact-family cell fails",
    req (aZones aCells) [zone "y04000" 50 500 ((rCells []).filter (·.1 != "trace.cc.Draw")),
      zone "y04500" 14 136 (rCells []), zone "tail" 30 0 (rCells [])]),
  ("a different frame count fails the zone's shape",
    req (aZones aCells) [zone "y04000" 50 500 (rCells []), zone "y04500" 13 136 (rCells []),
      zone "tail" 30 0 (rCells [])]),
  ("a zone missing in R fails and reports present false",
    req (aZones aCells) [zone "y04000" 50 500 (rCells []), zone "tail" 30 0 (rCells [])]),
  ("zones asks for one zone only", req (aZones aCells) (aZones (rCells [])) (some ["tail"])),
  ("classes missing is refused", Json.mkObj [("a", .arr #[]), ("r", .arr #[])])]

/-- The request with its `op` field set. -/
def withOp (j : Json) : Json :=
  match j with
  | .obj kvs => .obj (kvs.insert "op" (.str "faithful.verdict"))
  | j => j

/-- The reply to a request as a JSON object without the id. -/
def respond (req : Json) : Json :=
  match Json.parse (Fw.Wire.handleLine (withOp req).compress) with
  | .ok (.obj kvs) => .obj (kvs.erase "id")
  | .ok j => j
  | .error e => Json.mkObj [("error", .str s!"reply is not JSON: {e}")]

/-- The text of the golden file. -/
def fileText : String :=
  String.join (cases.map fun (name, r) =>
    (Json.mkObj [("name", .str name), ("request", withOp r), ("response", respond r)]).compress ++ "\n")

/-- The golden file, relative to `lean/`. -/
def file : System.FilePath := ".." / "packages" / "contracts" / "golden" / "faithful" / "faithful.verdict.jsonl"

/-- Write the golden file, or with `write = false` compare it; returns the number of stale files. -/
def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let p := root / file
  if write then
    IO.FS.createDirAll (p.parent.getD ".")
    IO.FS.writeFile p fileText
    IO.println s!"faithful golden: {cases.length} cases, written"
    return 0
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur != fileText then
    IO.println s!"faithful golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/FaithfulGolden.lean)"
    return 1
  IO.println s!"faithful golden: {cases.length} cases, 0 stale"
  return 0

end Fw.Wire.Faithful.Golden

import Fw.Wire
/-!
# Golden vectors of `faithful.verdict`

`packages/contracts/golden/faithful/<op>.jsonl` (`faithful.verdict`, `faithful.comparable`): one line per case, `{"name", "request", "response"}`,
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

/-- The cases of `faithful.verdict`. -/
def verdictCases : List (String × Json) := [
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
  ("A recorded no zones: every region zone is absent and fails", req [] (aZones (rCells []))),
  ("R recorded no zones: every region zone is absent and fails", req (aZones aCells) []),
  ("zones asks for no zone: undecided, never a pass", req (aZones aCells) (aZones (rCells [])) (some [])),
  ("no zones in either arm and none asked for: undecided", req [] [] (some [])),
  ("tail has 0 frames and no cells in both arms: undecided, not a pass",
    req [zone "y04000" 50 500 aCells, zone "y04500" 14 136 aCells, zone "tail" 0 0 []]
      [zone "y04000" 50 500 (rCells []), zone "y04500" 14 136 (rCells []), zone "tail" 0 0 []]),
  ("tail has 0 frames in both arms and equal cells: undecided",
    req [zone "y04000" 50 500 aCells, zone "y04500" 14 136 aCells, zone "tail" 0 0 aCells]
      [zone "y04000" 50 500 (rCells []), zone "y04500" 14 136 (rCells []), zone "tail" 0 0 (rCells [])]),
  ("tail has frames but no count type in either arm: undecided",
    req [zone "y04000" 50 500 aCells, zone "y04500" 14 136 aCells, zone "tail" 30 0 []]
      [zone "y04000" 50 500 (rCells []), zone "y04500" 14 136 (rCells []), zone "tail" 30 0 []]),
  ("a failing zone next to an empty zone: the request fails, the empty zone is undecided",
    req [zone "y04000" 50 500 aCells, zone "y04500" 14 136 aCells, zone "tail" 0 0 []]
      [zone "y04000" 50 500 (rCells [("trace.cc.Draw", 51)]), zone "y04500" 14 136 (rCells []), zone "tail" 0 0 []]),
  ("classes missing is refused", Json.mkObj [("a", .arr #[]), ("r", .arr #[])])]

def mj (profile : String := "swipe-v1") (observed : Option (Nat × Nat) := some (430, 932)) (preset : String := "original")
    (browser : String := "HeadlessChrome/156.0.8078.4") (zoneHeightPx : Nat := 500) (width : Nat := 430) (touch : Bool := true) : Json :=
  Json.mkObj ([("profile", .str profile), ("preset", .str preset), ("browser", .str browser),
    ("zoneHeightPx", toJson zoneHeightPx),
    ("viewport", Json.mkObj [("width", toJson width), ("height", toJson 932), ("dpr", toJson 3), ("mobile", .bool true),
      ("touch", .bool touch)])] ++
    (match observed with
     | some (w, h) => [("observed", Json.mkObj [("width", toJson w), ("height", toJson h)])]
     | none => []))

/-- A `faithful.comparable` request. -/
def cmp (a r : Json) : Json := Json.mkObj [("a", a), ("r", r)]

/-- The cases of `faithful.comparable`. -/
def comparableCases : List (String × Json) := [
  ("candidate and reference observed at the profile viewport: comparable", cmp (mj) (mj)),
  ("the frozen reference recorded no observed viewport: comparable", cmp (mj (observed := none)) (mj)),
  ("the 645 x 1398 run: the candidate's page reported another viewport", cmp (mj) (mj (observed := some (645, 1398)))),
  ("a candidate that did not record its observed viewport is refused", cmp (mj) (mj (observed := none))),
  ("another profile is refused first", cmp (mj) (mj (profile := "swipe-touch-v1") (observed := some (645, 1398)))),
  ("another preset", cmp (mj) (mj (preset := "rewrite"))),
  ("another zone height", cmp (mj) (mj (zoneHeightPx := 400))),
  ("another browser build", cmp (mj) (mj (browser := "HeadlessChrome/157.0.0.0"))),
  ("another declared viewport width", cmp (mj) (mj (width := 390) (observed := some (390, 932)))),
  ("another touch flag", cmp (mj) (mj (touch := false))),
  ("the reference's own observation is not the profile viewport", cmp (mj (observed := some (645, 1398))) (mj)),
  ("field a missing is refused", Json.mkObj [("r", mj)])]

/-- The cases: file name, case name, request. -/
def cases : List (String × String × Json) :=
  verdictCases.map (fun (n, r) => ("faithful.verdict", n, r)) ++ comparableCases.map (fun (n, r) => ("faithful.comparable", n, r))

/-- The request with its `op` field set. -/
def withOp (op : String) (j : Json) : Json :=
  match j with
  | .obj kvs => .obj (kvs.insert "op" (.str op))
  | j => j

/-- The reply to a request as a JSON object without the id. -/
def respond (op : String) (req : Json) : Json :=
  match Json.parse (Fw.Wire.handleLine (withOp op req).compress) with
  | .ok (.obj kvs) => .obj (kvs.erase "id")
  | .ok j => j
  | .error e => Json.mkObj [("error", .str s!"reply is not JSON: {e}")]

/-- The text of the golden file of one op. -/
def fileText (op : String) : String :=
  String.join ((cases.filter (·.1 == op)).map fun (_, name, r) =>
    (Json.mkObj [("name", .str name), ("request", withOp op r), ("response", respond op r)]).compress ++ "\n")

/-- The golden file of an op, relative to `lean/`. -/
def file (op : String) : System.FilePath := ".." / "packages" / "contracts" / "golden" / "faithful" / s!"{op}.jsonl"

/-- Write the golden files, or with `write = false` compare them; returns the number of stale files. -/
def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let mut stale := 0
  for op in ["faithful.verdict", "faithful.comparable"] do
    let p := root / file op
    if write then
      IO.FS.createDirAll (p.parent.getD ".")
      IO.FS.writeFile p (fileText op)
      IO.println s!"faithful golden {op}: {(cases.filter (·.1 == op)).length} cases, written"
    else
      let cur ← try IO.FS.readFile p catch _ => pure ""
      if cur != fileText op then
        IO.println s!"faithful golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/FaithfulGolden.lean)"
        stale := stale + 1
      else IO.println s!"faithful golden {op}: {(cases.filter (·.1 == op)).length} cases, 0 stale"
  return stale

end Fw.Wire.Faithful.Golden

import Fw.Wire
/-!
# Golden vectors of the `measure.*` ops

`packages/contracts/golden/measure/<op>.jsonl`: one line per case,
`{"name", "request", "response"}`, where `request` carries its `op` and `response` is what
`fwcore` replies (without the `id`). Generated from Lean, never by hand:

```
cd lean && lake env lean --run scripts/MeasureGolden.lean           # write the files
cd lean && lake env lean --run scripts/MeasureGolden.lean --check   # fail if a file is stale
```

`lake test` runs the same check (`FwTest.Golden.measure`). The TS conformance tests
(`packages/measure-chromium/test/fwcore.test.mjs`, `packages/measure-webkit/test/fwcore.test.mjs`)
send every request to the `fwcore` binary and compare the replies.
-/
namespace Fw.Wire.Measure.Golden
open Lean

/-- A deterministic pseudo-random sequence (64-bit LCG, high bits) for the synthetic cases. -/
def lcg (seed : Nat) (n : Nat) : List Nat :=
  (List.range n).foldl (fun (acc : List Nat × Nat) _ =>
    let s := (acc.2 * 6364136223846793005 + 1442695040888963407) % 2 ^ 64
    (acc.1 ++ [s / 2 ^ 33], s)) ([], seed) |>.1

/-- A synthetic swipe run: 10 rest frames, swipe frames of 10 px up to 1,230 px, 8 tail frames;
counts from the LCG (a type `rare` only in some frames, a type `neg` with negative values). -/
def syntheticFrames (seed : Nat) : Json :=
  let r := lcg seed 600
  let ph : Nat → String × Int := fun i =>
    if i < 10 then ("rest", 0) else if i < 133 then ("swipe", ((i - 9) * 10 : Nat)) else ("tail", 1230)
  .arr ((List.range 141).toArray.map fun i =>
    let (p, y) := ph i
    let v := fun (j : Nat) => r.getD (4 * i + j) 0
    let counts : List (String × Json) :=
      [("hasDamage", toJson (v 0 % 2)), ("trace.Layout", toJson (v 1 % 3)), ("trace.Paint", toJson (v 2 % 5))] ++
      (if v 3 % 7 == 0 then [("rare", toJson (1 : Nat))] else []) ++ [("neg", toJson ((v 3 % 5 : Nat) - (2 : Int)))]
    Json.mkObj [("n", toJson i), ("phase", .str p), ("scrollY", toJson y), ("vt", toJson (i * 16)),
      ("counts", Json.mkObj counts)])

/-- Parse a literal request (a parse error becomes a visible bad case). -/
def lit (s : String) : Json := (Json.parse s).toOption.getD (Json.mkObj [("unparsable", .str s)])

/-- The cases, per op file: (file stem, [(name, request without op)]). -/
def cases : List (String × List (String × Json)) := [
  ("measure.zoneSums", [
    ("seed vector of pure.test.mjs (500 px zones, rest/tail by phase)", lit "{\"zoneHeightPx\":500,\"frames\":[{\"n\":0,\"phase\":\"rest\",\"scrollY\":0,\"counts\":{\"a\":1,\"b\":2}},{\"n\":1,\"phase\":\"swipe\",\"scrollY\":10,\"counts\":{\"a\":1,\"b\":0}},{\"n\":2,\"phase\":\"swipe\",\"scrollY\":490,\"counts\":{\"a\":2,\"b\":1}},{\"n\":3,\"phase\":\"swipe\",\"scrollY\":500,\"counts\":{\"a\":4,\"b\":1}},{\"n\":4,\"phase\":\"tail\",\"scrollY\":500,\"counts\":{\"a\":0,\"b\":7}}]}"),
    ("no frames", lit "{\"zoneHeightPx\":500,\"frames\":[]}"),
    ("missing types stay absent; negative counts; zone revisited after another zone", lit "{\"zoneHeightPx\":100,\"frames\":[{\"n\":5,\"phase\":\"swipe\",\"scrollY\":50,\"counts\":{\"x\":1}},{\"n\":6,\"phase\":\"swipe\",\"scrollY\":150,\"counts\":{\"y\":-3}},{\"n\":7,\"phase\":\"swipe\",\"scrollY\":60,\"counts\":{\"x\":2,\"y\":1}}]}"),
    ("negative scroll floors down; six-digit offsets are not cut; a phase named like a zone shares it", lit "{\"zoneHeightPx\":500,\"frames\":[{\"n\":0,\"phase\":\"swipe\",\"scrollY\":-1,\"counts\":{\"a\":1}},{\"n\":1,\"phase\":\"swipe\",\"scrollY\":123456,\"counts\":{\"a\":1}},{\"n\":2,\"phase\":\"y00000\",\"scrollY\":0,\"counts\":{\"a\":5}},{\"n\":3,\"phase\":\"swipe\",\"scrollY\":10,\"counts\":{\"a\":1}}]}"),
    ("extra frame fields (vt) are ignored", lit "{\"zoneHeightPx\":500,\"frames\":[{\"n\":0,\"phase\":\"rest\",\"scrollY\":0,\"vt\":16.667,\"counts\":{\"a\":1}}]}"),
    ("synthetic swipe-like run, 141 frames", Json.mkObj [("zoneHeightPx", toJson (500 : Nat)), ("frames", syntheticFrames 7)]),
    ("zone height 0 is refused", lit "{\"zoneHeightPx\":0,\"frames\":[]}"),
    ("a non-integer count is refused", lit "{\"zoneHeightPx\":500,\"frames\":[{\"n\":0,\"phase\":\"rest\",\"scrollY\":0,\"counts\":{\"a\":1.5}}]}")]),
  ("measure.classify", [
    ("frames: deterministic, stable (one unit shifted a frame), quarantined (many frames)", lit "{\"mode\":\"frames\",\"kMax\":2,\"tMax\":24,\"runs\":[[{\"counts\":{\"d\":1,\"s\":1,\"q\":1}},{\"counts\":{\"d\":0,\"s\":0,\"q\":1}},{\"counts\":{\"d\":2,\"s\":3,\"q\":1}}],[{\"counts\":{\"d\":1,\"s\":0,\"q\":0}},{\"counts\":{\"d\":0,\"s\":1,\"q\":0}},{\"counts\":{\"d\":2,\"s\":3,\"q\":0}}],[{\"counts\":{\"d\":1,\"s\":1,\"q\":1}},{\"counts\":{\"d\":0,\"s\":0,\"q\":1}},{\"counts\":{\"d\":2,\"s\":3,\"q\":1}}]]}"),
    ("frames: tight policy quarantines the shifted type", lit "{\"mode\":\"frames\",\"kMax\":1,\"tMax\":0,\"runs\":[[{\"counts\":{\"s\":1}},{\"counts\":{\"s\":0}}],[{\"counts\":{\"s\":0}},{\"counts\":{\"s\":1}}]]}"),
    ("frames: runs as counts.json objects; a type missing from a run counts 0; shorter run padded", lit "{\"mode\":\"frames\",\"kMax\":4,\"tMax\":24,\"runs\":[{\"schema\":\"fw.counts/1\",\"frames\":[{\"n\":0,\"counts\":{\"a\":1,\"z\":0}},{\"n\":1,\"counts\":{\"a\":0}}]},{\"frames\":[{\"n\":0,\"counts\":{\"a\":1}}]}]}"),
    ("frames: one run is refused", lit "{\"mode\":\"frames\",\"kMax\":4,\"tMax\":24,\"runs\":[[{\"counts\":{\"a\":1}}]]}"),
    ("cells: deterministic (TOL.step)", lit "{\"mode\":\"cells\",\"tol\":{\"absTol\":1,\"relTol\":0},\"runs\":[[1,2,3],[1,2,3]]}"),
    ("cells: stable (TOL.step)", lit "{\"mode\":\"cells\",\"tol\":{\"absTol\":1,\"relTol\":0},\"runs\":[[1,2,3],[1,3,3]]}"),
    ("cells: quarantined (TOL.step)", lit "{\"mode\":\"cells\",\"tol\":{\"absTol\":1,\"relTol\":0},\"runs\":[[1,2,3],[1,5,3]]}"),
    ("cells: 4 <= max(2, 5) is stable (TOL.total)", lit "{\"mode\":\"cells\",\"tol\":{\"absTol\":2,\"relTol\":0.05},\"runs\":[[100],[104]]}"),
    ("cells: 10 > max(2, 5.5) is quarantined (TOL.total)", lit "{\"mode\":\"cells\",\"tol\":{\"absTol\":2,\"relTol\":0.05},\"runs\":[[100],[110]]}"),
    ("cells: lengths differ", lit "{\"mode\":\"cells\",\"tol\":{\"absTol\":1,\"relTol\":0},\"runs\":[[1,2],[1]]}"),
    ("cells: TOL.exact", lit "{\"mode\":\"cells\",\"tol\":{\"absTol\":0,\"relTol\":0},\"runs\":[[0],[1]]}"),
    ("cells: spread over three runs", lit "{\"mode\":\"cells\",\"tol\":{\"absTol\":1,\"relTol\":0},\"runs\":[[1],[1],[2]]}"),
    ("cells: boundary spread equal to relTol * big (TOL.zone, 3 = 0.1 * 30)", lit "{\"mode\":\"cells\",\"tol\":{\"absTol\":2,\"relTol\":0.1},\"runs\":[[30,27,0],[27,30,0],[29,29,-1]]}"),
    ("cells: memory bytes 2 % (TOL.memory)", lit "{\"mode\":\"cells\",\"tol\":{\"absTol\":0,\"relTol\":0.02},\"runs\":[[1000000,52428800],[1020000,52428800],[1000001,53477376]]}"),
    ("cells: relative spread rounding (1/3, 2/3, 1/32)", lit "{\"mode\":\"cells\",\"tol\":{\"absTol\":5,\"relTol\":0},\"runs\":[[3,0,32],[2,2,31]]}"),
    ("cells: one run is refused", lit "{\"mode\":\"cells\",\"tol\":{\"absTol\":1,\"relTol\":0},\"runs\":[[1]]}"),
    ("unknown mode", lit "{\"mode\":\"pairs\",\"runs\":[[1],[1]]}")]),
  ("measure.noMoreWork", [
    ("deterministic frame by frame, stable with margin 2t, quarantined left out", lit "{\"types\":[{\"class\":{\"class\":\"deterministic\"},\"base\":[3,1],\"var\":[2,1]},{\"class\":{\"class\":\"stable\",\"k\":2,\"t\":1},\"base\":[10,0],\"var\":[0,8]},{\"class\":{\"class\":\"quarantined\"},\"base\":[0],\"var\":[99]}]}"),
    ("stable inside the margin fails", lit "{\"types\":[{\"class\":{\"class\":\"stable\",\"k\":2,\"t\":1},\"base\":[10,0],\"var\":[0,9]}]}"),
    ("deterministic work moved a frame fails", lit "{\"types\":[{\"class\":{\"class\":\"deterministic\"},\"base\":[1,0],\"var\":[0,1]}]}"),
    ("stable with k = 0 needs no margin", lit "{\"types\":[{\"class\":{\"class\":\"stable\",\"k\":0,\"t\":5},\"base\":[3],\"var\":[3]}]}")]),
  ("measure.webkit.tally", [
    ("fixed types, paint area, other types (reduce.test.mjs)", lit "{\"rows\":[[\"Layout\",0,0,null],[\"Layout\",0,0,null],[\"Paint\",0,0,[0,0,4,0,4,4,0,4]],[\"EvaluateScript\",0,0,null],[\"TimeStamp\",0,0,\"x\"]]}"),
    ("paint area rounds half up; short quads count 0; clockwise quads count positive", lit "{\"rows\":[[\"Paint\",1,null,[0,0,1,0,1,0.5,0,0.5]],[\"Paint\",1,null,[0,0,0,1,1,1,1,0]],[\"Paint\",1,null,[1,2,3]],[\"Paint\",1,null,null]]}"),
    ("no rows", lit "{\"rows\":[]}")]),
  ("measure.webkit.reduceSteps", [
    ("half-open windows, rows before the first mark and after the end (reduce.test.mjs)", lit "{\"rows\":[[\"Layout\",0.5,null,null],[\"Layout\",1,null,null],[\"Layout\",1.9,null,null],[\"Paint\",2,null,null],[\"Layout\",3.5,null,null],[\"Layout\",4,null,null]],\"marks\":[1,2,3],\"endTime\":4}"),
    ("reduceSteps of reduce.test.mjs", lit "{\"rows\":[[\"RecalculateStyles\",1,null,null],[\"Layout\",2.5,null,null],[\"Layout\",3.5,null,null],[\"Paint\",3.6,null,[0,0,1,0,1,1,0,1]]],\"marks\":[1,2,3],\"endTime\":4}"),
    ("a row without a numeric start counts as before; equal marks: the later step wins", lit "{\"rows\":[[\"Layout\",null,null,null],[\"Layout\",2,null,null],[\"Composite\",2.0000001,null,null],[\"Bogus\",3,null,null]],\"marks\":[1,2,2],\"endTime\":10}"),
    ("decreasing marks are refused", lit "{\"rows\":[],\"marks\":[2,1],\"endTime\":3}"),
    ("no marks is refused", lit "{\"rows\":[],\"marks\":[],\"endTime\":3}")]),
  ("measure.webkit.zones", [
    ("zones of reduce.test.mjs", lit "{\"ys\":[0,400,800],\"perStep\":[[1,0,0,0,0,0,0,0,0,0,0,0],[0,1,0,0,0,0,0,0,0,0,0,0],[0,1,0,0,0,0,0,0,0,0,0,0]],\"perStepPaintArea\":[0,0,1],\"zonePx\":500}"),
    ("empty zones in between are listed; default zonePx 500; short rows pad with 0", lit "{\"ys\":[0,1700.5],\"perStep\":[[1,2],[3]],\"perStepPaintArea\":[5,7]}"),
    ("no steps", lit "{\"ys\":[],\"perStep\":[],\"perStepPaintArea\":[]}"),
    ("a negative offset is refused", lit "{\"ys\":[-1],\"perStep\":[[0]],\"perStepPaintArea\":[0]}"),
    ("length mismatch is refused", lit "{\"ys\":[0,1],\"perStep\":[[0]],\"perStepPaintArea\":[0]}")]),
  ("measure.symDiff", [
    ("same multiset", lit "{\"a\":[\"a\",\"b\"],\"b\":[\"b\",\"a\"]}"),
    ("multiplicities count", lit "{\"a\":[\"a\",\"a\",\"b\"],\"b\":[\"a\",\"c\"]}"),
    ("empty", lit "{\"a\":[],\"b\":[]}")]),
  ("measure.summarize", [
    ("worst level wins; a repeated level keeps its last class; groups in order of first appearance", lit "{\"rows\":[{\"family\":\"scroll\",\"metric\":\"Layout\",\"level\":\"total\",\"cls\":\"stable\"},{\"family\":\"scroll\",\"metric\":\"Layout\",\"level\":\"per step\",\"cls\":\"quarantined\"},{\"family\":\"census\",\"metric\":\"layerCount\",\"level\":\"per state\",\"cls\":\"deterministic\"},{\"family\":\"scroll\",\"metric\":\"Layout\",\"level\":\"per step\",\"cls\":\"deterministic\"}]}"),
    ("no rows", lit "{\"rows\":[]}")])]

/-- The request with its `op` field set. -/
def withOp (op : String) : Json → Json
  | .obj kvs => .obj (kvs.insert "op" (.str op))
  | j => j

/-- The reply to a request as a JSON object without the id. -/
def respond (op : String) (req : Json) : Json :=
  let full := withOp op req
  match Json.parse (Fw.Wire.handleLine full.compress) with
  | .ok r => match r with
    | .obj kvs => .obj (kvs.erase "id")
    | j => j
  | .error e => Json.mkObj [("error", .str s!"reply is not JSON: {e}")]

/-- The text of one golden file. -/
def fileText (op : String) (cs : List (String × Json)) : String :=
  String.join (cs.map fun (name, req) =>
    (Json.mkObj [("name", .str name), ("request", withOp op req),
      ("response", respond op req)]).compress ++ "\n")

/-- The golden directory, relative to `lean/`. -/
def dir : System.FilePath := ".." / "packages" / "contracts" / "golden" / "measure"

/-- Compare (or write) every golden file; returns the number of stale files. -/
def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let d := root / dir
  if write then IO.FS.createDirAll d
  let mut stale := 0
  for (op, cs) in cases do
    let p := d / s!"{op}.jsonl"
    let text := fileText op cs
    if write then
      IO.FS.writeFile p text
    else
      let cur ← try IO.FS.readFile p catch _ => pure ""
      if cur != text then
        IO.println s!"measure golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/MeasureGolden.lean)"
        stale := stale + 1
  let n := cases.foldl (fun a c => a + c.2.length) 0
  IO.println s!"measure golden: {cases.length} files, {n} cases, {if write then "written" else s!"{stale} stale"}"
  return stale

end Fw.Wire.Measure.Golden

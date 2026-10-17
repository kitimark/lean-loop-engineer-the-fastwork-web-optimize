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

/-- Run `j` (0, 1 or 2) of the self-check case: 100 swipe frames; `det` and `metric.Nodes` equal in
all runs; run 1 moves one unit of `stable` a frame later (2 frames differ) and one of `shift` over
4 frames, and has one `trace.MinorGC`; run 2 adds 50 to `quar` and has one `rare`. -/
def selfRun (j : Nat) : Json :=
  .arr ((List.range 100).toArray.map fun i =>
    let stable : Int := if j == 1 && i == 10 then 0 else if j == 1 && i == 11 then 2 else 1
    let shift : Int := if j == 1 && (i == 20 || i == 21 || i == 22) then 0 else if j == 1 && i == 23 then 4 else 1
    let quar : Int := if j == 2 && 30 ≤ i && i < 35 then 11 else 1
    let counts : List (String × Json) :=
      [("det", toJson (1 : Nat)), ("metric.Nodes", toJson (500 : Nat)), ("quar", toJson quar),
       ("shift", toJson shift), ("stable", toJson stable)] ++
      (if j == 1 && i == 5 then [("trace.MinorGC", toJson (1 : Nat))] else []) ++
      (if j == 2 && i == 50 then [("rare", toJson (1 : Nat))] else [])
    Json.mkObj [("n", toJson i), ("phase", .str "swipe"), ("scrollY", toJson (10 * i)), ("counts", Json.mkObj counts)])

/-- Runs of `n` frames whose only count `x` sits in frame 0, one run per value. -/
def oneFrameRuns (n : Nat) (vals : List Int) : Json :=
  .arr (vals.toArray.map fun v => Json.mkObj [("frames", .arr ((List.range n).toArray.map fun i =>
    Json.mkObj [("n", toJson i), ("phase", .str "rest"), ("scrollY", toJson (0 : Nat)),
      ("counts", Json.mkObj (if i == 0 then [("x", toJson v)] else []))]))])

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
    ("frames: pixel areas (CI run 39033771018 totals) are stable within 1/1000 of the smallest total; the same gap on a count type is quarantined", lit "{\"mode\":\"frames\",\"kMax\":4,\"tMax\":24,\"runs\":[[{\"counts\":{\"census.drawingAreaPx\":5340886817,\"census.activeTileAreaPx\":2811101184,\"census.drawingArea\":5340886817}}],[{\"counts\":{\"census.drawingAreaPx\":5338843401,\"census.activeTileAreaPx\":2810658816,\"census.drawingArea\":5338843401}}],[{\"counts\":{\"census.drawingAreaPx\":5340887569,\"census.activeTileAreaPx\":2811117568,\"census.drawingArea\":5340887569}}]]}"),
    ("frames: pixel area beyond 1/1000 and beyond tMax is quarantined; within tMax it is stable", lit "{\"mode\":\"frames\",\"kMax\":4,\"tMax\":24,\"runs\":[[{\"counts\":{\"a.AreaPx\":10000,\"b.AreaPx\":1000}}],[{\"counts\":{\"a.AreaPx\":10030,\"b.AreaPx\":1020}}]]}"),
    ("frames: pxRel 1/100 admits a 1 % gap; kMax still binds pixel areas", lit "{\"mode\":\"frames\",\"kMax\":1,\"tMax\":0,\"pxRel\":{\"num\":1,\"den\":100},\"runs\":[[{\"counts\":{\"a.AreaPx\":10000}},{\"counts\":{\"b.AreaPx\":5}},{\"counts\":{\"b.AreaPx\":0}}],[{\"counts\":{\"a.AreaPx\":10100}},{\"counts\":{\"b.AreaPx\":0}},{\"counts\":{\"b.AreaPx\":5}}]]}"),
    ("frames: pixel area identical in every run is deterministic", lit "{\"mode\":\"frames\",\"kMax\":4,\"tMax\":24,\"runs\":[[{\"counts\":{\"raster.invalidationAreaPx\":97163923}}],[{\"counts\":{\"raster.invalidationAreaPx\":97163923}}]]}"),
    ("frames: pxRel with den 0 is refused", lit "{\"mode\":\"frames\",\"kMax\":4,\"tMax\":24,\"pxRel\":{\"num\":1,\"den\":0},\"runs\":[[{\"counts\":{\"a\":1}}],[{\"counts\":{\"a\":1}}]]}"),
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
    ("no rows", lit "{\"rows\":[]}")]),
  ("measure.selfCheck", [
    ("100 frames, 3 runs: deterministic, stable (2% of frames), shifting, quarantined, GC-bound, rare type",
      Json.mkObj [("runs", .arr #[selfRun 0, selfRun 1, selfRun 2])]),
    ("spread at 0.2% of the mean exactly (500·m·s = |S|) is stable", Json.mkObj [("runs", oneFrameRuns 50 [1998, 2002])]),
    ("one below the 0.2% bound is shifting", Json.mkObj [("runs", oneFrameRuns 50 [1997, 2001])]),
    ("negative totals use |mean|", Json.mkObj [("runs", oneFrameRuns 50 [-1998, -2002])]),
    ("spread 4 above max(3, 2% of the mean) is quarantined", Json.mkObj [("runs", oneFrameRuns 50 [100, 104, 103])]),
    ("spread 3 is within the floor whatever the mean", Json.mkObj [("runs", oneFrameRuns 50 [1, 4])]),
    ("2% of frames: 49 frames with one differing frame is not stable", Json.mkObj [("runs", oneFrameRuns 49 [1, 2])]),
    ("one run: everything deterministic", Json.mkObj [("runs", .arr #[selfRun 0])]),
    ("runs as arrays; a shorter run pads with 0; a longer later run's extra frames count in totals only; phases differ", lit "{\"runs\":[[{\"phase\":\"rest\",\"scrollY\":0,\"counts\":{\"a\":1}},{\"phase\":\"swipe\",\"scrollY\":10,\"counts\":{\"a\":1}}],[{\"phase\":\"rest\",\"scrollY\":0,\"counts\":{\"a\":1}}],[{\"phase\":\"rest\",\"scrollY\":0,\"counts\":{\"a\":1}},{\"phase\":\"tail\",\"scrollY\":10,\"counts\":{\"a\":1}},{\"phase\":\"tail\",\"scrollY\":10,\"counts\":{\"a\":7}}]]}"),
    ("scrollY compared as exact numbers (1.0 = 1); no count types", lit "{\"runs\":[{\"frames\":[{\"phase\":\"rest\",\"scrollY\":1,\"counts\":{}}]},{\"frames\":[{\"phase\":\"rest\",\"scrollY\":1.0,\"counts\":{}}]}]}"),
    ("a different scrollY breaks alignment", lit "{\"runs\":[{\"frames\":[{\"phase\":\"rest\",\"scrollY\":1,\"counts\":{\"a\":0}}]},{\"frames\":[{\"phase\":\"rest\",\"scrollY\":2,\"counts\":{\"a\":0}}]}]}"),
    ("no runs is refused", lit "{\"runs\":[]}"),
    ("a non-integer count is refused", lit "{\"runs\":[[{\"phase\":\"rest\",\"scrollY\":0,\"counts\":{\"a\":0.5}}]]}")]),
  ("measure.snapshotCounts", [
    ("empty snapshot object", lit "{\"snapshot\":{}}"),
    ("null snapshot counts as empty", lit "{\"snapshot\":null}"),
    ("layers, tilings, invalidation quads (8 entries: 2 rects; 5: 1 rect; 3: invalidated, no rect), tiles", lit "{\"snapshot\":{\"tile_manager_basic_state\":{\"tile_count\":42},\"active_tree\":{\"layers\":[{\"draws_content\":true,\"bounds\":{\"width\":390,\"height\":844},\"tilings\":[{},{}],\"invalidation\":[0,0,10,20,5,5,3,4]},{\"draws_content\":false,\"bounds\":{\"width\":100,\"height\":100},\"invalidation\":[1,2,3,4,9]},{\"draws_content\":true,\"tilings\":[{}],\"invalidation\":[7,7,7]},{\"draws_content\":true,\"bounds\":{\"width\":50},\"invalidation\":[]}]},\"active_tiles\":[{\"draw_info\":{\"is_solid_color\":true},\"content_rect\":[0,0,256,256]},{\"draw_info\":{\"is_solid_color\":false},\"content_rect\":[0,256,256,100,99]},{\"draw_info\":{}},{}]}}"),
    ("null fields count as absent", lit "{\"snapshot\":{\"tile_manager_basic_state\":null,\"active_tree\":{\"layers\":null},\"active_tiles\":null}}"),
    ("one layer without fields", lit "{\"snapshot\":{\"active_tree\":{\"layers\":[{}]}}}"),
    ("a content_rect with fewer than 4 numbers is refused", lit "{\"snapshot\":{\"active_tiles\":[{\"content_rect\":[0,0]}]}}"),
    ("a non-boolean draws_content is refused", lit "{\"snapshot\":{\"active_tree\":{\"layers\":[{\"draws_content\":1}]}}}")]),
  ("measure.freeze", [
    ("worst class per type over three runs; a type missing from a run is quarantined; k, t maxima; tBound the smallest; pooled class and tally", lit "{\"runs\":[{\"id\":\"101\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":2,\"t\":3},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":500,\"tBound\":1000,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}},{\"id\":\"102\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":3,\"t\":1},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":2,\"t\":400,\"tBound\":990,\"unit\":\"px\"}}},{\"id\":\"103\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"stable\",\"k\":1,\"t\":0},\"b\":{\"class\":\"quarantined\",\"k\":9,\"t\":40},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":0,\"tBound\":1010,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}}],\"pooled\":{\"a\":{\"class\":\"stable\",\"k\":1,\"t\":0},\"b\":{\"class\":\"quarantined\",\"k\":9,\"t\":40},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":2,\"t\":500,\"tBound\":990,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}}"),
    ("the same runs in another order give the same classes (perRun follows the run order)", lit "{\"runs\":[{\"id\":\"103\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"stable\",\"k\":1,\"t\":0},\"b\":{\"class\":\"quarantined\",\"k\":9,\"t\":40},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":0,\"tBound\":1010,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}},{\"id\":\"101\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":2,\"t\":3},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":500,\"tBound\":1000,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}},{\"id\":\"102\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":3,\"t\":1},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":2,\"t\":400,\"tBound\":990,\"unit\":\"px\"}}}]}"),
    ("three copies of one table give that table", lit "{\"runs\":[{\"id\":\"101\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":2,\"t\":3},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":500,\"tBound\":1000,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}},{\"id\":\"201\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":2,\"t\":3},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":500,\"tBound\":1000,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}},{\"id\":\"202\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":2,\"t\":3},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":500,\"tBound\":1000,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}}]}"),
    ("no types", lit "{\"runs\":[{\"id\":\"1\",\"images\":[\"sha256:aa\"],\"classes\":{}},{\"id\":\"2\",\"images\":[\"sha256:aa\"],\"classes\":{}},{\"id\":\"3\",\"images\":[\"sha256:aa\"],\"classes\":{}}]}"),
    ("two runs are refused", lit "{\"runs\":[{\"id\":\"101\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":2,\"t\":3},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":500,\"tBound\":1000,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}},{\"id\":\"102\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":3,\"t\":1},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":2,\"t\":400,\"tBound\":990,\"unit\":\"px\"}}}]}"),
    ("mixed image digests are refused", lit "{\"runs\":[{\"id\":\"101\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":2,\"t\":3},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":500,\"tBound\":1000,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}},{\"id\":\"102\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":3,\"t\":1},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":2,\"t\":400,\"tBound\":990,\"unit\":\"px\"}}},{\"id\":\"103\",\"images\":[\"sha256:aa\",\"sha256:bb\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"stable\",\"k\":1,\"t\":0},\"b\":{\"class\":\"quarantined\",\"k\":9,\"t\":40},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":0,\"tBound\":1010,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}}]}"),
    ("a repeated workflow run id is refused", lit "{\"runs\":[{\"id\":\"101\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":2,\"t\":3},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":500,\"tBound\":1000,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}},{\"id\":\"102\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":3,\"t\":1},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":2,\"t\":400,\"tBound\":990,\"unit\":\"px\"}}},{\"id\":\"101\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"stable\",\"k\":1,\"t\":0},\"b\":{\"class\":\"quarantined\",\"k\":9,\"t\":40},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":0,\"tBound\":1010,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}}]}"),
    ("a run without an image digest is refused", lit "{\"runs\":[{\"id\":\"101\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":2,\"t\":3},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":500,\"tBound\":1000,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}},{\"id\":\"102\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":3,\"t\":1},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":2,\"t\":400,\"tBound\":990,\"unit\":\"px\"}}},{\"id\":\"103\",\"images\":[],\"classes\":{\"a\":{\"class\":\"stable\",\"k\":1,\"t\":0},\"b\":{\"class\":\"quarantined\",\"k\":9,\"t\":40},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":0,\"tBound\":1010,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}}]}"),
    ("an unknown class name is refused", lit "{\"runs\":[{\"id\":\"101\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":2,\"t\":3},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":500,\"tBound\":1000,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}},{\"id\":\"102\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":3,\"t\":1},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":2,\"t\":400,\"tBound\":990,\"unit\":\"px\"}}},{\"id\":\"103\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"shifting\",\"k\":1,\"t\":1}}}]}")])]

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

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

/-- A trace slice `{name, ph, ts, dur?}`. -/
def slice (name ph : String) (ts : Int) (dur : Option Int := none) : Json :=
  Json.mkObj ([("name", .str name), ("ph", .str ph), ("ts", toJson ts)] ++
    (match dur with | some d => [("dur", toJson d)] | none => []))

/-- One frame of a counts file: every required SPK-q key at 0 except the overrides; `drop` keys are left out. -/
def spkqFrame (over : List (String × Int)) (drop : List String := []) : Json :=
  let base := (Fw.Measure.Neutral.required.filter fun k => !(over.any (·.1 == k)) && !drop.contains k).map
    fun k => (k, (0 : Int))
  Json.mkObj [("counts", Json.mkObj ((base ++ over).map fun (k, v) => (k, toJson v)))]

/-- A counts file for `measure.spkq`: frames and `meta.n0` (`none`: no `meta`). -/
def spkqFile (n0 : Option (Bool × Nat × Nat × Nat)) (frames : List Json) : Json :=
  let tot (n : Nat) := Json.mkObj [("total", toJson n)]
  Json.mkObj ([("frames", .arr frames.toArray)] ++
    match n0 with
    | some (en, ld, pr, af) => [("meta", Json.mkObj [("n0", Json.mkObj
        [("enabled", .bool en), ("load", tot ld), ("preroll", tot pr), ("after", tot af)])])]
    | none => [])

/-- A class table entry `{class, k, t}`. -/
def cls (c : String) (k t : Nat) : Json := Json.mkObj [("class", .str c), ("k", toJson k), ("t", toJson t)]

/-- Parse a literal request (a parse error becomes a visible bad case). -/
def lit (s : String) : Json := (Json.parse s).toOption.getD (Json.mkObj [("unparsable", .str s)])

/-- The `jobs` of a `measure.freeze` run: job `i` is `chromium-counts-rewrite-r<i+1>` with the `i`-th frame
count and the `i`-th trajectory hash (`tr` when the list is shorter). -/
def jobsJ (frames : List Nat) (trs : List String := []) : Json :=
  .arr ((frames.zip (List.range frames.length)).toArray.map fun (f, i) => Json.mkObj
    [("name", .str s!"chromium-counts-rewrite-r{i + 1}"), ("frames", toJson f),
     ("trajectorySha256", .str (trs.getD i "tr"))])

/-- A `measure.freeze` request with three 409-frame jobs added to every run. -/
def withJobs (j : Json) : Json :=
  match j.getObjVal? "runs" with
  | .ok (.arr rs) => j.mergeObj (Json.mkObj [("runs", .arr (rs.map fun r =>
      r.mergeObj (Json.mkObj [("jobs", jobsJ [409, 409, 409])])))])
  | _ => j

/-- A `measure.freeze` run with one image digest, a two-type table and the given jobs. -/
def frun (id : String) (frames : List Nat) (trs : List String := []) : Json :=
  Json.mkObj [("id", .str id), ("images", .arr #[.str "sha256:aa"]),
    ("classes", Json.mkObj [("a", cls "deterministic" 0 0), ("b", cls "stable" 2 3)]),
    ("jobs", jobsJ frames trs)]

/-- A zone record `{id, frames, scrolledPx, firstFrame, lastFrame, sums}` for the `measure.zoneBaseline` cases. -/
def zrec (id : String) (fr : Nat) (px : Int) (a b : Nat) (sums : List (String × Int)) : Json :=
  Json.mkObj [("id", .str id), ("frames", toJson fr), ("scrolledPx", toJson px), ("firstFrame", toJson a),
    ("lastFrame", toJson b), ("sums", Json.mkObj (sums.map fun (k, v) => (k, toJson v)))]

/-- A run `{id, zones}` of two zones (`rest` 2 frames, `y00000` 3 frames, 400 px) with the given sums. -/
def zrun (id : String) (rest y0 : List (String × Int)) : Json :=
  Json.mkObj [("id", .str id), ("zones", .arr #[zrec "rest" 2 0 0 1 rest, zrec "y00000" 3 400 2 4 y0])]

/-- The frozen table of the `measure.zoneBaseline` cases: `a` deterministic, `b` stable, `q` quarantined
(extra fields as in `classes.frozen.json` are ignored). -/
def zbTable : Json := Json.mkObj [("a", cls "deterministic" 0 0), ("b", cls "stable" 2 3),
  ("q", Json.mkObj [("class", .str "quarantined"), ("k", toJson (9 : Nat)), ("t", toJson (9 : Nat)),
    ("perRun", .arr #[.str "quarantined"]), ("pooledClass", .str "quarantined")])]

/-- Three runs of the drift case: `a` (deterministic) differs in zone `y00000` of run 2, `b` varies,
`u` is unlisted and appears in run 3 only. -/
def zbRuns : List Json :=
  [zrun "r1" [("a", 4), ("b", 10)] [("a", 6), ("b", 7), ("q", 1)],
   zrun "r2" [("a", 4), ("b", 12)] [("a", 7), ("b", 5), ("q", 0)],
   zrun "r3" [("a", 4), ("b", 11)] [("a", 6), ("b", 9), ("q", 3), ("u", 2)]]

/-- A swipe-like frame list for the `measure.zoneBaseline` frames case. -/
def zbFrames (x : Int) : Json :=
  .arr #[Json.mkObj [("n", toJson (0 : Nat)), ("phase", .str "rest"), ("scrollY", toJson (0 : Nat)),
           ("counts", Json.mkObj [("a", toJson (1 : Nat)), ("b", toJson x)])],
         Json.mkObj [("n", toJson (1 : Nat)), ("phase", .str "swipe"), ("scrollY", toJson (300 : Nat)),
           ("counts", Json.mkObj [("a", toJson (2 : Nat)), ("b", toJson (1 : Nat))])],
         Json.mkObj [("n", toJson (2 : Nat)), ("phase", .str "swipe"), ("scrollY", toJson (700 : Nat)),
           ("counts", Json.mkObj [("a", toJson (3 : Nat))])]]

/-- A `measure.retry` request. -/
def retryReq (e : String) (a n : Nat) : Json :=
  Json.mkObj [("error", .str e), ("attempt", toJson a), ("max", toJson n)]

/-- A `measure.retryPlan` request. -/
def retryPlanReq (es : List String) (n : Nat) : Json :=
  Json.mkObj [("errors", .arr (es.toArray.map Json.str)), ("max", toJson n)]

/-- A `measure.viewport` request. -/
def viewportReq (pw ph ow oh : Nat) : Json :=
  Json.mkObj [("profile", Json.mkObj [("w", toJson pw), ("h", toJson ph)]),
              ("observed", Json.mkObj [("w", toJson ow), ("h", toJson oh)])]

/-- A `measure.simPlan` request (the commit is a fixed 40-character hex string). -/
def simPlanReq (target vms sessions preset fw experiment : String) : Json :=
  Json.mkObj [("target", .str target), ("vms", .str vms), ("sessions", .str sessions), ("preset", .str preset),
    ("fw", .str fw), ("experiment", .str experiment), ("sha", .str "0123456789abcdef0123456789abcdef01234567")]

/-- A `measure.inspector` request. -/
def inspectorReq (relaunched : Bool) (fails : Nat) (socket proxy page : Bool) : Json :=
  Json.mkObj [("relaunched", .bool relaunched), ("fails", toJson fails), ("socket", .bool socket), ("proxy", .bool proxy),
    ("page", .bool page)]

/-- A `measure.inspector` request that also names the outcome of the relaunch. -/
def inspectorRelaunchReq (relaunchOk : Bool) : Json :=
  Json.mkObj [("relaunched", .bool true), ("fails", toJson (0 : Nat)), ("socket", .bool true), ("proxy", .bool true),
    ("page", .bool true), ("relaunchOk", .bool relaunchOk)]

/-- A `measure.targetLost` request; `relaunchOk` names the outcome of the relaunch when given. -/
def targetReq (relaunched : Bool) (elapsedMs : Nat) (found : Bool) (relaunchOk : Option Bool := none) : Json :=
  Json.mkObj ([("relaunched", .bool relaunched), ("elapsedMs", toJson elapsedMs), ("found", .bool found)]
    ++ (relaunchOk.map fun b => [("relaunchOk", Json.bool b)]).getD [])

/-- A one-frame zone record of a `measure.compose` run. -/
def czone (id : String) (i : Nat) (sums : List (String × Int)) : Json :=
  Json.mkObj [("id", .str id), ("frames", toJson (1 : Nat)), ("scrolledPx", toJson (0 : Int)),
    ("firstFrame", toJson i), ("lastFrame", toJson i), ("sums", Json.mkObj (sums.map fun (k, v) => (k, toJson v)))]

/-- A `measure.compose` run: its variants and two zones. -/
def crun (vs : List (String × String)) (z0 z1 : List (String × Int)) : Json :=
  Json.mkObj [("variants", Json.mkObj (vs.map fun (k, v) => (k, .str v))),
    ("zones", .arr #[czone "y00000" 0 z0, czone "y00500" 1 z1])]

/-- Two base runs with variants `vs`; `fire` is the first run's `trace.FireAnimationFrame` in zone `y00000`. -/
def cbaseV (vs : List (String × String)) (fire : Int) : Json :=
  let z1 : List (String × Int) := [("trace.Layout.dirtyObjects", 10), ("census.layers", 5), ("trace.Layout", 4)]
  .arr #[crun vs [("trace.Layout.dirtyObjects", 10), ("census.layers", 5), ("trace.Layout", 4),
            ("trace.FireAnimationFrame", fire)] z1,
         crun vs [("trace.Layout.dirtyObjects", 10), ("census.layers", 5), ("trace.Layout", 4),
            ("trace.FireAnimationFrame", 4)] z1]

/-- Two faithful base runs. -/
def cbase (fire : Int) : Json := cbaseV [("a", "faithful"), ("b", "faithful")] fire

/-- Two equal arm runs with the given variants and sums. -/
def carm (vs : List (String × String)) (d0 d1 layers0 layout : Int) : Json :=
  let r := crun vs [("trace.Layout.dirtyObjects", d0), ("census.layers", layers0), ("trace.Layout", layout),
      ("trace.FireAnimationFrame", 4)]
    [("trace.Layout.dirtyObjects", d1), ("census.layers", 5), ("trace.Layout", layout)]
  .arr #[r, r]

/-- A `measure.compose` comparison. -/
def ccmp (id baseId : String) (base arm : Json) : Json :=
  Json.mkObj [("id", .str id), ("baseId", .str baseId), ("base", base), ("arm", arm)]

/-- The class table of the `measure.compose` cases. -/
def cclasses : Json := Json.mkObj [
  ("trace.Layout.dirtyObjects", cls "deterministic" 0 0), ("trace.FireAnimationFrame", cls "deterministic" 0 0),
  ("census.layers", cls "stable" 2 3), ("trace.Layout", cls "deterministic" 0 0),
  ("trace.FunctionCall", cls "quarantined" 0 0)]

/-- A `measure.compose` request. -/
def composeReq (comb : Json) (singles : List Json) : Json :=
  Json.mkObj [("classes", cclasses), ("combined", comb), ("singles", .arr singles.toArray)]

/-- The cases, per op file: (file stem, [(name, request without op)]). -/
def cases (_ : Unit := ()) : List (String × List (String × Json)) := [
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
  ("measure.webkit.align", [
    ("the longer run A against the shorter B (zones of 100 px): the first zone is full, the second has one paired step, the third only A", lit "{\"a\":{\"ys\":[0,50,100,150,200,250],\"perStep\":[[1,0],[2,1],[3,0],[4,1],[5,0],[6,1]],\"perStepPaintArea\":[10,20,30,40,50,60]},\"b\":{\"ys\":[0,50,100,150],\"perStep\":[[1,0],[2,1],[2,0],[9,9]],\"perStepPaintArea\":[10,20,25,5]},\"zonePx\":100}"),
    ("the arms exchanged give the swapped zones and negated deltas", lit "{\"a\":{\"ys\":[0,50,100,150],\"perStep\":[[1,0],[2,1],[2,0],[9,9]],\"perStepPaintArea\":[10,20,25,5]},\"b\":{\"ys\":[0,50,100,150,200,250],\"perStep\":[[1,0],[2,1],[3,0],[4,1],[5,0],[6,1]],\"perStepPaintArea\":[10,20,30,40,50,60]},\"zonePx\":100}"),
    ("a run against itself: every zone is full, delta 0", lit "{\"a\":{\"ys\":[0,50,100,150],\"perStep\":[[1,0],[2,1],[2,0],[9,9]],\"perStepPaintArea\":[10,20,25,5]},\"b\":{\"ys\":[0,50,100,150],\"perStep\":[[1,0],[2,1],[2,0],[9,9]],\"perStepPaintArea\":[10,20,25,5]},\"zonePx\":100}"),
    ("offsets that never coincide pair nothing", lit "{\"a\":{\"ys\":[0,30],\"perStep\":[[1],[1]],\"perStepPaintArea\":[0,0]},\"b\":{\"ys\":[10,40],\"perStep\":[[2],[2]],\"perStepPaintArea\":[0,0]}}"),
    ("no steps in B", lit "{\"a\":{\"ys\":[0],\"perStep\":[[1]],\"perStepPaintArea\":[0]},\"b\":{\"ys\":[],\"perStep\":[],\"perStepPaintArea\":[]}}"),
    ("offsets must increase strictly", lit "{\"a\":{\"ys\":[0,0],\"perStep\":[[1],[1]],\"perStepPaintArea\":[0,0]},\"b\":{\"ys\":[0],\"perStep\":[[1]],\"perStepPaintArea\":[0]}}"),
    ("a negative offset is refused", lit "{\"a\":{\"ys\":[-1],\"perStep\":[[1]],\"perStepPaintArea\":[0]},\"b\":{\"ys\":[0],\"perStep\":[[1]],\"perStepPaintArea\":[0]}}")]),
  ("measure.webkit.pairRows", [
    ("a state label only some sessions have (census y=5268 on one VM) is unpaired with its session count; the rest is paired in the first session's order", lit "{\"sessions\":[[\"scroll|Layout|total\",\"census|layerCount|y=5267\",\"scroll|Layout|per step\"],[\"scroll|Layout|total\",\"census|layerCount|y=5268\",\"scroll|Layout|per step\"],[\"scroll|Layout|total\",\"census|layerCount|y=5267\",\"scroll|Layout|per step\"]]}"),
    ("identical sessions pair everything", lit "{\"sessions\":[[\"a\",\"b\"],[\"a\",\"b\"]]}"),
    ("one session pairs everything", lit "{\"sessions\":[[\"a\",\"b\"]]}"),
    ("a key missing from the first session only is unpaired, counted in the others", lit "{\"sessions\":[[\"a\"],[\"a\",\"b\"],[\"a\",\"b\"]]}"),
    ("nothing in common: nothing paired, every key unpaired once", lit "{\"sessions\":[[\"a\"],[\"b\"]]}"),
    ("no sessions is refused", lit "{\"sessions\":[]}")]),
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
  ("measure.freeze", ([
    ("worst class per type over three runs; a type missing from a run is quarantined; k, t maxima; tBound the smallest; pooled class and tally", lit "{\"runs\":[{\"id\":\"101\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":2,\"t\":3},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":500,\"tBound\":1000,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}},{\"id\":\"102\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":3,\"t\":1},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":2,\"t\":400,\"tBound\":990,\"unit\":\"px\"}}},{\"id\":\"103\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"stable\",\"k\":1,\"t\":0},\"b\":{\"class\":\"quarantined\",\"k\":9,\"t\":40},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":0,\"tBound\":1010,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}}],\"pooled\":{\"a\":{\"class\":\"stable\",\"k\":1,\"t\":0},\"b\":{\"class\":\"quarantined\",\"k\":9,\"t\":40},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":2,\"t\":500,\"tBound\":990,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}}"),
    ("the same runs in another order give the same classes (perRun follows the run order)", lit "{\"runs\":[{\"id\":\"103\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"stable\",\"k\":1,\"t\":0},\"b\":{\"class\":\"quarantined\",\"k\":9,\"t\":40},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":0,\"tBound\":1010,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}},{\"id\":\"101\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":2,\"t\":3},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":500,\"tBound\":1000,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}},{\"id\":\"102\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":3,\"t\":1},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":2,\"t\":400,\"tBound\":990,\"unit\":\"px\"}}}]}"),
    ("three copies of one table give that table", lit "{\"runs\":[{\"id\":\"101\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":2,\"t\":3},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":500,\"tBound\":1000,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}},{\"id\":\"201\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":2,\"t\":3},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":500,\"tBound\":1000,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}},{\"id\":\"202\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":2,\"t\":3},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":500,\"tBound\":1000,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}}]}"),
    ("no types", lit "{\"runs\":[{\"id\":\"1\",\"images\":[\"sha256:aa\"],\"classes\":{}},{\"id\":\"2\",\"images\":[\"sha256:aa\"],\"classes\":{}},{\"id\":\"3\",\"images\":[\"sha256:aa\"],\"classes\":{}}]}"),
    ("two runs are refused", lit "{\"runs\":[{\"id\":\"101\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":2,\"t\":3},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":500,\"tBound\":1000,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}},{\"id\":\"102\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":3,\"t\":1},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":2,\"t\":400,\"tBound\":990,\"unit\":\"px\"}}}]}"),
    ("mixed image digests are refused", lit "{\"runs\":[{\"id\":\"101\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":2,\"t\":3},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":500,\"tBound\":1000,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}},{\"id\":\"102\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":3,\"t\":1},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":2,\"t\":400,\"tBound\":990,\"unit\":\"px\"}}},{\"id\":\"103\",\"images\":[\"sha256:aa\",\"sha256:bb\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"stable\",\"k\":1,\"t\":0},\"b\":{\"class\":\"quarantined\",\"k\":9,\"t\":40},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":0,\"tBound\":1010,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}}]}"),
    ("a repeated workflow run id is refused", lit "{\"runs\":[{\"id\":\"101\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":2,\"t\":3},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":500,\"tBound\":1000,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}},{\"id\":\"102\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":3,\"t\":1},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":2,\"t\":400,\"tBound\":990,\"unit\":\"px\"}}},{\"id\":\"101\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"stable\",\"k\":1,\"t\":0},\"b\":{\"class\":\"quarantined\",\"k\":9,\"t\":40},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":0,\"tBound\":1010,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}}]}"),
    ("a run without an image digest is refused", lit "{\"runs\":[{\"id\":\"101\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":2,\"t\":3},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":500,\"tBound\":1000,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}},{\"id\":\"102\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":3,\"t\":1},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":2,\"t\":400,\"tBound\":990,\"unit\":\"px\"}}},{\"id\":\"103\",\"images\":[],\"classes\":{\"a\":{\"class\":\"stable\",\"k\":1,\"t\":0},\"b\":{\"class\":\"quarantined\",\"k\":9,\"t\":40},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":0,\"tBound\":1010,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}}]}"),
    ("an unknown class name is refused", lit "{\"runs\":[{\"id\":\"101\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":2,\"t\":3},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":1,\"t\":500,\"tBound\":1000,\"unit\":\"px\"},\"gone\":{\"class\":\"deterministic\",\"k\":0,\"t\":0}}},{\"id\":\"102\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"deterministic\",\"k\":0,\"t\":0},\"b\":{\"class\":\"stable\",\"k\":3,\"t\":1},\"x.drawAreaPx\":{\"class\":\"stable\",\"k\":2,\"t\":400,\"tBound\":990,\"unit\":\"px\"}}},{\"id\":\"103\",\"images\":[\"sha256:aa\",\"sha256:aa\",\"sha256:aa\"],\"classes\":{\"a\":{\"class\":\"shifting\",\"k\":1,\"t\":1}}}]}"),
    ("the overlay-ad hit-test type has role byDesign (with its reason) whatever its class; quarantined types are findings, the others gate",
      let run (id : String) (o : String) := Json.mkObj [("id", .str id), ("images", .arr #[.str "sha256:aa"]),
        ("classes", Json.mkObj [("trace.HitTest", cls "deterministic" 0 0),
          ("trace.HitTest.overlayAdDetector", cls o 2 2), ("trace.Paint", cls "stable" 1 1),
          ("trace.MinorGC", cls "quarantined" 9 9)])]
      Json.mkObj [("runs", .arr #[run "1" "deterministic", run "2" "stable", run "3" "quarantined"])])]
    : List (String × Json)).map (fun (n, j) => (n, withJobs j)) ++ [
    ("a job with 403 frames among 409-frame jobs is refused; the refusal names that job and its run (CI run 39049478836)",
      Json.mkObj [("runs", .arr #[frun "39049471997" [409, 409, 409], frun "39049478836" [409, 403, 409],
        frun "39049481754" [409, 409, 409]])]),
    ("the odd job is named when it is the first job; every job whose count is not the most frequent one is named",
      Json.mkObj [("runs", .arr #[frun "1" [403, 409, 409], frun "2" [409, 409, 409], frun "3" [409, 409, 410]])]),
    ("a run without jobs is refused",
      Json.mkObj [("runs", .arr #[frun "1" [409], frun "2" [409], frun "3" []])]),
    ("a run without the jobs field is refused",
      Json.mkObj [("runs", .arr #[frun "1" [409], frun "2" [409],
        Json.mkObj [("id", .str "3"), ("images", .arr #[.str "sha256:aa"]), ("classes", Json.mkObj [])]])]),
    ("one frame count, different trajectories (touch): accepted, trajectoriesEqual false",
      Json.mkObj [("runs", .arr #[frun "1" [531, 531, 531] ["t1", "t1", "t1"], frun "2" [531, 531, 531] ["t1", "t2", "t1"],
        frun "3" [531, 531, 531] ["t1", "t1", "t1"]])])]),
  ("measure.splits", [
    ("HitTest inside the detector and a style update inside an SVG host move to the split types (ends included); B and I phases, slices past the end and slices outside stay; E is not counted",
      Json.mkObj [("slices", .arr #[
        slice "OverlayInterstitialAdDetector::MaybeFireDetection" "X" 1000 (some 100),
        slice "HitTest" "X" 1010 (some 20), slice "HitTest" "X" 1090 (some 10), slice "HitTest" "X" 1095 (some 10),
        slice "HitTest" "B" 1020, slice "HitTest" "E" 1030, slice "HitTest" "X" 2000 (some 5),
        slice "IsolatedSVGDocumentHost::IsolatedSVGDocumentHost" "X" 3000 (some 50),
        slice "StyleEngine::updateActiveStyleSheets" "X" 3010 (some 5),
        slice "StyleEngine::updateActiveStyleSheets" "I" 3020,
        slice "StyleEngine::updateActiveStyleSheets" "X" 4000 (some 5)])]),
    ("an outer slice that is not complete (B) moves nothing",
      Json.mkObj [("slices", .arr #[
        slice "OverlayInterstitialAdDetector::MaybeFireDetection" "B" 1000,
        slice "HitTest" "X" 1010 (some 20),
        slice "IsolatedSVGDocumentHost::IsolatedSVGDocumentHost" "I" 3000,
        slice "StyleEngine::updateActiveStyleSheets" "X" 3000 (some 0)])]),
    ("an outer slice without dur is the single instant ts; a zero-length slice at that instant is inside",
      Json.mkObj [("slices", .arr #[
        slice "OverlayInterstitialAdDetector::MaybeFireDetection" "X" 500,
        slice "HitTest" "X" 500 (some 0), slice "HitTest" "X" 500 (some 1)])]),
    ("no slices", Json.mkObj [("slices", .arr #[])]),
    ("a non-integer ts is refused", lit "{\"slices\":[{\"name\":\"HitTest\",\"ph\":\"X\",\"ts\":1.5}]}")]),
  ("measure.n0Windows", [
    ("the pure.test.mjs case: load, two pre-roll events, one per frame, after",
      lit "{\"events\":[{\"kind\":\"cssom.sheet\",\"vt\":5},{\"kind\":\"cssom.sheet\",\"vt\":20050},{\"kind\":\"cssom.sheet\",\"vt\":20090},{\"kind\":\"sheetNode.added\",\"vt\":20095},{\"kind\":\"cssom.keyframes\",\"vt\":20110},{\"kind\":\"sheetNode.text\",\"vt\":20111},{\"kind\":\"cssom.sheet\",\"vt\":20999}],\"frameVts\":[20100,20110,20120],\"startVt\":20000,\"dt\":10}"),
    ("an event between two frames goes to the later one; within 1/1000 after a frame still counts to it; adoptedStyleSheets is CSSOM",
      lit "{\"events\":[{\"kind\":\"adoptedStyleSheets\",\"vt\":-1},{\"kind\":\"sheetNode.removed\",\"vt\":84},{\"kind\":\"adoptedStyleSheets\",\"vt\":84.5},{\"kind\":\"cssom.insertRule\",\"vt\":100.5},{\"kind\":\"sheetNode.added\",\"vt\":116},{\"kind\":\"cssom.deleteRule\",\"vt\":132.0005},{\"kind\":\"sheetNode.text\",\"vt\":132.25}],\"frameVts\":[100,116,132],\"startVt\":0,\"dt\":16}"),
    ("no recorded frames: before the start is load, up to the start is pre-roll, later is after",
      lit "{\"events\":[{\"kind\":\"cssom.sheet\",\"vt\":10},{\"kind\":\"cssom.sheet\",\"vt\":50},{\"kind\":\"cssom.sheet\",\"vt\":51}],\"frameVts\":[],\"startVt\":50,\"dt\":16}"),
    ("decreasing frame times are refused",
      lit "{\"events\":[],\"frameVts\":[116,100],\"startVt\":0,\"dt\":16}")]),
  ("measure.spkq", [
    ("pass: census on, nothing in pre-roll or after, every required key 0 in every frame (the SVG-image type does not count; load does not count)",
      spkqFile (some (true, 12, 0, 0)) [spkqFrame [], spkqFrame [("trace.N1.svgImageDocument", 3)]]),
    ("pass: the SVG-image type need not be recorded",
      spkqFile (some (true, 0, 0, 0)) [spkqFrame [] ["trace.N1.svgImageDocument"]]),
    ("fail: a CSSOM write in frame 1",
      spkqFile (some (true, 0, 0, 0)) [spkqFrame [], spkqFrame [("n0.events", 1), ("n0.cssom", 1)]]),
    ("fail: a style-sheet update in frame 0",
      spkqFile (some (true, 0, 0, 0)) [spkqFrame [("trace.N1.updateActiveStyleSheets", 2)], spkqFrame []]),
    ("fail: events in the pre-roll",
      spkqFile (some (true, 0, 2, 0)) [spkqFrame []]),
    ("fail: events after the last frame",
      spkqFile (some (true, 0, 0, 1)) [spkqFrame []]),
    ("missing: a frame does not record a required key",
      spkqFile (some (true, 0, 0, 0)) [spkqFrame [], spkqFrame [] ["trace.N1.fontUpdateInvalidation"]]),
    ("missing: the census was off", spkqFile (some (false, 0, 0, 0)) [spkqFrame []]),
    ("missing: no meta", spkqFile none [spkqFrame []]),
    ("missing: no frames", spkqFile (some (true, 0, 0, 0)) []),
    ("a census without window totals is refused",
      lit "{\"frames\":[],\"meta\":{\"n0\":{\"enabled\":true}}}")]),
  ("measure.zoneBaseline", [
    ("drift: a deterministic type differs in one zone; stable, quarantined and unlisted types; a missing type is 0",
      Json.mkObj [("classes", zbTable), ("runs", .arr zbRuns.toArray)]),
    ("the same runs reordered: lo, hi, base, classes and drift unchanged, perRun reordered",
      Json.mkObj [("classes", zbTable), ("runs", .arr zbRuns.reverse.toArray)]),
    ("four runs: base is the lower median (sorted index 1)",
      Json.mkObj [("classes", zbTable), ("runs", .arr (zbRuns ++ [zrun "r4" [("a", 4), ("b", 13)] [("a", 6), ("b", 8)]]).toArray)]),
    ("runs given as frames (zoneHeightPx 500): equal deterministic sums, no drift",
      Json.mkObj [("classes", zbTable), ("zoneHeightPx", toJson (500 : Nat)), ("runs", .arr #[
        Json.mkObj [("id", .str "a"), ("frames", zbFrames 5)], Json.mkObj [("id", .str "b"), ("frames", zbFrames 6)],
        Json.mkObj [("id", .str "c"), ("frames", zbFrames 5)]])]),
    ("an empty class table: every type is unlisted (rule quarantined)",
      Json.mkObj [("classes", Json.mkObj []), ("runs", .arr zbRuns.toArray)]),
    ("two runs are refused",
      Json.mkObj [("classes", zbTable), ("runs", .arr (zbRuns.take 2).toArray)]),
    ("a repeated run id is refused",
      Json.mkObj [("classes", zbTable), ("runs", .arr #[zrun "r1" [] [], zrun "r2" [] [], zrun "r1" [] []])]),
    ("a different zone structure (frames of a zone) is refused",
      Json.mkObj [("classes", zbTable), ("runs", .arr #[zrun "r1" [] [], zrun "r2" [] [],
        Json.mkObj [("id", .str "r3"), ("zones", .arr #[zrec "rest" 2 0 0 1 [], zrec "y00000" 4 400 2 5 []])]])]),
    ("a repeated zone id is refused",
      Json.mkObj [("classes", zbTable), ("runs", .arr ((List.range 3).toArray.map fun i =>
        Json.mkObj [("id", .str s!"r{i}"), ("zones", .arr #[zrec "rest" 1 0 0 0 [], zrec "rest" 1 0 1 1 []])]))]),
    ("frames without zoneHeightPx are refused",
      Json.mkObj [("classes", zbTable), ("runs", .arr ((List.range 3).toArray.map fun i =>
        Json.mkObj [("id", .str s!"r{i}"), ("frames", zbFrames 1)]))]),
    ("a run with both frames and zones is refused",
      Json.mkObj [("classes", zbTable), ("zoneHeightPx", toJson (500 : Nat)), ("runs", .arr #[zrun "r1" [] [], zrun "r2" [] [],
        Json.mkObj [("id", .str "r3"), ("frames", zbFrames 1), ("zones", .arr #[])]])])]),
  ("measure.arms", [
    ("a type on one arm takes that arm's class; both arms: the worse; the overlay-ad type is byDesign; quarantined types are findings",
      Json.mkObj [("a", Json.mkObj [("trace.HitTest", cls "deterministic" 0 0),
          ("trace.HitTest.overlayAdDetector", cls "quarantined" 5 5), ("trace.Paint", cls "stable" 1 1),
          ("only.a", cls "quarantined" 9 9)]),
        ("r", Json.mkObj [("trace.HitTest", cls "stable" 2 2), ("trace.Paint", cls "deterministic" 0 0),
          ("only.r", cls "deterministic" 0 0)])]),
    ("both arms empty", Json.mkObj [("a", Json.mkObj []), ("r", Json.mkObj [])]),
    ("an unknown class name is refused",
      Json.mkObj [("a", Json.mkObj [("x", cls "shifting" 0 0)]), ("r", Json.mkObj [])])]),
  ("measure.quietSteps", [
    ("limit 30: the slow step 1 of pass 0 is left out; a differing count on step 1 no longer counts; one differing count on kept step 2 is stable",
      Json.mkObj [("limit", toJson (30 : Nat)), ("minKept", toJson (2 : Nat)),
        ("tol", Json.mkObj [("absTol", toJson (1 : Nat)), ("relTol", toJson (0 : Nat))]),
        ("durs", lit "[[5,90,7],[9,3,11]]"),
        ("series", lit "[{\"type\":\"a\",\"runs\":[[1,2,3],[1,9,4]]},{\"type\":\"b\",\"runs\":[[1,2,3],[1,9,3]]},{\"type\":\"c\",\"runs\":[[1,2,3],[1,2,6]]}]")]),
    ("limit 100: every step is kept, the class is the plain cell class",
      Json.mkObj [("limit", toJson (100 : Nat)), ("minKept", toJson (1 : Nat)),
        ("tol", Json.mkObj [("absTol", toJson (1 : Nat)), ("relTol", toJson (0 : Nat))]),
        ("durs", lit "[[5,90,7],[9,3,11]]"),
        ("series", lit "[{\"type\":\"b\",\"runs\":[[1,2,3],[1,9,3]]}]")]),
    ("fewer than minKept quiet steps: not enough, no classes",
      Json.mkObj [("limit", toJson (10 : Nat)), ("minKept", toJson (3 : Nat)),
        ("tol", Json.mkObj [("absTol", toJson (1 : Nat)), ("relTol", toJson (0 : Nat))]),
        ("durs", lit "[[5,90,7],[9,3,11]]"),
        ("series", lit "[{\"type\":\"b\",\"runs\":[[1,2,3],[1,9,3]]}]")]),
    ("no series: only the kept steps; passes of different length use the shortest",
      Json.mkObj [("limit", toJson (10 : Nat)), ("minKept", toJson (1 : Nat)),
        ("durs", lit "[[5,6,7,8],[9,3]]")]),
    ("a non-natural duration is refused",
      Json.mkObj [("limit", toJson (10 : Nat)), ("minKept", toJson (1 : Nat)), ("durs", lit "[[5,-1]]")])]),
  ("measure.retry", [
    ("a simctl call killed at its deadline (ETIMEDOUT) is transient: retried after the first attempt, wait 2 s",
      retryReq "ETIMEDOUT" 1 3),
    ("the wait doubles: second failure, wait 4 s", retryReq "simctl launch Safari failed: ETIMEDOUT" 2 3),
    ("the limit is reached: not retried even though transient", retryReq "ETIMEDOUT" 3 3),
    ("boot message from simctl is transient, case ignored",
      retryReq "simctl boot failed: UNABLE TO BOOT device in current state: Booted" 1 3),
    ("device busy is transient", retryReq "Device busy, try again" 1 2),
    ("the wait stops growing at the cap (30 s)", retryReq "operation timed out" 9 10),
    ("an unknown device is permanent: never retried", retryReq "Invalid device: fw-iphone-27" 1 3),
    ("an empty message is permanent", retryReq "" 1 3),
    ("a limit of 1 never retries", retryReq "ETIMEDOUT" 1 1),
    ("attempt 0 is refused", retryReq "ETIMEDOUT" 0 3)]),
  ("measure.retryPlan", [
    ("one timeout, then the call works: one retry, succeeded", retryPlanReq ["ETIMEDOUT"] 3),
    ("timeouts to the limit: waits 2 s and 4 s, exhausted", retryPlanReq ["ETIMEDOUT", "ETIMEDOUT", "ETIMEDOUT"] 3),
    ("a permanent error after a timeout ends the plan", retryPlanReq ["ETIMEDOUT", "No such app: x", "ETIMEDOUT"] 5),
    ("a permanent first error: no retry", retryPlanReq ["Invalid device: x"] 3),
    ("no failure at all", retryPlanReq [] 3),
    ("six timeouts, limit 8: waits double up to the cap",
      retryPlanReq ["ETIMEDOUT", "ETIMEDOUT", "ETIMEDOUT", "ETIMEDOUT", "ETIMEDOUT", "ETIMEDOUT"] 8)]),
  ("measure.viewport", [
    ("the profile viewport is kept", viewportReq 430 932 430 932),
    ("a zoomed-out layout viewport (the measured 645 x 1398) is refused", viewportReq 430 932 645 1398),
    ("only the width grew", viewportReq 430 932 645 932),
    ("only the height grew", viewportReq 430 932 430 1398),
    ("a smaller viewport is refused too", viewportReq 430 932 320 932)]),
  ("measure.simPlan", [
    ("the defaults: the original arm only, no query", simPlanReq "original" "1" "1" "original" "" "determinism"),
    ("both arms, one VM, the flag in the query of the rewrite arm only",
      simPlanReq "both" "1" "1" "original" "hero.countdown:strip" "determinism"),
    ("both arms, two VMs: v1 r1 v2 r2, each r paired with its v", simPlanReq "both" "2" "2" "original" "" "determinism"),
    ("the rewrite arm alone with a preset and flags",
      simPlanReq "rewrite" "1" "1" "strip-demo" "hero.countdown:strip,nav.hitTest:hit-skip" "determinism"),
    ("a preset without flags", simPlanReq "both" "1" "1" "strip-demo" "" "determinism"),
    ("flags need an arm that serves the rewrite", simPlanReq "original" "1" "1" "original" "hero.countdown:strip" "determinism"),
    ("a preset needs an arm that serves the rewrite", simPlanReq "original" "1" "1" "strip-demo" "" "determinism"),
    ("the quiet experiment measures the original only", simPlanReq "both" "1" "1" "original" "" "quiet"),
    ("quiet on the original is accepted", simPlanReq "original" "1" "1" "original" "" "quiet"),
    ("a malformed flag item is refused", simPlanReq "both" "1" "1" "original" "hero.countdown" "determinism"),
    ("a part twice is refused", simPlanReq "both" "1" "1" "original" "a.b:c,a.b:d" "determinism"),
    ("parts out of order are refused", simPlanReq "both" "1" "1" "original" "nav.hitTest:hit-skip,hero.countdown:strip" "determinism"),
    ("an unknown target, four VMs and zero sessions are all listed", simPlanReq "neither" "4" "0" "original" "" "determinism"),
    ("a leading zero is not a count", simPlanReq "both" "01" "1" "original" "" "determinism"),
    ("two determinism sessions: step 70 min, job 80 min", simPlanReq "original" "1" "2" "original" "" "determinism"),
    ("four sessions: step 140 min", simPlanReq "original" "1" "4" "original" "" "determinism"),
    ("quiet keeps the fixed 50 min step whatever the sessions", simPlanReq "original" "1" "3" "original" "" "quiet")]),
  ("measure.inspector", [
    ("all three alive: proceed, count reset", inspectorReq false 1 true true true),
    ("first failed probe (proxy refused or silent): proceed, count 1", inspectorReq false 0 true false true),
    ("first failed probe (Safari gone, page tab missing): proceed, count 1", inspectorReq false 0 true true false),
    ("second failed probe in a row (proxy): relaunch Safari", inspectorReq false 1 true false true),
    ("second failed probe in a row (page tab missing): relaunch Safari", inspectorReq false 1 true true false),
    ("no socket on the first probe: relaunch Safari", inspectorReq false 0 false true true),
    ("no socket after the relaunch: give up", inspectorReq true 0 false true true),
    ("second failed probe in a row after the relaunch (page tab missing): give up", inspectorReq true 1 true true false),
    ("first failed probe after the relaunch: proceed", inspectorReq true 0 true false false),
    ("healthy after the relaunch: proceed", inspectorReq true 1 true true true),
    ("the relaunch worked: go on", inspectorRelaunchReq true),
    ("the relaunch failed: give up", inspectorRelaunchReq false)]),
  ("measure.simBounds", [("the time constants of the dead-inspector and lost-target paths", Json.mkObj [])]),
  ("measure.targetLost", [
    ("a found target connects", targetReq false 12000 true),
    ("a found target connects after the relaunch", targetReq true 80000 true),
    ("no target at the start: wait", targetReq false 0 false),
    ("no target one ms inside the bound: wait, the poll may take 1 ms", targetReq false 479999 false),
    ("no target at 480 s: relaunch", targetReq false 480000 false),
    ("no target at 876 s (the lost runs): relaunch", targetReq false 876000 false),
    ("no target after the relaunch, inside its bound: wait", targetReq true 89999 false),
    ("no target after the relaunch at 90 s: fail the session", targetReq true 90000 false),
    ("a working relaunch goes back to the wait", targetReq false 480000 false (some true)),
    ("a failed relaunch fails the session", targetReq false 480000 false (some false))]),
  ("measure.compose",
    let comb := carm [("a", "x"), ("b", "y")] 5 4 9 2
    let sa := carm [("a", "x"), ("b", "faithful")] 7 9 6 3
    let sb := carm [("a", "faithful"), ("b", "y")] 8 10 7 3
    [("every verdict: composes, coupled, quarantined, no zone margin, drift, reported",
       composeReq (ccmp "C" "B" (cbase 3) comb) [ccmp "A" "B" (cbase 3) sa, ccmp "Bs" "B" (cbase 3) sb]),
     ("a single on another base and an unclean single leave flag b missing",
       composeReq (ccmp "C" "B" (cbase 4) comb) [ccmp "A" "B" (cbase 4) sa, ccmp "Bs" "B2" (cbase 4) sb,
         ccmp "Bu" "B" (cbase 4) (.arr #[crun [("b", "y")] [] [], crun [("a", "x"), ("b", "y")] [] []])]),
     ("a combined comparison without arm runs is refused", composeReq (ccmp "C" "B" (cbase 4) (.arr #[])) []),
     ("a combined adding one flag is refused, also with itself listed as its single",
       composeReq (ccmp "A" "B" (cbase 3) sa) [ccmp "A" "B" (cbase 3) sa]),
     ("a base with a shell part names it in baseFlags; the arms add only a and b",
       let sh := ("c", "shell")
       composeReq (ccmp "C" "B" (cbaseV [("a", "faithful"), ("b", "faithful"), sh] 3)
           (carm [("a", "x"), ("b", "y"), sh] 5 4 9 2))
         [ccmp "A" "B" (cbaseV [("a", "faithful"), ("b", "faithful"), sh] 3) (carm [("a", "x"), ("b", "faithful"), sh] 7 9 6 3),
          ccmp "Bs" "B" (cbaseV [("a", "faithful"), ("b", "faithful"), sh] 3) (carm [("a", "faithful"), ("b", "y"), sh] 8 10 7 3)])])]

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

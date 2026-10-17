import Lean.Data.Json
import Fw.Measure.WebKit
import Fw.Measure.SelfCheck
import Fw.Measure.Snapshot
import Fw.Measure.Freeze
import Fw.Measure.Neutral
import Fw.Measure.Arms
/-!
# JSON codecs and ops of the measurement lanes (`measure.*`)

The glue between `fwcore`'s JSON lines and `Fw.Measure` (namespace `Fw.Wire.Measure`, so the
math view treats it as wire code, like `Fw.Wire`). Total decoders only (`Except String`); no
partial operations. Integers are refused when not integral; times, offsets, clip coordinates and
tolerances are read as exact decimals (`JsonNumber` = mantissa · 10^(−exponent)).

| op | request | reply |
|---|---|---|
| `measure.zoneSums` | `zoneHeightPx` (≥ 1), `frames` [{n, phase, scrollY, counts}] | `zones` [{id, frames, scrolledPx, firstFrame, lastFrame, sums}] |
| `measure.classify` (`mode` `frames`) | `kMax`, `tMax`, `runs` (≥ 2; each an array of frames or an object with `frames`), optional `pxRel` {num, den ≥ 1} (default 1/1000) | `classes` {type: {class, k, t}} (+ `unit` `px` and `tBound` for `*AreaPx` types), `runs` |
| `measure.classify` (`mode` `cells`) | `tol` {absTol, relTol}, `runs` (≥ 2 integer arrays) | `cls`, `cells`, `differingCells`, `cellsBeyondTolerance`, `maxSpread`, `maxRelSpread`, `k`, `t` (+ `reason`) |
| `measure.noMoreWork` | `types` [{class: {class, k, t}, base, var}] | `noMoreWork`, `failing` (indices) |
| `measure.webkit.tally` | `rows` (raw `fw.webkit.records/1` rows) | `counts`, `paintArea`, `other` |
| `measure.webkit.reduceSteps` | `rows`, `marks` (non-empty, non-decreasing), `endTime` | `countTypes`, `perStep`, `perStepPaintArea`, `total`, `other`, `rowsBeforeFirstStep` |
| `measure.webkit.zones` | `ys` (≥ 0), `perStep`, `perStepPaintArea`, `zonePx` (default 500) | `zones` [{zone, y0, steps, counts, paintArea}] |
| `measure.symDiff` | `a`, `b` (string arrays) | `symDiff` |
| `measure.summarize` | `rows` [{family, metric, level, cls}] | `summary` [{family, metric, levels, worst}] |
| `measure.selfCheck` | `runs` (≥ 1; each an array of frames {phase, scrollY, counts} or an object with `frames`) | `rows` [{type, class, maxDiffFrames, spread, totals}], `frames`, `framesAligned`, `runs` |
| `measure.freeze` | `runs` (≥ 3, distinct `id`s) [{id, images (≥ 1 digest, all runs one digest), classes {type: {class, k, t, tBound?}}}], optional `pooled` {type: {class, k, t, tBound?}} | `image`, `runs` (ids), `types` {type: {class, k, t, perRun (class or `missing`), `unit` `px` + `tBound` for `*AreaPx` types, `pooledClass`?, `role` (`gate`, `finding`, `byDesign`), `reason`?}}, `tally`, `roles`, `pooledTally`? |
| `measure.splits` | `slices` [{name, ph, ts, dur?}] (integer µs) | `splits` [{name, within, base, key}], `n1Keys`, `n1Excluded`, `n1Gated`, `counts` {base and split types} |
| `measure.n0Windows` | `events` [{kind, vt}], `frameVts` (non-decreasing), `startVt`, `dt` | `windows` (per event: `load`, `preroll`, `after` or a frame index), `load`, `preroll`, `after`, `frames` [{n0.events, n0.cssom, n0.sheetNode}] |
| `measure.spkq` | a counts file: `frames` [{counts}], optional `meta.n0` {enabled, load, preroll, after {total}} | `verdict` (`pass`, `fail`, `missing`), `required`, `n1Gated`, `n1Excluded`, `unrecorded`, `nonzeroN0`, `nonzeroN1` (frame indices), `preroll`?, `after`? |
| `measure.arms` | `a`, `r` (class tables {type: {class, k, t, tBound?}} of the original and the rewrite) | `types` {type: {a, r (class or `absent`), class (cross-arm), role, reason?}}, `gates`, `roles` |
| `measure.snapshotCounts` | `snapshot` (`args.snapshot` of `LayerTreeHostImpl:snapshot`; a non-object is empty) | `counts` {census.\*, raster.\*} |
-/
namespace Fw.Wire.Measure
open Lean Fw.Measure Fw.Measure.WebKit

/-- The fields of a reply. -/
abbrev Reply := List (String × Json)

/-- A required field. -/
def field (j : Json) (k : String) : Except String Json :=
  match j.getObjVal? k with
  | .ok v => .ok v
  | .error _ => .error s!"missing field {k}"

/-- An optional field (`null` counts as absent). -/
def opt (j : Json) (k : String) : Option Json :=
  match j.getObjVal? k with
  | .ok .null => none
  | .ok v => some v
  | .error _ => none

/-- A JSON value as an array. -/
def asArr (k : String) : Json → Except String (Array Json)
  | .arr a => .ok a
  | _ => .error s!"field {k}: expected an array"

/-- A JSON value as a string. -/
def asStr (k : String) : Json → Except String String
  | .str s => .ok s
  | _ => .error s!"field {k}: expected a string"

/-- A JSON value as an integer. -/
def asInt (k : String) (j : Json) : Except String Int :=
  match j.getInt? with
  | .ok n => .ok n
  | .error _ => .error s!"field {k}: expected an integer"

/-- A JSON value as a natural number. -/
def asNat (k : String) (j : Json) : Except String Nat :=
  match j.getNat? with
  | .ok n => .ok n
  | .error _ => .error s!"field {k}: expected a non-negative integer"

/-- A JSON number as an exact rational. -/
def asRat (k : String) : Json → Except String Rat
  | .num n => .ok (mkRat n.mantissa (10 ^ n.exponent))
  | _ => .error s!"field {k}: expected a number"

/-- A required natural field. -/
def nat (j : Json) (k : String) : Except String Nat := do asNat k (← field j k)

/-- A required array field. -/
def arr (j : Json) (k : String) : Except String (Array Json) := do asArr k (← field j k)

/-- A required string field. -/
def str (j : Json) (k : String) : Except String String := do asStr k (← field j k)

/-- A required array of integers. -/
def ints (j : Json) (k : String) : Except String (List Int) := do (← arr j k).toList.mapM (asInt k)

/-- A required array of strings. -/
def strs (j : Json) (k : String) : Except String (List String) := do (← arr j k).toList.mapM (asStr k)

/-- A required array of numbers. -/
def rats (j : Json) (k : String) : Except String (List Rat) := do (← arr j k).toList.mapM (asRat k)

/-- An exact rational as a JSON number when its denominator is a power of 10 up to 10¹² (always
the case for decimal inputs), else as `{"num","den"}`. -/
def ratJson (q : Rat) : Json :=
  match (List.range 13).find? (fun e => (10 ^ e) % q.den == 0) with
  | some e => .num ⟨q.num * ((10 ^ e / q.den : Nat) : Int), e⟩
  | none => Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

/-- An object of integer counts as name–value entries (sorted by name). -/
def countsOf (k : String) : Json → Except String Counts
  | .obj kvs => kvs.toArray.toList.mapM fun ⟨name, v⟩ => do pure (name, ← asInt s!"{k}.{name}" v)
  | _ => .error s!"field {k}: expected an object"

/-- Name–value entries as a JSON object. -/
def objOf (kvs : List (String × Json)) : Json := Json.mkObj kvs

/-! ## Chromium lane -/

/-- Decode a frame `{n, phase, scrollY, counts}` (other fields ignored). -/
def frameOf (j : Json) : Except String Frame := do
  pure { n := ← nat j "n", phase := ← str j "phase", scrollY := ← asInt "scrollY" (← field j "scrollY"),
         counts := ← countsOf "counts" (← field j "counts") }

/-- Encode a zone. -/
def zoneJson (z : Zone) : Json := Json.mkObj [
  ("id", .str z.id), ("frames", toJson z.frames), ("scrolledPx", toJson z.scrolledPx),
  ("firstFrame", toJson z.firstFrame), ("lastFrame", toJson z.lastFrame),
  ("sums", objOf (z.sums.map fun (k, v) => (k, toJson v)))]

/-- `measure.zoneSums`: `{zoneHeightPx, frames}` → `{zones}`. -/
def opZoneSums (req : Json) : Except String Reply := do
  let h ← nat req "zoneHeightPx"
  if h = 0 then throw "zoneHeightPx must be positive"
  let fs ← (← arr req "frames").toList.mapM frameOf
  pure [("zones", .arr ((zoneSums h fs).toArray.map zoneJson))]

/-- The frames of one run: an array of frames, or an object with a `frames` array. -/
def runFrames (j : Json) : Except String (List Counts) := do
  let a ← match j with
    | .arr a => pure a
    | .obj _ => arr j "frames"
    | _ => throw "field runs: each run must be an array of frames or an object with frames"
  a.toList.mapM fun f => do countsOf "counts" (← field f "counts")

/-- Encode a class with its observed maxima. -/
def classJson (c : Class) (k t : Nat) : Json :=
  let name := match c with
    | .deterministic => "deterministic" | .stable _ _ => "stable" | .quarantined => "quarantined"
  Json.mkObj [("class", .str name), ("k", toJson k), ("t", toJson t)]

/-- Class name of a cell status. -/
def statusName : Nat → String
  | 0 => "deterministic" | 1 => "stable" | _ => "quarantined"

/-- Round half up to 4 decimals, as a JSON number (JS `Math.round(x * 1e4) / 1e4`). -/
def round4 (q : Rat) : Json := .num ⟨roundHalfUp (q * 10000), 4⟩

/-- The report of the cell mode: class, counts of differing and out-of-tolerance cells, the
largest spread and relative spread, and the frame-sense maxima `k`, `t`. -/
def cellsReport (tol : Tol) (runs : List Series) : Reply :=
  let len := (runs.headD []).length
  let k := kObs runs
  let t := tObs runs
  if runs.any (·.length != len) then
    [("cls", .str "quarantined"), ("reason", .str "vector length differs between runs"), ("cells", toJson len),
     ("differingCells", .null), ("cellsBeyondTolerance", .null), ("maxSpread", .null), ("maxRelSpread", .null),
     ("k", toJson k), ("t", toJson t)]
  else
    let cells := (List.range len).map fun i => cellVals runs i
    let st := cells.map stats
    let differing := st.filter fun s => s.2.1 - s.1 != 0
    let spreads := differing.map fun s => s.2.1 - s.1
    let maxSpread := spreads.foldr max 0
    let rels := (differing.filter fun s => s.2.2 > 0).map fun s => ((s.2.1 - s.1 : Int) : Rat) / ((s.2.2 : Int) : Rat)
    let maxRel := rels.foldr (fun a b => if a < b then b else a) 0
    [("cls", .str (statusName (classifyCells tol runs))), ("cells", toJson len),
     ("differingCells", toJson differing.length),
     ("cellsBeyondTolerance", toJson ((cells.filter fun c => cellStatus tol c == 2).length)),
     ("maxSpread", toJson maxSpread), ("maxRelSpread", round4 maxRel), ("k", toJson k), ("t", toJson t)]

/-- `measure.classify`: frame mode (Chromium per-frame counts) or cell mode (WebKit cells). -/
def opClassify (req : Json) : Except String Reply := do
  let mode ← str req "mode"
  let runsJ ← arr req "runs"
  if runsJ.size < 2 then throw "need at least two runs"
  match mode with
  | "frames" =>
    let p : Policy := ⟨← nat req "kMax", ← nat req "tMax"⟩
    let q : PxTol ← match opt req "pxRel" with
      | none => pure pxTolDefault
      | some j => pure ⟨← nat j "num", ← nat j "den"⟩
    if q.den = 0 then throw "pxRel.den must be at least 1"
    let runs ← runsJ.toList.mapM runFrames
    let rows := classifyAllU p q runs
    -- count rows keep the count schema; pixel-area rows also name their unit and gap bound
    let rowJson (r : ClassRow) : Json := match unitOf r.type with
      | .px => Json.mkObj [("class", .str (match r.cls with
            | .deterministic => "deterministic" | .stable _ _ => "stable" | .quarantined => "quarantined")),
          ("k", toJson r.k), ("t", toJson r.t), ("unit", .str "px"),
          ("tBound", toJson (tBound p q .px (runs.map (seriesOf r.type))))]
      | .count => classJson r.cls r.k r.t
    pure [("classes", objOf (rows.map fun r => (r.type, rowJson r))), ("runs", toJson runs.length)]
  | "cells" =>
    let tj ← field req "tol"
    let tol : Tol := ⟨← asRat "tol.absTol" (← field tj "absTol"), ← asRat "tol.relTol" (← field tj "relTol")⟩
    let runs ← runsJ.toList.mapM fun r => do (← asArr "runs" r).toList.mapM (asInt "runs")
    pure (cellsReport tol runs)
  | m => throw s!"unknown mode {m} (frames or cells)"

/-- Decode a class `{class, k, t}` (k, t only for stable). -/
def classOf (j : Json) : Except String Class := do
  match ← str j "class" with
  | "deterministic" => pure .deterministic
  | "stable" => pure (.stable (← nat j "k") (← nat j "t"))
  | "quarantined" => pure .quarantined
  | c => throw s!"unknown class {c}"

/-- `measure.noMoreWork`: `{types:[{class, base, var}]}` → `{noMoreWork, failing}`. -/
def opNoMoreWork (req : Json) : Except String Reply := do
  let os ← (← arr req "types").toList.mapM fun t => do
    pure ({ cls := ← classOf (← field t "class"), base := ← ints t "base", var := ← ints t "var" } : TypeObs)
  let failing := ((List.range os.length).zip os).filter (fun (_, o) => !typeOk o.cls o.base o.var) |>.map (·.1)
  pure [("noMoreWork", .bool (noMoreWork os)), ("failing", toJson failing)]

/-- The frames of one run as JSON: an array of frames, or an object with a `frames` array. -/
def runArr (j : Json) : Except String (Array Json) :=
  match j with
  | .arr a => pure a
  | .obj _ => arr j "frames"
  | _ => throw "field runs: each run must be an array of frames or an object with frames"

/-- The alignment key of a frame: its `phase` (a string) and `scrollY` (an exact number), each
absent when missing or `null`. -/
def frameKey (f : Json) : Except String (Option String × Option Rat) := do
  let ph ← match opt f "phase" with
    | none => pure none
    | some j => some <$> asStr "phase" j
  let y ← match opt f "scrollY" with
    | none => pure none
    | some j => some <$> asRat "scrollY" j
  pure (ph, y)

/-- Encode a self-check row. -/
def sRowJson (r : SelfCheck.SRow) : Json := Json.mkObj [
  ("type", .str r.type), ("class", .str r.cls.name), ("maxDiffFrames", toJson r.maxDiff),
  ("spread", toJson r.spread), ("totals", toJson r.totals)]

/-- `measure.selfCheck`: `{runs}` (≥ 1; each an array of frames or an object with `frames`) →
`{rows, frames, framesAligned, runs}` under the harness thresholds. -/
def opSelfCheck (req : Json) : Except String Reply := do
  let runsJ ← arr req "runs"
  if runsJ.size < 1 then throw "need at least one run"
  let fs ← runsJ.toList.mapM runArr
  let runs ← fs.mapM fun a => a.toList.mapM fun f => do countsOf "counts" (← field f "counts")
  let keys ← fs.mapM fun a => a.toList.mapM frameKey
  let rows := SelfCheck.check SelfCheck.harness runs
  pure [("rows", .arr (rows.toArray.map sRowJson)), ("frames", toJson (fs.headD #[]).size),
        ("framesAligned", .bool (SelfCheck.aligned keys)), ("runs", toJson runs.length)]

/-- A value along a path of object keys (absent when a step is missing, `null` or not an object). -/
def path (j : Json) : List String → Option Json
  | [] => some j
  | k :: ks => (opt j k).bind (path · ks)

/-- An optional boolean (absent or `null` is false). -/
def optBool (k : String) : Option Json → Except String Bool
  | none => pure false
  | some (.bool b) => pure b
  | some _ => throw s!"field {k}: expected a boolean"

/-- An optional integer (absent or `null` is 0). -/
def optInt (k : String) : Option Json → Except String Int
  | none => pure 0
  | some v => asInt k v

/-- An optional array (absent or `null` is empty). -/
def optArr (k : String) : Option Json → Except String (Array Json)
  | none => pure #[]
  | some v => asArr k v

/-- Decode a layer of `active_tree.layers`. -/
def layerOf (j : Json) : Except String Snapshot.Layer := do
  pure { draws := ← optBool "draws_content" (opt j "draws_content"),
         width := ← optInt "bounds.width" (path j ["bounds", "width"]),
         height := ← optInt "bounds.height" (path j ["bounds", "height"]),
         tilings := (← optArr "tilings" (opt j "tilings")).size,
         invalidation := ← (← optArr "invalidation" (opt j "invalidation")).toList.mapM (asInt "invalidation") }

/-- Decode an active tile: `draw_info.is_solid_color`, and `content_rect` `[x, y, w, h, …]`
(absent is all zeros; fewer than 4 entries is refused). -/
def tileOf (j : Json) : Except String Snapshot.Tile := do
  let solid ← optBool "draw_info.is_solid_color" (path j ["draw_info", "is_solid_color"])
  let (w, h) ← match opt j "content_rect" with
    | none => pure ((0 : Int), (0 : Int))
    | some v => do
      let r ← asArr "content_rect" v
      if r.size < 4 then throw "field content_rect: expected at least 4 numbers"
      pure (← asInt "content_rect" (r.getD 2 .null), ← asInt "content_rect" (r.getD 3 .null))
  pure ⟨solid, w, h⟩

/-- `measure.snapshotCounts`: `{snapshot}` (the `args.snapshot` of one `LayerTreeHostImpl:snapshot`
event; a non-object counts as empty) → `{counts}`. -/
def opSnapshotCounts (req : Json) : Except String Reply := do
  let s := (opt req "snapshot").getD (Json.mkObj [])
  let snap : Snapshot.Snap := {
    tileCount := ← optInt "tile_manager_basic_state.tile_count" (path s ["tile_manager_basic_state", "tile_count"]),
    layers := ← (← optArr "active_tree.layers" (path s ["active_tree", "layers"])).toList.mapM layerOf,
    tiles := ← (← optArr "active_tiles" (opt s "active_tiles")).toList.mapM tileOf }
  pure [("counts", objOf ((Snapshot.census snap).map fun (k, v) => (k, toJson v)))]

/-! ## WebKit lane -/

/-- Decode a raw row `[type, start, end, extra]`: a non-number start is `none`; a Paint row's
extra must be an array of numbers (the clip quad) or anything else (no clip). -/
def rowOf (j : Json) : Except String Row := do
  let a := (← asArr "rows" j).toList
  let ty ← match a.head? with
    | some (.str s) => pure s
    | _ => throw "field rows: each row must start with its type"
  let start := match a.drop 1 |>.head? with
    | some (.num n) => some (mkRat n.mantissa (10 ^ n.exponent))
    | _ => none
  let clip ← match a.drop 3 |>.head? with
    | some (.arr q) => if ty == "Paint" then q.toList.mapM (asRat "rows.clip") else pure []
    | _ => pure []
  pure ⟨ty, start, clip⟩

/-- Encode tally counts as an object keyed by count type. -/
def countsJson (cs : List Nat) : List (String × Json) := (countTypes.zip cs).map fun (k, v) => (k, toJson v)

/-- Encode the "other" types. -/
def otherJson (o : List (String × Nat)) : Json := objOf (o.map fun (k, v) => (k, toJson v))

/-- `measure.webkit.tally`: `{rows}` → `{counts, paintArea, other}`. -/
def opTally (req : Json) : Except String Reply := do
  let t := tally (← (← arr req "rows").toList.mapM rowOf)
  pure [("counts", objOf (countsJson t.counts)), ("paintArea", toJson t.paintArea), ("other", otherJson t.other)]

/-- Non-decreasing check. -/
def nondecreasing : List Rat → Bool
  | a :: b :: rest => decide (a ≤ b) && nondecreasing (b :: rest)
  | _ => true

/-- `measure.webkit.reduceSteps`: `{rows, marks, endTime}` → the `reduceSteps` object. -/
def opReduceSteps (req : Json) : Except String Reply := do
  let rows ← (← arr req "rows").toList.mapM rowOf
  let marks ← rats req "marks"
  if marks.isEmpty then throw "marks must be non-empty"
  if !nondecreasing marks then throw "marks must be non-decreasing"
  let e ← asRat "endTime" (← field req "endTime")
  let r := reduceSteps rows marks e
  pure [("countTypes", toJson countTypes), ("perStep", toJson r.perStep),
        ("perStepPaintArea", toJson r.perStepPaintArea),
        ("total", objOf (countsJson r.total.counts ++ [("paintArea", toJson r.total.paintArea)])),
        ("other", otherJson r.total.other), ("rowsBeforeFirstStep", toJson r.rowsBeforeFirstStep)]

/-- `measure.webkit.zones`: `{ys, perStep, perStepPaintArea, zonePx?}` → `{zones}`. -/
def opWebkitZones (req : Json) : Except String Reply := do
  let ys ← rats req "ys"
  let per ← (← arr req "perStep").toList.mapM fun r => do (← asArr "perStep" r).toList.mapM (asInt "perStep")
  let pa ← ints req "perStepPaintArea"
  let h ← match opt req "zonePx" with
    | none => pure 500
    | some v => asNat "zonePx" v
  if h = 0 then throw "zonePx must be positive"
  if per.length != ys.length || pa.length != ys.length then
    throw "ys, perStep and perStepPaintArea must have the same length"
  if ys.any (· < 0) then throw "ys: negative scroll offset"
  if per.any (·.length > countTypes.length) then throw "perStep: a row is longer than countTypes"
  let steps := (ys.zip (per.zip pa)).map fun (y, r, a) => ({ y, row := r, area := a } : Step)
  pure [("zones", .arr ((zones h countTypes.length steps).toArray.map fun z => Json.mkObj [
    ("zone", toJson z.zone), ("y0", toJson z.y0), ("steps", toJson z.steps), ("counts", toJson z.counts),
    ("paintArea", toJson z.paintArea)]))]

/-- `measure.symDiff`: `{a, b}` → `{symDiff}`. -/
def opSymDiff (req : Json) : Except String Reply := do
  pure [("symDiff", toJson (symDiff (← strs req "a") (← strs req "b")))]

/-- Class number of a class name. -/
def clsNum : String → Except String Nat
  | "deterministic" => .ok 0 | "stable" => .ok 1 | "quarantined" => .ok 2
  | c => .error s!"unknown class {c}"

/-- `measure.summarize`: `{rows:[{family, metric, level, cls}]}` → `{summary}`. -/
def opSummarize (req : Json) : Except String Reply := do
  let rows ← (← arr req "rows").toList.mapM fun r => do
    pure ({ family := ← str r "family", metric := ← str r "metric", level := ← str r "level",
            cls := ← clsNum (← str r "cls") } : CRow)
  pure [("summary", .arr ((summarize rows).toArray.map fun s => Json.mkObj [
    ("family", .str s.family), ("metric", .str s.metric),
    ("levels", objOf (s.levels.map fun (l, c) => (l, .str (statusName c)))),
    ("worst", .str (statusName s.worst))]))]

/-! ## Freeze (Fw.Measure.Freeze) -/

/-- Name of a level. -/
def levelName : Freeze.Level → String
  | .det => "deterministic" | .stable => "stable" | .quar => "quarantined"

/-- Decode a level name; any other string is an error. -/
def levelOfName : String → Except String Freeze.Level
  | "deterministic" => .ok .det | "stable" => .ok .stable | "quarantined" => .ok .quar
  | c => .error s!"unknown class {c}"

/-- Decode a class table `{type: {class, k, t, tBound?}}` (the `classes` reply of `measure.classify`). -/
def tableOf (k : String) : Json → Except String Freeze.Table
  | .obj kvs => kvs.toArray.toList.mapM fun ⟨ty, v⟩ => do
      let tb ← match opt v "tBound" with
        | none => pure none
        | some b => some <$> asNat s!"{k}.{ty}.tBound" b
      pure (ty, { cls := ← levelOfName (← str v "class"), k := ← nat v "k", t := ← nat v "t", tBound := tb })
  | _ => .error s!"field {k}: expected an object"

/-- Encode a tally `(det, stable, quar)`. -/
def tallyJson (c : Nat × Nat × Nat) : Json :=
  Json.mkObj [("deterministic", toJson c.1), ("stable", toJson c.2.1), ("quarantined", toJson c.2.2)]

/-- Name of a role. -/
def roleName : Arms.Role → String
  | .gate => "gate" | .finding => "finding" | .byDesign => "byDesign"

/-- The `role` field of a type of level `l`, with its `reason` when it is quarantined by design. -/
def roleFields (ty : String) (l : Freeze.Level) : List (String × Json) :=
  [("role", .str (roleName (Arms.roleOf ty l)))] ++
    (match Arms.reasonOf ty with | some s => [("reason", .str s)] | none => [])

/-- Encode a role tally `(gate, finding, byDesign)`. -/
def roleTallyJson (c : Nat × Nat × Nat) : Json :=
  Json.mkObj [("gate", toJson c.1), ("finding", toJson c.2.1), ("byDesign", toJson c.2.2)]

/-- `measure.freeze`: `{runs:[{id, images, classes}], pooled?}` → `{image, runs, types, tally, roles, pooledTally?}`;
an error when a table does not decode or `Freeze.freeze` refuses. In `perRun` a run without the type is the
string `"missing"`. -/
def opFreeze (req : Json) : Except String Reply := do
  let runs ← (← arr req "runs").toList.mapM fun r => do
    pure ({ id := ← str r "id", images := ← strs r "images", table := ← tableOf "classes" (← field r "classes") }
      : Freeze.RunTable)
  let pooled ← match opt req "pooled" with
    | none => pure none
    | some j => some <$> tableOf "pooled" j
  let (img, rows) ← Freeze.freeze runs
  let rowJson (r : Freeze.FRow) : Json := Json.mkObj <|
    [("class", .str (levelName r.cls)), ("k", toJson r.k), ("t", toJson r.t),
     ("perRun", .arr (r.perRun.toArray.map fun o => .str ((o.map levelName).getD "missing")))] ++
    (match unitOf r.type with | .px => [("unit", .str "px")] | .count => []) ++
    (match r.tBound with | some b => [("tBound", toJson b)] | none => []) ++
    (match pooled.bind (Freeze.entry? · r.type) with
      | some e => [("pooledClass", .str (levelName e.cls))] | none => []) ++
    roleFields r.type r.cls
  pure ([("image", .str img), ("runs", toJson (runs.map (·.id))),
         ("types", objOf (rows.map fun r => (r.type, rowJson r))),
         ("tally", tallyJson (Freeze.tally (rows.map (·.cls)))),
         ("roles", roleTallyJson (Arms.roleTally rows))] ++
        (match pooled with | some p => [("pooledTally", tallyJson (Freeze.tally (p.map (·.2.cls))))] | none => []))

/-! ## Splits, N0 windows, the SPK-q verdict, arms (Fw.Measure.Splits, .Neutral, .Arms) -/

/-- A list of strings as a JSON array. -/
def strArr (l : List String) : Json := .arr (l.toArray.map .str)

/-- Decode a trace slice `{name, ph, ts, dur?}` (integers, µs; a missing or `null` `dur` is 0). -/
def sliceOf (j : Json) : Except String Splits.Slice := do
  let dur ← match opt j "dur" with
    | none => pure 0
    | some d => asInt "dur" d
  pure { name := ← str j "name", ph := ← str j "ph", ts := ← asInt "ts" (← field j "ts"), dur := dur }

/-- `measure.splits`: `{slices}` → `{splits, n1Keys, n1Excluded, n1Gated, counts}` (`counts`: the
split counts of `Splits.splitTable` over all the slices). -/
def opSplits (req : Json) : Except String Reply := do
  let evs ← (← arr req "slices").toList.mapM sliceOf
  pure [("splits", .arr (Splits.splits.toArray.map fun s => Json.mkObj
          [("name", .str s.name), ("within", .str s.within), ("base", .str s.base), ("key", .str s.key)])),
        ("n1Keys", strArr Splits.n1Keys), ("n1Excluded", strArr Splits.n1Excluded),
        ("n1Gated", strArr Splits.n1Gated),
        ("counts", objOf ((Splits.splitTable evs).map fun (k, v) => (k, toJson v)))]

/-- A window as JSON: `"load"`, `"preroll"`, `"after"`, or the frame index. -/
def winJson : Neutral.Win → Json
  | .load => .str "load" | .preroll => .str "preroll" | .after => .str "after" | .frame i => toJson i

/-- `measure.n0Windows`: `{events [{kind, vt}], frameVts (non-decreasing), startVt, dt}` →
`{windows, load, preroll, after, frames}` (`windows` per event; `frames` the N0 counts per recorded frame). -/
def opN0Windows (req : Json) : Except String Reply := do
  let es ← (← arr req "events").toList.mapM fun e => do
    pure ({ kind := ← str e "kind", vt := ← asRat "vt" (← field e "vt") } : Neutral.N0Event)
  let fv ← rats req "frameVts"
  if !nondecreasing fv then throw "field frameVts: must be non-decreasing"
  let s ← asRat "startVt" (← field req "startVt")
  let dt ← asRat "dt" (← field req "dt")
  let n (w : Neutral.Win) : Json := toJson (Neutral.eventsIn fv s dt w es).length
  pure [("windows", .arr (es.toArray.map fun e => winJson (Neutral.winOf fv s dt e.vt))),
        ("load", n .load), ("preroll", n .preroll), ("after", n .after),
        ("frames", .arr ((Neutral.perFrame fv s dt es).toArray.map fun l =>
          objOf ((Neutral.frameCounts l).map fun (k, v) => (k, toJson v))))]

/-- A window total `meta.n0.<w>.total` (an error when absent). -/
def n0Total (n0 : Json) (w : String) : Except String Nat := do nat (← field n0 w) "total"

/-- Name of a verdict. -/
def verdictName : Neutral.Verdict → String
  | .pass => "pass" | .fail => "fail" | .missing => "missing"

/-- `measure.spkq`: a counts file `{frames [{counts}], meta {n0 {enabled, load, preroll, after}}}` →
`{verdict, required, n1Gated, n1Excluded, unrecorded, nonzeroN0, nonzeroN1, preroll?, after?}`. The census
is off (`none`) when `meta`, `meta.n0` or `enabled: true` is missing. -/
def opSpkq (req : Json) : Except String Reply := do
  let frames ← runFrames req
  let n0 := (opt req "meta").bind (opt · "n0")
  let w ← match n0 with
    | some j =>
      if opt j "enabled" == some (.bool true) then
        pure (some ({ load := ← n0Total j "load", preroll := ← n0Total j "preroll",
                      after := ← n0Total j "after" } : Neutral.N0Win))
      else pure none
    | none => pure none
  pure ([("verdict", .str (verdictName (Neutral.verdict w frames))),
         ("required", strArr Neutral.required), ("n1Gated", strArr Splits.n1Gated),
         ("n1Excluded", strArr Splits.n1Excluded),
         ("unrecorded", toJson (Neutral.unrecorded frames)),
         ("nonzeroN0", toJson (Neutral.nonzero Neutral.n0Keys frames)),
         ("nonzeroN1", toJson (Neutral.nonzero Splits.n1Gated frames))] ++
        (match w with
          | some v => [("preroll", toJson v.preroll), ("after", toJson v.after)]
          | none => []))

/-- `measure.arms`: `{a, r}` (class tables of the original and the rewrite, as in `measure.classify`
`classes`) → `{types {type: {a, r, class, role, reason?}}, gates, roles}`; an arm without the type reads
`"absent"`. -/
def opArms (req : Json) : Except String Reply := do
  let ta ← tableOf "a" (← field req "a")
  let tr ← tableOf "r" (← field req "r")
  let lv (o : Option Freeze.Level) : Json := .str ((o.map levelName).getD "absent")
  let rows := (Freeze.typesOf [ta, tr]).map fun ty =>
    let c := (Arms.crossLevel (Arms.levelAt? ta ty) (Arms.levelAt? tr ty)).getD .quar
    (ty, c, Json.mkObj ([("a", lv (Arms.levelAt? ta ty)), ("r", lv (Arms.levelAt? tr ty)),
      ("class", .str (levelName c))] ++ roleFields ty c))
  pure [("types", objOf (rows.map fun (ty, _, j) => (ty, j))),
        ("gates", strArr ((rows.filter fun (ty, c, _) => Arms.roleOf ty c == .gate).map (·.1))),
        ("roles", roleTallyJson (Arms.roleTally (rows.map fun (ty, c, _) =>
          ({ type := ty, cls := c, k := 0, t := 0, perRun := [], tBound := none } : Freeze.FRow))))]

/-- The `measure.*` ops. -/
def ops : List String :=
  ["measure.zoneSums", "measure.classify", "measure.noMoreWork", "measure.webkit.tally",
   "measure.webkit.reduceSteps", "measure.webkit.zones", "measure.symDiff", "measure.summarize",
   "measure.selfCheck", "measure.snapshotCounts", "measure.freeze", "measure.splits", "measure.n0Windows",
   "measure.spkq", "measure.arms"]

/-- Dispatch a `measure.*` op (`none` when the op is not one of them). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "measure.zoneSums" => some (opZoneSums req)
  | "measure.classify" => some (opClassify req)
  | "measure.noMoreWork" => some (opNoMoreWork req)
  | "measure.webkit.tally" => some (opTally req)
  | "measure.webkit.reduceSteps" => some (opReduceSteps req)
  | "measure.webkit.zones" => some (opWebkitZones req)
  | "measure.symDiff" => some (opSymDiff req)
  | "measure.summarize" => some (opSummarize req)
  | "measure.selfCheck" => some (opSelfCheck req)
  | "measure.snapshotCounts" => some (opSnapshotCounts req)
  | "measure.freeze" => some (opFreeze req)
  | "measure.splits" => some (opSplits req)
  | "measure.n0Windows" => some (opN0Windows req)
  | "measure.spkq" => some (opSpkq req)
  | "measure.arms" => some (opArms req)
  | _ => none

end Fw.Wire.Measure

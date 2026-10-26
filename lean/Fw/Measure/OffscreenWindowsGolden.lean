import Lean.Data.Json
import Fw.Measure.OffscreenWindows

/-!
Golden vectors for the Chromium push windows.
-/
namespace Fw.Measure.OffscreenWindowsGolden
open Fw.Measure.OffscreenWindows Fw.Measure.Offscreen Lean

def verdictName : Verdict → String
  | .gain => "gain"
  | .noGain => "noGain"
  | .noData => "noData"

def cmpName : Cmp → String
  | .less => "less"
  | .same => "same"
  | .more => "more"

def winJson (w : Win) : Json :=
  Json.mkObj [("name", Json.str w.name), ("lo", toJson w.lo), ("hi", toJson w.hi)]

def vecJson (v : Vec) : Json :=
  Json.mkObj [("n", toJson v.n), ("vals", Json.mkObj (v.vals.map fun (k, x) => (k, toJson x)))]

def endCases : List (String × List Nat) := [
  ("no frame", []),
  ("one frame", [7]),
  ("flat", [3, 3, 3]),
  ("ramp then flat: the first frame at the top", [0, 10, 20, 30, 30, 30, 30]),
  ("two peaks: the first one", [0, 50, 20, 50, 10]),
  ("top on the last frame", [0, 10, 20, 30]),
  ("top first", [9, 1, 2, 9])]

def windowCases : List (String × Nat × Nat) := [
  ("the swipe-touch-v1 push", 574, 741),
  ("end near the start: the approach is cut at frame 0", 12, 300),
  ("end 120 frames before the last", 100, 220),
  ("end inside the last 120 frames", 100, 150),
  ("end past the last frame", 800, 741),
  ("end on the last frame", 741, 741)]

def ownerFrom (e last : Nat) : Nat := (finishWin e last).lo - 2

def ownerCount (e last : Nat) : Nat := last - ownerFrom e last + 2

def ramp (total e : Nat) : List Nat := (List.range total).map fun i => min i e * 10000

def total : Nat := 204

def colv (j i : Nat) : Nat := (i * (j + 3) + j) % 5

def mkCols (f : String → Nat → Nat → Nat) (skip : List String := []) (tot : Nat := total) : List (String × List Nat) :=
  (wkeys.mapIdx fun j k => (k, (List.range tot).map fun i => f k i (colv j i))).filter fun (k, _) => !skip.contains k

def same : String → Nat → Nat → Nat := fun _ _ v => v

def mkRun (e : Nat) (f : String → Nat → Nat → Nat) (jit : Nat) (skip : List String := []) (tot : Nat := total) : Run :=
  { ys := ramp tot e,
    cols := mkCols (fun k i v => f k i v + (if k == "metric.RecalcStyleCount" && i == 80 then jit else 0)) skip tot,
    tail := touchTail }

def arm (e : Nat) (f : String → Nat → Nat → Nat) (jits : List Nat := [0, 1, 2]) (tot : Nat := total) : List Run :=
  jits.map fun j => mkRun e f j [] tot

def runJson (r : Run) : Json :=
  Json.mkObj [("ys", toJson r.ys), ("cols", Json.mkObj (r.cols.map fun (k, xs) => (k, toJson xs))), ("tail", toJson r.tail)]

def runWindowsJson (r : Run) : Json :=
  match r.windows with
  | none => Json.null
  | some (e, ws) => Json.mkObj [("end", toJson e), ("windows", Json.arr (ws.toArray.map fun (n, v) =>
      Json.mkObj [("name", Json.str n), ("vec", vecJson v)]))]

def lowRaster : String → Nat → Nat → Nat := fun k i v => if k == "trace.RasterTask" && 10 ≤ i && i < 60 then 0 else v
def highPaint : String → Nat → Nat → Nat := fun k i v =>
  if k == "trace.RasterTask" && 10 ≤ i && i < 40 then 0 else if k == "trace.Paint" && 100 ≤ i && i < 160 then v + 1 else v

def armCases (_ : Unit := ()) : List (String × List Run × List Run) := [
  ("raster tasks gone before and just after the end: approach and end 0-19 gain, finish gains", arm 40 same, arm 40 lowRaster),
  ("raster down in the approach but paint up in end 60-119: the finish is no gain", arm 40 same, arm 40 highPaint),
  ("identical arms", arm 40 same, arm 40 same),
  ("jitter on a recalc overlaps the base", arm 40 same [0, 1, 2], arm 40 same [1, 2, 3]),
  ("two flag runs", arm 40 same, (arm 40 lowRaster).take 2),
  ("a counter column missing in one flag run", arm 40 same, [mkRun 40 lowRaster 0, mkRun 40 lowRaster 1, mkRun 40 lowRaster 2 ["trace.FireAnimationFrame"]]),
  ("one flag run ends a frame later: end 120+ and finish differ in length", arm 40 same, [mkRun 40 lowRaster 0, mkRun 40 lowRaster 1, mkRun 41 lowRaster 2]),
  ("the page end falls in the tail: end windows are empty", arm 203 same, arm 203 lowRaster),
  ("no base runs", [], arm 40 lowRaster),
  ("no flag runs", arm 40 same, []),
  ("two base runs", (arm 40 same).take 2, arm 40 lowRaster)]

def cellJson (base flag : List Vec) (k : String) : Json :=
  match cell base flag k with
  | none => Json.null
  | some (c, b, f) => Json.mkObj [("key", Json.str k), ("cmp", Json.str (cmpName c)), ("base", toJson [b.1, b.2]),
      ("flag", toJson [f.1, f.2]), ("reduction", toJson (reduction b.1 f.2))]

def armJson (name : String) (base flag : List Run) : Json :=
  let bw := base.filterMap fun r => r.windows.map (·.2)
  let fw := flag.filterMap fun r => r.windows.map (·.2)
  Json.mkObj [("op", "arm"), ("case", Json.str name), ("base", Json.arr (base.toArray.map runWindowsJson)),
    ("flag", Json.arr (flag.toArray.map runWindowsJson)),
    ("verdicts", Json.arr ((armVerdicts bw fw).toArray.map fun (n, v) =>
      Json.mkObj [("window", Json.str n), ("verdict", Json.str (verdictName v)),
        ("usable", .bool (usableOn wkeys (vecsOf bw n) (vecsOf fw n))),
        ("cells", Json.arr (wkeys.toArray.map (cellJson (vecsOf bw n) (vecsOf fw n))))]))]

def lateRaster : String → Nat → Nat → Nat := fun k i v => if k == "trace.RasterTask" && 100 ≤ i then 0 else v
def latePaint : String → Nat → Nat → Nat := fun k i v =>
  if k == "trace.RasterTask" && 100 ≤ i then 0 else if k == "trace.Paint" && 165 ≤ i then v + 3 else v

/-- Arms whose runs end on different frames or have different lengths. -/
def ownCases (_ : Unit := ()) : List (String × List Run × List Run) := [
  ("the flag ends 125 frames later with 3 frames after its end: end 0-19 compares 3 frames, later end windows are empty",
    arm 40 same, arm 165 lateRaster [0, 1, 2] 198),
  ("same end frame and same length: the verdicts are today's", arm 40 same, arm 40 lowRaster),
  ("same end frame, the flag recorded 46 frames longer: the long windows compare their common frames", arm 40 same, arm 40 lowRaster [0, 1, 2] 250),
  ("the flag ends earlier than the base", arm 165 same [0, 1, 2] 198, arm 40 lowRaster),
  ("paint rises in the 3 frames after the flag end: end 0-19 is no gain", arm 40 same, arm 165 latePaint [0, 1, 2] 198),
  ("one flag run reaches its page end in the tail: its empty end windows empty every end window", arm 40 same,
    [mkRun 165 lateRaster 0 [] 198, mkRun 165 lateRaster 1 [] 198, mkRun 203 lateRaster 2]),
  ("a flag run without frames is dropped, two runs are left", arm 40 same,
    [mkRun 165 lateRaster 0 [] 198, mkRun 165 lateRaster 1 [] 198, { ys := [], cols := [], tail := touchTail }]),
  ("a counter column missing in one flag run", arm 40 same,
    [mkRun 165 lateRaster 0 [] 198, mkRun 165 lateRaster 1 [] 198, mkRun 165 lateRaster 2 ["trace.FireAnimationFrame"] 198]),
  ("two base runs", (arm 40 same).take 2, arm 165 lateRaster [0, 1, 2] 198),
  ("no flag runs", arm 40 same, [])]

def ownJson (name : String) (base flag : List Run) : Json :=
  let cap := commonLen ((base ++ flag).filterMap (·.plan))
  let bw := base.filterMap (·.capped cap)
  let fw := flag.filterMap (·.capped cap)
  Json.mkObj [("op", "own"), ("case", Json.str name), ("base", Json.arr (base.toArray.map runJson)),
    ("flag", Json.arr (flag.toArray.map runJson)),
    ("verdicts", Json.arr ((ownVerdicts base flag).toArray.map fun (n, v) =>
      Json.mkObj [("window", Json.str n), ("frames", toJson (cap n)), ("verdict", Json.str (verdictName v)),
        ("usable", .bool (usableOn wkeys (vecsOf bw n) (vecsOf fw n))),
        ("cells", Json.arr (wkeys.toArray.map (cellJson (vecsOf bw n) (vecsOf fw n))))]))]

def goldenLines (_ : Unit := ()) : List String :=
  let consts := (Json.mkObj [("op", "constants"), ("keys", toJson wkeys), ("approach", toJson approachFrames),
    ("tail", toJson touchTail), ("minRuns", toJson minRuns), ("slack", toJson slack), ("names", toJson windowNames)]).compress
  let es := endCases.map fun (name, ys) =>
    (Json.mkObj [("op", "end"), ("case", Json.str name), ("ys", toJson ys), ("end", toJson (endFrame ys))]).compress
  let ws := windowCases.map fun (name, e, last) =>
    (Json.mkObj [("op", "windows"), ("case", Json.str name), ("end", toJson e), ("last", toJson last),
      ("windows", Json.arr ((pushWindows e last).toArray.map winJson)), ("finish", winJson (finishWin e last)),
      ("ownersFrom", toJson (ownerFrom e last)),
      ("owners", Json.arr (((List.range (ownerCount e last)).map fun i => match owner e last (ownerFrom e last + i) with
        | some s => Json.str s
        | none => Json.null).toArray))]).compress
  let rs := [("end at 40", mkRun 40 same 0), ("end at 5", mkRun 5 same 0),
    ("a short column", { mkRun 40 same 0 with cols := [("metric.LayoutCount", [1, 2, 3])] }),
    ("no frames", { ys := [], cols := [], tail := touchTail : Run })].map fun (name, r) =>
    (Json.mkObj [("op", "run"), ("case", Json.str name), ("run", runJson r), ("result", runWindowsJson r)]).compress
  let as := armCases.map fun (name, b, f) => (armJson name b f).compress
  let os := ownCases.map fun (name, b, f) => (ownJson name b f).compress
  [consts] ++ es ++ ws ++ rs ++ as ++ os

def goldenText (_ : Unit := ()) : String := String.intercalate "" (goldenLines.map (· ++ "\n"))

def check (path : System.FilePath) : IO Unit := do
  let cur ← IO.FS.readFile path
  unless cur == goldenText do throw (IO.userError s!"offscreen-windows golden: {path} differs from the generated bytes")
  IO.println s!"offscreen-windows golden: {path} is up to date ({goldenLines.length} lines)"

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "measure" / "offscreen-windows.jsonl"

def checkRepo : IO Unit := check goldenPath

def write (path : System.FilePath) : IO Unit := IO.FS.writeFile path goldenText

#guard endFrame [0, 10, 20, 30, 30, 30, 30] == some 3
#guard endFrame [0, 50, 20, 50, 10] == some 1
#guard endFrame [] == none
#guard (pushWindows 574 741).map (fun w => (w.lo, w.hi)) == [(540, 574), (574, 594), (594, 634), (634, 694), (694, 741)]
#guard (finishWin 574 741).lo == 540 && (finishWin 574 741).hi == 741
#guard lastFrame 771 touchTail == 741
#guard (armVerdicts ((arm 40 same).filterMap fun r => r.windows.map (·.2))
  ((arm 40 lowRaster).filterMap fun r => r.windows.map (·.2))).map (·.2) == [.gain, .gain, .noGain, .noGain, .noGain, .gain]
#guard (armVerdicts ((arm 40 same).filterMap fun r => r.windows.map (·.2))
  ((arm 40 highPaint).filterMap fun r => r.windows.map (·.2))).map (·.2) == [.gain, .noGain, .noGain, .noGain, .noGain, .noGain]
#guard (ownVerdicts (arm 40 same) (arm 40 lowRaster)).map (·.2) == [.gain, .gain, .noGain, .noGain, .noGain, .gain]
#guard ownVerdicts (arm 40 same) (arm 40 lowRaster) ==
  armVerdicts ((arm 40 same).filterMap fun r => r.windows.map (·.2)) ((arm 40 lowRaster).filterMap fun r => r.windows.map (·.2))
#guard (ownVerdicts (arm 40 same) (arm 165 lateRaster [0, 1, 2] 198)).map (·.2) == [.gain, .gain, .noData, .noData, .noData, .gain]
#guard (armVerdicts ((arm 40 same).filterMap fun r => r.windows.map (·.2))
  ((arm 165 lateRaster [0, 1, 2] 198).filterMap fun r => r.windows.map (·.2))).map (·.2) == [.gain, .noData, .noData, .noData, .noData, .noData]
#guard (ownVerdicts (arm 40 same) (arm 165 latePaint [0, 1, 2] 198)).map (·.2) == [.gain, .noGain, .noData, .noData, .noData, .noGain]

end Fw.Measure.OffscreenWindowsGolden

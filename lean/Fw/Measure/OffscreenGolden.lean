import Lean.Data.Json
import Fw.Measure.Offscreen

/-!
# Offscreen golden vectors

The cases the TS reducer of the offscreen lane replays: hidden rule, windows, comparison and verdict.
-/
namespace Fw.Measure.OffscreenGolden
open Fw.Measure.Offscreen Lean

def recCases : List (String × Int × Nat × Nat) := [
  ("far below the fold", 2000000, 800000, 932000),
  ("top edge at the viewport bottom", 932000, 800000, 932000),
  ("one milli-px inside the bottom", 931999, 800000, 932000),
  ("filling the viewport", 0, 2000000, 932000),
  ("bottom edge at the viewport top", -800000, 800000, 932000),
  ("one milli-px inside the top", -799999, 800000, 932000),
  ("scrolled past", -3000000, 800000, 932000),
  ("empty section", 100000, 0, 932000),
  ("empty viewport", -100, 800000, 0)]

/-- Recs of one synthetic run, tops in milli-px. -/
def runRecs : List Rec :=
  [1000000, 1000000, 1000000, 1000000, 1000000, 1000000, 500000, -900000, -900000, -900000, 1000000, 1000000, 1000000, 1000000,
    1000000, 1000000].map fun t => { top := t, height := 800000, vh := 932000 }

def runCols : List (String × List Nat) :=
  [("trace.Paint", [5, 3, 2, 1, 1, 1, 4, 6, 2, 2, 7, 2, 1, 1, 1, 1]),
   ("trace.cc.NeedsTick", [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])]

def cmpCases : List (String × Nat × (Nat × Nat) × (Nat × Nat)) := [
  ("flag far below", 0, (100, 102), (0, 0)),
  ("flag just below by one", 0, (11, 12), (9, 10)),
  ("flag touching base", 0, (10, 12), (8, 10)),
  ("spreads overlap", 0, (98, 102), (99, 101)),
  ("flag above", 0, (0, 0), (100, 102)),
  ("slack absorbs", 2, (11, 12), (8, 9)),
  ("slack too small", 1, (11, 12), (8, 9))]

/-- A run with every counter at 10 except the overrides. -/
def full (n : Nat) (over : List (String × Nat)) : Vec :=
  { n := n, vals := keys.map fun k => (k, (over.lookup k).getD 10) }

def run3 (n : Nat) (over : List (String × Nat × Nat × Nat)) : List Vec :=
  [0, 1, 2].map fun i => full n (over.map fun (k, a, b, c) => (k, [a, b, c].getD i 0))

def vecJson (v : Vec) : Json :=
  Json.mkObj [("n", toJson v.n), ("vals", Json.mkObj (v.vals.map fun (k, x) => (k, toJson x)))]

def vecsJson (vs : List Vec) : Json := Json.arr (vs.toArray.map vecJson)

def verdictName : Verdict → String
  | .gain => "gain"
  | .noGain => "noGain"
  | .noData => "noData"

def cmpName : Cmp → String
  | .less => "less"
  | .same => "same"
  | .more => "more"

def tick := "trace.cc.NeedsTick"
def lay := "trace.Layout"

def verdictCases : List (String × List Vec × List Vec) := [
  ("sweep-like: ticks stop", run3 100 [(tick, 98, 100, 102)], run3 100 [(tick, 0, 0, 0)]),
  ("glint-like: identical steady windows", run3 100 [(lay, 10, 11, 10)], run3 100 [(lay, 10, 11, 10)]),
  ("noise overlaps", run3 100 [(lay, 10, 14, 12)], run3 100 [(lay, 11, 13, 12)]),
  ("layout up, ticks down", run3 100 [(tick, 100, 100, 100), (lay, 5, 5, 5)], run3 100 [(tick, 0, 0, 0), (lay, 6, 6, 6)]),
  ("few base runs", (run3 100 [(tick, 98, 100, 102)]).take 2, run3 100 [(tick, 0, 0, 0)]),
  ("few flag runs", run3 100 [(tick, 98, 100, 102)], (run3 100 [(tick, 0, 0, 0)]).take 2),
  ("empty window", run3 0 [(tick, 0, 0, 0)], run3 0 [(tick, 0, 0, 0)]),
  ("windows differ", run3 100 [(tick, 98, 100, 102)], run3 99 [(tick, 0, 0, 0)]),
  ("counter missing", run3 100 [(tick, 98, 100, 102)],
    [full 100 [(tick, 0)], full 100 [(tick, 0)], { full 100 [] with vals := (full 100 []).vals.drop 1 }]),
  ("one below by one", run3 100 [(lay, 11, 11, 11)], run3 100 [(lay, 10, 10, 10)]),
  ("equal", run3 100 [(lay, 10, 10, 10)], run3 100 [(lay, 10, 10, 10)]),
  ("no base runs", [], run3 100 [(tick, 0, 0, 0)]),
  ("no flag runs", run3 100 [(tick, 98, 100, 102)], [])]

def goldenLines (_ : Unit := ()) : List String :=
  let consts := (Json.mkObj [("op", "constants"), ("settle", toJson settle), ("minRuns", toJson minRuns), ("slack", toJson slack),
    ("keys", toJson keys)]).compress
  let hs := recCases.map fun (name, top, h, vh) =>
    (Json.mkObj [("op", "hidden"), ("case", Json.str name), ("top", toJson top), ("height", toJson h), ("vh", toJson vh),
      ("hidden", toJson (Rec.hidden { top, height := h, vh }))]).compress
  let ws := [0, 3, 6].map fun k =>
    let v := windowVec k runRecs runCols
    let m := steady k (hiddenMask runRecs)
    (Json.mkObj [("op", "window"), ("settle", toJson k), ("tops", toJson (runRecs.map (·.top))), ("height", toJson 800000),
      ("vh", toJson 932000), ("cols", Json.mkObj (runCols.map fun (key, xs) => (key, toJson xs))),
      ("mask", toJson m), ("blocks", toJson (blockSums m (runCols.head!.2))), ("vec", vecJson v)]).compress
  let cs := cmpCases.map fun (name, sl, b, f) =>
    (Json.mkObj [("op", "cmp"), ("case", Json.str name), ("slack", toJson sl), ("base", toJson [b.1, b.2]),
      ("flag", toJson [f.1, f.2]), ("cmp", Json.str (cmpName (cmp sl b f))),
      ("reduction", toJson (reduction b.1 f.2))]).compress
  let vs := verdictCases.map fun (name, b, f) =>
    (Json.mkObj [("op", "verdict"), ("case", Json.str name), ("base", vecsJson b), ("flag", vecsJson f),
      ("verdict", Json.str (verdictName (verdict b f)))]).compress
  let base := run3 100 [(tick, 98, 100, 102)]
  let flags := [run3 100 [(tick, 0, 0, 0)], base]
  let all := (Json.mkObj [("op", "all"), ("case", Json.str "two flags each on their own"), ("base", vecsJson base),
    ("flags", Json.arr (flags.toArray.map vecsJson)), ("verdicts", toJson ((verdictAll base flags).map verdictName))]).compress
  [consts] ++ hs ++ ws ++ cs ++ vs ++ [all]

def goldenText (_ : Unit := ()) : String := String.intercalate "" (goldenLines.map (· ++ "\n"))

def argAfter : List String → String → Option String
  | a :: b :: rest, flag => if a == flag then some b else argAfter (b :: rest) flag
  | _, _ => none

def run (args : List String) : IO UInt32 := do
  match argAfter args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if cur.data == goldenText.toUTF8.data then
      IO.eprintln s!"offscreen golden: {path} is up to date ({goldenLines.length} lines)"
      return 0
    IO.eprintln s!"offscreen golden: {path} differs from the generated bytes"
    return 1
  | none =>
    IO.print goldenText
    return 0

end Fw.Measure.OffscreenGolden

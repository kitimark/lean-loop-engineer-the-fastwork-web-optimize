import Lean.Data.Json
import Fw.Device.Replay
import Fw.Device.ReplayProfiles
/-! Golden cases of `packages/contracts/golden/device/replay.jsonl`, on synthetic touch streams. -/
namespace Fw.Device.Replay
open Lean
open Fw.Device.Session (Touch Phase Zone t0Of replayStrokes)

def actJ : Act → Json
  | .move x y d => toJson [Json.str "m", Json.num x, Json.num y, Json.num d]
  | .down => toJson [Json.str "d"]
  | .up => toJson [Json.str "u"]
  | .pause d => toJson [Json.str "p", Json.num d]

private def pointerJ (a : Act) : Json :=
  match a with
  | .move x y d => Json.mkObj [("type", "pointerMove"), ("duration", d), ("x", x), ("y", y), ("origin", "viewport")]
  | .down => Json.mkObj [("type", "pointerDown"), ("button", (0 : Nat))]
  | .up => Json.mkObj [("type", "pointerUp"), ("button", (0 : Nat))]
  | .pause d => Json.mkObj [("type", "pause"), ("duration", d)]

/-- The W3C Perform Actions payload of a list of actions: one touch pointer source. -/
def w3c (acts : List Act) : Json :=
  Json.mkObj [("actions", Json.arr #[Json.mkObj [("type", "pointer"), ("id", "finger"),
    ("parameters", Json.mkObj [("pointerType", "touch")]), ("actions", Json.arr (acts.map pointerJ).toArray)]])]

private def swipeJ (s : Swipe) : Json :=
  Json.mkObj [("start", s.start), ("lift", s.lift),
    ("s", Json.arr (s.samples.map fun e => toJson [e.t, e.x, e.y]).toArray)]

private def swipesJ (l : List Swipe) : Json := Json.arr (l.map swipeJ).toArray

private def profileJ (p : Profile) : Json :=
  Json.mkObj [("id", p.id), ("w", p.w), ("h", p.h), ("load", match p.load with | .warm => "warm" | .cold => "cold"),
    ("swipes", swipesJ p.swipes)]

private def optJ (o : Option Profile) : Json := match o with | some p => profileJ p | none => Json.null

private def touchJ (e : Touch) : Json := toJson [Json.num e.t, Json.str e.ph.code, Json.num e.x, Json.num e.y, Json.num e.n]

private def limJ (l : Lim) : Json :=
  Json.mkObj [("pos", l.pos), ("time", l.time), ("speedPct", l.speedPct), ("startGap", l.startGap), ("window", l.window)]

/-- A finger down at `(x, y0)` at `t0`, `n` moves of `(0, dy)` every `dt`, then lifted one `dt` later. -/
def stroke (t0 x y0 dy dt : Int) (n : Nat) (fingers : Nat := 1) : List Touch :=
  [⟨t0, .start, x, y0, fingers⟩] ++
    (List.range n).map (fun (i : Nat) => (⟨t0 + dt * ((i : Int) + 1), .move, x, y0 + dy * ((i : Int) + 1), fingers⟩ : Touch)) ++
    [⟨t0 + dt * ((n : Int) + 1), .stop, x, y0 + dy * ((n : Int) + 1), 0⟩]

def fixtureSorted : List Touch :=
  stroke 100000 1950 6000 (-400) 1650 8 ++ stroke 140000 1950 6500 (-700) 800 10 ++
  [⟨160000, .start, 1000, 3000, 1⟩, ⟨160800, .stop, 1000, 3000, 0⟩] ++ stroke 180000 1800 5000 (-250) 2000 6

def fixtureMulti : List Touch := stroke 100000 1950 6000 (-400) 1650 8 (fingers := 2) ++ stroke 140000 1950 6500 (-700) 800 10

private def frames : List (Int × Int) := [(0, 0), (100000, 1000), (140000, 30000), (180000, 95000)]

private def shiftY (d : Int) (s : Swipe) : Swipe := { s with samples := s.samples.map fun e => { e with y := e.y + d } }
private def shiftLast (d : Int) (s : Swipe) : Swipe :=
  { s with samples := s.samples.mapIdx fun i e => if i + 1 = s.samples.length then { e with t := e.t + d } else e }
private def dropOne (s : Swipe) : Swipe := { s with samples := s.samples.drop 1 }
private def moveStart (d : Int) (s : Swipe) : Swipe := { s with start := s.start + d }
private def nudge (s : Swipe) : Swipe :=
  { s with samples := s.samples.map fun e => { e with y := e.y + 3, t := e.t + 500 }, lift := s.lift + 500 }
private def faster2 (s : Swipe) : Swipe :=
  { s with samples := s.samples.mapIdx fun i e => if i + 1 = s.samples.length then { e with y := e.y - 400 } else e }

private def loose : Lim := { pos := 100000, time := 100000, speedPct := 100000, startGap := 100000, window := 5000 }

private def conjJ (lim : Lim) (a b : Swipe) : Json :=
  Json.mkObj [("eventsOk", eventsOk a b), ("posOk", posOk lim a b), ("timeOk", timeOk lim a b), ("speedOk", speedOk lim a b),
    ("startOk", startOk lim a b), ("swipe", swipeMatches lim a b)]

private def matchJ (name : String) (lim : Lim) (src rep : List Swipe) : Json :=
  Json.mkObj [("kind", "match"), ("name", name), ("lim", limJ lim), ("src", swipesJ src), ("rep", swipesJ rep),
    ("conj", Json.arr ((src.zip rep).map fun (a, b) => conjJ lim a b).toArray), ("replayMatches", replayMatches lim src rep)]

private def runKind (k : Kind) : Json := k.code

private def goldenLines (_ : Unit) : List String :=
  let src := swipesOf fixtureSorted
  let prof : Profile := ⟨"fixture", 390, 844, .warm, src⟩
  let one : Profile := ⟨"one", 390, 844, .warm, [{ start := 0, lift := 3000, samples := [⟨0, 1950, 6000⟩, ⟨1650, 1950, 5600⟩, ⟨3000, 1950, 5200⟩] }]⟩
  let lim : Lim := {}
  let pass := src.map nudge
  let hero := zoneLoop prof .hero 100000 frames (t0Of (replayStrokes fixtureSorted)) 2 50000
  let fin := zoneLoop prof .finish 100000 frames (t0Of (replayStrokes fixtureSorted)) 1 50000
  [ (Json.mkObj [("kind", "limits"), ("lim", limJ lim), ("tickMax", tickMax)]).compress,
    (Json.mkObj [("kind", "profile"), ("touches", Json.arr (fixtureSorted.map touchJ).toArray), ("w", (390 : Nat)), ("h", (844 : Nat)),
      ("profile", optJ (ofTouches "fixture" fixtureSorted 390 844))]).compress,
    (Json.mkObj [("kind", "profile"), ("touches", Json.arr (fixtureMulti.map touchJ).toArray), ("w", (390 : Nat)), ("h", (844 : Nat)),
      ("profile", optJ (ofTouches "multi" fixtureMulti 390 844))]).compress,
    (Json.mkObj [("kind", "compile"), ("profile", profileJ one), ("acts", Json.arr ((compile one).map actJ).toArray),
      ("w3c", w3c (compile one))]).compress,
    (Json.mkObj [("kind", "compile"), ("profile", profileJ prof), ("acts", Json.arr ((compile prof).map actJ).toArray)]).compress,
    (matchJ "same" lim src src).compress,
    (matchJ "nudged" lim src pass).compress,
    (matchJ "count" lim src (src.take 2)).compress,
    (matchJ "events" loose src (src.map dropOne)).compress,
    (matchJ "pos" { loose with pos := 10 } src (src.map (shiftY 30))).compress,
    (matchJ "time" { loose with time := 1700 } src (src.map (shiftLast 3000))).compress,
    (matchJ "speed" { loose with speedPct := 10 } src (src.map faster2)).compress,
    (matchJ "start" { loose with startGap := 5000 } src (src.map (moveStart 6000))).compress,
    (Json.mkObj [("kind", "fastest"), ("swipes", swipesJ src), ("speed2", toJson (src.map speed2)),
      ("down", toJson (src.map scrollsDown)), ("index", match fastest src with
        | some f => toJson ((src.findIdx? (· == f)).getD 0)
        | none => Json.null)]).compress,
    (Json.mkObj [("kind", "fastFling"), ("profile", profileJ prof), ("n", (3 : Nat)), ("gap", (40000 : Int)),
      ("out", optJ (fastFling prof 3 40000))]).compress,
    (Json.mkObj [("kind", "zoneLoop"), ("profile", profileJ prof), ("zone", "hero"), ("maxY10", (100000 : Int)),
      ("frames", toJson (frames.map fun f => [f.1, f.2])), ("t0", t0Of (replayStrokes fixtureSorted)), ("reps", (2 : Nat)),
      ("gap", (50000 : Int)), ("out", optJ hero)]).compress,
    (Json.mkObj [("kind", "zoneLoop"), ("profile", profileJ prof), ("zone", "finish"), ("maxY10", (100000 : Int)),
      ("frames", toJson (frames.map fun f => [f.1, f.2])), ("t0", t0Of (replayStrokes fixtureSorted)), ("reps", (1 : Nat)),
      ("gap", (50000 : Int)), ("out", optJ fin)]).compress,
    (Json.mkObj [("kind", "cold"), ("profile", profileJ prof), ("out", profileJ (cold prof))]).compress ] ++
  ((List.range 5).map fun n => (Json.mkObj [("kind", "rotation"), ("n", (n + 1 : Nat)),
    ("orders", Json.arr ((List.range 7).map fun r => toJson (rotation (n + 1) r)).toArray)]).compress) ++
  [ (Json.mkObj [("kind", "schedule"), ("reps", (3 : Nat)), ("n", (2 : Nat)),
      ("runs", Json.arr ((schedule [.recorded, .fastFling, .zoneHero, .zoneFinish, .cold] 3 2).map fun r =>
        Json.mkObj [("kind", runKind r.kind), ("rep", r.rep), ("order", toJson r.order)]).toArray)]).compress ]

/-- The golden file's text, one case per line. -/
def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

/-- Print the golden, or with `--check <file>` compare its bytes; exit 1 when they differ. -/
def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"device-replay golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"device-replay golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Device.Replay

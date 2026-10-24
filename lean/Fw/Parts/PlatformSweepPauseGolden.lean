import Lean.Data.Json
import Fw.Parts.PlatformSweepPause
/-!
# Golden vectors for `platform.sweep:offscreen-pause`
-/
namespace Fw.Parts.PlatformSweepPauseGolden
open Lean Fw.Parts.PlatformSweepPause
open Fw.Parts.PlatformSweep (phase period)

def ratWire (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

def numJ (q : Rat) : Json := if q.den = 1 then .num q.num else ratWire q

def frameJ (f : Step) : Json := Json.mkObj [("d", numJ f.1), ("vis", .bool f.2.1), ("rep", .bool f.2.2)]

def outs (o : Rat) (tr : List Step) : List Json :=
  let rec go (s : St) : List Step → List Json
    | [] => []
    | f :: t =>
      let a := seek s f
      Json.mkObj [("loc", numJ a.loc), ("phase", numJ (phase a.loc)), ("ticks", .num (ticks f)),
        ("paused", .bool a.paused)] :: go (step s f) t
  go (init o) tr

def traceLine (name : String) (o : Rat) (tr : List Step) : String :=
  (Json.mkObj [("fn", "trace"),
    ("in", Json.mkObj [("case", .str name), ("off", numJ o), ("frames", .arr (tr.map frameJ).toArray)]),
    ("out", .arr (outs o tr).toArray)]).compress

def origLine (o : Rat) (tr : List Step) : String :=
  (Json.mkObj [("fn", "orig"), ("in", Json.mkObj [("off", numJ o), ("frames", .arr (tr.map frameJ).toArray)]),
    ("out", numJ (orig o tr))]).compress

def leaveReturn : Rat × List Step :=
  (0, [(16, true, false), (16, true, false), (16, false, false), (1000, false, true), (3000, false, true),
    (500, false, true), (16, true, false), (16, true, false)])

def mountedOff : Rat × List Step :=
  (1234, [(16, false, true), (2000, false, true), (16, true, false), (16, true, false)])

def flicker : Rat × List Step :=
  (777, [(16, true, false), (16, false, false), (16, false, true), (16, true, false), (16, false, false),
    (16, false, true), (16, false, true), (4000, false, true), (16, true, false)])

def cases : List (String × Rat × List Step) :=
  [("leave-return", leaveReturn), ("mounted-offscreen", mountedOff), ("flicker", flicker)]

def constLine : String :=
  (Json.mkObj [("fn", "const"), ("in", Json.mkObj []),
    ("out", Json.mkObj [("periodMs", numJ period), ("flag", "platform.sweep:offscreen-pause"),
      ("variant", "offscreen-pause")])]).compress

def lines (_ : Unit := ()) : List String :=
  constLine :: (cases.flatMap fun (n, o, t) => [traceLine n o t, origLine o t])

def goldenText (_ : Unit := ()) : String := String.join ((lines ()).map (· ++ "\n"))

def sameOnVisible (o : Rat) (tr : List Step) : Bool :=
  (List.range tr.length).all fun k =>
    let f := tr.getD k (0, true, false)
    !f.2.1 || (seek (run (init o) (tr.take k)) f).loc == orig o (tr.take k)

#guard cases.all fun (_, o, t) => sameOnVisible o t
#guard (lines ()).length == 7

def run' (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText () then
      IO.eprintln s!"platform-sweep-pause golden: {path} is up to date ({(lines ()).length} lines)"
      return 0
    IO.eprintln s!"platform-sweep-pause golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Parts.PlatformSweepPauseGolden

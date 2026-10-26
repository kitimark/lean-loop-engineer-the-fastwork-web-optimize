import Lean.Data.Json
import Fw.Parts.PlatformFadedPause
/-!
# Golden vectors for `platform:faded-pause`
(`packages/contracts/golden/parts/platform-faded-pause.jsonl`)
-/
namespace Fw.Parts.PlatformFadedPauseGolden
open Lean Fw.Parts.PlatformFadedPause
open Fw.Parts.MorphTween (fade fadeEnd)
open Fw.Parts.PlatformSweepPause (init seek step ticks run orig)
open Fw.Parts.PlatformSweep (phase)
open Fw.Parts.PlatformGlintPause (Cont P Obs)

def ratWire (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

def numJ (q : Rat) : Json := if q.den = 1 then .num q.num else ratWire q

def framesJ (tr : List (Rat × Rat)) : Json :=
  .arr (tr.map fun x => Json.mkObj [("d", numJ x.1), ("m", numJ x.2)]).toArray

/-- CSS trace: per frame the seeked location, wrapped phase, ticks and paused flag. -/
def cssOuts (o : Rat) (tr : List (Rat × Rat)) : List Json :=
  let rec go (s : Fw.Parts.PlatformSweepPause.St) : List (Rat × Rat) → List Json
    | [] => []
    | x :: t =>
      let f := stepOf x.1 x.2
      let a := seek s f
      Json.mkObj [("loc", numJ a.loc), ("phase", numJ (phase a.loc)), ("ticks", .num (ticks f)),
        ("paused", .bool a.paused)] :: go (step s f) t
  go (init o) tr

def cssLine (name : String) (o : Rat) (tr : List (Rat × Rat)) : String :=
  (Json.mkObj [("fn", "css"), ("in", Json.mkObj [("case", .str name), ("off", numJ o), ("frames", framesJ tr)]),
    ("out", .arr (cssOuts o tr).toArray)]).compress

def origLine (o : Rat) (tr : List (Rat × Rat)) : String :=
  (Json.mkObj [("fn", "orig"), ("in", Json.mkObj [("off", numJ o), ("frames", framesJ tr)]),
    ("out", numJ (origCss o tr))]).compress

def glintOuts (b : Rat) (evs : List (Rat × Rat)) : List Json :=
  let rec go (p : P) : List (Rat × Rat) → List Json
    | [] => []
    | x :: t =>
      let o := obsOf x.1 x.2
      let q := p.step o
      let sk : Json := match o with
        | .hide _ => .null
        | .reveal t' => match p.target t' with
          | some v => numJ v
          | none => .null
      Json.mkObj [("seek", sk), ("paused", .bool q.c.paused)] :: go q t
  go ⟨Cont.start b, -b⟩ evs

def glintLine (name : String) (b : Rat) (evs : List (Rat × Rat)) : String :=
  (Json.mkObj [("fn", "glint"), ("in", Json.mkObj [("case", .str name), ("birth", numJ b), ("frames", framesJ evs)]),
    ("out", .arr (glintOuts b evs).toArray)]).compress

def fadeLine (m : Rat) : String :=
  (Json.mkObj [("fn", "fade"), ("in", Json.mkObj [("m", numJ m)]),
    ("out", Json.mkObj [("fade", numJ (fade m)), ("zero", .bool (zero m))])]).compress

def sceneLine (a f : Bool) : String :=
  (Json.mkObj [("fn", "scene"), ("in", Json.mkObj [("active", .bool a), ("faded", .bool f)]),
    ("out", .str (scene a f))]).compress

def constLine : String :=
  (Json.mkObj [("fn", "const"), ("in", Json.mkObj []),
    ("out", Json.mkObj [("fadeEnd", numJ fadeEnd), ("flag", "platform:faded-pause"), ("variant", "faded-pause")])]).compress

/-- Open, fade out, pause, close back and see the section again. -/
def openClose : Rat × List (Rat × Rat) :=
  (0, [(16, 0), (16, 1/10), (16, 3/10), (16, 11/20), (1000, 3/5), (3000, 1), (16, 1/2), (16, 1/4), (16, 0)])

/-- Settled open for a long time, then a reverse. -/
def longOpen : Rat × List (Rat × Rat) :=
  (1234, [(16, 1/2), (16, 11/20), (5000, 1), (16, 11/20), (7000, 1), (16, 2/5), (16, 0)])

/-- The edge: m just below and exactly at the end. -/
def edge : Rat × List (Rat × Rat) :=
  (777, [(16, 1099/2000), (16, 11/20), (16, 1099/2000), (16, 11/20), (16, 11/20), (16, 1/2)])

def cases : List (String × Rat × List (Rat × Rat)) :=
  [("open-close", openClose), ("long-open", longOpen), ("edge", edge)]

def glintCases : List (String × Rat × List (Rat × Rat)) :=
  [("open-close", 0, [(100, 0), (200, 1/2), (300, 11/20), (4300, 3/5), (4400, 1/2), (4500, 0)]),
   ("late-birth", 250, [(300, 11/20), (400, 1), (9000, 1/10), (9100, 3/5), (9200, 3/5), (9300, 0)])]

def lines (_ : Unit := ()) : List String :=
  [constLine] ++ [0, 1/10, 1/2, 1099/2000, 11/20, 3/5, 1].map fadeLine ++
  [sceneLine true false, sceneLine true true, sceneLine false false, sceneLine false true] ++
  cases.flatMap (fun (n, o, t) => [cssLine n o t, origLine o t]) ++
  glintCases.map fun (n, b, e) => glintLine n b e

def goldenText (_ : Unit := ()) : String := String.join ((lines ()).map (· ++ "\n"))

/-- Every non-faded frame sits at the faithful location. -/
def sameOnVisible (o : Rat) (tr : List (Rat × Rat)) : Bool :=
  (List.range tr.length).all fun k =>
    let x := tr.getD k (0, 0)
    zero x.2 || (seek (run (init o) ((tr.take k).map fun y => stepOf y.1 y.2)) (stepOf x.1 x.2)).loc == origCss o (tr.take k)

#guard cases.all fun (_, o, t) => sameOnVisible o t
#guard (lines ()).length == 20

def run' (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText () then
      IO.eprintln s!"platform-faded-pause golden: {path} is up to date ({(lines ()).length} lines)"
      return 0
    IO.eprintln s!"platform-faded-pause golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Parts.PlatformFadedPauseGolden

import Lean.Data.Json
import Fw.Parts.PlatformGlintHold
/-! Golden vectors for `platform.glint:hold-freeze` (`packages/contracts/golden/parts/platform-glint-hold.jsonl`). -/
namespace Fw.Parts.PlatformGlintHoldGolden
open Lean Fw.Parts.PlatformGlint Fw.Parts.PlatformGlintHold
open Fw.Parts.PlatformGlintPause (P Obs Cont)

def ratWire (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

def numJ (q : Rat) : Json := if q.den = 1 then .num q.num else ratWire q

def sideName : Side → String
  | .left => "left"
  | .right => "right"

def attrName : Attr → String
  | .x1 => "x1"
  | .x2 => "x2"

def kindName : Kind → String
  | .set => "set"
  | .ramp => "ramp"

def pairJ (p : Rat × Rat) : Json := .arr #[numJ p.1, numJ p.2]

def pieceJ (s : Side) (a : Attr) (k : Nat) : Json :=
  Json.mkObj [("attr", .str (attrName a)), ("seg", .num k), ("kind", .str (kindName (kindOf a s k))),
    ("from", numJ (segFrom a s k)), ("to", numJ (segTo a s k))]

def planLine (s : Side) : String :=
  (Json.mkObj [("fn", "glint.hold.plan"), ("in", Json.mkObj [("side", .str (sideName s))]),
    ("out", .arr (((List.range 5).map (pieceJ s .x1)) ++ ((List.range 5).map (pieceJ s .x2))).toArray)]).compress

def elapsedSamples : List Rat :=
  [0, 250, 500, 999, 1000, 1500, 1999, 2000, 2500, 2999, 3000, 3500, 3999, 4000, 4500, 4999, 5000, 5250, 6000,
   7500, 8001, 9999, 10000, 12345, 3600000]

def sampleLine (s : Side) (e : Rat) : String :=
  (Json.mkObj [("fn", "glint.hold.sample"), ("in", Json.mkObj [("side", .str (sideName s)), ("elapsed", numJ e)]),
    ("out", pairJ (holdSample s e))]).compress

def tickingLine (s : Side) (e : Rat) : String :=
  (Json.mkObj [("fn", "glint.hold.ticking"), ("in", Json.mkObj [("side", .str (sideName s)), ("elapsed", numJ e)]),
    ("out", Json.mkObj [("hold", .num (ticking s e)), ("faithful", .num faithfulTicking)])]).compress

def holdSegs (s : Side) : Json := .arr (((List.range 5).filter (holds s)).map fun (k : Nat) => Json.num k).toArray

def constLine : String :=
  (Json.mkObj [("fn", "glint.hold.const"), ("in", Json.mkObj []),
    ("out", Json.mkObj [("segMs", numJ 1000), ("left", holdSegs .left), ("right", holdSegs .right)])]).compress

def obsKind : Obs → String
  | .hide _ => "hide"
  | .reveal _ => "reveal"

def obsT : Obs → Rat
  | .hide t => t
  | .reveal t => t

/-- A pause and resume run: after each event the pairs at the listed frames (the container reads the uninterrupted clock
whenever it runs; while paused it is frozen at the value read at the pause). -/
def runLine (name : String) (s : Side) (b : Rat) (r : List (Obs × List Rat)) : String :=
  let res := r.foldl (fun (acc : P × List Json) (x : Obs × List Rat) =>
    let q := acc.1.step x.1
    (q, acc.2 ++ [.arr (x.2.map fun f => pairJ (holdSample s (q.c.elapsed f))).toArray])) (⟨Cont.start b, -b⟩, [])
  (Json.mkObj [("fn", "glint.hold.run"),
    ("in", Json.mkObj [("case", .str name), ("side", .str (sideName s)), ("b", numJ b),
      ("events", .arr (r.map fun (o, fs) => Json.mkObj [("kind", .str (obsKind o)), ("t", numJ (obsT o)),
        ("frames", .arr (fs.map numJ).toArray)]).toArray)]),
    ("out", .arr res.2.toArray)]).compress

def fr (t : Rat) : List Rat := [t, t + 16, t + 1000, t + 2500]

def runA : List (Obs × List Rat) :=
  [(.reveal 500, fr 500), (.hide 1000, fr 1000), (.hide 1200, fr 1200), (.reveal 4000, fr 4000),
   (.reveal 4100, fr 4100), (.hide 4500, fr 4500), (.reveal 4501, fr 4501), (.hide 9000, fr 9000),
   (.reveal 123456, fr 123456)]

def runB : List (Obs × List Rat) := [(.hide 100, fr 100), (.reveal 101, fr 101), (.hide 60000, [60000, 61000]), (.reveal 3600000, fr 3600000)]

def lines (_ : Unit) : List String :=
  [constLine, planLine .left, planLine .right] ++
    (([Side.left, Side.right].map fun s => elapsedSamples.map (sampleLine s)).flatten) ++
    (([Side.left, Side.right].map fun s => elapsedSamples.map (tickingLine s)).flatten) ++
    [runLine "A" .left 0 runA, runLine "A" .right 0 runA, runLine "B" .left 50 runB, runLine "B" .right 50 runB]

#guard (lines ()).length == 1 + 2 + 2 * elapsedSamples.length + 2 * elapsedSamples.length + 4

def goldenText : String := "\n".intercalate (lines ()) ++ "\n"

/-- `--check` compares the file with the generated text; without it the file is written. -/
def gen (args : List String) : IO Unit := do
  let path := "../packages/contracts/golden/parts/platform-glint-hold.jsonl"
  if args.contains "--check" then
    let disk ← IO.FS.readFile path
    if disk != goldenText then throw (IO.userError s!"platform-glint-hold: {path} is stale; regenerate with Fw.Parts.PlatformGlintHoldGolden.gen []")
    IO.println s!"platform-glint-hold: {path} equals the Lean output, {(lines ()).length} lines"
  else
    IO.FS.writeFile path goldenText

end Fw.Parts.PlatformGlintHoldGolden

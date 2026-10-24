import Lean.Data.Json
import Fw.Parts.PlatformGlintPause
/-! Golden vectors for `platform.glint:offscreen-pause` (`packages/contracts/golden/parts/platform-glint-pause.jsonl`). -/
namespace Fw.Parts.PlatformGlintPauseGolden
open Lean Fw.Parts.PlatformGlintPause

def ratWire (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

def numJ (q : Rat) : Json := if q.den = 1 then .num q.num else ratWire q

def obsKind : Obs → String
  | .hide _ => "hide"
  | .reveal _ => "reveal"

def obsT : Obs → Rat
  | .hide t => t
  | .reveal t => t

def act (p : P) : Obs → String
  | .hide _ => if p.c.paused then "none" else "pause"
  | .reveal _ => if p.c.paused then "resume-seek" else "none"

def seekJ (p : P) : Obs → Json
  | .hide _ => .null
  | .reveal t => match p.target t with
    | some x => numJ x
    | none => .null

def stepLine (p : P) (o : Obs) : String :=
  let q := p.step o
  (Json.mkObj [("fn", "glint.pause.step"),
    ("in", Json.mkObj [("paused", .bool p.c.paused), ("off", numJ p.off), ("ev", .str (obsKind o)),
      ("t", numJ (obsT o)), ("read", numJ (p.c.elapsed (obsT o)))]),
    ("out", Json.mkObj [("act", .str (act p o)), ("seek", seekJ p o), ("paused", .bool q.c.paused),
      ("off", numJ q.off)])]).compress

def stepLines (b : Rat) (os : List Obs) : List String :=
  (os.foldl (fun (acc : P × List String) o => (acc.1.step o, acc.2 ++ [stepLine acc.1 o])) (⟨Cont.start b, -b⟩, [])).2

abbrev Run := List (Obs × List Rat)

def runLine (name : String) (b : Rat) (r : Run) : String :=
  let res := r.foldl (fun (acc : P × List Json) (x : Obs × List Rat) =>
    let q := acc.1.step x.1
    (q, acc.2 ++ [.arr (x.2.map fun s => numJ (q.c.elapsed s)).toArray])) (⟨Cont.start b, -b⟩, [])
  (Json.mkObj [("fn", "glint.pause.run"),
    ("in", Json.mkObj [("case", .str name), ("b", numJ b),
      ("events", .arr (r.map fun (o, fs) => Json.mkObj [("kind", .str (obsKind o)), ("t", numJ (obsT o)),
        ("frames", .arr (fs.map numJ).toArray)]).toArray)]),
    ("out", Json.mkObj [("elapsed", .arr res.2.toArray), ("paused", .bool res.1.c.paused)])]).compress

def fr (t : Rat) : List Rat := [t, t + 16, t + 1000]

def runA : Run :=
  [(.reveal 500, fr 500), (.hide 1000, fr 1000), (.hide 1200, fr 1200), (.reveal 4000, fr 4000),
   (.reveal 4100, fr 4100), (.hide 4500, fr 4500), (.reveal 4501, fr 4501), (.hide 9000, fr 9000),
   (.reveal 123456, fr 123456)]

def runB : Run := [(.hide 100, fr 100), (.reveal 101, fr 101), (.hide 60000, [60000, 61000]), (.reveal 3600000, fr 3600000)]

def stepTrace : List Obs :=
  [.reveal 500, .hide 1000, .hide 1200, .reveal 4000, .reveal 4100, .hide 4500, .reveal 4501]

def ioJ (t : Rat) : Io → Json
  | .ratio r => Json.mkObj [("kind", "ratio"), ("t", numJ t), ("ratio", numJ r)]
  | .reduced b => Json.mkObj [("kind", "reduced"), ("t", numJ t), ("value", .bool b)]
  | .fire => Json.mkObj [("kind", "fire"), ("t", numJ t)]

def wJ (w : W) : Json :=
  Json.mkObj [("v", .bool w.g.v), ("h", .bool w.g.h), ("paused", .bool w.p.c.paused), ("away", .bool w.away)]

def jointLine (name : String) (b : Rat) (reduced : Bool) (es : List (Rat × Io)) : String :=
  let res := es.foldl (fun (acc : W × List Json) (x : Rat × Io) =>
    let w := acc.1.step x.1 x.2
    (w, acc.2 ++ [wJ w])) (W.init b reduced, [])
  (Json.mkObj [("fn", "glint.pause.joint"),
    ("in", Json.mkObj [("case", .str name), ("b", numJ b), ("reduced", .bool reduced),
      ("events", .arr (es.map fun (t, e) => ioJ t e).toArray)]),
    ("out", .arr res.2.toArray)]).compress

def jointA : List (Rat × Io) :=
  [(0, .ratio 0), (100, .ratio (2 / 5)), (1100, .fire), (3000, .ratio 0), (3500, .ratio (1 / 5)), (4000, .ratio (1 / 2)),
   (4500, .fire), (5000, .fire), (7000, .ratio 0), (9000, .ratio (7 / 10)), (9100, .reduced true), (9200, .reduced false),
   (10200, .fire), (12000, .ratio (1 / 5)), (12500, .ratio (1 / 2))]

def jointB : List (Rat × Io) :=
  [(0, .ratio (3 / 5)), (500, .ratio 0), (1000, .fire), (1500, .ratio (3 / 5)), (2500, .fire), (3000, .ratio 0),
   (3100, .ratio 0), (3200, .ratio (1 / 100)), (4300, .fire)]

def ticksLine (paused armed : Bool) : String :=
  (Json.mkObj [("fn", "glint.pause.ticks"),
    ("in", Json.mkObj [("paused", .bool paused), ("armed", .bool armed)]),
    ("out", .num (ticks ⟨0, 0, paused⟩ armed))]).compress

def constLine : String :=
  (Json.mkObj [("fn", "glint.pause.const"), ("in", Json.mkObj []),
    ("out", Json.mkObj [("awayRatio", numJ 0), ("events", .arr #[.str "hide", .str "reveal"]),
      ("acts", .arr #[.str "none", .str "pause", .str "resume-seek"])])]).compress

def lines (_ : Unit) : List String :=
  constLine :: stepLines 0 stepTrace ++ stepLines 250 [.hide 1000, .reveal 2000] ++
    [runLine "A" 0 runA, runLine "B" 50 runB, jointLine "A" 0 false jointA, jointLine "B" 0 false jointB,
     jointLine "reduced" 0 true jointA] ++
    [ticksLine false false, ticksLine false true, ticksLine true false, ticksLine true true]

#guard (lines ()).length == 1 + 7 + 2 + 2 + 3 + 4

#guard (runA.foldl (fun (p : P) x => p.step x.1) ⟨Cont.start 0, 0⟩).c.elapsed 123456 == 123456
#guard (runB.foldl (fun (p : P) x => p.step x.1) ⟨Cont.start 50, -50⟩).c.elapsed 3600000 == 3600000 - 50

#guard ((jointA.take 13).foldl (fun (w : W) x => w.step x.1 x.2) (W.init 0 false)).g.v == true

def text (_ : Unit) : String := String.intercalate "\n" (lines ()) ++ "\n"

def runGolden (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == text () then
      IO.eprintln s!"platform.glint pause golden: {path} is up to date"
      return 0
    IO.eprintln s!"platform.glint pause golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (text ())
    return 0

end Fw.Parts.PlatformGlintPauseGolden

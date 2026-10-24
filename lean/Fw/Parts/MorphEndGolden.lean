import Lean.Data.Json
import Fw.Parts.MorphEnd
/-! Golden vectors for the morph end bricks: three recorded-style cases, each under all 8 picks, event by event
(`packages/contracts/golden/parts/morph.end.jsonl`). -/
namespace Fw.Parts.MorphEndGolden
open Lean Fw.Parts.MorphEnd

def ratWire (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

def numJ (q : Rat) : Json := if q.den = 1 then .num q.num else ratWire q

def optJ : Option Rat → Json
  | some q => numJ q
  | none => .null

def readJ (r : Read) : List (String × Json) :=
  [("scrollY", numJ r.scrollY), ("arm", .bool r.arm), ("now", numJ r.now), ("reduced", .bool r.reduced)]

def evJ : Ev → Json
  | .touchstart y => Json.mkObj [("ev", "touchstart"), ("y", optJ y)]
  | .touchmove y r => Json.mkObj ([("ev", .str "touchmove"), ("y", optJ y)] ++ readJ r)
  | .wheel d r => Json.mkObj ([("ev", .str "wheel"), ("delta", numJ d)] ++ readJ r)
  | .scroll y m => Json.mkObj [("ev", "scroll"), ("y", numJ y), ("maxY", numJ m)]
  | .resize y m => Json.mkObj [("ev", "resize"), ("y", numJ y), ("maxY", numJ m)]
  | .tick now => Json.mkObj [("ev", "tick"), ("now", numJ now)]

def outJ (o : Out) (s : S) : Json :=
  Json.mkObj [("prevent", .bool o.prevent), ("goal", optJ o.goal), ("flip", .bool o.flip), ("write", optJ o.write),
    ("active", .bool s.tw.isActive), ("value", ratWire s.tw.value), ("pin", numJ s.pin)]

def run (h : Hooks) : S → List Ev → List (Ev × Out × S)
  | _, [] => []
  | s, e :: t => (e, (step h s e).2, (step h s e).1) :: run h (step h s e).1 t

def cfgJ (c : Cfg) : Json := Json.mkObj [("clamp", .bool c.clamp), ("flip", .bool c.flip), ("release", .bool c.release)]

def mv (finger y now : Rat) : Ev := .touchmove (some finger) (rd y now)

def springBack : Rat × List Ev :=
  (5200, [.touchstart (some 600), mv 560 5292 0, .scroll 5292 5227, .tick 100, .scroll 5250 5227, .tick 440,
    .scroll 5227 5227, .tick 780, .scroll 5292 5227, .resize 5227 5267])

def wiggle : Rat × List Ev :=
  (5227, [.touchstart (some 600), mv 560 5227 0, .tick 50, mv 561 5227 60, .scroll 5226 5227, mv 560 5227 70,
    mv 561 5227 80, .scroll 5226 5227, mv 560 5227 90, .tick 120, mv 580 5227 130, .scroll 5210 5227, .tick 400])

def dragBack : Rat × List Ev :=
  (5100, [.touchstart (some 600), mv 550 5250 0, .tick 400, .tick 1000, .scroll 5227 5227, .touchstart (some 400),
    mv 430 5227 1100, mv 470 5227 1110, .scroll 5200 5227, mv 460 5200 1120, mv 440 5200 1130, .scroll 5180 5227,
    .tick 1200, .scroll 5190 5227])

def cases : List (String × Rat × List Ev) :=
  [("spring-back", springBack), ("wiggle", wiggle), ("drag-back", dragBack)]

def caseLine (name : String) (y : Rat) (t : List Ev) (c : Cfg) : String :=
  (Json.mkObj [("fn", "morph.end"),
    ("in", Json.mkObj [("case", .str name), ("cfg", cfgJ c), ("init", numJ y), ("events", .arr (t.map evJ).toArray)]),
    ("out", .arr ((run c.hooks (init y) t).map fun (_, o, s) => outJ o s).toArray)]).compress

def constLine : String :=
  (Json.mkObj [("fn", "morph.end.const"), ("in", Json.mkObj []),
    ("out", Json.mkObj [("flipN", numJ flipN), ("ids", .arr #[.str clampId, .str flipId, .str releaseId]),
      ("off", .str faithfulV), ("on", .str onV)])]).compress

def lines (_ : Unit) : List String :=
  constLine :: cases.flatMap fun (n, y, t) => Cfg.all.map (caseLine n y t)

#guard (lines ()).length == 1 + 3 * 8
#guard cases.all fun (_, y, t) => Cfg.all.all fun c =>
  (run c.hooks (init y) t).map (fun (e, o, _) => (e, o)) == trace c.hooks (init y) t
#guard cases.all fun (_, _, t) => t.all fun
  | .touchmove (some f) r => f.den == 1 && r.scrollY.den == 1 && r.now.den == 1
  | .touchstart (some f) => f.den == 1
  | .scroll y m | .resize y m => y.den == 1 && m.den == 1
  | .tick now => now.den == 1
  | _ => false

def outs (c : Cfg) (cs : Rat × List Ev) : List Out := (trace c.hooks (init cs.1) cs.2).map (·.2)

#guard (outs Cfg.faithful springBack).map (·.write) ==
  [none, none, none, none, some 5292, none, some 5292, none, none, some 5292]
#guard (outs ⟨true, false, false⟩ springBack).map (·.write) ==
  [none, none, some 5227, none, some 5227, none, none, none, some 5227, some 5267]
#guard ((outs Cfg.faithful wiggle).filter (·.flip)).length == 5
#guard ((outs ⟨false, true, false⟩ wiggle).filter (·.flip)).length == 1
#guard (outs ⟨true, false, false⟩ dragBack).map (·.write) ==
  [none, none, none, none, none, none, none, none, some 5227, none, none, some 5227, none, some 5227]
#guard (outs ⟨true, false, true⟩ dragBack).map (·.write) ==
  [none, none, none, none, none, none, none, none, none, none, none, some 5200, none, some 5200]
#guard (outs ⟨true, false, true⟩ dragBack).map (·.prevent) ==
  [false, true, false, false, false, false, false, false, false, true, true, false, false, false]

def text (_ : Unit) : String := String.intercalate "\n" (lines ()) ++ "\n"

def runGolden (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == text () then
      IO.eprintln s!"morph.end golden: {path} is up to date"
      return 0
    IO.eprintln s!"morph.end golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (text ())
    return 0

end Fw.Parts.MorphEndGolden

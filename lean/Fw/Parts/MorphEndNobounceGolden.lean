import Lean.Data.Json
import Fw.Parts.MorphEndNobounce
import Fw.Parts.MorphEndGolden
/-! Golden vectors for the pin-write rule under no bounce: three recorded-style cases, each under all 8 brick picks
(`packages/contracts/golden/parts/morph-end-nobounce.jsonl`). Two cases read positions only up to the end (no bounce);
the third reads one position above the end (a bounce) as the contrast. -/
namespace Fw.Parts.MorphEndNobounceGolden
open Lean Fw.Parts.MorphEnd Fw.Parts.MorphEndGolden Fw.Parts.MorphEndNobounce

/-- Forward pushes at the end with the page staying at the end. -/
def pushAtEnd : Rat × List Ev :=
  (5227, [.touchstart (some 600), mv 560 5227 0, .scroll 5227 5227, .tick 100, mv 540 5227 110, .scroll 5227 5227,
    .tick 440, .scroll 5227 5227, .resize 5227 5227])

/-- A short reversal near the end: the page sits a few pixels under the pin, the pin is written back. -/
def reverseNearEnd : Rat × List Ev :=
  (5227, [.touchstart (some 600), mv 560 5227 0, .tick 50, .scroll 5227 5227, mv 585 5227 60, .scroll 5222 5227,
    .scroll 5227 5227, .tick 400])

/-- The same push with a rubber band: the page is read above the end once. -/
def bounceContrast : Rat × List Ev :=
  (5227, [.touchstart (some 600), mv 560 5227 0, .scroll 5292 5227, .tick 100, .scroll 5227 5227])

def cases : List (String × Bool × Rat × List Ev) :=
  [("push-at-end", false, pushAtEnd), ("reverse-near-end", false, reverseNearEnd), ("bounce-contrast", true, bounceContrast)]

def caseLine (name : String) (bounce : Bool) (y : Rat) (t : List Ev) (c : Cfg) : String :=
  (Json.mkObj [("fn", "morph.end.nobounce"),
    ("in", Json.mkObj [("case", .str name), ("bounce", .bool bounce), ("cfg", cfgJ c), ("init", numJ y),
      ("events", .arr (t.map evJ).toArray)]),
    ("out", .arr ((run c.hooks (init y) t).map fun (_, o, s) => outJ o s).toArray)]).compress

def constLine : String :=
  (Json.mkObj [("fn", "morph.end.nobounce.const"), ("in", Json.mkObj []),
    ("out", Json.mkObj [("id", .str flagId), ("css", .str css), ("on", .str onV), ("off", .str faithfulV)])]).compress

def lines (_ : Unit) : List String :=
  constLine :: cases.flatMap fun (n, b, y, t) => Cfg.all.map (caseLine n b y t)

#guard (lines ()).length == 1 + 3 * 8

def writes (c : Cfg) (cs : Rat × List Ev) : List (Option Rat) :=
  (trace c.hooks (init cs.1) cs.2).map (·.2.write)

#guard Cfg.all.all fun c => (writes c pushAtEnd).all (· == none)
#guard writes Cfg.faithful reverseNearEnd == [none, none, none, none, none, some 5227, none, none]
#guard writes Cfg.faithful bounceContrast == [none, none, some 5227, none, none]

def text (_ : Unit) : String := String.intercalate "\n" (lines ()) ++ "\n"

def runGolden (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == text () then
      IO.eprintln s!"morph.end.nobounce golden: {path} is up to date"
      return 0
    IO.eprintln s!"morph.end.nobounce golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (text ())
    return 0

end Fw.Parts.MorphEndNobounceGolden

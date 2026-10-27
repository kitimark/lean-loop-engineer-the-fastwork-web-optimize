import Lean.Data.Json
import Fw.Parts.MorphStyle
namespace Fw.Parts.MorphStyleGolden
open Lean Fw.Parts.MorphStyle

def writeList : List Write := [.navMorph, .navAttr, .platFade]

def consumerLine (w : Write) (md : Mode) : String :=
  (Json.mkObj [("fn", "morph.style.consumers"),
    ("in", Json.mkObj [("write", .str w.name), ("mode", .str md.name)]),
    ("out", Json.mkObj [("files", .arr ((consumers w md).map Json.str).toArray), ("skippable", .bool (skippable w))])]).compress

def milli : List Int := [0, 1, 250, 500, 999, 1000]

def writesLine (flip : Bool) (mm : Int) : String :=
  (Json.mkObj [("fn", "morph.style.writes"),
    ("in", Json.mkObj [("flip", .bool flip), ("mMilli", .num (JsonNumber.fromInt mm))]),
    ("out", Json.mkObj [("writes", .bool (writes flip ((mm : Rat) / 1000)))])]).compress

def lines (_ : Unit) : List String :=
  (writeList.flatMap fun w => [consumerLine w .base, consumerLine w .flip]) ++
    ([false, true].flatMap fun f => milli.map (writesLine f))

def text (_ : Unit) : String := String.intercalate "\n" (lines ()) ++ "\n"

def runGolden (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == text () then
      IO.eprintln s!"morph.style golden: {path} is up to date"
      return 0
    IO.eprintln s!"morph.style golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (text ())
    return 0

end Fw.Parts.MorphStyleGolden

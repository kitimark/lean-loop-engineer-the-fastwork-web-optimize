import Lean.Data.Json
import Fw.Parts.PlatformEntries
/-!
# Golden vectors for `platform.entries:fill-release`
-/
namespace Fw.Parts.PlatformEntriesFillGolden
open Lean Fw.Parts.PlatformEntries

def numJ (q : Rat) : Json :=
  if q.den = 1 then .num q.num else Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

def declsJ (ds : List (String × String)) : Json := .arr (ds.map fun (p, v) => Json.arr #[.str p, .str v]).toArray

def constLine : String :=
  (Json.mkObj [("fn", "const"), ("in", Json.mkObj []),
    ("out", Json.mkObj [("flag", "platform.entries:fill-release"), ("variant", "fill-release"), ("cls", "fillRelease"),
      ("media", .str fillMedia), ("roots", .arr (fillRoots.map Json.str).toArray), ("rows", .num fillRows.length)])]).compress

def rowLine (r : FillRow) : String :=
  (Json.mkObj [("fn", "row"),
    ("in", Json.mkObj [("faithful", .str r.faithful), ("els", .arr (r.els.map Json.str).toArray)]),
    ("out", Json.mkObj [("variant", .str r.variant), ("kf", .str r.kf), ("fill", "both"), ("durMs", numJ r.entry.dur),
      ("to", declsJ (endDecls r)), ("decls", declsJ (fillDecls r)), ("spec", .num r.spec), ("rival", .num r.rival)])]).compress

def lines (_ : Unit := ()) : List String := constLine :: fillRows.map rowLine

def goldenText (_ : Unit := ()) : String := String.join ((lines ()).map (· ++ "\n"))

#guard (lines ()).length == 16

def run' (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText () then
      IO.eprintln s!"platform-entries-fill golden: {path} is up to date ({(lines ()).length} lines)"
      return 0
    IO.eprintln s!"platform-entries-fill golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Parts.PlatformEntriesFillGolden

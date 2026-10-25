import Lean.Data.Json
import Fw.Parts.MorphMountToolbar

namespace Fw.Parts.MorphMountToolbarGolden
open Fw.Parts.MorphMountToolbar

def ratJ (q : Rat) : Lean.Json := .num ⟨q.num * ((1000 / q.den : Nat) : Int), 3⟩

def line (fn : String) (inp : List (String × Lean.Json)) (out : Lean.Json) : String :=
  (Lean.Json.mkObj [("fn", .str fn), ("in", Lean.Json.mkObj inp), ("out", out)]).compress

def bs : List Bool := [false, true]
def gs : List G := [.fresh, .native, .pushing, .spent]
def opts : List (String × Opt) := [("orig", orig), ("touch-first", firstOnly), ("open-once", onceOnly)]

def stepRows (_ : Unit) : List String :=
  opts.flatMap fun (n, o) => gs.flatMap fun g => bs.flatMap fun a => [(-1 : Rat), 1].flatMap fun d =>
    bs.flatMap fun geom => bs.map fun c =>
      let r := step o g a d geom c
      line "step" [("opt", .str n), ("g", .str g.name), ("active", .bool a), ("delta", ratJ d), ("geom", .bool geom), ("cancelable", .bool c)]
        (Lean.Json.mkObj [("take", .bool r.1), ("next", .str r.2.name)])

def runCases : List (String × List (Bool × Rat × Bool × Bool)) :=
  [("reopen-three", List.replicate 3 (false, 1, true, true)),
   ("arrives-mid-gesture", [(false, 1, false, true), (false, 1, true, true), (true, 1, true, true)]),
   ("uncancelable-first", [(false, 1, true, false), (false, 1, true, false)]),
   ("open-close-open", [(false, 1, true, true), (true, 1, true, true), (false, 1, true, true), (false, 1, true, true)])]

def runOut (o : Opt) : G → List (Bool × Rat × Bool × Bool) → List Lean.Json
  | _, [] => []
  | g, (a, d, geom, c) :: rest =>
    let r := step o g a d geom c
    Lean.Json.mkObj [("take", .bool r.1), ("next", .str r.2.name)] :: runOut o r.2 rest

def runRows (_ : Unit) : List String :=
  opts.flatMap fun (n, o) => runCases.map fun (c, steps) =>
    line "run" [("opt", .str n), ("case", .str c),
      ("steps", .arr (steps.map fun (a, d, geom, cc) =>
        Lean.Json.mkObj [("active", .bool a), ("delta", ratJ d), ("geom", .bool geom), ("cancelable", .bool cc)]).toArray)]
      (Lean.Json.mkObj [("out", .arr (runOut o .fresh steps).toArray), ("opens", .num ⟨(opens o .fresh steps : Nat), 0⟩)])

def armCases : List (Rat × Rat × Rat × Rat) :=
  [(450, 845, 800, 40), (450, 808, 800, 40), (450, 809, 800, 40), (450, 849, 800, 40), (450, 848, 800, 40),
   (359, 800, 800, 40), (360, 800, 800, 40), (378, 800, 800, 40), (379, 800, 800, 40)]

def armRows (_ : Unit) : List String :=
  armCases.map fun (h, b, vh, t) =>
    line "armPair" [("height", ratJ h), ("bottom", ratJ b), ("vh", ratJ vh), ("toolbar", ratJ t)]
      (Lean.Json.mkObj [("small", .bool (Fw.Parts.MorphMount.armed ⟨h, b⟩ vh)), ("large", .bool (Fw.Parts.MorphMount.armed ⟨h, b⟩ (vh + t)))])

def lockRows (_ : Unit) : List String :=
  (bs.flatMap fun n => bs.flatMap fun g => bs.map fun a =>
    line "lockWanted" [("near", .bool n), ("geom", .bool g), ("active", .bool a)] (.bool (lockWanted n g a)))
  ++ (bs.flatMap fun c => bs.map fun w => line "lockOp" [("cur", .bool c), ("want", .bool w)] (.str (lockOp c w).name))

def lines (_ : Unit) : List String := stepRows () ++ runRows () ++ armRows () ++ lockRows ()

def text (_ : Unit) : String := String.intercalate "\n" (lines ()) ++ "\n"

#guard (lines ()).length == 192 + 12 + 9 + 12

#guard text () == include_str "../../../packages/contracts/golden/parts/morph-mount-toolbar.jsonl"

def runGolden (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == text () then
      IO.eprintln s!"morph.mount toolbar golden: {path} is up to date"
      return 0
    IO.eprintln s!"morph.mount toolbar golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (text ())
    return 0

end Fw.Parts.MorphMountToolbarGolden

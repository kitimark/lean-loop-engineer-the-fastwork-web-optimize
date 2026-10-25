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

def boolsJ (l : List Bool) : Lean.Json := .arr (l.map Lean.Json.bool).toArray

def ratsJ (l : List Rat) : Lean.Json := .arr (l.map ratJ).toArray

def natJ (n : Nat) : Lean.Json := .num ⟨(n : Int), 0⟩

def allGeoms : Nat → List (List Bool)
  | 0 => [[]]
  | n + 1 => (allGeoms n).flatMap fun l => [false :: l, true :: l]

def gatePhases : List (String × List Rat) := [("down", downInsets), ("up", upInsets)]

def gateVhs : List Rat := [400, 667, 844]

def gateLatencies : List Rat := [0, 16, 33, 49, 50, 99, 100]

def gateRows (_ : Unit) : List String :=
  [line "gateWalk" []
    (Lean.Json.mkObj [("heightNum", natJ 3), ("heightDen", natJ 5), ("gap", natJ 15), ("down", ratsJ downInsets), ("up", ratsJ upInsets),
      ("liftedBelowMs", ratJ liftedBelowMs)])]
  ++ Flag.arms.map (fun f => line "gateExempt" [("flag", .str f.id)] (.bool f.exempt))
  ++ (gateVhs.flatMap fun vh0 => downInsets.map fun t =>
      line "gateGeom" [("vh0", ratJ vh0), ("inset", ratJ t)] (.bool (gateGeom vh0 t)))
  ++ (gatePhases.map fun (ph, ts) => line "gateExpect" [("phase", .str ph)]
      (Lean.Json.mkObj [("insets", ratsJ ts), ("geoms", boolsJ (gateGeoms 844 ts))]))
  ++ (Flag.arms.flatMap fun f => gatePhases.flatMap fun (ph, ts) => (allGeoms ts.length).map fun gs =>
      line "gateRun" [("flag", .str f.id), ("phase", .str ph), ("geoms", boolsJ gs)] (boolsJ (gateRun f gs)))
  ++ gateLatencies.map (fun l => line "gateLifted" [("medianMs", ratJ l)] (.bool (liftedBy l)))

def lines (_ : Unit) : List String := stepRows () ++ runRows () ++ armRows () ++ lockRows ()

def text (_ : Unit) : String := String.intercalate "\n" (lines ()) ++ "\n"

def gateText (_ : Unit) : String := String.intercalate "\n" (gateRows ()) ++ "\n"

#guard (lines ()).length == 192 + 12 + 9 + 12

#guard (gateRows ()).length == 1 + 5 + 15 + 2 + 5 * (32 + 16) + 7

#guard text () == include_str "../../../packages/contracts/golden/parts/morph-mount-toolbar.jsonl"

#guard gateText () == include_str "../../../packages/contracts/golden/parts/morph-mount-toolbar.gate.jsonl"

def runGolden (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == text () then
      IO.eprintln s!"morph.mount toolbar golden: {path} is up to date"
      return 0
    IO.eprintln s!"morph.mount toolbar golden: {path} differs from the generated text"
    return 1
  | ["--gate", "--check", path] =>
    if (← IO.FS.readFile path) == gateText () then
      IO.eprintln s!"morph.mount toolbar gate golden: {path} is up to date"
      return 0
    IO.eprintln s!"morph.mount toolbar gate golden: {path} differs from the generated text"
    return 1
  | ["--gate"] =>
    IO.print (gateText ())
    return 0
  | _ =>
    IO.print (text ())
    return 0

end Fw.Parts.MorphMountToolbarGolden

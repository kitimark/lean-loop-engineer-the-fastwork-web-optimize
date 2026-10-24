import Lean.Data.Json
import Fw.Parts.MorphMountArmLate

/-! Golden rows of `morph.mount:arm-late` for `armLate.test.ts`; `Unit` arguments keep the module free of start-up allocation. -/
namespace Fw.Parts.MorphMountArmLateGolden
open Fw.Parts.MorphMountArmLate

def ratJ (q : Rat) : Lean.Json := .num ⟨q.num * ((1000 / q.den : Nat) : Int), 3⟩

def line (fn : String) (inp : List (String × Lean.Json)) (out : Lean.Json) : String :=
  (Lean.Json.mkObj [("fn", .str fn), ("in", Lean.Json.mkObj inp), ("out", out)]).compress

def bs : List Bool := [false, true]

def opJ : Op → String
  | .addStart => "+touchstart"
  | .rmStart => "-touchstart"
  | .add .wheel p => s!"+wheel:{if p then "passive" else "blocking"}"
  | .add .touchmove p => s!"+touchmove:{if p then "passive" else "blocking"}"
  | .rm .wheel => "-wheel"
  | .rm .touchmove => "-touchmove"

def modes : List Mode := [.none, .passive, .blocking]

def bottoms (vh : Rat) : List Rat :=
  [-500, 0, vh, vh + 8, vh + 9, edge vh - 1, edge vh, edge vh + 1 / 2, edge vh + 1, 4 * vh]

def edgeRows (_ : Unit) : List String :=
  [(0 : Rat), 1, 320, 568, 800, 1080].map fun vh => line "edge" [("vh", ratJ vh)] (ratJ (edge vh))

def bandRows (_ : Unit) : List String :=
  [(568 : Rat), 800].flatMap fun vh => (bottoms vh).map fun b =>
    line "inBand" [("vh", ratJ vh), ("bottom", ratJ b)] (.bool (inBand vh b))

def boolRows (_ : Unit) : List String :=
  bs.flatMap fun n => bs.flatMap fun a =>
    [line "attached" [("near", .bool n), ("active", .bool a)] (.bool (attached n a))] ++
    bs.flatMap fun band =>
      [line "blocking" [("near", .bool n), ("band", .bool band), ("active", .bool a)] (.bool (blocking n band a)),
       line "mode" [("near", .bool n), ("band", .bool band), ("active", .bool a)] (.str (mode n band a).name)]

def opsRows (_ : Unit) : List String :=
  modes.flatMap fun c => modes.map fun n =>
    line "ops" [("cur", .str c.name), ("next", .str n.name)] (.arr ((ops c n).map fun o => .str (opJ o)).toArray)

def runCases : List (String × Rat × List (Bool × Rat × Bool)) :=
  [("approach", 800, [(false, 4000, false), (true, 3000, false), (true, 1900, false), (true, 1800, false), (true, 900, false)]),
   ("leave", 800, [(true, 700, false), (true, 1700, false), (true, 1900, false), (false, 4000, false)]),
   ("active-holds", 800, [(true, 700, false), (true, 2500, true), (true, 2500, false), (false, 2500, false)]),
   ("past", 568, [(true, -100, false), (true, -1100, false), (false, -1200, false)])]

def runOut (vh : Rat) : Mode → List (Bool × Rat × Bool) → List Lean.Json
  | _, [] => []
  | cur, (n, b, a) :: rest =>
    let m := mode n (inBand vh b) a
    Lean.Json.mkObj [("mode", .str m.name), ("ops", .arr ((ops cur m).map fun o => .str (opJ o)).toArray)] :: runOut vh m rest

def runRows (_ : Unit) : List String :=
  runCases.map fun (c, vh, steps) =>
    line "run" [("case", .str c), ("vh", ratJ vh),
      ("steps", .arr (steps.map fun (n, b, a) =>
        Lean.Json.mkObj [("near", .bool n), ("bottom", ratJ b), ("active", .bool a)]).toArray)]
      (.arr (runOut vh .none steps).toArray)

def lines (_ : Unit) : List String :=
  edgeRows () ++ bandRows () ++ boolRows () ++ opsRows () ++ runRows ()

def text (_ : Unit) : String := String.intercalate "\n" (lines ()) ++ "\n"

#guard (lines ()).length == 6 + 20 + 4 * 5 + 9 + 4

#guard text () == include_str "../../../packages/contracts/golden/parts/morph-mount-arm-late.jsonl"

def runGolden (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == text () then
      IO.eprintln s!"morph.mount arm-late golden: {path} is up to date"
      return 0
    IO.eprintln s!"morph.mount arm-late golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (text ())
    return 0

end Fw.Parts.MorphMountArmLateGolden

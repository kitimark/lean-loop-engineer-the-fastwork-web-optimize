import Lean.Data.Json
import Fw.Parts.PlatformSweepLayer
/-!
# Golden vectors for `platform.sweep:layer-sweep`
-/
namespace Fw.Parts.PlatformSweepLayerGolden
open Lean Fw.Parts.PlatformSweepLayer
open Fw.Parts.PlatformSweep (pos color bandU imageU period)

def ratWire (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

def numJ (q : Rat) : Json := if q.den = 1 then .num q.num else ratWire q

def rgbJ (c : Rat × Rat × Rat) : Json := .arr #[numJ c.1, numJ c.2.1, numJ c.2.2]

def ws : List Rat := [100, 230]
def ts : List Rat := [0, 1000, 2000, 3999, 4000, 6500]
def vs : List Rat := [0, 1 / 4, 1 / 2, 1]

def constLine : String :=
  (Json.mkObj [("fn", "const"), ("in", Json.mkObj []),
    ("out", Json.mkObj [("periodMs", numJ period), ("flag", "platform.sweep:layer-sweep"), ("variant", "layer-sweep"),
      ("fromPct", numJ fromPct), ("budgetBytes", .num budgetBytes), ("layers", .num pageLayers)])]).compress

def xLine (w t : Rat) : String :=
  (Json.mkObj [("fn", "layerX"), ("in", Json.mkObj [("w", numJ w), ("t", numJ t)]),
    ("out", Json.mkObj [("x", numJ (layerX w t)), ("bg", numJ (-2 * w * pos t)), ("css", numJ (layerXCss w t))])]).compress

def shownLine (w v t : Rat) : String :=
  (Json.mkObj [("fn", "shown"), ("in", Json.mkObj [("w", numJ w), ("v", numJ v), ("t", numJ t)]),
    ("out", Json.mkObj [("layer", rgbJ (color (bandU w (layerX w t) v))), ("orig", rgbJ (color (imageU v (pos t))))])]).compress

def xvs : List Rat := [0, 1 / 4, 1 / 2, 1, 2, 7 / 2]

def tiledLine (w v t : Rat) : String :=
  (Json.mkObj [("fn", "tiled"), ("in", Json.mkObj [("w", numJ w), ("v", numJ v), ("t", numJ t)]),
    ("out", Json.mkObj [("layer", rgbJ (color (layerU w (v * w - layerX w t)))), ("orig", rgbJ (color (repU w (v * w) (pos t))))])]).compress

def dprs : List Rat := [1, 2, 3]
def lefts : List Rat := [0, 102 / 5, 201 / 2, 149 / 4]
def widths : List Rat := [52681 / 100, 90, 2303 / 10, 3 / 5]

def snapLine (dpr left width : Rat) : String :=
  (Json.mkObj [("fn", "snap"), ("in", Json.mkObj [("dpr", numJ dpr), ("left", numJ left), ("width", numJ width)]),
    ("out", Json.mkObj [("px", .num (snapPx dpr left width)), ("w", numJ (snapW dpr left width))])]).compress

def workLine (n : Nat) : String :=
  (Json.mkObj [("fn", "work"), ("in", Json.mkObj [("words", .num n)]),
    ("out", Json.mkObj [("orig", .num (textRepaints (page origWord n))), ("layer", .num (textRepaints (page layerWord n)))])]).compress

def lines (_ : Unit := ()) : List String :=
  constLine :: (ws.flatMap fun w => ts.map (xLine w)) ++
    (ws.flatMap fun w => ts.flatMap fun t => vs.map fun v => shownLine w v t) ++ [workLine 1, workLine 4] ++
    (ws.flatMap fun w => ts.flatMap fun t => xvs.map fun v => tiledLine w v t) ++
    (dprs.flatMap fun d => lefts.flatMap fun l => widths.map fun w => snapLine d l w)

def goldenText (_ : Unit := ()) : String := String.join ((lines ()).map (· ++ "\n"))

#guard ws.all fun w => ts.all fun t => vs.all fun v => color (bandU w (layerX w t) v) == color (imageU v (pos t))
#guard ws.all fun w => ts.all fun t => xvs.all fun v => color (layerU w (v * w - layerX w t)) == color (repU w (v * w) (pos t))
#guard (lines ()).length == 1 + 12 + 48 + 2 + 72 + 48

def run' (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText () then
      IO.eprintln s!"platform-sweep-layer golden: {path} is up to date ({(lines ()).length} lines)"
      return 0
    IO.eprintln s!"platform-sweep-layer golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Parts.PlatformSweepLayerGolden

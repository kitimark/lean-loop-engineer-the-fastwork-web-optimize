import Lean.Data.Json
import Fw.Parts.FlipAccel
import Fw.Parts.MorphGeomGen
namespace Fw.Parts.FlipAccel
open Lean Fw.Parts.MorphGeom Fw.Parts.MorphTrackAccel Fw.Engine.TransitionStart

def allProps : List AnimProp := [.translate, .scale, .transformList, .opacity, .blur, .backdropBlur]

def propLines (_ : Unit) : List String :=
  allProps.map fun p =>
    gline "prop" [("prop", .str p.css)] (Json.mkObj [("accelerated", .bool (wkAlways p.css)), ("forces", .bool (forcesRecalc p))])

def cssLines (_ : Unit) : List String :=
  ["opacity", "transform", "translate", "scale", "rotate", "filter", "backdrop-filter", "offset-path", "max-width", "padding-inline", "width", "left"].map fun c =>
    gline "css" [("css", .str c)] (.bool (wkAlways c))

def trackLines (_ : Unit) : List String :=
  bandVps.map fun v =>
    let as := anims v (Ctx.sample v .webkit)
    gline "tracks" [("w", .num ⟨v.w.num, 0⟩), ("h", .num ⟨v.h.num, 0⟩)]
      (Json.mkObj [("n", .num ⟨as.length, 0⟩),
        ("forcing", .num ⟨(as.filter fun a => forcesRecalc a.prop).length, 0⟩),
        ("eligible", .num ⟨(as.filter (staticEligible v)).length, 0⟩),
        ("variant", .num ⟨(accelOnly as).length, 0⟩)])

def goldenText (_ : Unit) : String := String.join ((propLines () ++ cssLines () ++ trackLines ()).map (· ++ "\n"))

def gen (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText () then
      IO.eprintln s!"flip-accel golden: {path} is up to date"
      return 0
    IO.eprintln s!"flip-accel golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Parts.FlipAccel

import Lean.Data.Json
import Fw.Parts.MorphStage
import Fw.Parts.MorphEndGolden
namespace Fw.Parts.MorphStageGolden
open Lean Fw.Parts.MorphTween Fw.Parts.MorphTweenOpt Fw.Parts.MorphStage
open Fw.Parts.MorphEndGolden (numJ)

def wins : List Win :=
  [⟨390, 844, true⟩, ⟨640, 800, true⟩, ⟨641, 800, false⟩, ⟨844, 390, false⟩, ⟨1024, 768, false⟩, ⟨1280, 800, false⟩,
    ⟨1500, 300, false⟩, ⟨1920, 1080, false⟩, ⟨600, 120, true⟩]

#guard wins.all fun w => w.narrow == narrowOf w.vw

def trackLine (w : Win) : String :=
  (Json.mkObj [("fn", "morph.stage.track"),
    ("in", Json.mkObj [("vw", numJ w.vw), ("vh", numJ w.vh), ("narrow", .bool w.narrow)]),
    ("out", Json.mkObj [("spanH", numJ (spanH w)), ("spanW", numJ (spanW w)), ("blur", numJ blurSpan), ("t", numJ (trackT w))])]).compress

def progressCases : List (Rat × Rat × Rat) :=
  [(4000, 5000, 600), (4400, 5000, 600), (4400 + 1/2, 5000, 600), (4401, 5000, 600), (4600, 5000, 600),
    (4400 + 600 * (209/400), 5000, 600), (4400 + 600 * (209/400) + 1, 5000, 600), (4400 + 600 * (11/20), 5000, 600),
    (4880, 5000, 600), (4999, 5000, 600), (5000, 5000, 600), (5200, 5000, 600), (0, 0, 756), (3000, 3756, 756)]

def keyJ (k : List Bool) : Json := .arr (k.map Json.bool).toArray

def progressLine (c : Rat × Rat × Rat) : String :=
  let (y, mx, t) := c
  let p := progress y mx t
  (Json.mkObj [("fn", "morph.stage.progress"),
    ("in", Json.mkObj [("y", numJ y), ("maxY", numJ mx), ("t", numJ t)]),
    ("out", Json.mkObj [("p", numJ p), ("morph", numJ (morphKf p)), ("fade", numJ (fadeKf p)), ("key", keyJ (pxKey y mx t)),
      ("pointerNone", .bool (pointerNone p)), ("active", .bool (active p p))])]).compress

def sweepKeys (mx t : Rat) (ys : List Rat) : List (Rat × List Bool) :=
  (ys.foldl (fun (acc : List Bool × List (Rat × List Bool)) y =>
    let k := pxKey y mx t
    if k == acc.1 then acc else (k, acc.2 ++ [(y, k)])) (pxKey (ys.head!) mx t, [])).2

def ysUp (mx t : Rat) : List Rat := (List.range (t.num.toNat + 2)).map fun (i : Nat) => mx - t - 1 + (i : Rat)
def ysDown (mx t : Rat) : List Rat := (ysUp mx t).reverse

def sweepLine (name : String) (mx t : Rat) (up : Bool) : String :=
  let ys := if up then ysUp mx t else ysDown mx t
  let w := sweepKeys mx t ys
  (Json.mkObj [("fn", "morph.stage.sweep"),
    ("in", Json.mkObj [("case", .str name), ("maxY", numJ mx), ("t", numJ t), ("up", .bool up)]),
    ("out", Json.mkObj [("writes", .arr (w.map fun (y, k) => Json.mkObj [("y", numJ y), ("key", keyJ k)]).toArray),
      ("count", .num w.length)])]).compress

#guard (sweepKeys 5000 600 (ysUp 5000 600)).length == 8
#guard (sweepKeys 5000 600 (ysDown 5000 600)).length == 8

def sceneCases : List (Rat × Rat × Rat × Rat) :=
  [(5000, 600, 800, 4000), (5000, 600, 800, 4200), (5000, 600, 800, 4201), (5000, 600, 800, 4500), (5000, 600, 800, 4800), (5000, 600, 800, 4801)]

def sceneLine (c : Rat × Rat × Rat × Rat) : String :=
  let (pb, t, vh, y) := c
  (Json.mkObj [("fn", "morph.stage.scene"),
    ("in", Json.mkObj [("platformBottom", numJ pb), ("t", numJ t), ("vh", numJ vh), ("y", numJ y)]),
    ("out", Json.mkObj [("maxY", numJ (maxY pb t vh)), ("rangeStart", numJ (maxY pb t vh - t)), ("sceneBottom", numJ (sceneBottom pb t vh y))])]).compress

def kfJ (kf : List (Rat × Rat)) : Json := .arr (kf.map fun (o, v) => Json.mkObj [("offset", numJ o), ("value", numJ v)]).toArray

def readerJ (r : AttrReader) : Json :=
  Json.mkObj [("sel", .str r.sel), ("cmp", .str (match r.cmp with | .gt => "gt" | .lt => "lt")), ("theta", numJ r.θ)]

def opJ : Op → Json
  | .observe k => Json.mkObj [("op", "observe"), ("kind", .str k)]
  | .listen t p => Json.mkObj [("op", "listen"), ("type", .str t), ("passive", .bool p)]
  | .setAttr e a => Json.mkObj [("op", "setAttr"), ("el", .str e), ("attr", .str a)]
  | .setStyle e p => Json.mkObj [("op", "setStyle"), ("el", .str e), ("prop", .str p)]
  | .scrollTo => Json.mkObj [("op", "scrollTo")]

def constLine : String :=
  (Json.mkObj [("fn", "morph.stage.const"), ("in", Json.mkObj []),
    ("out", Json.mkObj [("id", .str flagId), ("attr", .str attr), ("on", .str onV), ("off", .str faithfulV),
      ("rangeCss", .str rangeCss), ("trackCss", .str (trackCss false)), ("trackCssNarrow", .str (trackCss true)),
      ("narrowMaxWidth", numJ 640), ("fadeEnd", numJ fadeEnd),
      ("morphKf", kfJ [(0, morphKf 0), (1, morphKf 1)]),
      ("fadeKf", kfJ [(0, fadeKf 0), (fadeEnd, fadeKf fadeEnd), (1, fadeKf 1)]),
      ("pointerTheta", numJ (209 / 400)), ("readers", .arr (attrReaders.map readerJ).toArray),
      ("ops", .arr (ops.map opJ).toArray),
      ("jackOn", Json.mkObj [(faithfulV, .bool (jackOn faithfulV)), (onV, .bool (jackOn onV))])])]).compress

def lines (_ : Unit) : List String :=
  [constLine] ++ wins.map trackLine ++ progressCases.map progressLine ++
    [sweepLine "up" 5000 600 true, sweepLine "down" 5000 600 false, sweepLine "up-narrow" 4210 768 true] ++ sceneCases.map sceneLine

def text (_ : Unit) : String := String.intercalate "\n" (lines ()) ++ "\n"

def runGolden (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == text () then
      IO.eprintln s!"morph.stage golden: {path} is up to date"
      return 0
    IO.eprintln s!"morph.stage golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (text ())
    return 0

end Fw.Parts.MorphStageGolden

import Lean.Data.Json
import Fw.Parts.MorphGeomAnim
import Fw.Parts.MorphGeomLook
/-! `morph.geom:on` generators: knot tables, track samples for the TS track builder, the `.is-flip` rule and the goal
CSS, written to `packages/contracts/golden/morph-geom.jsonl`. -/
namespace Fw.Parts.MorphGeom
open Lean Fw.Parts.Nav Fw.Engine.TransitionStart
open Fw.Parts.NavEarnOpt (frameMs frames)

def roundTo (d : Nat) (q : Rat) : Int := (q * (10 ^ d : Nat) + 1 / 2).floor

def jdec (d : Nat) (q : Rat) : Json := .num ⟨roundTo d q, d⟩

def cssNum (q : Rat) : String :=
  let z := roundTo 4 q
  let a := z.natAbs
  let frac := ((toString (10000 + a % 10000)).toList.drop 1).reverse.dropWhile (· = '0') |>.reverse
  (if z < 0 then "-" else "") ++ toString (a / 10000) ++ (if frac.isEmpty then "" else "." ++ String.ofList frac)

def jl (xs : List Json) : Json := .arr xs.toArray

def gline (fn : String) (inp : List (String × Json)) (out : Json) : String :=
  (Json.mkObj [("fn", .str fn), ("in", Json.mkObj inp), ("out", out)]).compress

def Ks.name : Ks → String
  | .grid => "grid" | .unit => "unit" | .earn => "earn" | .panel => "panel" | .fade => "fade" | .time => "time" | .kink _ => "kink"

def engTag : Eng → String
  | .webkit => "webkit" | .chromium => "chromium"

def samples : List Rat := [0, 1 / 100, 1 / 20, 2 / 25, 3 / 20, 1 / 5, 8 / 25, 1 / 2, 11 / 20, 4 / 5, 1]

def Ks.at (k : Ks) (m : Rat) : Rat := if k = .time then m * timeEnd else m

def engDep (a : Anim) : Bool := ["lang", "earn", "earnClip", "earnLabel"].contains a.el

def selector (a : Anim) : String :=
  let base := s!"[data-mg=\"{a.el}\"]"
  match a.el with
  | "column" | "Kc" | "Uc" => base ++ s!"[data-i=\"{a.key.1}\"]"
  | "image" => base ++ s!"[data-i=\"{a.key.1}\"][data-j=\"{a.key.2}\"]"
  | _ => base

def decl (p : AnimProp) (xs : List Rat) : String :=
  let n := fun i => cssNum (xs.getD i 0)
  match p with
  | .translate => s!"translate: {n 0}px {n 1}px"
  | .scale => s!"scale: {n 0} {n 1}"
  | .transformList => s!"transform: translate({n 0}px, {n 1}px) scale({n 2}, {n 3})"
  | .opacity => s!"opacity: {n 0}"
  | .blur => s!"filter: blur({n 0}px)"
  | .backdropBlur => s!"backdrop-filter: blur({n 0}px)"

def flipCss : String :=
  ", ".intercalate (flipEls.map fun e => s!".is-flip [data-mg=\"{e}\"]") ++ " { transition: none; }"

def goalCss (v : Vp) (c : Ctx) : List String :=
  (anims v c).map fun a => s!"{selector a} \{ {decl a.prop (a.fns.map fun f => f a.ks.last)}; }"

def vpIn (v : Vp) : List (String × Json) := [("w", jdec 0 v.w), ("h", jdec 0 v.h)]

def knotLines (_ : Unit) : List String :=
  bandVps.map fun v => gline "knots" (vpIn v)
    (Json.mkObj ([Ks.grid, .earn, .panel, .fade].map fun k => (k.name, jl ((k.list v).map (jdec 9)))))

def timeLine (_ : Unit) : String :=
  gline "time" [] (Json.mkObj [("frameMs", jdec 9 frameMs), ("frames", .num ⟨frames, 0⟩), ("end", jdec 9 timeEnd)])

def sampleLines (_ : Unit) : List String :=
  bandVps.flatMap fun v => [Eng.webkit, .chromium].flatMap fun e =>
    ((anims v (Ctx.sample v e)).filter fun a => e = .webkit || engDep a).map fun a =>
      gline "sample" (vpIn v ++ [("eng", .str (engTag e)), ("el", .str a.el), ("i", .num ⟨a.key.1, 0⟩),
        ("j", .num ⟨a.key.2, 0⟩), ("prop", .str a.prop.css), ("ks", .str a.ks.name)])
        (jl ((a.tracks v).map fun t => jl (samples.map fun m => jdec 6 (t.eval (a.ks.at m)))))

def cssLines (_ : Unit) : List String :=
  gline "flip" [] (.str flipCss) ::
  bandVps.flatMap fun v => [Eng.webkit, .chromium].map fun e =>
    gline "goal" (vpIn v ++ [("eng", .str (engTag e))]) (jl ((goalCss v (Ctx.sample v e)).map Json.str))

def layoutCss : List String :=
  [s!"[data-mg=\"Kb\"], [data-mg=\"Ub\"] \{ display: flex; gap: {match flipRowGap with | .inherit => "inherit" | .px n => cssNum n}; }",
   s!"[data-mg=\"Kc\"] \{ overflow: hidden; padding-block: {cssNum clipPad}px; margin-block: -{cssNum clipPad}px; }",
   "[data-mg=\"pic\"] { position: relative; flex: none; overflow: hidden; border-radius: 12px; }",
   ".is-flip [data-mg=\"image\"] { position: absolute; left: var(--pic-l); top: var(--pic-t); width: var(--pic-w); height: var(--pic-h) !important; max-width: none; object-fit: fill; border-radius: 0; transform-origin: 50% 50%; }",
   ".is-flip [data-mg=\"earn\"] { transform: none !important; }",
   ".is-flip [data-mg=\"actions\"] { top: 0; bottom: 0; translate: none; }"]

def flipTolPx : Rat := 1

def flipMs : List Rat := [0, 1 / 4, 1 / 2, 1]

def flipCellLines (_ : Unit) : List String :=
  gline "layout" [] (jl (layoutCss.map Json.str)) ::
  gline "leave" [] (jl (leaveNew.map fun o => Json.str o.name)) ::
  gline "move" [] (jl (moveNew.map fun o => Json.str o.name)) ::
  gline "flipCell" [] (Json.mkObj [("tolPx", jdec 4 flipTolPx), ("ms", jl (flipMs.map (jdec 4))),
    ("els", jl (["image", "nav", "lang", "earn", "actions"].map Json.str))]) ::
  bandVps.map fun v => gline "flipBand" (vpIn v)
    (Json.mkObj [("cols", .num ⟨(nCols v).floor, 0⟩), ("gap", jdec 0 (flipGap v)), ("btnH", jdec 0 (btnH v))])

def rcJson (r : Rc) : Json := jl [jdec 6 r.l, jdec 6 r.t, jdec 6 r.r, jdec 6 r.b]

/-- Pictures of a golden band: tall (width-limited), wide (height-limited), and one whose fit ratios cross at the middle of
the morph (integer intrinsic sizes, so the golden inputs are exact). -/
def bandPics (v : Vp) : List Pic :=
  [⟨0, 200, 300, 1000⟩, ⟨0, 200, 2000, 1000⟩, ⟨0, 200, ((cw v 0 + cw v 1) * 5 / 2).floor, 1000⟩]

/-- Per band and picture: the base's rectangle and crop at each sample `m`, and the rectangle at rest. -/
def picLines (_ : Unit) : List String :=
  bandVps.flatMap fun v => (bandPics v).map fun p =>
    gline "pic" (vpIn v ++ [("iw", jdec 0 p.iw), ("ih", jdec 0 p.ih), ("boxH", jdec 0 p.h)])
      (Json.mkObj [("lay", rcJson (layRect v p)), ("q", jdec 6 (qImg v p)),
        ("pic", jl (samples.map fun m => rcJson (basePic v p m))),
        ("crop", jl (samples.map fun m => rcJson (baseCrop v p m)))])

def goldenLines (_ : Unit) : List String :=
  knotLines () ++ [timeLine ()] ++ sampleLines () ++ cssLines () ++ flipCellLines () ++ picLines ()

def goldenText (_ : Unit) : String := String.join ((goldenLines ()).map (· ++ "\n"))

def gen (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText () then
      IO.eprintln s!"morph-geom golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"morph-geom golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

#guard roundTo 2 (1 / 3) == 33 && roundTo 0 (-1 / 2) == 0 && roundTo 0 (1 / 2) == 1
#guard cssNum (-5 / 4) == "-1.25" && cssNum 3 == "3" && cssNum (1 / 3) == "0.3333"
#guard decl .transformList [1, -2, 1 / 2, 1] == "transform: translate(1px, -2px) scale(0.5, 1)"
#guard selector (anim "image" .scale .unit [] (2, 1)) == "[data-mg=\"image\"][data-i=\"2\"][data-j=\"1\"]"
#guard engDep (anim "earnLabel" .opacity .unit []) && !engDep (anim "K0" .opacity .unit [])

end Fw.Parts.MorphGeom

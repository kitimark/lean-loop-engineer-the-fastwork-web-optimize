import Lean.Data.Json
import Fw.Parts.MorphGeomAnim
import Fw.Parts.MorphGeomLook
import Fw.Parts.MorphGeomLookRule
namespace Fw.Parts.MorphGeom
open Lean Fw.Parts.Nav Fw.Engine.TransitionStart
open Fw.Parts.NavEarnOpt (frameMs frames)
open Fw.Parts.MorphTween (pointerNone)

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
  | .grid => "grid" | .unit => "unit" | .earn => "earn" | .panel => "panel" | .fade => "fade" | .time => "time"

def engTag : Eng → String
  | .webkit => "webkit" | .chromium => "chromium"

def samples : List Rat := [0, 1 / 100, 1 / 20, 2 / 25, 3 / 20, 1 / 5, 8 / 25, 1 / 2, 11 / 20, 4 / 5, 1]

def Ks.at (k : Ks) (m : Rat) : Rat := if k = .time then m * timeEnd else m

def engDep (a : Anim) : Bool := ["lang", "earn", "earnClip", "earnLabel"].contains a.el

def selector (a : Anim) : String :=
  let base := s!"[data-mg=\"{a.el}\"]"
  match a.el with
  | "column" => base ++ s!"[data-i=\"{a.key.1}\"]"
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

def lookMs : List Rat := [0, 1 / 4, 1 / 2, 3 / 4, 1]

def jn (n : Nat) : Json := .num ⟨n, 0⟩

def lookPixels : List ((Nat × Nat × Nat) × (Nat × Nat × Nat)) :=
  [((10, 20, 30), (10, 20, 30)), ((0, 0, 0), (12, 0, 0)), ((0, 0, 0), (13, 0, 0)), ((0, 0, 0), (0, 13, 0)),
   ((0, 0, 0), (0, 0, 13)), ((255, 255, 255), (243, 255, 255)), ((255, 255, 255), (242, 255, 255)),
   ((19, 19, 19), (7, 7, 7)), ((19, 19, 19), (6, 7, 7))]

def lookRanges : List (Nat × Rat × Rat) :=
  [(100, 21 / 2, 20), (100, -5, 10), (100, 95, 20), (100, 3, 0), (100, 120, 5), (100, 9 / 4, 1 / 2), (100, 0, 100)]

def lookShares : List (Nat × Nat) := [(0, 0), (3, 12), (12, 12), (1, 8)]

def lookTracks : List (Rat × Rat × Rat) :=
  [(1000, 250, 1 / 4), (1000, 251, 1 / 4), (1000, 253, 1 / 4), (1000, 500, 1 / 4), (1500, 340, 7 / 8), (1500, 340, 1 / 2),
   (1500, 680, 1), (1500, 0, 0), (1500, 1360, 1), (1000, 1000, 1), (600, 250, 1 / 4), (680, 340, 7 / 8)]

def lookCounts : List (Rat × Nat) := [(0, 0), (0, 3), (1 / 4, 0), (1 / 4, 12)]

def lookScrolls : List (Rat × Rat) := [(7794, 7794), (7794, 7794 + 1 / 200), (7794, 7794 + 1 / 50), (6074, 7794)]

def lookShows : List (Rat × Rat) := [(1, 0), (0, 0), (0, 11 / 20), (11 / 20, 1 / 4), (14 / 25, 1 / 4), (1, 1 / 2)]

def lookFadeMs : List Rat := lookMs ++ [1 / 10, 3 / 10, 11 / 20]

def jdz (d : Nat) (q : Rat) : Json := if q = 0 then jn 0 else jdec d q

def pxJ (p : Nat × Nat × Nat) : Json := jl [jn p.1, jn p.2.1, jn p.2.2]

def lookRuleLines (_ : Unit) : List String :=
  gline "lookCell" [] (Json.mkObj [("over", jn overStep), ("gridMs", jdz 4 gridMs), ("timeEnd", jdz 4 timeEnd),
    ("tweenMs", jdz 4 Fw.Parts.MorphTween.duration), ("fadeEnd", jdz 4 Fw.Parts.MorphTween.fadeEnd),
    ("mTol", jdz 6 mTol), ("scrollTol", jdz 6 scrollTol), ("fadeTol", jdz 6 fadeTol), ("ms", jl (lookMs.map (jdz 4)))]) ::
  lookPixels.map (fun (a, b) => gline "lookPixel" [("a", pxJ a), ("b", pxJ b)] (.bool (pixelOver a b))) ++
  lookRanges.map (fun (n, x, w) => gline "lookRange" [("size", jn n), ("x", jdz 4 x), ("w", jdz 4 w)]
    (Json.mkObj [("lo", jn (pxLo x)), ("hi", jn (pxHi n x w))])) ++
  lookShares.map (fun (o, n) => gline "lookShare" [("over", jn o), ("n", jn n)] (jdz 6 (share o n))) ++
  lookTracks.map (fun (d, t, m) => gline "lookTrack" [("dur", jdz 4 d), ("t", jdz 4 t), ("m", jdz 4 m)] (.bool (trackAt d t m))) ++
  lookCounts.map (fun (m, n) => gline "lookCount" [("m", jdz 4 m), ("n", jn n)] (.bool (tracksOk m n))) ++
  [(0, false, false, 0), (0, true, false, 0), (1, true, true, 0), (1, true, true, 2), (1, true, false, 0), (1 / 2, true, true, 0)].map
    (fun (m, f, g, n) => gline "lookSettled" [("m", jdz 4 m), ("flip", .bool f), ("goal", .bool g), ("n", jn n)] (.bool (timedSettled m f g n))) ++
  lookScrolls.map (fun (a, b) => gline "lookScroll" [("a", jdz 4 a), ("b", jdz 4 b)] (.bool (scrollEq a b))) ++
  lookShows.map (fun (o, m) => gline "lookShows" [("o", jdz 4 o), ("m", jdz 4 m)] (.bool (fadeShows o m))) ++
  lookFadeMs.map (fun m => gline "lookFade" [("m", jdz 4 m)]
    (Json.mkObj [("fade", jdz 12 (Fw.Parts.MorphTween.fade m)), ("pointerNone", .bool (pointerNone m))]))

def goldenLines (_ : Unit) : List String := knotLines () ++ [timeLine ()] ++ sampleLines () ++ cssLines () ++ flipCellLines () ++ lookRuleLines ()

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

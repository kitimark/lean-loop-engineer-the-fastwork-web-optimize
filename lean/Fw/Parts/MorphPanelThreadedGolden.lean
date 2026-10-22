import Lean.Data.Json
import Fw.Parts.MorphPanelThreadedRun

namespace Fw.Parts.MorphPanelThreaded
open Lean Fw.Parts.MorphPanel Fw.Parts.MorphTween Fw.Parts.MorphTweenOpt Fw.Parts.PlatformFade

def ratWire (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

def rin (q : Rat) : Json :=
  if (1000000 % q.den) == 0 then .num ⟨q.num * ((1000000 / q.den : Nat) : Int), 6⟩ else ratWire q

def line (fn : String) (inp : List (String × Json)) (out : Json) : String :=
  (Json.mkObj [("fn", .str fn), ("in", Json.mkObj inp), ("out", out)]).compress

def ends : List Rat := [0, 1 / 25, 2 / 25, 1 / 5, 2 / 5, 1 / 2, 3 / 4, 4 / 5, 9 / 10, 1]

def bands : List Band := [.always, .w1000, .w720, .reduced, .w640, .w600]

def goldenLines : List String :=
  [line "const" [] (Json.mkObj
      [("kA", ratWire kA), ("kB", ratWire kB), ("blurMax", ratWire 12), ("duration", ratWire duration),
       ("easing", Json.arr #[ratWire easing.1, ratWire easing.2.1, ratWire easing.2.2.1, ratWire easing.2.2.2])])] ++
  (ends.flatMap fun f => ends.map fun t =>
    line "keyframes" [("from", rin f), ("to", rin t)]
      (Json.arr ((offs f t).map fun o =>
        let m := mAt f t o
        Json.mkObj [("off", ratWire o), ("opacity", ratWire (panelOpacity m)), ("blur", ratWire (panelBlurPx m)),
          ("scale", ratWire (panelScale m))]).toArray)) ++
  (ends.flatMap fun f => ends.map fun t =>
    line "ca" [("from", rin f), ("to", rin t)]
      (Json.mkObj [("kfs", Json.num ⟨((offs f t).length : Nat), 0⟩), ("accepts", .bool (caAccepts (caOf f t)))])) ++
  bands.map (fun b =>
    line "bands" [("query", .str b.query)]
      (Json.mkObj [("opacity", .bool (decide (Anim3.opacity ∈ declared b))), ("filter", .bool (decide (Anim3.filter ∈ declared b))),
        ("transform", .bool (decide (Anim3.transform ∈ declared b)))])) ++
  [line "installed" [("reduced", .bool true)] (.bool (installed true)),
   line "installed" [("reduced", .bool false)] (.bool (installed false)),
   line "effects" [] (Json.arr (effects.map fun e =>
     Json.arr (e.map fun a => Json.str (match a with | .opacity => "opacity" | .filter => "filter" | .transform => "transform")).toArray).toArray)]

def jsonl : String := String.join (goldenLines.map (· ++ "\n"))

#guard goldenLines.length == 1 + 100 + 100 + 6 + 3

#guard jsonl == include_str "../../../packages/contracts/golden/parts/morph-panel-threaded.jsonl"

end Fw.Parts.MorphPanelThreaded

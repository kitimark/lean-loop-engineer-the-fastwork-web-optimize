import Lean.Data.Json
import Fw.Device.Feel
import Fw.Device.FeelCapture
/-!
Writes `packages/contracts/golden/device/feel.jsonl`.
-/
namespace Fw.Device.Feel
open Lean

private def armJ (group : String) (a : Arm) : Json :=
  Json.mkObj [("kind", "arm"), ("group", group), ("id", a.id), ("flags", toJson a.flags), ("text", a.text)]

private def cellCode : Cell → String
  | .better => "better" | .same => "same" | .worse => "worse"

private def optJ : Option Nat → Json
  | some n => toJson n
  | none => Json.null

private def scores : List Nat := List.range 5 |>.map (· + 1)

private def reduceGrid : List String :=
  scores.flatMap fun x1 => scores.flatMap fun x2 => scores.flatMap fun b1 => scores.map fun b2 =>
    (reduceArm [x1, x2] [b1, b2]).code

private def lookGrid : List String :=
  scores.flatMap fun x => scores.flatMap fun b1 => scores.map fun b2 => (reduceLook [x] [b1, b2]).code

private def sessionCases : List (Nat × List (Option Nat) × List (Option Nat)) :=
  [(0, [some 3, some 3, some 3, some 3, some 3, some 3], [some 3, some 3, some 3, some 3]),
   (0, [some 2, some 4, some 4, some 4, some 2, some 3], [some 5, some 1, some 3, some 3]),
   (1, [some 2, some 4, some 4, some 4, some 2, some 3], [some 5, some 1, some 3, some 3]),
   (2, [some 4, some 4, some 2, some 2, some 5, some 5], [none, some 5, some 4, some 2]),
   (4, [some 3, some 3, some 4, some 5, none, some 1], [none, none, none, none]),
   (5, [none, none, none, none, none, none], [some 3, none, none, none])]

private def sessionJ (c : Nat × List (Option Nat) × List (Option Nat)) : Json :=
  let (seed, rs, ls) := c
  Json.mkObj [("kind", "session"), ("seed", seed), ("ratings", Json.arr (rs.map optJ).toArray),
    ("look", Json.arr (ls.map optJ).toArray),
    ("same", toJson ((List.range nSame).map fun a => (sameVerdict seed rs a).code)),
    ("lookVerdicts", toJson (ls.map fun x => (lookVerdict seed rs x).code))]

private def capJ (c : Capture) : Json :=
  Json.mkObj [("moving", c.moving), ("long17", c.long17), ("long33", c.long33), ("pins", c.pins), ("fights", c.fights),
    ("reversals", c.reversals), ("retargets", c.retargets), ("blinks", c.blinks), ("zoneWork", toJson c.zoneWork)]

private def sumJ (s : Summary) : Json :=
  Json.mkObj [("visits", s.visits), ("long17", s.long17), ("long33", s.long33), ("fights", s.fights), ("blinks", s.blinks),
    ("topZone", optJ s.topZone), ("score", s.score)]

private def jointJ (j : Joint) : Json :=
  Json.mkObj [("verdict", j.verdict.code), ("summary", match j.summary with | none => Json.null | some s => sumJ s), ("flag", j.flag.code)]

private def pinJ (p : Pin) : Json := Json.arr #[toJson p.t, toJson p.from_, toJson p.to_]

private def captureCases : List (String × List Nat × List Nat × List Pin × List (Nat × Nat) × List (List Nat) × List (List Nat)) :=
  [("still", [0, 1667, 3333, 5000, 6667], [300, 300, 300, 300, 300], [], [], [[1000, 1000, 1000, 1000, 1000]], [[1, 1, 1, 0]]),
   ("smooth", [0, 1667, 3333, 5000, 6667], [0, 80, 160, 240, 320], [], [], [[1000, 990, 980, 970, 960]], [[1, 1, 1, 0], [2, 1, 1, 0]]),
   ("stalls", [0, 1667, 3333, 8333, 10000, 13500, 15167], [0, 80, 160, 240, 320, 400, 480], [], [(500, 1000)], [[1000, 1000, 1000, 1000, 1000, 1000, 1000]], [[1, 1, 1, 0]]),
   ("fight-up", [0, 1667, 3333, 5000, 6667], [1000, 1080, 1160, 1240, 1320], [⟨5000, 1240, 1000⟩], [], [], []),
   ("fight-same-way", [0, 1667, 3333, 5000, 6667], [1000, 1080, 1160, 1240, 1320], [⟨5000, 1240, 1400⟩], [], [], []),
   ("fight-down", [0, 1667, 3333, 5000, 6667], [1320, 1240, 1160, 1080, 1000], [⟨5000, 1080, 1400⟩, ⟨6000, 1080, 900⟩], [], [], []),
   ("reversals", [0, 1667, 3333, 5000, 6667, 8333], [0, 80, 40, 60, 20, 20], [], [(0, 1000), (400, 0), (1000, 0)], [], []),
   ("blinks", [0, 1667, 3333, 5000, 6667, 8333, 10000], [0, 80, 160, 240, 320, 400, 480], [], [],
     [[1000, 1000, 300, 1000, 1000, 1000, 1000], [1000, 1000, 1000, 1000, 1000, 300, 1000], [1000, 900, 800, 700, 600, 500, 400]], []),
   ("zones", [0, 1667], [0, 10], [], [], [], [[3, 2, 4, 9, 9], [0, 0, 0, 5], [10, 0, 0, 0], []])]

private def blinkCases : List (List Nat) :=
  [[], [1000], [1000, 1000, 300, 1000, 1000], [1000, 300, 300, 300, 1000], [1000, 300, 1000, 1000, 1000, 300, 1000],
   [1000, 900, 1000, 1000], [1000, 1000, 300, 300, 300], [1000, 300, 300, 300, 300, 300, 300, 300, 300, 300, 1000],
   [1000, 1000, 850, 1000, 1000], [1000, 1000, 851, 1000, 1000], [1000, 300, 300, 300, 300, 300, 300, 300, 1000],
   [0, 1000, 0, 1000, 0], List.replicate 12 700, [1000, 900, 800, 700, 600, 500, 400, 300]]

private def mkCap (l33 f b : Nat) (z : List Nat) : Capture := ⟨100, l33, l33, f, f, 0, 0, b, z⟩

private def jointCases : List (Nat × List (Option Nat) × List (Option Nat) × List (Option Capture) × List (Option Capture)) :=
  let base := some (mkCap 10 0 0 [0, 12]); let light := some (mkCap 1 0 0 [4, 0]); let heavy := some (mkCap 9 0 3 [0, 0, 7])
  [(0, [some 5, some 2, some 5, some 2, some 5, some 5], [none, none, none, none], [base, light, base, light, base, base], [none, none, none, none]),
   (0, [some 2, some 5, some 2, some 5, some 2, some 2], [none, none, none, none], [light, heavy, light, heavy, light, light], [none, none, none, none]),
   (0, [some 5, some 2, some 5, some 2, some 5, some 5], [none, none, none, none], [light, heavy, light, heavy, light, light], [none, none, none, none]),
   (0, [some 5, some 2, some 5, some 2, some 5, some 5], [none, none, none, none], [none, none, none, none, none, none], [none, none, none, none]),
   (0, [some 5, some 3, some 5, some 4, some 5, some 5], [none, none, none, none], [base, light, base, light, base, base], [none, none, none, none]),
   (1, [some 3, some 3, some 3, some 3, some 3, some 3], [some 1, some 5, none, some 3], [base, base, base, base, base, base], [heavy, light, none, base]),
   (2, [some 3, some 1, some 3, some 5, some 3, some 3], [some 5, none, none, none], [base, base, base, base, base, base], [light, none, none, none])]

private def jointLineJ (c : Nat × List (Option Nat) × List (Option Nat) × List (Option Capture) × List (Option Capture)) : Json :=
  let (seed, rs, ls, caps, lcaps) := c
  let capOpt : Option Capture → Json := fun x => match x with | none => Json.null | some c => capJ c
  Json.mkObj [("kind", "joint"), ("seed", seed), ("ratings", Json.arr (rs.map optJ).toArray), ("look", Json.arr (ls.map optJ).toArray),
    ("captures", Json.arr (caps.map capOpt).toArray), ("lookCaptures", Json.arr (lcaps.map capOpt).toArray),
    ("same", Json.arr ((List.range nSame).map fun a => jointJ (jointSame seed rs caps a)).toArray),
    ("lookJoint", Json.arr ((ls.zip lcaps).map fun p => jointJ (jointLook seed rs caps p.1 p.2)).toArray)]

private def captureLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "capconsts"), ("long17Cs", long17Cs), ("long33Cs", long33Cs), ("blinkDrop", blinkDrop), ("blinkWithin", blinkWithin),
      ("idleMs", idleMs), ("zonePx", zonePx), ("capMargin", capMargin)]).compress] ++
  (captureCases.map fun c =>
    (Json.mkObj [("kind", "capture"), ("name", c.1), ("ts", toJson c.2.1), ("ys", toJson c.2.2.1),
      ("pins", Json.arr (c.2.2.2.1.map pinJ).toArray),
      ("starts", Json.arr (c.2.2.2.2.1.map fun p => Json.arr #[toJson p.1, toJson p.2]).toArray),
      ("cards", toJson c.2.2.2.2.2.1), ("zones", toJson c.2.2.2.2.2.2),
      ("result", capJ (captureOf c.2.1 c.2.2.1 c.2.2.2.1 c.2.2.2.2.1 c.2.2.2.2.2.1 c.2.2.2.2.2.2))]).compress) ++
  (blinkCases.map fun o => (Json.mkObj [("kind", "blinks"), ("series", toJson o), ("count", blinks o)]).compress) ++
  ([("self", true, none), ("usb absent", false, some false), ("usb present", false, some true), ("no probe", false, none),
    ("self, absent", true, some false)].map fun (c : String × Bool × Option Bool) =>
    (Json.mkObj [("kind", "closeCause"), ("name", c.1), ("selfClosed", Json.bool c.2.1),
      ("usb", match c.2.2 with | none => Json.null | some b => Json.bool b), ("cause", (closeCause c.2.1 c.2.2).code)]).compress) ++
  (jointCases.map fun c => (jointLineJ c).compress)

def goldenLines (_ : Unit) : List String :=
  [ (Json.mkObj [("kind", "consts"), ("nSame", nSame), ("baseArm", baseArm), ("repeats", repeats), ("scoreMin", scoreMin),
      ("scoreMax", scoreMax), ("margin", margin), ("doText", doText), ("rateText", rateText),
      ("texts", Json.mkObj [("better", Verdict.better.text), ("same", Verdict.same.text), ("worse", Verdict.worse.text),
        ("mixed", Verdict.mixed.text), ("unrated", Verdict.unrated.text)])]).compress ] ++
  (sameArms.map fun a => (armJ "same" a).compress) ++
  (lookArms.map fun a => (armJ "look" a).compress) ++
  ((List.range 6).map fun (seed : Nat) => (Json.mkObj [("kind", "order"), ("seed", seed), ("order", toJson (order seed)),
    ("labels", toJson ((visitsOf seed).map (·.label))),
    ("letters", String.ofList ((visitsOf seed).map (fun v => letter v.label)))]).compress) ++
  [ (Json.mkObj [("kind", "cells"), ("xs", toJson scores),
      ("grid", Json.arr (scores.map fun x => toJson (scores.map fun b => cellCode (cell x b))).toArray)]).compress,
    (Json.mkObj [("kind", "reduce"), ("scores", toJson scores), ("codes", toJson reduceGrid)]).compress,
    (Json.mkObj [("kind", "reduceLook"), ("scores", toJson scores), ("codes", toJson lookGrid)]).compress ] ++
  (sessionCases.map fun c => (sessionJ c).compress) ++ captureLines ()

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"device-feel golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"device-feel golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Device.Feel

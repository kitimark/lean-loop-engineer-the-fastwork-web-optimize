import Lean.Data.Json
import Fw.Parts.MorphGeomPrewarm
import Fw.Parts.MorphGeomGen
namespace Fw.Parts.MorphGeomPrewarm
open Lean Fw.Parts.MorphGeom

def evJson : Ev → Json
  | .warm => Json.mkObj [("e", .str "warm")]
  | .cool => Json.mkObj [("e", .str "cool")]
  | .push f t a s => Json.mkObj [("e", .str "push"), ("f", jdec 3 f), ("t", jdec 3 t), ("allowed", .bool a), ("stale", .bool s)]
  | .settle m => Json.mkObj [("e", .str "settle"), ("m", jdec 3 m)]
  | .dispose => Json.mkObj [("e", .str "dispose")]

def stepsOf (step : St → Ev → St × Act) (s : St) : List Ev → List (St × Act)
  | [] => []
  | e :: es => let r := step s e; r :: stepsOf step r.1 es

def sampleTimes : List Rat := [0, 170, 340, 680]

def scenarios : List (String × List Ev) :=
  [ ("warm-push-settle-reverse", [.warm, .push 0 1 true false, .settle 1, .push 1 0 true false, .settle 0])
  , ("warm-cool", [.warm, .cool, .cool])
  , ("warm-cool-warm", [.warm, .cool, .warm, .push 0 1 true false, .settle 1])
  , ("warm-warm", [.warm, .warm, .push 0 1 true false, .settle 1])
  , ("warm-stale-push", [.warm, .push 0 1 true true, .settle 1, .push 1 0 true false, .settle 0])
  , ("warm-refused-push", [.warm, .push 0 1 false false, .settle 0])
  , ("warm-refused-then-retry", [.warm, .push 0 1 false false, .push 0 1 false false, .push 0 1 true false, .settle 1])
  , ("warm-partial-push", [.warm, .push 0 (2 / 5) true false, .push (2 / 5) 1 true false, .settle 1])
  , ("warm-reduced-settle", [.warm, .settle 1, .push 0 1 true false])
  , ("warm-dispose", [.warm, .dispose])
  , ("rewarm-after-leave", [.warm, .push 0 1 true false, .settle 1, .push 1 0 true false, .settle 0, .warm, .push 0 1 true false, .settle 1])
  , ("no-warm", [.push 0 1 true false, .settle 1, .push 1 0 true false, .settle 0, .dispose]) ]

def stepJson (r : St × Act) (ref : St × Act) : Json :=
  Json.mkObj [("sets", .num ⟨r.2.creates, 0⟩), ("enters", .num ⟨r.2.enters, 0⟩), ("leaves", .num ⟨r.2.leaves, 0⟩),
    ("held", .bool r.1.held), ("tree", .bool r.1.tree), ("refSets", .num ⟨ref.2.creates, 0⟩)]

def sameLookAll (xs : List (St × Act)) (ys : List (St × Act)) : Bool :=
  (xs.zip ys).all fun (a, b) => sampleTimes.all fun e => decide (look a.1 e = look b.1 e)

def lines (_ : Unit) : List String :=
  scenarios.map fun (name, evs) =>
    let xs := stepsOf (newStep 1) clean evs
    let ys := stepsOf (refStep 1) clean evs
    gline "lifecycle" [("name", .str name), ("events", jl (evs.map evJson))]
      (Json.mkObj [("steps", jl ((xs.zip ys).map fun (a, b) => stepJson a b)), ("sameLook", .bool (sameLookAll xs ys))])

def timingLine (_ : Unit) : String := gline "rewarm" [] (Json.mkObj [("rewarmMs", .num ⟨rewarmMs, 0⟩), ("quietWindowMs", .num ⟨verifyWindowMs, 0⟩)])

def goldenText (_ : Unit) : String := String.join ((lines () ++ [timingLine ()]).map (· ++ "\n"))

def gen (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText () then
      IO.eprintln s!"morph-geom-prewarm golden: {path} is up to date"
      return 0
    IO.eprintln s!"morph-geom-prewarm golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Parts.MorphGeomPrewarm

import Fw.Parts.MorphGeomTimed
namespace Fw.Parts.MorphGeomTimed
open Lean Fw.Parts.MorphGeom Fw.Parts.MorphTween

def idealAt (evs : List Ev) (t : Rat) : Rat := idealM (run (evs.filter fun ev => ev.e ≤ t)) t

def scenarios : List (String × List Ev) :=
  [("open", [⟨0, 1⟩]), ("close", [⟨0, 1⟩, ⟨1000, 0⟩]), ("reverse-early", [⟨0, 1⟩, ⟨100, 0⟩]),
    ("reverse-mid", [⟨0, 1⟩, ⟨300, 0⟩]), ("reverse-late", [⟨0, 1⟩, ⟨500, 0⟩]),
    ("reverse-twice", [⟨0, 1⟩, ⟨200, 0⟩, ⟨400, 1⟩])]

def times (evs : List Ev) : List Rat :=
  let last := (evs.map (·.e)).foldl max 0
  (List.range 28).map fun (k : Nat) => (k : Rat) * (last + 680) / 27

def scenarioLines (_ : Unit) : List String :=
  scenarios.map fun (n, evs) =>
    gline "scenario" [("name", .str n), ("events", jl (evs.map fun ev => Json.mkObj [("e", jdec 6 ev.e), ("g", jdec 0 ev.g)]))]
      (Json.mkObj [("t", jl ((times evs).map (jdec 6))), ("m", jl ((times evs).map fun t => jdec 6 (idealAt evs t)))])

def rebaseCases : List (Rat × Rat) := [(0, 1), (3 / 10, 1), (1 / 20, 1), (4 / 5, 0), (1, 0), (1 / 2, 0), (1 / 10, 1 / 2)]

def panelTrack : Track := mk panelO panelKnots

def rebaseLines (_ : Unit) : List String :=
  rebaseCases.map fun (m0, g) =>
    let kf := rebase panelTrack m0 g
    gline "rebase" [("m0", jdec 6 m0), ("g", jdec 6 g)]
      (Json.mkObj [("offsets", jl (kf.map fun x => jdec 9 x.1)), ("values", jl (kf.map fun x => jdec 9 x.2))])

def crossCases : List (Rat × Rat × Rat) :=
  [(0, 1, 1 / 1000), (0, 1, 1 / 5), (0, 1, 2 / 5), (0, 1, 11 / 20), (0, 1, 9 / 10), (0, 1, 23 / 25), (1, 0, 9 / 10), (1, 0, 1 / 2),
    (1, 0, 1 / 5), (3 / 10, 1, 2 / 5), (3 / 5, 0, 1 / 5), (1, 0, 1 / 1000)]

def crossLines (_ : Unit) : List String :=
  crossCases.map fun (m0, g, c) =>
    gline "cross" [("m0", jdec 6 m0), ("g", jdec 6 g), ("c", jdec 6 c)]
      (match crossMs m0 g c with | some n => .num ⟨n, 0⟩ | none => .null)

def goldenText (_ : Unit) : String := String.join ((scenarioLines () ++ rebaseLines () ++ crossLines ()).map (· ++ "\n"))

def gen (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText () then
      IO.eprintln s!"morph-geom-timed golden: {path} is up to date"
      return 0
    IO.eprintln s!"morph-geom-timed golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

#guard (crossMs 0 1 (1 / 5)).isSome
#guard idealAt [⟨0, 1⟩] 340 == 7 / 8
#guard idealAt [⟨0, 1⟩, ⟨340, 0⟩] 340 == 7 / 8
#guard (rebase panelTrack 0 1).length == 4

end Fw.Parts.MorphGeomTimed

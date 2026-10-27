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

/-- Take-retry scenarios: events and, per push, the on-dark reading at frames 0, 1, ...; missing frames read light. -/
def takeScenarios : List (String × List Ev × List (List Bool)) :=
  [("dark-at-start", [⟨0, 1⟩], [[true]]), ("light-then-dark-3", [⟨0, 1⟩], [[false, false, false, true]]),
    ("never-dark", [⟨0, 1⟩], [[]]), ("close-from-rest", [⟨0, 1⟩, ⟨1020, 0⟩], [[], [false, false, true]]),
    ("close-after-open", [⟨0, 1⟩, ⟨1020, 0⟩], [[true], []]),
    ("reversal-while-pending", [⟨0, 1⟩, ⟨340, 0⟩], [[], [false, true]]),
    ("reversal-after-take", [⟨0, 1⟩, ⟨340, 0⟩], [[false, false, true], [false]])]

def tickMs : Nat := 17

/-- Frames of push `i`: those before the next event, at most 40 (17 ms ticks inside the 680 ms tween). -/
def frameCount (evs : List Ev) (i : Nat) : Nat :=
  let e := (evs.getD i ⟨0, 0⟩).e
  let gap : Rat := match evs[i + 1]? with | some n => n.e - e | none => 680
  min 40 (((min gap 680).ceil).toNat / tickMs + 1)

/-- The value a reversal starts from: the event-time ideal where the push before it is on the timed tracks; where it
ran the faithful tween, the value of its last tick strictly before the event (a tick every `tickMs`, none at frame 0). -/
def startValue (s : St) (e : Rat) (timed : Bool) : Rat :=
  let el := e - s.start
  if timed || 680 < el then idealM s e
  else idealM s (s.start + ((((el.ceil).toNat - 1) / tickMs * tickMs : Nat) : Rat))

/-- Per push: taken frame (or none) and the ideal value at that frame; `anims` carries over after a take. -/
def takeRows (evs : List Ev) (darks : List (List Bool)) : List (Option Nat × Rat) :=
  let go := fun (acc : Bool × Bool × St × List (Option Nat × Rat)) (i : Nat) =>
    let ev := evs.getD i ⟨0, 0⟩
    let s := push { acc.2.2.1 with value := startValue acc.2.2.1 ev.e acc.2.1 } ev.g false ev.e
    let d := darks.getD i []
    let r := takeFrame s.f s.t acc.1 (fun k => d.getD k false) (frameCount evs i)
    let m := match r with | some k => idealM s (ev.e + (k * tickMs : Nat)) | none => 0
    (acc.1 || r.isSome, r.isSome, s, acc.2.2.2 ++ [(r, m)])
  ((List.range evs.length).foldl go (false, false, MorphTween.rest, [])).2.2.2

def takeLines (_ : Unit) : List String :=
  takeScenarios.map fun (n, evs, darks) =>
    let rows := takeRows evs darks
    gline "take" [("name", .str n), ("events", jl (evs.map fun ev => Json.mkObj [("e", jdec 6 ev.e), ("g", jdec 0 ev.g)])),
      ("darks", jl (darks.map fun d => jl (d.map fun b => Json.bool b)))]
      (Json.mkObj [("taken", jl (rows.map fun r => match r.1 with | some k => .num ⟨k, 0⟩ | none => .null)),
        ("m", jl (rows.map fun r => jdec 6 r.2))])

def goldenText (_ : Unit) : String := String.join ((scenarioLines () ++ rebaseLines () ++ crossLines () ++ takeLines ()).map (· ++ "\n"))

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
#guard (takeRows [⟨0, 1⟩] [[false, false, false, true]]).map (·.1) == [some 3]
#guard (takeRows [⟨0, 1⟩, ⟨1020, 0⟩] [[], [false, false, true]]).map (·.1) == [none, some 2]
#guard (takeRows [⟨0, 1⟩, ⟨1020, 0⟩] [[true], []]).map (·.1) == [some 0, some 0]

end Fw.Parts.MorphGeomTimed

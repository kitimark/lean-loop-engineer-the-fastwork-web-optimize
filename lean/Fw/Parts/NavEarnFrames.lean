import Lean.Data.Json
import Fw.Parts.NavEarnWebkit
/-!
Verdict of the recorded earn-button frame cells against `NavEarnWebkit.frameOk`.
Record: `cd lean && lake env lean --run scripts/NavEarnFramesGolden.lean record <run> <leg>=<summary.json>... > <golden>`.
-/
namespace Fw.Parts.NavEarnFrames
open Lean Fw.Parts.NavEarnWebkit

structure Cell where
  run : Nat
  leg : String
  width : Nat
  scenario : String
  arm : String
  frames : Nat
  worst : Nat
  settled : Nat
  deriving DecidableEq, Repr

def Cell.ok (c : Cell) : Bool := frameOk c.width c.worst

theorem frameOk_max_iff (w m : Nat) (cs : List Nat) (hm : m ∈ cs) (hle : ∀ c ∈ cs, c ≤ m) :
    frameOk w m = true ↔ ∀ c ∈ cs, frameOk w c = true :=
  ⟨fun h c hc => frameOk_mono w c m (hle c hc) h, fun h => h m hm⟩

theorem cell_snap_fails (c : Cell) (hw : c.width = 1280) (h : 300 ≤ c.worst) : c.ok = false := by
  simp only [Cell.ok, frameOk, hw, frameAllowed_wide, decide_eq_false_iff_not]
  omega

def cellJson (c : Cell) : Json :=
  Json.mkObj [("fn", "frameCell"), ("in", Json.mkObj [("run", c.run), ("leg", c.leg), ("width", c.width),
    ("scenario", c.scenario), ("arm", c.arm)]),
    ("out", Json.mkObj [("frames", c.frames), ("worst", c.worst), ("settled", c.settled),
      ("allowed", frameAllowed c.width), ("ok", c.ok)])]

def parseCell (j : Json) : Except String Cell := do
  let i ← j.getObjVal? "in"
  let o ← j.getObjVal? "out"
  return { run := ← i.getObjValAs? Nat "run", leg := ← i.getObjValAs? String "leg", width := ← i.getObjValAs? Nat "width",
           scenario := ← i.getObjValAs? String "scenario", arm := ← i.getObjValAs? String "arm",
           frames := ← o.getObjValAs? Nat "frames", worst := ← o.getObjValAs? Nat "worst",
           settled := ← o.getObjValAs? Nat "settled" }

def cellsOfSummary (run : Nat) (leg : String) (j : Json) : Except String (List Cell) := do
  let m ← (← j.getObjVal? "chromiumVsWebkit").getObj?
  m.toList.mapM fun (k, v) => do
    match k.splitOn "/" with
    | [w, scenario, arm] =>
      let some width := w.toNat? | throw s!"bad width in {k}"
      return { run, leg, width, scenario, arm, frames := ← v.getObjValAs? Nat "frames",
               worst := ← v.getObjValAs? Nat "maxChanged", settled := ← v.getObjValAs? Nat "settledChanged" }
    | _ => throw s!"bad cell key {k}"

def goldenText (cs : List Cell) : String := String.join (cs.map fun c => (cellJson c).compress ++ "\n")

def readCells (text : String) : Except String (List Cell) :=
  (text.splitOn "\n").filter (· ≠ "") |>.mapM fun l => do parseCell (← Json.parse l)

def record (run : Nat) (legs : List (String × Json)) : Except String (List Cell) := do
  let cs ← legs.mapM fun (leg, j) => cellsOfSummary run leg j
  return (cs.flatten.toArray.qsort fun a b => s!"{a.leg}/{a.width}/{a.scenario}/{a.arm}" < s!"{b.leg}/{b.width}/{b.scenario}/{b.arm}").toList

def gen (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    let text ← IO.FS.readFile path
    match readCells text with
    | .error e => IO.eprintln s!"nav.earn.frames golden: {path}: {e}"; return 1
    | .ok cs =>
      if goldenText cs == text then
        IO.eprintln s!"nav.earn.frames golden: {path} agrees with Lean frameOk ({cs.length} cells)"
        return 0
      IO.eprintln s!"nav.earn.frames golden: {path} differs from the Lean verdicts"
      return 1
  | "record" :: run :: legs =>
    let some r := run.toNat? | IO.eprintln "run id is not a number"; return 2
    let mut ls : List (String × Json) := []
    for a in legs do
      match a.splitOn "=" with
      | [leg, p] => ls := ls ++ [(leg, ← IO.ofExcept ((Json.parse (← IO.FS.readFile p)).mapError fun e => s!"{p}: {e}"))]
      | _ => IO.eprintln s!"bad leg argument {a}"; return 2
    match record r ls with
    | .error e => IO.eprintln e; return 1
    | .ok cs => IO.print (goldenText cs); return 0
  | _ => IO.eprintln "usage: record <run> <leg>=<summary.json>... | --check <golden>"; return 2

end Fw.Parts.NavEarnFrames

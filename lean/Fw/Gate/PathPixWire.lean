import Lean.Data.Json
import Fw.Gate.PathPix
import Fw.Measure.Wire
/-!
# The op `gate.pathpixDrawBase`
JSON glue for `drawBase` and `aboveBase`: `lanes` in, one `{base, above}` per lane out (both `null` when unpinned).
-/
namespace Fw.Wire.PathPix
open Lean Fw.Wire.Measure Fw.Gate.PathPix

def laneJson (xs : List Nat) : Json :=
  Json.mkObj [("base", match drawBase xs with | some b => toJson b | none => .null),
              ("above", match aboveBase xs with | some a => toJson a | none => .null)]

def opDrawBase (req : Json) : Except String Reply := do
  let ls ← (← arr req "lanes").toList.mapM fun l => do (← asArr "lanes" l).toList.mapM (asNat "lanes")
  pure [("lanes", .arr (ls.toArray.map laneJson))]

def ops : List String := ["gate.pathpixDrawBase"]

def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "gate.pathpixDrawBase" => some (opDrawBase req)
  | _ => none

theorem laneJson_pinned (xs : List Nat) (b : Nat) (h : drawBase xs = some b) :
    laneJson xs = Json.mkObj [("base", toJson b), ("above", toJson (xs.map (· - b)))] := by
  simp [laneJson, aboveBase, h]

theorem laneJson_unpinned (xs : List Nat) (h : drawBase xs = none) :
    laneJson xs = Json.mkObj [("base", .null), ("above", .null)] := by
  simp [laneJson, aboveBase, h]

end Fw.Wire.PathPix

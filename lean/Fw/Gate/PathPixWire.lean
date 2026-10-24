import Lean.Data.Json
import Fw.Gate.PathPix
import Fw.Measure.Wire
/-!
# The op `gate.pathpixDrawBase` (task pathpix-drawbase-wire)

JSON glue for `Fw.Gate.PathPix.drawBase` and `aboveBase` (namespace `Fw.Wire.PathPix`, so the math view treats it as
wire code). It decides nothing: each lane goes to the Lean functions and the reply carries what they return.

| op | request | reply |
|---|---|---|
| `gate.pathpixDrawBase` | `lanes`: a list of outside-band lanes, each a list of changed-pixel counts (out phase, then in phase) | `lanes`: one `{base, above}` per lane, in order; both are `null` when `drawBase` does not pin the lane, else `base` is the baseline count and `above` the per-frame counts above it |
-/
namespace Fw.Wire.PathPix
open Lean Fw.Wire.Measure Fw.Gate.PathPix

/-- The reply entry of one lane. -/
def laneJson (xs : List Nat) : Json :=
  Json.mkObj [("base", match drawBase xs with | some b => toJson b | none => .null),
              ("above", match aboveBase xs with | some a => toJson a | none => .null)]

/-- `gate.pathpixDrawBase`: see the table above. -/
def opDrawBase (req : Json) : Except String Reply := do
  let ls ← (← arr req "lanes").toList.mapM fun l => do (← asArr "lanes" l).toList.mapM (asNat "lanes")
  pure [("lanes", .arr (ls.toArray.map laneJson))]

/-- The ops of this module. -/
def ops : List String := ["gate.pathpixDrawBase"]

/-- Dispatch a `gate.pathpixDrawBase` request (`none` when the op is not this one). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "gate.pathpixDrawBase" => some (opDrawBase req)
  | _ => none

/-- A pinned lane replies with its baseline and the counts above it. -/
theorem laneJson_pinned (xs : List Nat) (b : Nat) (h : drawBase xs = some b) :
    laneJson xs = Json.mkObj [("base", toJson b), ("above", toJson (xs.map (· - b)))] := by
  simp [laneJson, aboveBase, h]

/-- An unpinned lane replies with two nulls. -/
theorem laneJson_unpinned (xs : List Nat) (h : drawBase xs = none) :
    laneJson xs = Json.mkObj [("base", .null), ("above", .null)] := by
  simp [laneJson, aboveBase, h]

end Fw.Wire.PathPix

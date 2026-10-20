import Fw.Ops.Wire
import Fw.Ops.LeanFirstSearch

/-!
# The `ops.leanFirst` wire codec round-trips every grid point

Task `lfg-spec`. `lfFactsJson` then `lfFactsOf` (through the compact JSON text, as `fwcore` reads it) is the identity
on every point of the fault grid of `Fw.Ops.LeanFirstSearch`. On every single-fault point the op's `kind`, `exit` and
`lines` equal `out` at the deployed constant `stage`, and a request `stage` field of any stage name leaves the whole
reply unchanged. These are `#guard` checks over finite lists, not theorems.
-/
namespace FwTest.Mutants.LeanFirst

open Lean Fw.Wire.Ops Fw.Ops.LeanFirst

/-- Encode, print, parse and decode lean-first facts (`none` when a step fails). -/
def roundTrip (F : Facts) : Option Facts :=
  match Json.parse (lfFactsJson F).compress with
  | .ok j => (lfFactsOf j).toOption
  | .error _ => none

#guard grid.all fun F => roundTrip F == some F

/-- The encoded facts with a `stage` field of name `n` added (the field the op ignores). -/
def withStage (n : String) (F : Facts) : Json :=
  match lfFactsJson F with
  | .obj kvs => .obj (kvs.insert "stage" (.str n))
  | j => j

/-- The `kind`, `exit` and `lines` of the `ops.leanFirst` reply. -/
def wireOut (F : Facts) : Option (Json × Json × Json) :=
  match opLeanFirst (lfFactsJson F) with
  | .ok r => do pure (← r.lookup "kind", ← r.lookup "exit", ← r.lookup "lines")
  | .error _ => none

#guard (Fault.all.map fun f => factsOf [f]).all fun F =>
  wireOut F == some (.str (out stage F).kind.name, toJson (out stage F).exit, strsJson (out stage F).lines)

#guard (Fault.all.map fun f => factsOf [f]).all fun F =>
  ["shadow", "newTasks", "allNew", "ratchet", "strict"].all fun n =>
    (opLeanFirst (withStage n F)).toOption == (opLeanFirst (lfFactsJson F)).toOption

end FwTest.Mutants.LeanFirst

import Fw.Ops.Wire
import Fw.Ops.LeanFirstSearch

/-!
# The `ops.leanFirst` wire codec round-trips every grid point

Task `lfg-spec`. `lfFactsJson` then `lfFactsOf` (through the compact JSON text, as `fwcore` reads it) is the identity
on every point of the fault grid of `Fw.Ops.LeanFirstSearch`, and the op's reply matches `out` and `gate` there.
-/
namespace FwTest.Mutants.LeanFirst

open Lean Fw.Wire.Ops Fw.Ops.LeanFirst

/-- Encode, print, parse and decode lean-first facts (`none` when a step fails). -/
def roundTrip (F : Facts) : Option Facts :=
  match Json.parse (lfFactsJson F).compress with
  | .ok j => (lfFactsOf j).toOption
  | .error _ => none

#guard grid.all fun F => roundTrip F == some F

/-- The `kind`, `exit` and `lines` of the `ops.leanFirst` reply at a stage. -/
def wireOut (s : Stage) (F : Facts) : Option (Json × Json × Json) :=
  match opLeanFirst (match lfFactsJson F with
      | .obj kvs => .obj (kvs.insert "stage" (.str s.name))
      | j => j) with
  | .ok r => do pure (← r.lookup "kind", ← r.lookup "exit", ← r.lookup "lines")
  | .error _ => none

#guard [Stage.shadow, .newTasks, .allNew, .ratchet].all fun s => (Fault.all.map fun f => factsOf [f]).all fun F =>
  wireOut s F == some (.str (out s F).kind.name, toJson (out s F).exit, strsJson (out s F).lines)

end FwTest.Mutants.LeanFirst

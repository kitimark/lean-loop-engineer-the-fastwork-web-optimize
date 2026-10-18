import Fw.Ops.Premise

/-- The engine golden citation lint (m175 hardening): every row of `packages/contracts/golden/engine/**` cites a
measured or untested premise (`Fw.Ops.Premise.citeLint`, `engineCite_ok_iff`); prints the untested warning list.
Run from `lean/`: `lake env lean --run scripts/EngineCiteLint.lean`. -/
def main (_ : List String) : IO UInt32 := do
  let bad ← Fw.Ops.Premise.citeRun "."
  return if bad == 0 then 0 else 1

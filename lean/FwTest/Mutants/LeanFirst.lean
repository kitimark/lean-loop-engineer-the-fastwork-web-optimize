import FwTest.Mutants.LeanFirst.Gate
import FwTest.Mutants.LeanFirst.Out
import FwTest.Mutants.LeanFirst.Parts
import FwTest.Mutants.LeanFirst.Wire

/-! # Tier-K kills of every lean-first gate property (task `lfg-spec`)

One mutant and one in-kernel kill theorem `<P>_rejects_<mutant> : ¬ P mutant` per property of
`Fw.Ops.LeanFirstProps`: gate mutants in `Gate`, renderer mutants in `Out`, `discharges`/`isNew` mutants in `Parts`; the `ops.leanFirst` codec round trip in `Wire`. -/

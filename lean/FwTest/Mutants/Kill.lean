import FwTest.Mutants.Console
import FwTest.Mutants.DeviceQueue
import FwTest.Mutants.Meter
import FwTest.Mutants.Serve
import FwTest.Mutants.PathCheck
import FwTest.Mutants.SpawnGuard
import FwTest.Mutants.Usage
import FwTest.Mutants.OpsWire
import FwTest.Mutants.Wire
/-! # Mutant killers (task m0-mutants)

Root of the theorems and golden cases added because a mechanical mutant of an M0 module survived
`lake build` + `lake test` (see `scripts/mutants.sh`, `research/notes/2026/10-17-mutants.md`).
Each imported file names the mutants it kills. -/

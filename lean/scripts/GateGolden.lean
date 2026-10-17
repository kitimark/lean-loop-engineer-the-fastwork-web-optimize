import Fw.Wire.GateGolden

/-- Write (or with `--check`, verify) `packages/contracts/golden/gate/{gate,literal}.jsonl` from `cases.json`. Run
from `lean/`: `lake env lean --run scripts/GateGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  let bad ← Fw.Wire.Gate.Golden.run "." (!args.contains "--check")
  return if bad == 0 then 0 else 1

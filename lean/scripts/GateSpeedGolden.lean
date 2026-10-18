import Fw.Wire.GateSpeedGolden

/-- Write (or with `--check`, verify) `packages/contracts/golden/gate/schedule.jsonl` and
`packages/contracts/golden/ops/cache.jsonl`. Run from `lean/`:
`lake env lean --run scripts/GateSpeedGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  let stale ← Fw.Wire.GateSpeed.Golden.run "." (!args.contains "--check")
  return if stale == 0 then 0 else 1

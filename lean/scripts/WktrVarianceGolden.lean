import Fw.Wire.WktrVarianceGolden

/-- Write (or with `--check`, verify) `packages/contracts/golden/measure/wktr.variance.jsonl`. Run from `lean/`:
`lake env lean --run scripts/WktrVarianceGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  let stale ← Fw.Wire.WktrVariance.Golden.run "." (!args.contains "--check")
  return if stale == 0 then 0 else 1

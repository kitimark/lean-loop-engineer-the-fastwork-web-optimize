import Fw.Measure.Golden

/-- Write (or with `--check`, verify) `packages/contracts/golden/measure/*.jsonl`. Run from `lean/`:
`lake env lean --run scripts/MeasureGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  let stale ← Fw.Wire.Measure.Golden.run "." (!args.contains "--check")
  return if stale == 0 then 0 else 1

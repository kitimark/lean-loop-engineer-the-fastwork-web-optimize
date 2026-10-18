import Fw.Wire.WktrFixturesGolden

/-- Write (or with `--check`, verify) `packages/contracts/golden/measure/wktr.fixtures.jsonl`. Run from `lean/`:
`lake env lean --run scripts/WktrFixturesGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  let stale ← Fw.Wire.WktrFixtures.Golden.run "." (!args.contains "--check")
  return if stale == 0 then 0 else 1

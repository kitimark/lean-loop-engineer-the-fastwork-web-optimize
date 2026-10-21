import Fw.Measure.WkCost

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/measure/wkcost.jsonl`. Run from `lean/`:
`lake env lean --run scripts/WkCostGolden.lean [--check ../packages/contracts/golden/measure/wkcost.jsonl]`. -/
def main (args : List String) : IO UInt32 := Fw.Measure.WkCost.run args

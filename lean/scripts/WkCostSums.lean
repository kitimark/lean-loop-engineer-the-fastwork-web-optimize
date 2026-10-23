import Fw.Measure.WkCost

/-- Verify `packages/contracts/golden/measure/wkcost-sums.jsonl` (written by `morph-verdict --sums`) against the run literals
in `Fw.Measure.WkCost`. Run from `lean/`: `lake env lean --run scripts/WkCostSums.lean --check ../packages/contracts/golden/measure/wkcost-sums.jsonl`. -/
def main (args : List String) : IO UInt32 := Fw.Measure.WkCost.runSums args

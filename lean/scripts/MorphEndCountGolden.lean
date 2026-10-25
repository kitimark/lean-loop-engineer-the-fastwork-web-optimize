import Fw.Measure.MorphEndCount

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/device/morph-end-count.jsonl`. Run from `lean/`:
`lake env lean --run scripts/MorphEndCountGolden.lean [--check ../packages/contracts/golden/device/morph-end-count.jsonl]`. -/
def main (args : List String) : IO UInt32 := Fw.Measure.MorphEndCount.run args

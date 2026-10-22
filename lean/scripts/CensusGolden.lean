import Fw.Measure.Census

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/measure/census.jsonl`. Run from `lean/`:
`lake env lean --run scripts/CensusGolden.lean [--check ../packages/contracts/golden/measure/census.jsonl]`. -/
def main (args : List String) : IO UInt32 := Fw.Measure.Census.run args

import Fw.Measure.Profile

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/measure/profile.jsonl`. Run from `lean/`:
`lake env lean --run scripts/ProfileGolden.lean [--check ../packages/contracts/golden/measure/profile.jsonl]`. -/
def main (args : List String) : IO UInt32 := Fw.Measure.Profile.run args

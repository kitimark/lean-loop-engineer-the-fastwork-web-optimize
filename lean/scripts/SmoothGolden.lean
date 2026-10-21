import Fw.Gate.Smooth

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/gate/smooth.jsonl`. Run from `lean/`:
`lake env lean --run scripts/SmoothGolden.lean [--check ../packages/contracts/golden/gate/smooth.jsonl]`. -/
def main (args : List String) : IO UInt32 := Fw.Gate.Smooth.run args

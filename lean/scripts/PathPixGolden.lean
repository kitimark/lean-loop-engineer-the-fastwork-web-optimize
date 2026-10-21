import Fw.Gate.PathPix

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/gate/path-pix.jsonl`. Run from `lean/`:
`lake env lean --run scripts/PathPixGolden.lean [--check ../packages/contracts/golden/gate/path-pix.jsonl]`. -/
def main (args : List String) : IO UInt32 := Fw.Gate.PathPix.run args

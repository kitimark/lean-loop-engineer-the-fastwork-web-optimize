import Fw.Gate.Colour

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/gate/trajectory-colour.jsonl`. Run from `lean/`:
`lake env lean --run scripts/ColourGolden.lean [--check ../packages/contracts/golden/gate/trajectory-colour.jsonl]`. -/
def main (args : List String) : IO UInt32 := Fw.Gate.Colour.run args

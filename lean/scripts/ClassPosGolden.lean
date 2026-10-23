import Fw.Parts.ClassPos

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/parts/footprint.classpos.jsonl`. Run from
`lean/`: `lake env lean --run scripts/ClassPosGolden.lean [--check <file>]`. -/
def main (args : List String) : IO UInt32 := Fw.Parts.ClassPos.run args

import Fw.Parts.MorphEndGolden

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/parts/morph.end.jsonl`. -/
def main (args : List String) : IO UInt32 := Fw.Parts.MorphEndGolden.runGolden args

import Fw.Parts.MorphMountOpt

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/parts/morph-mount-tap.jsonl`. -/
def main (args : List String) : IO UInt32 := Fw.Parts.MorphMountOpt.tapMain args

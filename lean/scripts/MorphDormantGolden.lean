import Fw.Parts.MorphMountDormant

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/parts/morph.mount.dormant.jsonl`. -/
def main (args : List String) : IO UInt32 := Fw.Parts.MorphMountDormant.run args

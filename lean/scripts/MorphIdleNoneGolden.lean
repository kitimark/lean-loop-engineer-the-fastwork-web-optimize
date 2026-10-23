import Fw.Parts.MorphIdleNone

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/parts/morph-idle-none.jsonl`. -/
def main (args : List String) : IO UInt32 := Fw.Parts.MorphIdleNone.gen args

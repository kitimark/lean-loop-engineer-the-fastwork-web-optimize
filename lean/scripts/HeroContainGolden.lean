import Fw.Parts.HeroContainOpt

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/parts/hero-contain.jsonl`. -/
def main (args : List String) : IO UInt32 := Fw.Parts.HeroContainOpt.run args

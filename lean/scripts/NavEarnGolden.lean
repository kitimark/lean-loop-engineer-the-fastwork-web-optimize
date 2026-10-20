import Fw.Parts.NavEarnOpt

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/parts/nav-earn.jsonl`. -/
def main (args : List String) : IO UInt32 := Fw.Parts.NavEarnOpt.gen args

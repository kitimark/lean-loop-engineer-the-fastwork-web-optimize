import Fw.Parts.HeroExitOpt

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/parts/hero-exit.threaded.jsonl`. -/
def main (args : List String) : IO UInt32 := Fw.Parts.HeroExitOpt.runThreaded args

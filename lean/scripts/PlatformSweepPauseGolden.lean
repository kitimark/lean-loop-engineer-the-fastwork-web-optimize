import Fw.Parts.PlatformSweepPauseGolden

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/parts/platform-sweep-pause.jsonl`. -/
def main (args : List String) : IO UInt32 := Fw.Parts.PlatformSweepPauseGolden.run' args

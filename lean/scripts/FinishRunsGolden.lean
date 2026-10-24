import Fw.Device.FinishRuns

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/device/finishruns.jsonl`. Run from `lean/`:
`lake env lean --run scripts/FinishRunsGolden.lean [--check ../packages/contracts/golden/device/finishruns.jsonl]`. -/
def main (args : List String) : IO UInt32 := Fw.Device.FinishRuns.run args

import Fw.Device.StillRuns

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/device/stillruns.jsonl`. Run from `lean/`:
`lake env lean --run scripts/StillRunsGolden.lean [--check ../packages/contracts/golden/device/stillruns.jsonl]`. -/
def main (args : List String) : IO UInt32 := Fw.Device.StillRuns.run args

import Fw.Device.ReplayGolden

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/device/replay.jsonl`. Run from `lean/`:
`lake env lean --run scripts/DeviceReplayGolden.lean [--check ../packages/contracts/golden/device/replay.jsonl]`. -/
def main (args : List String) : IO UInt32 := Fw.Device.Replay.run args

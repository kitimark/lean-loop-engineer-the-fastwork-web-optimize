import Fw.Device.Stats

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/device/session.jsonl`. Run from `lean/`:
`lake env lean --run scripts/DeviceSessionGolden.lean [--check ../packages/contracts/golden/device/session.jsonl]`. -/
def main (args : List String) : IO UInt32 := Fw.Device.Stats.run args

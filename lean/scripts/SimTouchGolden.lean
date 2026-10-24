import Fw.Device.SimTouch

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/device/sim-touch.jsonl`. Run from `lean/`:
`lake env lean --run scripts/SimTouchGolden.lean [--check ../packages/contracts/golden/device/sim-touch.jsonl]`. -/
def main (args : List String) : IO UInt32 := Fw.Device.SimTouch.run args

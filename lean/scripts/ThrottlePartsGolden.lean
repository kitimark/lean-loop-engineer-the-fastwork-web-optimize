import Fw.Device.ThrottleParts

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/device/throttle-parts.jsonl`. Run from `lean/`:
`lake env lean --run scripts/ThrottlePartsGolden.lean [--check ../packages/contracts/golden/device/throttle-parts.jsonl]`. -/
def main (args : List String) : IO UInt32 := Fw.Device.ThrottleParts.run args

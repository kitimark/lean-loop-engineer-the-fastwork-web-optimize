import Fw.Device.PhoneArms

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/device/phone-arms.jsonl`. Run from `lean/`:
`lake env lean --run scripts/PhoneArmsGolden.lean [--check ../packages/contracts/golden/device/phone-arms.jsonl]`. -/
def main (args : List String) : IO UInt32 := Fw.Device.PhoneArms.run args

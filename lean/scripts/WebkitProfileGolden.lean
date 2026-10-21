import Fw.Measure.WebKitProfile

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/measure/webkit-profile.jsonl`. Run from `lean/`:
`lake env lean --run scripts/WebkitProfileGolden.lean [--check ../packages/contracts/golden/measure/webkit-profile.jsonl]`. -/
def main (args : List String) : IO UInt32 := Fw.Measure.WebKitProfile.run args

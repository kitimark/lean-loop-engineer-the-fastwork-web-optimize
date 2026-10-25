import Fw.Gate.FlagDelta

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/gate/flag-delta.jsonl`. Run from `lean/`:
`lake env lean --run scripts/GateFlagDeltaGolden.lean [--check ../packages/contracts/golden/gate/flag-delta.jsonl]`. -/
def main (args : List String) : IO UInt32 := Fw.Gate.FlagDelta.run args

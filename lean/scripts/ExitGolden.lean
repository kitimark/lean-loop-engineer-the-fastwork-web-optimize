import Fw.Gate.Exit

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/gate/exit.jsonl`. Run from `lean/`:
`lake env lean --run scripts/ExitGolden.lean [--check ../packages/contracts/golden/gate/exit.jsonl]`. -/
def main (args : List String) : IO UInt32 := Fw.Gate.Exit.run args

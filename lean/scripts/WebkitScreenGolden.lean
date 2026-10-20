import Fw.Gate.WebkitScreen

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/gate/webkit-screen.jsonl`. Run from `lean/`:
`lake env lean --run scripts/WebkitScreenGolden.lean [--check ../packages/contracts/golden/gate/webkit-screen.jsonl]`. -/
def main (args : List String) : IO UInt32 := Fw.Gate.WebkitScreen.run args

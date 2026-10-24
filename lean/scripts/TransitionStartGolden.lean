import Fw.Engine.TransitionStart

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/engine/transition-start.jsonl`. Run from `lean/`:
`lake env lean --run scripts/TransitionStartGolden.lean [--check ../packages/contracts/golden/engine/transition-start.jsonl]`. -/
def main (args : List String) : IO UInt32 := Fw.Engine.TransitionStart.run args

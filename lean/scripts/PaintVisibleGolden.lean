import Fw.Engine.PaintVisible

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/engine/paint-visible.jsonl`. -/
def main (args : List String) : IO UInt32 := Fw.Engine.PaintVisible.run args

import Fw.Measure.TouchPush

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/measure/touch-push.jsonl`. Run from `lean/`:
`lake env lean --run scripts/TouchPushGolden.lean [--check ../packages/contracts/golden/measure/touch-push.jsonl]`. -/
def main (args : List String) : IO UInt32 := Fw.Measure.TouchPush.run args

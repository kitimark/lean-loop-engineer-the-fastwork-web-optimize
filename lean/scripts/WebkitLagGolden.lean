import Fw.Measure.WebKitLag

/-- Print, or with `--check <file>` verify, `packages/contracts/golden/measure/webkit-lag.jsonl`. Run from `lean/`:
`lake env lean --run scripts/WebkitLagGolden.lean [--check ../packages/contracts/golden/measure/webkit-lag.jsonl]`. -/
def main (args : List String) : IO UInt32 := Fw.Measure.WebKitLag.run args

import Fw.Ops.Golden

/-- Write (or with `--check`, verify) `packages/contracts/golden/ops/*.jsonl`. Run from `lean/`:
`lake env lean --run scripts/OpsGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  let stale ← Fw.Wire.Ops.Golden.run "." (!args.contains "--check")
  return if stale == 0 then 0 else 1

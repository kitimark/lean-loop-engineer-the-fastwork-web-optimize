import Fw.Store.Golden

/-- Write (or with `--check`, verify) `packages/contracts/golden/store/*.jsonl`. Run from `lean/`:
`lake env lean --run scripts/StoreGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  let stale ← Fw.Wire.Store.Golden.run' "." (!args.contains "--check")
  return if stale == 0 then 0 else 1

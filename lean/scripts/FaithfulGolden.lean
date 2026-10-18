import Fw.Faithful.Golden

/-- Write (or with `--check`, verify) `packages/contracts/golden/faithful/faithful.verdict.jsonl`. Run from `lean/`:
`lake env lean --run scripts/FaithfulGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  let stale ← Fw.Wire.Faithful.Golden.run "." (!args.contains "--check")
  return if stale == 0 then 0 else 1

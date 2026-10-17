import Fw.Ops.Premise

/-- Write (or with `--check`, verify) `packages/contracts/golden/ops/premise.jsonl`. Run from `lean/`:
`lake env lean --run scripts/PremiseGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  let bad ← Fw.Ops.Premise.run "." (!args.contains "--check")
  return if bad == 0 then 0 else 1

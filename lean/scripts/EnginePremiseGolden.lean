import Fw.Ops.EnginePremise

/-- Write (or with `--check`, verify) `packages/contracts/golden/ops/engine-premises.jsonl`. Run from `lean/`:
`lake env lean --run scripts/EnginePremiseGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  let n ← Fw.Ops.EnginePremise.goldenRun "." (!args.contains "--check")
  return if n == 0 then 0 else 1

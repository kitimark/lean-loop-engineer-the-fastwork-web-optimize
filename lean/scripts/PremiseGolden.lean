import Fw.Ops.Premise

/-- Write (or with `--check`, verify) `packages/contracts/golden/ops/premise.jsonl` and
`packages/contracts/golden/ops/wktr-lane.jsonl`. Run from `lean/`:
`lake env lean --run scripts/PremiseGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  let write := !args.contains "--check"
  let a ← Fw.Ops.Premise.run "." write
  let b ← Fw.Ops.Premise.laneRun "." write
  return if a + b == 0 then 0 else 1

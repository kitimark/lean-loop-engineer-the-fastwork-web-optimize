import Fw.Wire.SchedGolden

/-- Write (or with `--check`, verify) `packages/contracts/golden/ops/{admit,metrics}.jsonl`. Run from `lean/`:
`lake env lean --run scripts/SchedGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  let stale ← Fw.Wire.Sched.Golden.run "." (!args.contains "--check")
  return if stale == 0 then 0 else 1

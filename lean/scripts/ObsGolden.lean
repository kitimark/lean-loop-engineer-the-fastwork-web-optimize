import Fw.Obs.Golden

/-- Write (or with `--check`, verify) `packages/contracts/golden/obs/health.jsonl`. Run from `lean/`:
`lake env lean --run scripts/ObsGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  let bad ← Fw.Wire.Obs.Golden.run "." (!args.contains "--check")
  return if bad == 0 then 0 else 1

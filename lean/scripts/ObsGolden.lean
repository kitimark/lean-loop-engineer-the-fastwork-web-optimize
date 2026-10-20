import Fw.Obs.Golden
import Fw.Obs.CiStatus

/-- Write (or with `--check`, verify) `packages/contracts/golden/obs/health.jsonl`. Run from `lean/`:
`lake env lean --run scripts/ObsGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  let bad ← Fw.Wire.Obs.Golden.run "." (!args.contains "--check")
  let bad2 ← Fw.Obs.CiStatus.run "." (!args.contains "--check")  -- circleci-status
  return if bad + bad2 == 0 then 0 else 1

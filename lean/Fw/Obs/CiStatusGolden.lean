import Fw.Obs.CiStatus

/-- Write (or with `--check`, verify) `packages/contracts/golden/obs/ci-status.jsonl` from `Fw.Obs.CiStatus.goldenText`.
Run from `lean/`: `lake env lean --run Fw/Obs/CiStatusGolden.lean [--check]`. -/
def main (args : List String) : IO UInt32 := do
  let bad ← Fw.Obs.CiStatus.run "." (!args.contains "--check")
  return if bad == 0 then 0 else 1
